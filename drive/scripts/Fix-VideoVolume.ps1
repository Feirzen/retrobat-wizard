<#
    Fix-VideoVolume.ps1
    ---------------------------------------------------------------------------
    Keeps every video on this setup at a sensible, consistent volume.

    THERE ARE THREE KINDS OF VIDEO HERE

      1. GAME PREVIEW VIDEOS   roms\<system>\videos\*.mp4
         The little clips that play when a game is highlighted, and what the
         idle screen shows. Target: -24 LUFS.

      2. MENU VIDEOS           the console clip behind each system, and behind
         each collection, on the main menu. These live inside the theme.
         Target: -20 LUFS, deliberately a bit louder than the previews.

      3. INTRO VIDEOS          emulationstation\.emulationstation\video\*.mp4
         The video RetroBat plays while it is starting up, before the menu
         appears. RandomVideo=1 in retrobat.ini picks a different one every
         boot, so they have to match each other or the drive greets you at a
         different volume each time. Target: -20 LUFS, the same as the menu
         videos, because the intro hands straight over to the menu.

    WHY THIS EXISTS

    EmulationStation has no volume slider for any of these - only a mute
    switch - so the volume has to live in the video files themselves. Scraped
    and theme videos arrive anywhere from -8 to -48 LUFS, which is why the menu
    felt like it was shouting at random.

    Every video is measured and, if it is off target, re-recorded at the right
    level with a gentle fade-in. Only the sound is touched. The picture is
    copied across untouched, so nothing loses quality.

    WHAT IT DOES NOT DO

    It does not re-do work. Once a video has been checked it goes in a list,
    and on the next run it is skipped instantly unless the file itself has
    changed. So the first run takes a minute and every run after that is
    basically instant. That is why it is safe to have this in the
    RUN THIS AFTER AN UPDATE button.

    Only menu videos for systems that ACTUALLY HAVE GAMES are touched. The
    theme ships 400+ of them and there is no reason to sit through the rest.
    Add a new system later and the next run picks it up on its own.

    THE FULL RE-CHECK

    To force every video to be measured again from scratch, delete
        _ClaudeWorkspace\tools\video-loudness-checked.txt
    and run this again. Changing either target number below does this for you
    automatically - the target is part of what gets remembered.

    RETROBAT MUST BE CLOSED. EmulationStation keeps videos open while it is
    running and the files cannot be replaced underneath it.

    Run it from:  Fix Video Volume.bat
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Recheck,        # ignore the checked-list and measure everything again
    [switch]$PreviewsOnly,   # skip the menu videos
    [switch]$MenuOnly,       # skip the game preview videos
    [int]$Parallel = 0       # 0 = decide automatically from the CPU
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# ===========================================================================
#  THE TARGETS - edit these numbers if you want it louder or quieter
# ===========================================================================
#  Loudness is measured in LUFS. It is a negative number, and MORE negative
#  means QUIETER. Every 3 dB up is roughly 1.4x the volume. For reference:
#
#      -16   about as loud as a normal YouTube video
#      -20   the intro videos and the menu videos
#      -24   the game previews
#      -36   very faint
#
#  History: these started at -26 and -22, which turned out to be noticeably
#  quieter than the games themselves, so both were raised by 2 dB (about 1.25x)
#  on 2026-08-25. The gap between the two was kept the same, so everything
#  stays balanced against everything else. If it is still too quiet, another
#  2 off each number is the same size step again.
#
#  Tolerance is how far off a video is allowed to be before it gets fixed.
#  This was 2.5, on the theory that nobody notices a difference that small.
#  In practice they do: 2.5 either side is a 5 dB spread across the library,
#  which is loud enough to be annoying when a new video starts every 30
#  seconds. 1.0 keeps everything inside a 2 dB window, which really is below
#  what you can pick out.
#
#  The cost of a tight tolerance is that changing a target above re-records
#  nearly everything once. That is a minute of your time and one extra pass
#  of audio compression, which nobody can hear on a 30-second game clip. The
#  untouched originals are kept in _ClaudeWorkspace\archive\ if you ever want
#  to start clean.
# ---------------------------------------------------------------------------
#  The intro target was not picked out of the air. The four intro videos that
#  were already on the drive were measured on 2026-08-27 and came out at
#  -17.7, -29.8, -22.5 and -11.1 LUFS: an 18.7 dB spread, so one boot
#  whispered and the next one shouted. Their average was about -20.3, so -20
#  keeps the set roughly where it already sits rather than making the whole
#  boot louder or quieter, while pulling the outliers into line with each
#  other. It also matches the menu videos exactly, which is the relationship
#  that matters most: the intro hands straight over to the menu, so a jump
#  between those two would be the most noticeable one on the drive.
$PreviewTargetLufs = -24.0
$MenuTargetLufs    = -20.0
$IntroTargetLufs   = -20.0
$Tolerance         = 1.0

#  How long the sound takes to come up when a video starts, in seconds.
#  This is what stops the menu being a jump-scare.
$FadeInSeconds = 1.5
# ===========================================================================


# --- locate RetroBat -------------------------------------------------------
# This script lives in <RetroBat>\_ClaudeWorkspace\scripts\
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    Write-Host "       This script must stay in <RetroBat>\_ClaudeWorkspace\scripts\." -ForegroundColor Red
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
    if (-not (Test-Feature $Root 'videovolume')) {
        Say ""
        Say (Get-FeatureOffMessage 'videovolume') 'Yellow'
        Say "Turn it back on in the Features tab, or in features.ini." 'DarkGray'
        Say ""
        exit 0
    }
}

$RomsDir    = Join-Path $Root 'roms'
$ToolsDir   = Join-Path $Root '_ClaudeWorkspace\tools'
$ArchiveDir = Join-Path $Root '_ClaudeWorkspace\archive'
$LedgerPath = Join-Path $ToolsDir 'video-loudness-checked.txt'
$EsDir      = Join-Path $Root 'emulationstation\.emulationstation'

# --- refuse to run while RetroBat is open ----------------------------------
$running = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Write-Host "  RetroBat is currently running." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Close it completely, then run this again." -ForegroundColor Yellow
    Write-Host "  (EmulationStation holds videos open while it is up, so they" -ForegroundColor Gray
    Write-Host "   cannot be replaced underneath it.)" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Say ""
Say "RetroBat found at: $Root" 'Cyan'
Say ""

# ===========================================================================
#  FIND FFMPEG
# ===========================================================================
#  ffmpeg is the tool that measures and re-records the sound. A copy of it
#  lives on this drive at
#      _ClaudeWorkspace\tools\ffmpeg.exe
#  so this works on any computer with no installing and no internet. Its
#  licence sits next to it as ffmpeg-LICENSE.txt.
# ---------------------------------------------------------------------------
$FFmpeg = Join-Path $ToolsDir 'ffmpeg.exe'

if (-not (Test-Path $FFmpeg)) {
    $onPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($onPath) {
        $FFmpeg = $onPath.Source
        Say "Using the ffmpeg already installed on this computer:" 'Yellow'
        Say "  $FFmpeg" 'DarkGray'
        Say ""
    }
    else {
        Write-Host ""
        Write-Host "  ERROR: ffmpeg could not be found." -ForegroundColor Red
        Write-Host ""
        Write-Host "  It should be at:" -ForegroundColor Yellow
        Write-Host "    _ClaudeWorkspace\tools\ffmpeg.exe" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  To put it back, download the 'essentials' Windows build from" -ForegroundColor Yellow
        Write-Host "  https://www.gyan.dev/ffmpeg/builds/ and copy ffmpeg.exe from" -ForegroundColor Gray
        Write-Host "  inside its bin folder to the path above. Nothing else is needed." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Nothing has been changed." -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

# ===========================================================================
#  HELPERS
# ===========================================================================
function ConvertTo-CmdArg([string]$a) {
    # Windows hands a program one long string, not a list, so anything with a
    # space in it has to be wrapped in quotes and any quote inside it escaped.
    # Game filenames are full of spaces, commas and brackets, so this matters.
    if ($a -eq '') { return '""' }
    if ($a -notmatch '[\s"]') { return $a }
    $s = [regex]::Replace($a, '(\\*)"', '$1$1\"')
    $s = [regex]::Replace($s, '(\\+)$', '$1$1')
    return '"' + $s + '"'
}

function Join-FFArgs([string[]]$FFArgs) {
    ($FFArgs | ForEach-Object { ConvertTo-CmdArg $_ }) -join ' '
}

function Invoke-FFmpeg {
    # Runs one ffmpeg and waits for it. Used for the re-recording pass.
    param([string[]]$FFArgs)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FFmpeg
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    # NOTE: built as one quoted string on purpose. The newer ArgumentList
    # property does not exist in the Windows PowerShell that ships with
    # Windows, and using it here would break the script on a clean machine.
    $psi.Arguments = Join-FFArgs $FFArgs

    $proc = [System.Diagnostics.Process]::Start($psi)
    # Read both streams before waiting, or a chatty ffmpeg can fill the pipe
    # buffer and deadlock waiting for someone to empty it.
    $err  = $proc.StandardError.ReadToEnd()
    $null = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $err }
}

function Get-LoudnessArgs([string]$Path, [double]$Target) {
    # -vn is the important one. Without it ffmpeg decodes every frame of
    # picture just to read the sound, which is the entire reason the old
    # version of this script took minutes instead of seconds.
    @(
        '-nostdin', '-hide_banner', '-nostats', '-vn',
        '-i', $Path,
        '-af', ("aformat=channel_layouts=stereo,loudnorm=I=" + $Target + ":TP=-2:LRA=11:print_format=json"),
        '-f', 'null', 'NUL'
    )
}

function Read-LoudnessJson([string]$Text) {
    $grab = {
        param($key)
        $m = [regex]::Match($Text, '"' + $key + '"\s*:\s*"([^"]+)"')
        if ($m.Success) { $m.Groups[1].Value } else { $null }
    }
    $i = & $grab 'input_i'
    if (-not $i) { return $null }
    if ($i -notmatch '^-?\d+(\.\d+)?$') { return $null }   # ffmpeg prints -inf for silence

    [pscustomobject]@{
        I      = [double]$i
        TP     = & $grab 'input_tp'
        LRA    = & $grab 'input_lra'
        Thresh = & $grab 'input_thresh'
        Offset = & $grab 'target_offset'
    }
}

# ===========================================================================
#  MEASURE A WHOLE BATCH AT ONCE
# ===========================================================================
#  Measuring is the slow part and one ffmpeg only uses a fraction of the
#  machine, so several are run side by side. Each one writes what it found to
#  its own little temp file, which sidesteps the classic deadlock you get when
#  you try to read from a lot of programs through pipes at the same time.
# ---------------------------------------------------------------------------
function Measure-Batch {
    param(
        [object[]]$Jobs,          # each: @{ Path=; Target=; Label= }
        [int]$MaxParallel
    )

    $queue   = New-Object System.Collections.Queue
    foreach ($j in $Jobs) { $queue.Enqueue($j) }

    $running = New-Object System.Collections.ArrayList
    $out     = @{}
    $done    = 0
    $total   = $Jobs.Count
    $lastMsg = -1

    while ($queue.Count -gt 0 -or $running.Count -gt 0) {

        while ($running.Count -lt $MaxParallel -and $queue.Count -gt 0) {
            $j       = $queue.Dequeue()
            $errFile = [System.IO.Path]::GetTempFileName()
            $p = Start-Process -FilePath $FFmpeg `
                               -ArgumentList (Join-FFArgs (Get-LoudnessArgs $j.Path $j.Target)) `
                               -NoNewWindow -PassThru -RedirectStandardError $errFile
            [void]$running.Add([pscustomobject]@{ Job = $j; Proc = $p; Err = $errFile })
        }

        Start-Sleep -Milliseconds 120

        $finished = @($running | Where-Object { $_.Proc.HasExited })
        foreach ($f in $finished) {
            $text = ''
            try { $text = [System.IO.File]::ReadAllText($f.Err) } catch { }
            Remove-Item $f.Err -Force -ErrorAction SilentlyContinue
            $out[$f.Job.Path] = Read-LoudnessJson $text
            [void]$running.Remove($f)
            $done++
        }

        # A progress line every 10, so a long first run does not look frozen.
        if ($done -ne $lastMsg -and ($done % 10 -eq 0) -and $done -gt 0) {
            Say ("    measured {0} of {1}..." -f $done, $total) 'DarkGray'
            $lastMsg = $done
        }
    }

    return $out
}

# ===========================================================================
#  THE CHECKED-LIST
# ===========================================================================
#  One line per video: the path, its size, when it was last written, and the
#  target AND tolerance it was checked against. If all five still match, the
#  video has not changed since it was checked and there is no reason to measure
#  it again.
#
#  Recording the target and the tolerance is what makes the numbers at the top
#  of this file safe to edit: change either one and everything re-checks itself
#  on the next run, with nothing for you to remember and nothing to delete.
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null

$checked = @{}
if ((Test-Path $LedgerPath) -and (-not $Recheck)) {
    foreach ($line in [System.IO.File]::ReadAllLines($LedgerPath)) {
        if ($line.Trim()) { $checked[$line] = $true }
    }
}

function Get-Key([string]$FullPath, [double]$Target) {
    $f   = Get-Item -LiteralPath $FullPath
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
    "$rel|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)|$Target|$Tolerance"
}

# ===========================================================================
#  BUILD THE WORK LIST
# ===========================================================================

$work = New-Object System.Collections.ArrayList

# --- 1. game preview videos ------------------------------------------------
if (-not $MenuOnly) {
    $previews = @(Get-ChildItem -Path $RomsDir -Directory -ErrorAction SilentlyContinue |
                  ForEach-Object { Join-Path $_.FullName 'videos' } |
                  Where-Object { Test-Path $_ } |
                  ForEach-Object { Get-ChildItem -Path $_ -File -Include *.mp4,*.webm,*.mkv -Recurse -ErrorAction SilentlyContinue })

    foreach ($p in $previews) {
        [void]$work.Add([pscustomobject]@{
            Path   = $p.FullName
            Target = $PreviewTargetLufs
            Kind   = 'preview'
            Label  = (Split-Path (Split-Path $p.FullName -Parent) -Parent | Split-Path -Leaf) + '\' + $p.Name
        })
    }
}

# --- 2. menu videos --------------------------------------------------------
#  Which theme is in use comes from es_settings.cfg. Which systems are on the
#  menu is worked out from which roms folders actually have something in them.
#  The file name of a system's menu video is its <theme> name from
#  es_systems.cfg, which is NOT always the folder name - gamecube uses gc.mp4.
# ---------------------------------------------------------------------------
if (-not $PreviewsOnly) {

    $themeName = $null
    $esSettings = Join-Path $EsDir 'es_settings.cfg'
    if (Test-Path $esSettings) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($esSettings), '<string name="ThemeSet" value="([^"]+)"')
        if ($m.Success) { $themeName = $m.Groups[1].Value }
    }

    $themeDir = $null
    if ($themeName) {
        $candidate = Join-Path $EsDir "themes\$themeName"
        if (Test-Path $candidate) { $themeDir = $candidate }
    }

    if (-not $themeDir) {
        Say "Could not work out which theme is in use - skipping the menu videos." 'Yellow'
        Say ""
    }
    else {
        Say ("Theme in use: {0}" -f $themeName) 'DarkGray'

        # every video file in the theme, indexed by its name without extension
        $themeVideos = @{}
        foreach ($v in (Get-ChildItem -Path $themeDir -File -Include *.mp4,*.webm,*.mkv -Recurse -ErrorAction SilentlyContinue)) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($v.Name).ToLower()
            if (-not $themeVideos.ContainsKey($key)) { $themeVideos[$key] = $v.FullName }
        }

        # which names do we actually need?
        $wanted = New-Object System.Collections.Generic.List[string]

        # systems that have games in them
        $esSystems = Join-Path $EsDir 'es_systems.cfg'
        if (Test-Path $esSystems) {
            $sysText = [System.IO.File]::ReadAllText($esSystems)
            foreach ($blk in [regex]::Matches($sysText, '(?s)<system>(.*?)</system>')) {
                $b  = $blk.Groups[1].Value
                $nm = [regex]::Match($b, '<name>(.*?)</name>')
                $th = [regex]::Match($b, '<theme>(.*?)</theme>')
                if (-not $nm.Success) { continue }

                $romDir = Join-Path $RomsDir $nm.Groups[1].Value
                if (-not (Test-Path $romDir)) { continue }

                # anything in there that is not scraper furniture counts as a game
                $hasGames = @(Get-ChildItem -Path $romDir -Force -ErrorAction SilentlyContinue |
                              Where-Object { $_.Name -notin @('videos','images','manuals','media','gamelist.xml') -and
                                             -not $_.Name.StartsWith('.') -and
                                             $_.Extension -notin @('.txt','.xml') }).Count -gt 0
                if (-not $hasGames) { continue }

                $wanted.Add(($(if ($th.Success) { $th.Groups[1].Value } else { $nm.Groups[1].Value })).ToLower())
            }
        }

        # custom collections
        $collDir = Join-Path $EsDir 'collections'
        if (Test-Path $collDir) {
            foreach ($c in (Get-ChildItem -Path $collDir -Filter 'custom-*.cfg' -File -ErrorAction SilentlyContinue)) {
                $wanted.Add(($c.BaseName -replace '^custom-', '').ToLower())
            }
        }

        # the built-in ones EmulationStation adds by itself
        foreach ($auto in @('auto-favorites','auto-lastplayed','auto-allgames','favorites','recent')) {
            $wanted.Add($auto)
        }

        $seen = @{}
        foreach ($w in $wanted) {
            if ($seen.ContainsKey($w)) { continue }
            $seen[$w] = $true
            if (-not $themeVideos.ContainsKey($w)) { continue }
            [void]$work.Add([pscustomobject]@{
                Path   = $themeVideos[$w]
                Target = $MenuTargetLufs
                Kind   = 'menu'
                Label  = 'menu\' + (Split-Path $themeVideos[$w] -Leaf)
            })
        }
    }
}

if ($work.Count -eq 0) {
    Say "No videos found to check - nothing to do." 'Yellow'
    Say ""
    exit 0
}

# --- 3. intro videos -------------------------------------------------------
#  The videos RetroBat plays while it is starting up, in
#  emulationstation\.emulationstation\video\.
#
#  Nothing here needs changing when you add one. Drop a new .mp4 into that
#  folder and the next run of this script finds it, measures it and brings it
#  into line with the rest on its own.
if (-not $MenuOnly -and -not $PreviewsOnly) {
    $introDir = Join-Path $EsDir 'video'
    if (Test-Path $introDir) {
        $intros = @(Get-ChildItem -Path $introDir -File -Include *.mp4,*.webm,*.mkv -Recurse -ErrorAction SilentlyContinue)
        foreach ($i in $intros) {
            [void]$work.Add([pscustomobject]@{
                Path   = $i.FullName
                Target = $IntroTargetLufs
                Kind   = 'intro'
                Label  = 'intro\' + $i.Name
            })
        }
    }
}

# --- what still needs measuring --------------------------------------------
$toCheck = @($work | Where-Object { -not $checked.ContainsKey((Get-Key $_.Path $_.Target)) })

$nPrev = @($work | Where-Object { $_.Kind -eq 'preview' }).Count
$nMenu = @($work | Where-Object { $_.Kind -eq 'menu' }).Count
$nIntro = @($work | Where-Object { $_.Kind -eq 'intro' }).Count

Say ""
Say ("Game preview videos : {0}   (target {1} LUFS)" -f $nPrev, $PreviewTargetLufs) 'White'
Say ("Menu videos         : {0}   (target {1} LUFS)" -f $nMenu, $MenuTargetLufs) 'White'
Say ("Intro videos        : {0}   (target {1} LUFS)" -f $nIntro, $IntroTargetLufs) 'White'
Say ("Already checked     : {0}" -f ($work.Count - $toCheck.Count)) 'DarkGray'
Say ("To measure now      : {0}" -f $toCheck.Count) 'White'
Say ""

if ($toCheck.Count -eq 0) {
    Say "Everything is already at the right volume. Nothing to do." 'Green'
    Say ""
    exit 0
}

# --- how many at once ------------------------------------------------------
if ($Parallel -le 0) {
    $cpu = 4
    try { $cpu = [int]$env:NUMBER_OF_PROCESSORS } catch { }
    if ($cpu -lt 1) { $cpu = 4 }
    $Parallel = [Math]::Max(2, [Math]::Min(8, $cpu))
}
Say ("Measuring {0} at a time." -f $Parallel) 'DarkGray'
Say ""

$measured = Measure-Batch -Jobs $toCheck -MaxParallel $Parallel

Say ""

# --- where backups go ------------------------------------------------------
$stamp      = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupPrev = Join-Path $ArchiveDir "gamevideos-original-$stamp"
$backupMenu = Join-Path $ArchiveDir "menuvideos-original-$stamp"
$backupIntro = Join-Path $ArchiveDir "introvideos-original-$stamp"

function Test-AlreadyBackedUp {
    # True only if an earlier run already saved a copy of THIS exact file.
    # The size has to match too, otherwise a re-scraped video would be skipped
    # because an older, different video of the same name was once backed up.
    param([string]$Prefix, [string]$SubFolder, [string]$FileName, [long]$Size)
    foreach ($h in (Get-ChildItem -Path $ArchiveDir -Directory -Filter "$Prefix-*" -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path $h.FullName (Join-Path $SubFolder $FileName)
        if ((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate).Length -eq $Size)) {
            return $true
        }
    }
    return $false
}

# --- re-record what needs it -----------------------------------------------
$okAlready = 0
$fixed     = 0
$failed    = 0
$n         = 0
$newlyChecked = New-Object System.Collections.Generic.List[string]

foreach ($j in $toCheck) {
    $n++
    $label = "[{0}/{1}] {2}" -f $n, $toCheck.Count, $j.Label
    $m     = $measured[$j.Path]

    if ($null -eq $m) {
        Say ("  SKIPPED  $label") 'Yellow'
        Say  "           (no readable sound track)" 'DarkGray'
        $failed++
        continue
    }

    $diff = [math]::Abs($m.I - $j.Target)
    if ($diff -le $Tolerance) {
        Say ("  ok       $label  ({0} LUFS)" -f $m.I) 'DarkGray'
        $okAlready++
        $newlyChecked.Add((Get-Key $j.Path $j.Target))
        continue
    }

    $file   = Get-Item -LiteralPath $j.Path
    switch ($j.Kind) {
        'menu'  {
            $prefix = 'menuvideos-original';  $subFol = 'theme'; $destRt = $backupMenu
        }
        'intro' {
            $prefix = 'introvideos-original'; $subFol = 'video'; $destRt = $backupIntro
        }
        default {
            $prefix = 'gamevideos-original'
            $subFol = Split-Path (Split-Path $file.FullName -Parent) -Parent | Split-Path -Leaf
            $destRt = $backupPrev
        }
    }

    # --- back up the original, once and only once --------------------------
    if (-not (Test-AlreadyBackedUp $prefix $subFol $file.Name $file.Length)) {
        $dest = Join-Path $destRt $subFol
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $file.Name) -Force
    }

    $filter = "loudnorm=I=" + $j.Target + ":TP=-2:LRA=11" +
              ":measured_I=$($m.I):measured_TP=$($m.TP):measured_LRA=$($m.LRA)" +
              ":measured_thresh=$($m.Thresh):offset=$($m.Offset):linear=true" +
              ",afade=t=in:st=0:d=" + $FadeInSeconds +
              ",aformat=channel_layouts=stereo,aresample=48000"

    $tmp = Join-Path $env:TEMP ("fvv_" + [guid]::NewGuid().ToString('N') + $file.Extension)

    # First try: keep the picture exactly as it is, only redo the sound.
    $r = Invoke-FFmpeg @(
        '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
        '-i', $file.FullName, '-af', $filter,
        '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart', $tmp
    )

    # A few videos have broken timestamps and refuse the copy. Redo the
    # picture as well for those - slower, and visually identical.
    if ($r.ExitCode -ne 0 -or -not (Test-Path $tmp)) {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        $r = Invoke-FFmpeg @(
            '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
            '-fflags', '+genpts', '-i', $file.FullName, '-af', $filter,
            '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
            '-pix_fmt', 'yuv420p', '-ac', '2', '-c:a', 'aac', '-b:a', '128k',
            '-movflags', '+faststart', $tmp
        )
    }

    if ($r.ExitCode -ne 0 -or -not (Test-Path $tmp)) {
        Say ("  FAILED   $label") 'Red'
        $firstLine = ($r.Output -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($firstLine) { Say ("           $firstLine") 'DarkGray' }
        $failed++
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        continue
    }

    try {
        Copy-Item -LiteralPath $tmp -Destination $file.FullName -Force
        Say ("  FIXED    $label") 'Green'
        Say ("           {0} LUFS -> {1} LUFS, {2}s fade-in" -f $m.I, $j.Target, $FadeInSeconds) 'DarkGray'
        $fixed++
        $newlyChecked.Add((Get-Key $j.Path $j.Target))
    }
    catch {
        Say ("  FAILED   $label") 'Red'
        Say ("           could not write the new file: $($_.Exception.Message)") 'DarkGray'
        $failed++
    }
    finally {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# --- save the checked-list -------------------------------------------------
if ($newlyChecked.Count -gt 0) {
    # An entry is "<relative path>|size|timestamp|target|tolerance", so a
    # video that gets RE-recorded produces a brand new key and its old key
    # would sit on this list forever. Those orphans are not harmless: the
    # drive health check walks every menu entry on the list and compares it
    # to the live file, so each orphan showed up as "changed since it was
    # levelled" and kept the video volume light yellow for good. Any old
    # entry for a file checked on this run is dropped.
    $freshPaths = @{}
    foreach ($k in $newlyChecked) { $freshPaths[$k.Split('|')[0]] = $true }
    $all = New-Object System.Collections.Generic.List[string]
    foreach ($k in $checked.Keys) {
        if ($freshPaths.ContainsKey($k.Split('|')[0])) { continue }
        $all.Add($k)
    }
    foreach ($k in $newlyChecked) { if (-not $all.Contains($k)) { $all.Add($k) } }
    [System.IO.File]::WriteAllLines($LedgerPath, $all, (New-Object System.Text.UTF8Encoding($false)))
}

Say ""
Say "---------------------------------------------------------------------------" 'DarkGray'
Say ("  already at the right volume : {0}" -f $okAlready) 'Gray'
Say ("  re-recorded                 : {0}" -f $fixed) $(if ($fixed) { 'Green' } else { 'Gray' })
Say ("  could not be done           : {0}" -f $failed) $(if ($failed) { 'Yellow' } else { 'Gray' })
Say "---------------------------------------------------------------------------" 'DarkGray'

if ($fixed -gt 0) {
    Say ""
    Say "Originals kept in _ClaudeWorkspace\archive\ under:" 'DarkGray'
    if (Test-Path $backupPrev) { Say ("  gamevideos-original-{0}\" -f $stamp) 'DarkGray' }
    if (Test-Path $backupMenu) { Say ("  menuvideos-original-{0}\" -f $stamp) 'DarkGray' }
    if (Test-Path $backupIntro) { Say ("  introvideos-original-{0}\" -f $stamp) 'DarkGray' }
}

Say ""
exit 0
