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
    Assert (@($st.assets) -contains 'my-game__My.Game..v1..sfc') 'asset uploaded under a safe name'
    $g = @($st.library.games | Where-Object id -eq 'my-game')[0]
    Assert ($null -ne $g -and $g.system -eq 'snes' -and $g.players -eq '1-2') 'entry added'
    Assert ($g.files[0].name -eq 'My Game (v1).sfc' -and $g.files[0].size -eq $bytes.Length) 'file name and size kept'
    Assert ($g.files[0].sha256 -eq (Get-FileHash $game -Algorithm SHA256).Hash.ToLower()) 'checksum right'
    Assert ($g.files[0].url -eq 'private:my-game__My.Game..v1..sfc') 'file kept private, listed by name'
    Assert (@($st.library.games).Count -eq 2 -and $st.library.note -eq 'n \ x') 'old game and note kept'
    # again: replaces, never duplicates
    $r2 = Publish-AdminLibraryGame $ws $game 'snes' 'My Game' '2' 'Again.' $sync
    $st = Invoke-RestMethod "http://127.0.0.1:$port/state" -Headers @{ Authorization = 'Bearer github_pat_TEST' }
    Assert ($r2.Ok -and @($st.assets).Count -eq 1 -and @($st.library.games).Count -eq 2) 'publishing again replaces'
    Assert ((@($st.library.games | Where-Object id -eq 'my-game')[0]).players -eq '2') 'entry updated'
    # the wizard can read what was written
    Remove-Item -Recurse -Force $ws
} finally { Stop-Process -Id $srv.Id -Force }
Write-Host ("admin tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
