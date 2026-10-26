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
Put "$A/saves/wiiu/cemu/mlc01/usr/title/0005000e/101c9400/content/big.bin" 'MK8 UPDATE'
Put "$A/saves/wiiu/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/save.dat" 'mk8 save'
Put "$A/saves/3ds/azahar/sdmc/Nintendo 3DS/0000/1111/title/00040000/0012AB00/content/00000000.app" 'GAME'
Put "$A/saves/3ds/azahar/sdmc/Nintendo 3DS/0000/1111/title/00040000/0012AB00/data/00000001/save" '3ds save'
$zipF = Join-Path $T 'mine.zip'
$script:prog = @()
$r = Export-RetroBatSaves $A $zipF '' { param($n, $of) $script:prog += "$n/$of" }
Check 'export ok' $r.Ok
Check 'four files packed (no Wii Menu, no cache, no installed games)' ($r.Files -eq 4)
Check 'progress reported' ($script:prog.Count -ge 1 -and $script:prog[0] -eq '0/4')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($zipF); $names = @($z.Entries | ForEach-Object FullName); $z.Dispose()
Check 'has the label file' ($names -contains 'retrobat-saves.txt')
Check 'no Wii Menu inside' (-not ($names -match 'title/00000001'))
Check 'no Wii U update inside' (-not ($names -match 'usr/title'))
Check 'Wii U save inside' (@($names -match 'usr/save/00050000').Count -eq 1)
Check 'no 3DS game inside' (-not ($names -match '\.app$'))
Check '3DS save inside' (@($names -match '0012AB00/data').Count -eq 1)
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
