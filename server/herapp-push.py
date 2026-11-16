#!/usr/bin/env python3
"""Sends a push to Herapp (FCM topic) when a Hermes cron job finishes: its answer, or why it failed.

Polls ~/.hermes/cron/jobs.json. Silent answers are skipped, and so are the successes of script-only jobs
(no_agent), except those listed in ~/.config/herapp-push/notify.json ({"jobs": ["<job id>", ...]}): their
output, when not empty, is pushed as is. No model is involved anywhere.
notify.json may also hold {"stale": {"<job id>": <minutes>}}: a listed job that has not run for that long, or is
paused, is reported once, and again when it runs anew. This service runs apart from Hermes, so it tells even when
Hermes' scheduler itself stopped.
Every notice is also kept in ~/.hermes/herapp/notifications.json (newest first), the app's Notifications page.
The FCM topic is drawn at random once and kept in ~/.hermes/herapp/push.json: the app reads it through Hermes, so only
those who can sign in to this server get its pushes, not everyone who installs Herapp.
Needs ~/.config/herapp-push/service-account.json (Firebase service account key) and openssl.
"""
import base64, json, os, secrets, subprocess, sys, tempfile, time, urllib.request
from datetime import datetime
from pathlib import Path

HOME = Path.home()
JOBS = HOME / '.hermes/cron/jobs.json'
OUTPUT = HOME / '.hermes/cron/output'
KEY = HOME / '.config/herapp-push/service-account.json'
NOTIFY = HOME / '.config/herapp-push/notify.json'
FEED = HOME / '.hermes/herapp/notifications.json'
FEED_SIZE = 300
TEXT_LIMIT = 4000
TOPIC_FILE = HOME / '.hermes/herapp/push.json'
SILENT = {'[SILENT]', 'SILENT', 'NO_REPLY', 'NO REPLY'}
OK = {'ok', 'delivery_queued'}  # delivery_queued: the output was handed to a Bot Chat, the run itself went fine


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


_token = (None, 0)


def access_token(sa):
    global _token
    if time.time() < _token[1]:
        return _token[0]
    now = int(time.time())
    head = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claims = b64(json.dumps({'iss': sa['client_email'], 'scope': 'https://www.googleapis.com/auth/firebase.messaging',
                             'aud': sa['token_uri'], 'iat': now, 'exp': now + 3600}).encode())
    # stdlib has no RSA: openssl signs, with the key in a private temp file
    with tempfile.NamedTemporaryFile('w', suffix='.pem') as k:
        k.write(sa['private_key'])
        k.flush()
        sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', k.name], check=True, capture_output=True,
                             input=f'{head}.{claims}'.encode()).stdout
    body = f'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion={head}.{claims}.{b64(sig)}'
    with urllib.request.urlopen(urllib.request.Request(sa['token_uri'], body.encode())) as r:
        _token = (json.load(r)['access_token'], now + 3000)
    return _token[0]


def topic(path=TOPIC_FILE):
    """This server's FCM topic, drawn the first time and kept in [path] for the app to subscribe to."""
    try:
        t = json.loads(path.read_text())['topic']
        if isinstance(t, str) and t:
            return t
    except (OSError, ValueError, KeyError, TypeError):
        pass
    t = 'herapp-' + secrets.token_hex(16)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps({'topic': t}))
    os.replace(tmp, path)
    return t


def send(sa, title, body, job_id, notice_id):
    msg = {'message': {'topic': topic(), 'notification': {'title': title, 'body': body},
                       'data': {'cron': job_id, 'notice': notice_id},
                       'apns': {'payload': {'aps': {'sound': 'default'}}}}}
    req = urllib.request.Request(f"https://fcm.googleapis.com/v1/projects/{sa['project_id']}/messages:send",
                                 json.dumps(msg).encode(), {'Authorization': f'Bearer {access_token(sa)}',
                                                            'Content-Type': 'application/json'})
    urllib.request.urlopen(req).close()


def latest_output(job_id):
    runs = sorted((OUTPUT / job_id).glob('*.md'))
    return runs[-1].read_text(errors='replace') if runs else ''


def answer(doc):
    """An agent run's answer, from the output file's Response section."""
    return doc.split('## Response', 1)[1].strip() if '## Response' in doc else ''


def script_output(doc):
    """What a script-only run printed: the output file without the header Hermes writes above it."""
    if not doc.startswith('# Cron Job:'):
        return doc.strip()
    cut = doc.find('\n---\n')
    return doc[cut + 5:].strip() if cut >= 0 else ''  # a run that printed nothing has the header only


def is_silent(text):
    lines = [l.strip() for l in text.strip().splitlines() if l.strip()]
    return bool(lines) and (lines[0].upper() in SILENT or lines[-1].upper() in SILENT)


def summary(text, limit=180):
    # markdown headings and emphasis read badly in a notification
    flat = ' '.join(l.strip().lstrip('#').strip() for l in text.splitlines() if l.strip()).replace('**', '')
    return flat if len(flat) <= limit else flat[:limit - 1].rstrip() + '…'


def notice(job, doc, notify=()):
    """(title, text, failed) for a finished run, or None when it isn't worth a push."""
    name = job.get('name') or job['id']
    if job.get('last_status') not in OK:
        return f'Échec : {name}', job.get('last_error') or 'Échec du cron', True
    if job.get('no_agent'):
        text = script_output(doc) if job['id'] in notify else ''
        return (name, text, False) if text and not is_silent(text) else None
    text = answer(doc)
    if is_silent(text):
        return None
    return name, text or 'Terminé', False


def notify_ids():
    try:
        return set(json.loads(NOTIFY.read_text()).get('jobs') or [])
    except (OSError, ValueError, AttributeError):
        return set()


def stale_limits():
    """{job id: minutes} from notify.json's "stale"."""
    try:
        limits = json.loads(NOTIFY.read_text()).get('stale') or {}
        return {k: float(v) for k, v in limits.items() if isinstance(v, (int, float))}
    except (OSError, ValueError, AttributeError):
        return {}


def staleness(job, minutes, now):
    """Why [job] looks stopped, or None while it runs on time."""
    if job is None:
        return 'supprimé'
    if job.get('state') == 'paused' or job.get('enabled') is False:
        return 'en pause'
    try:
        last = datetime.fromisoformat(job['last_run_at']).timestamp()
    except (KeyError, TypeError, ValueError):
        return 'jamais exécuté'
    idle = now - last
    return f'aucune exécution depuis {int(idle // 60)} min' if idle > minutes * 60 else None


def record(entry, feed=FEED):
    """Adds [entry] at the top of the feed, written whole then renamed, so the app never reads half of it."""
    try:
        old = json.loads(feed.read_text())
    except (OSError, ValueError):
        old = []
    items = [entry] + [e for e in old if isinstance(e, dict) and e.get('id') != entry['id']][:FEED_SIZE - 1]
    feed.parent.mkdir(parents=True, exist_ok=True)
    tmp = feed.with_suffix('.tmp')
    tmp.write_text(json.dumps(items, ensure_ascii=False))
    os.replace(tmp, feed)


def runs():
    try:
        return {j['id']: j for j in json.loads(JOBS.read_text())['jobs']}
    except (OSError, ValueError, KeyError):
        return None  # mid-write: read again next time


def tell(sa, cron, title, text, failed, nid):
    record({'id': nid, 'cron': cron, 'title': title, 'text': text[:TEXT_LIMIT],
            'at': datetime.now().astimezone().isoformat(timespec='seconds'), 'failed': failed})
    send(sa, title, summary(text), cron, nid)
    print('sent', cron, title, flush=True)


def watch_stale(sa, jobs, stopped, now):
    """Reports a watched job that stopped running, once, then when it runs again; [stopped] remembers which."""
    for i, minutes in stale_limits().items():
        job, why = jobs.get(i), staleness(jobs.get(i), minutes, now)
        name = (job or {}).get('name') or i
        try:
            if why and i not in stopped:
                tell(sa, i, f'Arrêt : {name}', f'{name} ne tourne plus : {why}.', True, f'{i}:stale:{int(now)}')
                stopped.add(i)
            elif not why and i in stopped:
                tell(sa, i, name, f'{name} tourne de nouveau.', False, f'{i}:back:{int(now)}')
                stopped.discard(i)
        except Exception as e:
            print('push failed', i, e, file=sys.stderr, flush=True)


def main():
    sa = json.loads(KEY.read_text())
    print('topic', topic(), flush=True)  # drawn now, for the app to find before the first push
    seen = {i: j.get('last_run_at') for i, j in (runs() or {}).items()}
    stopped = set()
    while True:
        time.sleep(20)
        jobs = runs()
        if jobs is None:
            continue
        watch_stale(sa, jobs, stopped, time.time())
        for i, j in jobs.items():
            if j.get('last_run_at') and j['last_run_at'] != seen.get(i):
                seen[i] = j['last_run_at']
                try:
                    if n := notice(j, latest_output(i), notify_ids()):
                        title, text, failed = n
                        nid = f"{i}:{j['last_run_at']}"
                        record({'id': nid, 'cron': i, 'title': title, 'text': text[:TEXT_LIMIT], 'at': j['last_run_at'],
                                'failed': failed})
                        send(sa, title, summary(text), i, nid)
                        print('sent', i, title, flush=True)
                except Exception as e:
                    print('push failed', i, e, file=sys.stderr, flush=True)


def test():
    assert is_silent('[SILENT]') and is_silent('blah\nNO_REPLY') and not is_silent('ok')
    assert summary('# Bilan\n**Gras** texte') == 'Bilan Gras texte'
    assert summary('x' * 300).endswith('…') and len(summary('x' * 300)) == 180
    assert notice({'id': 'a', 'name': 'N', 'last_status': 'error', 'last_error': 'boom'}, '') == ('Échec : N', 'boom', True)
    doc = '# Cron Job: K\n\n**Job ID:** k\n\n---\n\n🚀 t_1 : poussé sur main.\n'
    head_only = '# Cron Job: K\n\n**Job ID:** k\n**Mode:** no_agent (script)\n**Status:** silent (empty output)\n'
    script = {'id': 'k', 'name': 'K', 'last_status': 'ok', 'no_agent': True}
    assert notice(script, doc) is None  # not listed: script successes stay quiet
    assert notice(script, doc, {'k'}) == ('K', '🚀 t_1 : poussé sur main.', False)
    assert notice(script, head_only, {'k'}) is None  # a tick with nothing to say
    assert notice({**script, 'last_status': 'delivery_queued'}, doc, {'k'})[2] is False  # not a failure
    agent = {'id': 'a', 'name': 'A', 'last_status': 'ok'}
    assert notice(agent, '## Response\n\nBonjour') == ('A', 'Bonjour', False)
    assert notice(agent, '## Response\n\n[SILENT]') is None
    now = datetime.fromisoformat('2026-11-05T21:30:00+01:00').timestamp()
    on_time = {'state': 'scheduled', 'last_run_at': '2026-11-05T21:25:00+01:00'}
    assert staleness(on_time, 15, now) is None
    assert staleness({**on_time, 'last_run_at': '2026-11-05T21:00:00+01:00'}, 15, now) == 'aucune exécution depuis 30 min'
    assert staleness({**on_time, 'state': 'paused'}, 15, now) == 'en pause'
    assert staleness({**on_time, 'enabled': False}, 15, now) == 'en pause'
    assert staleness({'state': 'scheduled'}, 15, now) == 'jamais exécuté'
    assert staleness(None, 15, now) == 'supprimé'
    global NOTIFY, tell
    told, real = [], (NOTIFY, tell)
    with tempfile.TemporaryDirectory() as d:
        NOTIFY = Path(d) / 'notify.json'
        NOTIFY.write_text('{"stale": {"k": 15}}')
        tell = lambda sa, cron, title, text, failed, nid: told.append((title, failed))
        stopped, late = set(), {'k': {'name': 'K', 'last_run_at': '2026-11-05T21:00:00+01:00'}}
        for _ in range(3):  # reported once, not every 20 s
            watch_stale(None, late, stopped, now)
        watch_stale(None, {'k': {**late['k'], 'last_run_at': '2026-11-05T21:29:00+01:00'}}, stopped, now)
        assert told == [('Arrêt : K', True), ('K', False)] and not stopped
    NOTIFY, tell = real
    with tempfile.TemporaryDirectory() as d:
        feed = Path(d) / 'sub' / 'feed.json'
        for n in range(FEED_SIZE + 5):
            record({'id': f'k:{n}', 'text': str(n)}, feed)
        record({'id': 'k:3', 'text': 'again'}, feed)
        items = json.loads(feed.read_text())
        assert len(items) == FEED_SIZE and items[0] == {'id': 'k:3', 'text': 'again'}
        assert items[1]['id'] == f'k:{FEED_SIZE + 4}' and [e['id'] for e in items].count('k:3') == 1
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / 'herapp' / 'push.json'
        first = topic(path)
        assert first.startswith('herapp-') and len(first) == 39 and topic(path) == first  # drawn once, then kept
        path.write_text('{}')
        assert topic(path) not in ('', first)  # a broken file gets a new one
    print('ok')


if __name__ == '__main__':
    test() if sys.argv[1:] == ['test'] else main()
