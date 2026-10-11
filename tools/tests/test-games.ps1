$ErrorActionPreference='Stop'
. /home/claude/work/new/_ClaudeWorkspace/scripts/GameLibrary.ps1
$pass=0;$fail=0; function A($c,$n){ if($c){$script:pass++}else{$script:fail++;"FAIL $n"} }
$Root = Join-Path ([IO.Path]::GetTempPath()) ('gl-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$Root/emulationstation/.emulationstation","$Root/_ClaudeWorkspace","$Root/in" | Out-Null
Copy-Item /mnt/user-data/uploads/RetroBat/emulationstation/.emulationstation/es_systems.cfg "$Root/emulationstation/.emulationstation/"
$sys = Get-LibSystems $Root
A ($sys.Count -gt 100) "lots of consoles ($($sys.Count))"
A ($sys[0].Name -eq 'nes' -and $sys[1].Name -eq 'snes') "nintendo first ($($sys[0].Name),$($sys[1].Name))"
$nes = @($sys | Where-Object Name -eq 'nes')[0]
A ($nes.Folder -eq [IO.Path]::GetFullPath("$Root/roms/nes")) "nes folder resolves ($($nes.Folder))"
function MakeFile($n, [byte[]]$b) { $p = "$Root/in/$n"; [IO.File]::WriteAllBytes($p, $b); return $p }
$g = Get-LibSystemGuess (MakeFile 'Game.gba' ([byte[]](1..64))) $sys
A ($g.Sure -and $g.Candidates[0].Name -eq 'gba') 'gba sure'
# a zip with a .gbc inside
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zdir = "$Root/z"; New-Item -ItemType Directory $zdir | Out-Null; [IO.File]::WriteAllBytes("$zdir/Pokemon.gbc", [byte[]](1..200))
[IO.Compression.ZipFile]::CreateFromDirectory($zdir, "$Root/in/Pokemon.zip")
$g = Get-LibSystemGuess "$Root/in/Pokemon.zip" $sys
A ($g.Candidates[0].Name -eq 'gbc' -and $g.Sure) "zip -> gbc ($($g.Candidates[0].Name) sure=$($g.Sure))"
# disc magic
$wii = New-Object byte[] 64; $wii[0x18]=0x5D;$wii[0x19]=0x1C;$wii[0x1A]=0x9E;$wii[0x1B]=0xA3
$gc = New-Object byte[] 64; $gc[0x1C]=0xC2;$gc[0x1D]=0x33;$gc[0x1E]=0x9F;$gc[0x1F]=0x3D
$g = Get-LibSystemGuess (MakeFile 'A.iso' $wii) $sys; A ($g.Sure -and $g.Candidates[0].Name -eq 'wii') 'wii iso'
$g = Get-LibSystemGuess (MakeFile 'B.iso' $gc) $sys; A ($g.Sure -and $g.Candidates[0].Name -eq 'gamecube') 'gc iso'
$g = Get-LibSystemGuess (MakeFile 'C.iso' ([byte[]](1..64))) $sys; A (-not $g.Sure -and $g.Candidates.Count -gt 2) 'unknown iso asks'
$g = Get-LibSystemGuess (MakeFile 'D.wbfs' ([byte[]](1..64))) $sys; A ($g.Candidates[0].Name -eq 'wii') 'wbfs wii'
$g = Get-LibSystemGuess (MakeFile 'E.7z' ([byte[]](1..64))) $sys; A (-not $g.Sure) '7z asks'
$g = Get-LibSystemGuess (MakeFile 'F.swf' ([byte[]](1..64))) $sys; A ($g.Candidates[0].Name -eq 'flash' -and $g.Sure) 'swf flash'
$g = Get-LibSystemGuess (MakeFile 'G.xyz' ([byte[]](1..64))) $sys; A ($g.Candidates.Count -eq 0) 'unknown type: no consoles'
# copy
$gba = @($sys | Where-Object Name -eq 'gba')[0]
$r = Add-LibGameFile "$Root/in/Game.gba" $gba; A ($r.Ok -and (Test-Path "$Root/roms/gba/Game.gba")) 'copied'
A (Test-Path "$Root/in/Game.gba") 'original kept'
$r = Add-LibGameFile "$Root/in/Game.gba" $gba; A ($r.Ok -and $r.Message -eq 'Already there.') 'same file not copied twice'
[IO.File]::WriteAllBytes("$Root/in/Game.gba", [byte[]](5..80))
$r = Add-LibGameFile "$Root/in/Game.gba" $gba; A ($r.Ok -and $r.Path -like '*Game (2).gba') 'different file kept beside'
$pcts = New-Object System.Collections.ArrayList
$big = MakeFile 'Big.nds' (New-Object byte[] (9MB))
$r = Add-LibGameFile $big (@($sys | Where-Object Name -eq 'nds')[0]) { param($p) [void]$pcts.Add($p) }
A ($r.Ok -and $pcts.Count -ge 2 -and $pcts[-1] -eq 100) "progress reported ($($pcts -join ','))"
A (@(Get-ChildItem "$Root/roms/nds" -Filter '*.copying').Count -eq 0) 'no leftover .copying'
# library
$gh = "$Root/gh"; New-Item -ItemType Directory -Force "$gh/files" | Out-Null
[IO.File]::WriteAllBytes("$gh/files/Cool Game.nes", [byte[]](1..100))
$sha = (Get-FileHash "$gh/files/Cool Game.nes" -Algorithm SHA256).Hash.ToLower()
$lib = @{ version=1; games=@(
  @{ id='cool-game'; title='Cool Game'; system='nes'; players='1-2'; description='A homebrew'; files=@(@{ name='Cool Game.nes'; url='https://raw.githubusercontent.com/Feirzen/retrobat-wizard/main/library/files/Cool%20Game.nes'; size=100; sha256=$sha }) },
  @{ id='evil'; title='Evil'; system='nes'; files=@(@{ name='..\x.nes'; url='https://raw.githubusercontent.com/x'; size=1; sha256=$sha }) },
  @{ id='evil2'; title='Evil2'; system='nes'; files=@(@{ name='x.nes'; url='https://evil.example.com/x'; size=1; sha256=$sha }) },
  @{ id='bad'; title='Bad'; system='../nes'; files=@(@{ name='x.nes'; url='https://raw.githubusercontent.com/x'; size=1; sha256=$sha }) },
  @{ id='priv'; title='Priv Game'; system='nes'; files=@(@{ name='Priv.nes'; url='private:priv__Priv.nes'; size=100; sha256=$sha }) },
  @{ id='evil3'; title='Evil3'; system='nes'; files=@(@{ name='y.nes'; url='private:../y.nes'; size=1; sha256=$sha }) }
)} | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText("$gh/library.json", $lib)
$script:LibFetchOverride = { param($Url,$Out) if ($script:libDown) { throw 'offline' }; if ($Url -like '*library.json*') { Copy-Item "$gh/library.json" $Out -Force } elseif ($Url -like '*Cool%20Game.nes' -or $Url -eq 'private:priv__Priv.nes') { Copy-Item "$gh/files/Cool Game.nes" $Out -Force } else { throw "404 $Url" } }
$script:libDown = $false
$c = Get-LibCatalog "$Root/_ClaudeWorkspace"
A ($c.Ok -and @($c.Games).Count -eq 2 -and $c.Games[0].Title -eq 'Cool Game') "only the safe entries kept ($(@($c.Games).Count))"
$pg = @($c.Games | Where-Object Id -eq 'priv')[0]
A ($null -ne $pg -and $pg.Files[0].Url -eq 'private:priv__Priv.nes') 'private file listed by name'
$r = Install-LibGame "$Root/_ClaudeWorkspace" $pg $sys
A ($r.Ok -and (Test-Path "$Root/roms/nes/Priv.nes")) "private game installs: $($r.Message)"
A (-not (Test-LibGameInstalled $c.Games[0] $sys)) 'not installed yet'
$r = Install-LibGame "$Root/_ClaudeWorkspace" $c.Games[0] $sys
A ($r.Ok -and (Test-Path "$Root/roms/nes/Cool Game.nes")) "installed: $($r.Message)"
A (Test-LibGameInstalled $c.Games[0] $sys) 'now installed'
# tampered download refused
[IO.File]::WriteAllBytes("$gh/files/Cool Game.nes", [byte[]](9..108))
Remove-Item "$Root/roms/nes/Cool Game.nes"
$r = Install-LibGame "$Root/_ClaudeWorkspace" $c.Games[0] $sys
A (-not $r.Ok -and $r.Message -match 'checksum' -and -not (Test-Path "$Root/roms/nes/Cool Game.nes")) 'bad checksum refused'
$script:libDown = $true
$c = Get-LibCatalog "$Root/_ClaudeWorkspace"
A ($c.Ok -and $c.FromCache -and @($c.Games).Count -eq 2) 'offline uses cache'
# a private file with no friends key on the drive: a plain message, no crash
$script:LibFetchOverride = $null
$caught = ''
try { Invoke-LibFetch 'private:x.nes' "$Root/x.part" "$Root/_ClaudeWorkspace" } catch { $caught = $_.Exception.Message }
A ($caught -like '*no friends key*') "private without key: plain words ($caught)"
# publish entry
New-Item -ItemType Directory "$Root/_ClaudeWorkspace/library-to-publish" | Out-Null
A (Test-LibCanPublish "$Root/_ClaudeWorkspace") 'owner can publish'
$r = New-LibPublishEntry "$Root/_ClaudeWorkspace" "$Root/in/Game.gba" 'gba' "Fireboy & Watergirl: Forest Temple!" '1-2' "Co-op`npuzzles"
A ($r.Ok -and (Test-Path "$($r.Folder)/Game.gba") -and (Split-Path -Leaf $r.Folder) -eq 'fireboy-watergirl-forest-temple') "publish entry ($(Split-Path -Leaf $r.Folder))"
$ini = Get-Content "$($r.Folder)/game.ini"
A (($ini -match '^description = Co-op puzzles$').Count -eq 1) 'description one line'
$r2 = New-LibPublishEntry "$Root/_ClaudeWorkspace" "$Root/in/Game.gba" 'gba' "Fireboy & Watergirl: Forest Temple!" '' ''
A (-not $r2.Ok) 'no double queue'
# what RetroBat knows (gamelist.xml): name, players, words, box art; sub-folders too (2026-10-11)
$wiiS = @($sys | Where-Object Name -eq 'wii')[0]
New-Item -ItemType Directory -Force (Join-Path $wiiS.Folder 'Party Game'), (Join-Path $wiiS.Folder 'images') | Out-Null
$pf = Join-Path $wiiS.Folder 'Party Game/game.rvz'; [IO.File]::WriteAllBytes($pf, [byte[]](1,2))
[IO.File]::WriteAllBytes((Join-Path $wiiS.Folder 'images/party-image.png'), [byte[]](1,2))
[IO.File]::WriteAllText((Join-Path $wiiS.Folder 'gamelist.xml'), '<?xml version="1.0"?><gameList><game><path>./Party Game/game.rvz</path><name>Party Game</name><players>1-4</players><desc>Fun.</desc><image>./images/party-image.png</image><thumbnail>./images/missing.png</thumbnail></game><game><path>./plain.wbfs</path><name>Plain</name><image>./images/none.png</image></game></gameList>')
$i = Get-LibGamelistInfo $wiiS $pf
A ($i.Title -eq 'Party Game' -and $i.Players -eq '1-4' -and $i.Description -eq 'Fun.') "gamelist details in a sub-folder ($($i.Title))"
A ($i.Art -eq (Join-Path $wiiS.Folder 'images/party-image.png')) "box art found ($($i.Art))"
$i = Get-LibGamelistInfo $wiiS (Join-Path $wiiS.Folder 'plain.wbfs')
A ($i.Title -eq 'Plain' -and $i.Art -eq '') 'missing picture: no art'
$i = Get-LibGamelistInfo $wiiS (Join-Path $wiiS.Folder 'unknown.wbfs')
A ($i.Title -eq 'unknown' -and $i.Art -eq '') 'not in the list: file name, no art'
Remove-Item -Recurse -Force $Root
"games tests: $pass passed, $fail failed"
