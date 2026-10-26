# 3.2: games of several files and folder games, published and downloaded
# back, plus adding to a queue that is already running.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')
. (Join-Path $Scripts 'AdminEngine.ps1')
. (Join-Path $Scripts 'GameLibrary.ps1')
$port = 18767
$srv = Start-Process python3 -ArgumentList @((Join-Path $PSScriptRoot 'fake_github.py'), $port) -PassThru
Start-Sleep -Milliseconds 800
function New-Bytes([string]$Path, [int]$N, [int]$Seed) { $b = New-Object byte[] $N; (New-Object Random $Seed).NextBytes($b); [void](New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force); [IO.File]::WriteAllBytes($Path, $b) }
try {
    $script:AdminApiBase = "http://127.0.0.1:$port"; $script:AdminUploadBase = "http://127.0.0.1:$port"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('sets' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $ws = Join-Path $tmp 'RetroBat/_Wizard'
    New-Item -ItemType Directory -Path (Join-Path $ws 'People/social') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $ws 'People/social/social-token.txt'), 'github_pat_SOCIAL')
    [void](Set-AdminLibKey $ws 'github_pat_TEST')
    $psx = Join-Path $tmp 'RetroBat/roms/psx'
    $ps3 = Join-Path $tmp 'RetroBat/roms/ps3'

    # --- finding a game's files ---
    New-Bytes "$psx/Hero (Track 1).bin" 70000 1
    New-Bytes "$psx/Hero (Track 2).bin" 30000 2
    [IO.File]::WriteAllLines("$psx/Hero.cue", @('FILE "Hero (Track 1).bin" BINARY', '  TRACK 01 MODE2/2352', 'FILE "Hero (Track 2).bin" BINARY', '  TRACK 02 AUDIO'))
    $gs = Get-LibGameSet "$psx/Hero.cue" $psx
    Assert ($gs.Ok -and @($gs.Files).Count -eq 3) ('cue finds its tracks: ' + $gs.Message)
    Assert ($gs.Files[0].Name -eq 'Hero.cue' -and $gs.Files[1].Name -eq 'Hero (Track 1).bin') 'cue first, names inside the console folder'
    New-Bytes "$psx/Saga/Saga (Disc 1).bin" 40000 3
    New-Bytes "$psx/Saga/Saga (Disc 2).bin" 41000 4
    [IO.File]::WriteAllLines("$psx/Saga/Saga (Disc 1).cue", @('FILE "Saga (Disc 1).bin" BINARY'))
    [IO.File]::WriteAllLines("$psx/Saga/Saga (Disc 2).cue", @('FILE "Saga (Disc 2).bin" BINARY'))
    [IO.File]::WriteAllLines("$psx/Saga.m3u", @('# discs', 'Saga/Saga (Disc 1).cue', 'Saga/Saga (Disc 2).cue'))
    $gm = Get-LibGameSet "$psx/Saga.m3u" $psx
    Assert ($gm.Ok -and @($gm.Files).Count -eq 5) 'm3u finds its discs and their tracks'
    Assert (@($gm.Files.Name) -contains 'Saga/Saga (Disc 2).bin') 'a file in a folder keeps its folder, with /'
    [IO.File]::WriteAllLines("$psx/Broken.cue", @('FILE "Gone.bin" BINARY'))
    $gb = Get-LibGameSet "$psx/Broken.cue" $psx
    Assert (-not $gb.Ok -and $gb.Message -like '*Gone.bin*') 'a missing track is named'
    [IO.File]::WriteAllLines("$psx/Out.cue", @('FILE "../outside.bin" BINARY'))
    New-Bytes "$tmp/RetroBat/roms/outside.bin" 10 9
    Assert (-not (Get-LibGameSet "$psx/Out.cue" $psx).Ok) 'a track outside the console folder is refused'
    New-Bytes "$ps3/Quest.ps3/PS3_GAME/USRDIR/EBOOT.BIN" 50000 5
    New-Bytes "$ps3/Quest.ps3/PS3_GAME/PARAM.SFO" 900 6
    New-Bytes "$ps3/Quest.ps3/PS3_DISC.SFB" 0 7

    Assert (Test-LibRelName 'Saga/Saga (Disc 1).bin') 'name check: folder/file ok'
    Assert (-not (Test-LibRelName '../x.bin') -and -not (Test-LibRelName '.hidden/x') -and -not (Test-LibRelName 'a//b') -and -not (Test-LibRelName 'a\b')) 'name check: climbing out, dots, empty parts, backslash refused'

    # --- publishing: a queue that grows while it runs ---
    $sync = [hashtable]::Synchronized(@{ Stage = ''; Percent = 0; Prefix = ''; Current = 0; Skip = [hashtable]::Synchronized(@{}) })
    $queue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    [void]$queue.Add(@{ File = "$psx/Hero.cue"; System = 'psx'; Title = 'Hero'; Players = '1'; Description = 'Cue.'; Art = ''; MainName = 'Hero.cue'; Extra = @($gs.Files | Select-Object -Skip 1) })
    $grow = { param($s) }   # the window adds while it runs: simulated by adding before the 2nd pass
    $realOne = ${function:Publish-AdminLibraryGame}
    $script:added = $false
    function Publish-AdminLibraryGame { $r = & $realOne @args; if (-not $script:added) { $script:added = $true
        [void]$queue.Add(@{ File = "$psx/Saga.m3u"; System = 'psx'; Title = 'Saga'; Players = '1'; Description = ''; Art = ''; MainName = 'Saga.m3u'; Extra = @($gm.Files | Select-Object -Skip 1) })
        [void]$queue.Add(@{ File = "$ps3/Quest.ps3"; System = 'ps3'; Title = 'Quest'; Players = '1-4'; Description = 'Folder.'; Art = ''; Folder = "$ps3/Quest.ps3" }) }
        return $r }
    $res = Publish-AdminLibraryGames $ws $queue $sync
    Remove-Item function:Publish-AdminLibraryGame; ${function:Publish-AdminLibraryGame} = $realOne
    Assert ($res.Ok -and @($res.Done).Count -eq 3) ('games added while running are published too: ' + $res.Message)
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state"
    $hero = @($st.library.games | Where-Object id -eq 'hero')[0]
    Assert (@($hero.files).Count -eq 3 -and $hero.files[0].name -eq 'Hero.cue' -and $hero.min -eq '3.2.0') 'cue game listed with all its files and the minimum version'
    $saga = @($st.library.games | Where-Object id -eq 'saga')[0]
    Assert (@($saga.files.name) -contains 'Saga/Saga (Disc 1).cue') 'files in folders listed with /'
    $quest = @($st.library.games | Where-Object id -eq 'quest')[0]
    Assert ($null -ne $quest -and @($quest.files).Count -eq 0 -and $quest.bundle.folder -eq 'Quest.ps3' -and $quest.bundle.url -like 'private:quest__*') 'folder game listed as a bundle'
    Assert (-not (Test-Path (Join-Path $ws 'Cache/library/packing/quest.zip'))) 'the pack is deleted after it went up'
    $used = Get-AdminLibUsedNames $st.library.games
    Assert (@($st.assets | Where-Object { -not $used.ContainsKey($_) }).Count -eq 0) ('every upload is in use, none left over: ' + (@($st.assets) -join ','))

    # publishing the cue game again sends nothing twice
    $up0 = $st.uploads
    $r2 = Publish-AdminLibraryGame $ws "$psx/Hero.cue" 'psx' 'Hero' '1' 'Cue.' $sync '' @($gs.Files | Select-Object -Skip 1) 'Hero.cue'
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state"
    Assert ($r2.Ok -and $st.uploads -eq $up0) ('same game again: no file sent twice (' + $st.uploads + ')')

    # --- downloading them back on another drive ---
    $gh = Join-Path $tmp 'gh'; New-Item -ItemType Directory -Path $gh | Out-Null
    [IO.File]::WriteAllText("$gh/library.json", ($st.library | ConvertTo-Json -Depth 10))
    $script:LibFetchOverride = { param($Url, $Out) if ($Url -like '*library.json*') { Copy-Item "$gh/library.json" $Out -Force } elseif ($Url -like 'private:*') { Invoke-WebRequest ("http://127.0.0.1:$port/blob/" + [Uri]::EscapeDataString($Url.Substring(8))) -OutFile $Out } else { throw "404 $Url" } }
    $ws2 = Join-Path $tmp 'Other/_Wizard'; New-Item -ItemType Directory -Path $ws2 -Force | Out-Null
    $r2psx = Join-Path $tmp 'Other/roms/psx'; $r2ps3 = Join-Path $tmp 'Other/roms/ps3'
    $sys = @([pscustomobject]@{ Name = 'psx'; Folder = $r2psx }, [pscustomobject]@{ Name = 'ps3'; Folder = $r2ps3 })
    $c = Get-LibCatalog $ws2
    Assert ($c.Ok -and @($c.Games | Where-Object Id -in 'hero', 'saga', 'quest').Count -eq 3) 'all three show in the list'
    foreach ($id in 'hero', 'saga', 'quest') {
        $g = @($c.Games | Where-Object Id -eq $id)[0]
        Assert (-not (Test-LibGameInstalled $g $sys)) "$id not there yet"
        $ir = Install-LibGame $ws2 $g $sys
        Assert $ir.Ok ("$id installs: " + $ir.Message)
        Assert (Test-LibGameInstalled $g $sys) "$id counts as installed"
    }
    Assert ((Get-FileHash "$r2psx/Saga/Saga (Disc 2).bin").Hash -eq (Get-FileHash "$psx/Saga/Saga (Disc 2).bin").Hash) 'disc in its folder, same bytes'
    Assert ((Get-FileHash "$r2ps3/Quest.ps3/PS3_GAME/USRDIR/EBOOT.BIN").Hash -eq (Get-FileHash "$ps3/Quest.ps3/PS3_GAME/USRDIR/EBOOT.BIN").Hash) 'folder game unpacked, same bytes'
    Assert ((Test-Path "$r2ps3/Quest.ps3/PS3_DISC.SFB") -and -not (Test-Path "$r2ps3/Quest.ps3.unpacking")) 'empty file kept, nothing half-done left'
    Assert (@(Get-ChildItem (Join-Path $ws2 'Cache/library/downloads') -File).Count -eq 0) 'downloads folder left empty'

    # --- a wizard older than 3.2 leaves these out (no half games) ---
    $old = $st.library.games | Where-Object { $_.id -in 'saga', 'quest' }
    Assert (@($old | Where-Object { @($_.files | Where-Object { $_.name -match '[\\/]' }).Count -gt 0 -or @($_.files).Count -eq 0 }).Count -eq 2) 'saga has a / name and quest no files: 3.1 skips both'

    # --- a pack that tries to climb out is refused ---
    $evil = Join-Path $tmp 'evil.zip'
    Add-Type -AssemblyName System.IO.Compression; Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::Open($evil, 'Create'); $e = $z.CreateEntry('../../escape.txt'); $w = New-Object IO.StreamWriter($e.Open()); $w.Write('x'); $w.Close(); $z.Dispose()
    $u = Expand-LibBundle $evil (Join-Path $tmp 'unpack/Game.ps3')
    Assert (-not $u.Ok -and -not (Test-Path (Join-Path $tmp 'escape.txt')) -and -not (Test-Path (Join-Path $tmp 'unpack/Game.ps3'))) 'zip names climbing out are refused, nothing left'
}
finally {
    $script:LibFetchOverride = $null
    try { Stop-Process -Id $srv.Id -Force } catch { }
    try { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Write-Host ("library sets tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
