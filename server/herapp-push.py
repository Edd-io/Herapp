#!/usr/bin/env python3
"""Sends a push to Herapp (FCM topic) when a Hermes cron job finishes: its answer, or why it failed.

Polls ~/.hermes/cron/jobs.json. Silent answers are skipped, and so are the successes of script-only jobs
(no_agent), except those listed in ~/.config/herapp-push/notify.json ({"jobs": ["<job id>", ...]}): their
output, when not empty, is pushed as is. No model is involved anywhere.
Every notice is also kept in ~/.hermes/herapp/notifications.json (newest first), the app's Notifications page.
Needs ~/.config/herapp-push/service-account.json (Firebase service account key) and openssl.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path

HOME = Path.home()
JOBS = HOME / '.hermes/cron/jobs.json'
OUTPUT = HOME / '.hermes/cron/output'
KEY = HOME / '.config/herapp-push/service-account.json'
NOTIFY = HOME / '.config/herapp-push/notify.json'
FEED = HOME / '.hermes/herapp/notifications.json'
FEED_SIZE = 300
TEXT_LIMIT = 4000
TOPIC = 'herapp-crons'
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


def send(sa, title, body, job_id, notice_id):
    msg = {'message': {'topic': TOPIC, 'notification': {'title': title, 'body': body},
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


def main():
    sa = json.loads(KEY.read_text())
    seen = {i: j.get('last_run_at') for i, j in (runs() or {}).items()}
    while True:
        time.sleep(20)
        jobs = runs()
        if jobs is None:
            continue
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
    with tempfile.TemporaryDirectory() as d:
        feed = Path(d) / 'sub' / 'feed.json'
        for n in range(FEED_SIZE + 5):
            record({'id': f'k:{n}', 'text': str(n)}, feed)
        record({'id': 'k:3', 'text': 'again'}, feed)
        items = json.loads(feed.read_text())
        assert len(items) == FEED_SIZE and items[0] == {'id': 'k:3', 'text': 'again'}
        assert items[1]['id'] == f'k:{FEED_SIZE + 4}' and [e['id'] for e in items].count('k:3') == 1
    print('ok')


if __name__ == '__main__':
    test() if sys.argv[1:] == ['test'] else main()
