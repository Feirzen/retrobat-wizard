<#
    UpdateEngine.ps1 - keeps this drive's wizard up to date from GitHub.

    FUNCTIONS ONLY. Dot-source it, it never does anything by itself. The
    things that run it:

        wizard\SetupWizard.ps1           checks in the background when the
                                         window opens, shows a bar at the top
                                         when an update is ready
        scripts\Updater.ps1              installs or goes back, in its own
                                         process, after the wizard has closed
        Maintenance Steps\Check For Updates.bat     the same, without the
        Maintenance Steps\Go Back One Update.bat    window

    HOW IT WORKS
    ------------
    The public repo (Feirzen/retrobat-wizard unless update\update.ini says
    otherwise) holds:

        latest.ini     the newest version, its git tag, and one line of notes
        manifest.txt   at that tag: every file the update owns, with its
                       SHA-256, its size and its path under _Wizard
        drive\...      the files themselves

    1. CHECK. Read latest.ini. Newer than version.txt, and not the version
       somebody just went back from? When the wizard opens it stops there
       (-NoDownload) and only shows the Update now bar. Pressing the button
       carries on: read the manifest at that tag. Download
       ONLY the files that differ from what is on the drive, into
       update\incoming\<version>\, and check every one against its SHA-256.
       Only when all of them check out is READY.txt written. A half-finished
       download is never READY, and the next check carries on from the files
       that did arrive.

    2. INSTALL, straight after the download, only ever because somebody
       pressed a button, never while RetroBat is open.
       Every file that is about to be replaced is first copied into
       update\previous\, and every step is written to a journal there AS IT
       HAPPENS. If anything fails partway, the journal is walked backwards and
       the drive is exactly as it was.

    3. GO BACK. The same journal, walked backwards on purpose, from the Help
       tab. The version gone back from is remembered in update\skip.txt, so
       the same update is not offered again straight away. A NEWER one is.

    TWO CHANNELS (2026-10-12, Steven: "a dev branch toggle on the admin's
    wizard, so I can see the latest update that's active, or toggle the dev
    branch instead and see the one under development"):
        stable   latest.ini        what everybody gets (the default)
        dev      latest-dev.ini    the version being worked on
    Both files sit on the main branch; each names a COMMIT, so the dev build
    can live on any branch. update\update.ini "channel = dev" picks dev.
    update\installed.ini remembers the version, commit and channel that were
    last installed, which is how the check knows when:
      - the channel was switched: the other channel's version is offered,
        even when it is OLDER (stable after dev is a step back on purpose)
      - a dev build was republished under the same version number: on dev a
        different commit is enough to offer it
    Go back after a switch also switches the channel back.

    TWO KINDS OF FILE in the manifest:
        code   the update owns it. Replaced whenever it differs.
        seed   the PERSON owns it (features.ini, wizard.ini, ...). Written
               only if it is missing, never touched after that.
    Anything not in the manifest is not the update's business and is never
    touched: saves, roms, machines, the profile, the personal pack, logs.

    NOTHING IS EVER DELETED. Replaced files go into update\previous\, and the
    previous\ from the update before that moves into _SAFE TO DELETE.

    NO DRIVE LETTERS. Every path is built from the $Ws it is handed.

    ASCII ONLY, Windows PowerShell 5.1. Two hooks exist for the test harness,
    which runs all of this on a fake drive with a fake GitHub:
        $script:UpdFetchOverride    { param($Url, $OutFile) ... }
        $script:UpdRunningOverride  { $true / $false }
#>

$script:UpdDefaultRepo   = 'Feirzen/retrobat-wizard'
$script:UpdDefaultBranch = 'main'
$script:UpdFetchOverride   = $null
$script:UpdRunningOverride = $null

# ---------------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------------
function Join-UpdPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) {
        if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) }
    }
    return $p
}

function Get-UpdPaths([string]$Ws) {
    $dir = Join-UpdPath $Ws 'Program\update'
    return @{
        Ws        = $Ws
        Dir       = $dir
        Status    = Join-UpdPath $dir 'status.ini'
        Incoming  = Join-UpdPath $dir 'incoming'
        Previous  = Join-UpdPath $dir 'previous'
        Installed = Join-UpdPath $dir 'installed-manifest.txt'
        Skip      = Join-UpdPath $dir 'skip.txt'
        Log       = Join-UpdPath $dir 'update.log'
        Lock      = Join-UpdPath $dir 'lock.txt'
        Config    = Join-UpdPath $dir 'update.ini'
        Safe      = Join-UpdPath $Ws 'Cache\Trash'
        Version   = Join-UpdPath $Ws 'version.txt'
    }
}

# ---------------------------------------------------------------------------
#  THE WORKSHOP DRIVE (added 2026-10-14)
#  The drive the wizard is BUILT on is always ahead of what is on GitHub. On
#  2026-10-13 an update there put the published copy back over a day of new
#  work. So that drive carries update\workshop.txt, and on it the updater only
#  looks, never installs.
#
#  The file names the drive by its serial number, so a COPY of the drive
#  (a gift, or the second copy updates are tested on) is not a workshop and
#  updates normally. If the serial line is blank, the first check fills it in.
#  Delete workshop.txt to turn the guard off.
# ---------------------------------------------------------------------------
function Get-UpdDriveSerial([string]$Ws) {
    try {
        $q = Split-Path -Qualifier $Ws
        $out = (& cmd.exe /c ('vol ' + $q) 2>$null) -join ' '
        if ($out -match '([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})') { return $Matches[1].ToUpper() }
    } catch { }
    return ''
}

function Test-UpdWorkshop([string]$Ws) {
    $f = Join-UpdPath (Join-UpdPath $Ws 'Program\update') 'workshop.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $here = Get-UpdDriveSerial $Ws
    if ($here -eq '') { return $true }   # cannot tell: stay safe
    $lines = @([System.IO.File]::ReadAllLines($f))
    $want = ''
    foreach ($l in $lines) { if ($l -match '^\s*serial\s*=\s*(\S*)') { $want = $Matches[1].ToUpper() } }
    if ($want -eq '') {
        $new = @(); $done = $false
        foreach ($l in $lines) {
            if (-not $done -and $l -match '^\s*serial\s*=') { $new += ('serial = ' + $here); $done = $true } else { $new += $l }
        }
        if (-not $done) { $new += ('serial = ' + $here) }
        try { [System.IO.File]::WriteAllLines($f, [string[]]$new) } catch { }
        return $true
    }
    return ($want -eq $here)
}

$script:UpdWorkshopMessage = 'This is the workshop drive, where the wizard is built, so it is always newer than GitHub. Updates are switched off here. Test updates on a copy of the drive.'

function New-UpdDir([string]$Path) {
    if ($Path -and -not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Write-UpdLog([string]$Ws, [string]$Msg) {
    try {
        $P = Get-UpdPaths $Ws
        New-UpdDir $P.Dir
        $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
        [System.IO.File]::AppendAllText($P.Log, $line + "`r`n")
    } catch { }
}

function Get-UpdStamp { return (Get-Date -Format 'yyyy-MM-dd_HHmmss') }

# key = value, ; and # comments. The same shape as every .ini on this drive.
function Read-UpdIni([string]$Path) {
    $out = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $out[$t.Substring(0, $eq).Trim().ToLower()] = $t.Substring($eq + 1).Trim()
    }
    return $out
}

function Get-UpdConfig([string]$Ws) {
    $P = Get-UpdPaths $Ws
    $ini = Read-UpdIni $P.Config
    $repo   = if ($ini['repo'])   { $ini['repo'] }   else { $script:UpdDefaultRepo }
    $branch = if ($ini['branch']) { $ini['branch'] } else { $script:UpdDefaultBranch }
    $chan   = if ([string]$ini['channel'] -eq 'dev') { 'dev' } else { 'stable' }
    return @{ Repo = $repo; Branch = $branch; Channel = $chan
              Latest = $(if ($chan -eq 'dev') { 'latest-dev.ini' } else { 'latest.ini' }) }
}

# Picks the channel, keeping every other line of update.ini as it was.
function Set-UpdChannel([string]$Ws, [string]$Channel) {
    $P = Get-UpdPaths $Ws
    New-UpdDir $P.Dir
    $c = $(if ($Channel -eq 'dev') { 'dev' } else { 'stable' })
    $lines = @()
    if (Test-Path -LiteralPath $P.Config) {
        $lines = @([System.IO.File]::ReadAllLines($P.Config) | Where-Object { $_ -notmatch '^\s*channel\s*=' })
    }
    else { $lines = @('; Where this drive updates from. Written by scripts\UpdateEngine.ps1.') }
    $lines += ('channel = ' + $c)
    [System.IO.File]::WriteAllLines($P.Config, [string[]]$lines)
}

# What was installed last: @{ Version; Tag; Channel }. A drive no update ever
# touched says stable, with no tag.
function Get-UpdInstalled([string]$Ws) {
    $ini = Read-UpdIni (Join-UpdPath (Get-UpdPaths $Ws).Dir 'installed.ini')
    return @{
        Version = [string]$ini['version']
        Tag     = [string]$ini['tag']
        Channel = $(if ([string]$ini['channel'] -eq 'dev') { 'dev' } else { 'stable' })
    }
}

# Should this version be offered? See TWO CHANNELS at the top.
function Test-UpdOffer([string]$Remote, [string]$Tag, [string]$Local, $Inst, $Cfg) {
    if ($Cfg.Channel -ne $Inst.Channel) { return $true }
    if (Test-UpdNewer $Remote $Local) { return $true }
    if ($Cfg.Channel -eq 'dev' -and $Inst.Tag -ne '' -and $Tag -ne '' -and $Tag -ne $Inst.Tag) { return $true }
    return $false
}

# The folder a download waits in. Stable keeps the plain version, as always;
# dev adds the commit, because a dev build can be republished under the same
# version number.
function Get-UpdIncomingName([string]$Remote, [string]$Tag, $Cfg) {
    if ($Cfg.Channel -eq 'dev' -and $Tag.Length -ge 7) { return ($Remote + '-' + $Tag.Substring(0, 7)) }
    return $Remote
}

# The version of the wizard on this drive. version.txt is the one place it
# lives since 2026-10-10, and an update replaces it. A drive from before that
# still has it in Settings\wizard.ini, which is read as a fallback.
function Get-UpdLocalVersion([string]$Ws) {
    $P = Get-UpdPaths $Ws
    if (Test-Path -LiteralPath $P.Version) {
        foreach ($line in [System.IO.File]::ReadAllLines($P.Version)) {
            $t = $line.Trim()
            if ($t -ne '' -and -not $t.StartsWith(';') -and -not $t.StartsWith('#')) { return $t }
        }
    }
    $wi = Read-UpdIni (Join-UpdPath $Ws 'Settings\wizard.ini')
    if ($wi['version']) { return $wi['version'] }
    return '0'
}

# "2.2.0", "v2.2", "2.2.0-beta" all compare as numbers. Anything that will
# not parse comes back as 0.0, which is older than everything.
function ConvertTo-UpdVersion([string]$Text) {
    $t = ([string]$Text).Trim()
    if ($t.StartsWith('v') -or $t.StartsWith('V')) { $t = $t.Substring(1) }
    $dash = $t.IndexOf('-')
    if ($dash -ge 0) { $t = $t.Substring(0, $dash) }
    $parts = @($t.Split('.') | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 2) { $parts += '0' }
    try { return [version]($parts -join '.') } catch { return [version]'0.0' }
}

function Test-UpdNewer([string]$Remote, [string]$Local) {
    return ((ConvertTo-UpdVersion $Remote) -gt (ConvertTo-UpdVersion $Local))
}

function Get-UpdHash([string]$Path) {
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower())
}

function Test-UpdRetroBatRunning {
    if ($null -ne $script:UpdRunningOverride) { return [bool](& $script:UpdRunningOverride) }
    $p = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
    return ($null -ne $p)
}

# ---------------------------------------------------------------------------
#  Status: update\status.ini, read by the wizard to draw the bar
# ---------------------------------------------------------------------------
#  state = checking | uptodate | available | ready | error | installed |
#          wentback | offline | busy
function Write-UpdStatus([string]$Ws, [hashtable]$Fields) {
    try {
        $P = Get-UpdPaths $Ws
        New-UpdDir $P.Dir
        $lines = @('; Written by scripts\UpdateEngine.ps1. Safe to delete, it is rebuilt.')
        $lines += ('time = ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        foreach ($k in @('state', 'version', 'current', 'notes', 'message', 'files')) {
            if ($Fields.ContainsKey($k)) {
                $v = ([string]$Fields[$k]) -replace "[`r`n]+", ' | '
                $lines += ($k + ' = ' + $v)
            }
        }
        [System.IO.File]::WriteAllLines($P.Status, [string[]]$lines)
    } catch { }
}

function Read-UpdStatus([string]$Ws) {
    $P = Get-UpdPaths $Ws
    try { return (Read-UpdIni $P.Status) } catch { return @{} }
}

# ---------------------------------------------------------------------------
#  The manifest
# ---------------------------------------------------------------------------
#  version<TAB>2.2.0
#  code<TAB><sha256><TAB><size><TAB>scripts/Updater.ps1
#  seed<TAB><sha256><TAB><size><TAB>features.ini
#
#  EVERY PATH IS CHECKED before anything is written. A path that climbs out
#  of _Wizard ('..'), starts at a drive or a slash, or points into a room
#  this drive keeps for itself would let a bad manifest write anywhere, so a
#  manifest with even one such line is refused whole.
#
#  THE ROOMS (3.2, 2026-10-26). An update may write Program\ (except
#  Program\update\, which is the updater's own record), Buttons\, SEED
#  files in Settings\, and the two loose files at the top. People\,
#  Backups\, Apps\, Owner\ and Cache\ are never touched.
#  One more, the BRIDGE: wizard/Launch-Wizard.vbs, the old launcher's place,
#  which a 3.1 drive still points at until its first 3.2 start moves it.
#  A drive already in the 3.2 layout never gets it (Test-UpdLegacyPath).
$script:UpdAllowedTops = @('program', 'buttons', 'settings')
$script:UpdTopFiles    = @('version.txt', 'start here.txt')

function Test-UpdLegacyPath([string]$Rel) { return ($Rel.ToLower() -eq 'wizard/launch-wizard.vbs') }

function Test-UpdSafePath([string]$Rel, [string]$Kind = 'code') {
    if ($Rel -eq '' -or $Rel.Length -gt 200) { return $false }
    if ($Rel -match '[^\x20-\x7E]') { return $false }
    if ($Rel -match '[:*?"<>|\\]') { return $false }
    if ($Rel.StartsWith('/')) { return $false }
    $segs = $Rel.Split('/')
    foreach ($s in $segs) {
        if ($s -eq '' -or $s -eq '.' -or $s -eq '..') { return $false }
        if ($s.EndsWith(' ') -or $s.EndsWith('.')) { return $false }
    }
    $top = $segs[0].ToLower()
    if ($segs.Count -eq 1) { return ($script:UpdTopFiles -contains $top) }
    if (Test-UpdLegacyPath $Rel) { return $true }
    if (-not ($script:UpdAllowedTops -contains $top)) { return $false }
    if ($top -eq 'program' -and $segs[1].ToLower() -eq 'update') { return $false }
    if ($top -eq 'settings' -and $Kind -ne 'seed') { return $false }
    return $true
}

function Read-UpdManifest([string]$Path) {
    $m = @{ Version = ''; Entries = (New-Object System.Collections.ArrayList); Ok = $false; Problem = '' }
    if (-not (Test-Path -LiteralPath $Path)) { $m.Problem = 'manifest missing'; return $m }
    $seen = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
        $f = $line.Split("`t")
        if ($f[0] -eq 'version' -and $f.Count -ge 2) { $m.Version = $f[1].Trim(); continue }
        if (($f[0] -eq 'code' -or $f[0] -eq 'seed') -and $f.Count -eq 4) {
            $rel = $f[3]
            if (-not (Test-UpdSafePath $rel $f[0])) { $m.Problem = "unsafe path in manifest: $rel"; return $m }
            if ($f[1] -notmatch '^[0-9a-f]{64}$') { $m.Problem = "bad hash for $rel"; return $m }
            $size = 0L
            if (-not [long]::TryParse($f[2], [ref]$size)) { $m.Problem = "bad size for $rel"; return $m }
            $key = $rel.ToLower()
            if ($seen.ContainsKey($key)) { $m.Problem = "listed twice: $rel"; return $m }
            $seen[$key] = $true
            [void]$m.Entries.Add([pscustomobject]@{ Kind = $f[0]; Hash = $f[1]; Size = $size; Path = $rel })
            continue
        }
        $m.Problem = "unreadable manifest line: $line"; return $m
    }
    if ($m.Version -eq '') { $m.Problem = 'manifest has no version line'; return $m }
    if ($m.Entries.Count -eq 0) { $m.Problem = 'manifest lists no files'; return $m }
    $m.Ok = $true
    return $m
}

# ---------------------------------------------------------------------------
#  Fetching
# ---------------------------------------------------------------------------
#  Windows PowerShell 5.1 has three traps here, all handled:
#    - it does not offer TLS 1.2 unless asked, and GitHub refuses anything less
#    - without -UseBasicParsing it tries to start Internet Explorer's engine
#    - its progress bar slows a download down by a factor of ten or more
function Invoke-UpdFetch([string]$Url, [string]$OutFile) {
    if ($null -ne $script:UpdFetchOverride) { & $script:UpdFetchOverride $Url $OutFile; return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 60 `
            -Headers @{ 'Cache-Control' = 'no-cache' } -ErrorAction Stop
    }
    finally { $ProgressPreference = $oldPref }
}

function Get-UpdRawUrl($Cfg, [string]$Ref, [string]$Rel) {
    $escaped = (@($Rel.Split('/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/')
    return ('https://raw.githubusercontent.com/{0}/{1}/{2}' -f $Cfg.Repo, $Ref, $escaped)
}

# ---------------------------------------------------------------------------
#  BOTH CHANNELS AT A GLANCE (2026-10-17)
#  Steven: "I'm never sure which I'm looking at." The Admin page shows what
#  Stable and Dev each hold right now, next to what this drive runs. Two tiny
#  files (latest.ini and latest-dev.ini), read in the background with the
#  usual check, written to update\channels.ini for the window to read.
# ---------------------------------------------------------------------------
function Update-UpdChannelInfo([string]$Ws) {
    $cfg = Get-UpdConfig $Ws
    $P = Get-UpdPaths $Ws
    New-UpdDir $P.Dir
    $out = @('; Written by scripts\UpdateEngine.ps1. What each channel holds on GitHub. Safe to delete.',
             ('time = ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    foreach ($pair in @(@('stable', 'latest.ini'), @('dev', 'latest-dev.ini'))) {
        $tmp = Join-UpdPath $P.Dir ($pair[0] + '-peek.tmp')
        try {
            Invoke-UpdFetch ((Get-UpdRawUrl $cfg $cfg.Branch $pair[1]) + '?t=' + [DateTime]::UtcNow.Ticks) $tmp
            $ini = Read-UpdIni $tmp
            $out += ($pair[0] + '_version = ' + [string]$ini['version'])
            $out += ($pair[0] + '_tag = ' + [string]$ini['tag'])
        }
        catch { $out += ($pair[0] + '_version = ') }
        finally { try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch { } }
    }
    try { [System.IO.File]::WriteAllLines((Join-UpdPath $P.Dir 'channels.ini'), [string[]]$out) } catch { }
}

# @{ StableVersion; StableTag; DevVersion; DevTag; Time } from the last look,
# all '' when there has not been one.
function Read-UpdChannelInfo([string]$Ws) {
    $ini = @{}
    try { $ini = Read-UpdIni (Join-UpdPath (Get-UpdPaths $Ws).Dir 'channels.ini') } catch { }
    return @{ StableVersion = [string]$ini['stable_version']; StableTag = [string]$ini['stable_tag']
              DevVersion = [string]$ini['dev_version']; DevTag = [string]$ini['dev_tag']; Time = [string]$ini['time'] }
}

# ---------------------------------------------------------------------------
#  THE ADMIN TOOLS, A DOWNLOAD OF THEIR OWN (2026-10-17)
#  Steven: "add the admin as its own download". The Admin page's code
#  (scripts\AdminEngine.ps1 and scripts\AdminUI.ps1) is NOT in manifest.txt,
#  so an ordinary setup never gets it. It is listed in admin-manifest.txt,
#  beside manifest.txt at the same commit and in the same format, and only a
#  person on the admins list fetches it, with the button on their Admin page.
#  Every file is checked against its SHA-256 like any update file.
#  After each update, a setup that has the admin tools gets the matching ones
#  (Invoke-UpdateInstall calls this), so they never fall out of step.
# ---------------------------------------------------------------------------
function Install-UpdAdminPack([string]$Ws, [string]$Tag = '') {
    $res = @{ Ok = $false; Files = 0; Message = '' }
    if (Test-UpdWorkshop $Ws) {
        $res.Message = 'This is the workshop drive: the admin tools here are the ones being worked on, so nothing was downloaded.'
        return $res
    }
    $cfg = Get-UpdConfig $Ws
    $P = Get-UpdPaths $Ws
    New-UpdDir $P.Dir
    if ($Tag -eq '') { $Tag = (Get-UpdInstalled $Ws).Tag }
    if ($Tag -eq '') {
        # Never updated yet (a fresh install): the channel's newest.
        $lt = Join-UpdPath $P.Dir 'admin-latest.tmp'
        try {
            Invoke-UpdFetch ((Get-UpdRawUrl $cfg $cfg.Branch $cfg.Latest) + '?t=' + [DateTime]::UtcNow.Ticks) $lt
            $Tag = [string](Read-UpdIni $lt)['tag']
        }
        catch { $res.Message = 'Could not reach GitHub. Check the internet and try again.'; return $res }
        finally { try { if (Test-Path -LiteralPath $lt) { Remove-Item -LiteralPath $lt -Force } } catch { } }
        if ($Tag -eq '') { $res.Message = 'GitHub did not say which version is newest. Try again later.'; return $res }
    }
    $manTmp = Join-UpdPath $P.Dir 'admin-manifest.tmp'
    try {
        try { Invoke-UpdFetch (Get-UpdRawUrl $cfg $Tag 'admin-manifest.txt') $manTmp }
        catch { $res.Message = 'Could not get the list of admin tools. Check the internet. If this setup has not been updated in a while, update it first, then try again.'; return $res }
        $man = Read-UpdManifest $manTmp
        if (-not $man.Ok) { $res.Message = 'The list of admin tools was refused: ' + $man.Problem; return $res }
        foreach ($e in $man.Entries) {
            $dest = Join-UpdPath $Ws $e.Path
            if ((Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-UpdHash $dest) -eq $e.Hash) { continue }
            New-UpdDir (Split-Path -Parent $dest)
            $tmp = $dest + '.part'
            try { Invoke-UpdFetch (Get-UpdRawUrl $cfg $Tag ('drive/' + $e.Path)) $tmp }
            catch { $res.Message = ('The download stopped partway ({0}). Try again.' -f $e.Path); return $res }
            $ok = (Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp).Length -eq $e.Size) -and ((Get-UpdHash $tmp) -eq $e.Hash)
            if (-not $ok) {
                try { Remove-Item -LiteralPath $tmp -Force } catch { }
                $res.Message = ('A downloaded file did not match its checksum ({0}). Nothing was changed for that file.' -f $e.Path)
                return $res
            }
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
            Move-Item -LiteralPath $tmp -Destination $dest
            $res.Files++
        }
        Write-UpdLog $Ws ("admin tools: {0} file(s) brought up to date ({1})" -f $res.Files, $Tag)
        $res.Ok = $true
        $res.Message = $(if ($res.Files -gt 0) { 'The admin tools are on this setup now.' } else { 'The admin tools here were already up to date.' })
        return $res
    }
    finally { try { if (Test-Path -LiteralPath $manTmp) { Remove-Item -LiteralPath $manTmp -Force } } catch { } }
}

function Test-UpdAdminPack([string]$Ws) {
    return (Test-Path -LiteralPath (Join-UpdPath $Ws 'Program\scripts\AdminEngine.ps1')) -and (Test-Path -LiteralPath (Join-UpdPath $Ws 'Program\scripts\AdminUI.ps1'))
}

# ---------------------------------------------------------------------------
#  The lock. Two wizards open at once must not download into the same folder.
# ---------------------------------------------------------------------------
function Enter-UpdLock([string]$Ws) {
    $P = Get-UpdPaths $Ws
    New-UpdDir $P.Dir
    if (Test-Path -LiteralPath $P.Lock) {
        $age = ((Get-Date) - (Get-Item -LiteralPath $P.Lock).LastWriteTime).TotalMinutes
        $lockPid = 0
        try { [void][int]::TryParse(([System.IO.File]::ReadAllText($P.Lock)).Trim(), [ref]$lockPid) } catch { }
        $alive = $false
        if ($lockPid -gt 0 -and $lockPid -ne $PID) {
            $alive = ($null -ne (Get-Process -Id $lockPid -ErrorAction SilentlyContinue))
        }
        if ($alive -and $age -lt 30) { return $false }
    }
    [System.IO.File]::WriteAllText($P.Lock, [string]$PID)
    return $true
}

function Exit-UpdLock([string]$Ws) {
    $P = Get-UpdPaths $Ws
    try {
        if (Test-Path -LiteralPath $P.Lock) {
            $owner = ([System.IO.File]::ReadAllText($P.Lock)).Trim()
            if ($owner -eq [string]$PID) { Remove-Item -LiteralPath $P.Lock -Force }
        }
    } catch { }
}

# Moves a file or folder into _SAFE TO DELETE\<bucket>\<rel>, adding a number
# if the name is already taken there. The drive's one way of getting rid of
# anything.
function Move-UpdToSafe([string]$Ws, [string]$Full, [string]$Bucket, [string]$Rel) {
    $P = Get-UpdPaths $Ws
    $dest = Join-UpdPath (Join-UpdPath $P.Safe $Bucket) $Rel
    $n = 2; $try = $dest
    while (Test-Path -LiteralPath $try) { $try = "$dest ($n)"; $n++ }
    New-UpdDir (Split-Path -Parent $try)
    Move-Item -LiteralPath $Full -Destination $try
    return $try
}

function Copy-UpdFile([string]$From, [string]$To) {
    New-UpdDir (Split-Path -Parent $To)
    [System.IO.File]::Copy($From, $To, $true)
}

# ===========================================================================
#  1. CHECK
# ===========================================================================
#  Returns the status hashtable it wrote. Never throws: no internet is a
#  normal state for a drive that goes to other people's houses.
function Invoke-UpdateCheck {
    param([Parameter(Mandatory = $true)][string]$Ws, $Progress = $null, [switch]$NoDownload)

    $P = Get-UpdPaths $Ws
    $local = Get-UpdLocalVersion $Ws
    if (-not (Enter-UpdLock $Ws)) {
        return @{ state = 'busy'; current = $local; message = 'Another update check is already running.' }
    }
    try {
        if (Test-UpdWorkshop $Ws) {
            $st = @{ state = 'uptodate'; current = $local; version = $local; message = $script:UpdWorkshopMessage }
            Write-UpdStatus $Ws $st
            Write-UpdLog $Ws 'check: workshop drive, updates are off here'
            return $st
        }
        Write-UpdStatus $Ws @{ state = 'checking'; current = $local }
        $cfg = Get-UpdConfig $Ws
        New-UpdDir $P.Dir

        # --- what is the newest version? -----------------------------------
        $latestFile = Join-UpdPath $P.Dir 'latest.tmp'
        $url = (Get-UpdRawUrl $cfg $cfg.Branch $cfg.Latest) + '?t=' + [DateTime]::UtcNow.Ticks
        try { Invoke-UpdFetch $url $latestFile }
        catch {
            $st = @{ state = 'offline'; current = $local; message = 'Could not reach GitHub. No internet, or GitHub is down. Nothing changed.' }
            Write-UpdStatus $Ws $st
            Write-UpdLog $Ws ("check: could not fetch {0} - {1}" -f $cfg.Latest, $_.Exception.Message)
            return $st
        }
        $latest = Read-UpdIni $latestFile
        try { Remove-Item -LiteralPath $latestFile -Force } catch { }
        $remote = [string]$latest['version']
        $tag    = [string]$latest['tag']
        $notes  = [string]$latest['notes']
        if ($remote -eq '' -or $tag -eq '') {
            $st = @{ state = 'error'; current = $local; message = ($cfg.Latest + ' on GitHub is missing its version or tag.') }
            Write-UpdStatus $Ws $st; Write-UpdLog $Ws 'check: latest.ini unreadable'
            return $st
        }

        $skip = ''
        if (Test-Path -LiteralPath $P.Skip) { $skip = ([System.IO.File]::ReadAllText($P.Skip)).Trim() }

        $inst = Get-UpdInstalled $Ws
        $switching = ($cfg.Channel -ne $inst.Channel)
        $offer = Test-UpdOffer $remote $tag $local $inst $cfg
        $skipped = (-not $switching) -and $skip -ne '' -and -not (Test-UpdNewer $remote $skip)
        if (-not $offer -or $skipped) {
            $st = @{ state = 'uptodate'; version = $remote; current = $local }
            if ($skipped -and $offer) {
                $st.message = "You went back from $skip, so it is not offered again. A newer one will be."
            }
            Write-UpdStatus $Ws $st
            Write-UpdLog $Ws ("check: up to date (here {0}, GitHub {1})" -f $local, $remote)
            return $st
        }

        # --- just looking? ----------------------------------------------------
        #  The wizard asks this way when it opens: one tiny file, no
        #  downloading. Everything else waits for somebody to press Update now
        #  (Steven, 2026-10-10: no surprise waits when the wizard is reopened).
        if ($NoDownload) {
            $st = @{ state = 'available'; version = $remote; current = $local; notes = $notes }
            if ($switching) { $st.message = $(if ($cfg.Channel -eq 'dev') { 'Switching to the dev version.' } else { 'Switching back to the stable version.' }) }
            Write-UpdStatus $Ws $st
            Write-UpdLog $Ws ("check: {0} is available (here {1})" -f $remote, $local)
            return $st
        }

        # --- already downloaded? ---------------------------------------------
        $inDir   = Join-UpdPath $P.Incoming (Get-UpdIncomingName $remote $tag $cfg)
        $readyF  = Join-UpdPath $inDir 'READY.txt'
        $manPath = Join-UpdPath $inDir 'manifest.txt'
        if ((Test-Path -LiteralPath $readyF) -and (Read-UpdManifest $manPath).Ok) {
            $st = @{ state = 'ready'; version = $remote; current = $local; notes = $notes }
            Write-UpdStatus $Ws $st
            return $st
        }

        # --- the manifest at that tag ----------------------------------------
        Write-UpdStatus $Ws @{ state = 'checking'; version = $remote; current = $local; message = 'Reading the file list' }
        New-UpdDir $inDir
        $manTmp = Join-UpdPath $inDir 'manifest.tmp'
        try { Invoke-UpdFetch (Get-UpdRawUrl $cfg $tag 'manifest.txt') $manTmp }
        catch {
            $st = @{ state = 'offline'; version = $remote; current = $local; message = 'Found a new version but could not download its file list. Try again later.' }
            Write-UpdStatus $Ws $st; Write-UpdLog $Ws ("check: manifest fetch failed - " + $_.Exception.Message)
            return $st
        }
        $man = Read-UpdManifest $manTmp
        if (-not $man.Ok -or $man.Version -ne $remote) {
            $why = if (-not $man.Ok) { $man.Problem } else { "manifest says $($man.Version), latest.ini says $remote" }
            $st = @{ state = 'error'; version = $remote; current = $local; message = "The update's file list was refused: $why" }
            Write-UpdStatus $Ws $st; Write-UpdLog $Ws ("check: manifest refused - " + $why)
            return $st
        }

        # --- which files are actually different? -----------------------------
        $filesDir = Join-UpdPath $inDir 'files'
        $need = New-Object System.Collections.ArrayList
        foreach ($e in $man.Entries) {
            if (Test-UpdLegacyPath $e.Path) { continue }     # the 3.1 bridge: not on a 3.2 drive
            $dest = Join-UpdPath $Ws $e.Path
            if ($e.Kind -eq 'seed') {
                if (-not (Test-Path -LiteralPath $dest)) { [void]$need.Add($e) }
                continue
            }
            if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { [void]$need.Add($e); continue }
            if ((Get-Item -LiteralPath $dest).Length -ne $e.Size -or (Get-UpdHash $dest) -ne $e.Hash) { [void]$need.Add($e) }
        }

        # --- download them, checking every one -------------------------------
        $i = 0
        foreach ($e in $need) {
            $i++
            $target = Join-UpdPath $filesDir $e.Path
            if ((Test-Path -LiteralPath $target) -and (Get-UpdHash $target) -eq $e.Hash) { continue }
            Write-UpdStatus $Ws @{ state = 'checking'; version = $remote; current = $local; message = ("Downloading {0} of {1}" -f $i, $need.Count) }
            if ($null -ne $Progress) { try { & $Progress ("Downloading {0} of {1}: {2}" -f $i, $need.Count, $e.Path) } catch { } }
            New-UpdDir (Split-Path -Parent $target)
            $tmp = $target + '.part'
            try {
                Invoke-UpdFetch (Get-UpdRawUrl $cfg $tag ('drive/' + $e.Path)) $tmp
            }
            catch {
                $st = @{ state = 'offline'; version = $remote; current = $local; message = 'The download stopped partway. It carries on from where it got to next time.' }
                Write-UpdStatus $Ws $st; Write-UpdLog $Ws ("check: download failed for {0} - {1}" -f $e.Path, $_.Exception.Message)
                return $st
            }
            $ok = (Test-Path -LiteralPath $tmp) -and ((Get-Item -LiteralPath $tmp).Length -eq $e.Size) -and ((Get-UpdHash $tmp) -eq $e.Hash)
            if (-not $ok) {
                try { Remove-Item -LiteralPath $tmp -Force } catch { }
                $st = @{ state = 'error'; version = $remote; current = $local; message = "A downloaded file did not match its checksum ($($e.Path)). Nothing was installed." }
                Write-UpdStatus $Ws $st; Write-UpdLog $Ws ("check: checksum mismatch for " + $e.Path)
                return $st
            }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
            Move-Item -LiteralPath $tmp -Destination $target
        }

        # --- only now is it ready --------------------------------------------
        if (Test-Path -LiteralPath $manPath) { Remove-Item -LiteralPath $manPath -Force }
        Move-Item -LiteralPath $manTmp -Destination $manPath
        [System.IO.File]::WriteAllText((Join-UpdPath $inDir 'notes.txt'), $notes)
        [System.IO.File]::WriteAllLines((Join-UpdPath $inDir 'target.ini'), [string[]]@(
            ('version = ' + $remote), ('tag = ' + $tag), ('channel = ' + $cfg.Channel)))
        [System.IO.File]::WriteAllText($readyF, ("{0} file(s) to install, checked {1}" -f $need.Count, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
        $st = @{ state = 'ready'; version = $remote; current = $local; notes = $notes; files = $need.Count }
        Write-UpdStatus $Ws $st
        Write-UpdLog $Ws ("check: {0} is ready, {1} file(s) downloaded and checked" -f $remote, $need.Count)
        return $st
    }
    catch {
        $st = @{ state = 'error'; current = $local; message = ('The update check hit an error: ' + $_.Exception.Message) }
        Write-UpdStatus $Ws $st
        Write-UpdLog $Ws ("check: FAILED - " + $_.Exception.Message)
        return $st
    }
    finally { Exit-UpdLock $Ws }
}

# The version waiting in update\incoming, or '' when there is none.
#  Since 2026-10-12 a download says what it is in target.ini (version,
#  commit, channel) and only one for the CURRENT channel counts; the folder
#  name is returned. A folder from before that is judged by its name, as
#  always.
function Get-UpdReadyVersion([string]$Ws) {
    $P = Get-UpdPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Incoming)) { return '' }
    $local = Get-UpdLocalVersion $Ws
    $cfg = Get-UpdConfig $Ws
    $inst = Get-UpdInstalled $Ws
    $best = ''; $bestTime = [DateTime]::MinValue; $legacy = ''
    foreach ($d in @(Get-ChildItem -LiteralPath $P.Incoming -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-UpdPath $d.FullName 'READY.txt'))) { continue }
        $t = Read-UpdIni (Join-UpdPath $d.FullName 'target.ini')
        if ($t['tag']) {
            $tc = $(if ([string]$t['channel'] -eq 'dev') { 'dev' } else { 'stable' })
            if ($tc -ne $cfg.Channel) { continue }
            if (-not (Test-UpdOffer ([string]$t['version']) ([string]$t['tag']) $local $inst $cfg)) { continue }
            $when = (Get-Item -LiteralPath (Join-UpdPath $d.FullName 'READY.txt')).LastWriteTime
            if ($best -eq '' -or $when -gt $bestTime) { $best = $d.Name; $bestTime = $when }
            continue
        }
        if ($cfg.Channel -ne 'stable' -or $inst.Channel -ne 'stable') { continue }
        if (-not (Test-UpdNewer $d.Name $local)) { continue }
        if ($legacy -eq '' -or (Test-UpdNewer $d.Name $legacy)) { $legacy = $d.Name }
    }
    if ($best -ne '') { return $best }
    return $legacy
}

# ===========================================================================
#  2. INSTALL
# ===========================================================================
#  The journal, update\previous\changes.txt, one line per step, written the
#  moment the step is done:
#      changed<TAB>path    the old file is in previous\files\path
#      added<TAB>path      there was nothing here before
#      removed<TAB>path    the old file is in previous\files\path, and the
#                          new version no longer ships it
#  Migrations keep their own journal beside it, previous\migrations.txt.
function Invoke-UpdateInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Ws,
        [switch]$NoPostSteps,
        $Progress = $null
    )
    $res = @{ Ok = $false; Message = ''; Version = ''; Changed = 0; Added = 0; Removed = 0 }
    $P = Get-UpdPaths $Ws
    $from = Get-UpdLocalVersion $Ws
    $hadAdmin = Test-Path -LiteralPath (Join-UpdPath $Ws 'Program\scripts\AdminEngine.ps1')

    $dirName = Get-UpdReadyVersion $Ws
    if ($dirName -eq '') { $res.Message = 'There is no downloaded update waiting.'; return $res }
    $ver = $dirName
    $res.Version = $ver
    if (Test-UpdWorkshop $Ws) { $res.Message = $script:UpdWorkshopMessage; Write-UpdLog $Ws 'install: refused, workshop drive'; return $res }
    if (Test-UpdRetroBatRunning) { $res.Message = 'RetroBat is open. Close it completely, then try again.'; return $res }
    if (-not (Enter-UpdLock $Ws)) { $res.Message = 'An update check is still running. Try again in a minute.'; return $res }

    $inDir = Join-UpdPath $P.Incoming $dirName
    $man = Read-UpdManifest (Join-UpdPath $inDir 'manifest.txt')
    if (-not $man.Ok) {
        Exit-UpdLock $Ws
        $res.Message = 'The downloaded file list is damaged: ' + $man.Problem
        return $res
    }
    # The version is the manifest's own; the folder name can carry a commit.
    $ver = $man.Version
    $res.Version = $ver
    $target = Read-UpdIni (Join-UpdPath $inDir 'target.ini')
    $instIni = Join-UpdPath $P.Dir 'installed.ini'
    $fromChan = (Get-UpdInstalled $Ws).Channel
    $filesDir = Join-UpdPath $inDir 'files'
    $prevDir  = $P.Previous
    $journal  = Join-UpdPath $prevDir 'changes.txt'
    $migJour  = Join-UpdPath $prevDir 'migrations.txt'
    $stamp    = Get-UpdStamp

    # NOT a function called Say (2026-10-25). The 3.1 installer's own progress
    # block called ITS function Say; PowerShell found this one first, so the
    # two called each other until PowerShell gave up: about 40 silent seconds
    # per message, and a fresh install sat on "STEP 2" for half an hour. A
    # script block in a variable cannot be picked up by a caller's code.
    $updSay = { param([string]$m) if ($null -ne $Progress) { try { & $Progress $m } catch { } } }

    try {
        # --- the previous\ from last time goes to SAFE TO DELETE -------------
        if (Test-Path -LiteralPath $prevDir) {
            [void](Move-UpdToSafe $Ws $prevDir 'updates' ("previous-from-" + $stamp))
        }
        New-UpdDir (Join-UpdPath $prevDir 'files')
        [System.IO.File]::WriteAllLines((Join-UpdPath $prevDir 'info.ini'), [string[]]@(
            '; What "Go back one update" puts back. Written by scripts\UpdateEngine.ps1.',
            ('from = ' + $from), ('to = ' + $ver), ('time = ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
            ('fromchannel = ' + $fromChan)))
        if (Test-Path -LiteralPath $P.Installed) {
            Copy-UpdFile $P.Installed (Join-UpdPath $prevDir 'installed-manifest.txt')
        }
        if (Test-Path -LiteralPath $instIni) { Copy-UpdFile $instIni (Join-UpdPath $prevDir 'installed.ini') }
        [System.IO.File]::WriteAllText($journal, '')

        # --- one-time renames, before any file lands -------------------------
        $migLib = Join-UpdPath $Ws 'Program\scripts\Migrations.ps1'
        $newMig = Join-UpdPath $filesDir 'scripts/Migrations.ps1'
        if (Test-Path -LiteralPath $newMig) { $migLib = $newMig }
        if (Test-Path -LiteralPath $migLib) {
            & $updSay 'Tidying up old names'
            . $migLib
            $logger = { param($m) Write-UpdLog $Ws $m }
            [void](Invoke-DriveMigrations -Ws $Ws -Journal $migJour -Logger $logger)
        }

        # --- the files -------------------------------------------------------
        # version.txt goes LAST (2026-10-25): it is what says "this version is
        # here", so an install cut short must never have it early. Otherwise
        # the next check says up to date with half the files missing (the
        # friend's laptop).
        $order = @($man.Entries | Where-Object { $_.Path -ne 'version.txt' }) + @($man.Entries | Where-Object { $_.Path -eq 'version.txt' })
        $wanted = @{}
        $n = 0
        foreach ($e in $order) {
            $n++
            $wanted[$e.Path.ToLower()] = $true
            if (Test-UpdLegacyPath $e.Path) { continue }
            $dest = Join-UpdPath $Ws $e.Path
            $src  = Join-UpdPath $filesDir $e.Path
            $exists = Test-Path -LiteralPath $dest -PathType Leaf

            if ($e.Kind -eq 'seed' -and $exists) { continue }
            if ($exists -and (Get-UpdHash $dest) -eq $e.Hash) { continue }

            if (-not (Test-Path -LiteralPath $src)) { throw "the download is missing $($e.Path) - run Check for updates again" }
            if ((Get-UpdHash $src) -ne $e.Hash) { throw "the download of $($e.Path) is damaged - run Check for updates again" }

            if ($n % 10 -eq 0) { & $updSay ("Installing ({0} of {1})" -f $n, $man.Entries.Count) }
            if ($exists) {
                Copy-UpdFile $dest (Join-UpdPath (Join-UpdPath $prevDir 'files') $e.Path)
                Copy-UpdFile $src $dest
                [System.IO.File]::AppendAllText($journal, ("changed`t" + $e.Path + "`r`n"))
                $res.Changed++
            }
            else {
                Copy-UpdFile $src $dest
                [System.IO.File]::AppendAllText($journal, ("added`t" + $e.Path + "`r`n"))
                $res.Added++
            }
        }

        # --- files the new version no longer ships ---------------------------
        #  Only CODE files, and only when they are exactly what the last
        #  update put there. A file somebody has changed is theirs now.
        $old = Read-UpdManifest $P.Installed
        if ($old.Ok) {
            foreach ($e in $old.Entries) {
                if ($e.Kind -ne 'code') { continue }
                if ($wanted.ContainsKey($e.Path.ToLower())) { continue }
                $dest = Join-UpdPath $Ws $e.Path
                if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { continue }
                if ((Get-UpdHash $dest) -ne $e.Hash) { continue }
                $keep = Join-UpdPath (Join-UpdPath $prevDir 'files') $e.Path
                New-UpdDir (Split-Path -Parent $keep)
                Move-Item -LiteralPath $dest -Destination $keep
                [System.IO.File]::AppendAllText($journal, ("removed`t" + $e.Path + "`r`n"))
                $res.Removed++
            }
        }

        Copy-UpdFile (Join-UpdPath $inDir 'manifest.txt') $P.Installed
        if ($target['tag']) {
            [System.IO.File]::WriteAllLines($instIni, [string[]]@(
                '; The version this drive last installed, and from which channel. scripts\UpdateEngine.ps1.',
                ('version = ' + $ver), ('tag = ' + [string]$target['tag']),
                ('channel = ' + $(if ([string]$target['channel'] -eq 'dev') { 'dev' } else { 'stable' }))))
        }
    }
    catch {
        $why = $_.Exception.Message
        Write-UpdLog $Ws ("install: FAILED partway - " + $why + " - putting everything back")
        try { [void](Undo-UpdJournal $Ws 'rollback') } catch { Write-UpdLog $Ws ("install: rollback hit an error too - " + $_.Exception.Message) }
        Exit-UpdLock $Ws
        $res.Message = "The update stopped partway ($why). Everything was put back the way it was."
        Write-UpdStatus $Ws @{ state = 'error'; version = $ver; current = $from; message = $res.Message }
        return $res
    }

    # --- the download has done its job ---------------------------------------
    try { [void](Move-UpdToSafe $Ws $inDir 'updates' ("downloaded-" + $dirName + '-' + $stamp)) } catch { }
    if (Test-Path -LiteralPath $P.Skip) { try { Remove-Item -LiteralPath $P.Skip -Force } catch { } }
    Exit-UpdLock $Ws

    Write-UpdLog $Ws ("install: {0} -> {1}: {2} changed, {3} added, {4} removed" -f $from, $ver, $res.Changed, $res.Added, $res.Removed)

    # --- put the drive's own files in step, the way an update repair does ----
    if (-not $NoPostSteps) {
        $lines = @()
        if (Test-Path -LiteralPath $journal) { $lines = @([System.IO.File]::ReadAllLines($journal)) }
        $touchedRestore = @($lines | Where-Object { $_ -match "`tupdate-restore(-off)?/" }).Count -gt 0
        $touchedTiers   = @($lines | Where-Object { $_ -match "`tmachine/(tiers|rules)/" }).Count -gt 0
        if ($touchedRestore) { & $updSay 'Putting protected files in place'; Invoke-UpdPostStep $Ws 'Restore-ProtectedFiles.ps1' }
        if ($touchedTiers)   { & $updSay 'Re-applying settings';             Invoke-UpdPostStep $Ws 'Apply-Settings.ps1' }
    }

    # --- the admin tools, for a setup that has them --------------------------
    if ($hadAdmin) {
        & $updSay 'Updating the admin tools'
        try {
            $a = Install-UpdAdminPack $Ws ([string]$target['tag'])
            if (-not $a.Ok) { Write-UpdLog $Ws ("install: admin tools not refreshed - " + $a.Message) }
        } catch { Write-UpdLog $Ws ("install: admin tools not refreshed - " + $_.Exception.Message) }
    }

    $res.Ok = $true
    $res.Message = "Updated to $ver."
    Write-UpdStatus $Ws @{ state = 'installed'; version = $ver; current = $ver; message = $res.Message }
    return $res
}

function Invoke-UpdPostStep([string]$Ws, [string]$Script) {
    $p = Join-UpdPath $Ws ('Program\scripts\' + $Script)
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        $out = & $p *>&1 | Out-String
        Write-UpdLog $Ws ("post-step {0}: done" -f $Script)
        if ($out) { Write-UpdLog $Ws $out.TrimEnd() }
    }
    catch { Write-UpdLog $Ws ("post-step {0} failed: {1}" -f $Script, $_.Exception.Message) }
}

# Walks update\previous\changes.txt backwards, then the migrations journal.
# Used by a failed install (bucket 'rollback') and by Go back ('went-back').
function Undo-UpdJournal([string]$Ws, [string]$Bucket) {
    $P = Get-UpdPaths $Ws
    $prevDir = $P.Previous
    $journal = Join-UpdPath $prevDir 'changes.txt'
    $stamp = Get-UpdStamp
    $count = 0

    # Load the migrations library FIRST. Walking the file journal can move
    # Migrations.ps1 itself away (it is an "added" file on a drive that never
    # had it), and the functions must already be in memory by then.
    $migJour = Join-UpdPath $prevDir 'migrations.txt'
    $migOk = $false
    if (Test-Path -LiteralPath $migJour) {
        foreach ($cand in @((Join-UpdPath $Ws 'Program\scripts\Migrations.ps1'),
                            (Join-UpdPath (Join-UpdPath $prevDir 'files') 'scripts/Migrations.ps1'))) {
            if (Test-Path -LiteralPath $cand) { . $cand; $migOk = $true; break }
        }
        if (-not $migOk) { Write-UpdLog $Ws 'undo: Migrations.ps1 not found, renames were left as they are' }
    }

    $lines = @()
    if (Test-Path -LiteralPath $journal) { $lines = @([System.IO.File]::ReadAllLines($journal) | Where-Object { $_ -ne '' }) }
    [array]::Reverse($lines)
    foreach ($line in $lines) {
        $f = $line.Split("`t")
        if ($f.Count -ne 2) { continue }
        $rel = $f[1]
        if (-not (Test-UpdSafePath $rel 'seed')) { continue }
        $dest = Join-UpdPath $Ws $rel
        $kept = Join-UpdPath (Join-UpdPath $prevDir 'files') $rel
        switch ($f[0]) {
            'changed' {
                if (Test-Path -LiteralPath $kept) {
                    if (Test-Path -LiteralPath $dest) { [void](Move-UpdToSafe $Ws $dest 'updates' ("$Bucket-$stamp/" + $rel)) }
                    Copy-UpdFile $kept $dest
                    $count++
                }
            }
            'added' {
                if (Test-Path -LiteralPath $dest) {
                    [void](Move-UpdToSafe $Ws $dest 'updates' ("$Bucket-$stamp/" + $rel))
                    $count++
                }
            }
            'removed' {
                if ((Test-Path -LiteralPath $kept) -and -not (Test-Path -LiteralPath $dest)) {
                    Copy-UpdFile $kept $dest
                    $count++
                }
            }
        }
    }

    if ($migOk) {
        $logger = { param($m) Write-UpdLog $Ws $m }
        [void](Undo-DriveMigrations -Ws $Ws -Journal $migJour -Logger $logger)
    }

    # The list of what is installed goes back to what it was.
    $prevMan = Join-UpdPath $prevDir 'installed-manifest.txt'
    if (Test-Path -LiteralPath $prevMan) { Copy-UpdFile $prevMan $P.Installed }
    elseif (Test-Path -LiteralPath $P.Installed) { [void](Move-UpdToSafe $Ws $P.Installed 'updates' ("$Bucket-$stamp/installed-manifest.txt")) }
    $instIni = Join-UpdPath $P.Dir 'installed.ini'
    $prevInst = Join-UpdPath $prevDir 'installed.ini'
    if (Test-Path -LiteralPath $prevInst) { Copy-UpdFile $prevInst $instIni }
    elseif (Test-Path -LiteralPath $instIni) { [void](Move-UpdToSafe $Ws $instIni 'updates' ("$Bucket-$stamp/installed.ini")) }

    # previous\ has been used up. Into SAFE TO DELETE with it.
    if (Test-Path -LiteralPath $prevDir) { [void](Move-UpdToSafe $Ws $prevDir 'updates' ("previous-used-" + $stamp)) }
    return $count
}

# ===========================================================================
#  3. GO BACK
# ===========================================================================
function Get-UpdGoBackInfo([string]$Ws) {
    $P = Get-UpdPaths $Ws
    $info = Read-UpdIni (Join-UpdPath $P.Previous 'info.ini')
    if (-not $info['to']) { return $null }
    if (-not (Test-Path -LiteralPath (Join-UpdPath $P.Previous 'changes.txt'))) { return $null }
    return @{ From = [string]$info['from']; To = [string]$info['to']; Time = [string]$info['time'] }
}

function Invoke-UpdateGoBack {
    param([Parameter(Mandatory = $true)][string]$Ws)
    $res = @{ Ok = $false; Message = ''; Version = '' }
    $info = Get-UpdGoBackInfo $Ws
    if ($null -eq $info) { $res.Message = 'There is no update to go back from.'; return $res }
    if (Test-UpdRetroBatRunning) { $res.Message = 'RetroBat is open. Close it completely, then try again.'; return $res }
    if (-not (Enter-UpdLock $Ws)) { $res.Message = 'An update check is still running. Try again in a minute.'; return $res }
    $P = Get-UpdPaths $Ws
    try {
        $fromChan = [string](Read-UpdIni (Join-UpdPath $P.Previous 'info.ini'))['fromchannel']
        $n = Undo-UpdJournal $Ws ('went-back-from-' + $info.To)
        [System.IO.File]::WriteAllText($P.Skip, $info.To)
        # Going back from a channel switch switches the channel back too.
        if ($fromChan -ne '' -and $fromChan -ne (Get-UpdConfig $Ws).Channel) {
            Set-UpdChannel $Ws $fromChan
            Write-UpdLog $Ws ("go back: channel back to {0}" -f $fromChan)
        }
        $res.Ok = $true
        $res.Version = $info.From
        $res.Message = "Went back from $($info.To) to $($info.From)."
        Write-UpdLog $Ws ("go back: {0} -> {1}, {2} file(s) put back" -f $info.To, $info.From, $n)
        Write-UpdStatus $Ws @{ state = 'wentback'; version = $info.To; current = (Get-UpdLocalVersion $Ws); message = $res.Message }
    }
    catch {
        $res.Message = 'Going back hit an error: ' + $_.Exception.Message + '. Details in update\update.log.'
        Write-UpdLog $Ws ("go back: FAILED - " + $_.Exception.Message)
    }
    finally { Exit-UpdLock $Ws }
    return $res
}
