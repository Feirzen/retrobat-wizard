# SaveTransfer.ps1 (2026-10-17): export all saves to one file, import them back.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'SaveTransfer.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
function Put([string]$p, [string]$t) { New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null; [System.IO.File]::WriteAllText($p, $t) }
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('st-' + [guid]::NewGuid().ToString('N'))
$A = Join-Path $T 'A'; $B = Join-Path $T 'B'
Put "$A/saves/n64/zelda.srm" 'link'
Put "$A/saves/wii/dolphin-emu/User/Wii/title/00010000/abcd/data/save.bin" 'wii save'
Put "$A/saves/wii/dolphin-emu/User/Wii/title/00000001/00000002/content/title.tmd" 'NINTENDO MENU'
Put "$A/saves/psx/Cache/junk.bin" 'cache'
$zipF = Join-Path $T 'mine.zip'
$r = Export-RetroBatSaves $A $zipF
Check 'export ok' $r.Ok
Check 'two files packed (no Wii Menu, no cache)' ($r.Files -eq 2)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($zipF); $names = @($z.Entries | ForEach-Object FullName); $z.Dispose()
Check 'has the label file' ($names -contains 'retrobat-saves.txt')
Check 'no Wii Menu inside' (-not ($names -match '00000001'))
# B has an older zelda save and one of its own
Put "$B/saves/n64/zelda.srm" 'old'
Put "$B/saves/gba/pokemon.sav" 'mine'
$WsB = Join-Path $B '_ClaudeWorkspace'
$i = Import-RetroBatSaves $B $WsB $zipF
Check 'import ok' $i.Ok
Check 'zelda replaced' ([System.IO.File]::ReadAllText("$B/saves/n64/zelda.srm") -eq 'link')
Check 'wii save arrived' (Test-Path "$B/saves/wii/dolphin-emu/User/Wii/title/00010000/abcd/data/save.bin")
Check 'own other save kept' ([System.IO.File]::ReadAllText("$B/saves/gba/pokemon.sav") -eq 'mine')
Check 'safety copy made' (Test-Path $i.Undo)
# undo: import the safety copy
$u = Import-RetroBatSaves $B $WsB $i.Undo
Check 'undo ok' ($u.Ok -and [System.IO.File]::ReadAllText("$B/saves/n64/zelda.srm") -eq 'old')
# a random zip is refused
$bad = Join-Path $T 'bad.zip'
$zz = [System.IO.Compression.ZipFile]::Open($bad, 'Create'); [void]$zz.CreateEntry('saves/n64/x.srm'); $zz.Dispose()
Check 'foreign zip refused' (-not (Import-RetroBatSaves $B $WsB $bad).Ok)
Remove-Item $T -Recurse -Force
Write-Host ("save transfer tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
