#!/usr/bin/env python3
"""Builds the public repo tree from a copy of _Wizard (3.2+; _ClaudeWorkspace before) and its ship-list.txt.

usage:
  publish.py build  <ws_dir> <repo_dir> <version>      drive/..., manifest.txt, .gitattributes
  publish.py latest <repo_dir> <version> <commit> <notes>   latest.ini, pointing at <commit>
  publish.py dev    <repo_dir> <version> <commit> <notes>   latest-dev.ini, the same for the dev channel
  publish.py package <repo_dir>                        package/wizard-package.zip from drive/

THE PACKAGE (2026-10-25). The installer downloads package/wizard-package.zip
(at the published commit) in ONE go instead of fetching ~260 files one by
one, then the update engine checks every file against manifest.txt and
fetches only what the package lacks or has older. So the package does not
have to be exactly current: `build` prints how far it has drifted, and it is
only worth rebuilding (`package`) when that is more than a few MB, because
every rebuild adds its full size to the repo's history. Admin-only files are
left out of it.

The dev channel (2026-10-12): drives set to Dev on the Admin tab read
latest-dev.ini instead. Build the dev version on a dev branch (say 2.4-dev),
commit and push it there, then write latest-dev.ini ON MAIN pointing at that
commit. Friends on Stable never read latest-dev.ini.

Two steps because latest.ini names the COMMIT that holds the files, and a
commit cannot name itself: build, commit, push, then latest with that commit's
id, commit, push. Tags are not used (the session git proxy would not push them,
and a commit id is just as fixed).
Refuses to publish if any shipped file looks like it holds a GitHub token,
if a path is not plain ASCII, or if a file is over GitHub's 100 MB limit.
"""
import hashlib, os, re, shutil, sys

if sys.argv[1] in ('latest', 'dev'):
    repo, version, commit, notes = sys.argv[2:6]
    assert re.match(r'^[0-9a-f]{40}$', commit), 'need a full commit id'
    name = 'latest.ini' if sys.argv[1] == 'latest' else 'latest-dev.ini'
    head = ('; The newest version. Read by scripts\\UpdateEngine.ps1 on every drive.\n' if name == 'latest.ini'
            else '; The DEV version: read only by drives set to Dev on the Admin tab.\n')
    open(os.path.join(repo, name), 'w', newline='\n').write(
        head +
        '; "tag" is the commit whose manifest.txt and drive\\ files ARE that version.\n'
        '; A commit id never changes, so a download can never get a mix of two versions.\n'
        'version = %s\ntag = %s\nnotes = %s\n' % (version, commit, notes))
    print(name, '->', version, commit)
    sys.exit(0)

def drive_files(repo):
    drive = os.path.join(repo, 'drive')
    admin = set()
    am = os.path.join(repo, 'admin-manifest.txt')
    if os.path.exists(am):
        for line in open(am, encoding='latin-1'):
            parts = line.rstrip('\n').split('\t')
            if len(parts) == 4:
                admin.add(parts[3])
    out = []
    for d, _, fs in os.walk(drive):
        for f in fs:
            rel = os.path.relpath(os.path.join(d, f), drive).replace(os.sep, '/')
            if rel not in admin:
                out.append(rel)
    return drive, sorted(out, key=str.lower)


def package_drift(repo):
    import zipfile
    pk = os.path.join(repo, 'package', 'wizard-package.zip')
    drive, files = drive_files(repo)
    if not os.path.exists(pk):
        return None
    z = zipfile.ZipFile(pk)
    have = {i.filename: i for i in z.infolist()}
    n = 0; size = 0
    for rel in files:
        data = open(os.path.join(drive, rel), 'rb').read()
        i = have.get(rel)
        if i is None or i.file_size != len(data) or z.read(rel) != data:
            n += 1; size += len(data)
    return n, size


if sys.argv[1] == 'package':
    import zipfile
    repo = sys.argv[2]
    drive, files = drive_files(repo)
    os.makedirs(os.path.join(repo, 'package'), exist_ok=True)
    pk = os.path.join(repo, 'package', 'wizard-package.zip')
    tmp = pk + '.tmp'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in files:
            info = zipfile.ZipInfo(rel, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, open(os.path.join(drive, rel), 'rb').read(), compresslevel=9)
    os.replace(tmp, pk)
    print('package: %d files, %.1f MB' % (len(files), os.path.getsize(pk) / 1048576))
    sys.exit(0)

assert sys.argv[1] == 'build'
ws, repo, version = sys.argv[2], sys.argv[3], sys.argv[4]


def pat_to_re(p):
    out = ''
    i = 0
    while i < len(p):
        if p.startswith('**', i):
            out += '.*'; i += 2
        elif p[i] == '*':
            out += '[^/]*'; i += 1
        else:
            out += re.escape(p[i]); i += 1
    return re.compile('^' + out + '$', re.I)


rules = []
shiplist = os.path.join(ws, 'Program', 'ship-list.txt')       # 3.2 rooms
if not os.path.exists(shiplist):
    shiplist = os.path.join(ws, 'ship-list.txt')              # before 3.2
for raw in open(shiplist, encoding='latin-1'):
    line = raw.strip()
    if not line or line.startswith(';') or line.startswith('#'):
        continue
    kind, rest = line.split(None, 1)
    src = None
    if '<-' in rest:
        rest, src = [x.strip() for x in rest.split('<-', 1)]
    rules.append((kind, rest.strip(), src))

all_files = []
for d, _, fs in os.walk(ws):
    for f in fs:
        rel = os.path.relpath(os.path.join(d, f), ws).replace(os.sep, '/')
        all_files.append(rel)

entries = {}
for rel in sorted(all_files):
    if any(k == 'skip' and pat_to_re(p).match(rel) for k, p, _ in rules):
        continue
    for kind, p, src in rules:
        if kind in ('code', 'seed', 'admin') and src is None and pat_to_re(p).match(rel):
            entries[rel] = (kind, os.path.join(ws, rel))
            break
for kind, p, src in rules:
    if src is not None:
        s = os.path.join(ws, src)
        assert os.path.isfile(s), 'seed source missing: ' + src
        entries[p] = (kind, s)

# literal (no wildcard) rules must have matched something
for kind, p, src in rules:
    if kind != 'skip' and '*' not in p:
        assert p in entries, 'ship-list names a file that is not there: ' + p

problems = []
TOKEN = re.compile(rb'(github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,})')
for rel, (kind, src) in entries.items():
    if not all(32 <= ord(c) < 127 for c in rel) or '\\' in rel:
        problems.append('path not plain ASCII: ' + rel)
    size = os.path.getsize(src)
    if size > 95 * 1024 * 1024:
        problems.append('too big for git: ' + rel)
    if TOKEN.search(open(src, 'rb').read()):
        problems.append('LOOKS LIKE A TOKEN: ' + rel)
if problems:
    print('\n'.join(problems)); sys.exit(1)

drive = os.path.join(repo, 'drive')
if os.path.isdir(drive):
    shutil.rmtree(drive)
lines = ['# retrobat-wizard manifest. Built by publish.py from ship-list.txt.',
         'version\t' + version]
# The admin tools: same format, kind 'code', in a list of their own that
# only an admin's setup reads (Install-UpdAdminPack). manifest.txt never
# names them, so older drives, which refuse any kind but code and seed,
# read it as always.
admin_lines = ['# retrobat-wizard ADMIN TOOLS. Built by publish.py from ship-list.txt.',
               'version\t' + version]
total = 0
for rel in sorted(entries, key=str.lower):
    kind, src = entries[rel]
    dst = os.path.join(drive, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    data = open(dst, 'rb').read()
    total += len(data)
    line = '%s\t%s\t%d\t%s' % ('code' if kind == 'admin' else kind, hashlib.sha256(data).hexdigest(), len(data), rel)
    (admin_lines if kind == 'admin' else lines).append(line)

# version.txt in the repo must say the version being published
vt = open(os.path.join(drive, 'version.txt')).read().strip()
assert vt == version, 'version.txt says %s, publishing %s' % (vt, version)

open(os.path.join(repo, 'manifest.txt'), 'w', newline='\n').write('\n'.join(lines) + '\n')
am = os.path.join(repo, 'admin-manifest.txt')
if len(admin_lines) > 2:
    open(am, 'w', newline='\n').write('\n'.join(admin_lines) + '\n')
elif os.path.exists(am):
    os.remove(am)
open(os.path.join(repo, '.gitattributes'), 'w', newline='\n').write(
    '# Byte-for-byte: the drive checks every file against its SHA-256.\n* -text\n')
print('%d files, %.1f MB, version %s' % (len(entries), total / 1048576, version))
print('code: %d  seed: %d  admin: %d' % (sum(1 for e in entries.values() if e[0] == 'code'),
                                         sum(1 for e in entries.values() if e[0] == 'seed'),
                                         sum(1 for e in entries.values() if e[0] == 'admin')))
d = package_drift(repo)
if d is None:
    print('package: none yet. Run: publish.py package %s' % repo)
else:
    print('package: %d file(s), %.1f MB newer than package/wizard-package.zip%s' % (
        d[0], d[1] / 1048576, '  -> worth rebuilding (publish.py package)' if d[1] > 3 * 1048576 else ''))
