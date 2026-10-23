<#
    Social-Helper.ps1 - the quiet background half of the Profile tab.

    Started by the RetroBat start hook (emulationstation\.emulationstation\
    scripts\start\zz-social.bat) and by the wizard when it opens. Only one
    copy ever runs. It lives while RetroBat or the wizard is open and then
    signs off and exits by itself.

    WHAT IT DOES
      - says "online" when it starts, and checks in every 15 minutes
      - notices a game starting or stopping (RetroBat's own local web API,
        localhost:1234/runningGame) and checks in straight away
      - Away by itself after 15 minutes with no keyboard or mouse, when the
        chosen status is Online and no game is running. A controller does not
        count as input to Windows, which is why a running game always wins
      - every 2 minutes, reads everybody in ONE request and shows a small popup
        in the corner when a friend comes online or sends a friend request.
        The popup never takes the keyboard away from a game
      - signs off ("offline") on the way out

    ADDED 2026-10-12 (Steven: "make it stay open in the background? I just
    want banners showing for requests to start netplay sessions together"):
      - PLAY TOGETHER. A friend's invite shows as a banner with Join and No
        thanks, even when the wizard is closed. Join answers them and opens
        the wizard's Netplay tab; their answer to OUR invite shows as a
        popup too. Friends are read every minute instead of every two.
      - STAYS RUNNING. With "Stay reachable" on (the Profile tab, on by
        default) it no longer exits when RetroBat and the wizard close. It
        keeps you reachable until Windows restarts, the drive is unplugged
        or the switch goes off. When both have been closed for a few
        minutes, the SESSION is over: incognito (from "Who's playing?")
        ends there, exactly as it does when the helper exits.
      - SWITCHING PERSON. When "Who's playing?" switches profile, the old
        one signs off and the new one checks in.

    NOTHING HAPPENS for a guest, for a drive with no profile yet, or with no
    token. It exits at once.

    Everything goes to _ClaudeWorkspace\social\social.log.

    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body:
    it is empty in param() under -File.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Ws   = Split-Path $PSScriptRoot -Parent
$Root = Split-Path $Ws -Parent
. (Join-Path $PSScriptRoot 'SocialEngine.ps1')
# Light / dark / follow Windows, shared by every window (scripts\Theme.ps1,
# 2026-10-13). Missing file = the original dark colours, untouched.
try { . (Join-Path $PSScriptRoot 'Theme.ps1') } catch { }
if (-not (Get-Command Convert-ThemeHex -ErrorAction SilentlyContinue)) { function Convert-ThemeHex([string]$hex) { return $hex } }


# It may now run for hours, so it must not keep the drive busy: a program
# whose current folder is on the drive stops Windows ejecting it safely.
try { Set-Location -LiteralPath $env:TEMP; [Environment]::CurrentDirectory = $env:TEMP } catch { }

$mutex = New-Object System.Threading.Mutex($false, 'Local\RetroBatSocialHelper')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Get-HelperVersion {
    $v = Join-Path $Ws 'version.txt'
    if (Test-Path -LiteralPath $v) { return ([System.IO.File]::ReadAllLines($v) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1).Trim() }
    return '?'
}

# RetroBat's menu, only the copy on THIS drive.
function Test-EsRunning {
    $esDir = Join-Path $Root 'emulationstation'
    foreach ($p in @(Get-Process -Name 'emulationstation' -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and $p.Path.StartsWith($esDir, [StringComparison]::OrdinalIgnoreCase)) { return $true } } catch { }
    }
    return $false
}

# The wizard touches social\wizard-alive.txt once a minute while it is open.
function Test-WizardOpen {
    $f = Join-Path $Ws 'social\wizard-alive.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    return (((Get-Date) - (Get-Item -LiteralPath $f).LastWriteTime).TotalMinutes -lt 3)
}

# The game RetroBat is running right now, from its own local web API, or
# $null. The same API scripts\Launch-Game.ps1 uses.
function Get-RunningGame {
    try {
        $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:1234/runningGame')
        $req.Method = 'GET'; $req.Proxy = $null; $req.Timeout = 3000; $req.ReadWriteTimeout = 3000
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
        if ($code -ne 200 -or $body.Trim() -eq '') { return $null }
        $g = $body | ConvertFrom-Json
        $name = Get-SocialClean ([string]$g.name) 60
        if ($name -eq '') { return $null }
        $sys = [string]$g.systemName
        if ($sys -eq '') { $sys = [string]$g.system }
        return [pscustomobject]@{ Name = $name; Console = (Get-ConsoleName $sys) }
    }
    catch { return $null }
}

$script:ConsoleNames = @{
    nes = 'NES'; snes = 'SNES'; n64 = 'N64'; gamecube = 'GameCube'; wii = 'Wii'; wiiu = 'Wii U'
    gb = 'Game Boy'; gbc = 'Game Boy Color'; gba = 'GBA'; nds = 'DS'; '3ds' = '3DS'; 'switch' = 'Switch'
    steam = 'PC'; flash = 'Flash'; scummvm = 'PC'; virtualboy = 'Virtual Boy'; pokemini = 'Pokemon Mini'
}
function Get-ConsoleName([string]$Sys) {
    $k = $Sys.Trim().ToLower()
    if ($script:ConsoleNames.ContainsKey($k)) { return $script:ConsoleNames[$k] }
    return (Get-SocialClean $Sys 30).ToUpper()
}

# Minutes since the last keyboard or mouse input on this computer.
$script:idleOk = $false
try {
    Add-Type -Namespace RBSocial -Name Idle -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
public static double Minutes() {
    LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i);
    if (!GetLastInputInfo(ref i)) return 0;
    return ((uint)Environment.TickCount - i.dwTime) / 60000.0;
}
'@
    $script:idleOk = $true
} catch { }
function Get-IdleMinutes { if ($script:idleOk) { try { return [RBSocial.Idle]::Minutes() } catch { } } return 0 }

# ---------------------------------------------------------------------------
#  The popup: bottom right, above the taskbar, five seconds, never focused
# ---------------------------------------------------------------------------
$script:wpfOk = $false
try { Add-Type -AssemblyName PresentationFramework; $script:wpfOk = $true } catch { }

function Get-AvatarSource($Player) {
    try {
        $path = ''
        if ([string]$Player.Avatar -like 'custom:*') { $path = Get-SocialAvatarFile $Ws $Player }
        else {
            $name = (([string]$Player.Avatar) -replace '^icon:', '') -replace '^wiimote$', 'wiiremote'
            $path = Join-Path $Ws ('wizard\profile-' + $name + '.png')
        }
        if ($path -eq '' -or -not (Test-Path -LiteralPath $path)) { return $null }
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'; $bmp.UriSource = New-Object System.Uri($path); $bmp.EndInit()
        return $bmp
    } catch { return $null }
}

function Show-Popup($Player, [string]$Title, [string]$Line) {
    Write-SocialLog $Ws ("popup: {0} {1}" -f $Title, $Line)
    if (-not $script:wpfOk) { return }
    try {
        $bc = New-Object System.Windows.Media.BrushConverter
        $w = New-Object System.Windows.Window
        $w.WindowStyle = 'None'; $w.ResizeMode = 'NoResize'; $w.AllowsTransparency = $true
        $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false; $w.Focusable = $false
        $w.Width = 340; $w.Height = 76
        $w.Background = $bc.ConvertFromString((Convert-ThemeHex '#F21B1B22'))
        $wa = [System.Windows.SystemParameters]::WorkArea
        $w.Left = $wa.Right - $w.Width - 16; $w.Top = $wa.Bottom - $w.Height - 16
        $g = New-Object System.Windows.Controls.DockPanel
        $g.Margin = '12,10,12,10'
        $src = Get-AvatarSource $Player
        if ($null -ne $src) {
            $img = New-Object System.Windows.Controls.Image
            $img.Source = $src; $img.Width = 48; $img.Height = 48; $img.Margin = '0,0,12,0'
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'NearestNeighbor')
            [System.Windows.Controls.DockPanel]::SetDock($img, 'Left')
            [void]$g.Children.Add($img)
        }
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.VerticalAlignment = 'Center'
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = $Title; $t1.FontSize = 15; $t1.FontWeight = 'Bold'; $t1.Foreground = $bc.ConvertFromString((Convert-ThemeHex '#FFE8E8EC'))
        $t1.TextTrimming = 'CharacterEllipsis'
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = $Line; $t2.FontSize = 12; $t2.Foreground = $bc.ConvertFromString((Convert-ThemeHex '#FF9AA0AA')); $t2.TextTrimming = 'CharacterEllipsis'
        [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
        [void]$g.Children.Add($sp)
        $w.Content = $g
        # It slides up into place and fades in, then fades away (2026-10-11).
        # Stepped by hand rather than with a WPF animation, because this
        # helper has no message loop running between popups to drive one.
        $endTop = $w.Top
        $w.Opacity = 0; $w.Top = $endTop + 24
        $w.Show()
        $pump = { $w.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
        for ($i = 1; $i -le 12; $i++) {
            $u = 1 - [math]::Pow(1 - $i / 12, 3)
            $w.Opacity = $u; $w.Top = $endTop + 24 * (1 - $u)
            & $pump; Start-Sleep -Milliseconds 20
        }
        for ($i = 0; $i -lt 45; $i++) { & $pump; Start-Sleep -Milliseconds 100 }
        for ($i = 1; $i -le 12; $i++) {
            $w.Opacity = 1 - $i / 12
            & $pump; Start-Sleep -Milliseconds 20
        }
        $w.Close()
    }
    catch { Write-SocialLog $Ws ("popup failed: " + $_.Exception.Message) }
}

# The parts of the online file that change between check-ins: the three
# favourites (by name), this drive's live invite and its answer to one.
function Get-HelperLive($p) {
    $now = Get-SocialNowUtc
    $favs = @()
    try { $favs = @(Get-SocialFavs $Root $p | Where-Object { $null -ne $_ }) } catch { }
    $inv = $null; $rep = $null
    try { $inv = Read-SocialInvite $Ws $now } catch { }
    try { $rep = Read-SocialReply $Ws $now } catch { }
    return @{ Favs = $favs; Invite = $inv; Reply = $rep }
}

# --- the invite banner: stays up to 30 seconds, with two buttons ------------
#  Never takes the keyboard from a game until it is clicked. Returns 'join',
#  'no' or '' (nobody answered).
function Show-InviteBanner($Player, [string]$Title, [string]$Line) {
    Write-SocialLog $Ws ("invite banner: {0} {1}" -f $Title, $Line)
    if (-not $script:wpfOk) { return '' }
    $script:bannerAnswer = ''
    try {
        $bc = New-Object System.Windows.Media.BrushConverter
        $w = New-Object System.Windows.Window
        $w.WindowStyle = 'None'; $w.ResizeMode = 'NoResize'; $w.AllowsTransparency = $true
        $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false
        $w.Width = 380; $w.Height = 118
        $w.Background = $bc.ConvertFromString((Convert-ThemeHex '#F22A2440'))
        $w.BorderBrush = $bc.ConvertFromString((Convert-ThemeHex '#FF6C8CFF')); $w.BorderThickness = '1'
        $wa = [System.Windows.SystemParameters]::WorkArea
        $w.Left = $wa.Right - $w.Width - 16; $w.Top = $wa.Bottom - $w.Height - 16
        $g = New-Object System.Windows.Controls.DockPanel
        $g.Margin = '12,10,12,10'
        $src = Get-AvatarSource $Player
        if ($null -ne $src) {
            $img = New-Object System.Windows.Controls.Image
            $img.Source = $src; $img.Width = 48; $img.Height = 48; $img.Margin = '0,0,12,0'; $img.VerticalAlignment = 'Top'
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'NearestNeighbor')
            [System.Windows.Controls.DockPanel]::SetDock($img, 'Left')
            [void]$g.Children.Add($img)
        }
        $sp = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = $Title; $t1.FontSize = 15; $t1.FontWeight = 'Bold'; $t1.Foreground = $bc.ConvertFromString((Convert-ThemeHex '#FFE8E8EC')); $t1.TextTrimming = 'CharacterEllipsis'
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = $Line; $t2.FontSize = 12; $t2.Foreground = $bc.ConvertFromString((Convert-ThemeHex '#FFCFE6FF')); $t2.TextTrimming = 'CharacterEllipsis'
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'; $row.Margin = '0,10,0,0'
        $bj = New-Object System.Windows.Controls.Button
        $bj.Content = 'Join'; $bj.Padding = '16,3'; $bj.FontSize = 13; $bj.FontWeight = 'Bold'; $bj.Margin = '0,0,8,0'
        $bj.Add_Click({ $script:bannerAnswer = 'join' })
        $bn = New-Object System.Windows.Controls.Button
        $bn.Content = 'No thanks'; $bn.Padding = '12,3'; $bn.FontSize = 13
        $bn.Add_Click({ $script:bannerAnswer = 'no' })
        [void]$row.Children.Add($bj); [void]$row.Children.Add($bn)
        [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2); [void]$sp.Children.Add($row)
        [void]$g.Children.Add($sp)
        $w.Content = $g
        $w.Show()
        $pump = { $w.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
        for ($i = 0; $i -lt 300 -and $script:bannerAnswer -eq ''; $i++) { & $pump; Start-Sleep -Milliseconds 100 }
        $w.Close()
    }
    catch { Write-SocialLog $Ws ("invite banner failed: " + $_.Exception.Message) }
    return $script:bannerAnswer
}

# Join: open the wizard on its Netplay tab (or turn an open one to it).
function Open-WizardNetplay {
    try {
        if (Test-WizardOpen) {
            [System.IO.File]::WriteAllText((Join-Path $Ws 'social\goto.txt'), 'netplay')
            return
        }
        $vbs = Join-Path $Ws 'wizard\Launch-Wizard.vbs'
        if (Test-Path -LiteralPath $vbs) {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @('//nologo', ('"' + $vbs + '"'), '-netplay')
        }
    } catch { Write-SocialLog $Ws ("could not open the wizard: " + $_.Exception.Message) }
}

# New invites to us, and answers to ours. Called after every fetch.
function Invoke-HelperInvites($Prof, $Players) {
    $now = Get-SocialNowUtc
    foreach ($x in @(Get-SocialInvitesFor $Prof $Players $now)) {
        $key = 'inv:' + $x.From.Id + ':' + $x.Invite.Id
        if (Test-SocialSeen $Ws $key) { continue }
        Add-SocialSeen $Ws $key
        $what = $(if ($x.Invite.Game -ne '') { $x.Invite.Game } else { 'a game' })
        $line = $(if ($x.Invite.Note -ne '') { $x.Invite.Note } else { 'Netplay, right now' })
        $ans = Show-InviteBanner $x.From ("{0} wants to play {1}" -f $x.From.Username, $what) $line
        if ($ans -eq 'join' -or $ans -eq 'no') {
            try { Write-SocialReply $Ws $x.From.Id $x.Invite.Id ($ans -eq 'join'); [void](Send-CheckIn 'on'); $script:lastPublish = Get-Date } catch { }
            Write-SocialLog $Ws ("invite from {0}: {1}" -f $x.From.Username, $ans)
            if ($ans -eq 'join') { Open-WizardNetplay }
        }
    }
    $mine = $null
    try { $mine = Read-SocialInvite $Ws $now } catch { }
    foreach ($r in @(Get-SocialRepliesFor $Prof $Players $mine)) {
        $key = 'rep:' + $r.From.Id + ':' + $mine.Id + ':' + $(if ($r.Yes) { 'y' } else { 'n' })
        if (Test-SocialSeen $Ws $key) { continue }
        Add-SocialSeen $Ws $key
        if ($r.Yes) { Show-Popup $r.From ("{0} is joining!" -f $r.From.Username) 'Host the game and they will find it' }
        else { Show-Popup $r.From ("{0} can't play right now" -f $r.From.Username) 'Maybe next time' }
    }
}

# ===========================================================================
$prof = Read-SocialProfile $Ws
if ($null -eq $prof -or $prof.Guest) { exit 0 }
if ((Get-SocialToken $Ws) -eq '') { Write-SocialLog $Ws 'helper: no token, nothing to do'; exit 0 }
$version = Get-HelperVersion
Write-SocialLog $Ws ("helper: started as {0}" -f $prof.Username)

$game = $null; $since = ''
$lastPublish = [DateTime]::MinValue
$lastFetch   = [DateTime]::MinValue
$lastStatus  = ''
$profStamp   = (Get-Item -LiteralPath (Get-SocialPaths $Ws).Profile).LastWriteTime
$baseline    = $true
$prevOnline  = @{}
$prevIncoming = @{}
$goneTicks   = 0
$started     = Get-Date
$curId       = $prof.Id
$sessionOver = $false

function Send-CheckIn([string]$State) {
    $p = Read-SocialProfile $Ws
    if ($null -eq $p -or $p.Guest) { return $false }
    $eff = $p.Status
    if ($eff -eq 'online' -and $null -eq $script:game -and (Get-IdleMinutes) -ge 15) { $eff = 'away' }
    if ($State -ne 'offline' -and (Test-SocialIncognito $Ws)) { $eff = 'invisible' }
    $p.Status = $eff
    $pres = [pscustomobject]@{
        State = $State; InGame = ($null -ne $script:game)
        Game = $(if ($script:game) { $script:game.Name } else { '' })
        Console = $(if ($script:game) { $script:game.Console } else { '' })
        Since = $script:since
    }
    # played games for the profile (only sent when shared with someone)
    $stats = $null
    if (@($p.Share).Count -gt 0) {
        try {
            # (2026-10-17) this person's own play time, not the whole drive's
            $led = $null
            try { $led = Update-SocialPlayLedger $Root $Ws ([string]$p.Id) } catch { Write-SocialLog $Ws ("play ledger: " + $_.Exception.Message) }
            $stats = Get-SocialGameStats $Root (Get-SocialHiddenGames $Ws) 3 3 6 $led
        } catch { Write-SocialLog $Ws ("stats: " + $_.Exception.Message) }
    }
    $live = Get-HelperLive $p
    $r = Publish-SocialRecord $Ws $p $pres $script:version '' $stats $live
    $script:lastStatus = $eff
    if (-not $r.Ok) { Write-SocialLog $Ws ("helper: check-in failed - " + $r.Message) }
    return $r.Ok
}

try {
    [void](Send-CheckIn 'on'); $lastPublish = Get-Date

    while ($true) {
        Start-Sleep -Seconds 10

        # --- still wanted? ---------------------------------------------------
        if (-not (Test-Path -LiteralPath (Get-SocialPaths $Ws).Profile)) {
            if (-not (Test-Path -LiteralPath $Ws)) { Write-SocialLog $Ws 'helper: the drive is gone, stopping'; break }
        }
        $prof = Read-SocialProfile $Ws
        if ($null -eq $prof -or $prof.Guest) { Write-SocialLog $Ws 'helper: profile gone or guest, stopping'; break }

        $alive = (Test-EsRunning) -or (Test-WizardOpen)
        if (-not $alive -and ((Get-Date) - $started).TotalSeconds -gt 60) { $goneTicks++ } else { $goneTicks = 0; $sessionOver = $false }
        if ($goneTicks -ge 3) {
            if (-not $prof.Reach) { break }
            if (-not $sessionOver) {
                # Both closed: the session is over, the helper is not.
                $sessionOver = $true
                if (Test-SocialIncognito $Ws) {
                    Set-SocialIncognito $Ws $false
                    Write-SocialLog $Ws 'helper: session over, incognito ended'
                    [void](Send-CheckIn 'on'); $lastPublish = Get-Date
                }
            }
        }

        # --- somebody else is playing now ("Who's playing?" switched) ------
        if ($prof.Id -ne $curId) {
            try {
                $old = Read-SocialPersonCopy $Ws $curId
                if ($null -ne $old) {
                    $gone = [pscustomobject]@{ State = 'offline'; InGame = $false; Game = ''; Console = ''; Since = '' }
                    [void](Publish-SocialRecord $Ws $old $gone $version)
                }
            } catch { }
            Write-SocialLog $Ws ("helper: now {0}" -f $prof.Username)
            $curId = $prof.Id
            $baseline = $true; $prevOnline = @{}; $prevIncoming = @{}
            $lastFetch = [DateTime]::MinValue
            $publishNow = $true
        }

        if ($null -eq $publishNow) { $publishNow = $false }

        # --- a game started or stopped ---------------------------------------
        $g = $null
        if (Test-EsRunning) { $g = Get-RunningGame }
        $was = if ($game) { $game.Name } else { '' }
        $now = if ($g) { $g.Name } else { '' }
        if ($was -ne $now) {
            $game = $g
            $since = $(if ($g) { Format-SocialTime (Get-SocialNowUtc) } else { '' })
            $publishNow = $true
            Write-SocialLog $Ws ("helper: game {0}" -f $(if ($g) { "$($g.Name) ($($g.Console))" } else { 'ended' }))
        }

        # --- the profile was changed in the wizard ---------------------------
        $stamp = (Get-Item -LiteralPath (Get-SocialPaths $Ws).Profile).LastWriteTime
        if ($stamp -ne $profStamp) { $profStamp = $stamp; $publishNow = $true }

        # --- went idle, or came back -----------------------------------------
        $wantAway = ($prof.Status -eq 'online' -and $null -eq $game -and (Get-IdleMinutes) -ge 15)
        $isAway = ($lastStatus -eq 'away' -and $prof.Status -eq 'online')
        if ($wantAway -ne $isAway) { $publishNow = $true }

        if ($publishNow -or ((Get-Date) - $lastPublish).TotalMinutes -ge 15) {
            [void](Send-CheckIn 'on'); $lastPublish = Get-Date
        }
        $publishNow = $null

        # --- friends ----------------------------------------------------------
        if (((Get-Date) - $lastFetch).TotalSeconds -ge 60) {
            $lastFetch = Get-Date
            $all = Get-SocialPlayers $Ws
            if ($all.Ok) {
                # Name answers from an admin, a password changed on another drive.
                try { [void](Update-SocialFromOnline $Ws $all.Players @{ Names = $all.Names; Admins = $all.Admins }) } catch { }
                $view = Get-SocialView $prof $all.Players (Get-SocialNowUtc)
                $online = @{}
                foreach ($f in @($view.Friends)) {
                    if ((Get-SocialPresence $f (Get-SocialNowUtc)).Kind -ne 'offline') { $online[$f.Id] = $f }
                }
                $incoming = @{}
                foreach ($f in @($view.Incoming)) { $incoming[$f.Id] = $f }
                if (-not $baseline -and $prof.Popups) {
                    foreach ($id in $online.Keys) {
                        if (-not $prevOnline.ContainsKey($id)) {
                            $f = $online[$id]
                            Show-Popup $f ("{0} is online" -f $f.Username) (Get-SocialPresence $f (Get-SocialNowUtc)).Line
                        }
                    }
                    foreach ($id in $incoming.Keys) {
                        if (-not $prevIncoming.ContainsKey($id)) {
                            $f = $incoming[$id]
                            Show-Popup $f ("{0} sent a friend request" -f $f.Username) 'Open the wizard''s Profile tab to answer'
                        }
                    }
                }
                $prevOnline = $online; $prevIncoming = $incoming; $baseline = $false
                try { Invoke-HelperInvites $prof $all.Players } catch { Write-SocialLog $Ws ("invites: " + $_.Exception.Message) }
            }
        }
    }
}
catch { Write-SocialLog $Ws ("helper: stopped on an error - " + $_.Exception.Message) }
finally {
    $game = $null
    try { [void](Send-CheckIn 'offline') } catch { }
    try { Set-SocialIncognito $Ws $false } catch { }
    Write-SocialLog $Ws 'helper: signed off'
    try { $mutex.ReleaseMutex() } catch { }
}
