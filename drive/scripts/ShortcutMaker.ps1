<#
    ShortcutMaker.ps1
    ---------------------------------------------------------------------------
    Desktop and Start Menu shortcuts to ONE game. FUNCTIONS ONLY - dot-source
    it. Nothing here does anything until something calls it.

    WHAT IT MAKES. A normal Windows shortcut that starts one game directly,
    without the RetroBat front end opening first. Double-click "Wind Waker" on
    the desktop and you are in Wind Waker.

    HOW IT KNOWS HOW TO LAUNCH ANYTHING. It does not invent a command. It reads
    the real <command> line RetroBat wrote for that system in es_systems.cfg
    and fills in the blanks itself, dropping the extras (%EMULATOR%, %CORE%,
    %GAMEINFOXML%, %CONTROLLERSCONFIG%) that only EmulationStation can supply
    and that emulatorLauncher works out on its own. Same rule as game names
    everywhere else on this drive: the drive's own files are the truth.

    THE ICON PROBLEM, AND THE ANSWER. A shortcut stores its picture and its
    target separately. If the picture lived on the drive, every shortcut would
    go blank the moment the drive was unplugged - which looks broken even
    though nothing is. So the picture is COPIED ONTO THE COMPUTER, into the
    user's own app-data folder, and only the target points at the drive. Pull
    the drive out and the icons still look right; click one and Windows says,
    politely, that it cannot find it. That is the same trick the drive already
    uses for its two root buttons.

    WHY THE USER PICKS THE PICTURE. RetroBat scrapes several images per game -
    box art, a logo, a screenshot - and which one survives being shrunk to a
    32-pixel icon is different for every game. Tall box art turns to mush;
    some logos are pure text and vanish. So this offers every static image it
    can find and lets a person look at them and choose. Anything automatic
    here would be wrong about a third of the time.

    SQUARE, ALWAYS. Icons are square and game art is not, so the chosen image
    is scaled to fit and centred on a transparent square. Stretching it to fit
    would be the difference between looking deliberate and looking broken.

    RULES HONOURED HERE:
      - no drive letters anywhere; everything derives from -Root
      - no $PSScriptRoot inside a param() block
      - Windows PowerShell 5.1 only
      - pure ASCII, no byte-order mark
      - no function throws; failures come back as $false, '' or an empty list
#>

Set-StrictMode -Off

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# Folders inside a roms\<system> folder that hold artwork rather than games.
$script:ScNotGames = @('images', 'videos', 'manuals', 'media', 'downloaded_images', 'downloaded_videos', 'boxarts')

# The picture kinds RetroBat scrapes, best-for-an-icon first. A marquee is
# usually the game's logo on a transparent background, which is exactly what
# an icon wants; box art is next; a screenshot is the last resort because at
# icon size it is mush. The order only sets what the window shows first - the
# person still chooses.
$script:ScImageKinds = @(
    @('marquee',   'Logo'),
    @('thumb',     'Box art'),
    @('image',     'Screenshot or box'),
    @('wheel',     'Wheel logo'),
    @('boxart',    'Box art'),
    @('box2dfront','Box front'),
    @('titleshot', 'Title screen'),
    @('fanart',    'Fan art'),
    @('mix',       'Mixed image')
)

# ===========================================================================
#  PART ONE - what there is to make a shortcut to
# ===========================================================================

# system name -> the pretty name RetroBat shows, read from its own file.
function Get-ScSystemNames {
    param([string]$Root)
    $map = @{}
    try {
        $cfg = Join-Path $Root 'emulationstation\.emulationstation\es_systems.cfg'
        if (-not (Test-Path -LiteralPath $cfg)) { return $map }
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($cfg)
        foreach ($s in @($xml.SelectNodes('//system'))) {
            $n = [string]$s.name
            $f = [string]$s.fullname
            if ($n -ne '') { if ($f -eq '') { $f = $n }; $map[$n] = $f }
        }
    }
    catch { }
    return $map
}

# How a shortcut starts one game. Returns an object: Exe, Arguments,
# WorkingDirectory.
#
# Steam games go straight to Steam - the same request the tile in RetroBat
# makes, and Steam looks after its own controllers.
#
# EVERYTHING ELSE goes through Launch-Game.vbs, which asks RetroBat's own menu
# to launch the game (see the note below). The game is passed as a path
# INSIDE the RetroBat folder, so the only drive-dependent part of the
# shortcut is where the .vbs is - the same as any shortcut to this drive.
function Get-ScLaunchCommand {
    param([string]$Root, [string]$System, [string]$RomPath, [switch]$WithControllers)

    if ($System -eq 'steam') {
        $appId = Get-ScSteamAppId -RomPath $RomPath
        $steam = Get-ScSteamExe
        if ($appId -ne '' -and $steam -ne '') {
            return [pscustomobject]@{
                Exe              = $steam
                Arguments        = ('-applaunch ' + $appId)
                WorkingDirectory = (Split-Path $steam -Parent)
            }
        }
    }

    $vbs = Join-Path $Root '_ClaudeWorkspace\scripts\Launch-Game.vbs'
    $rel = $RomPath
    $prefix = $Root.TrimEnd('\') + '\'
    if ($RomPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $RomPath.Substring($prefix.Length) }

    $wscript = Join-Path ([Environment]::GetFolderPath('System')) 'wscript.exe'
    return [pscustomobject]@{
        Exe              = $wscript
        Arguments        = ('//nologo "' + $vbs + '" "' + $rel + '"')
        WorkingDirectory = (Split-Path $vbs -Parent)
        Script           = $vbs
    }
}

# ---------------------------------------------------------------------------
#  WHY SHORTCUTS GO THROUGH RETROBAT'S MENU (2026-09-25)
#
#  The first version called emulatorLauncher.exe directly. RetroBat's log
#  showed why that could never work (2026-09-21): EmulationStation passes
#
#    -p1index 0 -p1guid ... -p1path "USB\VID_045E..." -p1name "Xbox One
#    Controller" -p1nbbuttons 16 -p1nbhats 1 -p1nbaxes 6
#    -system gamecube -emulator dolphin -core dolphin -rom "..."
#
#  worked out from the hardware at the moment of launch, and then runs the
#  game-end hook that backs up saves. A direct call had none of it: dead
#  pads, no SELECT + START, no backup. Shortcuts were cut back to Steam only.
#
#  THE ANSWER: EmulationStation runs a small web service for programs on the
#  same computer (localhost:1234) with a /launch command. Launch-Game.ps1
#  opens the menu if needed, asks it to launch the game, waits for the game
#  to end and the backup to finish, then closes the menu again. So a game
#  from a shortcut is launched BY RetroBat, identically to picking it, and
#  nothing is imitated. Log: _ClaudeWorkspace\wizard\game-shortcut.log.
# ---------------------------------------------------------------------------

# Steam's own folder on this computer, for building a shortcut that asks
# Steam to start a game. Registry first, then the usual place.
function Get-ScSteamExe {
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue).SteamPath
        if ($p) {
            $p = $p -replace '/', '\'
            $exe = Join-Path $p 'steam.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    catch { }
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = (Get-ItemProperty -Path $key -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
            if ($p) {
                $exe = Join-Path $p 'steam.exe'
                if (Test-Path -LiteralPath $exe) { return $exe }
            }
        }
        catch { }
    }
    return ''
}

# The game number out of one of the drive's .url tiles.
function Get-ScSteamAppId {
    param([string]$RomPath)
    try {
        $text = [System.IO.File]::ReadAllText($RomPath)
        $m = [regex]::Match($text, '(?i)steam://rungameid/(\d+)')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    catch { }
    return ''
}

# The file extensions RetroBat counts as games for one system, lower case
# with the dot, read from es_systems.cfg. Cached, because it is asked a lot.
$script:ScExtCache = @{}
function Get-ScSystemExtensions {
    param([string]$Root, [string]$System)
    if ($script:ScExtCache.ContainsKey($System)) { return $script:ScExtCache[$System] }
    $list = @()
    try {
        if ($null -eq $script:ScSystemsXml) {
            $cfg = Join-Path $Root 'emulationstation\.emulationstation\es_systems.cfg'
            $script:ScSystemsXml = New-Object System.Xml.XmlDocument
            $script:ScSystemsXml.Load($cfg)
        }
        foreach ($s in @($script:ScSystemsXml.SelectNodes('//system'))) {
            if ([string]$s.name -ne $System) { continue }
            foreach ($e in ([string]$s.extension -split '\s+')) { if ($e -ne '') { $list += $e.ToLower() } }
            break
        }
    }
    catch { }
    $script:ScExtCache[$System] = $list
    return $list
}

# Every system that actually has games on this drive, prettiest name first.
# Returns psobjects: Name, FullName, GameCount.
function Get-ScSystems {
    param([string]$Root)

    $out = @()
    try {
        $romsDir = Join-Path $Root 'roms'
        if (-not (Test-Path -LiteralPath $romsDir)) { return $out }
        $names = Get-ScSystemNames -Root $Root

        foreach ($d in @(Get-ChildItem -LiteralPath $romsDir -Directory -ErrorAction SilentlyContinue)) {
            $n = @(Get-ScGames -Root $Root -System $d.Name).Count
            if ($n -eq 0) { continue }

            $full = $d.Name
            if ($names.ContainsKey($d.Name)) { $full = [string]$names[$d.Name] }

            # Deliberately NOT called Count. A property of that name on a
            # returned object shadows the array's own .Count, so a caller
            # asking how many systems there are silently gets the number of
            # games in the first one. Found by a test on 2026-09-19.
            $out += [pscustomobject]@{
                Name      = $d.Name
                FullName  = $full
                GameCount = $n
            }
        }
    }
    catch { return @() }

    return @($out | Sort-Object FullName)
}

# Every game in one system. Reads gamelist.xml when there is one, because that
# is where the real names live, and falls back to the file names when there is
# not. Returns psobjects: Name, RomPath, FileBase.
function Get-ScGames {
    param([string]$Root, [string]$System)

    $out = @()
    try {
        $dir = Join-Path (Join-Path $Root 'roms') $System
        if (-not (Test-Path -LiteralPath $dir)) { return $out }

        $seen = @{}
        $list = Join-Path $dir 'gamelist.xml'

        if (Test-Path -LiteralPath $list) {
            try {
                $xml = New-Object System.Xml.XmlDocument
                $xml.Load($list)
                foreach ($g in @($xml.SelectNodes('//game'))) {
                    $p = [string]$g.path
                    if ($p -eq '') { continue }
                    $p = $p -replace '^\./', ''
                    $full = Join-Path $dir $p
                    if (-not (Test-Path -LiteralPath $full)) { continue }

                    $name = [string]$g.name
                    if ($name -eq '') { $name = [System.IO.Path]::GetFileNameWithoutExtension($p) }

                    $base = [System.IO.Path]::GetFileNameWithoutExtension($p)
                    if ($seen.ContainsKey($base.ToLower())) { continue }
                    $seen[$base.ToLower()] = $true

                    $out += [pscustomobject]@{
                        Name     = $name
                        RomPath  = $full
                        FileBase = $base
                    }
                }
            }
            catch { }
        }

        # Anything on disk the game list did not mention - but only files
        # RetroBat itself would call a game (its own extension list), so side
        # files such as a .gameexe or a .sav never show up as games.
        $exts = Get-ScSystemExtensions -Root $Root -System $System
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -ieq 'gamelist.xml') { continue }
            if ($exts.Count -gt 0 -and -not ($exts -contains $f.Extension.ToLower())) { continue }
            if ($exts.Count -eq 0 -and $f.Extension -ieq '.txt') { continue }
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($seen.ContainsKey($base.ToLower())) { continue }
            $seen[$base.ToLower()] = $true
            $out += [pscustomobject]@{
                Name     = $base
                RomPath  = $f.FullName
                FileBase = $base
            }
        }
    }
    catch { return @() }

    return @($out | Sort-Object Name)
}

# Every still picture this drive holds for one game, for the person to choose
# between. Returns psobjects: Kind, Label, Path. Animated files are left out:
# an icon cannot move.
function Get-ScGameImages {
    param([string]$Root, [string]$System, [string]$FileBase)

    $out = @()
    try {
        $dir = Join-Path (Join-Path (Join-Path $Root 'roms') $System) 'images'
        if (-not (Test-Path -LiteralPath $dir)) { return $out }

        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            $ext = $f.Extension.ToLower()
            if ($ext -ne '.png' -and $ext -ne '.jpg' -and $ext -ne '.jpeg' -and $ext -ne '.bmp') { continue }

            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if (-not $base.StartsWith($FileBase, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            $suffix = $base.Substring($FileBase.Length)
            $kind = $suffix.TrimStart('-').Trim()
            if ($kind -eq '') { $kind = 'image' }

            $label = $kind
            foreach ($k in $script:ScImageKinds) {
                if ($k[0] -ieq $kind) { $label = $k[1]; break }
            }

            $out += [pscustomobject]@{
                Kind  = $kind
                Label = $label
                Path  = $f.FullName
            }
        }
    }
    catch { return @() }

    # Best-for-an-icon first, anything unrecognised last.
    $order = @{}
    for ($i = 0; $i -lt $script:ScImageKinds.Count; $i++) { $order[$script:ScImageKinds[$i][0].ToLower()] = $i }
    return @($out | Sort-Object @{ Expression = { if ($order.ContainsKey($_.Kind.ToLower())) { $order[$_.Kind.ToLower()] } else { 99 } } }, Kind)
}

# ===========================================================================
#  PART TWO - turning a picture into an icon, on the COMPUTER
# ===========================================================================

# Where the icons live. On the computer, never on the drive - that is the
# whole point. Windows keeps this per user, which is right: a shortcut on
# somebody's desktop is theirs.
function Get-ScIconFolder {
    try {
        $b = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($b)) { return '' }
        return (Join-Path $b 'RetroBatWizard\game-icons')
    }
    catch { return '' }
}

# Scale a picture to fit a square and centre it on transparency. Returns the
# PNG bytes, or $null.
function ConvertTo-ScSquarePng {
    param([string]$SourceImage, [int]$Size = 256)

    $img = $null; $bmp = $null; $gfx = $null; $inStream = $null; $outStream = $null
    try {
        # Read the bytes first rather than handing the file to .NET. FromFile
        # keeps the file locked for as long as the image object lives, and a
        # locked file on somebody's external drive is how you get a drive that
        # will not eject.
        $bytes = [System.IO.File]::ReadAllBytes($SourceImage)
        $inStream = New-Object System.IO.MemoryStream(,$bytes)
        $img = [System.Drawing.Image]::FromStream($inStream)

        $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gfx = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gfx.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $scale = [Math]::Min(($Size / [double]$img.Width), ($Size / [double]$img.Height))
        $w = [int][Math]::Round($img.Width * $scale)
        $h = [int][Math]::Round($img.Height * $scale)
        if ($w -lt 1) { $w = 1 }
        if ($h -lt 1) { $h = 1 }
        $x = [int](($Size - $w) / 2)
        $y = [int](($Size - $h) / 2)

        $gfx.DrawImage($img, $x, $y, $w, $h)
        $gfx.Flush()

        $outStream = New-Object System.IO.MemoryStream
        $bmp.Save($outStream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $outStream.ToArray()
    }
    catch { return $null }
    finally {
        if ($gfx) { $gfx.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
        if ($inStream) { $inStream.Dispose() }
        if ($outStream) { $outStream.Dispose() }
    }
}

# Write a real .ico file holding one 256-pixel picture.
#
# An .ico is a six-byte header, a sixteen-byte entry describing the picture,
# then the picture itself. Since Windows Vista that picture is allowed to be
# a PNG, which is why this can be done in a few lines with no extra software:
# the PNG made above is simply pasted in whole. A width and height byte of 0
# is the format's way of saying 256.
function Write-ScIconFile {
    param([byte[]]$PngBytes, [string]$DestPath)

    $fs = $null; $bw = $null
    try {
        if ($null -eq $PngBytes -or $PngBytes.Length -eq 0) { return $false }

        $dir = Split-Path $DestPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $fs = New-Object System.IO.FileStream($DestPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $bw = New-Object System.IO.BinaryWriter($fs)

        $bw.Write([uint16]0)   # reserved
        $bw.Write([uint16]1)   # 1 = icon
        $bw.Write([uint16]1)   # one picture in this file

        $bw.Write([byte]0)     # width  0 means 256
        $bw.Write([byte]0)     # height 0 means 256
        $bw.Write([byte]0)     # colours in palette: none, it is full colour
        $bw.Write([byte]0)     # reserved
        $bw.Write([uint16]1)   # colour planes
        $bw.Write([uint16]32)  # bits per pixel
        $bw.Write([uint32]$PngBytes.Length)
        $bw.Write([uint32]22)  # the picture starts right after this entry

        $bw.Write($PngBytes)
        $bw.Flush()
        return $true
    }
    catch { return $false }
    finally {
        if ($bw) { $bw.Dispose() }
        if ($fs) { $fs.Dispose() }
    }
}

# Picture on the drive -> icon on the computer. Returns the icon's path or ''.
function New-ScGameIcon {
    param([string]$SourceImage, [string]$System, [string]$FileBase)
    try {
        if ([string]::IsNullOrWhiteSpace($SourceImage)) { return '' }
        if (-not (Test-Path -LiteralPath $SourceImage)) { return '' }

        $folder = Get-ScIconFolder
        if ($folder -eq '') { return '' }

        $safe = $FileBase
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $safe = $safe.Replace([string]$c, '') }
        $safe = $safe.Trim().TrimEnd('.')
        if ($safe -eq '') { $safe = 'game' }

        $dest = Join-Path $folder ($System + '_' + $safe + '.ico')

        $png = ConvertTo-ScSquarePng -SourceImage $SourceImage
        if ($null -eq $png) { return '' }
        if (-not (Write-ScIconFile -PngBytes $png -DestPath $dest)) { return '' }
        return $dest
    }
    catch { return '' }
}

# ===========================================================================
#  PART THREE - the shortcut itself
# ===========================================================================

function Get-ScShortcutFolders {
    param([string]$StartMenuFolder = 'RetroBat Games')
    $desktop = ''
    $start   = ''
    try { $desktop = [Environment]::GetFolderPath('Desktop') } catch { }
    try {
        $p = [Environment]::GetFolderPath('Programs')
        if ($p -ne '') { $start = Join-Path $p $StartMenuFolder }
    }
    catch { }
    return [pscustomobject]@{ Desktop = $desktop; StartMenu = $start }
}

# Make the shortcut, in whichever places were asked for.
# Places is an array holding 'desktop' and/or 'start'.
# Returns an object: Ok, Written (paths), Problem, Icon.
function New-ScGameShortcut {
    param(
        [string]$Root,
        [string]$System,
        [string]$RomPath,
        [string]$Name,
        [string]$FileBase,
        [string]$ImagePath = '',
        [string[]]$Places = @('desktop'),
        [string]$StartMenuFolder = 'RetroBat Games',
        [switch]$WithControllers
    )

    $result = [pscustomobject]@{ Ok = $false; Written = @(); Problem = ''; Icon = '' }

    try {
        if (-not (Test-Path -LiteralPath $RomPath)) {
            $result.Problem = 'That game file is not on the drive any more.'
            return $result
        }

        $launch = Get-ScLaunchCommand -Root $Root -System $System -RomPath $RomPath -WithControllers:$WithControllers
        if (-not (Test-Path -LiteralPath $launch.Exe)) {
            $result.Problem = ("Could not find " + $launch.Exe)
            return $result
        }
        if ($launch.Script -and -not (Test-Path -LiteralPath $launch.Script)) {
            $result.Problem = ("Could not find " + $launch.Script)
            return $result
        }

        # The icon is made first. A shortcut with no icon is still a working
        # shortcut, so a failure here is worth carrying on past.
        if ($ImagePath -ne '') {
            $result.Icon = New-ScGameIcon -SourceImage $ImagePath -System $System -FileBase $FileBase
        }

        $safe = $Name
        foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $safe = $safe.Replace([string]$c, '') }
        $safe = $safe.Trim().TrimEnd('.')
        if ($safe -eq '') { $safe = 'Game' }

        $folders = Get-ScShortcutFolders -StartMenuFolder $StartMenuFolder
        $targets = @()
        if ($Places -contains 'desktop' -and $folders.Desktop -ne '') { $targets += $folders.Desktop }
        if ($Places -contains 'start'   -and $folders.StartMenu -ne '') { $targets += $folders.StartMenu }

        if ($targets.Count -eq 0) {
            $result.Problem = 'No place was chosen to put the shortcut.'
            return $result
        }

        $shell = New-Object -ComObject WScript.Shell
        $written = @()

        foreach ($t in $targets) {
            try {
                if (-not (Test-Path -LiteralPath $t)) { New-Item -ItemType Directory -Path $t -Force | Out-Null }
                $lnkPath = Join-Path $t ($safe + '.lnk')

                $lnk = $shell.CreateShortcut($lnkPath)
                $lnk.TargetPath       = $launch.Exe
                $lnk.Arguments        = $launch.Arguments
                $lnk.WorkingDirectory = $launch.WorkingDirectory
                $lnk.Description      = ($Name + ' - starts straight from this RetroBat drive')
                if ($result.Icon -ne '') { $lnk.IconLocation = ($result.Icon + ',0') }
                $lnk.Save()

                $written += $lnkPath
            }
            catch { }
        }

        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }

        if ($written.Count -eq 0) {
            $result.Problem = 'Windows would not let the shortcut be written. A folder may be locked down.'
            return $result
        }

        $result.Written = $written
        $result.Ok = $true
        return $result
    }
    catch {
        $result.Problem = $_.Exception.Message
        return $result
    }
}

# Start a game the same way its shortcut would, so the window can offer a
# "try it now" button and any problem shows up immediately rather than three
# days later on somebody's desktop.
function Start-ScGameNow {
    param([string]$Root, [string]$System, [string]$RomPath, [switch]$WithControllers)
    try {
        $launch = Get-ScLaunchCommand -Root $Root -System $System -RomPath $RomPath -WithControllers:$WithControllers
        if (-not (Test-Path -LiteralPath $launch.Exe)) { return $false }
        Start-Process -FilePath $launch.Exe -ArgumentList $launch.Arguments -WorkingDirectory $launch.WorkingDirectory -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}
