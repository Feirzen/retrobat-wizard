<#
    ProfileEngine.ps1
    ---------------------------------------------------------------------------
    The machine profile system: works out which computer the drive is plugged
    into, which graphics card it has, and which settings that machine should
    get. Three layers, each beating the one before it:

        1. TIER          machine\tiers\low|medium|high.ini   (card strength)
        2. BRAND RULES   machine\rules\vendor-rules.ini      (card brand)
        3. OVERRIDES     machine\machines\<PC>.ini           (this PC only)

    THIS FILE IS NOT RUN ON ITS OWN. It only defines functions, and is loaded
    ("dot-sourced") by:
        Apply-Settings.ps1        - applies the merged result for real
        Show-MachineProfile.ps1   - shows it without changing anything

    On a computer the drive has never seen, Resolve-MachineProfile detects the
    GPU, picks a tier from machine\rules\gpu-table.txt, and creates that
    machine's profile file automatically. Plug and play - nothing to set up.

    RULES HONOURED HERE (learned the hard way, see the customization record):
      - no drive letters anywhere; everything is derived from -Root
      - no $PSScriptRoot inside a param() block
      - written for Windows PowerShell 5.1 (no PowerShell 7-only syntax)
#>

Set-StrictMode -Off

# --- read a simple .ini file into sections of key = value ------------------
# Returns an ordered dictionary: section name -> ordered dictionary of keys.
# Understands ; and # comments (whole-line and trailing) and ignores blanks.
function Read-ProfileIni {
    param([string]$Path)

    $sections = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $sections }

    $current = $null
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }

        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $name = $line.Substring(1, $line.Length - 2).Trim()
            if (-not $sections.Contains($name)) { $sections[$name] = [ordered]@{} }
            $current = $name
            continue
        }

        $eq = $line.IndexOf('=')
        if ($eq -lt 1 -or $null -eq $current) { continue }

        $key   = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()

        # strip a trailing comment:  value = 3   ; why
        $semi = $value.IndexOf(';')
        if ($semi -ge 0) { $value = $value.Substring(0, $semi).Trim() }
        $hash = $value.IndexOf('#')
        if ($hash -ge 0) { $value = $value.Substring(0, $hash).Trim() }

        if ($key -ne '') { ($sections[$current])[$key] = $value }
    }
    return $sections
}

# --- which graphics card is in this computer -------------------------------
# Asks Windows directly; never asks the user. On a laptop with two GPUs the
# real card outranks the built-in Intel/AMD one, because that is the one the
# emulators will render on.
function Get-GpuName {
    try {
        $adapters = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                      Where-Object { $_.Name })

        # Prefer real PCI graphics devices over virtual/USB display adapters.
        $pci = @($adapters | Where-Object { $_.PNPDeviceID -like 'PCI\*' })
        if ($pci.Count -gt 0) { $adapters = $pci }
        if ($adapters.Count -eq 0) { return $null }

        $best = $adapters | Sort-Object -Descending {
            $n = $_.Name
            if     ($n -match '(?i)nvidia|geforce|quadro|\brtx\b|\bgtx\b') { 3 }
            elseif ($n -match '(?i)\bamd\b|radeon')                        { 2 }
            elseif ($n -match '(?i)intel')                                 { 1 }
            else                                                           { 0 }
        } | Select-Object -First 1
        return $best.Name
    }
    catch { return $null }
}

# --- which brand a card name belongs to ------------------------------------
function Get-GpuVendor {
    param([string]$GpuName)
    if ([string]::IsNullOrEmpty($GpuName))                                { return 'unknown' }
    if ($GpuName -match '(?i)nvidia|geforce|quadro|\brtx\b|\bgtx\b')      { return 'nvidia'  }
    if ($GpuName -match '(?i)\bamd\b|radeon|firepro')                     { return 'amd'     }
    if ($GpuName -match '(?i)intel|\barc\b|\biris\b|uhd graphics')        { return 'intel'   }
    return 'unknown'
}

# --- pick a tier for a card ------------------------------------------------
# First the lookup table (first matching line wins), then the generation
# guesser for cards the table has never heard of, then medium as the
# middle-of-the-road default. Returns an object with Tier and Source.
function Get-GpuTierInfo {
    param([string]$GpuName, [string]$TablePath)

    if (-not [string]::IsNullOrEmpty($GpuName) -and (Test-Path -LiteralPath $TablePath)) {
        foreach ($rawLine in [System.IO.File]::ReadAllLines($TablePath)) {
            $line = $rawLine.Trim()
            if ($line -eq '' -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
            $parts = $line.Split('|')
            if ($parts.Count -ne 2) { continue }
            $pattern = $parts[0].Trim()
            $tier    = $parts[1].Trim().ToLower()
            if ($tier -notin @('low','medium','high')) { continue }
            if ($GpuName -like $pattern) {
                return New-Object psobject -Property @{ Tier = $tier; Source = "gpu-table match '$pattern'" }
            }
        }
    }

    # Generation guesser: the table will go stale as new cards come out, so
    # read the model number and land a newer card sensibly instead of
    # dropping it to Low just because it is unrecognised.
    if (-not [string]::IsNullOrEmpty($GpuName)) {
        $n = $GpuName
        if ($n -match '(?i)\brtx\b') {
            return New-Object psobject -Property @{ Tier = 'high'; Source = 'guessed: any RTX-class card' }
        }
        if ($n -match '(?i)\bgtx\s*(\d{3,4})\b') {
            $model = [int]$Matches[1]
            if (($model % 100) -ge 70) {
                return New-Object psobject -Property @{ Tier = 'high'; Source = "guessed from GTX model $model" }
            }
            return New-Object psobject -Property @{ Tier = 'medium'; Source = "guessed from GTX model $model" }
        }
        if ($n -match '(?i)\brx\s*(\d{3,4})\b') {
            $model = [int]$Matches[1]
            if ($model -ge 5000 -and (($model % 1000) -ge 600)) {
                return New-Object psobject -Property @{ Tier = 'high'; Source = "guessed from RX model $model" }
            }
            return New-Object psobject -Property @{ Tier = 'medium'; Source = "guessed from RX model $model" }
        }
        if ($n -match '(?i)iris|uhd|hd graphics|\bvega\b') {
            return New-Object psobject -Property @{ Tier = 'low'; Source = 'guessed: built-in graphics' }
        }
    }

    return New-Object psobject -Property @{ Tier = 'medium'; Source = 'default (card not recognised)' }
}

# --- the main event: resolve this machine's merged settings ----------------
# Returns an object:
#   .Ok          $true if a usable result came back
#   .Machine     this computer's name
#   .ProfileName the profile's display name
#   .ProfileFile full path of the machine's .ini
#   .Created     $true if the profile was created on this run (new computer)
#   .Gpu / .Vendor / .Tier / .TierSource
#   .Settings    ordered dictionary of "console.setting" = "value", merged
#   .Origin      dictionary "console.setting" -> tier|vendor|override
#   .Messages    lines worth showing to a person
# -NoWrite: never touch the disk (used by Show My Machine).
function Resolve-MachineProfile {
    param(
        [string]$Root,
        [switch]$NoWrite,
        [string]$MachineNameOverride = '',
        [string]$GpuNameOverride = ''
    )

    $messages    = New-Object System.Collections.Generic.List[string]
    $profilesDir = Join-Path $Root '_ClaudeWorkspace\machine'
    $tiersDir    = Join-Path $profilesDir 'tiers'
    $rulesDir    = Join-Path $profilesDir 'rules'
    $machinesDir = Join-Path $profilesDir 'machines'

    $result = New-Object psobject -Property @{
        Ok = $false; Machine = ''; ProfileName = ''; ProfileFile = ''
        Created = $false; Gpu = ''; Vendor = 'unknown'; Tier = 'medium'
        TierSource = ''; Settings = [ordered]@{}; Origin = @{}
        ConsoleTiers = @{}
        # Settings for ONE game rather than a whole console. Read from the
        # profile's [game-settings] section - see Apply-Settings.ps1, which
        # is what turns them into real entries in es_settings.cfg.
        GameSettings = [ordered]@{}
        Messages = $messages
        # Set when machine\pinned.txt is making this drive run as a profile
        # that is not this computer's own. See Get-PinnedProfile below.
        Pinned = $false; PinnedFrom = ''
    }

    if (-not (Test-Path -LiteralPath $tiersDir)) {
        $messages.Add("machine\tiers not found - the machine settings are not installed, so only the hand-kept settings list applies.")
        return $result
    }

    $machineName = $MachineNameOverride
    if ([string]::IsNullOrEmpty($machineName)) { $machineName = [string]$env:COMPUTERNAME }
    if ([string]::IsNullOrEmpty($machineName)) { $machineName = 'UNKNOWN-PC' }
    $result.Machine = $machineName

    $gpuName = $GpuNameOverride
    if ([string]::IsNullOrEmpty($gpuName)) { $gpuName = Get-GpuName }

    # --- find the profile file ----------------------------------------------
    #  Normally that means "this computer's own", matched on the machine name.
    #  But machine\pinned.txt can name a profile to use INSTEAD, on whatever
    #  computer the drive is plugged into. That is what the Machine tab's
    #  "Use this one" button writes.
    #
    #  The pin wins, and the machine name is still reported honestly as THIS
    #  computer's - so nothing downstream starts believing it is a different
    #  PC, and the wrong-machine warning does not fire on a choice that was
    #  made deliberately.
    $machineIni  = $null
    $machineFile = $null

    $pinned = Get-PinnedProfile -Root $Root
    if ($pinned -ne '' -and (Test-Path -LiteralPath $machinesDir)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $machinesDir -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
            $ini = Read-ProfileIni $file.FullName
            $nm = $file.BaseName
            if ($ini.Contains('profile') -and ($ini['profile']).Contains('name') -and ($ini['profile'])['name']) {
                $nm = [string](($ini['profile'])['name'])
            }
            if ($nm -ieq $pinned -or $file.BaseName -ieq $pinned) {
                $machineIni        = $ini
                $machineFile       = $file.FullName
                $result.Pinned     = $true
                $result.PinnedFrom = $nm
                $messages.Add("Running as the '$nm' machine because it was chosen on the Machine tab. This computer is $machineName.")
                break
            }
        }
        if (-not $result.Pinned) {
            $messages.Add("machine\pinned.txt names '$pinned', which no profile matches - ignoring it and using this computer's own.")
        }
    }

    if ($null -eq $machineIni -and (Test-Path -LiteralPath $machinesDir)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $machinesDir -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
            $ini = Read-ProfileIni $file.FullName
            $prof = $null
            if ($ini.Contains('profile')) { $prof = $ini['profile'] }
            $entryMachine = ''
            if ($prof -and $prof.Contains('machine')) { $entryMachine = [string]$prof['machine'] }
            if ($entryMachine -ieq $machineName -or $file.BaseName -ieq $machineName) {
                $machineIni  = $ini
                $machineFile = $file.FullName
                break
            }
        }
    }

    if ($null -eq $machineIni) {
        # --- new computer: detect, pick a tier, create the profile ---------
        $tierInfo = Get-GpuTierInfo -GpuName $gpuName -TablePath (Join-Path $rulesDir 'gpu-table.txt')
        $gpuShown = $gpuName
        if ([string]::IsNullOrEmpty($gpuShown)) { $gpuShown = 'unknown graphics card' }

        $messages.Add("NEW COMPUTER: $machineName with $gpuShown.")
        $messages.Add("Picked the $(($tierInfo.Tier).ToUpper()) tier ($($tierInfo.Source)).")

        $machineFile = Join-Path $machinesDir ($machineName + '.ini')
        $newLines = @(
            "; Machine profile: $machineName"
            "; Created automatically on first run, $(Get-Date -Format 'yyyy-MM-dd HH:mm')."
            "; Only differences from the tier live here - see machine\README.txt."
            ""
            "[profile]"
            "name    = $machineName"
            "machine = $machineName"
            "gpu     = $gpuShown"
            "tier    = $($tierInfo.Tier)"
            ""
            "[console-tiers]"
            "; One console can run at a different tier from the rest of the machine."
            "; Use this first when a single emulator misbehaves - it is one line, and"
            "; the console keeps improving whenever that tier file improves."
            ";   example:  wii = low"
            ""
            "[overrides]"
            "; Add lines here to pin ONE setting, when a whole tier is the wrong tool."
            ";   example:  3ds.azahar_resolution_factor = 2"
        )
        if (-not $NoWrite) {
            if (-not (Test-Path -LiteralPath $machinesDir)) {
                New-Item -ItemType Directory -Path $machinesDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllLines($machineFile, $newLines, (New-Object System.Text.UTF8Encoding($false)))
            $messages.Add("Profile saved: _ClaudeWorkspace\machine\machines\$machineName.ini")
            $messages.Add("Wrong guess? Change its 'tier =' line and run Apply My Settings again.")
        }
        else {
            $messages.Add("(read-only run - the profile file was NOT created yet)")
        }

        $result.Created     = $true
        $result.ProfileName = $machineName
        $result.Tier        = $tierInfo.Tier
        $result.TierSource  = $tierInfo.Source
        $result.Gpu         = $gpuShown
        $machineIni         = [ordered]@{ 'overrides' = [ordered]@{} }
    }
    else {
        $prof = $machineIni['profile']
        $result.ProfileName = $machineName
        if ($prof -and $prof.Contains('name') -and $prof['name']) { $result.ProfileName = [string]$prof['name'] }

        $tier = ''
        if ($prof -and $prof.Contains('tier')) { $tier = ([string]$prof['tier']).ToLower() }
        if ($tier -notin @('low','medium','high')) {
            $messages.Add("The profile's tier line says '$tier', which is not low, medium or high - using medium.")
            $tier = 'medium'
        }
        $result.Tier       = $tier
        $result.TierSource = "set in this machine's profile file"

        if ($result.Pinned) {
            if ($prof -and $prof.Contains('name') -and $prof['name']) { $result.ProfileName = [string]$prof['name'] }
            else { $result.ProfileName = [System.IO.Path]::GetFileNameWithoutExtension($machineFile) }
        }

        $storedGpu = ''
        if ($prof -and $prof.Contains('gpu')) { $storedGpu = [string]$prof['gpu'] }
        $result.Gpu = $storedGpu
        if (-not [string]::IsNullOrEmpty($gpuName)) {
            $result.Gpu = $gpuName
            # A PINNED profile naming another card is the whole point of
            # pinning it, so that is not worth a warning. On this computer's
            # OWN profile it means the card really changed, which is.
            if (-not $result.Pinned -and -not [string]::IsNullOrEmpty($storedGpu) -and ($storedGpu -ine $gpuName)) {
                $messages.Add("Note: this profile was made with '$storedGpu' but the computer now reports '$gpuName'. If the graphics card really changed, consider changing the tier line in the profile.")
            }
        }
    }

    $result.ProfileFile = $machineFile
    $result.Vendor      = Get-GpuVendor $result.Gpu

    # --- layer 1: the tier --------------------------------------------------
    $tierPath = Join-Path $tiersDir ($result.Tier + '.ini')
    $tierIni  = Read-ProfileIni $tierPath
    if ($tierIni.Count -eq 0) {
        $messages.Add("ERROR: could not read $tierPath - the machine settings are skipped this run.")
        return $result
    }
    foreach ($system in $tierIni.Keys) {
        foreach ($key in ($tierIni[$system]).Keys) {
            $full = "$system.$key"
            $result.Settings[$full] = [string](($tierIni[$system])[$key])
            $result.Origin[$full]   = 'tier'
        }
    }

    # --- layer 1b: per-console tier -----------------------------------------
    # A machine can run one console at a different tier from the rest, which is
    # the common real case: the computer is fine on Medium but one emulator
    # stutters. Pinning half a dozen individual settings to fix that is the hard
    # way round. "wii = low" says the same thing in one line, stays readable,
    # and keeps improving whenever the Low tier improves.
    #
    # It sits BEFORE the brand rules on purpose: which graphics backend a card
    # wants is a question of brand, not of strength, so a vendor rule must still
    # win over a per-console tier.
    if ($machineIni.Contains('console-tiers')) {
        foreach ($console in ($machineIni['console-tiers']).Keys) {
            $wanted = ([string](($machineIni['console-tiers'])[$console])).ToLower()
            if ($wanted -notin @('low', 'medium', 'high')) {
                $messages.Add("The console-tiers line for '$console' says '$wanted', which is not low, medium or high - ignoring it.")
                continue
            }
            $cIni = Read-ProfileIni (Join-Path $tiersDir ($wanted + '.ini'))
            if (-not $cIni.Contains($console)) {
                $messages.Add("The console-tiers line names '$console', which the tier files do not know about - ignoring it.")
                continue
            }
            $result.ConsoleTiers[$console] = $wanted
            if ($wanted -eq $result.Tier) { continue }   # same as the machine, nothing to change
            foreach ($key in ($cIni[$console]).Keys) {
                $full = "$console.$key"
                $result.Settings[$full] = [string](($cIni[$console])[$key])
                $result.Origin[$full]   = 'console-tier'
            }
        }
    }

    # --- layer 2: brand rules ----------------------------------------------
    $vendorIni = Read-ProfileIni (Join-Path $rulesDir 'vendor-rules.ini')
    if ($vendorIni.Contains($result.Vendor)) {
        foreach ($key in ($vendorIni[$result.Vendor]).Keys) {
            $result.Settings[$key] = [string](($vendorIni[$result.Vendor])[$key])
            $result.Origin[$key]   = 'vendor'
        }
    }

    # --- layer 3: this machine's own pins ----------------------------------
    if ($machineIni.Contains('overrides')) {
        foreach ($key in ($machineIni['overrides']).Keys) {
            $result.Settings[$key] = [string](($machineIni['overrides'])[$key])
            $result.Origin[$key]   = 'override'
        }
    }

    # --- and settings for ONE game -----------------------------------------
    #  Kept apart from everything above on purpose. The layers are a merge:
    #  a tier value, then a console tier, then a brand rule, then a pin, and
    #  the last one wins. A per-game setting is not part of that argument at
    #  all - it names one game, nothing else can name that game, so there is
    #  nothing to merge and no order to get right.
    #
    #  The key is written the way it reads:
    #      wiiu[Mario Kart 8 (USA) (En,Fr,Es) (Rev 5).wux].use_wiimotes = 4
    #  and Apply-Settings turns it into the shape EmulationStation stores.
    #
    #  TWO PLACES, and the difference is worth keeping straight:
    #    machine\game-settings.ini   the whole drive. For settings that are
    #                                 about the ROOM - which controller a
    #                                 game expects is the same answer at home
    #                                 and at a friend's house
    #    the profile's own section    for settings about how hard THIS
    #                                 computer has to work, which stop
    #                                 applying when another profile is chosen
    #  The profile wins, so one machine can disagree about one game without
    #  editing the shared file.
    $sharedGs = Read-ProfileIni (Join-Path $profilesDir 'game-settings.ini')
    if ($sharedGs.Contains('game-settings')) {
        foreach ($key in ($sharedGs['game-settings']).Keys) {
            $result.GameSettings[$key] = [string](($sharedGs['game-settings'])[$key])
        }
    }
    if ($machineIni.Contains('game-settings')) {
        foreach ($key in ($machineIni['game-settings']).Keys) {
            $result.GameSettings[$key] = [string](($machineIni['game-settings'])[$key])
        }
    }

    $result.Ok = $true
    return $result
}

# --- list the consoles the tier files cover --------------------------------
# Used by the Setup Wizard's Machine tab so the list of consoles comes from
# the tier files themselves rather than being hardcoded in two places.
function Get-ProfileConsoles {
    param([string]$Root)
    $tierPath = Join-Path $Root '_ClaudeWorkspace\machine\tiers\medium.ini'
    $ini = Read-ProfileIni $tierPath
    return @($ini.Keys)
}

# --- record which profile is applied right now -----------------------------
# Written by Apply-Settings after a successful apply. Read by people, and
# later by the health check.
function Write-ActiveProfile {
    param([string]$Root, $MachineProfile)

    if ($null -eq $MachineProfile -or -not $MachineProfile.Ok) { return }
    try {
        $lines = @(
            "profile = $($MachineProfile.ProfileName)"
            "machine = $($MachineProfile.Machine)"
            "gpu     = $($MachineProfile.Gpu)"
            "tier    = $($MachineProfile.Tier)"
            "applied = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )
        # Per-console tiers go in as COMMENTS on purpose. active.txt is read as
        # plain "key = value" by the wizard and by people, and a line saying
        # "wii = low" next to "tier = medium" reads like a second machine tier.
        if ($MachineProfile.ConsoleTiers -and $MachineProfile.ConsoleTiers.Count -gt 0) {
            $lines += ""
            $lines += "; consoles deliberately running at a different tier:"
            foreach ($c in ($MachineProfile.ConsoleTiers.Keys | Sort-Object)) {
                $lines += (";   {0,-9} {1}" -f $c, $MachineProfile.ConsoleTiers[$c])
            }
        }
        $activePath = Join-Path $Root '_ClaudeWorkspace\machine\active.txt'
        [System.IO.File]::WriteAllLines($activePath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch { }
}


# ===========================================================================
#  PROFILES AS THINGS YOU CAN CHOOSE BETWEEN          (added 2026-09-18)
# ===========================================================================
#  Until now a profile was something that happened TO you: the drive looked
#  at the computer's name, found or made the matching file, and that was
#  that. Which is right almost always, and wrong exactly when you want to
#  try somebody else's settings, or keep two of your own and swap between
#  them.
#
#  machine\pinned.txt is the whole mechanism. One line:
#
#      profile = ZBOOK
#
#  When it is there, Resolve-MachineProfile uses that profile on whatever
#  computer the drive is plugged into. When it is not, nothing changes and
#  the drive behaves exactly as it always has. Delete the file by hand and
#  you are back to automatic.
#
#  IT IS PER-DRIVE, NOT PER-COMPUTER, and that is deliberate: it is the
#  drive that is being told what to be. Copy-ToNewDrive takes it along; the
#  next computer gets the same answer, which is the point of choosing.
# ---------------------------------------------------------------------------
$script:PinnedFileName = 'pinned.txt'

function Get-PinnedProfileFile {
    param([string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { return '' }
    return (Join-Path $Root ('_ClaudeWorkspace\machine\' + $script:PinnedFileName))
}

# The profile name the drive has been told to run as, or '' for automatic.
# Never throws: an unreadable file means automatic, which is the safe answer.
function Get-PinnedProfile {
    param([string]$Root)
    try {
        $p = Get-PinnedProfileFile -Root $Root
        if ($p -eq '' -or -not (Test-Path -LiteralPath $p)) { return '' }
        foreach ($line in @([System.IO.File]::ReadAllLines($p))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            if ($t -match '^\s*profile\s*=\s*(.+)$') { return $Matches[1].Trim() }
        }
    }
    catch { }
    return ''
}

# Write the pin, or clear it with an empty name. Returns $true if it worked.
# Clearing MOVES the file into _SAFE TO DELETE rather than deleting it,
# because nothing on this drive is ever deleted.
function Set-PinnedProfile {
    param([string]$Root, [string]$Name = '')
    try {
        $p = Get-PinnedProfileFile -Root $Root
        if ($p -eq '') { return $false }
        $dir = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        if ([string]::IsNullOrWhiteSpace($Name)) {
            if (Test-Path -LiteralPath $p) {
                $bin = Join-Path $Root '_ClaudeWorkspace\_SAFE TO DELETE'
                if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
                $dest = Join-Path $bin ('pinned_{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
                Move-Item -LiteralPath $p -Destination $dest -Force
            }
            return $true
        }

        $lines = @(
            '; Which profile this DRIVE runs as, whatever computer it is plugged into.'
            '; Written by the Setup Wizard''s Machine tab. Delete this file and the'
            '; drive goes back to picking the profile that matches the computer.'
            ''
            "profile = $Name"
        )
        [System.IO.File]::WriteAllLines($p, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}

# ---------------------------------------------------------------------------
#  Every profile on the drive, as things with names rather than files.
#  Returns an array of psobjects: File, Name, Machine, Tier, Gpu, Icon,
#  IsThisComputer, IsInUse. Sorted by name. Never throws.
# ---------------------------------------------------------------------------
function Get-ProfileList {
    param([string]$Root)

    $out = @()
    try {
        $machinesDir = Join-Path $Root '_ClaudeWorkspace\machine\machines'
        if (-not (Test-Path -LiteralPath $machinesDir)) { return $out }

        $thisMachine = [string]$env:COMPUTERNAME
        $pinned      = Get-PinnedProfile -Root $Root

        foreach ($f in @(Get-ChildItem -LiteralPath $machinesDir -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
            $ini  = Read-ProfileIni $f.FullName
            $prof = $null
            if ($ini.Contains('profile')) { $prof = $ini['profile'] }

            # Read out flat rather than through a helper. A function defined
            # inside a loop looks tidier and reaches back into the caller's
            # variables to work, which is the kind of quiet coupling this
            # project keeps getting bitten by.
            $name = ''; $mach = ''; $tier = ''; $gpu = ''; $icon = ''
            if ($prof) {
                if ($prof.Contains('name'))    { $name = [string]$prof['name'] }
                if ($prof.Contains('machine')) { $mach = [string]$prof['machine'] }
                if ($prof.Contains('tier'))    { $tier = ([string]$prof['tier']).ToLower() }
                if ($prof.Contains('gpu'))     { $gpu  = [string]$prof['gpu'] }
                if ($prof.Contains('icon'))    { $icon = [string]$prof['icon'] }
            }
            if ($name -eq '') { $name = $f.BaseName }
            if ($tier -eq '') { $tier = '?' }

            $out += (New-Object psobject -Property @{
                File           = $f.FullName
                Name           = $name
                Machine        = $mach
                Tier           = $tier
                Gpu            = $gpu
                Icon           = (Get-ProfileIcon -Name $name -Stored $icon)
                IsThisComputer = ($mach -ieq $thisMachine -or $f.BaseName -ieq $thisMachine)
                IsInUse        = ($pinned -ne '' -and ($name -ieq $pinned -or $f.BaseName -ieq $pinned))
            })
        }
    }
    catch { }
    return @($out | Sort-Object Name)
}

# ---------------------------------------------------------------------------
#  Which little picture a profile wears. An 'icon =' line in the profile
#  wins; without one, the name picks its own, the same one every time, so a
#  list of profiles is visually telling apart without anybody choosing
#  anything. The names match wizard\profile-<icon>.png, and an icon the
#  wizard has no picture for simply shows no picture.
# ---------------------------------------------------------------------------
#  The pool a name picks from ON ITS OWN is the four controllers, and stays
#  the four controllers: they are one visual family, so a list of profiles
#  nobody has touched looks deliberate rather than like a jumble sale.
$script:ProfileIcons = @('gamecube', 'n64', 'snes', 'nes')

#  Everything that can be CHOSEN, which is a different question. Each name
#  is a wizard\profile-<name>.png; a name with no picture simply shows no
#  picture, like every other picture in this window. Add a file, add a line.
$script:ProfileIconChoices = @(
    'nes', 'snes', 'n64', 'gamecube', 'wiimote',
    'gameboy', 'gba', 'ds', 'switch',
    'pc', 'laptop', 'monitor', 'brokenlaptop'
)

function Get-ProfileIcon {
    param([string]$Name = '', [string]$Stored = '')

    $s = ([string]$Stored).Trim().ToLower()
    if ($s -ne '') { return $s }

    # A plain sum of the letters. Not a hash worth the name, and it does not
    # need to be: it only has to be the same answer every time for the same
    # profile, and to spread four ways.
    $sum = 0
    foreach ($c in ([string]$Name).ToCharArray()) { $sum += [int]$c }
    return $script:ProfileIcons[$sum % $script:ProfileIcons.Count]
}

# ---------------------------------------------------------------------------
#  Make a brand-new empty profile. Deliberately a COPY of the shape
#  Resolve-MachineProfile writes for a new computer, minus the machine line:
#  a profile made by hand is not tied to any computer, which is exactly what
#  makes it worth having.
#
#  Returns the new file's path, or '' if it could not be made. Never
#  overwrites: an existing name is refused rather than replaced.
# ---------------------------------------------------------------------------
function New-BlankProfile {
    param([string]$Root, [string]$Name, [string]$Tier = 'medium')

    try {
        $safe = ConvertTo-ProfileFileName -Name $Name
        if ($safe -eq '') { return '' }
        $machinesDir = Join-Path $Root '_ClaudeWorkspace\machine\machines'
        if (-not (Test-Path -LiteralPath $machinesDir)) {
            New-Item -ItemType Directory -Path $machinesDir -Force | Out-Null
        }
        $file = Join-Path $machinesDir ($safe + '.ini')
        if (Test-Path -LiteralPath $file) { return '' }

        $t = ([string]$Tier).ToLower()
        if ($t -notin @('low','medium','high')) { $t = 'medium' }

        $lines = @(
            "; Profile: $Name"
            "; Made by hand on $(Get-Date -Format 'yyyy-MM-dd HH:mm') from the Machine tab."
            "; It has no 'machine =' line on purpose, so it belongs to no particular"
            "; computer. Choose it with 'Use this one' on the Machine tab."
            ""
            "[profile]"
            "name    = $Name"
            "tier    = $t"
            ""
            "[console-tiers]"
            "; One console can run at a different tier from the rest."
            ";   example:  wii = low"
            ""
            "[overrides]"
            "; Pin ONE setting, when a whole tier is the wrong tool."
            ";   example:  3ds.azahar_resolution_factor = 2"
            ""
            "[game-settings]"
            "; One setting for ONE game. See docs\PER-GAME-SETTINGS.md."
            ";   example:  wiiu[Mario Kart 8 (USA) (En,Fr,Es) (Rev 5).wux].cemu_vsync = 3"
        )
        [System.IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding($false)))
        return $file
    }
    catch { return '' }
}

# Turns a profile name into something Windows will accept as a file name.
function ConvertTo-ProfileFileName {
    param([string]$Name = '')
    $n = [string]$Name
    foreach ($c in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) { $n = $n.Replace($c, '') }
    $n = $n.Trim().Trim('.')
    return $n
}

# ---------------------------------------------------------------------------
#  Rename a profile: the 'name =' line inside it, the file itself, and the
#  pin if it was pointing at the old name. Returns the new path, or ''.
#  Every comment in the file is kept - they are what makes these readable.
# ---------------------------------------------------------------------------
function Rename-ProfileFile {
    param([string]$Root, [string]$File, [string]$NewName)

    try {
        if (-not (Test-Path -LiteralPath $File)) { return '' }
        $safe = ConvertTo-ProfileFileName -Name $NewName
        if ($safe -eq '') { return '' }

        $oldName = [System.IO.Path]::GetFileNameWithoutExtension($File)
        $ini = Read-ProfileIni $File
        if ($ini.Contains('profile') -and ($ini['profile']).Contains('name')) {
            $oldName = [string](($ini['profile'])['name'])
        }

        # EVERY reason to refuse is checked BEFORE anything is written. The
        # first version wrote the new name into the file and only then found
        # that the destination was taken, which left the profile answering to
        # a name that belonged to somebody else - a half-done rename, which is
        # the one outcome this drive never allows. Found by the test suite,
        # not by a person, which is exactly what it is for.
        $dest = Join-Path (Split-Path $File -Parent) ($safe + '.ini')
        if ($dest -ne $File -and (Test-Path -LiteralPath $dest)) { return '' }

        $lines = @([System.IO.File]::ReadAllLines($File))
        $at = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            if ($t -match '^\s*name\s*=') { $at = $i; break }
        }
        if ($at -lt 0) { return '' }

        # Nothing has been written up to here. From here on it all works.
        $lines[$at] = "name    = $NewName"
        [System.IO.File]::WriteAllLines($File, $lines, (New-Object System.Text.UTF8Encoding($false)))
        if ($dest -ne $File) { Move-Item -LiteralPath $File -Destination $dest -Force }

        if ((Get-PinnedProfile -Root $Root) -ieq $oldName) {
            [void](Set-PinnedProfile -Root $Root -Name $NewName)
        }
        return $dest
    }
    catch { return '' }
}


# ---------------------------------------------------------------------------
#  Set (or clear) a profile's chosen picture. Clearing means deleting the
#  'icon =' line, which puts the profile back to the one its name picks by
#  itself - so "no choice" stays a real state rather than becoming a choice
#  that happens to match.
#
#  The line goes in [profile], right after 'name', and every comment in the
#  file is kept. Returns $true if the file now says what was asked.
# ---------------------------------------------------------------------------
function Set-ProfileIcon {
    param([string]$File, [string]$Icon = '')

    try {
        if (-not (Test-Path -LiteralPath $File)) { return $false }
        $want  = ([string]$Icon).Trim().ToLower()
        $lines = @([System.IO.File]::ReadAllLines($File))
        $out   = New-Object System.Collections.Generic.List[string]

        $inProfile = $false
        $done      = $false
        $nameAt    = -1

        foreach ($line in $lines) {
            $t = ([string]$line).Trim()
            if ($t.StartsWith('[') -and $t.EndsWith(']')) {
                # Leaving [profile] without having written it: write it now,
                # so the line cannot end up in the wrong section.
                if ($inProfile -and -not $done -and $want -ne '') {
                    $out.Add("icon    = $want"); $done = $true
                }
                $inProfile = ($t -ieq '[profile]')
                $out.Add($line); continue
            }
            if ($inProfile -and -not ($t.StartsWith(';') -or $t.StartsWith('#')) -and $t -match '^\s*icon\s*=') {
                if ($want -ne '') { $out.Add("icon    = $want"); $done = $true }
                continue          # clearing: the line is simply dropped
            }
            if ($inProfile -and -not ($t.StartsWith(';') -or $t.StartsWith('#')) -and $t -match '^\s*name\s*=') {
                $out.Add($line); $nameAt = $out.Count; continue
            }
            $out.Add($line)
        }
        if ($inProfile -and -not $done -and $want -ne '') { $out.Add("icon    = $want"); $done = $true }

        # No [profile] section at all, which should not happen but must not
        # throw if it does.
        if ($want -ne '' -and -not $done) {
            if ($nameAt -ge 0) { $out.Insert($nameAt, "icon    = $want") }
            else { return $false }
        }

        [System.IO.File]::WriteAllLines($File, $out, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    catch { return $false }
}
