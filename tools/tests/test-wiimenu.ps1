# WiiMenu.ps1 (2026-10-17): bring your own Wii Menu files in, never overwriting.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'WiiMenu.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('wm-' + [guid]::NewGuid().ToString('N'))
$Root = Join-Path $T 'RetroBat'
$src = Join-Path $T 'MyDolphin'
$wii = [System.IO.Path]::Combine($src, 'User', 'Wii')
$tmd = Get-WiiMenuTmd $wii
New-Item -ItemType Directory -Path (Split-Path $tmd -Parent) -Force | Out-Null
'menu' | Set-Content -LiteralPath $tmd
$save = [System.IO.Path]::Combine($wii, 'title', '00010000', 'abcd', 'data', 'banner.bin')
New-Item -ItemType Directory -Path (Split-Path $save -Parent) -Force | Out-Null
'OLD SAVE' | Set-Content -LiteralPath $save
Check 'not installed at first' (-not (Test-WiiMenuInstalled $Root))
Check 'finds it from the Dolphin folder' ((Find-WiiNandRoot $src) -eq $wii)
Check 'finds it from the Wii folder' ((Find-WiiNandRoot $wii) -eq $wii)
Check 'nothing in an empty folder' ((Find-WiiNandRoot $T) -eq '')
# a newer save already on the setup must survive
$mine = [System.IO.Path]::Combine((Get-WiiNandDir $Root), 'title', '00010000', 'abcd', 'data', 'banner.bin')
New-Item -ItemType Directory -Path (Split-Path $mine -Parent) -Force | Out-Null
'MY SAVE' | Set-Content -LiteralPath $mine
$r = Import-WiiNand $Root $src
Check 'import ok' $r.Ok
Check 'one file copied' ($r.Copied -eq 1)
Check 'installed now' (Test-WiiMenuInstalled $Root)
Check 'own save kept' ((Get-Content -LiteralPath $mine) -eq 'MY SAVE')
$r2 = Import-WiiNand $Root $src
Check 'second time copies nothing' ($r2.Ok -and $r2.Copied -eq 0)
Check 'bad folder refused' (-not (Import-WiiNand $Root $T).Ok)
Remove-Item $T -Recurse -Force
Write-Host ("wii menu tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
