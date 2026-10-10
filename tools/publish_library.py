#!/usr/bin/env python3
"""Adds games from Steven's library-to-publish folder to library/library.json.

usage: publish_library.py <library-to-publish dir> <repo dir>

Each game is a folder holding its file(s) and a game.ini (written by the
wizard's Games tab). Files up to 45 MB are committed under library/files/<id>/;
bigger ones are listed in big-files.txt for upload as Release assets, which
publish step does by hand (see PUBLISHING.md). Re-running with the same game
replaces that game's entry.

BEFORE RUNNING: check every game may be shared (homebrew, freeware, fan-made,
Steven's own). Commercial games never go in here, free-to-play or not.
"""
import hashlib, json, os, re, shutil, sys, urllib.parse

src, repo = sys.argv[1], sys.argv[2]
lib_path = os.path.join(repo, 'library', 'library.json')
lib = json.load(open(lib_path))
games = {g['id']: g for g in lib.get('games', [])}
big = []
RAW = 'https://raw.githubusercontent.com/Feirzen/retrobat-wizard/main/library/files/'
for gid in sorted(os.listdir(src)):
    d = os.path.join(src, gid)
    ini = os.path.join(d, 'game.ini')
    if not os.path.isfile(ini):
        continue
    info = {}
    for line in open(ini, encoding='latin-1'):
        line = line.strip()
        if not line or line.startswith(';') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        info[k.strip().lower()] = v.strip()
    assert re.match(r'^[a-z0-9\-]{1,40}$', gid), gid
    assert re.match(r'^[a-z0-9\-]{1,20}$', info.get('system', '')), info
    files = []
    for fn in sorted(os.listdir(d)):
        if fn == 'game.ini':
            continue
        assert all(32 <= ord(c) < 127 for c in fn) and not re.search(r'[\\/:*?"<>|]', fn), fn
        p = os.path.join(d, fn)
        data = open(p, 'rb').read()
        size = len(data)
        sha = hashlib.sha256(data).hexdigest()
        if size > 45 * 1024 * 1024:
            big.append((gid, fn, size, sha))
            url = 'https://github.com/Feirzen/retrobat-wizard/releases/download/library/' + urllib.parse.quote(fn)
        else:
            dst = os.path.join(repo, 'library', 'files', gid, fn)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(p, dst)
            url = RAW + gid + '/' + urllib.parse.quote(fn)
        files.append({'name': fn, 'url': url, 'size': size, 'sha256': sha})
    games[gid] = {
        'id': gid, 'title': info.get('title', gid), 'system': info['system'],
        'players': info.get('players', ''), 'description': info.get('description', ''),
        'files': files, 'added': info.get('queued', '')[:10],
    }
    print('added', gid, info['system'], [f['name'] for f in files])
lib['games'] = sorted(games.values(), key=lambda g: (g['system'], g['title'].lower()))
json.dump(lib, open(lib_path, 'w', newline='\n'), indent=2)
open(lib_path, 'a').write('\n')
if big:
    with open(os.path.join(repo, 'library', 'big-files.txt'), 'w') as f:
        for b in big:
            f.write('%s\t%s\t%d\t%s\n' % b)
    print('BIG FILES to upload as Release assets (tag "library"):', big)
