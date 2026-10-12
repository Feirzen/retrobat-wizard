<#
    Install-Wizard.ps1 - puts the RetroBat Wizard into a RetroBat folder.

    Comes in RetroBat-Wizard-Installer.zip from the website, with
    INSTALL THE WIZARD.bat (which runs this) and token.txt (the shared key for
    the Profile tab's friends list, scrambled so GitHub does not cancel it).

    WHAT IT DOES, IN ORDER
      1. Finds the RetroBat folder: the one this file is in, or asks.
      2. Downloads the wizard's update engine from GitHub, then uses it to
         install EVERYTHING, exactly the way an update does: every file is
         checked against its SHA-256 before it lands. A fresh install is an
         update from "nothing".
      3. Puts the friends-list key and the wizard's button in place.
      4. Gets the ckau-book theme (the look the wizard is built for) from its
         own GitHub, unless it is already there or the person presses N.
         Added 2026-10-12 (Steven: "install ckau automatically ... less extra
         steps"). The wizard's setup switches RetroBat to it by itself.
      5. Opens the wizard's first-run setup (Quick or Advanced).

    Nothing outside the RetroBat folder is touched here. The setup that follows
    asks before it puts buttons on the computer.

    ASCII ONLY, Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Repo = 'Feirzen/retrobat-wizard'

function Say([string]$m, [string]$c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Stop-Install([string]$m) { Write-Host ''; Say $m 'Yellow'; Write-Host ''; exit 1 }

Write-Host ''
Say 'RetroBat Wizard installer' 'Cyan'
Say '-------------------------' 'DarkGray'

# --- 1. where is RetroBat? ----------------------------------------------------
function Test-RetroBatFolder([string]$p) { return ($p -and (Test-Path -LiteralPath (Join-Path $p 'retrobat.ini')) -and (Test-Path -LiteralPath (Join-Path $p 'RetroBat.exe'))) }
$root = ''
foreach ($cand in @($Here, (Split-Path $Here -Parent), (Join-Path $Here 'RetroBat'))) {
    if (Test-RetroBatFolder $cand) { $root = $cand; break }
}
if ($root -eq '') {
    Say 'This is not inside a RetroBat folder. Pick your RetroBat folder (the one with RetroBat.exe in it).'
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Pick your RetroBat folder (the one with RetroBat.exe in it)'
        if ($dlg.ShowDialog() -eq 'OK' -and (Test-RetroBatFolder $dlg.SelectedPath)) { $root = $dlg.SelectedPath }
    } catch { }
}
if ($root -eq '') { Stop-Install 'No RetroBat folder found. Install RetroBat first (see the website), open it once, then run this again from inside its folder.' }
Say ("RetroBat folder: {0}" -f $root) 'White'
if ($root -match ' ') { Say 'Heads up: the folder path has a space in it. RetroBat suggests a path with no spaces; some emulators can trip on them.' 'Yellow' }

foreach ($p in @('emulationstation', 'RetroBat', 'BatGui')) {
    if (@(Get-Process -Name $p -ErrorAction SilentlyContinue).Count -gt 0) { Stop-Install 'RetroBat is open. Close it completely, then run this again.' }
}

$vf = Join-Path $root 'system\version.info'
if (Test-Path -LiteralPath $vf) {
    $rbv = ([System.IO.File]::ReadAllText($vf)).Trim()
    Say ("RetroBat version: {0}" -f $rbv)
    if ($rbv -match '^v?(\d+)\.' -and [int]$Matches[1] -lt 8) { Say 'This RetroBat is older than version 8. The wizard was built on 8.2, so please update RetroBat first if anything acts up.' 'Yellow' }
}

$ws = Join-Path $root '_ClaudeWorkspace'
if (Test-Path -LiteralPath (Join-Path $ws 'version.txt')) {
    Say 'The wizard is already installed here. This only adds anything newer; updates normally come from the wizard''s Help tab.' 'Yellow'
}
foreach ($d in @($ws, (Join-Path $ws 'scripts'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }

# --- 2. the engine, then everything through it -----------------------------
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
$ProgressPreference = 'SilentlyContinue'
Write-Host ''
Say 'Downloading the wizard. The first time takes a few minutes; every file is checked.' 'White'
try {
    $latest = (Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/$Repo/main/latest.ini?t=" + [DateTime]::UtcNow.Ticks) -UseBasicParsing -TimeoutSec 60).Content
    $tag = ''
    foreach ($l in ($latest -split "`r?`n")) { if ($l -match '^\s*tag\s*=\s*(\S+)') { $tag = $Matches[1] } }
    if ($tag -eq '') { throw 'latest.ini has no tag' }
    $engine = Join-Path $ws 'scripts\UpdateEngine.ps1'
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/$tag/drive/scripts/UpdateEngine.ps1" -OutFile $engine -UseBasicParsing -TimeoutSec 60
}
catch { Stop-Install ('Could not reach GitHub: ' + $_.Exception.Message + '. Check the internet connection and run this again.') }

. $engine
$st = Invoke-UpdateCheck -Ws $ws -Progress { param($m) Say $m 'DarkGray' }
if ($st.state -eq 'uptodate') { Say 'Every file is already in place.' 'Green' }
elseif ($st.state -ne 'ready') { Stop-Install ("The download did not finish: {0} Run this again; it carries on where it stopped." -f $st.message) }
else {
    $r = Invoke-UpdateInstall -Ws $ws -NoPostSteps -Progress { param($m) Say $m 'DarkGray' }
    if (-not $r.Ok) { Stop-Install $r.Message }
    Say ("Installed version {0}: {1} files." -f $r.Version, ($r.Changed + $r.Added)) 'Green'
}

# --- 3. the friends-list key and the wizard's button --------------------------
$tokenSrc = Join-Path $Here 'token.txt'
$tokenDst = Join-Path $ws 'social\social-token.txt'
if ((Test-Path -LiteralPath $tokenSrc) -and -not (Test-Path -LiteralPath $tokenDst)) {
    [void](New-Item -ItemType Directory -Path (Split-Path $tokenDst -Parent) -Force)
    Copy-Item -LiteralPath $tokenSrc -Destination $tokenDst
    Say 'Friends list key in place.'
}
$name = 'RetroBat Wizard'
$ini = Join-Path $ws 'wizard\wizard.ini'
if (Test-Path -LiteralPath $ini) {
    foreach ($l in [System.IO.File]::ReadAllLines($ini)) { if ($l -match '^\s*name\s*=\s*(.+?)\s*$') { $name = $Matches[1] } }
}
$btn = Join-Path $root ($name + '.bat')
$tpl = Join-Path $ws 'defaults\Setup Wizard.bat'
if ((Test-Path -LiteralPath $tpl) -and -not (Test-Path -LiteralPath $btn)) { Copy-Item -LiteralPath $tpl -Destination $btn; Say ("Made the button '{0}.bat' in your RetroBat folder." -f $name) }
[System.IO.File]::WriteAllText((Join-Path $ws 'first-run.txt'), ("Installed {0}. The wizard's first-run setup reads this and then sets it aside." -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))

# --- 4. the ckau-book theme, straight from its own GitHub ---------------------
#  RetroBat's own theme downloader fetches the same thing. curl.exe (in every
#  Windows 10 and 11) is used when it is there because it shows how far it
#  has got; Invoke-WebRequest otherwise. Unpacked into a short folder in the
#  RetroBat folder (some theme paths are long, and Windows dislikes paths
#  over 260 letters), then moved into place, so a half-done copy never looks
#  like a theme.
$themes = Join-Path $root 'emulationstation\.emulationstation\themes'
$ckau = Join-Path $themes 'ckau-book'
if (Test-Path -LiteralPath (Join-Path $ckau 'theme.xml')) {
    Say 'The ckau-book theme is already here.'
}
else {
    Write-Host ''
    Say 'Next: the ckau-book theme, the look this wizard is built for. It is a big download (1 to 2 GB).' 'White'
    $ans = (Read-Host '  Press Enter to get it now, or type N and Enter to skip').Trim().ToUpper()
    if ($ans -eq 'N') { Say 'Skipped. The wizard explains how to get it later.' 'Yellow' }
    else {
        $zip = Join-Path $ws 'ckau-book-download.zip'
        $tmpDir = Join-Path $root '_ck'
        try {
            if (-not (Test-Path -LiteralPath $themes)) { [void](New-Item -ItemType Directory -Path $themes -Force) }
            $url = 'https://github.com/CkauNui/ckau-book/archive/refs/heads/master.zip'
            Say 'Downloading ckau-book. This can take a while; leave this window open.' 'DarkGray'
            $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
            if (Test-Path -LiteralPath $curl) {
                if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
                & $curl -L --fail --retry 3 -o $zip $url
                if ($LASTEXITCODE -ne 0) { throw "the download stopped (curl $LASTEXITCODE)" }
            }
            else { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 3600 }
            Say 'Unpacking ckau-book...' 'DarkGray'
            if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmpDir)
            # the zip holds one folder (ckau-book-master); that folder is the theme
            $inner = @(Get-ChildItem -LiteralPath $tmpDir -Directory)
            $src = $(if ($inner.Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $tmpDir 'theme.xml'))) { $inner[0].FullName } else { $tmpDir })
            if (-not (Test-Path -LiteralPath (Join-Path $src 'theme.xml'))) { throw 'the download did not look like the theme' }
            if (Test-Path -LiteralPath $ckau) { Rename-Item -LiteralPath $ckau -NewName ('ckau-book-old-' + (Get-Date -Format 'yyyyMMddHHmmss')) }
            Move-Item -LiteralPath $src -Destination $ckau
            if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
            Remove-Item -LiteralPath $zip -Force
            Say 'ckau-book is in place. The wizard switches RetroBat to it.' 'Green'
        }
        catch {
            Say ('ckau-book could not be set up: ' + $_.Exception.Message) 'Yellow'
            Say 'Everything else works without it. Run this installer again to try again.' 'Yellow'
            try { if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force } } catch { }
            try { if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force } } catch { }
        }
    }
}

# --- 5. the wizard's own setup --------------------------------------------------
Write-Host ''
Say 'Done. Opening the wizard''s setup now: pick Quick setup if you are not sure.' 'Green'
$vbs = Join-Path $ws 'wizard\Launch-Wizard.vbs'
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @('//nologo', ('"' + $vbs + '"'), '-Setup')
Start-Sleep -Seconds 2
