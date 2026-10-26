# 3.2: the missing games finder (Health page).
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'GameLibrary.ps1')
. (Join-Path $Scripts 'MissingGames.ps1')
$R = Join-Path ([IO.Path]::GetTempPath()) ('mg' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$Ws = Join-Path $R '_Wizard'
function Put([string]$P, [string]$T = 'x') { [void](New-Item -ItemType Directory -Path (Split-Path $P -Parent) -Force); [IO.File]::WriteAllText($P, $T) }
try {
    Put "$R/emulationstation/.emulationstation/es_systems.cfg" @'
<systemList>
 <system><name>snes</name><fullname>Super Nintendo</fullname><path>~\..\roms\snes</path><extension>.sfc .smc .zip</extension></system>
 <system><name>n64</name><fullname>Nintendo 64</fullname><path>~\..\roms\n64</path><extension>.z64 .n64 .v64</extension></system>
 <system><name>psx</name><fullname>PlayStation</fullname><path>~\..\roms\psx</path><extension>.cue .m3u .chd</extension></system>
 <system><name>ps3</name><fullname>PlayStation 3</fullname><path>~\..\roms\ps3</path><extension>.ps3 .iso</extension></system>
</systemList>
'@
    Put "$R/roms/snes/Good.sfc"
    Put "$R/roms/snes/Mario 64.z64"            # wrong folder: belongs in n64
    Put "$R/roms/snes/Odd.qqq"                 # nobody reads it
    Put "$R/roms/snes/readme.txt"              # never a game
    Put "$R/roms/snes/images/Good-image.png"   # art folder
    Put "$R/roms/snes/Secret.sfc"
    Put "$R/roms/snes/Bad Game.sfc"
    Put "$R/roms/snes/gamelist.xml" "<gameList>`n  <game>`n    <path>./Secret.sfc</path>`n    <name>Secret</name>`n    <hidden>true</hidden>`n  </game>`n  <game>`n    <path>./Bad Game.sfc</path>`n    <name>Bad Game</name>`n    <hidden>true</hidden>`n  </game>`n</gameList>`n"
    Put "$Ws/Settings/family-hidden.txt" "; x`nsnes|./Bad Game.sfc`n"
    Put "$R/roms/psx/Hero.cue" 'FILE "Hero.bin" BINARY'
    Put "$R/roms/psx/Hero.bin"                 # a track: part of Hero.cue
    Put "$R/roms/ps3/Quest.ps3/PS3_GAME/USRDIR/EBOOT.BIN"   # inside a folder game
    Put "$R/roms/Loose.n64"                    # loose in roms
    Put "$R/roms/gc/Game.iso"                  # folder no console uses
    Put "$R/roms/empty/notes.txt"              # unknown folder, nothing in it that could be a game

    $found = Find-MissingGames $R $Ws
    $by = @{}; foreach ($i in $found.Items) { $by[$i.Show] = $i }
    Assert ($found.Consoles -eq 3) ("three console folders looked at: " + $found.Consoles)
    Assert ($by.ContainsKey('snes\Mario 64.z64') -and $by['snes\Mario 64.z64'].Fix -eq 'move' -and $by['snes\Mario 64.z64'].To -eq 'n64') 'wrong folder: found, moves to n64'
    Assert ($by.ContainsKey('snes\Odd.qqq') -and $by['snes\Odd.qqq'].Fix -eq '' -and $by['snes\Odd.qqq'].Reason -like '*reads .sfc*') 'unknown type: found, says what the console reads, no fix'
    Assert (-not $by.ContainsKey('snes\readme.txt') -and -not $by.ContainsKey('snes\images\Good-image.png')) 'notes and art are not games'
    Assert ($by['snes\Secret.sfc'].Kind -eq 'hidden' -and $by['snes\Secret.sfc'].Fix -eq 'unhide') 'hidden by hand: can be shown'
    Assert ($by['snes\Bad Game.sfc'].Kind -eq 'family' -and $by['snes\Bad Game.sfc'].Fix -eq '') 'hidden by family-friendly: left alone'
    Assert (-not $by.ContainsKey('psx\Hero.bin')) 'a cue''s track is part of its game'
    Assert (-not $by.ContainsKey('ps3\Quest.ps3\PS3_GAME\USRDIR\EBOOT.BIN')) 'the inside of a folder game is not looked at'
    Assert ($by['Loose.n64'].Kind -eq 'loose' -and $by['Loose.n64'].To -eq 'n64') 'loose in roms: found, moves to n64'
    Assert ($by['gc\'].Kind -eq 'nofolder') 'a folder no console uses'
    Assert (-not $by.ContainsKey('empty\')) 'an unknown folder with no possible games is not listed'
    Assert (-not $by.ContainsKey('snes\Good.sfc')) 'a good game is not listed'

    # fixes
    $m = Repair-MissingGame $by['snes\Mario 64.z64']
    Assert ($m.Ok -and (Test-Path "$R/roms/n64/Mario 64.z64") -and -not (Test-Path "$R/roms/snes/Mario 64.z64")) 'move works (folder made)'
    Put "$R/roms/n64/Loose.n64" 'other'
    $m2 = Repair-MissingGame $by['Loose.n64']
    Assert (-not $m2.Ok -and (Test-Path "$R/roms/Loose.n64") -and [IO.File]::ReadAllText("$R/roms/n64/Loose.n64") -eq 'other') 'never replaces a file already there'
    $u = Repair-MissingGame $by['snes\Secret.sfc']
    $t = [IO.File]::ReadAllText("$R/roms/snes/gamelist.xml")
    Assert ($u.Ok -and $t -notmatch '(?s)Secret</name>\s*<hidden>' -and $t -match '(?s)Bad Game</name>\s*<hidden>true') 'unhide shows only that game'
    $found2 = Find-MissingGames $R $Ws
    Assert (@($found2.Items | Where-Object { $_.Show -in 'snes\Secret.sfc', 'snes\Mario 64.z64' }).Count -eq 0) 'fixed ones are gone from the list'
    Assert ((Find-MissingGames (Join-Path $R 'nowhere') $Ws).Message -like '*no roms*') 'no roms folder: plain message'
}
finally { Remove-Item $R -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ("missing games tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
