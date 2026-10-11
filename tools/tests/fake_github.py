#!/usr/bin/env python3
"""A tiny fake of the GitHub endpoints the Admin tab's Publish a game uses.
usage: fake_github.py <port>   (test-admin.ps1 starts and stops it)"""
import base64, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
state = {'release': None, 'assets': {}, 'next': 100,
         'library': json.dumps({'version': 1, 'note': 'n \\ x', 'games': [
             {'id': 'old', 'title': 'Old Game', 'system': 'nes', 'players': '1', 'description': '',
              'added': '2026-01-01', 'files': [{'name': 'old.nes', 'url': 'https://github.com/x', 'size': 3, 'sha256': 'a' * 64}]}]}),
         'libsha': 's1'}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj=None):
        b = json.dumps(obj).encode() if obj is not None else b''
        self.send_response(code); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def body(self):
        n = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(n)
    # Two keys since 2026-10-11: the library key (github_pat_TEST) may only
    # touch the PUBLIC repo's list, the friends key (github_pat_SOCIAL) only
    # the PRIVATE repo's release, where the files now live.
    def auth(self):
        a = self.headers.get('Authorization')
        if self.path == '/state': return True
        pub = '/repos/Feirzen/retrobat-wizard/' in self.path
        priv = '/repos/Feirzen/retrobat-wizard-social/' in self.path
        if (pub and a == 'Bearer github_pat_TEST') or (priv and a == 'Bearer github_pat_SOCIAL'):
            return True
        self.send(401, {'message': 'Bad credentials'}); return False
    def rel(self):
        r = dict(state['release']); r['assets'] = list(state['assets'].values()); return r
    def do_GET(self):
        if not self.auth(): return
        if self.path.endswith('/releases/tags/library'):
            return self.send(404, {}) if state['release'] is None else self.send(200, self.rel())
        if self.path.endswith('/contents/library/library.json'):
            return self.send(200, {'sha': state['libsha'], 'content': base64.b64encode(state['library'].encode()).decode()})
        if self.path == '/state':
            return self.send(200, {'assets': list(state['assets']), 'library': json.loads(state['library'])})
        self.send(404, {})
    def do_POST(self):
        if not self.auth(): return
        b = self.body()
        if self.path.endswith('/releases'):
            state['release'] = {'id': 7, 'tag_name': json.loads(b)['tag_name']}
            return self.send(201, self.rel())
        if '/releases/7/assets?name=' in self.path:
            name = self.path.split('name=')[1]
            state['next'] += 1
            state['assets'][name] = {'id': state['next'], 'name': name, 'size': len(b)}
            return self.send(201, {'name': name, 'url': 'https://api.github.com/repos/Feirzen/retrobat-wizard-social/releases/assets/%d' % state['next'], 'size': len(b)})
        self.send(404, {})
    def do_DELETE(self):
        if not self.auth(): return
        aid = int(self.path.rsplit('/', 1)[1])
        for k, v in list(state['assets'].items()):
            if v['id'] == aid: del state['assets'][k]
        self.send(204)
    def do_PUT(self):
        if not self.auth(): return
        b = json.loads(self.body())
        if b.get('sha') != state['libsha']: return self.send(409, {})
        state['library'] = base64.b64decode(b['content']).decode(); state['libsha'] = 's%d' % (int(state['libsha'][1:]) + 1)
        self.send(200, {'content': {'sha': state['libsha']}})
HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
