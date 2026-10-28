# The "Launch game?" screen (LaunchMenu.ps1, 2026-10-12) against copies of
# the drive's real es_savestates.cfg and es_systems.cfg.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'), [string]$Real = '/mnt/user-data/uploads/RetroBat/emulationstation/.emulationstation')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function A($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'LaunchMenu.ps1')
$TR = Join-Path ([IO.Path]::GetTempPath()) ('lm' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$es = Join-Path $TR 'emulationstation/.emulationstation'
New-Item -ItemType Directory -Force $es, (Join-Path $TR '_Wizard/Backups/Archive') | Out-Null
Copy-Item (Join-Path $Real 'es_savestates.cfg'), (Join-Path $Real 'es_systems.cfg') $es
$before = [IO.File]::ReadAllText((Join-Path $es 'es_savestates.cfg'))
function Names { [xml]$x = [IO.File]::ReadAllText((Join-Path $es 'es_savestates.cfg')); return @($x.savestates.emulator | ForEach-Object { $_.name }) }

$emus = Get-LaunchMenuEmulators $TR
A ($emus -contains 'ruffle' -and $emus -contains 'arcadeflashweb' -and $emus -contains 'xemu' -and $emus -contains 'cxbx') 'Flash and Xbox emulators found in es_systems.cfg'
$r = Update-LaunchMenu -Root $TR -On $true
$n = Names
A ($r.Ok -and @($r.Added).Count -gt 100) ('added ' + @($r.Added).Count)
A ($n -contains 'ruffle' -and $n -contains 'xemu' -and $n -contains 'cxbx' -and $n -contains 'arcadeflashweb') 'Flash and Xbox now listed'
[xml]$x = [IO.File]::ReadAllText((Join-Path $es 'es_savestates.cfg'))
$lib = @($x.savestates.emulator | Where-Object name -eq 'libretro')[0]
A ($lib.directory -eq '{{system}}/libretro.{{core}}') 'RetroArch entry untouched'
A ((@($x.savestates.emulator | Where-Object name -eq 'xemu')[0]).directory -eq '{{system}}/xemu') 'our entry points at an empty folder'
A (@(Get-ChildItem (Join-Path $TR '_Wizard/Backups/Archive') -Directory).Count -eq 1) 'backup made'
$r2 = Update-LaunchMenu -Root $TR -On $true
A ($r2.Ok -and @($r2.Added).Count -eq 0 -and $r2.Backup -eq '') 'second run writes nothing'
$r3 = Update-LaunchMenu -Root $TR -On $false
$n3 = Names
A ($r3.Ok -and $n3 -notcontains 'xemu' -and $n3 -contains 'libretro' -and $n3 -contains 'dolphin') 'off: ours out, RetroBat''s kept'
A ($n3 -notcontains 'azahar') 'off: an old entry in our shape goes too'
$r4 = Update-LaunchMenu -Root $TR -On $true
A ((Names) -contains 'ruffle') 'on again'
[IO.File]::WriteAllText((Join-Path $es 'es_savestates.cfg'), 'not xml')
A (-not (Update-LaunchMenu -Root $TR -On $true).Ok) 'unreadable file: left alone'
A ([IO.File]::ReadAllText((Join-Path $es 'es_savestates.cfg')) -eq 'not xml') 'unreadable file: not overwritten'
Remove-Item -Recurse -Force $TR
Write-Host ("launch menu tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
