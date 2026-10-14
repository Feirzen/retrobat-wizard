# Stable / dev update channels (UpdateEngine.ps1, 2026-10-12). PowerShell 7, Linux.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, [string]$name) {
    if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" -ForegroundColor Red }
}
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }
function RT([string]$p) { [IO.File]::ReadAllText($p) }

. (Join-Path $Scripts 'UpdateEngine.ps1')
. (Join-Path $Scripts 'Migrations.ps1')

$base = Join-Path ([IO.Path]::GetTempPath()) ('chantest-' + [guid]::NewGuid().ToString('N'))
$gh = Join-Path $base 'github'
$ws = Join-Path $base 'drive/RetroBat/_ClaudeWorkspace'
$script:fetchLog = New-Object System.Collections.ArrayList
$script:UpdFetchOverride = {
    param($Url, $OutFile)
    [void]$script:fetchLog.Add($Url)
    $u = $Url -replace '\?t=\d+$', ''
    $rest = [Uri]::UnescapeDataString($u.Substring('https://raw.githubusercontent.com/Feirzen/retrobat-wizard/'.Length))
    $src = Join-Path $gh $rest
    if (-not (Test-Path -LiteralPath $src)) { throw "404 $rest" }
    $d = Split-Path -Parent $OutFile; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    Copy-Item -LiteralPath $src -Destination $OutFile -Force
}
$script:UpdRunningOverride = { $false }

# A build on the fake GitHub, under its own commit id; $latest is latest.ini or latest-dev.ini.
function Publish([string]$ver, [string]$tag, [hashtable]$files, [string]$latest) {
    $lines = @("version`t$ver")
    foreach ($k in ($files.Keys | Sort-Object)) {
        $p = Join-Path (Join-Path (Join-Path $gh $tag) 'drive') $k
        W $p $files[$k]
        $lines += ("code`t{0}`t{1}`t{2}" -f (Sha $p), (Get-Item $p).Length, $k)
    }
    W (Join-Path (Join-Path $gh $tag) 'manifest.txt') (($lines -join "`n") + "`n")
    W (Join-Path (Join-Path $gh 'main') $latest) ("version = $ver`ntag = $tag`nnotes = $ver notes`n")
}
function Update-Now { $c = Invoke-UpdateCheck -Ws $ws; $i = Invoke-UpdateInstall -Ws $ws -NoPostSteps; return @($c, $i) }

# the drive: Steven's own, 2.4 dev code nobody installed through the updater
W (Join-Path $ws 'version.txt') "2.4.0-beta-dev`n"
W (Join-Path $ws 'scripts/A.ps1') 'A dev local'
W (Join-Path $ws 'scripts/Migrations.ps1') (RT (Join-Path $Scripts 'Migrations.ps1'))

$tagS = 'a' * 40; $tagD1 = 'b' * 40; $tagD2 = 'c' * 40
Publish '2.3.0-beta' $tagS @{ 'version.txt' = "2.3.0-beta`n"; 'scripts/A.ps1' = 'A stable' } 'latest.ini'
Publish '2.4.0-beta-dev' $tagD1 @{ 'version.txt' = "2.4.0-beta-dev`n"; 'scripts/A.ps1' = 'A dev 1'; 'scripts/B.ps1' = 'B dev 1' } 'latest-dev.ini'

# --- defaults --------------------------------------------------------------
$cfg = Get-UpdConfig $ws
Assert ($cfg.Channel -eq 'stable' -and $cfg.Latest -eq 'latest.ini') 'default channel is stable'
Assert ((Get-UpdInstalled $ws).Channel -eq 'stable') 'nothing installed reads as stable'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') "stable 2.3 not offered over local 2.4 (got $($st.state))"

# --- switch to dev -----------------------------------------------------------
Set-UpdChannel $ws 'dev'
Assert ((Get-UpdConfig $ws).Channel -eq 'dev') 'channel set to dev'
Set-UpdChannel $ws 'dev'
Assert (@([IO.File]::ReadAllLines((Join-Path $ws 'update/update.ini')) | Where-Object { $_ -match '^channel' }).Count -eq 1) 'channel line written once'
$script:fetchLog.Clear()
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available') "switching to dev offers the dev build (got $($st.state))"
Assert ($script:fetchLog[0] -match '/main/latest-dev\.ini') 'dev reads latest-dev.ini'
Assert ([string]$st.message -match 'dev') 'the bar says it is switching'
$r = Update-Now
Assert ($r[0].state -eq 'ready') "dev download ready (got $($r[0].state) $($r[0].message))"
Assert ($r[1].Ok -and $r[1].Version -eq '2.4.0-beta-dev') "dev installed ($($r[1].Message))"
Assert ((RT (Join-Path $ws 'scripts/A.ps1')) -eq 'A dev 1') 'dev file in place'
$inst = Get-UpdInstalled $ws
Assert ($inst.Channel -eq 'dev' -and $inst.Tag -eq $tagD1) 'installed.ini says dev, commit 1'
Assert ((Test-Path (Join-Path $ws 'update/previous/files/scripts/A.ps1')) -and (RT (Join-Path $ws 'update/previous/files/scripts/A.ps1')) -eq 'A dev local') 'local unpublished file kept for go back'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') "same dev commit not offered again (got $($st.state))"

# --- a republished dev build, same version number ----------------------------
Publish '2.4.0-beta-dev' $tagD2 @{ 'version.txt' = "2.4.0-beta-dev`n"; 'scripts/A.ps1' = 'A dev 2'; 'scripts/B.ps1' = 'B dev 1' } 'latest-dev.ini'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available') "new dev commit with same version is offered (got $($st.state))"
$r = Update-Now
Assert ($r[1].Ok) "dev 2 installed ($($r[1].Message))"
Assert ((RT (Join-Path $ws 'scripts/A.ps1')) -eq 'A dev 2') 'dev 2 file in place'
Assert ((Get-UpdInstalled $ws).Tag -eq $tagD2) 'installed commit 2'
Assert (@(Get-ChildItem (Join-Path $ws 'update/incoming') -Directory -ErrorAction SilentlyContinue).Count -eq 0) 'download folders tidied away'

# --- back to stable: an OLDER version, on purpose ----------------------------
Set-UpdChannel $ws 'stable'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available' -and $st.version -eq '2.3.0-beta') "switching to stable offers 2.3 (got $($st.state) $($st.version))"
$r = Update-Now
Assert ($r[1].Ok) "stable installed ($($r[1].Message))"
Assert ((RT (Join-Path $ws 'scripts/A.ps1')) -eq 'A stable') 'stable file in place'
Assert (-not (Test-Path (Join-Path $ws 'scripts/B.ps1'))) 'dev-only file removed (kept for go back)'
Assert ((Get-UpdLocalVersion $ws) -eq '2.3.0-beta') 'version.txt says 2.3'
Assert ((Get-UpdInstalled $ws).Channel -eq 'stable') 'installed.ini says stable'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') "stable then up to date (got $($st.state))"

# --- go back from the switch: dev again, channel too ---------------------------
$g = Invoke-UpdateGoBack -Ws $ws
Assert ($g.Ok) "go back ok ($($g.Message))"
Assert ((RT (Join-Path $ws 'scripts/A.ps1')) -eq 'A dev 2') 'go back puts dev 2 back'
Assert ((RT (Join-Path $ws 'scripts/B.ps1')) -eq 'B dev 1') 'go back puts the dev-only file back'
Assert ((Get-UpdConfig $ws).Channel -eq 'dev') 'go back switched the channel back to dev'
$inst = Get-UpdInstalled $ws
Assert ($inst.Channel -eq 'dev' -and $inst.Tag -eq $tagD2) 'installed.ini back to dev commit 2'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') "after go back, dev is up to date (got $($st.state))"

# --- a stale download from the other channel is never installed ----------------
Set-UpdChannel $ws 'stable'
$c = Invoke-UpdateCheck -Ws $ws
Assert ($c.state -eq 'ready') 'stable downloaded'
Set-UpdChannel $ws 'dev'
Assert ((Get-UpdReadyVersion $ws) -eq '') 'stable download ignored while on dev'
$i = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert (-not $i.Ok) 'nothing installed from the other channel'
Assert ((RT (Join-Path $ws 'scripts/A.ps1')) -eq 'A dev 2') 'files untouched'

# --- stable drives behave exactly as before (a newer stable is offered) -----------
$ws2 = Join-Path $base 'drive2/RetroBat/_ClaudeWorkspace'
W (Join-Path $ws2 'version.txt') "2.2.0`n"
$ws = $ws2
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available' -and $st.version -eq '2.3.0-beta') 'friend drive on stable sees 2.3'
$r = Update-Now
Assert ($r[1].Ok -and (Get-UpdInstalled $ws).Channel -eq 'stable') 'friend drive installs stable'
Assert ((Invoke-UpdateCheck -Ws $ws -NoDownload).state -eq 'uptodate') 'and is then up to date'

Remove-Item -Recurse -Force $base
Write-Host ("channel tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
