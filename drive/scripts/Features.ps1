<#
    Features.ps1 - the on/off switches, and nothing else.

    FUNCTIONS ONLY. Dot-source it, it never does anything by itself:

        . (Join-Path $PSScriptRoot 'Features.ps1')
        if (Test-Feature $Root 'videovolume') { ... }

    WHY THIS EXISTS
    ---------------
    Every customization on this drive used to be permanently on. That is fine
    for the person who set it up and wrong for anybody it gets handed to, who
    may not want the menus reworded or the videos levelled. The switches live
    in one plain text file, _ClaudeWorkspace\features.ini, which can be edited
    by hand or from the wizard's Features tab.

    THE ONE RULE THAT MATTERS: EVERYTHING FAILS ON.
    -----------------------------------------------
    A missing file, an unreadable file, a key nobody recognises, a value that
    is not on or off - all of them mean ON, which is exactly what this drive
    did before any of this existed. So the worst a broken features.ini can do
    is nothing at all. It can never quietly switch something off, which is the
    only failure that would be hard to notice.

    ASCII ONLY. Windows PowerShell reads a script with no byte-order mark as
    ANSI, so a stray accented character renders as garbage.
#>

# ===========================================================================
#  THE CATALOGUE - the one list of what can be switched
# ===========================================================================
#  Adding a switch means adding an entry here AND teaching the script named
#  in 'scripts' to do both directions. A key in this list that no script
#  honours is a switch that does nothing, which is worse than no switch.
#
#    title    what the tab calls it. Keep it short
#    desc     one line, what it does when it is on
#    off      one line, what happens when it is turned off. Say plainly where
#             turning it off cannot undo what has already been done
#    scripts  which script makes the change real, run by the tab on Apply
#    reverts  $true if switching it off actively undoes what was done, $false
#             if off only means "stop doing it from now on"
#    warn     optional. A heavier warning shown before switching this OFF,
#             for a switch that can cost somebody something. Only 'savebackup'
#             has one, and its wording is deliberately heavier than the rest -
#             do not trim it down to match them
#
#  DELIBERATELY NOT SWITCHABLE: the mid-game savestate quarantine. It is a
#  different job from backing saves up, it has its own button and its own
#  health light, and turning it off would leave savestates loadable again,
#  which changes how games behave rather than what the drive stores.
# ---------------------------------------------------------------------------
function Get-FeatureCatalogue {
    $c = [ordered]@{}

    $c['wiisystemmenu'] = @{
        title   = 'Wii boots through the Wii Menu'
        desc    = 'Wii discs start at the real Wii System Menu, then the game.'
        off     = 'Off boots straight into the game, the way RetroBat does.'
        scripts = @('Fix-Portability.ps1')
        reverts = $true
    }

    $c['launchmenu'] = @{
        title   = 'Ask before a slow launch'
        desc    = 'A confirmation menu on 3DS, Wii U, DS and the ports.'
        off     = 'Off removes it. Those games launch the moment you press A.'
        scripts = @('Apply-Settings.ps1')
        reverts = $true
    }

    $c['rewordedmenus'] = @{
        title   = 'Reworded menus'
        desc    = 'LAUNCH GAME instead of START NEW GAME, and three backup lines.'
        off     = "Off puts RetroBat's own wording back."
        scripts = @('Restore-ProtectedFiles.ps1')
        reverts = $true
    }

    # Renamed and turned the right way round on 2026-09-18. It used to be
    # 'hidedecorations', called "Plain frame for 3DS", and ON meant throw the
    # 3DS frame away. That was the right switch in August, when the 3DS frame
    # straddled the console's hinge and a preview video looked wrong in it.
    # The frame was re-cut on 2026-09-06 so the top screen fills it, and from
    # that day the switch was correct only when switched OFF - a switch whose
    # good setting is 'off' reads as something being disabled, which is the
    # opposite of the truth. Now ON is the good setting and the name says
    # what you get. Get-Features migrates an old features.ini by itself.
    $c['fixed3dsframe'] = @{
        title   = 'Fixed 3DS idle frame'
        desc    = 'The idle screen shows the real 3DS, re-cut so the preview video fills its top screen.'
        off     = "Off uses the plain curved-TV frame instead, and the 3DS frame is moved into archive\decorations-hidden."
        scripts = @('Apply-Settings.ps1')
        reverts = $true
    }

    $c['themecollections'] = @{
        title   = 'Collection artwork'
        desc    = 'Keeps the Zelda and Pokemon artwork, video and colour in the theme.'
        off     = 'Off stops maintaining it. What is already there stays.'
        scripts = @('Restore-CkauBookTheme.ps1')
        reverts = $false
    }

    $c['savebackup'] = @{
        title   = 'Automatic save backup'
        desc    = 'Copies changed game saves into SaveBackups after every game.'
        off     = 'Off stops backing up. What is already kept stays.'
        scripts = @()
        reverts = $false
        warn    = "Turning this off stops your game saves being backed up.`n`nEverything already backed up stays, and you can still put an old save back. But from here on, a save that gets corrupted or overwritten is gone for good.`n`nThis is the only switch here that can cost you something you cannot get back."
    }

    $c['videovolume'] = @{
        title   = 'Even out video volume'
        desc    = 'Re-records game, menu and intro videos so none of them shout.'
        off     = 'Off leaves new videos alone. Levelled ones stay levelled.'
        scripts = @('Fix-VideoVolume.ps1')
        reverts = $false
    }

    $c['scrollsound'] = @{
        title   = 'One scroll sound'
        desc    = 'Every game list scrolls with the same soft Wii U sound.'
        off     = "Off puts the theme's own per-system sounds back."
        scripts = @('Restore-ProtectedFiles.ps1')
        reverts = $true
    }

    $c['unpack3ds'] = @{
        title   = 'Unpack new 3DS roms'
        desc    = 'Extracts any new .7z in roms\3ds so the game appears in the menu.'
        off     = 'Off leaves archives packed. Unpacked games are unaffected.'
        scripts = @('Decompress-3DS.ps1')
        reverts = $false
    }

    return $c
}

# ===========================================================================
#  WHICH PROTECTED FILES BELONG TO A SWITCH
# ===========================================================================
#  Most files in update-restore\ are simply ours and are always put back. A
#  few ARE a feature, and switching that feature off has to put RetroBat's
#  own version back instead, from update-restore-off\.
#
#  This map used to be written out twice, once in Restore-ProtectedFiles.ps1
#  and again in Check-DriveHealth.ps1, with a comment in each asking whoever
#  edited one to remember the other. Two copies of the same list is a list
#  that goes wrong, so it lives here now, beside the catalogue it belongs to.
#
#  Paths are relative to the RetroBat root, exactly as they sit inside
#  update-restore\, and are compared lower-cased.
#
#  A feature with no entry here simply has no protected file, which is true
#  of six of the nine. Adding one is a line here and a copy into both
#  update-restore\ and update-restore-off\ - no script needs editing.
# ---------------------------------------------------------------------------
function Get-FeatureFileMap {
    $m = [ordered]@{}
    $m['rewordedmenus'] = @('emulationstation\resources\locale\en_GB\LC_MESSAGES\emulationstation2.po')
    $m['scrollsound']   = @('emulationstation\.emulationstation\themes\ckau-book\_inc\views\ScrollSound.xml')
    return $m
}

# ===========================================================================
#  PROTECTED FILES THAT ARE NOT MEANT TO BE THERE
# ===========================================================================
#  The map above says: when this feature is OFF, put RetroBat's own copy back
#  instead of ours. This one says a different thing about a different kind of
#  switch: when this feature is ON, the file is deliberately NOT on the drive,
#  so do not put it back and do not report it missing.
#
#  Only 'hidedecorations' works that way, and only since the 3DS frame was
#  re-cut in September 2026. Switched ON, Apply-Settings moves that frame out
#  of system\decorations on purpose. A restore that put it straight back would
#  fight Apply-Settings on every single run, and the Protected files light
#  would read red for the drive doing exactly what it was told - which is the
#  two-scripts-undoing-each-other trap this project has already been bitten by
#  once. Switched OFF, the frame belongs on the drive and is protected like
#  anything else.
#
#  Paths are relative to the RetroBat root and compared lower-cased, the same
#  as the map above.
# ---------------------------------------------------------------------------
#  EACH ENTRY SAYS WHEN IT APPLIES. 'off' means the files are deliberately
#  absent while the feature is switched OFF, 'on' means the other way round.
#  It was a bare list of paths until 2026-09-18, when the only entry in it
#  was turned round: 'fixed3dsframe' switched OFF is what moves the 3DS frame
#  away. Saying which sense each entry has, in the entry, is one word and
#  removes any chance of the two readers of this map disagreeing about it.
function Get-FeatureSkipMap {
    $m = [ordered]@{}
    $m['fixed3dsframe'] = @{
        When  = 'off'
        Paths = @(
            'system\decorations\default_curve_night\systems\3ds.png',
            'system\decorations\default_curve_night\systems\3ds.info'
        )
    }
    return $m
}

# Does this entry's skip apply, given whether the feature is on?
# One place decides, so the restore step and the health check cannot drift.
function Test-FeatureSkipApplies($Entry, [bool]$FeatureOn) {
    $when = 'on'
    if ($null -ne $Entry -and $Entry.Contains('When')) { $when = ([string]$Entry['When']).ToLower() }
    if ($when -eq 'off') { return (-not $FeatureOn) }
    return $FeatureOn
}

# ---------------------------------------------------------------------------
#  Where the file lives. $Root is the RETROBAT root, not the workspace.
# ---------------------------------------------------------------------------
function Get-FeaturesPath([string]$Root) {
    return (Join-Path $Root '_ClaudeWorkspace\features.ini')
}

# ---------------------------------------------------------------------------
#  Read it. Returns an ordered hashtable of every catalogue key to $true or
#  $false, always complete, never $null. Anything it cannot make sense of is
#  left at ON - see the rule at the top.
# ---------------------------------------------------------------------------
function Get-Features([string]$Root) {
    $cat    = Get-FeatureCatalogue
    $result = [ordered]@{}
    foreach ($k in $cat.Keys) { $result[$k] = $true }

    # Set by the loop below the moment a real 'fixed3dsframe' line is seen,
    # so an old 'hidedecorations' line cannot then overrule it whichever
    # order the two appear in.
    $script:sawFixed3ds = $false

    $path = Get-FeaturesPath $Root
    if (-not (Test-Path -LiteralPath $path)) { return $result }

    try {
        # @() matters: a one-line file comes back as a bare string, and
        # indexing a string walks its characters one at a time.
        $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
    }
    catch { return $result }

    foreach ($line in $lines) {
        $t = "$line".Trim()
        if ($t.Length -eq 0) { continue }
        if ($t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t.StartsWith('[')) { continue }

        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }

        $key = $t.Substring(0, $eq).Trim().ToLower()
        $val = $t.Substring($eq + 1).Trim().ToLower()

        # A trailing comment on the same line: off ; because I hate it
        $semi = $val.IndexOf(';')
        if ($semi -ge 0) { $val = $val.Substring(0, $semi).Trim() }

        $off = ($val -in @('off', 'false', 'no', '0'))

        # A features.ini written before 2026-09-18 says 'hidedecorations',
        # which is the same switch the other way up. Honour it rather than
        # ignoring it, or a drive that had deliberately chosen the plain
        # frame would silently get the 3DS one back after an update.
        # An explicit fixed3dsframe line anywhere in the file wins.
        if ($key -eq 'hidedecorations') {
            if (-not $script:sawFixed3ds) { $result['fixed3dsframe'] = $off }
            continue
        }
        if ($key -eq 'fixed3dsframe') { $script:sawFixed3ds = $true }

        if (-not $result.Contains($key)) { continue }

        # Only the words that clearly mean off turn anything off.
        if ($off) { $result[$key] = $false }
        else      { $result[$key] = $true }
    }

    return $result
}

# ---------------------------------------------------------------------------
#  The one every script calls. $true unless the file plainly says otherwise.
# ---------------------------------------------------------------------------
function Test-Feature([string]$Root, [string]$Key) {
    $f = Get-Features $Root
    $k = "$Key".ToLower()
    if (-not $f.Contains($k)) { return $true }
    return [bool]$f[$k]
}

# ---------------------------------------------------------------------------
#  One line for a log or a console listing.
# ---------------------------------------------------------------------------
function Format-FeatureLine([string]$Key, [bool]$On) {
    $cat = Get-FeatureCatalogue
    $title = if ($cat.Contains($Key)) { $cat[$Key].title } else { $Key }
    return ("  [{0}]  {1,-26} {2}" -f $(if ($On) { 'on ' } else { 'OFF' }), $title, $Key)
}

# ---------------------------------------------------------------------------
#  Build the file from scratch, comments and all. Only ever called when there
#  is no file, so it can never overwrite anything somebody wrote.
# ---------------------------------------------------------------------------
function New-FeaturesFile([string]$Root, [hashtable]$Values = $null) {
    $path = Get-FeaturesPath $Root
    if (Test-Path -LiteralPath $path) { return $false }

    $cat = Get-FeatureCatalogue
    $out = New-Object System.Collections.Generic.List[string]

    $out.Add('; ===========================================================================')
    $out.Add(';  WHAT THIS DRIVE DOES FOR YOU - the on/off switches')
    $out.Add('; ===========================================================================')
    $out.Add(';  Every line below is one thing this drive does that plain RetroBat does')
    $out.Add(';  not. Write on or off after the = sign, save the file, then run')
    $out.Add(';  RUN THIS AFTER AN UPDATE.bat to make the change real - or use the')
    $out.Add(';  Features tab in the Setup Wizard, which does both for you.')
    $out.Add(';')
    $out.Add(';  Anything this file cannot make sense of counts as ON, which is how the')
    $out.Add(';  drive behaved before these switches existed. So a typo here can never')
    $out.Add(';  quietly turn something off.')
    $out.Add(';')
    $out.Add(';  Keep the comments. They are what makes this readable to whoever ends up')
    $out.Add(';  owning the drive.')
    $out.Add('; ---------------------------------------------------------------------------')
    $out.Add('')
    $out.Add('[features]')

    foreach ($k in $cat.Keys) {
        $on = $true
        if ($null -ne $Values -and $Values.ContainsKey($k)) { $on = [bool]$Values[$k] }

        $out.Add('')
        $out.Add(('; {0}' -f $cat[$k].title))
        $out.Add((';   on   {0}' -f $cat[$k].desc))
        $out.Add((';   off  {0}' -f $cat[$k].off))
        $out.Add(('{0,-18}= {1}' -f $k, $(if ($on) { 'on' } else { 'off' })))
    }

    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-Content -LiteralPath $path -Value $out -Encoding ASCII
    return $true
}

# ---------------------------------------------------------------------------
#  Write changed values back, KEEPING every comment and blank line.
#
#  Three details that are here because of bugs found on the profile writers,
#  which do the same job on a different file:
#    - comment lines are skipped before looking for a key, so a commented
#      example "; videovolume = off" is never edited instead of the real line
#    - trailing blank lines are trimmed, or every save leaves one more than
#      the last and the file slowly turns into empty space
#    - a key that is not in the file yet is appended with its comments, so a
#      file written by an older version picks up new switches by itself
# ---------------------------------------------------------------------------
function Set-Features([string]$Root, [hashtable]$Values) {
    $path = Get-FeaturesPath $Root
    $cat  = Get-FeatureCatalogue

    if (-not (Test-Path -LiteralPath $path)) {
        return (New-FeaturesFile -Root $Root -Values $Values)
    }

    $lines   = @(Get-Content -LiteralPath $path)
    $out     = New-Object System.Collections.Generic.List[string]
    $written = @{}

    foreach ($line in $lines) {
        $t = "$line".Trim()

        if ($t.Length -eq 0 -or $t.StartsWith(';') -or $t.StartsWith('#') -or $t.StartsWith('[')) {
            $out.Add($line)
            continue
        }

        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { $out.Add($line); continue }

        $key = $t.Substring(0, $eq).Trim().ToLower()

        if (-not $Values.ContainsKey($key)) { $out.Add($line); continue }

        $out.Add(('{0,-18}= {1}' -f $key, $(if ([bool]$Values[$key]) { 'on' } else { 'off' })))
        $written[$key] = $true
    }

    # switches the file has never heard of
    foreach ($k in $cat.Keys) {
        if (-not $Values.ContainsKey($k)) { continue }
        if ($written.ContainsKey($k))     { continue }

        $out.Add('')
        $out.Add(('; {0}' -f $cat[$k].title))
        $out.Add((';   on   {0}' -f $cat[$k].desc))
        $out.Add((';   off  {0}' -f $cat[$k].off))
        $out.Add(('{0,-18}= {1}' -f $k, $(if ([bool]$Values[$k]) { 'on' } else { 'off' })))
    }

    while ($out.Count -gt 0 -and "$($out[$out.Count - 1])".Trim().Length -eq 0) {
        $out.RemoveAt($out.Count - 1)
    }

    Set-Content -LiteralPath $path -Value $out -Encoding ASCII
    return $true
}

# ---------------------------------------------------------------------------
#  The line a script prints when it stops because its switch is off. One
#  line, same shape everywhere, so it is obvious in a log what happened.
# ---------------------------------------------------------------------------
function Get-FeatureOffMessage([string]$Key) {
    $cat = Get-FeatureCatalogue
    $title = if ($cat.Contains($Key)) { $cat[$Key].title } else { $Key }
    return ("Skipped: '{0}' is switched off in features.ini." -f $title)
}
