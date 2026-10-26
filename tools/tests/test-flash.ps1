param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0; function A($c, $n) { if ($c) { $script:pass++ } else { $script:fail++; "FAIL: $n" } }
. (Join-Path $Scripts 'SteamArtwork.ps1')
. (Join-Path $Scripts 'FlashArtwork.ps1')
$R = Join-Path ([IO.Path]::GetTempPath()) ('fa' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force "$R/roms/flash", "$R/_Wizard/Settings" | Out-Null
Copy-Item /home/claude/work/new/_ClaudeWorkspace/flash-games.ini "$R/_Wizard/Settings/"
foreach ($f in @('Age_of War.swf', 'Bloons TD5.swf', 'Raft Wars.swf', 'Duck Life 4.swf', "Bob's Game.swf")) { [IO.File]::WriteAllBytes("$R/roms/flash/$f", [byte[]](1..10)) }
$g = @(Read-FlashGames "$R/_Wizard/Settings/flash-games.ini")
A ($g.Count -eq 11) "11 games read ($($g.Count))"
A (($g | Where-Object File -eq 'Bloons TD5.swf').Steam -eq 'Bloons TD 5') 'steam name read'
$png = [byte[]](0x89, 0x50, 0x4E, 0x47) + [byte[]](1..200); $jpg = [byte[]](0xFF, 0xD8) + [byte[]](1..200)
$script:urls = @()
$script:FaTextOverride = { param($u) if ($u -like '*storesearch*Bloons*') { '{"total":2,"items":[{"id":1,"name":"Bloons TD 6"},{"id":306020,"name":"Bloons TD 5"}]}' } elseif ($u -like '*storesearch*') { '{"total":1,"items":[{"id":9,"name":"Duck Life: Battle"}]}' } else { '' } }
$script:FaFetchOverride = { param($u, $o) $script:urls += $u; if ($u -like '*archive.org*') { [IO.File]::WriteAllBytes($o, $png) } elseif ($u -like '*306020*') { [IO.File]::WriteAllBytes($o, $jpg) } else { throw 'nope' } }
$res = Invoke-FlashArtwork -Root $R
A $res.Ok "runs: $($res.Message)"
$img = "$R/roms/flash/images"
A (Test-Path "$img/Bloons TD5-image.jpg") 'steam banner'
A (Test-Path "$img/Bloons TD5-marquee.png") 'steam logo'
A (Test-Path "$img/Bloons TD5-thumb.jpg") 'steam box'
A (-not (Test-Path "$img/Bloons TD5-image.png")) 'archive not used when Steam gave it'
A (Test-Path "$img/Raft Wars-image.png") 'archive cover, png by its bytes'
A (Test-Path "$img/Raft Wars-thumb.png") 'archive cover as box art too'
A (Test-Path "$img/Duck Life 4-image.png") 'not on Steam by exact name: archive used'
A (-not (Test-Path "$img/Duck Life 4-marquee.png")) 'no wrong Steam game used'
A (@(Get-ChildItem $img -Filter '*.part').Count -eq 0) 'no leftovers'
[xml]$x = Get-Content "$R/roms/flash/gamelist.xml" -Raw
$games = @($x.gameList.game)
A ($games.Count -eq 4) "only games on the drive written ($($games.Count))"
$b = $games | Where-Object { $_.path -eq './Bloons TD5.swf' }
A ($b.name -eq 'Bloons TD 5' -and $b.marquee -eq './images/Bloons TD5-marquee.png' -and $b.releasedate -eq '20110101T000000') 'entry right'
$aw = $games | Where-Object { $_.path -eq './Age_of War.swf' }
A ($aw.name -eq 'Age of War' -and $null -eq $aw.image) 'no picture: words only'
A ((@($res.Lines) -match 'Bob').Count -eq 0) 'unlisted game left alone'
# hand edit kept, second run downloads nothing
$b.name = 'My BTD'; $x.Save("$R/roms/flash/gamelist.xml")
$script:urls = @()
$res = Invoke-FlashArtwork -Root $R
[xml]$x = Get-Content "$R/roms/flash/gamelist.xml" -Raw
A ((@($x.gameList.game) | Where-Object { $_.path -eq './Bloons TD5.swf' }).name -eq 'My BTD') 'hand-typed name kept'
A (@($script:urls).Count -eq 0) "second run fetches nothing ($(@($script:urls).Count))"
A (@(Get-ChildItem "$R/_Wizard/Backups/Archive" -Directory).Count -ge 1) 'game list backed up'
$res = Invoke-FlashArtwork -Root $R -Force $true
[xml]$x = Get-Content "$R/roms/flash/gamelist.xml" -Raw
A ((@($x.gameList.game) | Where-Object { $_.path -eq './Bloons TD5.swf' }).name -eq 'Bloons TD 5') 'force replaces'
A ($x.OuterXml -notmatch '\.part') 'no part files listed'
Remove-Item -Recurse -Force $R
"flash tests: $pass passed, $fail failed"
