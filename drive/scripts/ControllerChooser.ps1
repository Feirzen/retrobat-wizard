<#
    ControllerChooser.ps1 - "Wii Remotes or Pro Controller?" before a Wii U game.

    Written 2026-10-13 for Steven: "instead of one launch button, two:
    launch with Wii Remotes and launch with a Pro Controller, with grey
    icons shaped like the controllers."

    HOW IT IS REACHED
    RetroBat's Wii U launch command points at system\scripts\wiiu-launch.vbs
    (put there, and put back after RetroBat updates, by Fix-Portability.ps1).
    That little script runs this one and WAITS for it, then starts the game
    with the choice added to the launch line. A choice given on the launch
    line beats the per-game setting (checked against RetroBat's own launcher
    code, 2026-10-13), so nothing in es_settings.cfg is ever rewritten here.

    WHO GETS ASKED
    Only games whose controllers.ini kind is "party-wiimotes" or "pro" - the
    ones that genuinely work both ways. Games that need the Wii U GamePad
    (pro-p1gamepad, pro-touch, touch-extras-wiimote) cannot use real Wii
    Remotes at all, so they launch straight away with no question. A game
    not in controllers.ini yet is asked, with Pro Controller picked first.
    The choice the game's kind prefers is the one highlighted to start.

    WHAT IT RETURNS (exit code, read by wiiu-launch.vbs)
      10  Wii Remotes          -> launch line gets  -use_wiimotes 4
      20  Pro Controller       -> launch line gets  -use_wiimotes 0
      30  do not ask, launch as normal
      40  backed out (B / Esc) -> the game does not start
    Anything going wrong at all means 30. It can never stop a game launching
    by accident.

    CONTROLS: any controller (d-pad / stick, A, B), the keyboard (arrows,
    Enter, Esc) or the mouse. Reads pads through RetroBat's own SDL2.dll,
    the same way the Setup Wizard does (scripts\PadInput.ps1).

    OTHER CONSOLES (2026-10-17, -System). The same screen, reached the same
    way through a launch wrapper:
      wii       wii-nand-launch.vbs. Only games that play either way
                (controllers.ini kind "remote-or-pad") are asked: Wii Remotes
                (10, through the Wii Menu as usual) or a controller (20,
                straight into the game, so no Wii Remote is needed to get
                past the Wii Menu). Every other Wii game: no screen (30).
      flash, scummvm, windows
                game-launch.vbs. A "how this game plays" screen (info mode):
                made for mouse and keyboard, and how the controller works in
                it - the game's own key layout from flash-games.ini or
                browser-games.ini, or the couch mouse. PLAY (30) or Back (40).
                Y (or the D key) means "do not show this again for this
                game", kept in wizard\howtoplay-seen.txt. PC games only get
                it when they are browser games or have a key layout.
                Switched off with howtoplay = off in features.ini.

    No drive letters - everything comes from -Root. Windows PowerShell 5.1.
    ASCII only.
#>
param(
    [string]$Root = '',
    [string]$Rom  = '',
    [string]$System = 'wiiu'
)

$ErrorActionPreference = 'Stop'
$CODE_WIIMOTE = 10; $CODE_PRO = 20; $CODE_ASIS = 30; $CODE_BACK = 40

function Log([string]$t) {
    try {
        $p = Join-Path $Root '_ClaudeWorkspace\wizard\controller-chooser.log'
        Add-Content -LiteralPath $p -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $t)
    } catch { }
}

try {
    if ($Root -eq '' -or -not (Test-Path -LiteralPath $Root)) { exit $CODE_ASIS }

    # --- the on/off switch (features.ini, 'wiiuchooser') -------------------
    #  Anything other than a clear "off" means on, like every other switch.
    $System = $System.Trim().ToLowerInvariant()
    $isKeys = (@('flash', 'scummvm', 'windows') -contains $System)
    $switchName = $(if ($isKeys) { 'howtoplay' } elseif ($System -eq 'wii') { 'wiichooser' } else { 'wiiuchooser' })
    $feat = Join-Path $Root '_ClaudeWorkspace\features.ini'
    if (Test-Path -LiteralPath $feat) {
        foreach ($l in [System.IO.File]::ReadAllLines($feat)) {
            if ($l -match ('^\s*' + $switchName + '\s*=\s*off\b')) { Log ($switchName + ' switched off in features.ini'); exit $CODE_ASIS }
        }
    }

    # --- which game, and what kind is it? ----------------------------------
    $rel = $Rom.Replace('/', '\')
    $marker = '\roms\' + $System + '\'
    $ix = $rel.ToLowerInvariant().IndexOf($marker)
    if ($ix -ge 0) { $rel = $rel.Substring($ix + $marker.Length) } else { $rel = [System.IO.Path]::GetFileName($rel) }
    $key = $rel.Replace('\', '/').Trim().ToLowerInvariant()

    $kind = ''
    $title = ''
    $note = ''
    $ci = Join-Path $Root '_ClaudeWorkspace\controllers.ini'
    if (Test-Path -LiteralPath $ci) {
        $sec = ''
        foreach ($raw in [System.IO.File]::ReadAllLines($ci, (New-Object System.Text.UTF8Encoding($false)))) {
            $t = $raw.Trim()
            if ($t -eq '' -or $t.StartsWith(';')) { continue }
            if ($t -match '^\[([^\]]+)\]') { $sec = $Matches[1].Trim().ToLowerInvariant(); continue }
            if ($sec -ne $System) { continue }
            $p = $t.Split('|')
            if ($p.Count -lt 2) { continue }
            if ($p[1].Trim().Replace('\', '/').ToLowerInvariant() -eq $key) {
                $kind = $p[0].Trim().ToLowerInvariant()
                if ($p.Count -ge 3) { $title = $p[2].Trim() }
                if ($p.Count -ge 4) { $note = $p[3].Trim() }
                break
            }
        }
    }
    # GamePad games (Steven, 2026-10-14): no question, but the SAME screen,
    # saying how the game plays - so every Wii U game opens the same way and
    # no description has to carry a "Controllers:" line any more. A starts it
    # exactly as RetroBat would (30), B goes back (40).
    $script:infoMode = $false
    $script:infoLines = @()
    $script:keysMode = $false
    $script:wiiMode = ($System -eq 'wii')
    if ($script:wiiMode -and $kind -ne 'remote-or-pad') { Log ("{0}: Wii kind '{1}', no question" -f $key, $kind); exit $CODE_ASIS }
    if ($isKeys) {
        # Seen and ticked "do not show again"?
        $seenF = Join-Path $Root '_ClaudeWorkspace\wizard\howtoplay-seen.txt'
        $leaf = [System.IO.Path]::GetFileName($rel).ToLowerInvariant()
        if ((Test-Path -LiteralPath $seenF) -and (@([System.IO.File]::ReadAllLines($seenF) | ForEach-Object { $_.Trim().ToLowerInvariant() }) -contains ($System + '/' + $leaf))) { exit $CODE_ASIS }
        # The game's layout (KeyLayouts.ps1: the person's own, else the
        # game's default), and whether it is a browser game.
        $script:kWs = Join-Path $Root '_ClaudeWorkspace'
        . (Join-Path $script:kWs 'scripts\KeyLayouts.ps1')
        $script:kLeaf = [System.IO.Path]::GetFileName($rel)
        $isBrowser = (Read-KlSection (Join-Path $script:kWs 'browser-games.ini') $script:kLeaf).Found
        # its name, when one of the lists gives it one
        foreach ($ini in @('flash-games.ini', 'browser-games.ini')) {
            if ($title -ne '') { break }
            $fi = Join-Path $script:kWs $ini
            if (-not (Test-Path -LiteralPath $fi)) { continue }
            $in = $false
            foreach ($raw in [System.IO.File]::ReadAllLines($fi)) {
                $t = $raw.Trim()
                if ($t -match '^\[(.+)\]$') { if ($in) { break }; $in = ($Matches[1].Trim() -ieq $script:kLeaf); continue }
                if ($in -and $t -match '^name\s*=\s*(.+)$') { $title = $Matches[1].Trim(); break }
            }
        }
        $lay = Get-KlLayout $script:kWs $script:kLeaf
        # A PC game only when the couch mouse runs in it: a browser game
        # (its .bat goes through Launch-Browser) or one with a key layout.
        if ($System -eq 'windows' -and $lay.Keys -eq '' -and $lay.Stick -eq '') {
            $cmOn = $false
            try { if ((Get-Item -LiteralPath $Rom).Length -lt 16KB) { $cmOn = ([System.IO.File]::ReadAllText($Rom) -match 'Launch-Browser|(?i)couch\s*mouse\s*=\s*on') } } catch { }
            if (-not $cmOn) { exit $CODE_ASIS }
        }
        $script:infoMode = $true; $script:keysMode = $true
        # (Steven, 2026-10-25) say it is a keyboard game, but that the
        # controller is set up, and let them change the buttons right here.
        function Set-KeyLines {
            $l2 = Get-KlLayout $script:kWs $script:kLeaf
            $what = $(if ($System -eq 'scummvm') { 'This game is made for a mouse' } else { 'This game is made for a mouse and keyboard' })
            $script:infoLines = @()
            if ($l2.Keys -ne '' -or $l2.Stick -eq 'arrows') {
                $script:infoLines += ($what + ', but your controller is set up for it:')
                $script:infoLines += (Format-KlLayout $l2) + $(if ($l2.From -eq 'mine') { '   (your own layout)' } else { '' })
                $script:infoLines += 'Need the mouse too? Push in the left stick; push it in again to go back to the keys.'
            }
            elseif ($System -eq 'scummvm') {
                $script:infoLines += ($what + ', but your controller works as one: the left stick moves the pointer, A clicks, B is the right click.')
            }
            else {
                $script:infoLines += ($what + ', but your controller works as the mouse: push in the left stick to switch it on (the stick moves the pointer, A clicks), and again to switch it off.')
            }
            $script:infoLines += 'X: change which key each button presses.     Y: do not show this again for this game.'
        }
        Set-KeyLines
    }
    elseif ($System -eq 'wiiu' -and $kind -ne '' -and $kind -ne 'party-wiimotes' -and $kind -ne 'pro') {
        $script:infoMode = $true
        $script:infoLines += 'Use a controller: Xbox, PlayStation, Switch Pro and the like.'
        if ($kind -eq 'pro-p1gamepad') {
            $script:infoLines += "Player 1's controller acts as the Wii U GamePad, so nothing extra is needed."
        }
        else {
            $script:infoLines += "This game also needs the GamePad's touch screen. It opens in its own window; a second monitor makes that easiest."
            $script:infoLines += 'To tap it: push in the left stick, then the right stick moves the pointer and pushing the right stick in taps. Push in the left stick again to go back to playing.'
            if ($kind -eq 'touch-extras-wiimote') { $script:infoLines += 'Players 2 to 4 use controllers too; the game sees them as sideways Wii Remotes.' }
        }
        if ($note -ne '') { $script:infoLines += $note }
    }
    if ($title -eq '') {
        $title = [System.IO.Path]::GetFileNameWithoutExtension($rel)
        if ($title -match '^(code|content)$' -or $title -match '\.rpx$') { $title = Split-Path (Split-Path $rel -Parent) -Leaf }
        $title = ($title -replace '\s*[\(\[].*$', '').Trim()
    }
    $sel = 1                      # 0 = Wii Remotes, 1 = Pro Controller
    if ($kind -eq 'party-wiimotes') { $sel = 0 }

    # --- the window ---------------------------------------------------------
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $cBg     = [System.Drawing.Color]::FromArgb(235, 12, 12, 16)
    $cPanel  = [System.Drawing.Color]::FromArgb(255, 30, 31, 38)
    $cTile   = [System.Drawing.Color]::FromArgb(255, 40, 42, 52)
    $cTileOn = [System.Drawing.Color]::FromArgb(255, 58, 61, 76)
    $cEdgeOn = [System.Drawing.Color]::FromArgb(255, 235, 235, 240)
    $cIcon   = [System.Drawing.Color]::FromArgb(255, 150, 152, 160)
    $cIconOn = [System.Drawing.Color]::FromArgb(255, 205, 207, 214)
    $cText   = [System.Drawing.Color]::FromArgb(255, 240, 240, 244)
    $cDim    = [System.Drawing.Color]::FromArgb(255, 140, 142, 152)

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.WindowState = 'Maximized'
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 12, 12, 16)
    $form.KeyPreview = $true
    $form.ShowInTaskbar = $false
    $form.Text = 'Choose controllers'
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $prop = $form.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    $prop.SetValue($form, $true, $null)

    # The Pro Controller picture: wizard\pro-controller.png. Missing = the
    # drawn one below is used instead.
    $script:proImg = $null
    try {
        $pf = Join-Path $Root '_ClaudeWorkspace\wizard\pro-controller.png'
        if (Test-Path -LiteralPath $pf) {
            $bytes = [System.IO.File]::ReadAllBytes($pf)
            $script:proImg = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,$bytes)))
        }
    } catch { $script:proImg = $null }
    # Keyboard games show Steven's mouse picture instead (2026-10-17).
    if ($script:keysMode) {
        try {
            $mf = Join-Path $Root '_ClaudeWorkspace\wizard\profile-mouse.png'
            if (Test-Path -LiteralPath $mf) { $script:proImg = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,[System.IO.File]::ReadAllBytes($mf)))) }
        } catch { }
    }
    $cm = New-Object System.Drawing.Imaging.ColorMatrix
    $cm.Matrix00 = 0.73; $cm.Matrix11 = 0.73; $cm.Matrix22 = 0.73
    $script:dimAttr = New-Object System.Drawing.Imaging.ImageAttributes
    $script:dimAttr.SetColorMatrix($cm)

    $script:result = $CODE_ASIS
    $script:sel = $sel
    $script:tiles = @($null, $null)
    $script:backRect = $null
    $script:lastTile = $sel

    $fTitle = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
    $fSub   = New-Object System.Drawing.Font('Segoe UI', 13)
    $fLabel = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $fHint  = New-Object System.Drawing.Font('Segoe UI', 12)

    function New-RoundPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = $r * 2
        if ($d -gt $w) { $d = $w }; if ($d -gt $h) { $d = $h }
        $gp.AddArc($x, $y, $d, $d, 180, 90)
        $gp.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
        $gp.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
        $gp.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
        $gp.CloseFigure()
        return $gp
    }

    # A Wii Remote, standing up: long body, d-pad, A button, - HOME +, 1 and 2.
    function Draw-Wiimote($g, [float]$cx, [float]$cy, [float]$s, $col) {
        $w = 46 * $s; $h = 190 * $s
        $x = $cx - $w / 2; $y = $cy - $h / 2
        $body = New-RoundPath $x $y $w $h (18 * $s)
        $g.FillPath((New-Object System.Drawing.SolidBrush($col)), $body)
        $dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 30, 31, 38))
        $a = 9 * $s; $l = 26 * $s
        $g.FillRectangle($dark, $cx - $a / 2, $y + 18 * $s, $a, $l)
        $g.FillRectangle($dark, $cx - $l / 2, $y + 18 * $s + ($l - $a) / 2, $l, $a)
        $r = 15 * $s
        $g.FillEllipse($dark, $cx - $r / 2, $y + 58 * $s, $r, $r)
        foreach ($dx in @(-12, 0, 12)) { $g.FillEllipse($dark, $cx + $dx * $s - 3 * $s, $y + 92 * $s, 6 * $s, 6 * $s) }
        $g.FillEllipse($dark, $cx - 6 * $s, $y + 132 * $s, 12 * $s, 12 * $s)
        $g.FillEllipse($dark, $cx - 6 * $s, $y + 152 * $s, 12 * $s, 12 * $s)
    }

    # The Pro Controller tile.
    function Draw-Pro($g, [float]$cx, [float]$cy, [float]$s, $col) {
        # An Xbox-style pad (Steven, 2026-10-14: "closer to an Xbox shape").
        # Drawn on a 200 x 140 grid centred on (cx, cy).
        $ox = $cx - 100 * $s; $oy = $cy - 70 * $s
        $br = New-Object System.Drawing.SolidBrush($col)
        foreach ($grip in @(@(46, 22), @(154, -22))) {
            $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
            $gp.AddEllipse([float]($ox + ($grip[0] - 33) * $s), [float]($oy + (82 - 52) * $s), [float](66 * $s), [float](104 * $s))
            $m = New-Object System.Drawing.Drawing2D.Matrix
            $m.RotateAt([float]$grip[1], (New-Object System.Drawing.PointF([float]($ox + $grip[0] * $s), [float]($oy + 82 * $s))))
            $gp.Transform($m)
            $g.FillPath($br, $gp)
        }
        $g.FillPath($br, (New-RoundPath ($ox + 8 * $s) ($oy + 4 * $s) (184 * $s) (70 * $s) (36 * $s)))
        $g.FillPath($br, (New-RoundPath ($ox + 50 * $s) ($oy + 40 * $s) (100 * $s) (60 * $s) (30 * $s)))
        $dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 30, 31, 38))
        $mid  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 70, 72, 84))
        foreach ($st in @(@(54, 36), @(128, 70))) {
            $g.FillEllipse($dark, $ox + ($st[0] - 14) * $s, $oy + ($st[1] - 14) * $s, 28 * $s, 28 * $s)
            $g.FillEllipse($mid,  $ox + ($st[0] - 9) * $s,  $oy + ($st[1] - 9) * $s,  18 * $s, 18 * $s)
        }
        $a = 8 * $s; $l = 26 * $s; $dx = $ox + 76 * $s; $dy = $oy + 70 * $s
        $g.FillRectangle($dark, $dx - $a / 2, $dy - $l / 2, $a, $l)
        $g.FillRectangle($dark, $dx - $l / 2, $dy - $a / 2, $l, $a)
        $bx = $ox + 150 * $s; $by = $oy + 36 * $s; $b = 12 * $s; $o = 12 * $s
        foreach ($p in @(@(0, -1), @(1, 0), @(0, 1), @(-1, 0))) {
            $g.FillEllipse($dark, $bx + $p[0] * $o - $b / 2, $by + $p[1] * $o - $b / 2, $b, $b)
        }
        $g.FillEllipse($dark, $ox + 91 * $s, $oy + 11 * $s, 18 * $s, 18 * $s)
        $g.FillPath($dark, (New-RoundPath ($ox + 82 * $s) ($oy + 37 * $s) (10 * $s) (6 * $s) (3 * $s)))
        $g.FillPath($dark, (New-RoundPath ($ox + 108 * $s) ($oy + 37 * $s) (10 * $s) (6 * $s) (3 * $s)))
    }

    $form.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $W = $form.ClientSize.Width; $H = $form.ClientSize.Height
        $sc = [Math]::Min($W / 1920.0, $H / 1080.0); if ($sc -lt 0.55) { $sc = 0.55 }

        $pw = 1100 * $sc; $ph = 620 * $sc
        $px = ($W - $pw) / 2; $py = ($H - $ph) / 2
        $g.FillPath((New-Object System.Drawing.SolidBrush($cPanel)), (New-RoundPath $px $py $pw $ph (22 * $sc)))

        $center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'; $center.LineAlignment = 'Center'
        $center.Trimming = 'EllipsisCharacter'; $center.FormatFlags = 'NoWrap'
        $g.DrawString($title.ToUpperInvariant(), $fTitle, (New-Object System.Drawing.SolidBrush($cText)), (New-Object System.Drawing.RectangleF(($px + 30 * $sc), ($py + 30 * $sc), ($pw - 60 * $sc), (60 * $sc))), $center)
        # "< Back" for the mouse (Steven, 2026-10-14). Up on the d-pad
        # reaches it too; it is selection 2.
        $bw = 150 * $sc; $bh = 50 * $sc
        $script:backRect = New-Object System.Drawing.RectangleF(($px + 24 * $sc), ($py + 24 * $sc), $bw, $bh)
        $bOn = ($script:sel -eq 2)
        $bp = New-RoundPath ($px + 24 * $sc) ($py + 24 * $sc) $bw $bh (12 * $sc)
        if ($bOn) { $g.FillPath((New-Object System.Drawing.SolidBrush($cTileOn)), $bp); $g.DrawPath((New-Object System.Drawing.Pen($cEdgeOn, (3 * $sc))), $bp) }
        else      { $g.FillPath((New-Object System.Drawing.SolidBrush($cTile)), $bp) }
        $bc = $cDim; if ($bOn) { $bc = $cText }
        $g.DrawString('<  Back', $fHint, (New-Object System.Drawing.SolidBrush($bc)), $script:backRect, $center)
        $subTop = 'How are you playing?'
        if ($script:infoMode) { $subTop = 'How this game plays' }
        $g.DrawString($subTop, $fSub, (New-Object System.Drawing.SolidBrush($cDim)), (New-Object System.Drawing.RectangleF($px, ($py + 88 * $sc), $pw, (34 * $sc))), $center)

        $tw = 440 * $sc; $th = 360 * $sc; $gap = 60 * $sc
        if ($script:infoMode) { $th = 250 * $sc }
        $ty = $py + 145 * $sc
        $tx0 = $px + ($pw - (2 * $tw + $gap)) / 2
        for ($i = 0; $i -lt 2; $i++) {
            if ($script:infoMode -and $i -eq 0) { $script:tiles[0] = $null; continue }
            $tx = $tx0 + $i * ($tw + $gap)
            if ($script:infoMode) { $tx = $px + ($pw - $tw) / 2 }
            $on = ($i -eq $script:sel)
            $rect = New-Object System.Drawing.RectangleF($tx, $ty, $tw, $th)
            $script:tiles[$i] = $rect
            $tp = New-RoundPath $tx $ty $tw $th (18 * $sc)
            if ($on) { $g.FillPath((New-Object System.Drawing.SolidBrush($cTileOn)), $tp) } else { $g.FillPath((New-Object System.Drawing.SolidBrush($cTile)), $tp) }
            if ($on) { $g.DrawPath((New-Object System.Drawing.Pen($cEdgeOn, (4 * $sc))), $tp) }
            $ic = $cIcon; if ($on) { $ic = $cIconOn }
            $icy = $ty + 135 * $sc
            if ($script:infoMode) { $icy = $ty + 95 * $sc }
            if ($i -eq 0) {
                Draw-Wiimote $g ($tx + $tw / 2 - 34 * $sc) $icy (0.95 * $sc) $ic
                Draw-Wiimote $g ($tx + $tw / 2 + 34 * $sc) $icy (0.95 * $sc) $ic
                $label = 'LAUNCH WITH WII REMOTES'
            } else {
                if ($null -ne $script:proImg) {
                    # Steven's own picture (2026-10-14), recoloured to match.
                    $iw = 290 * $sc; if ($script:infoMode) { $iw = 220 * $sc }
                    $ih = $iw * $script:proImg.Height / $script:proImg.Width
                    $dst = New-Object System.Drawing.Rectangle([int]($tx + ($tw - $iw) / 2), [int]($icy - $ih / 2), [int]$iw, [int]$ih)
                    $g.InterpolationMode = $(if ($script:keysMode) { 'NearestNeighbor' } else { 'HighQualityBicubic' })
                    $g.PixelOffsetMode = $(if ($script:keysMode) { 'Half' } else { 'Default' })
                    if ($on) { $g.DrawImage($script:proImg, $dst) }
                    else { $g.DrawImage($script:proImg, $dst, 0, 0, $script:proImg.Width, $script:proImg.Height, [System.Drawing.GraphicsUnit]::Pixel, $script:dimAttr) }
                } else { Draw-Pro $g ($tx + $tw / 2) ($icy + 4 * $sc) (1.2 * $sc) $ic }
                $label = $(if ($script:wiiMode) { 'LAUNCH WITH A CONTROLLER' } else { 'LAUNCH WITH A PRO CONTROLLER' })
                if ($script:infoMode) { $label = $(if ($script:keysMode) { 'CONTINUE TO THE GAME' } else { 'PLAY' }) }
            }
            $lc = $cDim; if ($on) { $lc = $cText }
            $ly = $ty + $th - 80 * $sc; if ($script:infoMode) { $ly = $ty + $th - 62 * $sc }
            $g.DrawString($label, $fLabel, (New-Object System.Drawing.SolidBrush($lc)), (New-Object System.Drawing.RectangleF($tx, $ly, $tw, (50 * $sc))), $center)
        }
        if ($script:infoMode) {
            $wrap = New-Object System.Drawing.StringFormat; $wrap.Alignment = 'Center'
            $iy = $ty + $th + 16 * $sc
            foreach ($ln in $script:infoLines) {
                $r = New-Object System.Drawing.RectangleF(($px + 60 * $sc), $iy, ($pw - 120 * $sc), (200 * $sc))
                $sz = $g.MeasureString($ln, $fSub, [int]($pw - 120 * $sc), $wrap)
                $g.DrawString($ln, $fSub, (New-Object System.Drawing.SolidBrush($cText)), $r, $wrap)
                $iy += $sz.Height + 8 * $sc
            }
        }
        else {
            $sub = 'Real Wii Remotes only. Other controllers will not work.'
            if ($script:wiiMode) { $sub = 'Real Wii Remotes, starting at the Wii Menu.' }
            if ($script:sel -eq 1) { $sub = $(if ($script:wiiMode) { 'Xbox, PlayStation and other controllers, as GameCube controllers. Straight into the game.' } else { 'Xbox, PlayStation, Switch Pro and other controllers.' }) }
            $g.DrawString($sub, $fSub, (New-Object System.Drawing.SolidBrush($cDim)), (New-Object System.Drawing.RectangleF($px, ($ty + $th + 18 * $sc), $pw, (34 * $sc))), $center)
        }
        $hint = $(if ($script:keysMode) { 'A  continue          B  back          X  change buttons          Y  do not show this again' } else { 'A  launch          B  back' })
        $g.DrawString($hint, $fHint, (New-Object System.Drawing.SolidBrush($cDim)), (New-Object System.Drawing.RectangleF($px, ($py + $ph - 52 * $sc), $pw, (34 * $sc))), $center)
    })

    function Save-Seen {
        try {
            $sf = Join-Path $Root '_ClaudeWorkspace\wizard\howtoplay-seen.txt'
            if (-not (Test-Path -LiteralPath $sf)) { [System.IO.File]::WriteAllLines($sf, [string[]]@('; Games whose "how to play" screen was switched off with Y. Delete a line to see it again.')) }
            Add-Content -LiteralPath $sf -Value ($System + '/' + [System.IO.Path]::GetFileName($rel).ToLowerInvariant())
            Log ("{0}: how-to-play switched off for this game" -f $key)
        } catch { }
    }
    # X: the wizard's layout editor for this game, then back here with the
    # new layout on screen (2026-10-25).
    function Edit-Keys {
        try {
            $timer.Stop(); $form.Hide()
            $wiz = Join-Path $Root '_ClaudeWorkspace\wizard\SetupWizard.ps1'
            $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $p = Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $wiz + '"'), '-EditKeys', ('"' + $script:kLeaf + '"')) -WindowStyle Hidden -PassThru
            $p.WaitForExit()
            Set-KeyLines
            Log ("{0}: layout edited from the how-to-play screen" -f $key)
        } catch { Log ('edit keys: ' + $_.Exception.Message) }
        finally { $script:prev = -1; $form.Show(); $form.Activate(); $form.Invalidate(); $timer.Start() }
    }
    function Finish([int]$code) {
        $script:result = $code
        $form.Close()
    }
    function Move-Sel([int]$to) {
        if ($script:infoMode -and $to -eq 0) { return }
        if ($to -ne $script:sel) {
            if ($script:sel -ne 2) { $script:lastTile = $script:sel }
            $script:sel = $to; $form.Invalidate()
        }
    }
    function Pick {
        if ($script:infoMode -and $script:sel -ne 2) { Finish $CODE_ASIS }
        elseif ($script:sel -eq 0) { Finish $CODE_WIIMOTE }
        elseif ($script:sel -eq 1) { Finish $CODE_PRO }
        else { Finish $CODE_BACK }
    }

    $form.Add_KeyDown({
        param($s, $e)
        switch ($e.KeyCode) {
            'Left'   { if ($script:sel -ne 2) { Move-Sel 0 } }
            'Right'  { if ($script:sel -ne 2) { Move-Sel 1 } }
            'Up'     { Move-Sel 2 }
            'Down'   { if ($script:sel -eq 2) { Move-Sel $script:lastTile } }
            'Enter'  { Pick }
            'Space'  { Pick }
            'Escape' { Finish $CODE_BACK }
            'D'      { if ($script:keysMode) { Save-Seen; Finish $CODE_ASIS } }
            'X'      { if ($script:keysMode) { Edit-Keys } }
            'Back'   { Finish $CODE_BACK }
        }
    })
    $form.Add_MouseMove({
        param($s, $e)
        for ($i = 0; $i -lt 2; $i++) { if ($null -ne $script:tiles[$i] -and $script:tiles[$i].Contains([float]$e.X, [float]$e.Y)) { Move-Sel $i } }
        if ($null -ne $script:backRect -and $script:backRect.Contains([float]$e.X, [float]$e.Y)) { Move-Sel 2 }
    })
    $form.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq 'Right') { Finish $CODE_BACK; return }
        if ($null -ne $script:backRect -and $script:backRect.Contains([float]$e.X, [float]$e.Y)) { Finish $CODE_BACK; return }
        for ($i = 0; $i -lt 2; $i++) { if ($null -ne $script:tiles[$i] -and $script:tiles[$i].Contains([float]$e.X, [float]$e.Y)) { $script:sel = $i; Pick } }
    })

    # --- controllers, through RetroBat's own SDL2 ---------------------------
    $script:padOk = $false
    try {
        . (Join-Path $Root '_ClaudeWorkspace\scripts\PadInput.ps1')
        $script:padOk = [RBPad]::Init((Join-Path $Root 'emulationstation\SDL2.dll'))
        if (-not $script:padOk) { Log ('pads: ' + [RBPad]::LastError) }
    } catch { Log ('pads: ' + $_.Exception.Message) }

    # Whatever is held when the window opens (the A that launched the game)
    # has to be let go before it counts, or the window would vanish at once.
    $script:prev = -1
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 40
    $timer.Add_Tick({
        if (-not $script:padOk) { return }
        $now = [RBPad]::Poll()
        if ($script:prev -eq -1) { $script:prev = $now; return }
        $down = $now -band (-bnot $script:prev)
        $script:prev = $now
        if ($down -eq 0) { return }
        if ($down -band ((1 -shl 13) -bor (1 -shl 16))) { if ($script:sel -ne 2) { Move-Sel 0 } }
        if ($down -band ((1 -shl 14) -bor (1 -shl 17))) { if ($script:sel -ne 2) { Move-Sel 1 } }
        if ($down -band ((1 -shl 11) -bor (1 -shl 18))) { Move-Sel 2 }
        if ($down -band ((1 -shl 12) -bor (1 -shl 19))) { if ($script:sel -eq 2) { Move-Sel $script:lastTile } }
        if ($down -band ((1 -shl 0) -bor (1 -shl 6))) { Pick; return }
        if ($down -band (1 -shl 1)) { Finish $CODE_BACK }
        if ($script:keysMode -and ($down -band (1 -shl 3))) { Save-Seen; Finish $CODE_ASIS }
        if ($script:keysMode -and ($down -band (1 -shl 2))) { Edit-Keys }
    })

    $form.Add_Shown({
        $form.Activate()
        $form.Focus()
        $timer.Start()
    })

    [void]$form.ShowDialog()
    $timer.Stop()
    if ($script:padOk) { try { [RBPad]::Quit() } catch { } }
    Log ("{0}: kind '{1}', chose {2}" -f $key, $kind, $script:result)
    exit $script:result
}
catch {
    Log ('error, launching as normal: ' + $_.Exception.Message)
    exit $CODE_ASIS
}
