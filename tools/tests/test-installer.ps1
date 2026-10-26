# The installer's two background jobs (installer/Install-Wizard.ps1), run
# without the window against a fake GitHub on this machine. PowerShell 7.
#   pwsh tools/tests/test-installer.ps1
param(
    [string]$Installer = (Join-Path $PSScriptRoot '../../installer/Install-Wizard.ps1'),
    [string]$Engine = (Join-Path $PSScriptRoot '../../drive/scripts/UpdateEngine.ps1')
)
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, [string]$name) { if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" -ForegroundColor Red } }
function W([string]$p, $data) {
    $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    if ($data -is [byte[]]) { [IO.File]::WriteAllBytes($p, $data) } else { [IO.File]::WriteAllText($p, [string]$data) }
}
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function Zip([string]$out, [hashtable]$files) {
    Add-Type -AssemblyName System.IO.Compression
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force)
    $fs = [IO.File]::Create($out); $z = New-Object System.IO.Compression.ZipArchive($fs, 'Create')
    foreach ($k in $files.Keys) { $e = $z.CreateEntry($k); $s = $e.Open(); $b = [Text.Encoding]::UTF8.GetBytes([string]$files[$k]); $s.Write($b, 0, $b.Length); $s.Dispose() }
    $z.Dispose(); $fs.Dispose()
}

$base = Join-Path ([IO.Path]::GetTempPath()) ('insttest-' + [guid]::NewGuid().ToString('N'))
$gh = Join-Path $base 'gh'
$ghRepo = Join-Path $gh 'Feirzen/retrobat-wizard'

# --- a fake published version -------------------------------------------------
function Publish([string]$tag, [string]$ver, [hashtable]$files, [string]$pkgMode) {
    $lines = @("version`t$ver")
    foreach ($k in ($files.Keys | Sort-Object)) {
        $p = Join-Path (Join-Path (Join-Path $ghRepo $tag) 'drive') $k
        if ($files[$k] -is [string] -and $files[$k] -eq '<engine>') { $d = Split-Path -Parent $p; [void](New-Item -ItemType Directory -Path $d -Force); Copy-Item $Engine $p }
        else { W $p $files[$k] }
        $lines += ("code`t{0}`t{1}`t{2}" -f (Sha $p), (Get-Item $p).Length, $k)
    }
    W (Join-Path (Join-Path $ghRepo $tag) 'manifest.txt') (($lines -join "`n") + "`n")
    if ($pkgMode -ne 'none') {
        $pk = @{}
        foreach ($k in $files.Keys) { $pk[$k] = [IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $ghRepo $tag) 'drive') $k)) }
        if ($pkgMode -eq 'stale') { $pk['scripts/Base.ps1'] = 'an older Base' }
        if ($pkgMode -eq 'evil') { $pk['../../evil.txt'] = 'x' }
        Zip (Join-Path (Join-Path $ghRepo $tag) 'package/wizard-package.zip') $pk
    }
    W (Join-Path $ghRepo 'main/latest.ini') "version = $ver`ntag = $tag`nnotes = n`n"
}
$files = @{
    'scripts/UpdateEngine.ps1' = '<engine>'
    'scripts/Base.ps1' = 'base 3.2'
    'scripts/Restore-CkauBookTheme.ps1' = "'restored' | Out-File (Join-Path `$PSScriptRoot 'restored.txt')"
    'version.txt' = "3.2.0`n"
    'wizard/wizard.ini' = "name = Test Wizard`n"
    'defaults/Setup Wizard.bat' = '@echo off'
}
Publish 'aaaaaaa1' '3.2.0' $files 'full'
Zip (Join-Path $gh 'theme.zip') @{ 'ckau-book-master/theme.xml' = '<theme/>'; 'ckau-book-master/_inc/arts/a.png' = 'png' }

# --- the server --------------------------------------------------------------------
$port = Get-Random -Minimum 20000 -Maximum 40000
$srv = Start-Process python3 -ArgumentList @('-m', 'http.server', $port, '--bind', '127.0.0.1', '--directory', $gh) -PassThru -RedirectStandardError (Join-Path $base 'srv.err') -RedirectStandardOutput (Join-Path $base 'srv.out')
Start-Sleep -Seconds 1
$env:RBW_TEST_NOUI = '1'
$env:RBW_TEST_RAW = "http://127.0.0.1:$port"
$env:RBW_TEST_THEME = "http://127.0.0.1:$port/theme.zip"
# Only the part above the window: the window needs Windows' drawing library.
$src = [IO.File]::ReadAllText($Installer)
$cut = $src.IndexOf('# Tests run the two workers without any window')
Assert ($cut -gt 0) 'installer has the test cut line'
. ([scriptblock]::Create($src.Substring(0, $cut)))

function Run-Install([string]$name, [string]$themeUrl = $env:RBW_TEST_THEME) {
    $root = Join-Path $base $name
    W (Join-Path $root 'retrobat.ini') ''
    W (Join-Path $root 'RetroBat.exe') ''
    $ws = Join-Path $root '_ClaudeWorkspace'
    [void](New-Item -ItemType Directory -Path (Join-Path $ws 'update') -Force)
    $t = [hashtable]::Synchronized(@{})
    $t.Root = $root; $t.Ws = $ws; $t.Repo = 'Feirzen/retrobat-wizard'; $t.RawBase = $env:RBW_TEST_RAW
    $t.Token = 'rb1:dGVzdA=='; $t.ThemeUrl = $themeUrl; $t.ThemeGuess = [long]1000
    $t.LogFile = Join-Path (Join-Path $ws 'update') 'install.log'; $t.LogLock = New-Object object
    foreach ($i in 1..3) { $t["F$i"] = 0.0; $t["T$i"] = ''; $t["St$i"] = 'wait' }
    $t.ADone = $false; $t.AErr = ''; $t.TDone = $false; $t.ThemeGo = $false; $t.Cancel = $false
    $a = Start-Worker $WorkA $t
    $b = Start-Worker $WorkT $t
    $until = (Get-Date).AddSeconds(90)
    while (-not (($t.ADone -or $t.AErr -ne '') -and $t.TDone) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 200 }
    foreach ($w in @($a, $b)) {
        try { $w.PS.EndInvoke($w.Handle) } catch { Write-Host ('worker threw: ' + $_) }
        foreach ($er in $w.PS.Streams.Error) { Write-Host ('worker error: ' + $er) }
        $w.PS.Dispose()
    }
    return @{ T = $t; Root = $root; Ws = $ws }
}
function With([hashtable]$h, [string]$k, $v) { $c = @{}; foreach ($x in $h.Keys) { $c[$x] = $h[$x] }; $c[$k] = $v; return $c }
function J([string]$a, [string]$b) { return [IO.Path]::Combine([string[]](@($a) + @($b -split '[\\/]'))) }

# 1. a fresh install with the package and the theme
$r = Run-Install 'one'
$t = $r.T; $ws = $r.Ws
Assert ($t.ADone) "1: steps 1-2 done ($($t.AErr))"
Assert ($t.St1 -eq 'done' -and $t.St2 -eq 'done') "1: bars 1 and 2 done ($($t.St1)/$($t.St2))"
Assert ([IO.File]::ReadAllText((J $ws 'version.txt')).Trim() -eq '3.2.0') '1: version.txt'
Assert ([IO.File]::ReadAllText((J $ws 'scripts/Base.ps1')) -eq 'base 3.2') '1: Base.ps1'
Assert (Test-Path (J $ws 'update/installed-manifest.txt')) '1: installed manifest written'
$log = [IO.File]::ReadAllText((J $ws 'update/install.log'))
Assert ($log -match 'package downloaded') '1: used the package'
function Fetched([string]$tag) {
    # the test server writes one line per request to srv.err
    return @(Get-Content (Join-Path $base 'srv.err') | Where-Object { $_ -match ('GET /Feirzen/retrobat-wizard/' + $tag + '/drive/') -and $_ -notmatch 'UpdateEngine' })
}
Assert ((Fetched 'aaaaaaa1').Count -eq 0) ("1: no file fetched one at a time ({0})" -f (Fetched 'aaaaaaa1').Count)
Assert ([IO.File]::ReadAllText((J $ws 'social/social-token.txt')).Trim() -eq 'rb1:dGVzdA==') '1: token written'
Assert (Test-Path (Join-Path $r.Root 'Test Wizard.bat')) '1: wizard button made, named from wizard.ini'
Assert (Test-Path (J $ws 'first-run.txt')) '1: first-run note'
Assert ($t.St3 -eq 'done') "1: theme done ($($t.St3): $($t.T3))"
Assert (Test-Path (J $r.Root 'emulationstation/.emulationstation/themes/ckau-book/theme.xml')) '1: theme in place'
Assert (Test-Path (J $r.Root 'emulationstation/.emulationstation/themes/ckau-book/_inc/arts/a.png')) '1: theme subfolders'
Assert (-not (Test-Path (Join-Path $r.Root '_ck'))) '1: no _ck left'
Assert (-not (Test-Path (J $ws 'update/ckau-book.zip'))) '1: theme zip removed'
Assert (-not (Test-Path (J $ws 'update/theme-downloading.txt'))) '1: theme marker removed'
Assert (-not (Test-Path (J $ws 'update/wizard-package.zip'))) '1: package removed'
Assert ([math]::Abs([double]$t.F1 - 1) -lt 0.001 -and [math]::Abs([double]$t.F3 - 1) -lt 0.001) '1: bars full'

# 2. run again: nothing to do, theme already here
$root1 = $r.Root
$t2 = [hashtable]::Synchronized(@{})
$r2 = Run-Install 'one'
Assert ($r2.T.ADone -and $r2.T.T2 -match 'Nothing') "2: rerun: nothing needed ($($r2.T.T2))"
Assert ($r2.T.St3 -eq 'skip') '2: rerun: theme already here'

# 3. no package at that version: one file at a time still works
Publish 'bbbbbbb2' '3.2.1' (With $files 'version.txt' "3.2.1`n") 'none'
$r = Run-Install 'three'
Assert ($r.T.ADone) "3: no package: installed ($($r.T.AErr))"
Assert ([IO.File]::ReadAllText((J $r.Ws 'version.txt')).Trim() -eq '3.2.1') '3: version 3.2.1'
Assert ([IO.File]::ReadAllText((J $r.Ws 'update/install.log')) -match 'one at a time') '3: log says one at a time'

# 4. a package with an older file in it: the engine fetches the right one
Publish 'ccccccc3' '3.2.2' (With $files 'version.txt' "3.2.2`n") 'stale'
$r = Run-Install 'four'
Assert ($r.T.ADone) "4: stale package: installed ($($r.T.AErr))"
Assert ([IO.File]::ReadAllText((J $r.Ws 'scripts/Base.ps1')) -eq 'base 3.2') '4: the right Base.ps1, not the package one'
$f4 = @(Fetched 'ccccccc3')
Assert ($f4.Count -eq 1 -and $f4[0] -match 'Base\.ps1') ("4: exactly the one stale file fetched ({0})" -f ($f4 -join ' | '))

# 5. a package with a name that climbs out: refused, nothing outside
Publish 'ddddddd4' '3.2.3' (With $files 'version.txt' "3.2.3`n") 'evil'
$r = Run-Install 'five'
Assert (-not $r.T.ADone -and $r.T.AErr -match 'unsafe') "5: unsafe name refused ($($r.T.AErr))"
Assert ($r.T.St1 -eq 'fail') '5: bar 1 failed'
Assert (-not (Test-Path (Join-Path $base 'evil.txt')) -and -not (Test-Path (J $r.Ws 'update/evil.txt'))) '5: nothing written outside'
Assert ($r.T.TDone -and $r.T.St3 -ne 'done') '5: theme not started after a failure'
Publish 'eeeeeee5' '3.2.4' (With $files 'version.txt' "3.2.4`n") 'full'

# 6. theme missing on the server: the wizard still installs, theme says why
$r = Run-Install 'six' "http://127.0.0.1:$port/no-such-theme.zip"
Assert ($r.T.ADone) '6: wizard installed'
Assert ($r.T.St3 -eq 'fail' -and $r.T.T3 -match 'Could not get it') "6: theme failed, says so ($($r.T.T3))"
Assert (-not (Test-Path (J $r.Ws 'update/theme-downloading.txt'))) '6: marker removed'
Assert (-not (Test-Path (Join-Path $r.Root '_ck'))) '6: no _ck left'

# 7. the built one-file installer: batch head, ASCII, key and mage written in
$zip = Join-Path $PSScriptRoot '../../installer/RetroBat-Wizard-Installer.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip)
Assert ($z.Entries.Count -eq 1 -and $z.Entries[0].FullName -eq 'INSTALL THE WIZARD.bat') '7: zip holds exactly the one .bat'
$sr = New-Object IO.StreamReader($z.Entries[0].Open()); $bat = $sr.ReadToEnd(); $sr.Dispose(); $z.Dispose()
Assert ($bat.StartsWith('<# :')) '7: starts as a batch/PowerShell hybrid'
Assert ($bat -notmatch "[^\x00-\x7F]") '7: plain ASCII'
Assert ($bat -match "\r\n" -and $bat -notmatch "[^\r]\n") '7: Windows line ends throughout'
Assert ($bat -notmatch '@@TOKEN@@|@@MAGE@@') '7: markers replaced'
Assert ($bat -match "\`$Token    = 'rb1:") '7: key in its scrambled form'
$tokens = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($bat, [ref]$tokens, [ref]$errs)
Assert ($errs.Count -eq 0) ("7: the whole .bat parses as PowerShell ({0})" -f (($errs | ForEach-Object { $_.Message }) -join '; '))

Stop-Process -Id $srv.Id -Force
Remove-Item -LiteralPath $base -Recurse -Force
Write-Host ("installer: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
