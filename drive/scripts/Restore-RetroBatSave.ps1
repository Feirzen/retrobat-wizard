<#
    Restore-RetroBatSave.ps1   (v7)
    -------------------------------------------------------------------------
    Browse and restore save-file versions.
    Use the SaveBackups\Restore A Save.bat button rather than calling this directly.

    v7 CHANGES
      * Results are now GROUPED BY SAVE FILE instead of sorted by date. All of
        one game's versions sit together, newest first, even if another game
        has newer entries.
      * If any result is from Wii or 3DS, a warning prints explaining that
        those systems store one game's save across SEVERAL files which must
        all be restored from the same timestamp.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)] [string] $Search,
    [int]    $Pick,
    [string] $SavesRoot  = '',
    [string] $BackupRoot = ''
)

# ---------------------------------------------------------------------------
#  WHERE AM I?  (do not move this into the param block above)
# ---------------------------------------------------------------------------
#  $PSScriptRoot is EMPTY while PowerShell is working out parameter default
#  values in a script started with -File, which is how the EmulationStation
#  hooks start this one. Any path built up there silently comes out wrong, and
#  the script dies on its first Split-Path before it can even write to its own
#  log. That is exactly what happened here for a week in August 2026: saves
#  quietly stopped being backed up and nothing said a word.
#
#  In the body, below the param block, $PSScriptRoot is filled in properly. So
#  the paths get built here, and the parameters above just default to empty.
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { throw 'Could not work out which folder this script is in.' }
$WorkspaceDir = Split-Path $ScriptDir -Parent      # <RetroBat>\_ClaudeWorkspace
$RetroBatDir  = Split-Path $WorkspaceDir -Parent   # <RetroBat>

if (-not $SavesRoot)  { $SavesRoot  = Join-Path $RetroBatDir 'saves' }
if (-not $BackupRoot) { $BackupRoot = Join-Path $WorkspaceDir 'SaveBackups' }


$ErrorActionPreference = 'Stop'
$versionRoot = Join-Path $BackupRoot 'Versions'
# The shortcut list lives next to the buttons, in SaveBackups, so it is
# somewhere you would actually find it. The old location is still accepted.
$aliasPath   = Join-Path $BackupRoot 'game-name-shortcuts.txt'
if (-not (Test-Path -LiteralPath $aliasPath)) { $aliasPath = Join-Path $PSScriptRoot 'aliases.txt' }

if (-not (Test-Path -LiteralPath $versionRoot)) {
    throw "No backup history yet at $versionRoot. Run the Backup Saves Now button first."
}

# --- Expand the search using the shortcut list ----------------------------
$terms = @($Search)
if (Test-Path -LiteralPath $aliasPath) {
    foreach ($line in (Get-Content -LiteralPath $aliasPath -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#') -or $t -notmatch '=') { continue }
        $name = ($t -split '=', 2)[0].Trim()
        $code = ($t -split '=', 2)[1].Trim()
        if (-not $name -or -not $code) { continue }
        if ($name -like "*$Search*" -or $Search -like "*$name*") { $terms += $code }
    }
}
$terms = $terms | Select-Object -Unique

# --- Gather ---------------------------------------------------------------
$allVersions = Get-ChildItem -LiteralPath $versionRoot -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match '__' }

$matched = $allVersions | Where-Object {
    $orig = ($_.Name -split '__', 2)[1]
    $path = $_.FullName.Substring($versionRoot.Length)
    $hit  = $false
    foreach ($t in $terms) { if ($orig -like "*$t*" -or $path -like "*$t*") { $hit = $true; break } }
    $hit
}

if (-not $matched) {
    Write-Host ''
    Write-Host "  Nothing found for '$Search'." -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Systems you can search by name:' -ForegroundColor DarkGray
    $systems = Get-ChildItem -LiteralPath $versionRoot -Directory -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty Name
    Write-Host ('    ' + ($systems -join ', ')) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  GameCube and Wii saves are named by game code, not game name.' -ForegroundColor DarkGray
    Write-Host "  Add a shortcut in: $aliasPath" -ForegroundColor DarkGray
    Write-Host ''
    return
}

$rows = @()
foreach ($v in $matched) {
    $orig = ($v.Name -split '__', 2)[1]
    $when = if ($v.BaseName -match '^(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})_') {
                '{0} {1}:{2}:{3}' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4]
            } else { $v.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }

    $rows += [pscustomobject]@{
        Index    = 0
        When     = $when
        Size     = '{0:N0} KB' -f [math]::Max(1, $v.Length / 1KB)
        System   = ($v.FullName.Substring($versionRoot.Length).TrimStart('\') -split '\\')[0]
        SaveFile = $orig
        Path     = $v.FullName
    }
}

# Group by game: same save file together, newest version first inside each.
$rows = $rows | Sort-Object SaveFile, @{ Expression = 'When'; Descending = $true }
$i = 1; foreach ($r in $rows) { $r.Index = $i; $i++ }

if (-not $Pick) {
    Write-Host ''

    $multiFile = $rows | Where-Object { $_.System -in @('wii', '3ds') } | Select-Object -First 1
    if ($multiFile) {
        Write-Host '  ------------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host '   HEADS UP: Wii and 3DS results below.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '   Those systems split ONE game''s save across SEVERAL files.' -ForegroundColor Yellow
        Write-Host '   Restoring just one will not work and may leave the save broken.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '   Restore EVERY file listed for that game, and pick the SAME' -ForegroundColor Yellow
        Write-Host '   date and time for all of them. Run this tool once per file.' -ForegroundColor Yellow
        Write-Host '  ------------------------------------------------------------------' -ForegroundColor Yellow
        Write-Host ''
    }

    $rows | Format-Table -GroupBy SaveFile -Property Index, When, Size, System -AutoSize
    Write-Host ''
    return
}

$chosen = $rows | Where-Object { $_.Index -eq $Pick }
if (-not $chosen) { throw "No version with index $Pick." }

$histDir = Split-Path $chosen.Path -Parent
$relDir  = (Split-Path $histDir -Parent).Substring($versionRoot.Length).TrimStart('\')
$target  = Join-Path (Join-Path $SavesRoot $relDir) $chosen.SaveFile

Write-Host ''
Write-Host "  Restoring : $($chosen.SaveFile)" -ForegroundColor Cyan
Write-Host "  Version   : $($chosen.When)  ($($chosen.Size))" -ForegroundColor Cyan
Write-Host "  Back to   : $target" -ForegroundColor Cyan
Write-Host ''

if ($chosen.System -in @('wii', '3ds')) {
    Write-Host "  REMINDER: $($chosen.System) saves span multiple files. Restore the rest" -ForegroundColor Yellow
    Write-Host "  of this game's files from $($chosen.When) too, or the save may not load." -ForegroundColor Yellow
    Write-Host ''
}

if ($PSCmdlet.ShouldProcess($target, "Restore save from $($chosen.When)")) {

    if (Test-Path -LiteralPath $target) {
        $safety = Join-Path $histDir ('{0}_prerestore__{1}' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), $chosen.SaveFile)
        Copy-Item -LiteralPath $target -Destination $safety -Force
        Write-Host "  Previous file kept as: $(Split-Path $safety -Leaf)" -ForegroundColor DarkGray
    }

    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    Copy-Item -LiteralPath $chosen.Path -Destination $target -Force
    Write-Host ''
    Write-Host '  Restored.' -ForegroundColor Green
}
