# FirstRunDefaults.ps1 (2026-10-17): the RetroBat settings a new setup starts
# with, and the shared scraper login. Runs on a throwaway fake RetroBat.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'FirstRunDefaults.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
$R = Join-Path ([System.IO.Path]::GetTempPath()) ('frd-' + [guid]::NewGuid().ToString('N'))
$Ws = Join-Path $R '_ClaudeWorkspace'
New-Item -ItemType Directory -Path (Join-Path $R 'emulationstation/.emulationstation') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Ws 'defaults') -Force | Out-Null
Copy-Item (Join-Path (Split-Path $Scripts -Parent) 'defaults/retrobat-defaults.ini') (Join-Path $Ws 'defaults/retrobat-defaults.ini')
$es = Join-Path $R 'emulationstation/.emulationstation/es_settings.cfg'
function Get-Val([string]$k, [string]$name) { [xml]$x = [System.IO.File]::ReadAllText($es); $n = $x.SelectSingleNode("/config/$k[@name='$name']"); if ($null -eq $n) { return $null }; return $n.GetAttribute('value') }

# 1. no es_settings.cfg yet: it is started
$res1 = Set-FirstRunDefaults $R $Ws
Check 'made a settings file' (Test-Path $es)
Check 'ok' $res1.Ok
Check 'music off' ((Get-Val 'bool' 'audio.bgmusic') -eq 'false')
Check 'collections' ((Get-Val 'string' 'CollectionSystemsAuto') -eq '2players,4players,all')
Check 'all games grid' ((Get-Val 'string' 'all.defaultView') -eq 'grid')
Check '2 players grid+details' ((Get-Val 'string' '2players.defaultView') -eq 'Grid + Details')
Check 'ampersand kept' ((Get-Val 'string' 'ScreenSaverGameInfo') -eq 'start & end')
Check 'no scraper login without the file' ($null -eq (Get-Val 'string' 'ScreenScraperUser'))

# 2. second run changes nothing
$r2 = Set-FirstRunDefaults $R $Ws
Check 'second run: nothing to change' ($r2.Changed -eq 0)

# 3. a wrong kind of node is replaced, not duplicated
[System.IO.File]::WriteAllText($es, '<?xml version="1.0"?><config><string name="audio.bgmusic" value="true" /><bool name="EnableSounds" value="false" /></config>')
$null = Set-FirstRunDefaults $R $Ws
[xml]$x = [System.IO.File]::ReadAllText($es)
Check 'one bgmusic node' (@($x.SelectNodes("/config/*[@name='audio.bgmusic']")).Count -eq 1)
Check 'bgmusic is a bool now' ((Get-Val 'bool' 'audio.bgmusic') -eq 'false')
Check 'a backup was made' (@(Get-ChildItem (Join-Path $Ws 'archive') -Directory -ErrorAction SilentlyContinue).Count -ge 1)

# 4. the scraper login: saved from this setup, then used by a new one
[System.IO.File]::WriteAllText($es, '<?xml version="1.0"?><config><string name="ScreenScraperUser" value="someone" /><string name="ScreenScraperPass" value="p4ss|w0rd" /></config>')
$s = Save-FrdScraperFromThisSetup $R $Ws
Check 'saved' $s.Ok
$txt = [System.IO.File]::ReadAllText((Join-Path $Ws 'defaults/scraper.txt'))
Check 'not plain text' ($txt -notmatch 'p4ss')
$sc = Read-FrdScraper $Ws
Check 'reads back user' ($sc.User -eq 'someone')
Check 'reads back pass' ($sc.Pass -eq 'p4ss|w0rd')
[System.IO.File]::WriteAllText($es, '<?xml version="1.0"?><config></config>')
$null = Set-FirstRunDefaults $R $Ws
Check 'new setup gets the user' ((Get-Val 'string' 'ScreenScraperUser') -eq 'someone')
Check 'new setup gets the pass' ((Get-Val 'string' 'ScreenScraperPass') -eq 'p4ss|w0rd')
# 5. a setup with its own login keeps it
[System.IO.File]::WriteAllText($es, '<?xml version="1.0"?><config><string name="ScreenScraperUser" value="mine" /></config>')
$null = Set-FirstRunDefaults $R $Ws
Check 'own login kept' ((Get-Val 'string' 'ScreenScraperUser') -eq 'mine')
# 6. no login in this setup: refuses to save
[System.IO.File]::WriteAllText($es, '<?xml version="1.0"?><config></config>')
Check 'refuses with no login' (-not (Save-FrdScraperFromThisSetup $R $Ws).Ok)

Remove-Item $R -Recurse -Force
Write-Host ("first-run tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
