# Publishing a new version

Everything under `tools/` is for whoever publishes. Drives never read it.

1. Make and test the change on the drive (the drive is the source of truth).
2. Bump `_ClaudeWorkspace\version.txt` on the drive (for example `2.2.1`).
3. If a file should start or stop shipping, edit `_ClaudeWorkspace\ship-list.txt`.
4. Copy the shipped folders off the drive (a tar of the folders `ship-list.txt` names).
5. `python3 tools/publish.py build <copy of _ClaudeWorkspace> . <version>`
   This rebuilds `drive/` and `manifest.txt`, and refuses anything that looks
   like a GitHub token, a non-ASCII path, or a file too big for git.
6. Commit and push. Note the commit id.
7. `python3 tools/publish.py latest . <version> <commit id> "note | note | note"`
   Commit and push. Drives see the new version from this moment.

`latest.ini` names a COMMIT, not a branch, so a drive can never download half
of one version and half of another. Tags are not used.

`tools/test-update.ps1` is the engine's test suite (PowerShell 7): a fake drive
and a fake GitHub, 105 assertions covering check, download, checksum refusal,
install, rollback, go back, skip, removed files and the profiles to machine rename.

## The website

`index.html` at the repo root, with `site\` for its icons and banner (drawn by
`tools/make_icons.py`). GitHub Pages serves the repo root at
https://feirzen.github.io/retrobat-wizard/. The front password is a polite
door, not a lock: two passwords work (Steven knows them), checked as SHA-256
of "rbw:" + the lower-cased password. To change one, replace its hash in KEYS.

## The installer

`installer/RetroBat-Wizard-Installer.zip` is what the website's button gives
out: `INSTALL THE WIZARD.bat`, `Install-Wizard.ps1`, and `token.txt` (the
social token scrambled as `rb1:` + base64 of it backwards, so GitHub's secret
scanner does not revoke it). Rebuild the zip whenever either script changes.
The installer always installs whatever `latest.ini` points at.

## The game library

`library/library.json` lists free games; the wizard's Games tab and the site
read it. To add games: Steven queues them from the Games tab on his drive
(they land in `_ClaudeWorkspace\library-to-publish\`), then Claude copies that
folder off the drive and runs
`python3 tools/publish_library.py <copy of library-to-publish> .`
Check every game may be shared first: homebrew, freeware, fan-made, his own.
Files over 45 MB are listed in `library/big-files.txt` and go up as assets on a
Release tagged `library`.
