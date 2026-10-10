# RetroBat Wizard

A setup wizard for a portable RetroBat drive, built around Nintendo, party and co-op games.

This repo is where the wizard **updates itself from**. A drive running the wizard reads
`latest.ini`, and when someone presses **Update now** it downloads only the files that
changed, checks each one against `manifest.txt`, installs them, and keeps the old ones so
**Go back one update** can undo it.

- `latest.ini` the newest version, its tag, and the notes shown in the wizard
- `manifest.txt` every file an update owns, with its SHA-256, size and path
- `drive/` those files, laid out as they sit in `RetroBat\_ClaudeWorkspace\`

Nothing here touches saves, games, settings anyone typed, or the personal pack.
No ROMs, BIOS files or emulators are kept here.
