"""Read-only feasibility probe. Never prints credentials or account identities."""
import json, os, selectors, subprocess, time, urllib.request, urllib.error


def codex():
    binary = '/Applications/ChatGPT.app/Contents/Resources/codex'
    p = subprocess.Popen([binary, 'app-server', '-c', 'analytics.enabled=false'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(p.stdout, selectors.EVENT_READ)
    def send(method, params, ident=None):
        msg = dict(method=method, params=params)
        if ident is not None: msg['id'] = ident
        p.stdin.write((json.dumps(msg)+'\n').encode()); p.stdin.flush()
    def receive(ident):
        deadline = time.monotonic()+20
        while time.monotonic()<deadline:
            if not selector.select(max(0, deadline-time.monotonic())): break
            line = p.stdout.readline()
            if not line: raise RuntimeError('Helper exited')
            msg = json.loads(line)
            if msg.get('id') == ident:
                if 'error' in msg: raise RuntimeError('RPC error code '+str(msg['error'].get('code')))
                return msg['result']
        raise TimeoutError('Codex request timed out')
    try:
        send('initialize', {'clientInfo': {'name':'token_meter_probe','version':'0.1.0'}}, 1); receive(1)
        send('initialized', {})
        send('account/read', {}, 2)
        account = receive(2).get('account')
        print('Codex account type:', (account or {}).get('type'))
        send('account/rateLimits/read', {}, 3)
        result = receive(3)
        buckets = result.get('rateLimitsByLimitId')
        bucket = buckets.get('codex') if isinstance(buckets,dict) else result.get('rateLimits')
        print('Codex bucket IDs:', list(buckets) if isinstance(buckets,dict) else 'legacy')
        print('Codex windows:', json.dumps({k: (bucket or {}).get(k) for k in ['primary','secondary']}))
    finally:
        selector.close(); p.stdin.close()
        p.terminate()
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired: p.kill(); p.wait()


def claude():
    r = subprocess.run(['/usr/bin/security','find-generic-password','-s','Claude Code-credentials','-w'],capture_output=True,timeout=10)
    if r.returncode: print('Claude credential unavailable, Keychain status:',r.returncode); return
    credentials = json.loads(r.stdout)
    oauth = credentials.get('claudeAiOauth',{})
    token = oauth.get('accessToken')
    print('Claude OAuth present:',bool(token), 'profile scope:', 'user:profile' in oauth.get('scopes',[]))
    if not token: return
    req = urllib.request.Request('https://api.anthropic.com/api/oauth/usage',headers={'Authorization':'Bearer '+token,'anthropic-beta':'oauth-2025-04-20'})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            result=json.load(response)
            print('Claude windows:',json.dumps({k:result.get(k) for k in ['five_hour','seven_day']}))
    except urllib.error.HTTPError as e:
        print('Claude HTTP status:',e.code,'Retry-After:',e.headers.get('Retry-After'))

if __name__ == '__main__':
    for probe in [codex, claude]:
        try: probe()
        except Exception as e: print(probe.__name__, 'failed:', type(e).__name__)
