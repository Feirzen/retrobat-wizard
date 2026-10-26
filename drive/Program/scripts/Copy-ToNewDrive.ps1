<#
    Copy-ToNewDrive.ps1
    ---------------------------------------------------------------------------
    Copies EVERYTHING on this external drive onto a new drive, exactly as it
    is, then checks the copy file by file.

      - The drive it copies FROM is whichever drive this script is sitting
        on. No drive letter is written down anywhere.
      - The drive it copies TO is picked from a list, by typing its letter.
      - Nothing on either drive is ever deleted. Files already on the new
        drive with the same name and place are replaced with this drive's
        copy; anything else already on the new drive is left alone.
      - Uses Windows' own robocopy: retries on a hiccup, keeps the dates on
        every file, and can be run again after an interruption - the second
        run only copies what is missing or different.
      - Keeps the computer awake while it runs, then lets it sleep again.
      - After copying it checks every file against the original, rebuilds
        the two icons at the top of the new drive so they point at the NEW
        drive, and saves its log into the new drive's archive folder.

    RULES HONOURED HERE (see the customization record):
      - no drive letters; everything derives from this script's location
      - no $PSScriptRoot inside a param() block
      - written for Windows PowerShell 5.1, pure ASCII
      - refuses to run while RetroBat or an emulator is open

    Run it from:  Buttons\Copy This Drive To A New Drive.bat
#>

$ErrorActionPreference = 'Stop'

function Say {
    param([string] $Text = '', [string] $Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
}
function GB {
    param([double] $Bytes)
    return ('{0:N0} GB' -f ($Bytes / 1GB))
}
function Quit {
    param([string] $Text, [int] $Code = 1)
    Say ''
    if ($Code -eq 0) { Say $Text 'Yellow' } else { Say $Text 'Red' }
    Say ''
    exit $Code
}

# ---------------------------------------------------------------------------
# Where are we?
# ---------------------------------------------------------------------------
$workspace   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # _Wizard
$retrobatDir = Split-Path $workspace -Parent               # the RetroBat folder
$srcRoot     = [System.IO.Path]::GetPathRoot($retrobatDir) # the drive, e.g. X:\
$relRetroBat = $retrobatDir.Substring($srcRoot.Length).TrimStart('\')

if ($srcRoot -notmatch '^[A-Za-z]:\\$') {
    Quit '   This has to be run from the external drive itself, not a network folder.'
}
if ($srcRoot.TrimEnd('\') -eq $env:SystemDrive) {
    Quit ('   RetroBat is sitting on this computer''s own ' + $env:SystemDrive + ' drive, not an external one.' +
          "`n   This button copies a whole external drive, so it will not run from here.")
}

$src = New-Object System.IO.DriveInfo($srcRoot)
$srcUsed  = [double]($src.TotalSize - $src.TotalFreeSpace)
$srcLabel = if ($src.VolumeLabel) { $src.VolumeLabel } else { '(no name)' }

Say ''
Say '   COPY THIS DRIVE TO A NEW DRIVE' 'Cyan'
Say ''
Say ('   This drive:  ' + $srcRoot.Substring(0,2) + '   ' + $srcLabel + '   about ' + (GB $srcUsed) + ' of files')
Say ''

# ---------------------------------------------------------------------------
# Nothing may be running. A game writing a save mid-copy would leave the new
# drive with half a file.
# ---------------------------------------------------------------------------
$busy = @(Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui', 'emulatorLauncher',
                            'retroarch', 'dolphin', 'cemu', 'azahar', 'melonDS' -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    $names = ($busy | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Quit ('   Close RetroBat first (still open: ' + $names + '), then run this again.')
}

# ---------------------------------------------------------------------------
# Pick the new drive
# ---------------------------------------------------------------------------
$candidates = @([System.IO.DriveInfo]::GetDrives() | Where-Object {
    $_.IsReady -and
    ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and
    $_.Name -ne $srcRoot -and
    $_.Name.TrimEnd('\') -ne $env:SystemDrive
})

if ($candidates.Count -eq 0) {
    Quit '   No other drive found. Plug the new drive in, wait for it to show up in File Explorer, and run this again.'
}

Say '   Drives you can copy to:'
Say ''
foreach ($d in $candidates) {
    $label = if ($d.VolumeLabel) { $d.VolumeLabel } else { '(no name)' }
    Say ('     {0}   {1,-26} {2,-6} {3,9} total {4,9} free' -f $d.Name.Substring(0,2), $label, $d.DriveFormat,
         (GB $d.TotalSize), (GB $d.AvailableFreeSpace)) 'White'
}
Say ''

$dest = $null
while ($null -eq $dest) {
    $answer = Read-Host '   Type the LETTER of the NEW drive and press Enter (or just press Enter to cancel)'
    $answer = ([string]$answer).Trim().TrimEnd('\').TrimEnd(':').ToUpper()
    if ($answer -eq '') { Quit '   Cancelled. Nothing was copied.' 0 }
    $dest = $candidates | Where-Object { $_.Name.Substring(0,1).ToUpper() -eq $answer } | Select-Object -First 1
    if ($null -eq $dest) { Say ('   "' + $answer + '" is not one of the drives listed above. Try again.') 'Yellow' }
}

$destRoot  = $dest.Name
$destLabel = if ($dest.VolumeLabel) { $dest.VolumeLabel } else { '(no name)' }

# ---------------------------------------------------------------------------
# Checks on the new drive
# ---------------------------------------------------------------------------
$useFft = $false
switch ($dest.DriveFormat) {
    'NTFS'  { }
    'exFAT' { $useFft = $true }   # exFAT keeps file times to 2 seconds; /FFT allows for that
    default {
        Quit ('   The new drive is formatted ' + $dest.DriveFormat + ', which cannot hold files bigger than 4 GB' +
              "`n   (several games here are bigger than that). Reformat it as NTFS first, then run this again.")
    }
}

$skipNames = @('System Volume Information', '$RECYCLE.BIN')
$already   = @(Get-ChildItem -LiteralPath $destRoot -Force -ErrorAction SilentlyContinue |
               Where-Object { $skipNames -notcontains $_.Name })
$resuming  = Test-Path -LiteralPath (Join-Path $destRoot $relRetroBat)

if (-not $resuming -and [double]$dest.AvailableFreeSpace -lt ($srcUsed + 1GB)) {
    Quit ('   Not enough room. This drive has about ' + (GB $srcUsed) + ' of files and the new drive has ' +
          (GB $dest.AvailableFreeSpace) + ' free.')
}

Say ''
Say ('   FROM:  ' + $srcRoot.Substring(0,2) + '   ' + $srcLabel + '   (about ' + (GB $srcUsed) + ')') 'White'
Say ('   TO:    ' + $destRoot.Substring(0,2) + '   ' + $destLabel + '   (' + (GB $dest.AvailableFreeSpace) + ' free)') 'White'
Say ''
Say '   Everything on the FROM drive is copied. Nothing on either drive is deleted.'
if ($resuming) {
    Say '   The new drive already has a RetroBat folder, so this looks like a copy that' 'Yellow'
    Say '   was started before. Only files that are missing or different get copied.' 'Yellow'
}
elseif ($already.Count -gt 0) {
    Say ('   The new drive already has ' + $already.Count + ' thing(s) at its top level. They stay, but any') 'Yellow'
    Say '   file with the same name in the same place gets replaced by this drive''s copy.' 'Yellow'
}
Say ''
Say '   It can take a few hours. Leave both drives plugged in until it says DONE.'
Say '   If it gets interrupted, just run this button again - it picks up where it left off.'
Say ''
$go = Read-Host '   Type COPY and press Enter to start (anything else cancels)'
if (([string]$go).Trim() -ne 'COPY') { Quit '   Cancelled. Nothing was copied.' 0 }

# ---------------------------------------------------------------------------
# Keep the computer awake while this runs. A computer that goes to sleep
# halfway through a copy is the most likely way for this to fail.
# ---------------------------------------------------------------------------
$awake = $false
try {
    Add-Type -Namespace RetroBatCopy -Name Power -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
    # 2147483649 = ES_CONTINUOUS (0x80000000) + ES_SYSTEM_REQUIRED (0x1).
    # Written in decimal because PowerShell 5.1 reads 0x80000001 as a negative number.
    [void][RetroBatCopy.Power]::SetThreadExecutionState([uint32]2147483649)
    $awake = $true
}
catch { Say '   (Could not stop the computer sleeping. Keep it awake yourself.)' 'Yellow' }

# ---------------------------------------------------------------------------
# The copy
# ---------------------------------------------------------------------------
$robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
$stamp    = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$log      = Join-Path $env:TEMP ('drive-copy_' + $stamp + '.log')

# /E    every folder, empty ones included      /XJ  never follow a folder link
# /R:3 /W:5  retry a file 3 times, 5 s apart   /XD  skip Windows' own hidden folders
$common = @('/E', '/XJ', '/R:3', '/W:5', '/XD') + $skipNames
if ($useFft) { $common += '/FFT' }

Say ''
Say '   Copying. File names will scroll past - that is it working.' 'Cyan'
Say '   A big game file can sit on one line for several minutes. That is normal too.' 'Cyan'
Say ''
$started = Get-Date

$copyArgs = @($srcRoot, $destRoot) + $common + @('/COPY:DAT', '/DCOPY:T', '/MT:8', '/NP', '/TEE', ('/LOG:' + $log))
& $robocopy @copyArgs
$copyCode = $LASTEXITCODE

# ---------------------------------------------------------------------------
# The check. A second pass in list-only mode: robocopy compares every file's
# size and date against the original and names any that still differ.
# /XX leaves out things that exist only on the new drive - those are not ours.
# ---------------------------------------------------------------------------
Say ''
Say '   Checking every file on the new drive against the original...' 'Cyan'
$verifyArgs = @($srcRoot, $destRoot) + $common + @('/L', '/XX', '/NJH', '/NJS', '/NDL', '/NP')
$verifyOut  = @(& $robocopy @verifyArgs)
$verifyCode = $LASTEXITCODE
$different  = @($verifyOut | Where-Object { $_ -and $_.Trim() -ne '' })

try {
    Add-Content -LiteralPath $log -Value ''
    Add-Content -LiteralPath $log -Value ('==== CHECK PASS, exit code ' + $verifyCode + ', ' + $different.Count + ' line(s) ====')
    if ($different.Count -gt 0) { Add-Content -LiteralPath $log -Value $different }
}
catch { }

if ($awake) { try { [void][RetroBatCopy.Power]::SetThreadExecutionState([uint32]2147483648) } catch { } }

# Robocopy exit codes are a set of flags: 1 copied, 2 extra, 4 mismatched,
# 8 failed, 16 fatal. Anything 8 or over means something did not make it.
$verified = (($verifyCode -band 29) -eq 0) -and ($different.Count -eq 0)

# ---------------------------------------------------------------------------
# Rebuild the two icons at the top of the new drive. The copied ones still
# point at THIS drive's letter, so on a computer with both drives plugged in
# they would open the OLD drive. The new drive's own Shortcuts.ps1 builds
# them fresh, pointing at wherever the new drive is right now.
# ---------------------------------------------------------------------------
$destRetroBat = Join-Path $destRoot $relRetroBat
$iconsNote = ''
if ($verified) {
    try {
        $lib = Join-Path $destRetroBat '_Wizard\Program\scripts\Shortcuts.ps1'
        if (Test-Path -LiteralPath $lib) {
            . $lib
            $wizName = 'Setup Wizard'
            $ini = Join-Path $destRetroBat '_Wizard\Settings\wizard.ini'
            if (Test-Path -LiteralPath $ini) {
                foreach ($line in [System.IO.File]::ReadAllLines($ini)) {
                    if ($line -match '^\s*name\s*=\s*(.+?)\s*$') { $wizName = $Matches[1]; break }
                }
            }
            $r = Update-RootShortcuts -Root $destRetroBat -WizardName $wizName
            if ($r -and -not $r.Problem) { $iconsNote = 'The two icons at the top of the new drive now point at the new drive.' }
        }
    }
    catch { }
    if (-not $iconsNote) { $iconsNote = 'The first time, open the RetroBat folder and use PLAY.bat - that rebuilds the icons.' }
}

# ---------------------------------------------------------------------------
# Keep the log with the drive it describes
# ---------------------------------------------------------------------------
$logHome = $log
try {
    $archive = Join-Path $destRetroBat '_Wizard\Backups\Archive'
    if (Test-Path -LiteralPath $archive) {
        $kept = Join-Path $archive ('drive-copy_' + $stamp + '.log')
        Copy-Item -LiteralPath $log -Destination $kept -Force
        $logHome = $kept
    }
}
catch { }

# ---------------------------------------------------------------------------
# The verdict
# ---------------------------------------------------------------------------
$took = (Get-Date) - $started
$tookText = '{0} h {1} min' -f [int][math]::Floor($took.TotalHours), $took.Minutes

Say ''
Say '   ---------------------------------------------------------------------'
if ($verified) {
    Say '   DONE. Every file is on the new drive and matches the original.' 'Green'
    Say ('   Took ' + $tookText + '.')
    Say ''
    Say '   What to do now:' 'White'
    Say '     1. Close this window.'
    Say '     2. Safely eject BOTH drives (the USB icon by the clock, then Eject).'
    Say '     3. Put the old drive somewhere safe and leave it as it is for a couple'
    Say '        of weeks. It is your backup until the new one has proven itself.'
    Say '     4. Plug in only the new drive and play as normal.'
    Say ('        ' + $iconsNote)
    Say '     5. Open the Setup Wizard once. All the lights should be green.'
}
else {
    if ($copyCode -ge 8 -or ($verifyCode -band 24) -ne 0) {
        Say '   NOT FINISHED. Some files could not be copied.' 'Red'
    }
    else {
        Say ('   NOT FINISHED. ' + $different.Count + ' file(s) on the new drive do not match the original yet.') 'Red'
    }
    Say ''
    Say '   Run this button again - it only copies what is still missing or different.'
    Say '   If it fails in the same place twice, the file named in the log is the'
    Say '   problem, and a different USB port or cable is the first thing to try.'
    Say '   Do NOT wipe or reuse the old drive.' 'Yellow'
}
Say ''
Say ('   The full log is at: ' + $logHome)
Say '   ---------------------------------------------------------------------'
Say ''
if ($verified) { exit 0 } else { exit 1 }
