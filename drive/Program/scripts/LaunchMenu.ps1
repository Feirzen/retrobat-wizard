<#
    LaunchMenu.ps1 - the "Launch game?" screen on every console.

    FUNCTIONS ONLY. Used by Apply-Settings.ps1 (RUN THIS AFTER AN UPDATE) and,
    since 2026-10-12, by the wizard's PLAY flow just before RetroBat starts.

    WHY BOTH (Steven, 2026-10-12: "the launch game marker is NOT working on
    flash or Xbox"): the list below only reached RetroBat when Apply-Settings
    ran, and it had not run since the list grew. PLAY now checks it every time,
    quietly, and only writes when an emulator is missing. So nobody has to
    remember a maintenance button, and a RetroBat update that replaces
    es_savestates.cfg is put right on the next PLAY by itself.

    HOW IT WORKS: RetroBat shows its launch menu only for emulators listed in
    emulationstation\.emulationstation\es_savestates.cfg. Every emulator named
    in RetroBat's own es_systems*.cfg gets an entry pointing at an empty
    folder (saves\<system>\<emulator>), so the menu only ever offers LAUNCH
    GAME. RetroBat's own entries (RetroArch, Dolphin...) are never touched.
    The off switch ('launchmenu' in features.ini) takes out only entries in
    exactly our shape.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter.
#>

# The ones that are not in es_systems*.cfg under these names, or that must be
# there whatever RetroBat's list says.
$script:LaunchMenuBase = @(
    'azahar'      # 3DS
    'cemu'        # Wii U
    'melonds'     # DS
    'soh'         # Ship of Harkinian (Ocarina of Time PC port)
    '2ship'       # 2 Ship 2 Harkinian (Majora's Mask PC port)
    'starship'    # Starship (Star Fox 64 PC port)
    'ghostship'   # Ghostship (Luigi's Mansion PC port)
    'windows'     # the Steam and Windows shelves
)

# Join-Path that also works off Windows (the tests run on Linux).
function Join-LmPath([string]$Base, [string]$Rel) {
    return (Join-Path $Base ($Rel -replace '[\\/]', [string][System.IO.Path]::DirectorySeparatorChar))
}

# Every emulator to list: the base list plus every one RetroBat names.
function Get-LaunchMenuEmulators([string]$Root) {
    $known = @{}
    $list = New-Object System.Collections.ArrayList
    foreach ($e0 in @($script:LaunchMenuBase)) { $known[([string]$e0).ToLower()] = $true; [void]$list.Add([string]$e0) }
    $esDir = Join-LmPath $Root 'emulationstation\.emulationstation'
    foreach ($sf in @(Get-ChildItem -LiteralPath $esDir -Filter 'es_systems*.cfg' -File -ErrorAction SilentlyContinue)) {
        $sx = $null
        try { [xml]$sx = [System.IO.File]::ReadAllText($sf.FullName) } catch { continue }
        foreach ($en in @($sx.SelectNodes('//emulator'))) {
            if ($null -eq $en) { continue }
            $n = [string]$en.GetAttribute('name')
            if ($n -notmatch '^[A-Za-z0-9_.\-]+$') { continue }
            if ($known.ContainsKey($n.ToLower())) { continue }
            $known[$n.ToLower()] = $true
            [void]$list.Add($n)
        }
    }
    return ,([string[]]$list.ToArray())
}

# Puts es_savestates.cfg right. $On = $false takes our entries out again.
# Writes only when something changes, with a copy of the old file in
# _Wizard\Backups\Archive\savestates_<time>\ first.
# Returns @{ Ok; Message; Added (names); Removed (names); Already; Backup }.
function Update-LaunchMenu([string]$Root, [bool]$On = $true) {
    $res = @{ Ok = $false; Message = ''; Added = @(); Removed = @(); Already = 0; Backup = '' }
    $ssPath = Join-LmPath $Root 'emulationstation\.emulationstation\es_savestates.cfg'
    if (-not (Test-Path -LiteralPath $ssPath)) { $res.Message = 'es_savestates.cfg not found'; return $res }
    $ssXml = New-Object System.Xml.XmlDocument
    try { $ssXml.LoadXml([System.IO.File]::ReadAllText($ssPath)) } catch { $res.Message = 'es_savestates.cfg could not be read'; return $res }
    $ssRoot = $ssXml.SelectSingleNode('/savestates')
    if ($null -eq $ssRoot) { $res.Message = 'es_savestates.cfg has no <savestates> root'; return $res }

    $added = New-Object System.Collections.ArrayList
    $removed = New-Object System.Collections.ArrayList
    foreach ($emu in (Get-LaunchMenuEmulators $Root)) {
        $old = $ssRoot.SelectSingleNode("emulator[@name='$emu']")
        if (-not $On) {
            if ($null -eq $old) { continue }
            $d = $old.SelectSingleNode('directory'); $f = $old.SelectSingleNode('file')
            if ($null -eq $d -or $null -eq $f -or [string]$d.InnerText -ne "{{system}}/$emu" -or
                [string]$f.InnerText -ne '{{romfilename}}.state{{slot2d}}') { continue }
            [void]$ssRoot.RemoveChild($old)
            [void]$removed.Add($emu)
            continue
        }
        if ($null -ne $old) { $res.Already++; continue }
        $node = $ssXml.CreateElement('emulator')
        $node.SetAttribute('name', $emu)
        $node.SetAttribute('firstslot', '1')
        $node.SetAttribute('lastslot', '10')
        $node.SetAttribute('autosave', 'false')
        $node.SetAttribute('incremental', 'false')
        foreach ($pair in @(@('directory', "{{system}}/$emu"), @('file', '{{romfilename}}.state{{slot2d}}'), @('image', '{{romfilename}}.state{{slot2d}}.png'))) {
            $child = $ssXml.CreateElement($pair[0]); $child.InnerText = $pair[1]
            [void]$node.AppendChild($child)
        }
        [void]$ssRoot.AppendChild($node)
        [void]$added.Add($emu)
    }
    $res.Added = @($added.ToArray()); $res.Removed = @($removed.ToArray())

    if ($added.Count + $removed.Count -gt 0) {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $backup = Join-LmPath $Root "_Wizard\Backups\Archive\savestates_$stamp"
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $ssPath -Destination (Join-Path $backup 'es_savestates.cfg') -Force
        $res.Backup = $backup
        $set = New-Object System.Xml.XmlWriterSettings
        $set.Indent = $true; $set.IndentChars = '  '
        $set.Encoding = New-Object System.Text.UTF8Encoding($false)
        $w = [System.Xml.XmlWriter]::Create($ssPath, $set)
        try { $ssXml.Save($w) } finally { $w.Close() }
    }
    $res.Ok = $true
    $res.Message = $(if ($On) { '{0} added, {1} already there' -f $added.Count, $res.Already } else { '{0} removed' -f $removed.Count })
    return $res
}
