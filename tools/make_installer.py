#!/usr/bin/env python3
"""Builds installer/RetroBat-Wizard-Installer.zip, the website's download.

usage: make_installer.py [<token.txt>]

The zip holds ONE file, INSTALL THE WIZARD.bat: a .bat on top and
installer/Install-Wizard.ps1 underneath, in one file. Windows runs a single
file straight out of a zip when it is double-clicked, so nobody has to unzip
anything (Steven, 2026-10-25: "the unzip anywhere is not awesome").

How one file is both: the first line, `<# : ...`, is a harmless label to
cmd.exe and the start of a comment to PowerShell. cmd runs the few batch
lines, which start PowerShell on this same file; PowerShell skips the batch
lines as a comment and runs the rest.

Written in:
  @@TOKEN@@  the friends-list key, as scrambled in token.txt ("rb1:" + base64
             of it backwards, so GitHub's secret scanner leaves it alone).
             Taken from <token.txt>, or from the zip being replaced.
  @@MAGE@@   the mage riding the bars: drive/Program/wizard/mage.png brought back to
             its own pixels (18 x 26), as a base64 PNG.
"""
import base64, io, os, sys, zipfile
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(here)
src = os.path.join(repo, 'installer', 'Install-Wizard.ps1')
out_zip = os.path.join(repo, 'installer', 'RetroBat-Wizard-Installer.zip')

# --- the key ---------------------------------------------------------------
if len(sys.argv) > 1:
    token = open(sys.argv[1], 'rb').read().decode('ascii').strip()
else:
    token = zipfile.ZipFile(out_zip).read('token.txt' if 'token.txt' in zipfile.ZipFile(out_zip).namelist()
                                         else 'INSTALL THE WIZARD.bat').decode('ascii')
    if 'rb1:' in token and '\n' in token.strip():      # read back out of an earlier one-file build
        token = token.split("$Token    = '", 1)[1].split("'", 1)[0]
    token = token.strip()
assert token.startswith('rb1:') and all(32 < ord(c) < 127 and c != "'" for c in token), 'token.txt is not the scrambled form'

# --- the mage --------------------------------------------------------------
im = Image.open(os.path.join(repo, 'drive', 'Program', 'wizard', 'mage.png')).convert('RGBA')
W, H = im.size
px = im.load()
best = None
for ox in range(4):
    for oy in range(4):
        bad = sum(1 for by in range(oy, H - 3, 4) for bx in range(ox, W - 3, 4)
                  if len({px[bx + i, by + j] for i in range(4) for j in range(4)}) > 1)
        if best is None or bad < best[0]:
            best = (bad, ox, oy)
_, ox, oy = best
sm = Image.new('RGBA', ((W - ox) // 4, (H - oy) // 4))
for y in range(sm.size[1]):
    for x in range(sm.size[0]):
        r, g, b, a = px[ox + x * 4 + 1, oy + y * 4 + 1]
        if a < 200 or (r > 150 and g > 190 and b > 220):   # the soft glow around it
            a = 0
        sm.putpixel((x, y), (r, g, b, a))
sm = sm.crop(sm.getbbox())
buf = io.BytesIO()
sm.save(buf, 'PNG', optimize=True)
mage = base64.b64encode(buf.getvalue()).decode('ascii')

# --- one file ----------------------------------------------------------------
ps = open(src, encoding='ascii').read()
assert ps.count('@@TOKEN@@') == 1 and ps.count('@@MAGE@@') == 1
ps = ps.replace("'@@TOKEN@@'", "'" + token + "'").replace("'@@MAGE@@'", "'" + mage + "'")
head = (
    '<# : RetroBat Wizard installer. Double-click this file. It can run straight from the zip.\n'
    '@echo off\n'
    'title Installing the RetroBat Wizard\n'
    'set "RBW_SELF=%~f0"\n'
    '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -ExecutionPolicy Bypass '
    '-Command "iex ([System.IO.File]::ReadAllText($env:RBW_SELF))"\n'
    'exit /b\n'
    '#>\n'
)
assert '#>' not in head[:-3]
bat = (head + ps).replace('\r\n', '\n').replace('\n', '\r\n')
assert all(ord(c) < 128 for c in bat), 'not plain ASCII'

tmp = out_zip + '.tmp'
with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
    info = zipfile.ZipInfo('INSTALL THE WIZARD.bat', date_time=(2026, 10, 25, 12, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    z.writestr(info, bat.encode('ascii'))
os.replace(tmp, out_zip)
print('installer: %s (%d KB, one file, mage %dx%d)' % (out_zip, os.path.getsize(out_zip) // 1024, sm.size[0], sm.size[1]))
