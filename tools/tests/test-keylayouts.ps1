# KeyLayouts.ps1 (2026-10-25): a game's default layout plus each person's own.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'KeyLayouts.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('kl-' + [guid]::NewGuid().ToString('N'))
$Ws = Join-Path $T '_Wizard'
New-Item -ItemType Directory -Path (Join-Path $Ws 'People'), (Join-Path $Ws 'Settings') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $Ws 'Settings\flash-games.ini'), "; flash games`n[Learn To Fly 3.swf]`nname      = Learn to Fly 3`nkeys      = A:Space, B:Z`n`n[Other.swf]`nname = Other`n")
[System.IO.File]::WriteAllText((Join-Path $Ws 'People/profile.ini'), "id = steven1`nusername = Steven`n")
Check 'person read' ((Get-KlPersonId $Ws) -eq 'steven1')
$l = Get-KlLayout $Ws 'Learn To Fly 3.swf'
Check 'default used' ($l.From -eq 'default' -and $l.Keys -eq 'A:Space, B:Z')
Check 'readable' ((Format-KlLayout $l) -eq 'A = Space,   B = Z')
Set-KlLayout $Ws 'Learn To Fly 3.swf' 'Learn to Fly 3' 'A:Enter' 'arrows' 'steven1'
$l = Get-KlLayout $Ws 'Learn To Fly 3.swf'
Check 'mine wins' ($l.From -eq 'mine' -and $l.Keys -eq 'A:Enter' -and $l.Stick -eq 'arrows')
Check 'default untouched' ((Get-KlDefault $Ws 'Learn To Fly 3.swf').Keys -eq 'A:Space, B:Z')
Check 'someone else gets the default' ((Get-KlLayout $Ws 'Learn To Fly 3.swf' 'friend22').From -eq 'default')
[System.IO.File]::WriteAllText((Join-Path $Ws 'People/profile.ini'), "guest = yes`n")
Check 'guest gets the default' ((Get-KlLayout $Ws 'Learn To Fly 3.swf').From -eq 'default')
Set-KlLayout $Ws 'Other.swf' 'Other' 'X:C' '' 'default'
$txt = [System.IO.File]::ReadAllText((Join-Path $Ws 'Settings\flash-games.ini'))
Check 'default written in its own section' ($txt -match '\[Other\.swf\]\s+name = Other\s+keys\s+= X:C')
Check 'comment kept' ($txt.StartsWith('; flash games'))
Set-KlLayout $Ws 'Learn To Fly 3.swf' '' '' '' 'steven1'
Check 'mine cleared: back to default' ((Get-KlLayout $Ws 'Learn To Fly 3.swf' 'steven1').From -eq 'default')
Set-KlLayout $Ws 'New Game.bat' 'New Game' 'A:Space' '' 'default'
Check 'new PC game default goes to browser-games.ini' ((Read-KlSection (Join-Path $Ws 'Settings\browser-games.ini') 'New Game.bat').Keys -eq 'A:Space')
Check 'no layout: nothing' ((Get-KlLayout $Ws 'Nothing.swf' '').From -eq '')
Remove-Item $T -Recurse -Force
Write-Host ("key layout tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
