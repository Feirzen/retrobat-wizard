<#
.SYNOPSIS
    Re-applies custom EmulationStation collection theming to the ckau-book theme
    after a RetroBat theme update overwrites it.

.DESCRIPTION
    A RetroBat / EmulationStation theme update replaces everything inside the theme
    folder. This script restores the pieces that make a custom collection render as
    its own system view instead of the generic shared "custom-collections" look:

      1. Copies master asset files from the safe folder into the theme.
      2. Ensures each collection name is listed in collections.info.
      3. Ensures a <sysColor> line exists in _inc\elements\syscolors.xml.

    The script is idempotent. Running it twice reports "already correct" rather than
    duplicating anything. It never deletes, moves, or truncates a file, and it writes
    a .bak copy beside any existing theme file before its first modification.

.PARAMETER WhatIf
    Dry run. Shows every action without touching a single file.

.EXAMPLE
    .\Restore-CkauBookTheme.ps1 -WhatIf
    .\Restore-CkauBookTheme.ps1

.NOTES
    Background colors only render when the theme's "System background color" subset
    is set to one of the Colorful options. Darkful / Blackful / Lightful / Greyful
    hardcode a fixed value and ignore <sysColor> entirely.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# ============================================================================
#  CONFIGURATION -- edit this block only
# ============================================================================

# --- Collections -----------------------------------------------------------
# Key   = the collection name EXACTLY as it appears in the collections folder
#         filename (custom-<Name>.cfg). This match is case-sensitive inside
#         EmulationStation even though the UI displays everything in uppercase.
# Value = background hex color, no leading '#'.
#
# To add a collection later: drop its three files in
# _ClaudeWorkspace\theme-assets\  (<Name>.xml, <Name>.png, <Name>.mp4)
# and add one line here.

$Collections = [ordered]@{
    'Zelda'   = '3a694a'
    'Pokemon' = 'd9c88c'
}

# --- Paths -----------------------------------------------------------------
# RetroBat is found from where this script sits, never from a drive letter.
# The safe folder holds the master copies of the collection artwork.

# This script lives in <RetroBat>\_ClaudeWorkspace\scripts\, so RetroBat is
# always two folders up. No drive letter, no guessing, works on any machine.
$RetroBatRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$SafeFolderName = '_ClaudeWorkspace\theme-assets'
$ThemeName      = 'ckau-book'

# --- Asset routing ---------------------------------------------------------
# The safe folder is flat. File extension decides where each file lands inside
# the theme. Add an entry here if you ever add a new asset type.

$AssetMap = [ordered]@{
    '.xml' = '_inc\layouts'
    '.png' = '_inc\arts'
    '.mp4' = '_inc\videos'
    '.svg' = '_inc\logos'
}

# ============================================================================
#  END CONFIGURATION
# ============================================================================

$script:Stats = [ordered]@{ Copied = 0; Skipped = 0; Added = 0; Fixed = 0; Warnings = 0 }

function Write-Item {
    param(
        [Parameter(Mandatory)][ValidateSet('OK', 'ACT', 'WARN', 'INFO')][string]$Kind,
        [Parameter(Mandatory)][string]$Message
    )
    switch ($Kind) {
        'OK'   { Write-Host '  [ok]    ' -ForegroundColor DarkGray -NoNewline; Write-Host $Message -ForegroundColor DarkGray }
        'ACT'  { Write-Host '  [done]  ' -ForegroundColor Green    -NoNewline; Write-Host $Message }
        'WARN' { Write-Host '  [warn]  ' -ForegroundColor Yellow   -NoNewline; Write-Host $Message -ForegroundColor Yellow }
        'INFO' { Write-Host '  [info]  ' -ForegroundColor Cyan     -NoNewline; Write-Host $Message }
    }
}

function Resolve-RetroBatRoot {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath (Join-Path $Explicit 'RetroBat.exe'))) {
            throw "RetroBat.exe not found under '$Explicit'. Fix `$RetroBatRoot at the top of this script."
        }
        return $Explicit
    }

    # Probe every fixed/removable drive for \RetroBat\RetroBat.exe
    $found = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path ($d.Root) 'RetroBat'
        if (Test-Path -LiteralPath (Join-Path $candidate 'RetroBat.exe')) { $found += $candidate }
    }

    if ($found.Count -eq 0) {
        throw 'Could not auto-detect RetroBat. Set $RetroBatRoot explicitly at the top of this script.'
    }
    if ($found.Count -gt 1) {
        Write-Item WARN "Multiple RetroBat installs found: $($found -join ', '). Using the first."
        $script:Stats.Warnings++
    }
    return $found[0]
}

function Backup-Once {
    <# Writes <file>.bak beside the file if one does not already exist. Never overwrites. #>
    param([Parameter(Mandatory)][string]$Path)

    $bak = "$Path.bak"
    if (Test-Path -LiteralPath $bak) { return }
    if (-not $WhatIfPreference) {
        Copy-Item -LiteralPath $Path -Destination $bak -ErrorAction Stop
    }
    Write-Item ACT "backed up -> $(Split-Path $bak -Leaf)"
}

function Get-FileHashSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Read-TextPreserving {
    <#
      Returns @{ Text; Newline; HasBom } so the file is written back with its own
      line endings and its own BOM state. collections.info ships WITH a UTF-8 BOM
      and syscolors.xml ships WITHOUT one; silently flipping either is asking for
      a hard-to-diagnose parse failure later.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $bytes  = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text   = [System.IO.File]::ReadAllText($Path)   # strips the BOM from the string
    $nl     = if ($text -match "`r`n") { "`r`n" } else { "`n" }

    return @{ Text = $text; Newline = $nl; HasBom = $hasBom }
}

function Write-TextPreserving {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [bool]$HasBom = $false
    )
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function New-CaseVariantCondition {
    <#
      Builds an OR'd condition covering UPPER / lower / Title case of the name, so a
      mis-cased collection still picks up its color. Single-quoted throughout because
      ${system.theme} is literal text, not a PowerShell variable.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $ti = (Get-Culture).TextInfo
    $variants = @(
        $Name.ToUpperInvariant()
        $Name.ToLowerInvariant()
        $ti.ToTitleCase($Name.ToLowerInvariant())
        $Name
    ) | Select-Object -Unique

    return (($variants | ForEach-Object { '${system.theme} == ''' + $_ + '''' }) -join ' || ')
}

# ============================================================================
#  MAIN
# ============================================================================

Write-Host ''
Write-Host '  ckau-book collection theme restore' -ForegroundColor White
Write-Host '  ----------------------------------' -ForegroundColor DarkGray
if ($WhatIfPreference) { Write-Host '  DRY RUN - nothing will be written' -ForegroundColor Magenta }
Write-Host ''

# --- Resolve paths ---------------------------------------------------------
$RetroBatRoot   = Resolve-RetroBatRoot -Explicit $RetroBatRoot

# --- is this switched on? --------------------------------------------------
#  features.ini decides. EVERYTHING FAILS ON: a missing Features.ps1, a
#  missing or unreadable features.ini, or a value that is not on or off, all
#  mean ON, which is what this drive did before the switches existed. So a
#  broken file can never quietly stop this from running. Details and the
#  catalogue of switches are in scripts\Features.ps1.
$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    if (-not (Test-Feature $RetroBatRoot 'themecollections')) {
        Write-Host ""
        Write-Host (Get-FeatureOffMessage 'themecollections') -ForegroundColor Yellow
        Write-Host "Turn it back on in the Features tab, or in features.ini." -ForegroundColor DarkGray
        Write-Host ""
        exit 0
    }
}

$EsRoot         = Join-Path $RetroBatRoot 'emulationstation\.emulationstation'
$ThemeRoot      = Join-Path $EsRoot "themes\$ThemeName"
$SafeFolder     = Join-Path $RetroBatRoot $SafeFolderName
$CollectionsDir = Join-Path $EsRoot 'collections'
$CollectionsInfo = Join-Path $ThemeRoot 'collections.info'
$SysColorsFile   = Join-Path $ThemeRoot '_inc\elements\syscolors.xml'

foreach ($p in @($ThemeRoot, $SafeFolder, $CollectionsInfo, $SysColorsFile)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Required path not found: $p" }
}

Write-Host '  Paths' -ForegroundColor White
Write-Item INFO "RetroBat    $RetroBatRoot"
Write-Item INFO "Theme       $ThemeRoot"
Write-Item INFO "Safe folder $SafeFolder"
Write-Host ''

# --- Sanity check: collection names vs what is actually on disk -------------
Write-Host '  Collection names' -ForegroundColor White

# NOTE: a plain @{} hashtable in PowerShell is CASE-INSENSITIVE, which would
# silently defeat the whole point of this check. Compare with Ordinal explicitly.
$onDisk = @()
if (Test-Path -LiteralPath $CollectionsDir) {
    $onDisk = @(
        Get-ChildItem -LiteralPath $CollectionsDir -Filter 'custom-*.cfg' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName -replace '^custom-', '' }
    )
}

foreach ($name in $Collections.Keys) {
    $exact = $onDisk | Where-Object { [string]::Equals($_, $name, [System.StringComparison]::Ordinal) } | Select-Object -First 1
    $loose = $onDisk | Where-Object { [string]::Equals($_, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1

    if ($exact) {
        Write-Item OK "'$name' matches custom-$exact.cfg"
    }
    elseif ($loose) {
        Write-Item WARN "'$name' is cased wrong - disk says '$loose'. Change the hashtable key to '$loose' or this collection will not theme."
        $script:Stats.Warnings++
    }
    else {
        Write-Item WARN "no custom-$name.cfg in the collections folder. Theming will not apply."
        $script:Stats.Warnings++
    }
}
Write-Host ''

# --- 1. Copy assets --------------------------------------------------------
Write-Host '  Assets' -ForegroundColor White
$assetFiles = Get-ChildItem -LiteralPath $SafeFolder -File -ErrorAction SilentlyContinue

if (-not $assetFiles) {
    Write-Item WARN "safe folder is empty - nothing to copy."
    $script:Stats.Warnings++
}

foreach ($f in $assetFiles) {
    $ext = $f.Extension.ToLowerInvariant()
    if (-not $AssetMap.Contains($ext)) {
        Write-Item WARN "$($f.Name) - unmapped extension '$ext', skipped."
        $script:Stats.Warnings++
        continue
    }

    $destDir  = Join-Path $ThemeRoot $AssetMap[$ext]
    $destFile = Join-Path $destDir $f.Name
    $rel      = "$($AssetMap[$ext])\$($f.Name)"

    if (-not (Test-Path -LiteralPath $destDir)) {
        if (-not $WhatIfPreference) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Write-Item ACT "created folder $($AssetMap[$ext])"
    }

    $srcHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $dstHash = Get-FileHashSafe -Path $destFile

    if ($dstHash -eq $srcHash) {
        Write-Item OK "$rel already correct"
        $script:Stats.Skipped++
        continue
    }

    # Videos are the one asset something else deliberately changes AFTER a
    # restore: Fix Video Volume re-records the theme's menu videos to the
    # menu target, which makes the live file differ from this master for
    # good. Copying over it every run put the two scripts in a permanent
    # loop - the restore put the loud original back, the volume step
    # levelled it again, every single time RUN THIS AFTER AN UPDATE ran.
    # So a video is copied when it is MISSING, or when this master is NEWER
    # than the live copy (which is what happens when a new video is
    # deliberately dropped into theme-assets). Otherwise it is left alone.
    if ($ext -eq '.mp4' -and $null -ne $dstHash) {
        $dstTime = (Get-Item -LiteralPath $destFile).LastWriteTimeUtc
        if ($f.LastWriteTimeUtc -le $dstTime) {
            Write-Item OK "$rel left alone (the levelled copy is newer than the master)"
            $script:Stats.Skipped++
            continue
        }
    }

    if ($null -ne $dstHash) { Backup-Once -Path $destFile }

    if (-not $WhatIfPreference) { Copy-Item -LiteralPath $f.FullName -Destination $destFile -Force }
    Write-Item ACT "$rel copied"
    $script:Stats.Copied++
}
Write-Host ''

# --- 2. collections.info ---------------------------------------------------
Write-Host '  collections.info' -ForegroundColor White
$ci      = Read-TextPreserving -Path $CollectionsInfo
$ciLines = $ci.Text -split "`r?`n"
$toAppend = @()

foreach ($name in $Collections.Keys) {
    # -ceq / -cne are the case-SENSITIVE operators. This comparison is the whole
    # reason the script exists, so do not relax them.
    $exact = $ciLines | Where-Object { $_.Trim() -ceq $name } | Select-Object -First 1
    $loose = $ciLines | Where-Object { $_.Trim() -ieq $name -and $_.Trim() -cne $name } | Select-Object -First 1

    if ($null -ne $exact) {
        Write-Item OK "'$name' already listed"
        $script:Stats.Skipped++
    }
    else {
        if ($null -ne $loose) {
            Write-Item WARN "found '$($loose.Trim())' (wrong case). Appending correct '$name'; the old line is left alone."
            $script:Stats.Warnings++
        }
        $toAppend += $name
    }
}

if ($toAppend.Count -gt 0) {
    Backup-Once -Path $CollectionsInfo

    $body = $ci.Text.TrimEnd("`r", "`n")
    $new  = $body + $ci.Newline + (($toAppend) -join $ci.Newline) + $ci.Newline

    if (-not $WhatIfPreference) { Write-TextPreserving -Path $CollectionsInfo -Text $new -HasBom $ci.HasBom }
    foreach ($n in $toAppend) { Write-Item ACT "'$n' appended"; $script:Stats.Added++ }
}
Write-Host ''

# --- 3. syscolors.xml ------------------------------------------------------
Write-Host '  syscolors.xml' -ForegroundColor White
$sc      = Read-TextPreserving -Path $SysColorsFile
$scText  = $sc.Text
$scDirty = $false

foreach ($name in $Collections.Keys) {
    $hex = $Collections[$name].ToLowerInvariant()

    # Match a sysColor element whose condition names this collection in ANY casing.
    # The quotes around the name are part of the pattern, so 'zeldac' will not match 'zelda'.
    $esc     = [regex]::Escape($name)
    $linePat = '(?m)^[ \t]*<sysColor\s+if="[^"]*\$\{system\.theme\}\s*==\s*''' + $esc + '''[^"]*"\s*>([0-9a-fA-F]{6,8})</sysColor>[ \t]*\r?$'
    $rx      = [regex]::new($linePat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $m       = $rx.Match($scText)

    if ($m.Success) {
        if ($m.Groups[1].Value.ToLowerInvariant() -eq $hex) {
            Write-Item OK "'$name' -> $hex already correct"
            $script:Stats.Skipped++
        }
        else {
            $old = $m.Groups[1].Value
            if (-not $scDirty) { Backup-Once -Path $SysColorsFile; $scDirty = $true }
            $fixedLine = $m.Value -replace [regex]::Escape(">$old</sysColor>"), ">$hex</sysColor>"
            $scText    = $scText.Remove($m.Index, $m.Length).Insert($m.Index, $fixedLine)
            Write-Item ACT "'$name' color corrected $old -> $hex"
            $script:Stats.Fixed++
        }
        continue
    }

    # Not present -> insert before the closing </variables> tag.
    $closeRx = [regex]::new('(?m)^([ \t]*)</variables>')
    $close   = $closeRx.Match($scText)
    if (-not $close.Success) {
        Write-Item WARN "no </variables> tag found - cannot insert '$name'. File left untouched."
        $script:Stats.Warnings++
        continue
    }

    if (-not $scDirty) { Backup-Once -Path $SysColorsFile; $scDirty = $true }

    $indent    = $close.Groups[1].Value + "`t"
    $condition = New-CaseVariantCondition -Name $name
    $newLine   = $indent + '<sysColor if="' + $condition + '">' + $hex + '</sysColor>' + $sc.Newline

    $scText = $scText.Insert($close.Index, $newLine)
    Write-Item ACT "'$name' -> $hex inserted"
    $script:Stats.Added++
}

if ($scDirty -and -not $WhatIfPreference) {
    Write-TextPreserving -Path $SysColorsFile -Text $scText -HasBom $sc.HasBom
}
Write-Host ''

# --- Summary ---------------------------------------------------------------
Write-Host '  Summary' -ForegroundColor White
Write-Host "  copied $($script:Stats.Copied)   added $($script:Stats.Added)   corrected $($script:Stats.Fixed)   already correct $($script:Stats.Skipped)   warnings $($script:Stats.Warnings)"
Write-Host ''

if ($script:Stats.Warnings -gt 0) {
    Write-Host '  Review the warnings above before launching.' -ForegroundColor Yellow
    Write-Host ''
}

Write-Host '  Reminder' -ForegroundColor White
Write-Host '  Background colors only render when the theme subset' -ForegroundColor DarkYellow
Write-Host '  "System background color" is set to one of the Colorful options.' -ForegroundColor DarkYellow
Write-Host '  Darkful / Blackful / Lightful / Greyful ignore sysColor entirely.' -ForegroundColor DarkYellow
Write-Host '  Main Menu > Game Settings > Theme Configuration' -ForegroundColor DarkYellow
Write-Host ''

# Exit codes, for the .bat launcher:  0 = clean   2 = finished with warnings
if ($script:Stats.Warnings -gt 0) { exit 2 } else { exit 0 }
