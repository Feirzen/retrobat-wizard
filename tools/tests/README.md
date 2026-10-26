# Test suites (PowerShell 7, run on Linux or Windows)

Written against a working copy of `_ClaudeWorkspace` at
`/home/claude/work/new/_ClaudeWorkspace`; change the path at the top of each
file (or the `$Scripts` parameter) to point at another copy. Some read real
drive files staged to `/mnt/user-data/uploads/RetroBat/...` (es_settings.cfg,
es_systems.cfg, Dolphin.ini).

| file | covers | assertions |
|---|---|---|
| test-update.ps1 | UpdateEngine + Migrations | 105 |
| test-channels.ps1 | Stable / Dev update channels (switching, go back, republished dev) | 39 |
| test-play-together.ps1 | Favorites, invites, incognito, more than one person per drive, helper banners | 70 |
| test-social.ps1 | SocialEngine (+ AdminEngine lists) against a fake GitHub | 90 |
| test-admin.ps1 | Publish a game (files private, list public), against fake_github.py | 15 |
| test-helper.ps1 | Social-Helper functions | 10 |
| test-bug.ps1 | BugReport | 14 |
| test-netplay.ps1 | NetplayEngine on real settings files | 20 |
| test-games.ps1 | GameLibrary on the real es_systems.cfg (+ private library files) | 31 |
| test-flash.ps1 | FlashArtwork (Flash shelf names and pictures) | 21 |
| test-firstrun.ps1 | FirstRunDefaults (new setup RetroBat settings, shared scraper login) | 20 |
| test-wiimenu.ps1 | WiiMenu (bring your own Wii Menu, never overwriting saves) | 10 |
| test-playtime.ps1 | Play time and favourites per person (SocialEngine ledgers) | 19 |
| test-savetransfer.ps1 | Export / import every save in one file (installed games and updates left out) | 16 |
| test-separatesaves.ps1 | Separate saves per person: one switch at a time (race test), owner record, never moves a folder with saves into the way. Off for 3.1 | 48 |
| test-adminpack.ps1 | Admin tools as their own download (admin-manifest.txt, checksums, refresh after an update, workshop guard) | 32 |
| test-family.ps1 | Family-friendly filter (loose name matching, hide and show again, hand-hidden games left alone) | 26 |
| test-keylayouts.ps1 | Keyboard game layouts (game default plus each person's own) | 12 |
| test-libdupes.ps1 | No game listed twice: renamed republish replaces, same file name but different game kept, tidy after a queue | 13 |
