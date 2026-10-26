<#
    Install-Wizard.ps1 - the RetroBat Wizard installer. SOURCE FILE.

    Nobody runs this file directly. tools/make_installer.py wraps it into ONE
    file, INSTALL THE WIZARD.bat, with the friends-list key and the little
    mage picture written in (the @@ markers below), and zips that one file
    for the website. One file means it runs straight out of the zip: no
    unzipping, nothing left lying around.

    REBUILT 2026-10-25 after Steven sat through 30+ minutes at a friend's
    house watching a black window. What changed:
      - A real window with three bars, a mage riding each one, and how long
        is left.
      - Step 1 is ONE download (package/wizard-package.zip on main, about
        17 MB) instead of 263 separate ones. Its files go where
        the update engine keeps a download, and the engine then checks every
        one against its SHA-256 exactly as before, fetching only anything the
        package did not have. If the package is missing it falls back to one
        file at a time, so an older version still installs.
      - The ckau-book theme (1.7 GB) starts as soon as step 1's download is
        done and keeps going in the background. The wizard's setup opens the
        moment step 2 is done, so nobody waits for the theme. When the theme
        lands, the next PLAY switches RetroBat to it (that part is the
        wizard's, unchanged).

    WHAT IT TOUCHES: only the RetroBat folder it is pointed at. A log of every
    run goes to _ClaudeWorkspace\update\install.log.

    ASCII ONLY, Windows PowerShell 5.1. Run through iex by the .bat, so no
    param() block and no $PSScriptRoot: the .bat hands its own path over in
    the environment variable RBW_SELF.
#>
$ErrorActionPreference = 'Stop'

$Repo     = 'Feirzen/retrobat-wizard'
$Token    = '@@TOKEN@@'
$MageB64  = '@@MAGE@@'
$ThemeUrl = 'https://github.com/CkauNui/ckau-book/archive/refs/heads/master.zip'
# GitHub makes the theme's zip on the spot and often does not say how big it
# is. Measured 2026-10-25: 1.77 GB unpacked; the zip is about the same.
$ThemeGuess = [long]1750 * 1MB
$RawBase  = 'https://raw.githubusercontent.com'
if ($env:RBW_TEST_RAW) { $RawBase = $env:RBW_TEST_RAW }          # tests only
if ($env:RBW_TEST_THEME) { $ThemeUrl = $env:RBW_TEST_THEME }      # tests only

$Self = [string]$env:RBW_SELF
if ($Self -eq '' -and $PSCommandPath) { $Self = $PSCommandPath }
$Here = $(if ($Self -ne '') { Split-Path -Parent $Self } else { (Get-Location).Path })

# =============================================================================
#  THE WORK. Runs on two background threads (runspaces) so the window stays
#  alive. They talk to the window only through $RBI, a synchronized table:
#    F1..F3  how far each bar is (0 to 1)      T1..T3  the line under it
#    St1..St3  wait / run / done / skip / fail
#    ADone, AErr   steps 1 and 2 finished, or why not
#    TDone         the theme thread finished (either way)
#    ThemeGo       step 1's download is done: the theme may start
#    Cancel        the window asked everything to stop
# =============================================================================
$Common = @'
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
$Sep = [string][System.IO.Path]::DirectorySeparatorChar
function Join-Rel([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

function Note([string]$m) {
    [System.Threading.Monitor]::Enter($RBI.LogLock)
    try { [System.IO.File]::AppendAllText($RBI.LogFile, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m + "`r`n")) } catch { }
    finally { [System.Threading.Monitor]::Exit($RBI.LogLock) }
}

# One download, with its progress on bar $Bar between $From and $To.
function Get-Download([string]$Url, [string]$Out, [int]$Bar, [long]$Guess, [double]$From, [double]$To, [string]$What) {
    $part = $Out + '.part'
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = 'RetroBat-Wizard-Installer'
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 120000
    $req.Headers.Add('Cache-Control', 'no-cache')
    $resp = $req.GetResponse()
    $in = $null; $fs = $null; $done = [long]0
    $exact = ($resp.ContentLength -gt 0)
    $total = $(if ($exact) { [long]$resp.ContentLength } else { $Guess })
    try {
        $in = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($part, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 1048576)
        $buf = New-Object byte[] 262144
        $last = [DateTime]::MinValue
        while ($true) {
            $n = $in.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $fs.Write($buf, 0, $n)
            $done += $n
            if ($RBI.Cancel) { throw 'stopped' }
            $now = [DateTime]::UtcNow
            if (($now - $last).TotalMilliseconds -ge 200) {
                $last = $now
                $f = [math]::Min(0.995, [double]$done / [double][math]::Max($total, $done + 1))
                $RBI["F$Bar"] = $From + ($To - $From) * $f
                if ($exact) { $RBI["T$Bar"] = ('{0}: {1:N1} of {2:N1} MB' -f $What, ($done / 1MB), ($total / 1MB)) }
                else { $RBI["T$Bar"] = ('{0}: {1:N0} of about {2:N0} MB' -f $What, ($done / 1MB), ([math]::Max($total, $done) / 1MB)) }
            }
        }
    }
    finally {
        if ($null -ne $fs) { $fs.Dispose() }
        if ($null -ne $in) { $in.Dispose() }
        $resp.Close()
    }
    if ($exact -and $done -ne $total) { throw ('the download was cut short ({0} of {1} bytes)' -f $done, $total) }
    if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Force }
    Move-Item -LiteralPath $part -Destination $Out
    $RBI["F$Bar"] = $To
    return $done
}

# Unpacks a zip into $Dest, dropping the first $Strip folder levels of every
# name, with its progress on bar $Bar. Refuses any name that would land
# outside $Dest.
function Expand-Zip([string]$Zip, [string]$Dest, [int]$Bar, [double]$From, [double]$To, [int]$Strip, [string]$What) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destFull = [System.IO.Path]::GetFullPath($Dest).TrimEnd($Sep)
    [void][System.IO.Directory]::CreateDirectory($destFull)
    $z = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $all = $z.Entries.Count; $i = 0; $last = [DateTime]::MinValue
        foreach ($en in $z.Entries) {
            $i++
            if ($RBI.Cancel) { throw 'stopped' }
            $parts = @($en.FullName -split '[\\/]' | Where-Object { $_ -ne '' })
            if ($parts.Count -le $Strip) { continue }
            $rel = ($parts[$Strip..($parts.Count - 1)] -join $Sep)
            $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destFull, $rel))
            if (-not $target.StartsWith($destFull + $Sep, [StringComparison]::OrdinalIgnoreCase)) { throw ('the download holds an unsafe name: ' + $en.FullName) }
            if ($en.FullName.EndsWith('/')) { [void][System.IO.Directory]::CreateDirectory($target); continue }
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($en, $target, $true)
            $now = [DateTime]::UtcNow
            if (($now - $last).TotalMilliseconds -ge 200) {
                $last = $now
                $RBI["F$Bar"] = $From + ($To - $From) * ([double]$i / [double]$all)
                $RBI["T$Bar"] = ('{0}: {1:N0} of {2:N0} files' -f $What, $i, $all)
            }
        }
    }
    finally { $z.Dispose() }
    $RBI["F$Bar"] = $To
}
'@

# --- steps 1 and 2: the wizard ------------------------------------------------
$WorkA = @'
try {
    $ws = $RBI.Ws
    Note ('install: starting, into ' + $RBI.Root)
    $RBI.St1 = 'run'; $RBI.T1 = 'Asking GitHub for the newest version'
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'RetroBat-Wizard-Installer')
    $wc.Headers.Add('Cache-Control', 'no-cache')
    $latest = $wc.DownloadString(('{0}/{1}/main/latest.ini?t={2}' -f $RBI.RawBase, $RBI.Repo, [DateTime]::UtcNow.Ticks))
    $ver = ''; $tag = ''
    foreach ($l in ($latest -split "`r?`n")) {
        if ($l -match '^\s*version\s*=\s*(\S+)') { $ver = $Matches[1] }
        if ($l -match '^\s*tag\s*=\s*(\S+)') { $tag = $Matches[1] }
    }
    if ($ver -eq '' -or $tag -eq '') { throw 'GitHub''s latest.ini has no version or tag' }
    Note ('install: newest is {0} ({1})' -f $ver, $tag)
    $RBI.Version = $ver

    foreach ($d in @($ws, (Join-Rel $ws 'scripts'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
    $engine = Join-Rel $ws 'scripts\UpdateEngine.ps1'
    [void](Get-Download ('{0}/{1}/{2}/drive/scripts/UpdateEngine.ps1' -f $RBI.RawBase, $RBI.Repo, $tag) $engine 1 100000 0.0 0.02 'The update engine')
    . $engine
    if ($RBI.RawBase -ne 'https://raw.githubusercontent.com') {
        # tests only: the engine's own downloads go to the test server too
        $script:UpdFetchOverride = { param($Url, $OutFile) (New-Object System.Net.WebClient).DownloadFile($Url.Replace('https://raw.githubusercontent.com', $RBI.RawBase), $OutFile) }
    }

    $P = Get-UpdPaths $ws
    $cfg = Get-UpdConfig $ws
    New-UpdDir $P.Dir
    $inDir = Join-UpdPath $P.Incoming (Get-UpdIncomingName $ver $tag $cfg)

    # --- a half-finished install from before -------------------------------
    #  (2026-10-25) A download that is READY but still waiting means the last
    #  install never finished. Older engines put version.txt in place early,
    #  so that drive says it is up to date with half its files missing.
    #  Setting version.txt aside makes the engine finish the job; every file
    #  already in place is skipped by its checksum.
    $vt = Join-UpdPath $ws 'version.txt'
    if ((Test-Path -LiteralPath (Join-UpdPath $inDir 'READY.txt')) -and (Test-Path -LiteralPath $vt)) {
        Move-Item -LiteralPath $vt -Destination (Join-UpdPath $P.Dir ('version-unfinished-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')) -Force
        Note 'install: the last install never finished, finishing it now'
    }

    # --- the whole wizard in one download ---------------------------------
    #  From main, not from the version's own commit: the package does not have
    #  to be the newest (the engine checks every file and fetches whatever it
    #  lacks or has older), so the website can get a new package any time.
    $pkg = Join-UpdPath $P.Dir 'wizard-package.zip'
    $havePkg = $false
    $RBI.T1 = 'Downloading the wizard'
    try {
        $bytes = Get-Download ('{0}/{1}/main/package/wizard-package.zip' -f $RBI.RawBase, $RBI.Repo) $pkg 1 ([long]20 * 1MB) 0.02 0.80 'Downloading'
        $havePkg = $true
        Note ('install: package downloaded, {0:N1} MB' -f ($bytes / 1MB))
    }
    catch {
        if ($RBI.Cancel) { throw }
        Note ('install: no single package (' + $_.Exception.Message + '), getting the files one at a time')
    }
    $RBI.ThemeGo = $true      # the internet connection is free for the theme now
    if ($havePkg) {
        Expand-Zip $pkg (Join-UpdPath $inDir 'files') 1 0.80 0.90 0 'Unpacking'
        Remove-Item -LiteralPath $pkg -Force
    }

    # --- the engine checks every file, and fetches anything still missing ----
    $lo = $(if ($havePkg) { 0.90 } else { 0.02 })
    $RBI.T1 = 'Checking every file'
    $st = Invoke-UpdateCheck -Ws $ws -Progress {
        param($m)
        if ($m -match 'Downloading (\d+) of (\d+)') {
            $RBI.F1 = $lo + (1 - $lo) * ([double]$Matches[1] / [double]$Matches[2])
            $RBI.T1 = ('Downloading file {0} of {1}' -f $Matches[1], $Matches[2])
        }
    }
    if ($RBI.Cancel) { throw 'stopped' }
    if ($st.state -eq 'uptodate') {
        Note 'install: every file already in place'
        $RBI.F1 = 1.0; $RBI.St1 = 'done'; $RBI.T1 = ('Version {0} was already here' -f $ver)
        $RBI.F2 = 1.0; $RBI.St2 = 'done'; $RBI.T2 = 'Nothing needed changing'
    }
    elseif ($st.state -ne 'ready') { throw ([string]$st.message) }
    else {
        $RBI.F1 = 1.0; $RBI.St1 = 'done'; $RBI.T1 = ('Version {0}, every file checked' -f $ver)
        # --- step 2 ------------------------------------------------------------
        $RBI.St2 = 'run'; $RBI.T2 = 'Putting the files in place'
        $r = Invoke-UpdateInstall -Ws $ws -NoPostSteps -Progress {
            param($m)
            if ($m -match '(\d+) of (\d+)') {
                $RBI.F2 = [double]$Matches[1] / [double]$Matches[2]
                $RBI.T2 = ('File {0} of {1}' -f $Matches[1], $Matches[2])
            }
        }
        if (-not $r.Ok) { throw ([string]$r.Message) }
        Note ('install: version {0} in place, {1} files' -f $r.Version, ($r.Changed + $r.Added))
    }

    # --- the friends-list key, the wizard's button, the first-run note ----------
    $tokenDst = Join-Rel $ws 'social\social-token.txt'
    if ($RBI.Token -ne '' -and -not $RBI.Token.StartsWith('@@') -and -not (Test-Path -LiteralPath $tokenDst)) {
        [void](New-Item -ItemType Directory -Path (Split-Path $tokenDst -Parent) -Force)
        [System.IO.File]::WriteAllText($tokenDst, ($RBI.Token + "`n"))
        Note 'install: friends list key in place'
    }
    $name = 'RetroBat Wizard'
    $ini = Join-Rel $ws 'wizard\wizard.ini'
    if (Test-Path -LiteralPath $ini) {
        foreach ($l in [System.IO.File]::ReadAllLines($ini)) { if ($l -match '^\s*name\s*=\s*(.+?)\s*$') { $name = $Matches[1] } }
    }
    $btn = Join-Path $RBI.Root ($name + '.bat')
    $tpl = Join-Rel $ws 'defaults\Setup Wizard.bat'
    if ((Test-Path -LiteralPath $tpl) -and -not (Test-Path -LiteralPath $btn)) { Copy-Item -LiteralPath $tpl -Destination $btn; Note ('install: made ' + $btn) }
    if (-not (Test-Path -LiteralPath (Join-Path $ws 'first-run.txt')) -and -not (Test-Path -LiteralPath (Join-Path $ws 'profile'))) {
        [System.IO.File]::WriteAllText((Join-Path $ws 'first-run.txt'), ("Installed {0}. The wizard's first-run setup reads this and then sets it aside." -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
    }
    $RBI.F2 = 1.0; $RBI.St2 = 'done'
    if ([string]$RBI.T2 -notmatch 'Nothing') { $RBI.T2 = 'Done' }
    Note 'install: steps 1 and 2 done'
    $RBI.ADone = $true
}
catch {
    $why = $(if ($RBI.Cancel) { 'stopped' } else { $_.Exception.Message })
    $RBI.AErr = $why
    Note ('install: FAILED - ' + $why)
    if ($RBI.St2 -eq 'run') { $RBI.St2 = 'fail' } else { $RBI.St1 = 'fail' }
}
finally { $RBI.ThemeGo = $true }
'@

# --- step 3: the ckau-book theme ------------------------------------------------
$WorkT = @'
$mark = Join-Rel $RBI.Ws 'update\theme-downloading.txt'
$zip = Join-Rel $RBI.Ws 'update\ckau-book.zip'
$tmp = Join-Path $RBI.Root '_ck'
try {
    $themes = Join-Rel $RBI.Root 'emulationstation\.emulationstation\themes'
    $ckau = Join-Path $themes 'ckau-book'
    if (Test-Path -LiteralPath (Join-Path $ckau 'theme.xml')) {
        $RBI.F3 = 1.0; $RBI.St3 = 'skip'; $RBI.T3 = 'Already here'
        Note 'theme: ckau-book already here'
        return
    }
    $RBI.St3 = 'wait'; $RBI.T3 = 'Starts as soon as the wizard is downloaded'
    while (-not $RBI.ThemeGo) { Start-Sleep -Milliseconds 200 }
    if ($RBI.AErr -ne '') { $RBI.T3 = 'Not started'; return }

    $free = [long](New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($RBI.Root)))).AvailableFreeSpace
    if ($free -gt 0 -and $free -lt 4GB) { throw ('only {0:N1} GB is free on that drive, and the theme needs about 4 GB while it unpacks' -f ($free / 1GB)) }

    [void](New-Item -ItemType Directory -Path (Split-Path $mark -Parent) -Force)
    [System.IO.File]::WriteAllText($mark, ('started {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $RBI.St3 = 'run'; $RBI.T3 = 'Starting the download'
    Note 'theme: downloading ckau-book'
    $bytes = Get-Download $RBI.ThemeUrl $zip 3 $RBI.ThemeGuess 0.0 0.88 'Downloading'
    Note ('theme: downloaded {0:N0} MB' -f ($bytes / 1MB))
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    # The zip holds one folder (ckau-book-master); its insides are the theme.
    Expand-Zip $zip $tmp 3 0.88 0.98 1 'Unpacking'
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-Path -LiteralPath (Join-Path $tmp 'theme.xml'))) { throw 'the download did not look like the theme' }
    if (-not (Test-Path -LiteralPath $themes)) { [void](New-Item -ItemType Directory -Path $themes -Force) }
    if (Test-Path -LiteralPath $ckau) { Rename-Item -LiteralPath $ckau -NewName ('ckau-book-old-' + (Get-Date -Format 'yyyyMMddHHmmss')) }
    Move-Item -LiteralPath $tmp -Destination $ckau

    # The drive's own collection pictures go into the theme. That script is
    # the wizard's, so wait for step 2 if it is somehow still going.
    while (-not $RBI.ADone -and $RBI.AErr -eq '') { Start-Sleep -Milliseconds 300 }
    $rs = Join-Rel $RBI.Ws 'scripts\Restore-CkauBookTheme.ps1'
    if ($RBI.ADone -and (Test-Path -LiteralPath $rs) -and $env:SystemRoot) {
        $RBI.T3 = 'Adding the collection pictures'
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        try { Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $rs + '"')) -WindowStyle Hidden -Wait }
        catch { Note ('theme: collection pictures not added - ' + $_.Exception.Message) }
    }
    $RBI.F3 = 1.0; $RBI.St3 = 'done'; $RBI.T3 = 'In place. The next PLAY switches RetroBat to it.'
    Note 'theme: ckau-book in place'
}
catch {
    $why = $(if ($RBI.Cancel) { 'stopped' } else { $_.Exception.Message })
    $RBI.St3 = 'fail'
    $RBI.T3 = $(if ($why -eq 'stopped') { 'Stopped. Run the installer again any time to get it.' } else { 'Could not get it: ' + $why })
    Note ('theme: FAILED - ' + $why)
    try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force } } catch { }
    try { foreach ($f in @($zip, ($zip + '.part'))) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } } catch { }
}
finally {
    try { if (Test-Path -LiteralPath $mark) { Remove-Item -LiteralPath $mark -Force } } catch { }
    $RBI.TDone = $true
}
'@

function Start-Worker([string]$Body, $Table) {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ([Environment]::OSVersion.Platform -eq 'Win32NT') { try { $iss.ExecutionPolicy = 'Bypass' } catch { } }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript("param(`$RBI)`n" + $Common + "`n" + $Body).AddArgument($Table)
    return @{ PS = $ps; Handle = $ps.BeginInvoke() }
}

# Tests run the two workers without any window (tools/tests/test-installer.ps1).
if ($env:RBW_TEST_NOUI) { return }

# =============================================================================
#  THE WINDOW
# =============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type -Namespace RBWI -Name Win -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);'
    [void][RBWI.Win]::ShowWindow([RBWI.Win]::GetConsoleWindow(), 0)     # the .bat's black window goes away
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$Owner = New-Object System.Windows.Forms.Form
$Owner.TopMost = $true; $Owner.ShowInTaskbar = $false; $Owner.Opacity = 0; $Owner.StartPosition = 'CenterScreen'; $Owner.Size = New-Object System.Drawing.Size(1, 1)
$Owner.FormBorderStyle = 'None'
$Owner.Show()     # an invisible window that keeps the question boxes on top
$script:form = $null
function Show-Box([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    $o = $Owner
    if ($null -ne $script:form -and $script:form.Visible) { $o = $script:form }
    return [string][System.Windows.Forms.MessageBox]::Show($o, $Text, 'RetroBat Wizard installer', $Buttons, $Icon)
}

try {
    # --- 1. where is RetroBat? ------------------------------------------------
    function Test-RetroBatFolder([string]$p) { return ($p -and (Test-Path -LiteralPath (Join-Path $p 'retrobat.ini')) -and (Test-Path -LiteralPath (Join-Path $p 'RetroBat.exe'))) }
    $root = ''
    foreach ($cand in @($Here, (Split-Path $Here -Parent), (Join-Path $Here 'RetroBat'))) {
        if ($cand -and (Test-RetroBatFolder $cand)) { $root = $cand; break }
    }
    $pick = $false
    if ($root -eq '') {
        # RetroBat's own installer suggests C:\RetroBat; then the top of every
        # other drive (RetroBat on an external drive).
        $look = @((Join-Path $env:SystemDrive 'RetroBat'))
        try { foreach ($d in [System.IO.DriveInfo]::GetDrives()) { if ($d.IsReady) { $look += (Join-Path $d.RootDirectory.FullName 'RetroBat') } } } catch { }
        foreach ($cand in ($look | Select-Object -Unique)) {
            if (Test-RetroBatFolder $cand) {
                $a = Show-Box ("Found RetroBat here:`n`n    {0}`n`nPut the wizard there?`n`nYes: install it there.`nNo: let me pick a different RetroBat folder." -f $cand) 'YesNoCancel' 'Question'
                if ($a -eq 'Cancel') { exit 0 }
                if ($a -eq 'Yes') { $root = $cand }
                break
            }
        }
    }
    while ($root -eq '') {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Pick your RetroBat folder (the one with RetroBat.exe in it)'
        if ($dlg.ShowDialog($Owner) -ne 'OK') {
            [void](Show-Box 'Nothing was installed. Install RetroBat first (see the website), open it once, then run this again.')
            exit 0
        }
        if (Test-RetroBatFolder $dlg.SelectedPath) { $root = $dlg.SelectedPath }
        else { [void](Show-Box 'That folder has no RetroBat.exe in it. Pick the RetroBat folder itself.' 'OK' 'Warning') }
    }

    # --- 2. RetroBat must be closed -------------------------------------------
    while (@(Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue).Count -gt 0) {
        if ((Show-Box 'RetroBat is open. Close it completely, then press Retry.' 'RetryCancel' 'Warning') -ne 'Retry') { exit 0 }
    }

    $ws = Join-Path $root '_ClaudeWorkspace'
    foreach ($d in @($ws, (Join-Path $ws 'update'))) { if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) } }
}
catch {
    [void](Show-Box ('The installer could not start: ' + $_.Exception.Message) 'OK' 'Error')
    exit 0
}

$RBI = [hashtable]::Synchronized(@{})
$RBI.Root = $root; $RBI.Ws = $ws; $RBI.Repo = $Repo; $RBI.RawBase = $RawBase; $RBI.Token = $Token
$RBI.ThemeUrl = $ThemeUrl; $RBI.ThemeGuess = $ThemeGuess
$RBI.LogFile = Join-Path $ws 'update\install.log'; $RBI.LogLock = New-Object object
foreach ($i in 1..3) { $RBI["F$i"] = 0.0; $RBI["T$i"] = 'Waiting'; $RBI["St$i"] = 'wait' }
$RBI.ADone = $false; $RBI.AErr = ''; $RBI.TDone = $false; $RBI.ThemeGo = $false; $RBI.Cancel = $false; $RBI.Version = ''

# --- colours, the mage ---------------------------------------------------------
function Rgb([int]$r, [int]$g, [int]$b) { return [System.Drawing.Color]::FromArgb($r, $g, $b) }
$cBg = Rgb 27 27 34; $cPanel = Rgb 35 35 44; $cText = Rgb 232 232 236; $cDim = Rgb 154 160 170
$cGold = Rgb 229 184 59; $cGoldHi = Rgb 247 214 120; $cGreen = Rgb 47 168 79; $cRed = Rgb 224 82 77; $cTrack = Rgb 52 52 64
$brTrack = New-Object System.Drawing.SolidBrush($cTrack)
$brGold = New-Object System.Drawing.SolidBrush($cGold); $brGoldHi = New-Object System.Drawing.SolidBrush($cGoldHi)
$brGreen = New-Object System.Drawing.SolidBrush($cGreen); $brRed = New-Object System.Drawing.SolidBrush($cRed)
$mage = $null
try {
    if (-not $MageB64.StartsWith('@@')) {
        $ms = New-Object System.IO.MemoryStream(, [Convert]::FromBase64String($MageB64))
        $mage = [System.Drawing.Image]::FromStream($ms)
    }
} catch { $mage = $null }

$fTitle = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$fName = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$fBody = New-Object System.Drawing.Font('Segoe UI', 9.5)

$form = New-Object System.Windows.Forms.Form
$script:form = $form
$form.Text = 'Installing the RetroBat Wizard'
$form.ClientSize = New-Object System.Drawing.Size(620, 520)
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'; $form.BackColor = $cBg; $form.ForeColor = $cText; $form.Font = $fBody
try { if ($null -ne $mage) { $form.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($mage)).GetHicon()) } } catch { }

function New-Label([string]$t, [int]$x, [int]$y, [int]$w, [int]$h, $font, $col) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font; $l.ForeColor = $col; $l.BackColor = [System.Drawing.Color]::Transparent
    $form.Controls.Add($l)
    return $l
}
[void](New-Label 'Installing the RetroBat Wizard' 24 16 572 32 $fTitle $cText)
$sub = 'Into ' + $root
if ($root -match ' ') { $sub += '   (heads up: a space in this path can trip some emulators)' }
[void](New-Label $sub 26 50 572 20 $fBody $cDim)

$names = @{ 1 = '1.  Download the wizard'; 2 = '2.  Put it in place'; 3 = '3.  The ckau-book look (1.7 GB, finishes in the background)' }
$lblEta = @{}; $lblDet = @{}; $bars = @{}
$script:shown = @{ 1 = 0.0; 2 = 0.0; 3 = 0.0 }
$script:hist = @{ 1 = (New-Object System.Collections.ArrayList); 2 = (New-Object System.Collections.ArrayList); 3 = (New-Object System.Collections.ArrayList) }
$script:tick = 0

$paint = {
    param($sender, $e)
    $i = [int]$sender.Tag
    $g = $e.Graphics
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
    $st = [string]$RBI["St$i"]
    $f = [double]$script:shown[$i]
    $x0 = 20; $x1 = $w - 20; $ty = $h - 16; $th = 10
    $g.FillRectangle($brTrack, $x0, $ty, ($x1 - $x0), $th)
    $fw = [int][math]::Round(($x1 - $x0) * [math]::Max(0.0, [math]::Min(1.0, $f)))
    $br = $brGold
    if ($st -eq 'done' -or $st -eq 'skip') { $br = $brGreen; $fw = $x1 - $x0 }
    elseif ($st -eq 'fail') { $br = $brRed }
    if ($fw -gt 0) {
        $g.FillRectangle($br, $x0, $ty, $fw, $th)
        if ($br -eq $brGold) { $g.FillRectangle($brGoldHi, $x0, $ty, $fw, 2) }
    }
    if ($st -eq 'run' -and $null -ne $mage) {
        $t = $script:tick
        $mx = [math]::Max(0, [math]::Min($w - 36, $x0 + $fw - 18))
        $bob = [int][math]::Round([math]::Sin(($t / 4.0) + $i) * 2.0)
        $my = $ty - 52 + 5 + $bob
        # a few sparks trailing behind
        for ($k = 1; $k -le 4; $k++) {
            $sx = $mx - (7 * $k) - ($t % 7)
            $sy = $ty - 6 - ((($t + ($k * 5)) % 14))
            if ($sx -gt $x0) { $g.FillRectangle($brGoldHi, $sx, $sy, 2, 2) }
        }
        $g.DrawImage($mage, $mx, $my, 36, 52)
    }
}

for ($i = 1; $i -le 3; $i++) {
    $y = 86 + ($i - 1) * 124
    [void](New-Label $names[$i] 24 $y 420 24 $fName $cText)
    $lblEta[$i] = New-Label '' 330 ($y + 2) 266 22 $fBody $cDim
    $lblEta[$i].TextAlign = 'TopRight'
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(4, ($y + 24)); $p.Size = New-Object System.Drawing.Size(612, 66)
    $p.BackColor = $cBg; $p.Tag = $i
    try { $p.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($p, $true, $null) } catch { }
    $p.Add_Paint($paint)
    $form.Controls.Add($p)
    $bars[$i] = $p
    $lblDet[$i] = New-Label 'Waiting' 24 ($y + 92) 572 22 $fBody $cDim
}
$foot = New-Label 'Getting ready...' 24 458 470 54 $fBody $cText
$btn = New-Object System.Windows.Forms.Button
$btn.Text = 'Close'; $btn.Location = New-Object System.Drawing.Point(506, 470); $btn.Size = New-Object System.Drawing.Size(90, 32)
$btn.FlatStyle = 'Flat'; $btn.BackColor = $cPanel; $btn.ForeColor = $cText; $btn.Visible = $false
$btn.Add_Click({ $form.Close() })
$form.Controls.Add($btn)

function Format-Left([double]$sec) {
    if ($sec -lt 50) { return 'under a minute left' }
    if ($sec -lt 90) { return 'about a minute left' }
    if ($sec -lt 5400) { return ('about {0} minutes left' -f [int][math]::Round($sec / 60)) }
    return ('about {0:N1} hours left' -f ($sec / 3600))
}

$script:launched = $false; $script:errShown = $false; $script:endAt = $null; $script:allowClose = $false
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({
    $script:tick++
    $now = [DateTime]::UtcNow
    for ($i = 1; $i -le 3; $i++) {
        $target = [double]$RBI["F$i"]
        $script:shown[$i] = $script:shown[$i] + ($target - $script:shown[$i]) * 0.25
        $st = [string]$RBI["St$i"]
        if ($st -eq 'run' -or $script:tick % 10 -eq 0) { $bars[$i].Invalidate() }
        if ($script:tick % 4 -eq 0) {
            $lblDet[$i].Text = [string]$RBI["T$i"]
            $h = $script:hist[$i]
            if ($st -eq 'run') {
                [void]$h.Add(@($now, $target))
                while ($h.Count -gt 2 -and ($now - $h[0][0]).TotalSeconds -gt 15) { $h.RemoveAt(0) }
            }
        }
        if ($script:tick % 20 -eq 0) {
            $h = $script:hist[$i]
            switch ($st) {
                'done' { $lblEta[$i].Text = 'Done'; $lblEta[$i].ForeColor = $cGreen }
                'skip' { $lblEta[$i].Text = 'Already here'; $lblEta[$i].ForeColor = $cGreen }
                'fail' { $lblEta[$i].Text = $(if ($RBI.Cancel) { 'Stopped' } else { 'Did not finish' }); $lblEta[$i].ForeColor = $cRed }
                'wait' { $lblEta[$i].Text = 'Waiting' }
                'run' {
                    $txt = 'Working...'
                    if ($h.Count -ge 2) {
                        $dt = ($h[$h.Count - 1][0] - $h[0][0]).TotalSeconds
                        $df = [double]$h[$h.Count - 1][1] - [double]$h[0][1]
                        if ($dt -ge 3 -and $df -gt 0) { $txt = Format-Left ((1.0 - $target) * $dt / $df) }
                    }
                    $lblEta[$i].Text = $txt
                }
            }
        }
    }

    if ($RBI.ADone -and -not $script:launched) {
        $script:launched = $true
        $vbs = Join-Path $RBI.Ws 'wizard\Launch-Wizard.vbs'
        try {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @('//nologo', ('"' + $vbs + '"'), '-Setup')
            $foot.Text = "The wizard's setup is opening in its own window. Go ahead with it (pick Quick setup if you are not sure)."
        }
        catch { $foot.Text = "The wizard is installed. Open it with 'RetroBat Wizard' in your RetroBat folder." }
    }
    if ($RBI.AErr -ne '' -and -not $script:errShown) {
        $script:errShown = $true
        $RBI.Cancel = $true
        $foot.ForeColor = $cRed
        $foot.Text = $(if ($RBI.AErr -eq 'stopped') { 'Stopped. Run the installer again any time; it carries on where it stopped.' }
                       else { 'It stopped: ' + $RBI.AErr + "`nRun the installer again; it carries on where it stopped. Details: _ClaudeWorkspace\update\install.log" })
        $btn.Visible = $true
    }
    if ($RBI.ADone -and $RBI.TDone -and $null -eq $script:endAt) {
        $script:endAt = $now.AddSeconds(10)
        $foot.ForeColor = $cText
        $foot.Text = $(if ($RBI.St3 -eq 'fail') { "The wizard is installed. The theme can come later: run this installer again any time.`nThis window closes in a few seconds." }
                       else { "All done! This window closes in a few seconds." })
        $btn.Visible = $true
    }
    elseif ($RBI.ADone -and -not $RBI.TDone -and $script:launched -and $script:tick % 20 -eq 0) {
        $foot.Text = "The wizard's setup is open in its own window: go ahead with it.`nLeave this window open until the last bar is done. It closes by itself."
    }
    if ($null -ne $script:endAt -and $now -ge $script:endAt) { $script:allowClose = $true; $form.Close() }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:allowClose -or $RBI.AErr -ne '') { return }
    $aRun = -not $RBI.ADone
    $tRun = -not $RBI.TDone
    if ($aRun -and $RBI.St2 -eq 'run') {
        [void](Show-Box 'Almost done: the wizard is being put in place right now. Give it a moment.')
        $e.Cancel = $true; return
    }
    if ($aRun) {
        if ((Show-Box "Stop installing?`n`nNothing is left half-done. Run the installer again later and it carries on." 'YesNo' 'Question') -ne 'Yes') { $e.Cancel = $true; return }
        $RBI.Cancel = $true
    }
    elseif ($tRun) {
        if ((Show-Box "Stop the ckau-book download?`n`nEverything works without it. Run the installer again any time to get it." 'YesNo' 'Question') -ne 'Yes') { $e.Cancel = $true; return }
        $RBI.Cancel = $true
        $until = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $RBI.TDone -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 200 }
    }
})

$form.Add_Shown({
    $Owner.Hide()
    $form.Activate()
    $script:wA = Start-Worker $WorkA $RBI
    $script:wT = Start-Worker $WorkT $RBI
    $timer.Start()
})
[void]$form.ShowDialog()
$timer.Stop()
# The background threads end with this program.
[Environment]::Exit(0)
