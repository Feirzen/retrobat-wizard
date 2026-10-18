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
| test-savetransfer.ps1 | Export / import every save in one file | 11 |
