<#
    AdminUI.ps1 - the Admin page of the wizard: reports, Stable or Dev, the
    shared scraper login, names, the admins list, and publishing games to the
    online library.

    PART OF THE ADMIN TOOLS, A DOWNLOAD OF ITS OWN (Steven, 2026-10-17: "add
    the admin as its own download"). It is not in manifest.txt, so ordinary
    setups never get it; it is in admin-manifest.txt with AdminEngine.ps1, and
    a person on the admins list fetches both from their Admin page
    (Install-UpdAdminPack in UpdateEngine.ps1). Every update after that brings
    the matching copy.

    FUNCTIONS ONLY. Dot-sourced by wizard\SetupWizard.ps1 at the top, after
    AdminEngine.ps1, and only when both are here. The functions use the
    wizard's own helpers (New-Text, New-SocialButton, Show-Choice, ...), so it
    is no use on its own. Without it, the wizard's Admin page shows one card,
    "Get the admin tools".

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Invoke-AdminRefresh {
    $script:adminNote = 'Checking...'; Render-Admin
    try { $script:win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
    $r = Get-AdminReports $Ws
    $script:adminReports = $r
    $script:adminTopic = Get-SocialNotifyTopic $Ws
    $script:adminNote = $(if ($r.Ok) { 'Updated ' + (Get-Date -Format 'h:mm tt') + '.' } else { $r.Message })
    Start-SocialFetch
    Render-Admin
}

# ---------------------------------------------------------------------------
#  STABLE OR DEV                                                (2026-10-12)
# ---------------------------------------------------------------------------
#  Steven: "a dev branch toggle on the admin's wizard, so I can see the
#  latest update that's active, or toggle the dev branch and see the one
#  under development and work on it with Claude." Two buttons, the chosen
#  one lit. Choosing writes update\update.ini and looks on GitHub at once;
#  the usual Update now bar does the rest, so nothing installs without a
#  press. The engine (UpdateEngine.ps1, TWO CHANNELS) explains the rules.
function Add-AdminChannelCard($panel) {
    if (-not $script:updateOk) { return }
    #  Rebuilt 2026-10-17. Steven: "I'm never sure which I'm looking at,
    #  because one's green and the other is gold", and switching then needed a
    #  second press on the Update now bar. Now: one badge that SAYS which one
    #  this drive runs, what each channel holds on GitHub, and one press to
    #  switch, which asks once and then shows the download and install.
    $cfg = $null; $inst = $null
    try { $cfg = Get-UpdConfig $Ws; $inst = Get-UpdInstalled $Ws } catch { return }
    $ci = $null; try { $ci = Read-UpdChannelInfo $Ws } catch { }
    $workshop = $false; try { $workshop = Test-UpdWorkshop $Ws } catch { }
    $gold = '#FFE5B83B'; $violet = '#FF9B7BFF'
    $card = New-Object System.Windows.Controls.Border
    $card.Background = (New-Brush $ColPanel); $card.Padding = '16,12'; $card.Margin = '0,12,0,0'; $card.CornerRadius = '6'
    $sp = New-Object System.Windows.Controls.StackPanel

    # --- what this drive runs, said in words, in one badge ------------------
    $hd = New-Object System.Windows.Controls.StackPanel; $hd.Orientation = 'Horizontal'
    $t = New-Text 'This setup runs' $ColText 15 $true; $t.VerticalAlignment = 'Center'
    [void]$hd.Children.Add($t)
    $runDev = $(if ($inst.Tag -ne '') { $inst.Channel -eq 'dev' } else { $cfg.Channel -eq 'dev' })
    $bd = New-Object System.Windows.Controls.Border
    $bd.CornerRadius = '4'; $bd.Padding = '10,3'; $bd.Margin = '10,0,0,0'; $bd.VerticalAlignment = 'Center'
    $bd.Background = (New-Brush $(if ($runDev) { $violet } else { $gold }))
    $bt = New-Text $(if ($runDev) { ('DEV  ' + $WizardVersion) } else { ('STABLE  ' + $WizardVersion) }) '#FF1B1B22' 13 $true
    $bd.Child = $bt
    [void]$hd.Children.Add($bd)
    if ($workshop) {
        $wb = New-Object System.Windows.Controls.Border
        $wb.CornerRadius = '4'; $wb.Padding = '10,3'; $wb.Margin = '8,0,0,0'; $wb.VerticalAlignment = 'Center'
        $wb.BorderBrush = (New-Brush $gold); $wb.BorderThickness = '1'
        $wb.Child = (New-Text 'WORKSHOP DRIVE' $gold 12 $true)
        [void]$hd.Children.Add($wb)
    }
    [void]$sp.Children.Add($hd)

    # --- what each channel holds right now ----------------------------------
    $sv = $(if ($null -ne $ci -and $ci.StableVersion -ne '') { $ci.StableVersion } else { '...' })
    $dv = $(if ($null -ne $ci -and $ci.DevVersion -ne '') { $ci.DevVersion } else { '...' })
    $grid = New-Object System.Windows.Controls.Grid; $grid.Margin = '0,10,0,0'
    foreach ($w0 in @('Auto', '*')) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w0; [void]$grid.ColumnDefinitions.Add($cd) }
    $rowN = 0
    foreach ($opt in @(@('Stable', 'stable', $sv, 'what everybody has', $gold), @('Dev', 'dev', $dv, 'what Claude is working on next', $violet))) {
        $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = 'Auto'; [void]$grid.RowDefinitions.Add($rd)
        $isOn = ($cfg.Channel -eq $opt[1])
        $b = New-Object System.Windows.Controls.Button
        $b.Padding = '12,5'; $b.FontSize = 13; $b.Margin = '0,4,12,4'; $b.Tag = $opt[1]; $b.MinWidth = 150
        if ($isOn) {
            $b.Content = ([char]0x2714 + '  ' + $opt[0] + ' - in use')
            $b.FontWeight = 'Bold'; $b.BorderBrush = (New-Brush $opt[4]); $b.BorderThickness = '2'; $b.IsHitTestVisible = $false
        }
        elseif ($workshop) { $b.Content = ($opt[0] + ' - off here'); $b.IsEnabled = $false }
        else {
            $b.Content = ('Switch to ' + $opt[0])
            $b.Add_Click({ param($s2, $e2) Invoke-AdminChannel ([string]$s2.Tag) })
        }
        [System.Windows.Controls.Grid]::SetRow($b, $rowN); [System.Windows.Controls.Grid]::SetColumn($b, 0)
        [void]$grid.Children.Add($b)
        $lt = New-Text ('{0} on GitHub: {1}  -  {2}' -f $opt[0], $opt[2], $opt[3]) $ColDim 13
        $lt.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetRow($lt, $rowN); [System.Windows.Controls.Grid]::SetColumn($lt, 1)
        [void]$grid.Children.Add($lt)
        $rowN++
    }
    [void]$sp.Children.Add($grid)

    # --- what it means ---------------------------------------------------
    if ($workshop) {
        $why = 'This is the workshop drive: Claude puts new work straight onto it, so it already has the newest of everything, and updates never install here (that keeps an older copy from GitHub from landing on top of new work). Stable and Dev only matter on other drives and fresh installs.'
    }
    else {
        $why = 'Switching downloads the other version and installs it straight away, with a progress window (usually under a minute). Saves, games and settings stay. Switch back the same way any time.'
        try {
            $st = Read-UpdStatus $Ws
            if ([string]$st['state'] -eq 'available' -or [string]$st['state'] -eq 'ready') {
                $why = ('A newer {0} version ({1}) is waiting: press Update now at the top. ' -f $(if ($cfg.Channel -eq 'dev') { 'Dev' } else { 'Stable' }), [string]$st['version']) + $why
            }
        } catch { }
    }
    $wt = New-Text $why $ColDim 12; $wt.Margin = '0,8,0,0'
    [void]$sp.Children.Add($wt)
    $card.Child = $sp
    [void]$panel.Children.Add($card)
}

# New setups scrape box art by themselves with a shared ScreenScraper login
# (Steven's choice, 2026-10-17). Since 3.2 (2026-10-26) it never goes in the
# public download: this keeps the login in Owner\scraper.txt and puts a copy
# LOCKED with the friends key in the private friends store
# (shared/scraper.txt), which every new setup fetches during its setup.
function Add-AdminScraperCard($panel) {
    if (-not $script:frdOk) { return }
    $card = New-Object System.Windows.Controls.Border
    $card.Background = (New-Brush $ColPanel); $card.Padding = '16,12'; $card.Margin = '0,12,0,0'; $card.CornerRadius = '6'
    $sp = New-Object System.Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text 'Box art for new setups' $ColText 15 $true))
    $has = Test-Path -LiteralPath (Join-Path $Ws 'Owner\scraper.txt')
    $t = New-Text $(if ($has) { 'New setups start signed in to ScreenScraper with the shared login, so they find box art and videos by themselves.' } else { 'New setups are not signed in to ScreenScraper yet. Share the login saved in RetroBat here, and they find box art and videos by themselves.' }) $ColDim 13
    $t.Margin = '0,4,0,8'
    [void]$sp.Children.Add($t)
    $b = New-SocialButton $(if ($has) { 'Share my login again' } else { 'Share my ScreenScraper login' }) {
        $pick = Show-Choice $WizardName "Share the ScreenScraper login saved in RetroBat on this setup with every new setup?`n`nIt goes to the private friends store, locked with the friends key, never into the public download. Every new setup signs in with it during its setup. ScreenScraper may slow down an account many people use at once." @('Share it', 'Cancel')
        if ($pick -ne 'Share it') { return }
        $r = Save-FrdScraperFromThisSetup $Root $Ws
        Log ('admin: scraper login - ' + $r.Message)
        if ($r.Ok) {
            $txt = Get-FrdSharedScraperText $Ws (Get-SocialToken $Ws)
            $ok = ($txt -ne '') -and (Set-AdminRepoFile $Ws 'shared/scraper.txt' $txt 'Shared ScreenScraper login (locked with the friends key)')
            $msg = $(if ($ok) { 'Shared. Every new setup signs in to ScreenScraper with it during its setup.' } else { 'Saved on this drive, but it could not be sent to the friends store (no internet, or no friends key). Try again later.' })
            Log ('admin: scraper login shared - ' + $ok)
            [void](Show-Choice $WizardName $msg @('OK'))
        }
        else { [void](Show-Choice $WizardName $r.Message @('OK')) }
        Render-Admin
    }
    $b.HorizontalAlignment = 'Left'; $b.Margin = '0'
    [void]$sp.Children.Add($b)
    $card.Child = $sp
    [void]$panel.Children.Add($card)
}

function Invoke-AdminChannel([string]$Channel) {
    try {
        $cur = (Get-UpdConfig $Ws).Channel
        if ($cur -eq $Channel) { return }
        if (Test-UpdWorkshop $Ws) {
            [void](Show-Choice $WizardName 'This is the workshop drive, so updates never install here. It already has the newest work. Try Stable or Dev on another drive or a fresh install.' @('OK'))
            return
        }
        $name = $(if ($Channel -eq 'dev') { 'Dev' } else { 'Stable' })
        $ci = Read-UpdChannelInfo $Ws
        $ver = $(if ($Channel -eq 'dev') { $ci.DevVersion } else { $ci.StableVersion })
        $verTxt = $(if ($ver -ne '') { (' (version ' + $ver + ')') } else { '' })
        $more = $(if ($Channel -eq 'dev') { 'Dev is the version being worked on: newer, but it may have rough edges.' } else { 'Stable is what everybody has.' })
        $pick = Show-Choice $WizardName ("Switch this setup to {0}{1}?`n`n{2}`n`nThe wizard closes, downloads it, installs it and opens again, with a progress window the whole way. Saves, games and settings stay. You can switch back the same way." -f $name, $verTxt, $more) @("Switch to $name", 'Cancel')
        if ($pick -ne "Switch to $name") { return }
        if (Test-RetroBatRunning) { [void](Show-Choice $WizardName 'RetroBat is open. Close it completely first, then switch.' @('OK')); return }
        Set-UpdChannel $Ws $Channel
        Log ("admin: update channel {0} -> {1}, installing now" -f $cur, $Channel)
        Invoke-WizardUpdate 'Update' -NoAsk -Title ("Switching to " + $name) -RevertChannel $cur
    } catch { Log ("admin: channel - {0}" -f $_.Exception.Message) }
}

function Render-Admin {
    $panel = $script:adminPanel
    if ($null -eq $panel) { return }
    $panel.Children.Clear()
    $top = New-Object System.Windows.Controls.StackPanel; $top.Orientation = 'Horizontal'; $top.Margin = '0,4,0,0'
    $rb = New-SocialButton 'Refresh' { Invoke-AdminRefresh }; $rb.Margin = '0'; $rb.FontWeight = 'Bold'
    [void]$top.Children.Add($rb)
    $nt = New-Text ('   ' + $script:adminNote) $ColDim 12; $nt.VerticalAlignment = 'Center'
    [void]$top.Children.Add($nt)
    [void]$panel.Children.Add($top)
    $players = @(Get-SocialPlayersNow)
    $ex = Get-SocialCachedExtras $Ws

    Add-AdminChannelCard $panel
    Add-AdminScraperCard $panel

    # --- reports ----------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Reports and suggestions'))
    $rep = $script:adminReports
    if ($null -eq $rep) { [void]$panel.Children.Add((New-Text 'Press Refresh to load them.' $ColDim 13)) }
    elseif (-not $rep.Ok) { [void]$panel.Children.Add((New-Text $rep.Message $ColAway 13)) }
    elseif (@($rep.Items).Count -eq 0) { [void]$panel.Children.Add((New-Text 'Nothing open. Nice.' $ColDim 13)) }
    else {
        foreach ($i in @($rep.Items)) {
            $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,6,0,0'
            $btns = New-Object System.Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Top'
            [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
            [void]$btns.Children.Add((New-SocialButton 'Read' { param($s2, $e2) $it = $s2.Tag; [void](Show-ChoiceScroll $it.Title ($it.Title + "`n" + $it.When + "`n`n" + $it.Body)) } $i))
            [void]$btns.Children.Add((New-SocialButton 'Done' { param($s2, $e2) Invoke-AdminCloseReport $s2.Tag } $i))
            [void]$row.Children.Add($btns)
            $info = New-Object System.Windows.Controls.StackPanel
            [void]$info.Children.Add((New-Text $i.Title $ColText 14 $true))
            [void]$info.Children.Add((New-Text $i.When $ColDim 12))
            [void]$row.Children.Add($info)
            [void]$panel.Children.Add($row)
        }
    }

    # --- name requests ---------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Name requests'))
    $reqs = @(Get-AdminNameRequests $players $ex)
    if ($reqs.Count -eq 0) { [void]$panel.Children.Add((New-Text 'None waiting.' $ColDim 13)) }
    foreach ($p in $reqs) {
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,6,0,0'
        $t = New-Text ("{0}  wants to be  {1}" -f $p.Username, $p.NameReq) $ColText 14; $t.Width = 360; $t.VerticalAlignment = 'Center'
        [void]$row.Children.Add($t)
        [void]$row.Children.Add((New-SocialButton 'Approve' { param($s2, $e2) Invoke-AdminName $s2.Tag $true } $p))
        [void]$row.Children.Add((New-SocialButton 'Decline' { param($s2, $e2) Invoke-AdminName $s2.Tag $false } $p))
        [void]$panel.Children.Add($row)
    }

    # --- the online library ------------------------------------------------------
    [void]$panel.Children.Add((New-IconHeader 'E898' 'Online library'))
    if ((Get-AdminLibKey $Ws) -eq '') {
        $t = New-Text 'Publishing needs a library key: a second GitHub key that can update the public game LIST. The game files themselves go to the private repo, so only a wizard can download them. The key stays on this drive only. One-time setup, about 3 minutes.' $ColDim 13
        [void]$panel.Children.Add($t)
        $kb = New-SocialButton 'Set up the library key...' { Invoke-AdminLibKey }; $kb.Margin = '0,8,0,0'; $kb.HorizontalAlignment = 'Left'
        [void]$panel.Children.Add($kb)
    }
    else {
        $t = New-Text 'Pick one or more games from your roms folder and they go online by themselves. The name, players, description and box art come from what RetroBat already knows; it only asks for a picture when a game has none. The details and art show on the public list and website; the files stay private, so only a wizard can download them. Only games that may be shared: homebrew, freeware, fan-made, your own. Any size: a game over 2 GB goes up in pieces and comes back down as one. Files and folder games (PS3, Wii U, PlayStation folders) are picked from the same list; a game made of several files (.cue and .bin, .gdi, .m3u) takes its other files with it. You can add more games while the queue runs.' $ColDim 13
        [void]$panel.Children.Add($t)
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        $pb = New-SocialButton $(if ($null -ne $script:adminLibJob) { 'Add more games...' } else { 'Publish games...' }) { Invoke-AdminPublish }; $pb.Margin = '0'; $pb.FontWeight = 'Bold'
        [void]$row.Children.Add($pb)
        $xb = New-SocialButton 'Remove games...' { Invoke-AdminRemove }
        $xb.IsEnabled = ($null -eq $script:adminLibJob)
        [void]$row.Children.Add($xb)
        $kb = New-SocialButton 'New key...' { Invoke-AdminLibKey }; $kb.FontSize = 11; $kb.Padding = '6,1'
        [void]$row.Children.Add($kb)
        [void]$panel.Children.Add($row)
        $script:adminLibText = New-Text $(if ($null -ne $script:adminLibJob) { 'Working...' } else { '' }) $ColAway 13
        $script:adminLibText.Margin = '0,6,0,0'
        [void]$panel.Children.Add($script:adminLibText)
        # (2026-10-17) The queue while it runs: what is done, what is going
        # up, and a cross for anything still waiting.
        $script:adminQueuePanel = New-Object System.Windows.Controls.StackPanel; $script:adminQueuePanel.Margin = '0,4,0,0'
        [void]$panel.Children.Add($script:adminQueuePanel)
        Update-AdminQueueList
    }

    # --- phone alerts ----------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Phone alerts'))
    if ($null -eq $script:adminTopic) { [void]$panel.Children.Add((New-Text 'Press Refresh to see the alert channel.' $ColDim 13)) }
    elseif ($script:adminTopic -eq '') {
        [void]$panel.Children.Add((New-Text 'Off. Turn it on and your phone buzzes for every new report and name request (free ntfy app).' $ColDim 13))
        $ab = New-SocialButton 'Turn on phone alerts' { Invoke-AdminTopic }; $ab.Margin = '0,8,0,0'; $ab.HorizontalAlignment = 'Left'
        [void]$panel.Children.Add($ab)
    }
    else {
        $t = New-Text ("In the ntfy app, subscribe to:   {0}" -f $script:adminTopic) $ColText 14
        [void]$panel.Children.Add($t)
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,8,0,0'
        $cb = New-SocialButton 'Copy' { try { [System.Windows.Clipboard]::SetText([string]$script:adminTopic); $script:adminNote = 'Copied.'; Render-Admin } catch { } }; $cb.Margin = '0'
        [void]$row.Children.Add($cb)
        [void]$row.Children.Add((New-SocialButton 'Send a test' { $ok = Send-SocialNotify $Ws 'Test' 'Phone alerts work.'; $script:adminNote = $(if ($ok) { 'Test sent.' } else { 'Could not send.' }); Render-Admin }))
        [void]$row.Children.Add((New-SocialButton 'New channel' { Invoke-AdminTopic }))
        [void]$panel.Children.Add($row)
    }

    # --- admins -------------------------------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Admins'))
    $me = $null; try { $me = Read-SocialProfile $Ws } catch { }
    foreach ($id in @($ex.Admins)) {
        $who = @($players | Where-Object { $null -ne $_ -and $_.Id -eq $id }) | Select-Object -First 1
        $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,4,0,0'
        $t = New-Text $(if ($null -ne $who) { $who.Username } else { "($id)" }) $ColText 14; $t.Width = 220; $t.VerticalAlignment = 'Center'
        [void]$row.Children.Add($t)
        if ($null -ne $me -and $id -ne $me.Id) { [void]$row.Children.Add((New-SocialButton 'Remove' { param($s2, $e2) Invoke-AdminSetAdmin ([string]$s2.Tag) $false } $id)) }
        [void]$panel.Children.Add($row)
    }
    $ad = New-SocialButton 'Make someone an admin...' { Invoke-AdminAdd }; $ad.Margin = '0,8,0,0'; $ad.HorizontalAlignment = 'Left'
    [void]$panel.Children.Add($ad)

    # --- forgotten passwords (2026-10-25) -------------------------------------------
    [void]$panel.Children.Add((New-SectionHeader 'Forgotten passwords'))
    $pt = New-Text 'Somebody forgot theirs? A request shows up in Reports above. Reset it here: they log in once without it and pick a new one.' $ColDim 13
    $pt.TextWrapping = 'Wrap'; [void]$panel.Children.Add($pt)
    $rp = New-SocialButton 'Reset someone''s password...' { Invoke-AdminPwReset }; $rp.Margin = '0,8,0,0'; $rp.HorizontalAlignment = 'Left'
    [void]$panel.Children.Add($rp)
    $d = New-Text 'A light lock like the rest of the friends system: the shared key could change these lists, so keep admins to people you trust.' '#FF777780' 11
    $d.Margin = '0,14,0,0'
    [void]$panel.Children.Add($d)
}

function Invoke-AdminCloseReport($Item) {
    if (Close-AdminReport $Ws $Item.Number) {
        $script:adminReports.Items = @(@($script:adminReports.Items) | Where-Object { $_.Number -ne $Item.Number })
        $script:adminNote = 'Marked done.'
    } else { $script:adminNote = 'GitHub would not close it. Try Refresh.' }
    Render-Admin
}

function Invoke-AdminName($Player, [bool]$Approve) {
    if ($Approve -and (Test-SocialNameTaken @(Get-SocialPlayersNow) $Player.NameReq $Player.Id)) {
        [void](Show-Choice $WizardName "Somebody else already has the name $($Player.NameReq). Decline this one." @('OK')); return
    }
    if (Set-AdminNameAnswer $Ws $Player.Id $Player.NameReq $Approve) {
        $script:adminNote = $(if ($Approve) { "Approved. $($Player.Username) becomes $($Player.NameReq) the next time their wizard checks in." } else { 'Declined.' })
        Log ("admin: name {0} -> {1} {2}" -f $Player.Username, $Player.NameReq, $(if ($Approve) { 'approved' } else { 'declined' }))
        # Taken in at once here, so the request leaves this list straight away.
        $script:socialFetched = $null
        Start-SocialFetch
    } else { $script:adminNote = 'GitHub would not take it. Try again.' }
    Render-Admin
}

function Invoke-AdminSetAdmin([string]$Id, [bool]$Add) {
    $ex = Get-SocialCachedExtras $Ws
    $ids = @($ex.Admins)
    if ($Add) { $ids = @($ids + $Id) } else {
        if ((Show-Choice $WizardName 'Take away their Admin tab?' @('Remove', 'Cancel')) -ne 'Remove') { return }
        $ids = @($ids | Where-Object { $_ -ne $Id })
    }
    if (Set-AdminList $Ws $ids) { $script:adminNote = 'Saved. It shows up for them within a couple of minutes.'; Log ("admin: admins now {0}" -f ($ids -join ',')); Start-SocialFetch }
    else { $script:adminNote = 'GitHub would not take it.' }
    Render-Admin
}

function Invoke-AdminAdd {
    $name = (Show-TextInput $WizardName 'Their username, exactly as it shows on the Social page:' '').Trim()
    if ($name -eq '') { return }
    $who = @(Get-SocialPlayersNow | Where-Object { $null -ne $_ -and $_.Username -eq $name }) | Select-Object -First 1
    if ($null -eq $who) { [void](Show-Choice $WizardName "Nobody called '$name'. Press Refresh first if they are new." @('OK')); return }
    if ((Show-Choice $WizardName "Make $($who.Username) an admin?`n`nThey get the Admin tab: reports, name requests, publishing to the library (with their own library key), and the admins list." @('Make admin', 'Cancel')) -ne 'Make admin') { return }
    Invoke-AdminSetAdmin $who.Id $true
}

function Invoke-AdminPwReset {
    $name = (Show-TextInput $WizardName 'Their username, exactly as it shows on the Social page:' '').Trim()
    if ($name -eq '') { return }
    $who = @(Get-SocialPlayersNow | Where-Object { $null -ne $_ -and $_.Username -eq $name }) | Select-Object -First 1
    if ($null -eq $who) { [void](Show-Choice $WizardName "Nobody called '$name'. Press Refresh first if they are new." @('OK')); return }
    if ((Show-Choice $WizardName "Reset $($who.Username)'s password?`n`nThey can log in once without it, on any setup, and are asked to pick a new one straight away." @('Reset it', 'Cancel')) -ne 'Reset it') { return }
    if (Set-AdminPwReset $Ws $who.Id) { $script:adminNote = "Reset. $($who.Username) can log in without a password now (give it a minute)."; Log ("admin: password reset for {0}" -f $who.Username); Start-SocialFetch }
    else { $script:adminNote = 'GitHub would not take it. Try again.' }
    Render-Admin
}

function Invoke-AdminTopic {
    $t = New-AdminNotifyTopic
    if (Set-AdminNotifyTopic $Ws $t) { $script:adminTopic = $t; $script:adminNote = 'Phone alerts are on. Subscribe to the channel in the ntfy app.' }
    else { $script:adminNote = 'GitHub would not take it.' }
    Render-Admin
}

function Invoke-AdminLibKey {
    $steps = "One-time setup, on github.com (signed in as you):`n`n" +
             "1. Click your picture (top right) > Settings.`n" +
             "2. At the bottom left: Developer settings > Personal access tokens > Fine-grained tokens > Generate new token.`n" +
             "3. Name: wizard library. Expiration: the longest it offers.`n" +
             "4. Repository access: Only select repositories > retrobat-wizard.`n" +
             "5. Permissions > Repository permissions > Contents: Read and write.`n" +
             "6. Generate token, copy it, and paste it here:"
    $k = (Show-TextInput $WizardName $steps '').Trim()
    if ($k -eq '') { return }
    if (-not (Set-AdminLibKey $Ws $k)) { [void](Show-Choice $WizardName 'That does not look like a GitHub key (they start with github_pat_).' @('OK')); return }
    $r = Invoke-AdminLibApi $k 'GET' "https://api.github.com/repos/$script:AdminLibRepo"
    $script:adminNote = $(if ($r.Status -eq 200) { 'Library key saved and working.' } else { "Saved, but GitHub answered $($r.Status). Check the key's settings." })
    Log ("admin: library key saved, test {0}" -f $r.Status)
    Render-Admin
}

# Publish games to the online library (Steven, 2026-10-11: "upload multiple
# games at once", "pull what is needed" from RetroBat). Pick one or more game
# files from the roms folder. The console comes from the folder it is in, and
# the name, players, description and box art from RetroBat's gamelist.xml.
# Only a game with no box art asks: pick a picture or skip. One yes, then it
# all runs in the background, one game after another.
# The games about to be published, in order, to rearrange or cross off
# before anything is sent (Steven, 2026-10-17). Returns the list, or $null.
function Show-QueueEditor($Items, [string[]]$Lines) {
    Close-Splash
    $w = New-Object System.Windows.Window
    Start-PadForDialogs
    $w.Title = $WizardName; $w.Width = 640; $w.Height = 520
    $w.WindowStartupLocation = 'CenterScreen'; $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '20'
    $hd = New-Text 'Publish these to the online library? They go up in this order, one at a time. Move them with the arrows, or cross one off. Only games that may be shared: homebrew, freeware, fan-made, your own.' $ColText 14
    $hd.Margin = '0,0,0,10'
    [System.Windows.Controls.DockPanel]::SetDock($hd, 'Top'); [void]$dp.Children.Add($hd)
    $row = New-Object System.Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'; $row.Margin = '0,12,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($row, 'Bottom')
    $script:qeOrder = New-Object System.Collections.ArrayList
    for ($k = 0; $k -lt @($Items).Count; $k++) { [void]$script:qeOrder.Add($k) }
    $script:qeLines = $Lines; $script:qeWin = $w; $script:qeOk = $false
    $script:qeList = New-Object System.Windows.Controls.StackPanel
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $script:qeList
    $script:qeGo = New-Object System.Windows.Controls.Button
    $script:qeGo.Content = 'Publish'; $script:qeGo.Padding = '16,7'; $script:qeGo.FontSize = 14; $script:qeGo.Margin = '8,0,0,0'
    $script:qeGo.Add_Click({ $script:qeOk = $true; $script:qeWin.Close() })
    $cn = New-Object System.Windows.Controls.Button
    $cn.Content = 'Cancel'; $cn.Padding = '16,7'; $cn.FontSize = 14
    $cn.Add_Click({ $script:qeWin.Close() })
    [void]$row.Children.Add($cn); [void]$row.Children.Add($script:qeGo)
    [void]$dp.Children.Add($row); [void]$dp.Children.Add($sv)
    $w.Content = $dp
    Update-QueueEditor
    [void]$w.ShowDialog()
    if (-not $script:qeOk -or $script:qeOrder.Count -eq 0) { return $null }
    $out = @(); foreach ($k in $script:qeOrder) { $out += $Items[$k] }
    return ,$out
}
function Update-QueueEditor {
    $script:qeList.Children.Clear()
    $pos = 0
    foreach ($k in @($script:qeOrder)) {
        $pos++
        $r = New-Object System.Windows.Controls.DockPanel; $r.Margin = '0,4,0,0'
        $btns = New-Object System.Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
        foreach ($b0 in @(@([string][char]0x25B2, -1, 'Earlier'), @([string][char]0x25BC, 1, 'Later'), @([string][char]0x2715, 0, 'Cross off'))) {
            $b = New-Object System.Windows.Controls.Button
            $b.Content = $b0[0]; $b.Padding = '9,2'; $b.Margin = '4,0,0,0'; $b.ToolTip = $b0[2]
            $b.Tag = @($k, $b0[1])
            $b.Add_Click({ param($s2, $e2)
                $kk = [int]$s2.Tag[0]; $mv = [int]$s2.Tag[1]
                $at = $script:qeOrder.IndexOf($kk)
                if ($mv -eq 0) { $script:qeOrder.RemoveAt($at) }
                else {
                    $to = $at + $mv
                    if ($to -ge 0 -and $to -lt $script:qeOrder.Count) { $script:qeOrder.RemoveAt($at); $script:qeOrder.Insert($to, $kk) }
                }
                Update-QueueEditor
            })
            [void]$btns.Children.Add($b)
        }
        [void]$r.Children.Add($btns)
        $t = New-Text ('{0}.  {1}' -f $pos, $script:qeLines[$k]) $ColText 14; $t.VerticalAlignment = 'Center'
        [void]$r.Children.Add($t)
        [void]$script:qeList.Children.Add($r)
    }
    if ($script:qeOrder.Count -eq 0) { [void]$script:qeList.Children.Add((New-Text 'Everything is crossed off.' $ColDim 13)) }
    $script:qeGo.IsEnabled = ($script:qeOrder.Count -gt 0)
    $script:qeGo.Content = $(if ($script:qeOrder.Count -eq 1) { 'Publish 1 game' } else { ('Publish {0} games' -f $script:qeOrder.Count) })
}

# The running queue on the Admin page. Redrawn when the game being sent
# changes, not every tick.
function Update-AdminQueueList {
    $qp = $script:adminQueuePanel
    if ($null -eq $qp) { return }
    $qp.Children.Clear()
    $j = $script:adminLibJob
    if ($null -eq $j -or $null -eq $j.Items -or @($j.Items).Count -lt 2) { return }
    $cur = [int]$j.Sync.Current
    $i = 0
    foreach ($it in @($j.Items)) {
        $i++
        $r = New-Object System.Windows.Controls.StackPanel; $r.Orientation = 'Horizontal'; $r.Margin = '0,2,0,0'
        $state = $(if ($j.Sync.Skip.ContainsKey([string]$i)) { 'crossed off' } elseif ($i -lt $cur) { 'done' } elseif ($i -eq $cur) { 'going up now' } else { 'waiting' })
        $col = $(switch ($state) { 'done' { $ColOnline } 'going up now' { '#FFE5B83B' } default { $ColDim } })
        [void]$r.Children.Add((New-Text ('{0}. {1}  -  {2}' -f $i, $it.Title, $state) $col 13))
        if ($state -eq 'waiting') {
            $x = New-SocialButton 'Cross off' { param($s2, $e2) $script:adminLibJob.Sync.Skip[[string]$s2.Tag] = $true; Update-AdminQueueList } ([string]$i)
            $x.FontSize = 11; $x.Padding = '6,0'
            [void]$r.Children.Add($x)
        }
        [void]$qp.Children.Add($r)
    }
}

# 3.2 (2026-10-26): games of several files (.cue + .bin, .gdi, .m3u ...) go
# up with all their files, folder games (PS3, Wii U ...) have their own
# button, and more games can be added while the queue is running (Steven:
# "add games on to a current queue of games").

# The console folder a path sits in (the longest match, so gb never takes
# gba's games), or $null.
function Get-AdminPickSystem([string]$Path) {
    $sys = $null; $best = 0
    foreach ($s in @(Get-GamesSystems)) {
        $base = ([string]$s.Folder).TrimEnd('\', '/') + '\'
        if ($base.Length -gt $best -and $Path.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) { $sys = $s; $best = $base.Length }
    }
    if ($null -eq $sys) { try { $sys = Resolve-GameConsole $Path } catch { } }
    return $sys
}

# (2026-10-26) The admin's own copy of GameLibrary's Get-LibGamelistInfo,
# with folder games matched by the file inside their folder. Kept here so
# the fix ships with the admin tools and the players' wizard is untouched.
function Get-AdminGamelistInfo($System, [string]$File) {
    $out = @{ Title = [System.IO.Path]::GetFileNameWithoutExtension($File); Players = ''; Description = ''; Art = ''; Video = '' }
    $gl = Join-LibPath $System.Folder 'gamelist.xml'
    if (-not (Test-Path -LiteralPath $gl)) { return $out }
    try {
        [xml]$x = [System.IO.File]::ReadAllText($gl)
        $want = './' + [System.IO.Path]::GetFileName($File)
        $base = ([string]$System.Folder).TrimEnd('\', '/')
        if ($File.Length -gt $base.Length -and $File.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $want = './' + ($File.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/')
        }
        # (2026-10-26) A folder game (PS1, N64, Dreamcast, Wii U, ScummVM in
        # its own folder) is usually listed by a file INSIDE its folder
        # (./Game/Game.cue, ./Game/code/x.rpx), so the folder itself never
        # matched and its art and video were never found. Exact match first
        # (a <game> or <folder> entry); else, for a folder, the entry inside
        # it that sits highest up.
        $hit = $null
        $all = @(@($x.gameList.game) + @($x.gameList.folder) | Where-Object { $null -ne $_ })
        foreach ($g in $all) {
            if ((([string]$g.path -replace '\\', '/').TrimEnd('/')) -eq $want) { $hit = $g; break }
        }
        if ($null -eq $hit -and (Test-Path -LiteralPath $File -PathType Container)) {
            $depth = 999
            foreach ($g in @($x.gameList.game | Where-Object { $null -ne $_ })) {
                $gp = ([string]$g.path -replace '\\', '/')
                if ($gp.StartsWith($want + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $dd = ($gp.Split('/')).Count
                    if ($dd -lt $depth) { $hit = $g; $depth = $dd }
                }
            }
        }
        if ($null -ne $hit) {
            $g = $hit
            if ($g.name) { $out.Title = [string]$g.name }
            if ($g.players) { $out.Players = [string]$g.players }
            if ($g.desc) { $out.Description = [string]$g.desc }
            foreach ($k in @('image', 'thumbnail')) {
                $rel = [string]$g.$k
                if ($rel -eq '') { continue }
                $full = $(if ($rel.StartsWith('./') -or $rel.StartsWith('.\')) { Join-LibPath $System.Folder $rel.Substring(2) } else { $rel })
                if (Test-Path -LiteralPath $full) { $out.Art = $full; break }
            }
            # (3.2) the scraped video, for the library's preview
            $vr = [string]$g.video
            if ($vr -ne '') {
                $vf = $(if ($vr.StartsWith('./') -or $vr.StartsWith('.\')) { Join-LibPath $System.Folder $vr.Substring(2) } else { $vr })
                if (Test-Path -LiteralPath $vf) { $out.Video = $vf }
            }
        }
    } catch { }
    return $out
}

# One picked game -> its queue item and line, asking for box art if it has
# none. $Set: Get-LibGameSet's answer (files), or $null for a folder game.
function New-AdminPublishItem($Sys, [string]$Path, $Set, [long]$Bytes) {
    $info = Get-AdminGamelistInfo $Sys $Path
    $title = ([string]$info.Title).Trim()
    $desc = (([string]$info.Description) -replace '\s+', ' ').Trim()
    if ($desc.Length -gt 280) { $desc = $desc.Substring(0, 280); $cut = $desc.LastIndexOf(' '); if ($cut -gt 200) { $desc = $desc.Substring(0, $cut) }; $desc += '...' }
    $art = [string]$info.Art
    if ($art -eq '') {
        $ans = Show-Choice $WizardName ("RetroBat has no box art for '{0}'.`n`nPick a picture for the library, or skip it and the console's picture shows instead." -f $title) @('Pick a picture', 'Skip')
        if ($ans -eq 'Pick a picture') {
            try {
                $pd = New-Object Microsoft.Win32.OpenFileDialog
                $pd.Title = "A picture for $title"
                $pd.Filter = 'Pictures|*.png;*.jpg;*.jpeg;*.gif;*.webp'
                $pd.InitialDirectory = [string]$Sys.Folder
                if ($pd.ShowDialog()) { $art = $pd.FileName }
            } catch { }
        }
    }
    $it = @{ File = $Path; System = $Sys.Name; Title = $title; Players = ([string]$info.Players).Trim(); Description = $desc; Art = $art; Video = [string]$info.Video }
    $kind = ''
    if ($null -eq $Set) { $it.Folder = $Path; $kind = ', folder' }
    elseif (@($Set.Files).Count -gt 1) {
        $it.MainName = [string]$Set.Files[0].Name
        $it.Extra = @($Set.Files | Select-Object -Skip 1 | ForEach-Object { @{ Path = [string]$_.Path; Name = [string]$_.Name } })
        $kind = (', {0} files' -f @($Set.Files).Count)
    }
    $line = ('{0} ({1}, {2} MB{3}{4}{5})' -f $title, $Sys.FullName, [math]::Round($Bytes / 1MB, 1), $kind, $(if ($art -eq '') { ', no art' } else { '' }), $(if ([string]$info.Video -ne '') { ', with video' } else { '' }))
    return @{ Item = $it; Line = $line }
}

# The publish picker (3.2, Steven: "the window to choose a folder game is
# itty bitty"; "select a normal file OR a folder game from the same button";
# more than one folder at a time). Consoles on the left; on the right that
# console's games, files and folders alike, each with a tick box. Ticks are
# kept while moving between consoles. Returns @{ Files; Folders } or $null.
function Show-PublishPicker {
    Close-Splash
    $script:ppTicked = [ordered]@{}
    $script:ppSystems = @(Get-GamesSystems | Where-Object { Test-Path -LiteralPath ([string]$_.Folder) } | Sort-Object FullName)
    if ($script:ppSystems.Count -eq 0) { [void](Show-Choice $WizardName 'No console folders were found in roms.' @('OK')); return $null }
    $w = New-Object System.Windows.Window
    Start-PadForDialogs
    $w.Title = $WizardName; $w.Width = 1000; $w.Height = 700; $w.MinWidth = 700; $w.MinHeight = 480
    $w.WindowStartupLocation = 'CenterScreen'; $w.Background = (New-Brush $ColBg); $w.Topmost = $true
    $dp = New-Object System.Windows.Controls.DockPanel; $dp.Margin = '20'
    $hd = New-Text 'Pick games for the online library: files and folder games alike, from any console. Tick as many as you like. Only games that may be shared: homebrew, freeware, fan-made, your own.' $ColText 14
    $hd.Margin = '0,0,0,10'; $hd.TextWrapping = 'Wrap'
    [System.Windows.Controls.DockPanel]::SetDock($hd, 'Top'); [void]$dp.Children.Add($hd)
    $row = New-Object System.Windows.Controls.DockPanel; $row.Margin = '0,12,0,0'
    [System.Windows.Controls.DockPanel]::SetDock($row, 'Bottom')
    $btns = New-Object System.Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($btns, 'Right')
    $script:ppOk = $false; $script:ppWin = $w
    $cn = New-Object System.Windows.Controls.Button; $cn.Content = 'Cancel'; $cn.Padding = '16,7'; $cn.FontSize = 14
    $cn.Add_Click({ $script:ppWin.Close() })
    $script:ppGo = New-Object System.Windows.Controls.Button; $script:ppGo.Content = 'Next'; $script:ppGo.Padding = '16,7'; $script:ppGo.FontSize = 14; $script:ppGo.Margin = '8,0,0,0'; $script:ppGo.IsEnabled = $false
    $script:ppGo.Add_Click({ $script:ppOk = $true; $script:ppWin.Close() })
    [void]$btns.Children.Add($cn); [void]$btns.Children.Add($script:ppGo)
    [void]$row.Children.Add($btns)
    $script:ppCount = New-Text 'Nothing ticked yet.' $ColDim 13; $script:ppCount.VerticalAlignment = 'Center'
    [void]$row.Children.Add($script:ppCount)
    [void]$dp.Children.Add($row)
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '260'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    # (2026-10-26, Steven) a search box above the console list ("it's
    # forever long and I'd rather just search the console")
    $left = New-Object System.Windows.Controls.DockPanel; $left.Margin = '0,0,12,0'
    $lcl = New-Text 'Find a console' $ColDim 12; $lcl.Margin = '0,0,0,3'
    [System.Windows.Controls.DockPanel]::SetDock($lcl, 'Top'); [void]$left.Children.Add($lcl)
    $script:ppConFind = New-Object System.Windows.Controls.TextBox; $script:ppConFind.FontSize = 14; $script:ppConFind.Padding = '6,3'; $script:ppConFind.Margin = '0,0,0,8'; $script:ppConFind.ToolTip = 'Type part of a console name'
    [System.Windows.Controls.DockPanel]::SetDock($script:ppConFind, 'Top'); [void]$left.Children.Add($script:ppConFind)
    $script:ppCons = New-Object System.Windows.Controls.ListBox; $script:ppCons.FontSize = 14
    $script:ppCons.Background = (New-Brush $ColPanel); $script:ppCons.Foreground = (New-Brush $ColText); $script:ppCons.BorderThickness = '0'
    foreach ($sy in $script:ppSystems) { $li = New-Object System.Windows.Controls.ListBoxItem; $li.Content = [string]$sy.FullName; $li.Tag = $sy; $li.Padding = '8,4'; [void]$script:ppCons.Items.Add($li) }
    [void]$left.Children.Add($script:ppCons)
    [System.Windows.Controls.Grid]::SetColumn($left, 0); [void]$g.Children.Add($left)
    $right = New-Object System.Windows.Controls.DockPanel
    $rcl = New-Text 'Find a game' $ColDim 12; $rcl.Margin = '0,0,0,3'
    [System.Windows.Controls.DockPanel]::SetDock($rcl, 'Top'); [void]$right.Children.Add($rcl)
    # the game search box with a Select all button beside it (2026-10-26)
    $frow = New-Object System.Windows.Controls.DockPanel; $frow.Margin = '0,0,0,8'
    $script:ppAll = New-Object System.Windows.Controls.Button; $script:ppAll.Content = 'Select all'; $script:ppAll.Padding = '12,3'; $script:ppAll.FontSize = 13; $script:ppAll.Margin = '8,0,0,0'
    $script:ppAll.ToolTip = 'Ticks every game showing in this list (or clears them when they are all ticked)'
    $script:ppAll.Add_Click({ Invoke-PublishPickerAll })
    [System.Windows.Controls.DockPanel]::SetDock($script:ppAll, 'Right'); [void]$frow.Children.Add($script:ppAll)
    $script:ppFilter = New-Object System.Windows.Controls.TextBox; $script:ppFilter.FontSize = 14; $script:ppFilter.Padding = '6,3'; $script:ppFilter.ToolTip = 'Type to narrow the list'
    [void]$frow.Children.Add($script:ppFilter)
    [System.Windows.Controls.DockPanel]::SetDock($frow, 'Top'); [void]$right.Children.Add($frow)
    $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
    $script:ppList = New-Object System.Windows.Controls.StackPanel
    $sv.Content = $script:ppList; [void]$right.Children.Add($sv)
    [System.Windows.Controls.Grid]::SetColumn($right, 1); [void]$g.Children.Add($right)
    [void]$dp.Children.Add($g)
    $script:ppCons.Add_SelectionChanged({ Update-PublishPickerList })
    $script:ppFilter.Add_TextChanged({ Update-PublishPickerList })
    $script:ppConFind.Add_TextChanged({ Update-PublishPickerConsoles })
    $w.Content = $dp
    $script:ppCons.SelectedIndex = 0
    [void]$w.ShowDialog()
    if (-not $script:ppOk -or $script:ppTicked.Count -eq 0) { return $null }
    $files = @(); $folders = @()
    foreach ($k in $script:ppTicked.Keys) { if ($script:ppTicked[$k]) { $folders += $k } else { $files += $k } }
    return @{ Files = $files; Folders = $folders }
}

function Update-PublishPickerList {
    $script:ppList.Children.Clear()
    $sel = $script:ppCons.SelectedItem
    if ($null -eq $sel) { return }
    $dir = [string]$sel.Tag.Folder
    $q = ([string]$script:ppFilter.Text).Trim().ToLower()
    $skip = @('images', 'videos', 'manuals', 'media', 'downloaded_images', 'downloaded_videos', 'marquees', 'thumbnails', 'screenshots', 'saves')
    $noGame = @('.xml', '.txt', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.mp4', '.pdf', '.nfo', '.ini', '.cfg', '.srm', '.sav')
    $n = 0
    foreach ($it in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($it.Name.StartsWith('.')) { continue }
        if ($it.PSIsContainer -and $skip -contains $it.Name.ToLower()) { continue }
        if (-not $it.PSIsContainer -and $noGame -contains $it.Extension.ToLower()) { continue }
        if ($q -ne '' -and -not $it.Name.ToLower().Contains($q)) { continue }
        $n++
        if ($n -gt 400) { [void]$script:ppList.Children.Add((New-Text 'Showing the first 400. Type in the box above to narrow it down.' $ColDim 12)); break }
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Foreground = (New-Brush $ColText); $cb.FontSize = 14; $cb.Margin = '0,3,0,3'
        $cb.Content = $(if ($it.PSIsContainer) { '[folder]  ' + $it.Name } else { '{0}   ({1:N0} MB)' -f $it.Name, ($it.Length / 1MB) })
        $cb.Tag = @($it.FullName, [bool]$it.PSIsContainer)
        $cb.IsChecked = $script:ppTicked.Contains($it.FullName)
        $cb.Add_Checked({ param($s2, $e2) $script:ppTicked[[string]$s2.Tag[0]] = [bool]$s2.Tag[1]; Update-PublishPickerCount })
        $cb.Add_Unchecked({ param($s2, $e2) if ($script:ppTicked.Contains([string]$s2.Tag[0])) { $script:ppTicked.Remove([string]$s2.Tag[0]) }; Update-PublishPickerCount })
        [void]$script:ppList.Children.Add($cb)
    }
    if ($n -eq 0) { [void]$script:ppList.Children.Add((New-Text 'Nothing here.' $ColDim 13)) }
    Update-PublishPickerAllLabel
}

# The tick boxes showing in the game list right now.
function Get-PublishPickerBoxes {
    return @($script:ppList.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })
}

# Select all: ticks every game showing (the search box narrows what that
# is); when they are all ticked already, it clears them instead.
function Invoke-PublishPickerAll {
    $boxes = @(Get-PublishPickerBoxes)
    if ($boxes.Count -eq 0) { return }
    $allOn = (@($boxes | Where-Object { -not $_.IsChecked }).Count -eq 0)
    foreach ($cb in $boxes) { $cb.IsChecked = (-not $allOn) }
    Update-PublishPickerAllLabel
}

function Update-PublishPickerAllLabel {
    if ($null -eq $script:ppAll) { return }
    $boxes = @(Get-PublishPickerBoxes)
    $script:ppAll.IsEnabled = ($boxes.Count -gt 0)
    $script:ppAll.Content = $(if ($boxes.Count -gt 0 -and @($boxes | Where-Object { -not $_.IsChecked }).Count -eq 0) { 'Clear all' } else { 'Select all' })
}

# The console search: hides consoles whose name does not match, and moves
# to the first one left when the one picked is hidden.
function Update-PublishPickerConsoles {
    $q = ([string]$script:ppConFind.Text).Trim().ToLower()
    $first = $null
    foreach ($li in @($script:ppCons.Items)) {
        $sy = $li.Tag
        $hay = ([string]$sy.FullName + ' ' + [string]$sy.Name).ToLower()
        $show = ($q -eq '' -or $hay.Contains($q))
        $li.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' })
        if ($show -and $null -eq $first) { $first = $li }
    }
    $sel = $script:ppCons.SelectedItem
    if ($null -ne $first -and ($null -eq $sel -or $sel.Visibility -ne 'Visible')) { $script:ppCons.SelectedItem = $first }
}

function Update-PublishPickerCount {
    $c = $script:ppTicked.Count
    $script:ppCount.Text = $(if ($c -eq 0) { 'Nothing ticked yet.' } elseif ($c -eq 1) { '1 game ticked.' } else { ('{0} games ticked.' -f $c) })
    $script:ppGo.IsEnabled = ($c -gt 0)
    Update-PublishPickerAllLabel
}

function Invoke-AdminPublish {
    if (-not $script:gamesOk) { return }
    # (3.2) one big picker for files AND folder games, as many as you like
    $pick = Show-PublishPicker
    if ($null -eq $pick) { return }
    # Work out each game's files first, so a .bin picked together with its
    # .cue is not sent twice.
    $sets = @(); $covered = @{}; $problems = @()
    $folderItems = @(); $folderLines = @()
    foreach ($d in @($pick.Folders)) {
        $sys = Get-AdminPickSystem $d
        if ($null -eq $sys) { $problems += ('{0}: not in a console folder' -f (Split-Path $d -Leaf)); continue }
        $bytes = [long]0; try { $bytes = [long]((Get-ChildItem -LiteralPath $d -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum) } catch { }
        if ($bytes -le 0) { $problems += ('{0}: the folder is empty' -f (Split-Path $d -Leaf)); continue }
        $n0 = New-AdminPublishItem $sys $d $null $bytes
        $folderItems += $n0.Item; $folderLines += ($n0.Line + '  -  packed on this drive first')
    }
    foreach ($f in @($pick.Files)) {
        $sys = Get-AdminPickSystem $f
        if ($null -eq $sys) { $problems += ('{0}: not in a console folder' -f [System.IO.Path]::GetFileName($f)); continue }
        $gs = Get-LibGameSet $f ([string]$sys.Folder)
        if (-not $gs.Ok) { $problems += $gs.Message; continue }
        $sets += @{ Sys = $sys; File = $f; Set = $gs }
        if (@($gs.Files).Count -gt 1) { foreach ($x in @($gs.Files | Select-Object -Skip 1)) { $covered[([string]$x.Path).ToLower()] = $true } }
    }
    $items = @(); $lines = @()
    foreach ($e in $sets) {
        if ($covered.ContainsKey(([System.IO.Path]::GetFullPath($e.File)).ToLower())) { continue }   # part of another picked game
        $bytes = [long]0; foreach ($x in @($e.Set.Files)) { $bytes += (Get-Item -LiteralPath $x.Path).Length }
        $n = New-AdminPublishItem $e.Sys $e.File $e.Set $bytes
        $items += $n.Item; $lines += $n.Line
    }
    $items += $folderItems; $lines += $folderLines
    if ($problems.Count -gt 0) { [void](Show-Choice $WizardName ("These cannot go up as they are:`n`n" + ($problems -join "`n")) @('OK')) }
    if ($items.Count -eq 0) { return }
    Add-AdminPublishItems $items $lines
}

# A game that is a whole folder (PS3, Wii U, ...): pick the folder.
function Invoke-AdminPublishFolder {
    if (-not $script:gamesOk) { return }
    $path = ''
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.Description = 'Pick the game''s own folder (for example roms\ps3\My Game.ps3). It goes up packed into one file and comes back down as the same folder.'
        $fd.SelectedPath = (Join-Path $Root 'roms')
        if ($fd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $path = $fd.SelectedPath
    } catch { return }
    $sys = Get-AdminPickSystem $path
    if ($null -eq $sys -or ([string]$sys.Folder).TrimEnd('\', '/') -ieq $path.TrimEnd('\', '/')) {
        [void](Show-Choice $WizardName 'Pick one game''s folder inside a console folder (roms\ps3\My Game.ps3), not the console folder itself.' @('OK')); return
    }
    $bytes = [long]0; try { $bytes = [long]((Get-ChildItem -LiteralPath $path -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum) } catch { }
    if ($bytes -le 0) { [void](Show-Choice $WizardName 'That folder is empty.' @('OK')); return }
    $n = New-AdminPublishItem $sys $path $null $bytes
    $n.Line += '  -  packed on this drive first, so it needs that much free room for a while'
    Add-AdminPublishItems @($n.Item) @($n.Line)
}

# Starts the queue, or adds to the one already running.
function Add-AdminPublishItems($Items, [string[]]$Lines) {
    $picked = Show-QueueEditor $Items $Lines
    if ($null -eq $picked) { return }
    $items = @($picked)
    if ($null -ne $script:adminLibJob) {
        foreach ($it in $items) { [void]$script:adminLibJob.Items.Add($it) }
        Log ("admin: added to the running queue: {0}" -f ((@($items | ForEach-Object { '{0} ({1})' -f $_.Title, $_.System })) -join ', '))
        $script:adminLibJob.Shown = -1
        Update-AdminQueueList
        return
    }
    try {
        $queue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        foreach ($it in $items) { [void]$queue.Add($it) }
        $sync = [hashtable]::Synchronized(@{ Stage = 'Starting...'; Percent = 0; Prefix = ''; Current = 0; Skip = [hashtable]::Synchronized(@{}) })
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try { $iss.ExecutionPolicy = 'Bypass' } catch { }
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss); $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript('param($s, $a, $ws, $items, $sync) . $s; . $a; Publish-AdminLibraryGames $ws $items $sync')
        foreach ($arg in @($script:socialLib, (Join-Path $ScriptsDir 'AdminEngine.ps1'), $Ws)) { [void]$ps.AddArgument($arg) }
        [void]$ps.AddArgument($queue); [void]$ps.AddArgument($sync)
        $label = $(if ($items.Count -eq 1) { $items[0].Title } else { "$($items.Count) games" })
        $script:adminLibJob = [pscustomobject]@{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync; Title = $label; Items = $queue; Shown = -1 }
        try { Start-WorkWatch } catch { }
        Log ("admin: publishing {0}: {1}" -f $label, ((@($items | ForEach-Object { '{0} ({1})' -f $_.Title, $_.System })) -join ', '))
        $script:adminLibTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:adminLibTimer.Interval = [TimeSpan]::FromMilliseconds(800)
        $script:adminLibTimer.Add_Tick({ Invoke-AdminPublishTick })
        $script:adminLibTimer.Start()
    } catch { Log "admin: publish could not start - $_"; $script:adminLibJob = $null }
    Render-Admin
}

# Take games off the online library (Steven, 2026-10-11: "is there any way
# to remove games from the online library? There had better be"). Shows
# what is up there with tick boxes; an upload that never made the list
# (a publish that stopped halfway) shows as one extra line, ticked already.
# Asks once more, then takes them off: list, box art, private file.
function Invoke-AdminRemove {
    if ($null -ne $script:adminLibJob) { return }
    $c = Invoke-EngineWork 'reading the online library' @('SocialEngine.ps1', 'AdminEngine.ps1') 'Get-AdminLibraryContents $args[0]' @($Ws)
    if ($null -eq $c) { [void](Show-Choice $WizardName 'The library could not be read. Details are in wizard.log.' @('OK')); return }
    if (-not $c.Ok) { [void](Show-Choice $WizardName $c.Message @('OK')); return }
    $games = @($c.Games | Sort-Object @{ Expression = { [string]$_.system } }, @{ Expression = { ([string]$_.title).ToLower() } })
    $left = @($c.Leftovers)
    if ($games.Count -eq 0 -and $left.Count -eq 0) { [void](Show-Choice $WizardName 'The online library is empty, and there are no leftover uploads.' @('OK')); return }
    $labels = @(); $ticks = @()
    foreach ($g in $games) {
        $con = [string]$g.system
        try { $s = @(Get-GamesSystems | Where-Object { $_.Name -eq $con }) | Select-Object -First 1; if ($null -ne $s) { $con = $s.FullName } } catch { }
        $labels += ('{0}   ({1})' -f $g.title, $con); $ticks += $false
    }
    if ($left.Count -gt 0) {
        $mb = 0; foreach ($l in $left) { $mb += [double]$l.size / 1MB }
        $labels += ('Leftover uploads not on the list: {0} file(s), {1:N0} MB' -f $left.Count, $mb); $ticks += $true
    }
    $picked = Show-CheckPick $WizardName 'Tick what to take off the online library.' $labels ([bool[]]$ticks) 'Remove'
    if ($null -eq $picked -or @($picked).Count -eq 0) { return }
    $ids = @(); $names = @(); $clear = @()
    foreach ($k in @($picked)) {
        if ($k -lt $games.Count) { $ids += [string]$games[$k].id; $names += [string]$games[$k].title }
        else { $clear = $left }
    }
    $what = @()
    if ($names.Count -gt 0) { $what += ($names -join "`n") }
    if ($clear.Count -gt 0) { $what += ('{0} leftover upload(s)' -f $clear.Count) }
    $ok = Show-Choice $WizardName ("Remove these from the online library?`n`n{0}`n`nThey leave the website and the wizard's list, and the private files are deleted. Anyone who already downloaded a game keeps their copy." -f ($what -join "`n")) @('Remove', 'Cancel')
    if ($ok -ne 'Remove') { return }
    $r = Invoke-EngineWork 'removing games from the online library' @('SocialEngine.ps1', 'AdminEngine.ps1') 'Remove-AdminLibraryGames $args[0] $args[1] $args[2]' @($Ws, [string[]]$ids, $clear)
    if ($null -eq $r) { $r = @{ Ok = $false; Cleared = 0; Message = 'That did not finish. Details are in wizard.log.' } }
    Log ("admin: remove {0} game(s), {1} leftover(s) - ok {2}" -f $ids.Count, $r.Cleared, $r.Ok)
    $script:adminNote = $r.Message
    $script:libCatalog = $null
    Render-Admin
    [void](Show-Choice $WizardName $r.Message @('OK'))
}

function Invoke-AdminPublishTick {
    try {
        $j = $script:adminLibJob
        if ($null -eq $j) { $script:adminLibTimer.Stop(); return }
        if (-not $j.Handle.IsCompleted) {
            if ($null -ne $script:adminLibText) {
                $txt = [string]$j.Sync.Stage
                if ($txt -eq 'Uploading...') { $txt = 'Uploading... {0}%' -f $j.Sync.Percent }
                if ($txt -like 'Packing the folder*') { $txt = 'Packing the folder into one file... {0}%' -f $j.Sync.Percent }
                $script:adminLibText.Text = ([string]$j.Sync.Prefix) + $txt
            }
            if ([int]$j.Sync.Current -ne [int]$j.Shown) { $j.Shown = [int]$j.Sync.Current; Update-AdminQueueList }
            return
        }
        $script:adminLibTimer.Stop()
        $out = $null
        try { $out = @($j.Ps.EndInvoke($j.Handle)) } catch { $out = @(@{ Ok = $false; Message = $_.Exception.Message }) }
        try { $j.Ps.Runspace.Dispose(); $j.Ps.Dispose() } catch { }
        $script:adminLibJob = $null
        $r = $(if ($out.Count -gt 0) { $out[-1] } else { @{ Ok = $false; Message = 'No answer.' } })
        Log ("admin: publish {0} - {1}" -f $j.Title, $r.Message)
        $script:adminNote = $r.Message
        $script:libCatalog = $null
        Render-Admin
        # Kept in the taskbar so the upload could finish (see Add_Closing): no
        # pop-up that could jump in front of a game. The note is on the Admin page.
        $down = $false; try { $down = ([string]$script:win.WindowState -eq 'Minimized') } catch { }
        # (The wizard's own work watch closes it, if it was only kept open for this.)
        if (-not $down -and $script:afterWork -eq '') { [void](Show-Choice $WizardName $r.Message @('OK')) }
    } catch { Log "admin: publish tick - $_" }
}
