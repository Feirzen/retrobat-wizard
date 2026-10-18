# Test harness for the admin tools download (Install-UpdAdminPack in
# UpdateEngine.ps1) and publish.py's admin-manifest.txt. PowerShell 7, Linux.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, [string]$name) {
    if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" -ForegroundColor Red }
}
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }

. (Join-Path $Scripts 'UpdateEngine.ps1')

$base = Join-Path ([IO.Path]::GetTempPath()) ('admtest-' + [guid]::NewGuid().ToString('N'))
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
$script:running = $false
$script:UpdRunningOverride = { $script:running }

# Publishes into the fake GitHub: $files / $admin = @{ 'rel' = @(kind, content) }
function Publish([string]$ver, [hashtable]$files, [hashtable]$admin) {
    $tag = "v$ver"
    foreach ($pair in @(@('manifest.txt', $files), @('admin-manifest.txt', $admin))) {
        if ($null -eq $pair[1]) { continue }
        $lines = @("version`t$ver")
        foreach ($k in ($pair[1].Keys | Sort-Object)) {
            $p = Join-Path (Join-Path (Join-Path $gh $tag) 'drive') $k
            W $p $pair[1][$k][1]
            $lines += ("{0}`t{1}`t{2}`t{3}" -f $pair[1][$k][0], (Sha $p), (Get-Item $p).Length, $k)
        }
        W (Join-Path (Join-Path $gh $tag) $pair[0]) (($lines -join "`n") + "`n")
    }
    W (Join-Path (Join-Path $gh 'main') 'latest.ini') ("version = $ver`ntag = $tag`nnotes = n`n")
}

W (Join-Path $ws 'wizard/wizard.ini') "name = Test`nversion = 3.0.0`n"
W (Join-Path $ws 'version.txt') "3.0.0`n"
W (Join-Path $ws 'scripts/Base.ps1') 'base 1'

# --- nothing published: a clear message, nothing written ----------------------
$r = Install-UpdAdminPack $ws
Assert (-not $r.Ok) 'offline: not ok'
Assert ($r.Message -match 'GitHub') "offline message names GitHub ($($r.Message))"
Assert (-not (Test-UpdAdminPack $ws)) 'offline: no admin tools'

# --- 3.1.0 with admin tools -----------------------------------------------------
Publish '3.1.0' @{ 'version.txt' = @('code', "3.1.0`n"); 'scripts/Base.ps1' = @('code', 'base 2') } `
                @{ 'scripts/AdminEngine.ps1' = @('code', 'engine 1'); 'scripts/AdminUI.ps1' = @('code', 'ui 1') }

# The ordinary manifest never names them, and an ordinary update leaves them out
$m = Read-UpdManifest (Join-Path $gh 'v3.1.0/manifest.txt')
Assert ($m.Ok) 'ordinary manifest reads (only code and seed lines)'
Assert (@($m.Entries | Where-Object { $_.Path -like '*Admin*' }).Count -eq 0) 'ordinary manifest has no admin files'
$st = Invoke-UpdateCheck -Ws $ws
Assert ($st.state -eq 'ready') "update downloads ($($st.state))"
$i = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert ($i.Ok) "update installs ($($i.Message))"
Assert (-not (Test-UpdAdminPack $ws)) 'ordinary update brings no admin tools'
Assert (@($script:fetchLog | Where-Object { $_ -match 'admin-manifest' }).Count -eq 0) 'ordinary update never asks for the admin list'

# --- the button: uses the installed tag ----------------------------------------
$script:fetchLog.Clear()
$r = Install-UpdAdminPack $ws
Assert ($r.Ok) "admin tools download ($($r.Message))"
Assert ($r.Files -eq 2) "two files ($($r.Files))"
Assert ((Test-UpdAdminPack $ws)) 'admin tools present'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'scripts/AdminUI.ps1')) -eq 'ui 1') 'AdminUI content'
Assert ($script:fetchLog[0] -match '/v3\.1\.0/admin-manifest\.txt$') "admin list from the installed tag ($($script:fetchLog[0]))"
Assert (-not (Test-Path (Join-Path $ws 'scripts/AdminUI.ps1.part'))) 'no .part left'
$r = Install-UpdAdminPack $ws
Assert ($r.Ok -and $r.Files -eq 0) 'second press: already up to date'
Assert ($r.Message -match 'already') 'already message'

# --- a tampered file is refused and nothing replaced -----------------------------
Publish '3.1.1' @{ 'version.txt' = @('code', "3.1.1`n"); 'scripts/Base.ps1' = @('code', 'base 3') } `
                @{ 'scripts/AdminEngine.ps1' = @('code', 'engine 2'); 'scripts/AdminUI.ps1' = @('code', 'ui 2') }
[IO.File]::WriteAllText((Join-Path $gh 'v3.1.1/drive/scripts/AdminUI.ps1'), 'evil')
$r = Install-UpdAdminPack $ws 'v3.1.1'
Assert (-not $r.Ok) 'tampered: refused'
Assert ($r.Message -match 'checksum') 'tampered: checksum message'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'scripts/AdminUI.ps1')) -eq 'ui 1') 'tampered: old file kept'
Assert (-not (Test-Path (Join-Path $ws 'scripts/AdminUI.ps1.part'))) 'tampered: .part removed'
[IO.File]::WriteAllText((Join-Path $gh 'v3.1.1/drive/scripts/AdminUI.ps1'), 'ui 2')

# --- an update refreshes them on a setup that has them --------------------------
$st = Invoke-UpdateCheck -Ws $ws
$i = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert ($i.Ok) "3.1.1 installs ($($i.Message))"
Assert ([IO.File]::ReadAllText((Join-Path $ws 'scripts/AdminEngine.ps1')) -eq 'engine 2') 'update refreshed AdminEngine'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'scripts/AdminUI.ps1')) -eq 'ui 2') 'update refreshed AdminUI'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'scripts/Base.ps1')) -eq 'base 3') 'update did its normal job'

# --- an unsafe admin list is refused ------------------------------------------------
W (Join-Path $gh 'vbad/admin-manifest.txt') ("version`t9`ncode`t" + ('0' * 64) + "`t1`t../outside.ps1`n")
$r = Install-UpdAdminPack $ws 'vbad'
Assert (-not $r.Ok -and $r.Message -match 'refused') "unsafe list refused ($($r.Message))"
Assert (-not (Test-Path (Join-Path $base 'drive/RetroBat/outside.ps1'))) 'nothing written outside'

# --- an old version with no admin list: says to update first ------------------------
W (Join-Path $gh 'vold/manifest.txt') "version`t3.0.0`n"
$r = Install-UpdAdminPack $ws 'vold'
Assert (-not $r.Ok -and $r.Message -match 'update it first') "old version message ($($r.Message))"

# --- a fresh install (no installed.ini) uses the channel's newest ------------------
$ws2 = Join-Path $base 'drive2/RetroBat/_ClaudeWorkspace'
W (Join-Path $ws2 'version.txt') "3.1.1`n"
$script:fetchLog.Clear()
$r = Install-UpdAdminPack $ws2
Assert ($r.Ok -and $r.Files -eq 2) "fresh setup gets them ($($r.Message))"
Assert (@($script:fetchLog | Where-Object { $_ -match '/v3\.1\.1/admin-manifest' }).Count -eq 1) 'fresh setup: newest tag'

# --- the workshop drive is never touched ---------------------------------------------
$ws3 = Join-Path $base 'drive3/RetroBat/_ClaudeWorkspace'
W (Join-Path $ws3 'version.txt') "3.1.1`n"
W (Join-Path $ws3 'update/workshop.txt') 'serial ='
$r = Install-UpdAdminPack $ws3
Assert (-not $r.Ok -and $r.Message -match 'workshop') "workshop refused ($($r.Message))"
Assert (-not (Test-UpdAdminPack $ws3)) 'workshop: nothing downloaded'

Remove-Item -LiteralPath $base -Recurse -Force
Write-Host ("adminpack: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
