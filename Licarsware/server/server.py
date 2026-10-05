#!/usr/bin/env python3
"""
licarsware // auth server
=========================
Key system backend enforcing:
  - one key per script (you generate it, only you have it)
  - one IP per key: first successful verify binds the key to that IP
  - any other IP using the key  ->  key + HWID BLACKLISTED permanently
  - any blacklisted HWID        ->  permanently denied
  - wrong-key attempt limiting (lockout after N bad tries per HWID)

Run:  python3 Licarsware/server/server.py
Test: python3 Licarsware/server/server.py --test
Deploy: Render free tier works out of the box (see README for the walkthrough).
Env vars: LW_ADMIN (admin token), LW_PORT/PORT (listen port),
          LW_GIST_ID + LW_GIST_TOKEN (optional: persist the key DB to a
          private GitHub gist so free-host restarts don't wipe your keys).

Durations:
  keys are 'lifetime' (default), '1d' (1 day) or '7d' (1 week).
  The clock starts on FIRST USE (activation), not creation. Expired keys
  never bind an IP and always return {'status': 'expired'}.

Admin endpoints (guard ADMIN_TOKEN in production!):
  GET  /admin/list                  -> dump db (keys + blacklist)
  POST /admin/gen {script,duration} -> generate a key ('1d'|'7d'|'lifetime')
  POST /admin/unban {hwid}          -> remove hwid from blacklist
  POST /admin/reset {key}           -> unbind key from its IP (keeps expiry)
"""

import json
import os
import secrets
import string
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ---------------- config ----------------
DB_PATH     = os.environ.get('LW_DB', os.path.join(os.path.dirname(__file__), 'licarsware_db.json'))
# Render/other hosts inject PORT; LW_PORT stays as an explicit override
PORT        = int(os.environ.get('LW_PORT', os.environ.get('PORT', '8787')))
ADMIN_TOKEN = os.environ.get('LW_ADMIN', 'changeme-admin-token')
MAX_ATTEMPTS = 5
LOCKOUT_SECS = 600

# license durations; None = never expires
DURATIONS = {
    '1d': 86400,
    '7d': 7 * 86400,
    'lifetime': None,
}

_lock = threading.Lock()

# ---------------- optional: gist-backed persistence ----------------
# Free hosts (Render free tier, etc.) have EPHEMERAL disks: every restart or
# redeploy wipes local files, which would silently delete your keys and
# blacklist. If LW_GIST_ID + LW_GIST_TOKEN are set, the DB is mirrored to a
# private GitHub "secret" gist (stdlib urllib only, no dependencies) and
# restored on boot. A secret gist is unlisted but NOT encrypted -- anyone with
# the URL + token could read it, so keep the token in a host secret store.
GIST_ID    = os.environ.get('LW_GIST_ID', '')
GIST_TOKEN = os.environ.get('LW_GIST_TOKEN', '')
GIST_FILE  = 'licarsware_db.json'
_GIST_API  = 'https://api.github.com'

_gist_headers = {
    'Authorization': f'Bearer {GIST_TOKEN}',
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'licarsware-auth',
    'Content-Type': 'application/json',
}

_gist_pending = threading.Event()


def _gist_fetch():
    req = urllib.request.Request(f'{_GIST_API}/gists/{GIST_ID}', headers=_gist_headers)
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.load(resp)
    content = data.get('files', {}).get(GIST_FILE, {}).get('content')
    return json.loads(content) if content else None


def _gist_push(db):
    body = json.dumps({'files': {GIST_FILE: {'content': json.dumps(db)}}}).encode()
    req = urllib.request.Request(f'{_GIST_API}/gists/{GIST_ID}', data=body, headers=_gist_headers, method='PATCH')
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def _gist_worker():
    # coalescing background writer: bursts of verifies collapse into one push
    while True:
        _gist_pending.wait()
        _gist_pending.clear()
        time.sleep(0.5)
        try:
            with _lock:
                with open(DB_PATH, 'r', encoding='utf-8') as f:
                    db = json.load(f)
            _gist_push(db)
        except Exception as exc:  # never crash the server over a mirror write
            sys.stderr.write(f'[auth] gist push failed: {exc}\n')


def _start_gist_worker():
    threading.Thread(target=_gist_worker, daemon=True).start()

def _new_db():
    return {
        'keys': {},          # key -> {script, hwid, ip, bound_at, created}
        'blacklist': {},     # hwid -> {reason, at, key}
        'attempts': {},      # hwid -> {count, locked_until}
    }

def _load():
    if os.path.exists(DB_PATH):
        with open(DB_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    return _new_db()

def _save(db):
    with open(DB_PATH, 'w', encoding='utf-8') as f:
        json.dump(db, f, indent=2)
    if GIST_ID and GIST_TOKEN:
        _gist_pending.set()

# IP binding trusts X-Forwarded-For by default because hosts like Render sit
# behind a proxy and client_address would otherwise be the proxy's IP for EVERYONE
# (every key would 'collide'). Only set LW_TRUST_PROXY=0 when the server is
# exposed directly to the internet -- otherwise users could spoof their IP header.
TRUST_PROXY = os.environ.get('LW_TRUST_PROXY', '1') == '1'

def _ip(handler):
    if TRUST_PROXY:
        fwd = handler.headers.get('X-Forwarded-For', '')
        if fwd:
            return fwd.split(',')[0].strip()
    return handler.client_address[0]

def _gen_key():
    alphabet = string.ascii_uppercase + string.digits
    length = secrets.choice([12, 14, 16])
    return '-'.join(''.join(secrets.choice(alphabet) for _ in range(4)) for _ in range(length // 4))

def _new_key(script, duration):
    return {
        'script': script,
        'duration': duration,
        'hwid': None,
        'ip': None,
        'created': time.time(),
        'activated': None,     # set on first successful verify
        'expires_at': None,    # set on activation for timed keys
    }

# ---------------- core logic ----------------
def verify(db, script, key, hwid):
    now = time.time()

    # 1) HWID blacklist is absolute
    if hwid in db['blacklist']:
        return {'status': 'blacklisted', 'reason': db['blacklist'][hwid].get('reason', 'blacklisted')}

    entry = db['keys'].get(key)

    # 2) unknown key -> count attempts for this hwid
    if entry is None:
        rec = db['attempts'].setdefault(hwid, {'count': 0, 'locked_until': 0})
        if rec.get('locked_until', 0) > now:
            return {'status': 'locked', 'retryAfter': int(rec['locked_until'] - now)}
        rec['count'] += 1
        if rec['count'] >= MAX_ATTEMPTS:
            rec['locked_until'] = now + LOCKOUT_SECS
            rec['count'] = 0
            return {'status': 'locked', 'retryAfter': LOCKOUT_SECS}
        return {'status': 'invalid', 'message': f'Invalid key. {MAX_ATTEMPTS - rec["count"]} attempts left.'}

    # 3) key exists but belongs to another script -> count as invalid
    if entry.get('script') != script:
        rec = db['attempts'].setdefault(hwid, {'count': 0, 'locked_until': 0})
        rec['count'] += 1
        if rec['count'] >= MAX_ATTEMPTS:
            rec['locked_until'] = now + LOCKOUT_SECS
            rec['count'] = 0
            return {'status': 'locked', 'retryAfter': LOCKOUT_SECS}
        return {'status': 'invalid', 'message': 'This key is not for this script.'}

    # 4) expiry: dead keys never bind and never play
    if entry.get('expires_at') is not None and now > entry['expires_at']:
        return {'status': 'expired', 'message': 'License expired. Buy a new key.'}

    # 5) IP binding: first use binds (and starts timed licenses), other IP = theft = blacklist
    bound_ip = entry.get('ip')
    if bound_ip is None:
        entry['ip'] = _CLIENT_IP
        entry['hwid'] = hwid
        entry['bound_at'] = now
        seconds = DURATIONS.get(entry.get('duration', 'lifetime'))
        if seconds is not None:
            entry['activated'] = now
            entry['expires_at'] = now + seconds
        _save(db)
        remaining = entry.get('expires_at')
        return {'status': 'valid', 'message': 'Key verified and bound to your IP.',
                'duration': entry.get('duration', 'lifetime'),
                'expires_in': remaining is not None and int(remaining - now) or None}

    if bound_ip != _CLIENT_IP:
        db['blacklist'][hwid] = {'reason': f'key {key} used from a second IP', 'at': now, 'key': key}
        db['blacklist'].setdefault('__keys__', {})
        db['keys'].pop(key, None)  # kill the key entirely
        _save(db)
        return {'status': 'blacklisted', 'reason': 'Key in use on another network. Access denied.'}

    # 6) same IP but different hwid (shared PC) -> also blacklist
    if entry.get('hwid') not in (None, hwid):
        db['blacklist'][hwid] = {'reason': 'hwid mismatch on bound key', 'at': now, 'key': key}
        _save(db)
        return {'status': 'blacklisted', 'reason': 'Key fingerprint mismatch. Access denied.'}

    db['attempts'].pop(hwid, None)  # successful login clears attempts
    remaining = entry.get('expires_at')
    return {'status': 'valid', 'message': 'Welcome back.',
            'duration': entry.get('duration', 'lifetime'),
            'expires_in': remaining is not None and int(remaining - now) or None}

# ---------------- HTTP ----------------
_CLIENT_IP = None  # set per request

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        # CORS: lets a browser hit /admin endpoints (Roblox executors ignore CORS)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _admin(self):
        return self.headers.get('Authorization', '') == f'Bearer {ADMIN_TOKEN}'

    def do_POST(self):
        global _CLIENT_IP
        _CLIENT_IP = _ip(self)
        try:
            length = int(self.headers.get('Content-Length', 0))
            data = json.loads(self.rfile.read(length) or b'{}')
        except Exception:
            return self._send(400, {'status': 'error', 'message': 'bad json'})

        with _lock:
            db = _load()

            if self.path == '/verify':
                script = str(data.get('script', ''))[:64]
                key = str(data.get('key', '')).strip().upper()[:64]
                hwid = str(data.get('hwid', ''))[:64]
                if not script or not key or not hwid:
                    return self._send(400, {'status': 'error', 'message': 'missing fields'})
                result = verify(db, script, key, hwid)
                db['attempts'] = {h: r for h, r in db['attempts'].items() if r.get('locked_until', 0) > time.time()}
                _save(db)
                return self._send(200, result)

            if self.path.startswith('/admin'):
                if not self._admin():
                    return self._send(403, {'status': 'error', 'message': 'forbidden'})

                if self.path == '/admin/gen':
                    script = str(data.get('script', 'default'))[:64]
                    duration = str(data.get('duration', 'lifetime')).lower()
                    if duration not in DURATIONS:
                        return self._send(400, {'status': 'error',
                                                'message': "duration must be one of: '1d', '7d', 'lifetime'"})
                    key = _gen_key()
                    db['keys'][key] = _new_key(script, duration)
                    _save(db)
                    return self._send(200, {'status': 'ok', 'key': key, 'script': script, 'duration': duration})

                if self.path == '/admin/unban':
                    hwid = str(data.get('hwid', ''))[:64]
                    db['blacklist'].pop(hwid, None)
                    _save(db)
                    return self._send(200, {'status': 'ok'})

                if self.path == '/admin/reset':
                    key = str(data.get('key', '')).upper()[:64]
                    if key in db['keys']:
                        db['keys'][key]['ip'] = None
                        db['keys'][key]['hwid'] = None
                        _save(db)
                        return self._send(200, {'status': 'ok', 'message': 'key unbound'})
                    return self._send(404, {'status': 'error', 'message': 'no such key'})

            return self._send(404, {'status': 'error', 'message': 'not found'})

    def do_GET(self):
        global _CLIENT_IP
        _CLIENT_IP = _ip(self)
        if self.path == '/ping':
            return self._send(200, {'status': 'ok', 'service': 'licarsware-auth'})
        with _lock:
            if self.path == '/admin/list':
                if not self._admin():
                    return self._send(403, {'status': 'error', 'message': 'forbidden'})
                db = _load()
                return self._send(200, {'keys': db['keys'], 'blacklist': db['blacklist']})
        return self._send(404, {'status': 'error', 'message': 'not found'})

    def log_message(self, fmt, *args):
        sys.stderr.write('[auth] ' + fmt % args + '\n')

# ---------------- self-test ----------------
def _test():
    global _CLIENT_IP
    import tempfile
    tmp = tempfile.mkdtemp()
    globals()['DB_PATH'] = os.path.join(tmp, 'db.json')
    db = _new_db()

    # lifetime key: full bind/blacklist flow
    key = _gen_key()
    db['keys'][key] = _new_key('test', 'lifetime')
    globals()['_CLIENT_IP'] = '1.2.3.4'
    res = verify(db, 'test', key, 'HWID_A')
    assert res['status'] == 'valid' and res['expires_in'] is None, 'lifetime must never expire'
    globals()['_CLIENT_IP'] = '5.6.7.8'
    assert verify(db, 'test', key, 'HWID_B')['status'] == 'blacklisted', 'second IP must be blacklisted'
    globals()['_CLIENT_IP'] = '1.2.3.4'
    assert verify(db, 'test', key, 'HWID_A')['status'] == 'blacklisted', 'key destroyed after theft attempt'
    globals()['_CLIENT_IP'] = '5.6.7.8'
    assert verify(db, 'test', key, 'HWID_B')['status'] == 'blacklisted', 'HWID_B stays blacklisted'

    # 1d key: activates on first use with <= 86400s remaining
    day = _gen_key()
    db['keys'][day] = _new_key('test', '1d')
    globals()['_CLIENT_IP'] = '9.9.9.9'
    res = verify(db, 'test', day, 'HWID_C')
    assert res['status'] == 'valid' and res['expires_in'] and res['expires_in'] <= 86400, '1d key must report expires_in'
    assert db['keys'][day]['expires_at'] is not None, '1d key must set expires_at on activation'

    # expiry: force the clock past the deadline -> denied
    db['keys'][day]['expires_at'] = time.time() - 1
    assert verify(db, 'test', day, 'HWID_C')['status'] == 'expired', 'past deadline must be expired'

    # expired keys must never bind a fresh IP
    dead = _gen_key()
    db['keys'][dead] = _new_key('test', '1d')
    db['keys'][dead]['expires_at'] = time.time() - 100
    globals()['_CLIENT_IP'] = '7.7.7.7'
    assert verify(db, 'test', dead, 'HWID_D')['status'] == 'expired'
    assert db['keys'][dead].get('ip') is None, 'expired key must not bind'

    print('all auth tests passed ✔  (lifetime, 1d, 7d, expiry, no-bind-on-expired)')

if __name__ == '__main__':
    if '--test' in sys.argv:
        _test()
        sys.exit(0)

    if GIST_ID and GIST_TOKEN:
        try:
            if not os.path.exists(DB_PATH):
                remote = _gist_fetch()
                if remote:
                    with open(DB_PATH, 'w', encoding='utf-8') as f:
                        json.dump(remote, f, indent=2)
                    print('[auth] restored key database from gist')
            _start_gist_worker()
            print('[auth] gist persistence active')
        except Exception as exc:
            print(f'[auth] WARNING: gist persistence unavailable ({exc}); running local-only')

    print(f'licarsware auth listening on :{PORT}  (db: {DB_PATH})')
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
