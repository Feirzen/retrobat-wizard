<#
    ShortcutMakerUI.ps1
    ---------------------------------------------------------------------------
    The "Add a shortcut to a game" window. FUNCTIONS ONLY - dot-source it.

    SELF CONTAINED, like SteamUI.ps1: its own colours and its own little
    helpers, so it runs from a .bat when the wizard is not open.

    THE SHAPE OF IT. Four questions down one page, in the order a person
    actually thinks: which console, which game, which picture, where to put
    it. Nothing is hidden behind a Next button, because all four fit on one
    screen and a person changing their mind about the picture should not have
    to walk back through the console.

    THE PICTURES ARE SHOWN, NOT NAMED. "marquee" and "thumb" mean nothing to
    anybody, and which one survives being shrunk to a desktop icon is
    different for every game. So the window draws each one at roughly icon
    size and the person picks with their eyes. That is the entire reason this
    window exists rather than a line of script.

    RULES HONOURED HERE:
      - no drive letters; everything derives from -Root
      - Windows PowerShell 5.1 only
      - pure ASCII, no byte-order mark
      - event handlers touch script scope only
#>

Set-StrictMode -Off

Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationCore -ErrorAction SilentlyContinue
Add-Type -AssemblyName WindowsBase -ErrorAction SilentlyContinue

$script:ScUiBg    = '#FF1E1E24'
$script:ScUiPanel = '#FF2A2A34'
$script:ScUiText  = '#FFE8E8EC'
$script:ScUiDim   = '#FF9A9AA6'
$script:ScUiGold  = '#FFE5B83B'
$script:ScUiGreen = '#FF7FD17F'
$script:ScUiWarn  = '#FFE0A050'

function New-ScUiBrush([string]$hex) {
    return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)))
}

function New-ScUiText([string]$text, [string]$colour, [int]$size = 14, [bool]$bold = $false) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.Foreground = (New-ScUiBrush $colour)
    $tb.FontSize = $size
    $tb.TextWrapping = 'Wrap'
    if ($bold) { $tb.FontWeight = 'Bold' }
    return $tb
}

# Load a picture WITHOUT leaving the file open. The default behaviour keeps a
# handle on it for as long as the image is on screen, and a held-open file on
# an external drive is how you end up unable to eject it.
function New-ScUiBitmap([string]$path) {
    $fs = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $fs = New-Object System.IO.MemoryStream(,$bytes)
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.DecodePixelWidth = 160
        $bi.StreamSource = $fs
        $bi.EndInit()
        $bi.Freeze()
        return $bi
    }
    catch { return $null }
    finally { if ($fs) { $fs.Dispose() } }
}

# ===========================================================================

function Show-ShortcutMakerWindow {
    param([string]$Root, [string]$Title = 'Add a shortcut to a game', [string]$StartMenuFolder = 'RetroBat Games')

    $script:scuRoot   = $Root
    $script:scuFolder = $StartMenuFolder
    $script:scuGames  = @()
    $script:scuImages = @()
    $script:scuChosen = ''
    $script:scuResult = ''

    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 700
    $w.Height = 640
    $w.WindowStartupLocation = 'CenterScreen'
    $w.ResizeMode = 'NoResize'
    $w.Background = (New-ScUiBrush $script:ScUiBg)
    $script:scuWin = $w

    $outer = New-Object System.Windows.Controls.DockPanel

    # --- header ------------------------------------------------------------
    $header = New-Object System.Windows.Controls.Border
    $header.Background = (New-ScUiBrush $script:ScUiPanel)
    $header.Padding = '22,14,22,14'
    [System.Windows.Controls.DockPanel]::SetDock($header, 'Top')
    $hsp = New-Object System.Windows.Controls.StackPanel
    [void]$hsp.Children.Add((New-ScUiText 'Add a shortcut to a game' $script:ScUiGold 19 $true))
    $sub = New-ScUiText 'Puts one game on this computer''s desktop or Start Menu, so a double-click takes you straight into it.' $script:ScUiDim 13
    $sub.Margin = '0,4,0,0'
    [void]$hsp.Children.Add($sub)
    $header.Child = $hsp
    [void]$outer.Children.Add($header)

    # --- footer ------------------------------------------------------------
    $footer = New-Object System.Windows.Controls.Border
    $footer.Background = (New-ScUiBrush $script:ScUiPanel)
    $footer.Padding = '22,12,22,12'
    [System.Windows.Controls.DockPanel]::SetDock($footer, 'Bottom')
    $frow = New-Object System.Windows.Controls.StackPanel
    $frow.Orientation = 'Horizontal'
    $frow.HorizontalAlignment = 'Right'

    $close = New-Object System.Windows.Controls.Button
    $close.Content = 'Close'; $close.Padding = '16,7'; $close.FontSize = 14; $close.Margin = '8,0,0,0'
    $close.Add_Click({ $script:scuWin.Close() })
    [void]$frow.Children.Add($close)

    $script:scuTestBtn = New-Object System.Windows.Controls.Button
    $script:scuTestBtn.Content = 'Try it now'; $script:scuTestBtn.Padding = '16,7'; $script:scuTestBtn.FontSize = 14; $script:scuTestBtn.Margin = '8,0,0,0'
    $script:scuTestBtn.Add_Click({ Invoke-ScuTest })
    [void]$frow.Children.Add($script:scuTestBtn)

    $script:scuMakeBtn = New-Object System.Windows.Controls.Button
    $script:scuMakeBtn.Content = 'Make the shortcut'; $script:scuMakeBtn.Padding = '16,7'; $script:scuMakeBtn.FontSize = 14; $script:scuMakeBtn.Margin = '8,0,0,0'
    $script:scuMakeBtn.Add_Click({ Invoke-ScuMake })
    [void]$frow.Children.Add($script:scuMakeBtn)

    $footer.Child = $frow
    [void]$outer.Children.Add($footer)

    # --- the four questions ------------------------------------------------
    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $scroll.Padding = '22,16,22,16'
    $body = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $body
    [void]$outer.Children.Add($scroll)

    # 1. console
    $l1 = New-ScUiText '1.  Which console' $script:ScUiText 15 $true
    $l1.Margin = '0,0,0,6'
    [void]$body.Children.Add($l1)

    $script:scuSystemBox = New-Object System.Windows.Controls.ComboBox
    $script:scuSystemBox.FontSize = 14
    $script:scuSystemBox.Margin = '0,0,0,16'
    $script:scuSystemBox.Add_SelectionChanged({ Update-ScuGames })
    [void]$body.Children.Add($script:scuSystemBox)

    # 2. game
    $l2 = New-ScUiText '2.  Which game' $script:ScUiText 15 $true
    $l2.Margin = '0,0,0,6'
    [void]$body.Children.Add($l2)

    $script:scuGameBox = New-Object System.Windows.Controls.ComboBox
    $script:scuGameBox.FontSize = 14
    $script:scuGameBox.Margin = '0,0,0,16'
    $script:scuGameBox.Add_SelectionChanged({ Update-ScuImages })
    [void]$body.Children.Add($script:scuGameBox)

    # 3. picture
    $l3 = New-ScUiText '3.  Which picture for the icon' $script:ScUiText 15 $true
    $l3.Margin = '0,0,0,2'
    [void]$body.Children.Add($l3)

    $l3b = New-ScUiText 'They all get squashed down to a very small square, and which one still reads at that size is different for every game. Pick with your eyes.' $script:ScUiDim 13
    $l3b.Margin = '0,0,0,8'
    [void]$body.Children.Add($l3b)

    $script:scuImagePanel = New-Object System.Windows.Controls.WrapPanel
    $script:scuImagePanel.Margin = '0,0,0,6'
    [void]$body.Children.Add($script:scuImagePanel)

    $script:scuImageNote = New-ScUiText '' $script:ScUiDim 13
    $script:scuImageNote.Margin = '0,0,0,16'
    [void]$body.Children.Add($script:scuImageNote)

    # 4. where
    $l4 = New-ScUiText '4.  Where to put it' $script:ScUiText 15 $true
    $l4.Margin = '0,0,0,6'
    [void]$body.Children.Add($l4)

    $script:scuDesk = New-Object System.Windows.Controls.CheckBox
    $script:scuDesk.Content = 'Desktop'
    $script:scuDesk.Foreground = (New-ScUiBrush $script:ScUiText)
    $script:scuDesk.FontSize = 15
    $script:scuDesk.IsChecked = $true
    [void]$body.Children.Add($script:scuDesk)

    $script:scuStart = New-Object System.Windows.Controls.CheckBox
    $script:scuStart.Content = ('Start Menu, in a folder called ' + $StartMenuFolder)
    $script:scuStart.Foreground = (New-ScUiBrush $script:ScUiText)
    $script:scuStart.FontSize = 15
    $script:scuStart.Margin = '0,8,0,0'
    [void]$body.Children.Add($script:scuStart)

    $why = New-ScUiText 'How it works: the shortcut quietly opens RetroBat, has it start the game exactly as if you picked it (so controllers, SELECT + START and the save backup all work), and closes RetroBat again when you quit. Expect a few seconds of RetroBat''s loading screen first. Steam games go straight to Steam instead.' $script:ScUiDim 13
    $why.Margin = '0,16,0,0'
    [void]$body.Children.Add($why)

    $note = New-ScUiText 'The picture is copied onto this computer, so the icon still looks right after the drive is unplugged. Clicking it then just says it cannot find the game, which is the polite version of what would otherwise be a blank white square.' $script:ScUiDim 13
    $note.Margin = '0,14,0,0'
    [void]$body.Children.Add($note)

    $script:scuStatus = New-ScUiText '' $script:ScUiGreen 14
    $script:scuStatus.Margin = '0,14,0,0'
    [void]$body.Children.Add($script:scuStatus)

    $w.Content = $outer

    # fill the first dropdown
    try {
        $systems = @(Get-ScSystems -Root $Root)
        $script:scuSystems = $systems
        foreach ($s in $systems) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = ('{0}   ({1} games)' -f $s.FullName, $s.GameCount)
            $item.Tag = $s.Name
            [void]$script:scuSystemBox.Items.Add($item)
        }
        if ($systems.Count -gt 0) { $script:scuSystemBox.SelectedIndex = 0 }
    }
    catch { }

    [void]$w.ShowDialog()
    return $script:scuResult
}

# --- when the console changes ----------------------------------------------

function Get-ScuSystem {
    try {
        $sel = $script:scuSystemBox.SelectedItem
        if ($null -eq $sel) { return '' }
        return [string]$sel.Tag
    }
    catch { return '' }
}

function Get-ScuGame {
    try {
        $i = $script:scuGameBox.SelectedIndex
        if ($i -lt 0 -or $i -ge @($script:scuGames).Count) { return $null }
        return $script:scuGames[$i]
    }
    catch { return $null }
}

function Update-ScuGames {
    try {
        $sys = Get-ScuSystem
        $script:scuGameBox.Items.Clear()
        $script:scuGames = @()
        if ($sys -eq '') { return }

        $script:scuGames = @(Get-ScGames -Root $script:scuRoot -System $sys)
        foreach ($g in $script:scuGames) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $g.Name
            [void]$script:scuGameBox.Items.Add($item)
        }
        if (@($script:scuGames).Count -gt 0) { $script:scuGameBox.SelectedIndex = 0 }
        else { Update-ScuImages }
    }
    catch { }
}

# --- when the game changes -------------------------------------------------

function Update-ScuImages {
    try {
        $script:scuImagePanel.Children.Clear()
        $script:scuImages = @()
        $script:scuChosen = ''
        $script:scuImageNote.Text = ''
        $script:scuStatus.Text = ''

        $sys = Get-ScuSystem
        $game = Get-ScuGame
        if ($sys -eq '' -or $null -eq $game) { return }

        $script:scuImages = @(Get-ScGameImages -Root $script:scuRoot -System $sys -FileBase $game.FileBase)

        if (@($script:scuImages).Count -eq 0) {
            $script:scuImageNote.Text = 'No pictures have been scraped for this game, so the shortcut gets Windows'' plain icon. Scraping it in RetroBat first would fix that.'
            return
        }

        foreach ($img in $script:scuImages) {
            $b = New-Object System.Windows.Controls.Button
            $b.Width = 104
            $b.Height = 124
            $b.Margin = '0,0,10,10'
            $b.Padding = '4'
            $b.Tag = $img.Path
            $b.Background = (New-ScUiBrush $script:ScUiPanel)
            $b.BorderBrush = (New-ScUiBrush $script:ScUiPanel)
            $b.BorderThickness = '2'

            $sp = New-Object System.Windows.Controls.StackPanel

            $pic = New-Object System.Windows.Controls.Image
            $pic.Height = 82
            $pic.Stretch = 'Uniform'
            $bi = New-ScUiBitmap $img.Path
            if ($null -ne $bi) { $pic.Source = $bi }
            [void]$sp.Children.Add($pic)

            $cap = New-ScUiText $img.Label $script:ScUiDim 12
            $cap.Margin = '0,6,0,0'
            $cap.TextAlignment = 'Center'
            [void]$sp.Children.Add($cap)

            $b.Content = $sp
            $b.Add_Click({ param($s, $e) Select-ScuImage ([string]$s.Tag) })
            [void]$script:scuImagePanel.Children.Add($b)
        }

        # The first one is the best guess for an icon, so it starts chosen.
        Select-ScuImage ([string]$script:scuImages[0].Path)
    }
    catch { }
}

function Select-ScuImage([string]$path) {
    try {
        $script:scuChosen = $path
        foreach ($child in @($script:scuImagePanel.Children)) {
            if ([string]$child.Tag -eq $path) {
                $child.BorderBrush = (New-ScUiBrush $script:ScUiGold)
            }
            else {
                $child.BorderBrush = (New-ScUiBrush $script:ScUiPanel)
            }
        }
        $label = ''
        foreach ($img in @($script:scuImages)) { if ($img.Path -eq $path) { $label = $img.Label; break } }
        if ($label -ne '') { $script:scuImageNote.Text = ('Using: ' + $label) }
    }
    catch { }
}

# --- the two buttons -------------------------------------------------------

function Invoke-ScuTest {
    try {
        $sys = Get-ScuSystem
        $game = Get-ScuGame
        if ($sys -eq '' -or $null -eq $game) { return }

        $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiDim)
        $script:scuStatus.Text = ('Starting ' + $game.Name + '...')

        if (Start-ScGameNow -Root $script:scuRoot -System $sys -RomPath $game.RomPath) {
            $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiGreen)
            $script:scuStatus.Text = 'Starting it the same way the shortcut will. RetroBat opens first, then the game. If the game comes up and the controller works, the shortcut will too.'
        }
        else {
            $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiWarn)
            $script:scuStatus.Text = 'Could not start it. A shortcut would not work either, so it is worth sorting that out first.'
        }
    }
    catch { }
}

function Invoke-ScuMake {
    try {
        $sys = Get-ScuSystem
        $game = Get-ScuGame
        if ($sys -eq '' -or $null -eq $game) { return }

        $places = @()
        if ($script:scuDesk.IsChecked)  { $places += 'desktop' }
        if ($script:scuStart.IsChecked) { $places += 'start' }

        if ($places.Count -eq 0) {
            $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiWarn)
            $script:scuStatus.Text = 'Tick the desktop, the Start Menu, or both.'
            return
        }

        $script:scuMakeBtn.IsEnabled = $false
        $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiDim)
        $script:scuStatus.Text = 'Working...'
        try { $script:scuWin.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{}) | Out-Null } catch { }

        $r = New-ScGameShortcut -Root $script:scuRoot -System $sys -RomPath $game.RomPath `
                -Name $game.Name -FileBase $game.FileBase -ImagePath $script:scuChosen `
                -Places $places -StartMenuFolder $script:scuFolder

        $script:scuMakeBtn.IsEnabled = $true

        if ($r.Ok) {
            $where = @()
            foreach ($p in @($r.Written)) { $where += (Split-Path $p -Parent) }
            $msg = ($game.Name + ' is now in: ' + (($where | Select-Object -Unique) -join '  and  '))
            if ($r.Icon -eq '' -and $script:scuChosen -ne '') {
                $msg += '   (the picture could not be turned into an icon, so it has Windows'' plain one)'
            }
            $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiGreen)
            $script:scuStatus.Text = $msg
            $script:scuResult = 'made'
        }
        else {
            $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiWarn)
            $script:scuStatus.Text = ('It did not work: ' + $r.Problem)
        }
    }
    catch {
        $script:scuMakeBtn.IsEnabled = $true
        $script:scuStatus.Foreground = (New-ScUiBrush $script:ScUiWarn)
        $script:scuStatus.Text = ('It did not work: ' + $_.Exception.Message)
    }
}
