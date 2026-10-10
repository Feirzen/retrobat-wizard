<#
    Test-WiiUGames.ps1
    ---------------------------------------------------------------------------
    Checks every Wii U .wux disc image for a half-finished download or a
    half-finished unzip.

    WHY THIS EXISTS

    A .wux that is missing the end of the file still starts. The beginning of a
    disc is the menu and the first load, so the game boots, plays for a bit, and
    then crashes the moment it reaches a part that was never written. That looks
    exactly like an emulator problem and it is not one - the file is simply
    incomplete.

    Yoshi's Woolly World was 98.2% complete in August 2026 and did precisely
    that. Nothing in RetroBat or Cemu would ever have told you why.

    HOW IT KNOWS

    A .wux is a squashed copy of a Wii U disc. Its first few bytes say how big
    the original disc was and how big each chunk is, and then it lists which
    slot in the file each chunk of the disc was put in. Read that list, find the
    highest slot number used, and you know exactly how many bytes the file has
    to be. Anything shorter is truncated. It is arithmetic, not a guess.

    WHAT IT DOES NOT CHECK

    Only whether the whole file is THERE. It says nothing about whether the
    bytes inside are correct.

    A download can arrive at exactly the right length with damaged data in the
    middle, and this will call it OK. That kind of damage shows up a different
    way: 7-Zip reports "Data error" while unpacking. So the two checks go
    together -

        7-Zip  ->  right-click the .7z, 7-Zip, Test archive
                   catches damaged data
        this   ->  catches a file that stopped early

    It also cannot tell you whether the key in keys.txt is right, or whether the
    file is even the game its name claims. Cemu says so itself in those cases.

    Nothing is changed, moved or deleted. It only looks.

    Run it from:  Maintenance Steps\Check Wii U Games.bat
#>

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# --- locate RetroBat -------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = Split-Path (Split-Path $ScriptDir -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    exit 1
}

$RomDir = Join-Path $Root 'roms\wiiu'
if (-not (Test-Path $RomDir)) {
    Say "No roms\wiiu folder - nothing to check." 'Yellow'
    exit 0
}

Say ""
Say "Checking Wii U disc images in roms\wiiu" 'Cyan'
Say ""

$files = @(Get-ChildItem -LiteralPath $RomDir -Filter '*.wux' -File -ErrorAction SilentlyContinue | Sort-Object Name)

if ($files.Count -eq 0) {
    Say "No .wux files found." 'Yellow'
    Say "(Games stored as decrypted folders or .wua files are not checked by this -" 'DarkGray'
    Say " they cannot be half-written in a way that looks like a working game.)" 'DarkGray'
    Say ""
    exit 0
}

$HEADER_BYTES = 24
$ok = 0; $bad = 0; $unknown = 0
$broken = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
    $name = $f.BaseName
    $short = if ($name.Length -gt 46) { $name.Substring(0,43) + '...' } else { $name }

    try {
        $fs = [System.IO.File]::OpenRead($f.FullName)
        try {
            $hdr = New-Object byte[] $HEADER_BYTES
            if ($fs.Read($hdr, 0, $HEADER_BYTES) -lt $HEADER_BYTES) { throw 'file is too small to be a .wux at all' }

            # 0x00 'WUX0'  0x04 magic  0x08 chunk size  0x0C padding  0x10 disc size
            if ([System.Text.Encoding]::ASCII.GetString($hdr, 0, 4) -ne 'WUX0' -or
                [BitConverter]::ToUInt32($hdr, 4) -ne 0x1099d02e) {
                throw 'not a .wux file (the identifying bytes at the front are wrong)'
            }

            $chunkSize = [BitConverter]::ToUInt32($hdr, 8)
            $discSize  = [BitConverter]::ToUInt64($hdr, 16)
            if ($chunkSize -eq 0 -or $chunkSize -gt 1MB) { throw 'the header does not make sense' }

            $chunkCount = [uint64][math]::Ceiling($discSize / [double]$chunkSize)
            $tableBytes = [int]($chunkCount * 4)

            $table = New-Object byte[] $tableBytes
            $read = 0
            while ($read -lt $tableBytes) {
                $n = $fs.Read($table, $read, $tableBytes - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            if ($read -lt $tableBytes) { throw 'truncated so early that even the chunk list is cut off' }

            $highest = [uint32]0
            for ($i = 0; $i -lt $tableBytes; $i += 4) {
                $v = [BitConverter]::ToUInt32($table, $i)
                if ($v -gt $highest) { $highest = $v }
            }

            $dataStart = [uint64][math]::Ceiling(($HEADER_BYTES + $tableBytes) / [double]$chunkSize) * $chunkSize
            $needed    = $dataStart + ([uint64]$highest + 1) * $chunkSize
        }
        finally { $fs.Dispose() }
    }
    catch {
        Say ("  ?  {0}" -f $short) 'Yellow'
        Say ("     {0}" -f $_.Exception.Message) 'DarkGray'
        $unknown++
        continue
    }

    $haveGB = $f.Length / 1GB
    $needGB = $needed / 1GB

    if ($f.Length -ge $needed) {
        Say ("  OK {0,-46} {1,6:N2} GB" -f $short, $haveGB) 'Green'
        $ok++
    }
    else {
        $pct = 100.0 * $f.Length / $needed
        Say ("  XX {0,-46} {1,6:N2} GB of {2,6:N2} GB  ({3:N1}%)" -f $short, $haveGB, $needGB, $pct) 'Red'
        $bad++
        $broken.Add($name)
    }
}

Say ""
Say "---------------------------------------------------------------------------" 'DarkGray'
Say ("  complete    : {0}" -f $ok) 'Gray'
Say ("  INCOMPLETE  : {0}" -f $bad) $(if ($bad) { 'Red' } else { 'Gray' })
Say ("  unreadable  : {0}" -f $unknown) $(if ($unknown) { 'Yellow' } else { 'Gray' })
Say "---------------------------------------------------------------------------" 'DarkGray'

if ($bad -gt 0) {
    Say ""
    Say "These are missing part of the file:" 'Red'
    foreach ($b in $broken) { Say ("   $b") 'Yellow' }
    Say ""
    Say "An incomplete disc image still boots and then crashes later, which is why" 'Gray'
    Say "it looks like an emulator fault. It is not. Get the file again and unpack" 'Gray'
    Say "it with 7-Zip, then run this to confirm before you spend an evening on it." 'Gray'
}

Say ""
exit 0
