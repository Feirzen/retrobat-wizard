# Publish a game (Admin tab) against a fake GitHub on this computer.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')
. (Join-Path $Scripts 'AdminEngine.ps1')
$port = 18765
$srv = Start-Process python3 -ArgumentList @((Join-Path $PSScriptRoot 'fake_github.py'), $port) -PassThru
Start-Sleep -Milliseconds 800
try {
    $script:AdminApiBase = "http://127.0.0.1:$port"; $script:AdminUploadBase = "http://127.0.0.1:$port"
    $ws = Join-Path ([IO.Path]::GetTempPath()) ('adm' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $ws | Out-Null
    $sync = [hashtable]::Synchronized(@{ Stage = ''; Percent = 0 })
    $game = Join-Path $ws 'My Game (v1).sfc'
    $bytes = New-Object byte[] (3MB + 17); (New-Object Random 5).NextBytes($bytes); [IO.File]::WriteAllBytes($game, $bytes)

    $r = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '1-2' 'A test.' $sync
    Assert (-not $r.Ok -and $r.Message -like '*no library key*') 'no key: stops'
    New-Item -ItemType Directory -Path (Join-Path $ws 'social') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $ws 'social/social-token.txt'), 'github_pat_SOCIAL')
    Assert (-not (Set-AdminLibKey $ws 'nonsense')) 'bad key refused'
    Assert (Set-AdminLibKey $ws 'github_pat_WRONG') 'key saved'
    $r = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '1-2' 'A test.' $sync
    Assert (-not $r.Ok -and $r.Message -like '*refused the library key*') 'wrong key: plain message'
    $st0 = Invoke-RestMethod "http://127.0.0.1:$port/state"
    Assert (@($st0.assets).Count -eq 0) 'wrong key: stops before uploading anything'
    [void](Set-AdminLibKey $ws 'github_pat_TEST')
    $r = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '1-2' 'A test.' $sync
    Assert $r.Ok ('publish works: ' + $r.Message)
    Assert ($sync.Percent -eq 100) 'progress reaches 100'
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    Assert (@($st.assets) -contains 'my-game__My.Game.v1.sfc') ('asset uploaded under the name GitHub keeps: ' + (@($st.assets) -join ','))
    $g = @($st.library.games | Where-Object id -eq 'my-game')[0]
    Assert ($null -ne $g -and $g.system -eq 'snes' -and $g.players -eq '1-2') 'entry added'
    Assert ($g.files[0].name -eq 'My Game (v1).sfc' -and $g.files[0].size -eq $bytes.Length) 'file name and size kept'
    Assert ($g.files[0].sha256 -eq (Get-FileHash $game -Algorithm SHA256).Hash.ToLower()) 'checksum right'
    Assert ($g.files[0].url -eq 'private:my-game__My.Game.v1.sfc') 'file kept private, listed by name'
    Assert (@($st.library.games).Count -eq 2 -and $st.library.note -eq 'n \ x') 'old game and note kept'
    # again: replaces, never duplicates
    $r2 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    Assert ($r2.Ok -and @($st.assets).Count -eq 1 -and @($st.library.games).Count -eq 2) 'publishing again replaces'
    Assert ((@($st.library.games | Where-Object id -eq 'my-game')[0]).players -eq '2') 'entry updated'
    Assert ($st.uploads -eq 1) ('same file again: not sent twice (uploads ' + $st.uploads + ')')

    # names the way GitHub tidies them (Steven's first real upload, 2026-10-11)
    Assert ((Get-AdminLibAssetName 'paper' 'Paper Mario - Door (USA).nkit.iso') -eq 'paper__Paper.Mario.-.Door.USA.nkit.iso') 'name: runs of odd characters become one dot'
    Assert ((Get-AdminLibAssetName 'g' '..(x).') -eq 'g__x' -and (Get-AdminLibAssetName 'g' '()') -eq 'g__file') 'name: no dots at the ends, never empty'

    # box art (2026-10-11): goes to the public repo, listed as "art"
    $png = Join-Path $ws 'cover.png'; [IO.File]::WriteAllBytes($png, [byte[]](137,80,78,71,13,10,26,10,1,2,3,4))
    $r3 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync $png
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    $g = @($st.library.games | Where-Object id -eq 'my-game')[0]
    Assert ($r3.Ok -and $g.art -eq 'library/art/my-game.png') ('art listed: ' + $g.art)
    Assert ($st.art.'library/art/my-game.png' -eq 12) 'art uploaded whole'
    $r4 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync $png
    Assert $r4.Ok 'art replaced on a second publish'
    $r5 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    Assert ((@($st.library.games | Where-Object id -eq 'my-game')[0]).art -eq 'library/art/my-game.png') 'no new art: old art kept'
    Assert ($null -eq (@($st.library.games | Where-Object id -eq 'old')[0]).art) 'games without art stay without'
    $txt = Join-Path $ws 'notes.txt'; [IO.File]::WriteAllText($txt, 'x')
    Assert ((Send-AdminLibArt 'github_pat_TEST' "http://127.0.0.1:$port/repos/Feirzen/retrobat-wizard" 'zz' $txt) -eq '') 'not a picture: skipped'

    # several games at once: one bad file never stops the others
    $game2 = Join-Path $ws 'Second.nes'; [IO.File]::WriteAllBytes($game2, [byte[]](1,2,3))
    $items = @(@{ File = $game2; System = 'nes'; Title = 'Second Game'; Players = '1-2'; Description = ''; Art = '' },
               @{ File = (Join-Path $ws 'gone.nes'); System = 'nes'; Title = 'Gone: Game'; Players = ''; Description = ''; Art = '' })
    $sync.Prefix = ''
    $m = Publish-AdminLibraryGames $ws $items $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    Assert (-not $m.Ok -and @($m.Done).Count -eq 1 -and @($m.Failed).Count -eq 1) 'multi: one done, one failed'
    Assert ($m.Message -like '*Second Game*' -and $m.Message -like '*Gone: Game: The file is gone.*') ('multi: says both ' + $m.Message)
    Assert (@($st.library.games).Count -eq 3) 'multi: list has the new game'
    Assert ($sync.Prefix -eq '') 'multi: prefix cleared'
    $one = Publish-AdminLibraryGames $ws @(@{ File = $game2; System = 'nes'; Title = 'Second Game'; Players = '1-2'; Description = ''; Art = '' }) $sync
    Assert ($one.Ok -and $one.Message -like 'Second Game is in the online library*') 'multi with one game: plain message'

    # a changed file: uploaded again, the old copy cleared once the list is saved
    $bytes[0] = [byte](($bytes[0] + 1) % 256); [IO.File]::WriteAllBytes($game, $bytes)
    $r6 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state"
    Assert ($r6.Ok -and @($st.assets | Where-Object { $_ -like 'my-game__*' }).Count -eq 1) 'changed file: one copy left'

    # GitHub answers with a name of its own: that name is what gets listed
    [void](Invoke-RestMethod "http://127.0.0.1:$port/quirk")
    $game3 = Join-Path $ws 'Third.gb'; [IO.File]::WriteAllBytes($game3, [byte[]](9,8,7,6))
    $r7 = Publish-AdminLibraryGame $ws $game3 'gb' 'Third' '1' '' $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state"
    Assert ($r7.Ok -and (@($st.library.games | Where-Object id -eq 'third')[0]).files[0].url -eq 'private:third__x.Third.gb') ('GitHub''s own name listed: ' + $r7.Message)

    # an upload that never made the list (what Steven's first test left)
    $orph = Join-Path $ws 'Orphan.gba'; [IO.File]::WriteAllBytes($orph, [byte[]](5,5,5))
    $up = Invoke-WebRequest -Method Post -Uri "http://127.0.0.1:$port/repos/Feirzen/retrobat-wizard-social/releases/7/assets?name=lost__Orphan.gba" -Headers @{ Authorization = 'Bearer github_pat_SOCIAL' } -InFile $orph -ContentType 'application/octet-stream'
    $c = Get-AdminLibraryContents $ws
    Assert ($c.Ok -and @($c.Games).Count -eq 4) ('contents: games read (' + @($c.Games).Count + ')')
    Assert (@($c.Leftovers).Count -eq 1 -and $c.Leftovers[0].name -like 'lost__*') ('contents: the leftover found: ' + (@($c.Leftovers | ForEach-Object name) -join ','))

    # removing: list entry, box art, private file, and the leftover
    $rm = Remove-AdminLibraryGames $ws @('my-game') $c.Leftovers
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state"
    Assert ($rm.Ok -and @($rm.Removed).Count -eq 1 -and $rm.Cleared -eq 1) ('remove: ' + $rm.Message)
    Assert (@($st.library.games | Where-Object id -eq 'my-game').Count -eq 0 -and @($st.library.games).Count -eq 3) 'remove: off the list, others kept'
    Assert ($null -eq $st.art.'library/art/my-game.png') 'remove: box art gone'
    Assert (@($st.assets | Where-Object { $_ -like 'my-game__*' -or $_ -like '*lost__*' }).Count -eq 0 -and @($st.assets).Count -eq 2) ('remove: files gone, others kept: ' + (@($st.assets) -join ','))
    Assert ($st.library.note -eq 'n \ x') 'remove: note kept'
    $rm2 = Remove-AdminLibraryGames $ws @('nope') @()
    Assert ($rm2.Ok -and $rm2.Message -eq 'Nothing to remove.') 'remove: unknown id does nothing'
    $c2 = Get-AdminLibraryContents $ws
    Assert (@($c2.Leftovers).Count -eq 0) 'nothing left over after'
    Remove-Item -Recurse -Force $ws
} finally { Stop-Process -Id $srv.Id -Force }
Write-Host ("admin tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
