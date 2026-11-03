#!/usr/bin/env python3
"""Sends a push to Herapp (FCM topic) when a Hermes cron job finishes: its answer, or why it failed.

Polls ~/.hermes/cron/jobs.json. Successes of script-only jobs (no_agent) and silent answers are skipped.
Needs ~/.config/herapp-push/service-account.json (Firebase service account key) and openssl.
"""
import base64, json, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path

HOME = Path.home()
JOBS = HOME / '.hermes/cron/jobs.json'
OUTPUT = HOME / '.hermes/cron/output'
KEY = HOME / '.config/herapp-push/service-account.json'
TOPIC = 'herapp-crons'
SILENT = {'[SILENT]', 'SILENT', 'NO_REPLY', 'NO REPLY'}


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


def send(sa, title, body, job_id):
    msg = {'message': {'topic': TOPIC, 'notification': {'title': title, 'body': body}, 'data': {'cron': job_id},
                       'apns': {'payload': {'aps': {'sound': 'default'}}}}}
    req = urllib.request.Request(f"https://fcm.googleapis.com/v1/projects/{sa['project_id']}/messages:send",
                                 json.dumps(msg).encode(), {'Authorization': f'Bearer {access_token(sa)}',
                                                            'Content-Type': 'application/json'})
    urllib.request.urlopen(req).close()


def answer(job_id):
    """The latest run's answer, from the output file's Response section."""
    runs = sorted((OUTPUT / job_id).glob('*.md'))
    if not runs:
        return ''
    text = runs[-1].read_text(errors='replace')
    return text.split('## Response', 1)[1].strip() if '## Response' in text else ''


def is_silent(text):
    lines = [l.strip() for l in text.strip().splitlines() if l.strip()]
    return bool(lines) and (lines[0].upper() in SILENT or lines[-1].upper() in SILENT)


def summary(text, limit=180):
    # markdown headings and emphasis read badly in a notification
    flat = ' '.join(l.strip().lstrip('#').strip() for l in text.splitlines() if l.strip()).replace('**', '')
    return flat if len(flat) <= limit else flat[:limit - 1].rstrip() + '…'


def notice(job):
    """(title, body) for a finished run, or None when it isn't worth a push."""
    name = job.get('name') or job['id']
    if job.get('last_status') != 'ok':
        return f'Échec : {name}', summary(job.get('last_error') or 'Échec du cron')
    if job.get('no_agent'):
        return None
    text = answer(job['id'])
    if is_silent(text):
        return None
    return name, summary(text) or 'Terminé'


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
                    if n := notice(j):
                        send(sa, *n, i)
                        print('sent', i, n[0], flush=True)
                except Exception as e:
                    print('push failed', i, e, file=sys.stderr, flush=True)


if __name__ == '__main__':
    if sys.argv[1:] == ['test']:
        assert is_silent('[SILENT]') and is_silent('blah\nNO_REPLY') and not is_silent('ok')
        assert summary('# Bilan\n**Gras** texte') == 'Bilan Gras texte'
        assert summary('x' * 300).endswith('…') and len(summary('x' * 300)) == 180
        assert notice({'id': 'a', 'name': 'N', 'last_status': 'error', 'last_error': 'boom'}) == ('Échec : N', 'boom')
        assert notice({'id': 'a', 'name': 'N', 'last_status': 'ok', 'no_agent': True}) is None
        print('ok')
    else:
        main()
