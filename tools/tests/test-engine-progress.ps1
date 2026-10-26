# Two update engine bugs found on a friend's laptop, 2026-10-25:
#  1. A caller's progress block that calls its OWN function named Say looped
#     with the engine's nested Say (about 40 s per message, nothing shown).
#  2. version.txt landed early, so an install cut short looked finished.
# PowerShell 7, Linux.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, [string]$name) { if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" -ForegroundColor Red } }
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }

. (Join-Path $Scripts 'UpdateEngine.ps1')

$base = Join-Path ([IO.Path]::GetTempPath()) ('engprog-' + [guid]::NewGuid().ToString('N'))
$gh = Join-Path $base 'github'
$ws = Join-Path $base 'drive/RetroBat/_ClaudeWorkspace'
$script:UpdFetchOverride = {
    param($Url, $OutFile)
    $u = $Url -replace '\?t=\d+$', ''
    $src = Join-Path $gh ([Uri]::UnescapeDataString($u.Substring('https://raw.githubusercontent.com/Feirzen/retrobat-wizard/'.Length)))
    if (-not (Test-Path -LiteralPath $src)) { throw "404" }
    $d = Split-Path -Parent $OutFile; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    Copy-Item -LiteralPath $src -Destination $OutFile -Force
}
$script:UpdRunningOverride = { $false }

# 25 files, so the install reports progress twice, plus version.txt
$lines = @("version`t3.2.0")
$files = @{ 'version.txt' = "3.2.0`n" }
for ($i = 1; $i -le 25; $i++) { $files[('scripts/F{0:D2}.ps1' -f $i)] = "file $i" }
$files['wizard/wizard.ini'] = 'sorts after version.txt'
foreach ($k in ($files.Keys | Sort-Object)) {
    $p = Join-Path $gh "v320/drive/$k"; W $p $files[$k]
    $lines += ("code`t{0}`t{1}`t{2}" -f (Sha $p), (Get-Item $p).Length, $k)
}
W (Join-Path $gh 'v320/manifest.txt') (($lines -join "`n") + "`n")
W (Join-Path $gh 'main/latest.ini') "version = 3.2.0`ntag = v320`nnotes = n`n"
W (Join-Path $ws 'version.txt') "3.1.0`n"

$st = Invoke-UpdateCheck -Ws $ws
Assert ($st.state -eq 'ready') "downloaded ($($st.state))"

# --- 1. a caller with its own Say ------------------------------------------------
$script:said = New-Object System.Collections.ArrayList
function Say([string]$m, [string]$c = 'Gray') { [void]$script:said.Add($m) }
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps -Progress { param($m) Say $m 'DarkGray' }
$sw.Stop()
Assert ($r.Ok) "installed ($($r.Message))"
Assert ($sw.Elapsed.TotalSeconds -lt 10) ("a caller's own Say does not loop ({0:N1} s)" -f $sw.Elapsed.TotalSeconds)
Assert ($script:said.Count -ge 2) "the caller's Say got the messages ($($script:said -join ' / '))"
Assert (@($script:said | Where-Object { $_ -match 'Installing \(\d+ of \d+\)' }).Count -ge 1) 'install progress reached the caller'

# --- 2. version.txt is the last file put in place --------------------------------
$j = [IO.File]::ReadAllLines((Join-Path $ws 'update/previous/changes.txt')) | Where-Object { $_ -ne '' }
Assert ($j[-1] -match "`tversion\.txt$") "version.txt is last in the journal ($($j[-1]))"
Assert ([IO.File]::ReadAllText((Join-Path $ws 'version.txt')).Trim() -eq '3.2.0') 'version.txt says 3.2.0'

Remove-Item -LiteralPath $base -Recurse -Force
Write-Host ("engine progress: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
