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
