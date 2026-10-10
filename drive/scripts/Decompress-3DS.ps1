<#
    Decompress-3DS.ps1
    ---------------------------------------------------------------------------
    Permanently unpacks 3DS ROMs so RetroBat stops extracting a ~1 GB archive
    off the external drive every single time you launch a game.

    For each .7z sitting in roms\3ds it will:

      1. Look inside. Only proceeds if the archive holds exactly one real 3DS
         ROM (.3ds .cci .cxi .cia). Harmless filler that ROM sites bundle in -
         readme and watermark text files like "Vimm's Lair.txt" - is ignored
         and left behind in the archive. If there is anything in there the
         script does not recognise, it skips that archive and says so rather
         than guessing.
      2. Extract just the ROM into roms\3ds. The filler files are not
         extracted, so nothing junk lands in your ROM folder.
      3. Move the original .7z into roms\3ds\.compressed
         The dot at the start of that folder name is deliberate - it is how
         EmulationStation knows to ignore a folder, so your archives sit right
         there next to the games without showing up in the game list.
      4. Repair gamelist.xml so your scraped box art, videos and descriptions
         follow the game to its new filename instead of detaching.

    Nothing is deleted. The originals stay in .compressed until you remove
    them yourself.

    Safe to re-run. Files already converted are skipped.

    Run it from:  Maintenance Steps\Unpack New 3DS Roms.bat
      - after dropping a new .7z into roms\3ds
      - or any time; if there is nothing new it does nothing.
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$WhatIfOnly   # list what would happen, change nothing
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# Extensions we accept as a real 3DS ROM inside an archive.
$RomExts = @('.3ds', '.cci', '.cxi', '.cia')

# Filler that ROM sites bundle alongside the game. Safe to leave in the
# archive and not extract. Add to this list if you meet a new one.
$JunkExts = @('.txt', '.nfo', '.md', '.url', '.diz', '.sfv', '.log',
              '.jpg', '.jpeg', '.png', '.gif', '.htm', '.html')

# --- locate RetroBat -------------------------------------------------------
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    exit 1
}


# --- is this switched on? --------------------------------------------------
#  features.ini decides. EVERYTHING FAILS ON: a missing Features.ps1, a
#  missing or unreadable features.ini, or a value that is not on or off, all
#  mean ON, which is what this drive did before the switches existed. So a
#  broken file can never quietly stop this from running. Details and the
#  catalogue of switches are in scripts\Features.ps1.
$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    if (-not (Test-Feature $Root 'unpack3ds')) {
        Write-Host ""
        Write-Host (Get-FeatureOffMessage 'unpack3ds') -ForegroundColor Yellow
        Write-Host "Turn it back on in the Features tab, or in features.ini." -ForegroundColor DarkGray
        Write-Host ""
        exit 0
    }
}

$romDir  = Join-Path $Root 'roms\3ds'
$archDir = Join-Path $romDir '.compressed'
$glPath  = Join-Path $romDir 'gamelist.xml'
$sevenZ  = Join-Path $Root 'system\tools\7za.exe'

if (-not (Test-Path $romDir))  { Write-Host "ERROR: $romDir not found." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $sevenZ))  { Write-Host "ERROR: 7za.exe not found at $sevenZ" -ForegroundColor Red; exit 1 }

# --- refuse to run while RetroBat is open ----------------------------------
$running = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Write-Host "  RetroBat is currently running." -ForegroundColor Red
    Write-Host "  Close it and run this again, so the game list picks up the changes." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$archives = @(Get-ChildItem -LiteralPath $romDir -Filter '*.7z' -File -ErrorAction SilentlyContinue)

Say ""
Say "3DS folder: $romDir" 'Cyan'
Say ""

if ($archives.Count -eq 0) {
    Say "No .7z files to unpack. Nothing to do." 'Green'
    Say ""
    exit 0
}

Say "Found $($archives.Count) archive(s)." 'White'
Say ""

# --- read what is inside each archive first, so we can check space ---------
function Get-ArchiveContents([string]$archive) {
    $out = & $sevenZ l -slt -- $archive 2>&1
    $entries = @()
    $cur = $null
    foreach ($line in $out) {
        $s = [string]$line
        if ($s -match '^Path = (.+)$') {
            if ($cur) { $entries += $cur }
            $cur = [pscustomobject]@{ Path = $Matches[1]; Size = 0; IsDir = $false }
        }
        elseif ($cur -and $s -match '^Size = (\d+)$')       { $cur.Size = [int64]$Matches[1] }
        elseif ($cur -and $s -match '^Attributes = (.+)$')  { if ($Matches[1] -match 'D') { $cur.IsDir = $true } }
    }
    if ($cur) { $entries += $cur }
    # The first "Path =" 7-Zip prints is the archive's own name, drop it.
    if ($entries.Count -gt 0 -and $entries[0].Path -eq $archive) { $entries = $entries[1..($entries.Count - 1)] }
    return @($entries | Where-Object { -not $_.IsDir })
}

$plan = @()

foreach ($a in $archives) {
    $files = Get-ArchiveContents $a.FullName

    # Sort what is inside into three buckets: the game, harmless filler, and
    # anything we do not recognise.
    $roms  = @($files | Where-Object { $RomExts  -contains [System.IO.Path]::GetExtension($_.Path).ToLower() })
    $junk  = @($files | Where-Object { $JunkExts -contains [System.IO.Path]::GetExtension($_.Path).ToLower() })
    $other = @($files | Where-Object {
        $e = [System.IO.Path]::GetExtension($_.Path).ToLower()
        ($RomExts -notcontains $e) -and ($JunkExts -notcontains $e)
    })

    if ($other.Count -gt 0) {
        $names = ($other | ForEach-Object { Split-Path $_.Path -Leaf }) -join ', '
        $plan += [pscustomobject]@{ Archive = $a; Skip = "contains unrecognised file(s): $names" }
        continue
    }

    if ($roms.Count -ne 1) {
        $plan += [pscustomobject]@{ Archive = $a; Skip = "holds $($roms.Count) ROM files, expected exactly 1" }
        continue
    }

    $inner  = $roms[0]
    $target = Join-Path $romDir (Split-Path $inner.Path -Leaf)

    if (Test-Path $target) {
        $plan += [pscustomobject]@{ Archive = $a; Skip = "$(Split-Path $target -Leaf) already exists" }
        continue
    }

    $plan += [pscustomobject]@{
        Archive   = $a
        Inner     = Split-Path $inner.Path -Leaf
        InnerPath = $inner.Path      # path as stored inside the archive
        Size      = $inner.Size
        JunkCount = $junk.Count
        Target    = $target
        Skip      = $null
    }
}

$todo = @($plan | Where-Object { -not $_.Skip })
$skip = @($plan | Where-Object { $_.Skip })

foreach ($s in $skip) {
    Say ("  SKIP  {0}" -f $s.Archive.Name) 'DarkYellow'
    Say ("        {0}" -f $s.Skip) 'DarkGray'
}

if ($todo.Count -eq 0) {
    Say ""
    Say "Nothing left to unpack." 'Green'
    Say ""
    exit 0
}

# --- disk space check ------------------------------------------------------
$needed = ($todo | Measure-Object -Property Size -Sum).Sum
$drive  = (Get-Item $romDir).PSDrive
$free   = (Get-PSDrive $drive.Name).Free

Say ""
Say ("  To unpack : {0} game(s), {1:N1} GB" -f $todo.Count, ($needed / 1GB)) 'White'
Say ("  Free space: {0:N1} GB" -f ($free / 1GB)) 'White'
Say ""

if ($free -lt ($needed * 1.05)) {
    Write-Host "  Not enough free space. Free up room and run this again." -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($WhatIfOnly) {
    Say "  -WhatIfOnly was set. Stopping here without changing anything." 'Cyan'
    Say ""
    exit 0
}

# --- back up gamelist.xml before we touch it -------------------------------
if (Test-Path $glPath) {
    $stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $backupDir = Join-Path $Root "_ClaudeWorkspace\archive\3ds-unpack_$stamp"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item $glPath (Join-Path $backupDir 'gamelist.xml') -Force
    Say "  gamelist.xml backed up to _ClaudeWorkspace\archive\3ds-unpack_$stamp" 'DarkGray'
    Say ""
}

if (-not (Test-Path $archDir)) {
    New-Item -ItemType Directory -Path $archDir -Force | Out-Null
    # Belt and braces: the leading dot is what hides it from EmulationStation,
    # the Hidden attribute keeps it out of the way in Explorer too.
    (Get-Item $archDir -Force).Attributes = 'Directory, Hidden'
}

# --- do the work -----------------------------------------------------------
$renames = @{}
$done    = 0
$failed  = 0

foreach ($job in $todo) {
    Say ("  Unpacking {0}" -f $job.Archive.Name) 'White'
    if ($job.JunkCount -gt 0) {
        Say ("        (leaving {0} readme/filler file(s) in the archive)" -f $job.JunkCount) 'DarkGray'
    }

    # Name the file explicitly so only the ROM comes out - readme and
    # watermark files stay inside the archive where they belong.
    & $sevenZ e -y -o"$romDir" -- $job.Archive.FullName $job.InnerPath | Out-Null

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $job.Target)) {
        Say ("        FAILED - 7-Zip exit code $LASTEXITCODE. Original left alone." ) 'Red'
        $failed++
        continue
    }

    Move-Item -LiteralPath $job.Archive.FullName -Destination (Join-Path $archDir $job.Archive.Name) -Force
    $renames[$job.Archive.Name] = $job.Inner
    Say ("        -> {0}" -f $job.Inner) 'Green'
    $done++
}

# --- repair gamelist.xml ---------------------------------------------------
if ((Test-Path $glPath) -and $renames.Count -gt 0) {
    [xml]$gl = Get-Content -LiteralPath $glPath -Raw
    $fixed = 0

    foreach ($game in @($gl.SelectNodes('//game'))) {
        $pathNode = $game.SelectSingleNode('path')
        if (-not $pathNode) { continue }

        $leaf = Split-Path $pathNode.InnerText -Leaf
        if ($renames.ContainsKey($leaf)) {
            $prefix = $pathNode.InnerText.Substring(0, $pathNode.InnerText.Length - $leaf.Length)
            $pathNode.InnerText = $prefix + $renames[$leaf]
            $fixed++
        }
    }

    if ($fixed -gt 0) {
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.IndentChars = "`t"
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
        $writer = [System.Xml.XmlWriter]::Create($glPath, $settings)
        try { $gl.Save($writer) } finally { $writer.Close() }
    }

    Say ""
    Say "  gamelist.xml: $fixed entry(s) repointed, so box art and videos stay attached." 'Cyan'
}

# --- clear the old temp extraction folder if it is now dead weight ---------
$uncompressed = Join-Path $Root 'roms\.uncompressed\3ds'
$remaining    = @(Get-ChildItem -LiteralPath $romDir -Filter '*.7z' -File -ErrorAction SilentlyContinue)

if ((Test-Path $uncompressed) -and $remaining.Count -eq 0) {
    $size = (Get-ChildItem -LiteralPath $uncompressed -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    if ($size -gt 0) {
        $stamp2 = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $dest   = Join-Path $Root "_ClaudeWorkspace\_to_delete\uncompressed-3ds_$stamp2"
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        Move-Item -LiteralPath $uncompressed -Destination $dest -Force
        Say ""
        Say ("  No .7z files left, so RetroBat's old temp extraction folder is dead weight.") 'Cyan'
        Say ("  Moved {0:N1} GB to _ClaudeWorkspace\_to_delete\uncompressed-3ds_{1}" -f ($size / 1GB), $stamp2) 'Cyan'
        Say  "  Delete that folder whenever you like to reclaim the space." 'Gray'
    }
}

Say ""
Say "Finished. $done unpacked, $($skip.Count) skipped, $failed failed." 'Cyan'
Say "Originals are in roms\3ds\.compressed" 'Gray'
Say ""
