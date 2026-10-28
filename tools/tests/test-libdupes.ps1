# 2026-10-26: no game is ever listed twice in the online library. A game
# republished under a new name (so a new id) replaces its old entry; the
# tidy after a queue clears any duplicates and stray uploads.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')
. (Join-Path $Scripts 'AdminEngine.ps1')
. (Join-Path $Scripts 'GameLibrary.ps1')
$port = 18769
$srv = Start-Process python3 -ArgumentList @((Join-Path $PSScriptRoot 'fake_github.py'), $port) -PassThru
Start-Sleep -Milliseconds 800
function New-Bytes([string]$Path, [int]$N, [int]$Seed) { $b = New-Object byte[] $N; (New-Object Random $Seed).NextBytes($b); [void](New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force); [IO.File]::WriteAllBytes($Path, $b) }
try {
    $script:AdminApiBase = "http://127.0.0.1:$port"; $script:AdminUploadBase = "http://127.0.0.1:$port"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dup' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $ws = Join-Path $tmp 'RetroBat/_Wizard'
    New-Item -ItemType Directory -Path (Join-Path $ws 'People/social') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $ws 'People/social/social-token.txt'), 'github_pat_SOCIAL')
    [void](Set-AdminLibKey $ws 'github_pat_TEST')
    $n64 = Join-Path $tmp 'RetroBat/roms/n64'
    New-Bytes "$n64/Kart/Kart.z64" 30000 1
    $art = Join-Path $tmp 'a.png'; New-Bytes $art 500 2
    $vid = Join-Path $tmp 'v.mp4'; New-Bytes $vid 600 3
    $sync = [hashtable]::Synchronized(@{ Stage = ''; Percent = 0; Prefix = ''; Current = 0; Skip = [hashtable]::Synchronized(@{}) })
    function St { Invoke-RestMethod "http://127.0.0.1:$port/state" }

    # the old way: a folder game named after its folder, with art, no video
    $q1 = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    [void]$q1.Add(@{ File = "$n64/Kart"; System = 'n64'; Title = 'Kart'; Players = ''; Description = ''; Art = $art; Folder = "$n64/Kart" })
    $r1 = Publish-AdminLibraryGames $ws $q1 $sync
    $s = St
    Assert ($r1.Ok -and @($s.library.games | Where-Object id -eq 'kart').Count -eq 1) ('first copy up: ' + $r1.Message)
    Assert ($null -ne $s.art.'library/art/kart.png') 'first copy has its art'
    # republished with its real name (new id) and a video
    $q2 = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    [void]$q2.Add(@{ File = "$n64/Kart"; System = 'n64'; Title = 'Super Kart 64'; Players = '1-4'; Description = 'Race.'; Art = $art; Video = $vid; Folder = "$n64/Kart" })
    $r2 = Publish-AdminLibraryGames $ws $q2 $sync
    $s = St
    $karts = @($s.library.games | Where-Object { $null -ne $_.bundle -and $_.bundle.folder -eq 'Kart' })
    Assert ($r2.Ok -and $karts.Count -eq 1 -and $karts[0].id -eq 'super-kart-64') ('one entry, the new one: ' + (@($karts.id) -join ','))
    Assert ($karts[0].video -eq 'library/video/super-kart-64.mp4') 'the new one has its video'
    Assert ($null -eq $s.art.'library/art/kart.png') 'the old copy''s art is gone'
    Assert (@($s.assets | Where-Object { $_ -like 'kart__*' }).Count -eq 0) ('the old copy''s private file is gone: ' + (@($s.assets) -join ','))
    $used = Get-AdminLibUsedNames $s.library.games
    Assert (@($s.assets | Where-Object { -not $used.ContainsKey($_) }).Count -eq 0) 'no stray uploads'
    Assert (@($s.library.games | Where-Object id -eq 'old').Count -eq 1) 'other games left alone'

    # two DIFFERENT games that happen to share a file name both stay
    New-Bytes "$n64/a/game.z64" 1000 5; New-Bytes "$n64/b/game.z64" 1000 6
    $ra = Publish-AdminLibraryGame $ws "$n64/a/game.z64" 'n64' 'Game A' '' '' $sync
    $rb = Publish-AdminLibraryGame $ws "$n64/b/game.z64" 'n64' 'Game B' '' '' $sync
    $s = St
    Assert ($ra.Ok -and $rb.Ok -and @($s.library.games | Where-Object { $_.id -in 'game-a', 'game-b' }).Count -eq 2) 'same file name, different games: both listed'
    # the very same file under a new name replaces it
    $rc = Publish-AdminLibraryGame $ws "$n64/a/game.z64" 'n64' 'Game A Deluxe' '' '' $sync
    $s = St
    Assert ($rc.Ok -and @($s.library.games | Where-Object { $_.id -in 'game-a', 'game-a-deluxe' }).Count -eq 1 -and @($s.library.games | Where-Object id -eq 'game-b').Count -eq 1) 'same file renamed: replaced, the other kept'

    # the tidy fixes a list that already has a duplicate (made the old way)
    $lib = $s.library
    $keep = @($lib.games | Where-Object id -eq 'super-kart-64')[0]
    $dupe = $keep.PSObject.Copy(); $dupe.id = 'kart-old'; $dupe.video = ''; $dupe.art = ''
    $dupe.bundle = $keep.bundle.PSObject.Copy(); $dupe.bundle.url = 'private:kart-old__Kart.zip'
    $lib.games = @($lib.games) + @($dupe)
    $t = Remove-AdminLibDuplicates $ws   # reads the list from the fake: put it there first
    Assert ($t.Dupes -eq 0) 'nothing to tidy before the duplicate is written'
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($lib | ConvertTo-Json -Depth 10)))
    $key = Get-AdminLibKey $ws
    $cur = Invoke-AdminLibApi $key 'GET' "http://127.0.0.1:$port/repos/Feirzen/retrobat-wizard/contents/library/library.json"
    [void](Invoke-AdminLibApi $key 'PUT' "http://127.0.0.1:$port/repos/Feirzen/retrobat-wizard/contents/library/library.json" ('{"message":"x","content":"' + $b64 + '","sha":"' + [string](($cur.Body | ConvertFrom-Json).sha) + '"}'))
    $t = Remove-AdminLibDuplicates $ws
    $s = St
    Assert ($t.Dupes -eq 1) ('tidy took one duplicate off: ' + $t.Dupes)
    Assert (@($s.library.games | Where-Object id -eq 'kart-old').Count -eq 0 -and @($s.library.games | Where-Object id -eq 'super-kart-64').Count -eq 1) 'tidy kept the copy with the video'
}
finally {
    try { Stop-Process -Id $srv.Id -Force } catch { }
    try { Remove-Item -LiteralPath $tmp -Recurse -Force } catch { }
}
Write-Host ("library duplicate tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
