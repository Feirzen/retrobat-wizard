# Test suites (PowerShell 7, run on Linux or Windows)

Written against a working copy of `_ClaudeWorkspace` at
`/home/claude/work/new/_ClaudeWorkspace`; change the path at the top of each
file (or the `$Scripts` parameter) to point at another copy. Some read real
drive files staged to `/mnt/user-data/uploads/RetroBat/...` (es_settings.cfg,
es_systems.cfg, Dolphin.ini).

| file | covers | assertions |
|---|---|---|
| test-update.ps1 | UpdateEngine + Migrations | 105 |
| test-social.ps1 | SocialEngine (+ AdminEngine lists) against a fake GitHub | 90 |
| test-admin.ps1 | Publish a game, against fake_github.py | 14 |
| test-helper.ps1 | Social-Helper functions | 10 |
| test-bug.ps1 | BugReport | 14 |
| test-netplay.ps1 | NetplayEngine on real settings files | 20 |
| test-games.ps1 | GameLibrary on the real es_systems.cfg | 28 |
