<#
    SteamEngine.ps1
    ---------------------------------------------------------------------------
    Everything this drive knows about Steam. FUNCTIONS ONLY - dot-source it.
    Nothing in this file does anything until something calls it.

    WHAT THE STEAM SYSTEM IS. A shelf of party games that live on this drive
    in <drive>\SteamLibrary, shown inside RetroBat as ordinary game tiles in
    the stock "windows" system, so you never close RetroBat to play them.

    THE FOUR IDEAS THIS FILE IS BUILT ON, in order of how much trouble each
    one saves:

    1. THE GAME LIST IS NEVER TYPED OUT. Steam writes a small bookkeeping file
       called appmanifest_<id>.acf beside every game it installs. It holds the
       game's number and its name. We read those. No lookup table, no web
       call, no list to keep in sync - exactly how game names work everywhere
       else on this drive. A game that is not installed here gets no tile,
       which is right, because it would not launch.

    2. THE SYSTEM IS GATED PER COMPUTER, NOT PER DRIVE. features.ini is one
       shared file, so a switch there would follow the drive onto somebody
       else's PC. Instead a [steam] section is written into THIS computer's
       profile at machine\machines\<name>.ini. A computer that has never run
       Connect Steam has no such section, so Sync-SteamSystem parks the
       shortcuts and RetroBat shows no Steam games at all.

    2b. IT USES RETROBAT'S OWN 'steam' SYSTEM, not 'windows'. RetroBat already
       ships a Steam system in es_systems.cfg - roms\steam, .url files, its
       own theme name - so the tiles get a proper Steam shelf with Steam
       artwork instead of being lumped in with generic PC games. Nothing
       custom is added to es_systems.cfg, which means a RetroBat update
       cannot break it. The first sync moves any tiles left in roms\windows
       by an earlier version across.

    3. NOTHING IS EVER DELETED. Parked shortcuts move to
       _Wizard\Settings\steam\parked\. Steam's library list is backed up with
       a timestamp, per computer, before any edit.

    4. POINTING STEAM AT THIS DRIVE ADDS, IT NEVER REPLACES. libraryfolders.vdf
       is a numbered list. Entry "0" is always the host's own Steam install and
       is never touched. We append one entry. Unplugging the drive later leaves
       every game on the host's own drives working exactly as before.

    RULES HONOURED HERE (see the customization record):
      - no drive letters anywhere; everything derives from -Root
      - no $PSScriptRoot inside a param() block
      - Windows PowerShell 5.1 only, no PowerShell 7 syntax
      - pure ASCII, no byte-order mark
      - no function throws. A failure returns $false, '' or an empty list.
#>

Set-StrictMode -Off

$script:SteamSectionName = 'steam'
$script:SteamParkedDir   = '_Wizard\Settings\steam\parked'
$script:SteamBackupDir   = '_Wizard\Backups\Steam'
$script:SteamIndexFile   = '_Wizard\Settings\steam\steam-shortcuts.txt'
$script:SteamRomsDir     = 'roms\steam'
$script:SteamOldRomsDir  = 'roms\windows'
$script:SteamInfoFile    = '_Wizard\Settings\steam\steam-game-info.txt'
$script:SteamOwnerFile   = '_Wizard\Settings\steam\steam-owner.txt'

# Steam's own store categories that mean "can be played together on ONE
# screen": Shared/Split Screen (24), its PvP (37) and Co-op (39) versions, and
# Remote Play Together (44), which Steam only offers for games with local
# multiplayer. Party games like Jackbox and versus games like Stick Fight
# count, which is what "couch multiplayer" is meant to cover.
$script:SteamCouchCategories = @(24, 37, 39, 44)

# Things Steam installs that are not games and should never get a tile,
# whatever filter is chosen. Patterns, like steam-hidden.txt.
$script:SteamNeverTiles = @('Steamworks Common Redistributables', 'Steam Linux Runtime*', 'Proton*', 'SteamVR*', 'Steam Controller Configs*')

# Store types that are never a game to play. Anything else, including a
# type nobody has checked yet, is allowed through.
$script:SteamNotGameTypes = @('dlc', 'music', 'video', 'hardware', 'advertising', 'series', 'episode', 'mod', 'demo')
$script:SteamHiddenFile  = '_Wizard\Settings\steam\steam-hidden.txt'

# ===========================================================================
#  PART ONE - what is on THIS DRIVE
# ===========================================================================

# The SteamLibrary folder, which sits beside RetroBat at the top of the drive.
# Returns '' when RetroBat is not at a drive root, or when no library exists
# yet. Never guesses a letter: the answer is derived from -Root.
function Get-SteamDriveLibrary {
    param([string]$Root)
    try {
        if ([string]::IsNullOrWhiteSpace($Root)) { return '' }
        $parent = Split-Path -Path $Root -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) { return '' }
        $lib = Join-Path $parent 'SteamLibrary'
        if (Test-Path -LiteralPath (Join-Path $lib 'steamapps')) { return $lib }
        return ''
    }
    catch { return '' }
}

# Pull one quoted value out of a Valve text file:  "key"   "value"
function Get-VdfValue {
    param([string]$Text, [string]$Key)
    try {
        $pattern = '(?im)^\s*"' + [regex]::Escape($Key) + '"\s+"([^"]*)"'
        $m = [regex]::Match($Text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    catch { }
    return ''
}

# Every Steam game installed on this drive.
# Returns psobjects: AppId, Name, InstallDir, StateFlags, Installed, FileName.
#
# Installed is the one that matters. Steam's StateFlags is a set of bits and
# bit 4 means "fully installed". A game that is still downloading has that bit
# clear, and a manifest can also sit there for a game whose files were never
# written, so the folder is checked as well. Both must be true.
function Get-SteamGamesOnDrive {
    param([string]$Root)
    try {
        $lib = Get-SteamDriveLibrary -Root $Root
        if ($lib -eq '') { return @() }
        return @(Get-SteamGamesInLibrary -Library $lib)
    }
    catch { return @() }
}

# The same, for ANY Steam library folder (the drive's, or one on the
# computer). Returns psobjects: AppId, Name, InstallDir, StateFlags,
# Installed, FileName, Library.
function Get-SteamGamesInLibrary {
    param([string]$Library)

    $out = @()
    try {
        if ([string]::IsNullOrWhiteSpace($Library)) { return $out }
        $apps   = Join-Path $Library 'steamapps'
        $common = Join-Path $apps 'common'
        if (-not (Test-Path -LiteralPath $apps)) { return $out }

        foreach ($f in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $text = [System.IO.File]::ReadAllText($f.FullName)

                $appId      = Get-VdfValue -Text $text -Key 'appid'
                $name       = Get-VdfValue -Text $text -Key 'name'
                $installDir = Get-VdfValue -Text $text -Key 'installdir'
                $flagsText  = Get-VdfValue -Text $text -Key 'StateFlags'

                if ($appId -eq '' -or $name -eq '') { continue }

                $flags = 0
                [void][int]::TryParse($flagsText, [ref]$flags)

                $hasFiles = $false
                if ($installDir -ne '') {
                    $hasFiles = Test-Path -LiteralPath (Join-Path $common $installDir)
                }

                $out += [pscustomobject]@{
                    AppId      = $appId
                    Name       = $name
                    InstallDir = $installDir
                    StateFlags = $flags
                    Installed  = (($flags -band 4) -ne 0) -and $hasFiles
                    FileName   = $f.Name
                    Library    = $Library
                }
            }
            catch { continue }
        }
    }
    catch { return @() }

    return @($out | Sort-Object Name)
}

# ===========================================================================
#  PART TWO - what is on THIS COMPUTER
# ===========================================================================

# Where Steam is installed on the computer the drive is plugged into.
# Three places are tried, cheapest first. The third is a happy accident: Steam
# writes the path of the client that made a library into that library's own
# libraryfolder.vdf, so the drive can often answer this by itself.
function Get-SteamRootOnComputer {
    param([string]$Root = '')
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue).SteamPath
        if ($p) {
            $p = $p -replace '/', '\'
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    catch { }

    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = (Get-ItemProperty -Path $key -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
        catch { }
    }

    try {
        if ($Root -ne '') {
            $lib = Get-SteamDriveLibrary -Root $Root
            if ($lib -ne '') {
                $own = Join-Path $lib 'libraryfolder.vdf'
                if (Test-Path -LiteralPath $own) {
                    $launcher = Get-VdfValue -Text ([System.IO.File]::ReadAllText($own)) -Key 'launcher'
                    $launcher = $launcher -replace '\\\\', '\'
                    if ($launcher -ne '') {
                        $dir = Split-Path -Path $launcher -Parent
                        if ($dir -and (Test-Path -LiteralPath $dir)) { return $dir }
                    }
                }
            }
        }
    }
    catch { }

    return ''
}

function Test-SteamInstalled {
    param([string]$Root = '')
    return ((Get-SteamRootOnComputer -Root $Root) -ne '')
}

function Get-SteamExe {
    param([string]$Root = '')
    try {
        $s = Get-SteamRootOnComputer -Root $Root
        if ($s -eq '') { return '' }
        $exe = Join-Path $s 'steam.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    catch { }
    return ''
}

function Test-SteamRunning {
    try { return (@(Get-Process -Name 'steam' -ErrorAction SilentlyContinue).Count -gt 0) }
    catch { return $false }
}

# Close Steam the way Steam wants to be closed, and wait for it to go.
#
# THIS MATTERS MORE THAN IT LOOKS. Steam rewrites libraryfolders.vdf when it
# shuts down, so anything written while it is running gets thrown away a
# minute later. Killing the process instead would risk that same file being
# half written. So: ask nicely, then wait.
function Stop-SteamClient {
    param([int]$TimeoutSeconds = 30, [string]$Root = '')
    try {
        if (-not (Test-SteamRunning)) { return $true }
        $exe = Get-SteamExe -Root $Root
        if ($exe -ne '') {
            Start-Process -FilePath $exe -ArgumentList '-shutdown' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
        }
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            if (-not (Test-SteamRunning)) { return $true }
        }
        return (-not (Test-SteamRunning))
    }
    catch { return $false }
}

function Start-SteamClient {
    param([string]$Root = '', [string[]]$Arguments = @())
    try {
        $exe = Get-SteamExe -Root $Root
        if ($exe -eq '') { return $false }
        if ($Arguments.Count -gt 0) {
            Start-Process -FilePath $exe -ArgumentList $Arguments -ErrorAction SilentlyContinue | Out-Null
        } else {
            Start-Process -FilePath $exe -ErrorAction SilentlyContinue | Out-Null
        }
        return $true
    }
    catch { return $false }
}

# Which Steam account is signed in on this computer right now.
# Returns an object: Account (the login name), Persona (the display name),
# SteamId. Empty strings mean nobody is signed in, or Steam has never run.
function Get-SteamLoginUser {
    param([string]$Root = '')

    $account = ''
    $persona = ''
    $steamId = ''

    try {
        $account = [string](Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'AutoLoginUser' -ErrorAction SilentlyContinue).AutoLoginUser
    }
    catch { }

    try {
        $s = Get-SteamRootOnComputer -Root $Root
        if ($s -ne '') {
            $f = Join-Path $s 'config\loginusers.vdf'
            if (Test-Path -LiteralPath $f) {
                $text = [System.IO.File]::ReadAllText($f)
                # Blocks look like:  "76561198..."  {  "AccountName" "x" ... }
                $rx = [regex]'(?s)"(7656\d+)"\s*\{(.*?)\n\t\}'
                foreach ($m in $rx.Matches($text)) {
                    $block = $m.Groups[2].Value
                    $acct  = Get-VdfValue -Text $block -Key 'AccountName'
                    $pers  = Get-VdfValue -Text $block -Key 'PersonaName'
                    $most  = Get-VdfValue -Text $block -Key 'MostRecent'
                    if (($account -ne '' -and $acct -eq $account) -or ($account -eq '' -and $most -eq '1')) {
                        $steamId = $m.Groups[1].Value
                        $persona = $pers
                        if ($account -eq '') { $account = $acct }
                        break
                    }
                }
            }
        }
    }
    catch { }

    return [pscustomobject]@{
        Account = $account
        Persona = $persona
        SteamId = $steamId
    }
}

# ===========================================================================
#  PART THREE - Steam's library list
# ===========================================================================

function Get-SteamLibraryFoldersFile {
    param([string]$SteamRoot)
    try {
        if ([string]::IsNullOrWhiteSpace($SteamRoot)) { return '' }
        return (Join-Path $SteamRoot 'steamapps\libraryfolders.vdf')
    }
    catch { return '' }
}

# Is this drive's SteamLibrary already in Steam's list on this computer?
#
# FIXED 2026-10-13 (Steven, on the ZBook: "it said it was already connected"
# when Steam was NOT using the drive). Steam keeps an entry in its list even
# for a library it is not actually using - a drive it could not read, or an
# entry written by hand that it never accepted. Just finding the path was
# taken as "connected", so setup skipped the one step that mattered.
#
# Now the entry has to show Steam really using the folder: Steam fills in the
# entry's "apps" list with every game it has found there. An empty list on a
# drive that holds games means the entry is stale, so this answers no and
# setup offers to add the drive properly.
#   -PathOnly  the old question (is the path in the file at all?), still
#              used before adding so a second copy of the entry is never made.
function Test-SteamLibraryRegistered {
    param([string]$SteamRoot, [string]$LibraryPath, [switch]$PathOnly)
    try {
        if ([string]::IsNullOrWhiteSpace($LibraryPath)) { return $false }
        $f = Get-SteamLibraryFoldersFile -SteamRoot $SteamRoot
        if ($f -eq '' -or -not (Test-Path -LiteralPath $f)) { return $false }
        $text = [System.IO.File]::ReadAllText($f)
        # Paths in the file are escaped:  "R:\\SteamLibrary"
        $plain  = ($text -replace '\\\\', '\')
        $wanted = $LibraryPath.TrimEnd('\')
        $m = [regex]::Match($plain, ('(?i)"path"\s+"' + [regex]::Escape($wanted) + '\\?"'))
        if (-not $m.Success) { return $false }
        if ($PathOnly) { return $true }

        # The drive has no downloaded games? Then there is nothing for Steam
        # to list, and the path being there is all that can be checked.
        $manifests = @(Get-ChildItem -LiteralPath (Join-Path $LibraryPath 'steamapps') -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)
        if ($manifests.Count -eq 0) { return $true }

        # This entry's own "apps" block: after its path, before the next path.
        $rest = $plain.Substring($m.Index + $m.Length)
        $next = [regex]::Match($rest, '(?i)"path"\s+"')
        if ($next.Success) { $rest = $rest.Substring(0, $next.Index) }
        $apps = [regex]::Match($rest, '(?is)"apps"\s*\{(.*?)\}')
        if (-not $apps.Success) { return $false }
        return ([regex]::IsMatch($apps.Groups[1].Value, '"\d+"\s+"\d+"'))
    }
    catch { return $false }
}

# Copy Steam's library list somewhere safe, per computer, with a timestamp.
# Returns the backup's path, or '' if nothing was copied.
function Backup-SteamLibraryFolders {
    param([string]$Root, [string]$SteamRoot)
    try {
        $src = Get-SteamLibraryFoldersFile -SteamRoot $SteamRoot
        if ($src -eq '' -or -not (Test-Path -LiteralPath $src)) { return '' }

        $dir = Join-Path $Root ($script:SteamBackupDir + '\' + [string]$env:COMPUTERNAME)
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $dest = Join-Path $dir ('libraryfolders_{0}.vdf' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
        Copy-Item -LiteralPath $src -Destination $dest -Force
        return $dest
    }
    catch { return '' }
}

function Get-SteamLibraryBackups {
    param([string]$Root)
    try {
        $dir = Join-Path $Root ($script:SteamBackupDir + '\' + [string]$env:COMPUTERNAME)
        if (-not (Test-Path -LiteralPath $dir)) { return @() }
        return @(Get-ChildItem -LiteralPath $dir -Filter 'libraryfolders_*.vdf' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)
    }
    catch { return @() }
}

# Add this drive to Steam's library list. ADDS ONE ENTRY. Never rewrites,
# reorders or removes anything that was already there.
#
# Steam must be closed first - the caller does that, and this checks anyway.
# Returns an object: Ok, Message, Backup.
function Add-SteamLibraryFolder {
    param([string]$Root, [string]$SteamRoot, [string]$LibraryPath)

    $result = [pscustomobject]@{ Ok = $false; Message = ''; Backup = '' }

    try {
        if (Test-SteamRunning) {
            $result.Message = 'Steam is still running. It has to be closed first, or it will overwrite the change when it exits.'
            return $result
        }

        $f = Get-SteamLibraryFoldersFile -SteamRoot $SteamRoot
        if ($f -eq '' -or -not (Test-Path -LiteralPath $f)) {
            $result.Message = "Could not find Steam's library list. Looked for: $f"
            return $result
        }

        if (Test-SteamLibraryRegistered -SteamRoot $SteamRoot -LibraryPath $LibraryPath -PathOnly) {
            # In the list but not being used (see Test-SteamLibraryRegistered).
            # Writing a second entry would not help; Steam's own Add Drive is
            # what makes it take the folder properly.
            $result.Ok = $false
            $result.Message = 'This drive is already in Steam''s list, but Steam is not using it. Use the Manual way: Steam''s own Add Drive sorts it out.'
            return $result
        }

        $result.Backup = Backup-SteamLibraryFolders -Root $Root -SteamRoot $SteamRoot
        if ($result.Backup -eq '') {
            $result.Message = 'Could not make a backup of the library list, so nothing was changed.'
            return $result
        }

        $lines = @([System.IO.File]::ReadAllLines($f))

        # Highest entry number already in use.
        $highest = -1
        foreach ($line in $lines) {
            if ($line -match '^\s*"(\d+)"\s*$') {
                $n = [int]$Matches[1]
                if ($n -gt $highest) { $highest = $n }
            }
        }
        $next = $highest + 1

        # Reuse the contentid Steam itself wrote into this library when it is
        # there. Steam recalculates the size fields on its next start.
        $contentId = '0'
        try {
            $own = Join-Path $LibraryPath 'libraryfolder.vdf'
            if (Test-Path -LiteralPath $own) {
                $c = Get-VdfValue -Text ([System.IO.File]::ReadAllText($own)) -Key 'contentid'
                if ($c -ne '') { $contentId = $c }
            }
        }
        catch { }

        $escaped = $LibraryPath.TrimEnd('\') -replace '\\', '\\'
        $t = [string][char]9

        $block = @(
            ($t + '"' + $next + '"')
            ($t + '{')
            ($t + $t + '"path"' + $t + $t + '"' + $escaped + '"')
            ($t + $t + '"label"' + $t + $t + '""')
            ($t + $t + '"contentid"' + $t + $t + '"' + $contentId + '"')
            ($t + $t + '"totalsize"' + $t + $t + '"0"')
            ($t + $t + '"update_clean_bytes_tally"' + $t + $t + '"0"')
            ($t + $t + '"time_last_update_verified"' + $t + $t + '"0"')
            ($t + $t + '"apps"')
            ($t + $t + '{')
            ($t + $t + '}')
            ($t + '}')
        )

        # Insert before the LAST closing brace, which closes the outer block.
        $closeAt = -1
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i].Trim() -eq '}') { $closeAt = $i; break }
        }
        if ($closeAt -lt 0) {
            $result.Message = "Steam's library list is not shaped the way this expected, so nothing was changed."
            return $result
        }

        $new = @()
        if ($closeAt -gt 0) { $new += $lines[0..($closeAt - 1)] }
        $new += $block
        $new += $lines[$closeAt..($lines.Count - 1)]

        [System.IO.File]::WriteAllLines($f, $new, (New-Object System.Text.UTF8Encoding($false)))

        $result.Ok = $true
        $result.Message = "Added this drive to Steam's library list as entry $next."
        return $result
    }
    catch {
        $result.Message = 'Something went wrong writing the library list: ' + $_.Exception.Message
        return $result
    }
}

# The drive just changed letter (for example D: to R:). Steam's library list
# still points at the OLD letter, so every game on the drive would show as not
# installed until somebody disconnected and reconnected Steam by hand
# (2026-09-25, the first time R: was claimed). This rewrites that one path in
# place, keeping the entry's number, id and everything else. Nothing else in
# the file is touched, and a copy is kept first as always.
#
# Steam must be closed or it overwrites the change on exit; this closes it
# politely if it is open, the same way Connect Steam does.
# Returns an object: Ok, Changed, Message.
function Move-SteamLibraryLetter {
    param([string]$Root, [string]$OldLibraryPath, [string]$NewLibraryPath)

    $result = [pscustomobject]@{ Ok = $true; Changed = $false; Message = '' }
    try {
        $steamRoot = Get-SteamRootOnComputer -Root $Root
        if ($steamRoot -eq '') { $result.Message = 'Steam is not installed here, nothing to fix.'; return $result }
        if (-not (Test-SteamLibraryRegistered -SteamRoot $steamRoot -LibraryPath $OldLibraryPath -PathOnly)) {
            $result.Message = 'Steam was not connected to this drive here, nothing to fix.'
            return $result
        }
        if (Test-SteamLibraryRegistered -SteamRoot $steamRoot -LibraryPath $NewLibraryPath -PathOnly) {
            $result.Message = 'Steam already knows the new letter.'
            return $result
        }

        if (Test-SteamRunning) {
            if (-not (Stop-SteamClient -Root $Root)) {
                $result.Ok = $false
                $result.Message = 'Steam would not close, so its library list was left alone. Disconnect and reconnect Steam on the Machine tab to fix it.'
                return $result
            }
        }

        $f = Get-SteamLibraryFoldersFile -SteamRoot $steamRoot
        [void](Backup-SteamLibraryFolders -Root $Root -SteamRoot $steamRoot)

        $text = [System.IO.File]::ReadAllText($f)
        $oldEsc = $OldLibraryPath.TrimEnd('\') -replace '\\', '\\'
        $newEsc = $NewLibraryPath.TrimEnd('\') -replace '\\', '\\'
        $pattern = '(?i)("path"\s+")' + [regex]::Escape($oldEsc) + '(\\\\)?"'
        $fixed = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $newEsc + '"' })
        if ($fixed -eq $text) {
            $result.Ok = $false
            $result.Message = 'Could not find the old path in Steam''s library list. Disconnect and reconnect Steam on the Machine tab.'
            return $result
        }
        [System.IO.File]::WriteAllText($f, $fixed, (New-Object System.Text.UTF8Encoding($false)))
        $result.Changed = $true
        $result.Message = ('Steam now looks for its games at ' + $NewLibraryPath + '.')
        return $result
    }
    catch {
        $result.Ok = $false
        $result.Message = 'Could not update Steam''s library list: ' + $_.Exception.Message
        return $result
    }
}

# Take this drive back out of Steam's library list, leaving every other entry
# exactly as it was, and renumber what is left so the numbering stays tidy.
# Returns an object: Ok, Message, Backup.
function Remove-SteamLibraryFolder {
    param([string]$Root, [string]$SteamRoot, [string]$LibraryPath)

    $result = [pscustomobject]@{ Ok = $false; Message = ''; Backup = '' }

    try {
        if (Test-SteamRunning) {
            $result.Message = 'Steam is still running. It has to be closed first.'
            return $result
        }

        $f = Get-SteamLibraryFoldersFile -SteamRoot $SteamRoot
        if ($f -eq '' -or -not (Test-Path -LiteralPath $f)) {
            $result.Message = "Could not find Steam's library list."
            return $result
        }

        if (-not (Test-SteamLibraryRegistered -SteamRoot $SteamRoot -LibraryPath $LibraryPath -PathOnly)) {
            $result.Ok = $true
            $result.Message = 'This drive was not in the list. Nothing was changed.'
            return $result
        }

        $result.Backup = Backup-SteamLibraryFolders -Root $Root -SteamRoot $SteamRoot
        if ($result.Backup -eq '') {
            $result.Message = 'Could not make a backup first, so nothing was changed.'
            return $result
        }

        $lines  = @([System.IO.File]::ReadAllLines($f))
        $wanted = $LibraryPath.TrimEnd('\')

        $keep    = @()
        $i       = 0
        $removed = 0

        while ($i -lt $lines.Count) {
            if ($lines[$i] -match '^\s*"(\d+)"\s*$') {
                $start = $i
                $open  = -1
                $j     = $i + 1
                if ($j -lt $lines.Count -and $lines[$j].Trim() -eq '{') { $open = $j }

                if ($open -lt 0) { $keep += $lines[$i]; $i++; continue }

                $depth = 0
                $end   = -1
                for ($k = $open; $k -lt $lines.Count; $k++) {
                    $tr = $lines[$k].Trim()
                    if ($tr -eq '{') { $depth++ }
                    elseif ($tr -eq '}') { $depth--; if ($depth -eq 0) { $end = $k; break } }
                }
                if ($end -lt 0) { $keep += $lines[$i]; $i++; continue }

                $blockText = ($lines[$start..$end] -join "`n") -replace '\\\\', '\'
                if ($blockText -match ('(?i)"path"\s+"' + [regex]::Escape($wanted) + '\\?"')) {
                    $removed++
                    $i = $end + 1
                    continue
                }

                $keep += $lines[$start..$end]
                $i = $end + 1
                continue
            }

            $keep += $lines[$i]
            $i++
        }

        if ($removed -eq 0) {
            $result.Message = 'Could not find the entry to remove, so nothing was changed.'
            return $result
        }

        # Renumber what is left, in the order it appears.
        $n = 0
        for ($k = 0; $k -lt $keep.Count; $k++) {
            if ($keep[$k] -match '^(\s*)"(\d+)"\s*$') {
                $keep[$k] = $Matches[1] + '"' + $n + '"'
                $n++
            }
        }

        [System.IO.File]::WriteAllLines($f, $keep, (New-Object System.Text.UTF8Encoding($false)))

        $result.Ok = $true
        $result.Message = "Removed this drive from Steam's library list. $n other library folder(s) left untouched."
        return $result
    }
    catch {
        $result.Message = 'Something went wrong editing the library list: ' + $_.Exception.Message
        return $result
    }
}

# Put back a backup taken on this computer. Defaults to the newest one.
function Restore-SteamLibraryFolders {
    param([string]$Root, [string]$SteamRoot, [string]$BackupPath = '')

    $result = [pscustomobject]@{ Ok = $false; Message = '' }
    try {
        if (Test-SteamRunning) {
            $result.Message = 'Steam is still running. It has to be closed first.'
            return $result
        }

        $src = $BackupPath
        if ($src -eq '') {
            $all = Get-SteamLibraryBackups -Root $Root
            if ($all.Count -eq 0) {
                $result.Message = 'There are no backups of the library list from this computer.'
                return $result
            }
            $src = $all[0].FullName
        }

        $dest = Get-SteamLibraryFoldersFile -SteamRoot $SteamRoot
        if ($dest -eq '') {
            $result.Message = 'Could not work out where Steam keeps its library list.'
            return $result
        }

        # Back up what is there NOW before overwriting it, so a restore is
        # itself undoable.
        [void](Backup-SteamLibraryFolders -Root $Root -SteamRoot $SteamRoot)

        Copy-Item -LiteralPath $src -Destination $dest -Force
        $result.Ok = $true
        $result.Message = 'Put back the library list from ' + (Split-Path $src -Leaf) + '.'
        return $result
    }
    catch {
        $result.Message = 'Could not put the library list back: ' + $_.Exception.Message
        return $result
    }
}

# ===========================================================================
#  PART FOUR - the [steam] section in THIS COMPUTER'S profile
# ===========================================================================

# Which profile file belongs to the computer in use right now.
# Honours a pinned profile when ProfileEngine.ps1 has been loaded too.
function Get-SteamProfileFile {
    param([string]$Root)
    try {
        $dir = Join-Path $Root '_Wizard\Settings\computers'
        if (-not (Test-Path -LiteralPath $dir)) { return '' }

        $pinned = ''
        if (Get-Command -Name 'Get-PinnedProfile' -ErrorAction SilentlyContinue) {
            $pinned = Get-PinnedProfile -Root $Root
        }

        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            if ($pinned -ne '') {
                if ($text -match ('(?im)^\s*name\s*=\s*' + [regex]::Escape($pinned) + '\s*$')) { return $f.FullName }
            }
            else {
                if ($text -match ('(?im)^\s*machine\s*=\s*' + [regex]::Escape([string]$env:COMPUTERNAME) + '\s*$')) { return $f.FullName }
            }
        }
    }
    catch { }
    return ''
}

# Read this computer's Steam state.
# Returns: Connected (bool), Library, Account, ProfileFile, ProfileName,
#          Mode, Filter, Picked, Unpicked.
#
# Mode (added 2026-09-25, "friends' Steam"):
#   owner  - the drive owner's account: the drive's games AND anything
#            downloaded on this computer
#   guest  - somebody else's account: only games downloaded on this computer
#   ''     - set up before this existed: the drive's games, all of them,
#            exactly as it always worked. Running Steam setup again moves it on.
# Filter: couch | solo | all   (which games start ticked)
# Picked / Unpicked: app numbers somebody ticked or unticked by hand. They
# always win over the filter. A game in neither list follows the filter, so a
# game downloaded later turns up on its own if it fits.
function Get-SteamProfileState {
    param([string]$Root)

    $state = [pscustomobject]@{
        Connected   = $false
        Library     = ''
        Account     = ''
        ProfileFile = ''
        ProfileName = ''
        Mode        = ''
        Filter      = 'all'
        Picked      = @()
        Unpicked    = @()
    }

    try {
        $f = Get-SteamProfileFile -Root $Root
        if ($f -eq '') { return $state }
        $state.ProfileFile = $f

        $inSteam = $false
        foreach ($raw in @([System.IO.File]::ReadAllLines($f))) {
            $line = $raw.Trim()
            if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }

            if ($line.StartsWith('[') -and $line.EndsWith(']')) {
                $inSteam = ($line.Substring(1, $line.Length - 2).Trim() -ieq $script:SteamSectionName)
                continue
            }

            $eq = $line.IndexOf('=')
            if ($eq -lt 1) { continue }
            $key = $line.Substring(0, $eq).Trim()
            $val = $line.Substring($eq + 1).Trim()
            $semi = $val.IndexOf(';'); if ($semi -ge 0) { $val = $val.Substring(0, $semi).Trim() }

            if (-not $inSteam) {
                if ($key -ieq 'name' -and $state.ProfileName -eq '') { $state.ProfileName = $val }
                continue
            }

            if ($key -imatch '^connected$') { $state.Connected = ($val -imatch '^(yes|on|true|1)$') }
            elseif ($key -imatch '^library$') { $state.Library = $val }
            elseif ($key -imatch '^account$') { $state.Account = $val }
            elseif ($key -imatch '^mode$')    { $state.Mode = $val.ToLower() }
            elseif ($key -imatch '^filter$')  { $state.Filter = $val.ToLower() }
            elseif ($key -imatch '^picked$')   { $state.Picked   = @($val -split '[,\s]+' | Where-Object { $_ -match '^\d+$' }) }
            elseif ($key -imatch '^unpicked$') { $state.Unpicked = @($val -split '[,\s]+' | Where-Object { $_ -match '^\d+$' }) }
        }
    }
    catch { }

    return $state
}

# Write the [steam] section into this computer's profile, keeping every other
# line and every comment exactly as it was. Creates the section when missing.
function Set-SteamProfileState {
    param(
        [string]$Root,
        [bool]$Connected,
        [string]$Library = '',
        [string]$Account = '',
        [string]$Mode = '',
        [string]$Filter = 'couch',
        [string[]]$Picked = @(),
        [string[]]$Unpicked = @()
    )

    try {
        $f = Get-SteamProfileFile -Root $Root
        if ($f -eq '') { return $false }

        $lines = @([System.IO.File]::ReadAllLines($f))

        $connectedWord = 'no'
        if ($Connected) { $connectedWord = 'yes' }

        $body = @(
            '[steam]'
            ('; Written by Steam setup on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '.')
            '; This is what decides whether the Steam games show up in RetroBat on'
            '; THIS computer. It lives here, per computer, rather than in features.ini,'
            '; because features.ini is one shared file and would follow the drive onto'
            '; somebody else''s PC. Set connected to no, or delete this whole section,'
            '; and the Steam tiles disappear from this computer at the next launch.'
            ('connected = ' + $connectedWord)
            ('library   = ' + $Library)
            ('account   = ' + $Account)
        )
        if ($Connected -and $Mode -ne '') {
            $body += @(
                '; mode: owner = the drive owner''s games plus this computer''s,'
                ';       guest = only games downloaded on this computer.'
                '; filter: couch, solo or all - which games start ticked.'
                '; picked / unpicked: games ticked or unticked by hand (Steam app'
                '; numbers). Change them with Steam setup on the wizard''s Machine tab.'
                ('mode      = ' + $Mode)
                ('filter    = ' + $Filter)
                ('picked    = ' + (@($Picked) -join ', '))
                ('unpicked  = ' + (@($Unpicked) -join ', '))
            )
        }

        # Find an existing [steam] section and replace it whole.
        $start = -1
        $end   = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t -imatch '^\[\s*steam\s*\]$') { $start = $i; continue }
            if ($start -ge 0 -and $t.StartsWith('[') -and $t.EndsWith(']')) { $end = $i; break }
        }

        if ($start -ge 0) {
            $before = @()
            if ($start -gt 0) { $before = $lines[0..($start - 1)] }
            $after = @()
            if ($end -lt $lines.Count) { $after = $lines[$end..($lines.Count - 1)] }
            $new = @($before) + @($body) + @($after)
        }
        else {
            $new = @($lines) + @('') + @($body)
        }

        [System.IO.File]::WriteAllLines($f, $new, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

# ===========================================================================
#  PART FOUR-B - which games, for whom (2026-09-25, "friends' Steam")
# ===========================================================================
#
#  A friend with their own Steam account can put THEIR couch games on the
#  shelf while the drive is at their place, without touching their Steam
#  settings. And the drive owner's shelf can include games downloaded on the
#  computer as well as the ones on the drive.
#
#  DOWNLOADED GAMES ONLY, on purpose. A tile for a game that is not installed
#  would make Steam start a download when it is picked, which is a bad
#  surprise at a party.
#
#  WHICH GAMES COUNT AS COUCH MULTIPLAYER is Steam's own answer, from the
#  store's category list, cached on the drive in machine\steam-game-info.txt
#  so it is fetched once per game, ever, and PLAY never needs the internet.

# Every Steam library folder this computer's Steam knows about, including its
# own. Read from libraryfolders.vdf; only folders that exist are returned.
function Get-SteamComputerLibraries {
    param([string]$Root = '')
    $out = @()
    try {
        $steamRoot = Get-SteamRootOnComputer -Root $Root
        if ($steamRoot -eq '') { return $out }
        $f = Get-SteamLibraryFoldersFile -SteamRoot $steamRoot
        if ($f -ne '' -and (Test-Path -LiteralPath $f)) {
            $text = [System.IO.File]::ReadAllText($f)
            foreach ($m in [regex]::Matches($text, '(?i)"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                if ((Test-Path -LiteralPath (Join-Path $p 'steamapps')) -and -not ($out -contains $p)) { $out += $p }
            }
        }
        if ($out.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $steamRoot 'steamapps'))) { $out += $steamRoot }
    }
    catch { }
    return $out
}

# --- the game information cache -------------------------------------------
#  One line per game:   appid | type | couch | category numbers | controller | name
#  couch is yes / no. controller is full / partial / none, from the store.

function Get-SteamGameInfo {
    param([string]$Root)
    $table = @{}
    try {
        $f = Join-Path $Root $script:SteamInfoFile
        if (-not (Test-Path -LiteralPath $f)) { return $table }
        foreach ($line in @([System.IO.File]::ReadAllLines($f))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith(';')) { continue }
            $parts = $t.Split('|')
            if ($parts.Count -lt 6) { continue }
            $cats = @($parts[3].Trim() -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
            $table[$parts[0].Trim()] = [pscustomobject]@{
                AppId      = $parts[0].Trim()
                Type       = $parts[1].Trim().ToLower()
                Couch      = ($parts[2].Trim() -ieq 'yes')
                Categories = $cats
                Controller = $parts[4].Trim().ToLower()
                Name       = (($parts[5..($parts.Count - 1)]) -join '|').Trim()
            }
        }
    }
    catch { }
    return $table
}

function Set-SteamGameInfo {
    param([string]$Root, [hashtable]$Table)
    try {
        $f = Join-Path $Root $script:SteamInfoFile
        $dir = Split-Path $f -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $lines = @(
            '; What Steam''s store says about each Steam game this drive has met.'
            '; Written by Steam setup and Get Steam Artwork, read by PLAY to decide'
            '; which games count as couch multiplayer. Fetched once per game and kept,'
            '; so PLAY never needs the internet. Safe to delete: it is fetched again.'
            ';'
            '; appid | type | couch | store category numbers | controller | name'
        )
        foreach ($k in @($Table.Keys | Sort-Object)) {
            $i = $Table[$k]
            $couch = 'no'; if ($i.Couch) { $couch = 'yes' }
            $name = ([string]$i.Name).Replace("`r", ' ').Replace("`n", ' ')
            $lines += ('{0} | {1} | {2} | {3} | {4} | {5}' -f $i.AppId, $i.Type, $couch, ((@($i.Categories)) -join ','), $i.Controller, $name)
        }
        [System.IO.File]::WriteAllLines($f, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

# Is this a couch game? From a list of store category numbers.
function Test-SteamCouchCategories {
    param($Categories)
    foreach ($c in @($Categories)) { if ($script:SteamCouchCategories -contains [int]$c) { return $true } }
    return $false
}

# A few plain words about a game for the checklist: "couch co-op",
# "couch versus", "couch multiplayer", "solo or online only", or
# "not checked yet". Plus the controller support when known.
function Get-SteamGameKindText {
    param($Info)
    if ($null -eq $Info) { return 'not checked yet - needs the internet once' }
    $cats = @($Info.Categories)
    $kind = 'solo or online only'
    if ($cats -contains 39 -and $cats -contains 37) { $kind = 'couch co-op and versus' }
    elseif ($cats -contains 39) { $kind = 'couch co-op' }
    elseif ($cats -contains 37) { $kind = 'couch versus' }
    elseif ($Info.Couch)        { $kind = 'couch multiplayer' }
    switch ([string]$Info.Controller) {
        'full'    { $kind += ', full controller support' }
        'partial' { $kind += ', partial controller support' }
        'none'    { $kind += ', keyboard and mouse' }
    }
    return $kind
}

# --- who owns the drive's games --------------------------------------------
#  Remembered the first time somebody chooses "this is the drive owner's
#  account", so the setup window can say "Steven" rather than "the owner".

function Get-SteamDriveOwner {
    param([string]$Root)
    $o = [pscustomobject]@{ Account = ''; Persona = '' }
    try {
        $f = Join-Path $Root $script:SteamOwnerFile
        if (-not (Test-Path -LiteralPath $f)) { return $o }
        foreach ($line in @([System.IO.File]::ReadAllLines($f))) {
            if ($line -match '^\s*account\s*=\s*(.*)$') { $o.Account = $Matches[1].Trim() }
            elseif ($line -match '^\s*persona\s*=\s*(.*)$') { $o.Persona = $Matches[1].Trim() }
        }
    }
    catch { }
    return $o
}

function Set-SteamDriveOwner {
    param([string]$Root, [string]$Account, [string]$Persona)
    try {
        $f = Join-Path $Root $script:SteamOwnerFile
        $lines = @(
            '; The Steam account the games on this drive belong to. Written the'
            '; first time Steam setup is told "this is the drive owner''s account".'
            '; Only used for wording in that window. Safe to edit or delete.'
            ('account = ' + $Account)
            ('persona = ' + $Persona)
        )
        [System.IO.File]::WriteAllLines($f, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

# --- the candidates and the final list --------------------------------------

# Every downloaded game that COULD have a tile on this computer, for a mode,
# before anybody's ticks are applied. De-duplicated by app number, never a
# redistributable or a DLC, never anything steam-hidden.txt keeps out.
# Returns the same objects as Get-SteamGamesInLibrary.
function Get-SteamCandidateGames {
    param([string]$Root, [string]$Mode = 'owner')
    $out = @()
    try {
        $libs = @()
        $driveLib = Get-SteamDriveLibrary -Root $Root
        if ($Mode -ne 'guest' -and $driveLib -ne '') { $libs += $driveLib }
        if ($Mode -ne '') {
            foreach ($l in @(Get-SteamComputerLibraries -Root $Root)) {
                if ($driveLib -ne '' -and $l.TrimEnd('\') -ieq $driveLib.TrimEnd('\')) { continue }
                $libs += $l
            }
        }

        $hidden = @(Get-SteamHiddenPatterns -Root $Root) + $script:SteamNeverTiles
        $info = Get-SteamGameInfo -Root $Root
        $seen = @{}
        foreach ($l in $libs) {
            foreach ($g in @(Get-SteamGamesInLibrary -Library $l)) {
                if (-not $g.Installed) { continue }
                if ($seen.ContainsKey($g.AppId)) { continue }
                if (Test-SteamGameHidden -Name $g.Name -Patterns $hidden) { continue }
                if ($info.ContainsKey($g.AppId) -and ($script:SteamNotGameTypes -contains $info[$g.AppId].Type)) { continue }
                $seen[$g.AppId] = $true
                $out += $g
            }
        }
    }
    catch { }
    return @($out | Sort-Object Name)
}

# Would this game start ticked, going by the filter alone?
function Test-SteamGameFitsFilter {
    param($Info, [string]$Filter)
    switch ($Filter) {
        'all'   { return $true }
        'solo'  { return ($null -ne $Info -and -not $Info.Couch) }
        default { return ($null -ne $Info -and $Info.Couch) }   # couch
    }
}

# THE list: the games that should have a tile on THIS computer right now.
# Used by PLAY (through Sync-SteamSystem), the setup window's last page, the
# wizard's Machine tab and Get Steam Artwork, so they can never disagree.
function Get-SteamWantedGames {
    param([string]$Root)
    try {
        $state = Get-SteamProfileState -Root $Root
        if (-not $state.Connected) { return @() }
        $cands = @(Get-SteamCandidateGames -Root $Root -Mode $state.Mode)
        if ($state.Mode -eq '') { return $cands }   # set up before 2026-09-25
        $info = Get-SteamGameInfo -Root $Root
        $out = @()
        foreach ($g in $cands) {
            if (@($state.Unpicked) -contains $g.AppId) { continue }
            if ((@($state.Picked) -contains $g.AppId) -or (Test-SteamGameFitsFilter -Info $info[$g.AppId] -Filter $state.Filter)) { $out += $g }
        }
        return $out
    }
    catch { return @() }
}

# ===========================================================================
#  PART FIVE - the tiles RetroBat shows
# ===========================================================================

# Windows will not have these characters in a file name.
function ConvertTo-SafeShortcutName {
    param([string]$Name)
    try {
        $out = $Name
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
            $out = $out.Replace([string]$c, '')
        }
        $out = $out.Trim().TrimEnd('.')
        if ($out -eq '') { $out = 'Steam game' }
        return $out
    }
    catch { return 'Steam game' }
}

# Write one .url shortcut. RetroBat's stock "windows" system reads these and
# hands them to Windows, which hands them to Steam.
function Write-SteamShortcutFile {
    param([string]$Path, [string]$AppId)
    try {
        $lines = @(
            '[InternetShortcut]'
            ('URL=steam://rungameid/' + $AppId)
            'IconIndex=0'
            'Comment=Written by the RetroBat Wizard. Safe to delete.'
        )
        [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.ASCIIEncoding))
        return $true
    }
    catch { return $false }
}

# Is this .url one of ours? Two tests, both must pass, so a shortcut the user
# put there by hand is never touched.
function Test-OurSteamShortcut {
    param([string]$Path)
    try {
        $text = [System.IO.File]::ReadAllText($Path)
        return (($text -match '(?i)steam://rungameid/\d+') -and ($text -match '(?i)RetroBat Wizard'))
    }
    catch { return $false }
}

# The record of which shortcuts we wrote, so a later tidy-up knows what is
# ours even if a file gets edited.
function Get-SteamShortcutIndex {
    param([string]$Root)
    try {
        $f = Join-Path $Root $script:SteamIndexFile
        if (-not (Test-Path -LiteralPath $f)) { return @() }
        return @([System.IO.File]::ReadAllLines($f) | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith(';') })
    }
    catch { return @() }
}

function Set-SteamShortcutIndex {
    param([string]$Root, [string[]]$Names = @())
    try {
        $f = Join-Path $Root $script:SteamIndexFile
        $dir = Split-Path $f -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $head = @(
            '; The Steam game tiles this drive wrote into roms\windows.'
            '; Rebuilt every time Connect Steam or PLAY runs. Safe to delete:'
            '; the next run works it out again from the games on the drive.'
            ''
        )
        [System.IO.File]::WriteAllLines($f, ($head + $Names), (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

# Move a shortcut out of the way rather than deleting it. Nothing on this
# drive is ever deleted.
function Move-SteamShortcutToParked {
    param([string]$Root, [string]$Path)
    try {
        $dir = Join-Path $Root $script:SteamParkedDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $dest = Join-Path $dir (Split-Path $Path -Leaf)
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
        Move-Item -LiteralPath $Path -Destination $dest -Force
        return $true
    }
    catch { return $false }
}

# ---------------------------------------------------------------------------
#  GAMES DELIBERATELY KEPT OUT
#
#  Some games on the drive should not get a tile even though they are
#  installed and would launch. The ten Jackbox Party Packs are the reason
#  this exists: the free Jackbox Megapicker launches all of them from one
#  place, so ten extra tiles are ten ways to reach the same games badly.
#
#  It is a PATTERN LIST in a plain text file rather than a list of numbers in
#  this script, for two reasons. Steven buys more Jackbox packs, and a
#  pattern catches Pack 11 without anybody editing code. And a future owner
#  can read the file and change it without knowing what PowerShell is.
# ---------------------------------------------------------------------------

$script:SteamHiddenDefault = @(
    '; Steam games to keep OUT of RetroBat, one per line.'
    ';'
    '; These games stay installed and still work from Steam itself. They just'
    '; do not get their own tile in RetroBat.'
    ';'
    '; A * matches anything, so "The Jackbox Party Pack*" catches every pack'
    '; including ones bought later. Capital letters do not matter.'
    ';'
    '; Lines starting with a semicolon are notes and are ignored.'
    ''
    '; The Jackbox Megapicker launches all of these from one tile, so the ten'
    '; individual packs would only be ten worse ways in. The Megapicker itself'
    '; is NOT matched by this line and keeps its tile.'
    'The Jackbox Party Pack*'
)

# Read the hidden list, writing the shipped one the first time. Never throws;
# an unreadable file means nothing is hidden, which is the safe answer because
# it shows too much rather than too little.
function Get-SteamHiddenPatterns {
    param([string]$Root)
    try {
        $f = Join-Path $Root $script:SteamHiddenFile
        if (-not (Test-Path -LiteralPath $f)) {
            $dir = Split-Path $f -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllLines($f, $script:SteamHiddenDefault, (New-Object System.Text.UTF8Encoding($false)))
        }
        $out = @()
        foreach ($line in @([System.IO.File]::ReadAllLines($f))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            $out += $t
        }
        return $out
    }
    catch { return @() }
}

function Test-SteamGameHidden {
    param([string]$Name, [string[]]$Patterns)
    try {
        foreach ($p in $Patterns) {
            if ($p -eq '') { continue }
            if ($Name -like $p) { return $true }
        }
    }
    catch { }
    return $false
}

# Tiles written into roms\windows by the first version of this system get
# moved across to roms\steam. One-way, runs once, silent when there is
# nothing to move.
function Move-SteamShortcutsFromOldSystem {
    param([string]$Root)
    $moved = 0
    try {
        $oldDir = Join-Path $Root $script:SteamOldRomsDir
        $newDir = Join-Path $Root $script:SteamRomsDir
        if (-not (Test-Path -LiteralPath $oldDir)) { return 0 }
        if (-not (Test-Path -LiteralPath $newDir)) {
            New-Item -ItemType Directory -Path $newDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        foreach ($e in @(Get-ChildItem -LiteralPath $oldDir -Filter '*.url' -File -ErrorAction SilentlyContinue)) {
            if (-not (Test-OurSteamShortcut -Path $e.FullName)) { continue }
            $dest = Join-Path $newDir $e.Name
            try {
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $e.FullName -Force -ErrorAction SilentlyContinue }
                else { Move-Item -LiteralPath $e.FullName -Destination $dest -Force }
                $moved++
            }
            catch { }
        }
    }
    catch { return $moved }
    return $moved
}

# ---------------------------------------------------------------------------
#  THE ONE THAT RUNS EVERY LAUNCH.
#
#  Makes roms\windows match this computer's [steam] setting:
#    connected = yes -> one .url per installed game on the drive
#    anything else   -> every one of ours parked, so RetroBat shows nothing
#
#  Returns an object: Wrote, Parked, Shown, Connected, Message.
# ---------------------------------------------------------------------------
function Sync-SteamSystem {
    param([string]$Root)

    $summary = [pscustomobject]@{
        Wrote     = 0
        Parked    = 0
        Shown     = 0
        Hidden    = 0
        Moved     = 0
        Connected = $false
        Message   = ''
    }

    try {
        $romsDir = Join-Path $Root $script:SteamRomsDir
        if (-not (Test-Path -LiteralPath $romsDir)) {
            New-Item -ItemType Directory -Path $romsDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $summary.Moved = Move-SteamShortcutsFromOldSystem -Root $Root

        $state = Get-SteamProfileState -Root $Root
        $summary.Connected = $state.Connected

        $existing = @(Get-ChildItem -LiteralPath $romsDir -Filter '*.url' -File -ErrorAction SilentlyContinue)

        if (-not $state.Connected) {
            $oldDir = Join-Path $Root $script:SteamOldRomsDir
            if (Test-Path -LiteralPath $oldDir) {
                foreach ($e in @(Get-ChildItem -LiteralPath $oldDir -Filter '*.url' -File -ErrorAction SilentlyContinue)) {
                    if (Test-OurSteamShortcut -Path $e.FullName) {
                        if (Move-SteamShortcutToParked -Root $Root -Path $e.FullName) { $summary.Parked++ }
                    }
                }
            }
            foreach ($e in $existing) {
                if (Test-OurSteamShortcut -Path $e.FullName) {
                    if (Move-SteamShortcutToParked -Root $Root -Path $e.FullName) { $summary.Parked++ }
                }
            }
            [void](Set-SteamShortcutIndex -Root $Root -Names @())
            $summary.Message = 'Steam is not connected on this computer, so no Steam games are shown.'
            return $summary
        }

        # Which games, for whom, is decided in one place (Get-SteamWantedGames)
        # so this, the setup window and the artwork fetcher never disagree.
        $games  = @(Get-SteamWantedGames -Root $Root)
        $summary.Hidden = @(Get-SteamCandidateGames -Root $Root -Mode $state.Mode).Count - $games.Count

        # Work out every file we want BEFORE touching anything, so the parked
        # folder can be emptied first. Writing first would make every un-park a
        # no-op and leave parked copies lying about forever.
        $wantedFiles = @()
        foreach ($g in $games) {
            $wantedFiles += ((ConvertTo-SafeShortcutName -Name $g.Name) + '.url')
        }

        # Bring a parked one back when its game is installed again.
        $parkedDir = Join-Path $Root $script:SteamParkedDir
        if (Test-Path -LiteralPath $parkedDir) {
            foreach ($p in @(Get-ChildItem -LiteralPath $parkedDir -Filter '*.url' -File -ErrorAction SilentlyContinue)) {
                if ($wantedFiles -contains $p.Name) {
                    $dest = Join-Path $romsDir $p.Name
                    if (-not (Test-Path -LiteralPath $dest)) {
                        try { Move-Item -LiteralPath $p.FullName -Destination $dest -Force } catch { }
                    }
                }
            }
        }

        foreach ($g in $games) {
            $file = (ConvertTo-SafeShortcutName -Name $g.Name) + '.url'
            $full = Join-Path $romsDir $file

            $needsWriting = $true
            if (Test-Path -LiteralPath $full) {
                try {
                    $t = [System.IO.File]::ReadAllText($full)
                    if ($t -match ('(?i)steam://rungameid/' + [regex]::Escape($g.AppId) + '(\D|$)')) {
                        $needsWriting = $false
                    }
                }
                catch { }
            }

            if ($needsWriting) {
                if (Write-SteamShortcutFile -Path $full -AppId $g.AppId) { $summary.Wrote++ }
            }
        }

        # Park anything of ours that is no longer wanted - a game uninstalled,
        # or renamed by Steam.
        foreach ($e in @(Get-ChildItem -LiteralPath $romsDir -Filter '*.url' -File -ErrorAction SilentlyContinue)) {
            if ($wantedFiles -contains $e.Name) { continue }
            if (Test-OurSteamShortcut -Path $e.FullName) {
                if (Move-SteamShortcutToParked -Root $Root -Path $e.FullName) { $summary.Parked++ }
            }
        }

        [void](Set-SteamShortcutIndex -Root $Root -Names $wantedFiles)
        $summary.Shown = $wantedFiles.Count
        $summary.Message = ('{0} Steam game(s) showing in RetroBat.' -f $wantedFiles.Count)
        if ($summary.Hidden -gt 0) {
            $summary.Message += (' {0} more downloaded but not chosen for this computer.' -f $summary.Hidden)
        }
        return $summary
    }
    catch {
        $summary.Message = 'Could not sync the Steam system: ' + $_.Exception.Message
        return $summary
    }
}

# ===========================================================================
#  PART SIX - taking it all back off a computer
# ===========================================================================

# Undo, in whatever combination was asked for. Every part is independent and
# every part is safe to run when it was never done in the first place.
# Returns an object: Steps (a list of what happened), Ok.
function Disconnect-Steam {
    param(
        [string]$Root,
        [switch]$RestoreLibraries,
        [switch]$LogOut,
        [switch]$UninstallSteam
    )

    $steps = @()
    $ok    = $true

    try {
        $steamRoot = Get-SteamRootOnComputer -Root $Root
        $library   = Get-SteamDriveLibrary -Root $Root

        # 1. The tiles always go, whatever else was ticked.
        [void](Set-SteamProfileState -Root $Root -Connected $false -Library '' -Account '')
        $sync = Sync-SteamSystem -Root $Root
        $steps += ('Steam tiles removed from RetroBat on this computer ({0} parked).' -f $sync.Parked)

        if ($RestoreLibraries -or $LogOut -or $UninstallSteam) {
            if (Test-SteamRunning) {
                if (Stop-SteamClient -Root $Root) {
                    $steps += 'Closed Steam.'
                }
                else {
                    $steps += 'Could not close Steam, so the rest was not attempted.'
                    return [pscustomobject]@{ Steps = $steps; Ok = $false }
                }
            }
        }

        if ($RestoreLibraries) {
            if ($steamRoot -eq '') {
                $steps += 'Steam is not installed on this computer, so there was no library list to change.'
            }
            else {
                $r = Remove-SteamLibraryFolder -Root $Root -SteamRoot $steamRoot -LibraryPath $library
                $steps += $r.Message
                if (-not $r.Ok) { $ok = $false }
            }
        }

        if ($LogOut) {
            try {
                Set-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'AutoLoginUser' -Value '' -ErrorAction SilentlyContinue
                Set-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'RememberPassword' -Value 0 -Type DWord -ErrorAction SilentlyContinue
                $steps += 'Signed this account out of Steam. The next start of Steam asks for a login.'
            }
            catch {
                $steps += 'Could not sign the account out automatically. Do it from Steam''s own menu.'
                $ok = $false
            }
        }

        if ($UninstallSteam) {
            $un = ''
            if ($steamRoot -ne '') {
                $c = Join-Path $steamRoot 'uninstall.exe'
                if (Test-Path -LiteralPath $c) { $un = $c }
            }
            if ($un -ne '') {
                try {
                    Start-Process -FilePath $un -ErrorAction SilentlyContinue | Out-Null
                    $steps += 'Started Steam''s own uninstaller. Follow its window to finish.'
                }
                catch {
                    $steps += 'Could not start Steam''s uninstaller.'
                    $ok = $false
                }
            }
            else {
                $steps += 'Could not find Steam''s uninstaller. Remove Steam from Windows Settings instead.'
                $ok = $false
            }
        }
    }
    catch {
        $steps += 'Something went wrong: ' + $_.Exception.Message
        $ok = $false
    }

    return [pscustomobject]@{ Steps = $steps; Ok = $ok }
}
