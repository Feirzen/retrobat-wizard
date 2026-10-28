<#
    Updater.ps1 - updates the wizard from GitHub, or goes back one update.

    Runs in ITS OWN process, so the wizard can close first and nothing is in
    use while files are replaced. The engine is scripts\UpdateEngine.ps1;
    this file is only the window around it.

        -Mode Update    download what changed, check it, install it
        -Mode GoBack    put back what the last update replaced
        -WaitPid <n>    wait for that process (the wizard) to close first
        -Relaunch       open the wizard again afterwards
        -Console        plain text in a console instead of a window, with a
                        yes/no question before anything changes. Used by the
                        two buttons in Buttons.
        -Title <text>   the window's heading (the Admin page's Stable / Dev
                        switch says "Switching to Dev")
        -RevertChannel <stable|dev>
                        the channel to put back if the switch does not finish,
                        so a failed switch leaves the drive as it was

    Started by:
        the wizard's "Update now" bar and Help tab buttons (window mode)
        Buttons\Check For Updates.bat   (-Mode Update -Console)
        Buttons\Go Back One Update.bat  (-Mode GoBack -Console)

    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the
    body, never in param(): it is empty there under -File.
#>

[CmdletBinding()]
param(
    [ValidateSet('Update', 'GoBack')][string]$Mode = 'Update',
    [int]$WaitPid = 0,
    [switch]$Relaunch,
    [switch]$Console,
    [string]$Title = '',
    [string]$RevertChannel = ''
)

$ErrorActionPreference = 'Stop'
$Ws = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'UpdateEngine.ps1')
# Light / dark / follow Windows, shared by every window (scripts\Theme.ps1,
# 2026-10-13). Missing file = the original dark colours, untouched.
try { . (Join-Path $PSScriptRoot 'Theme.ps1') } catch { }
if (-not (Get-Command Convert-ThemeHex -ErrorAction SilentlyContinue)) { function Convert-ThemeHex([string]$hex) { return $hex } }


Write-UpdLog $Ws ("updater: started, mode {0}{1}" -f $Mode, $(if ($Console) { ', console' } else { '' }))

# --- let the wizard finish closing ------------------------------------------
if ($WaitPid -gt 0) {
    try {
        $p = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
        if ($null -ne $p) { [void]$p.WaitForExit(30000) }
    } catch { }
}

# --- the window: small, borderless, the same look as the wizard's splash ----
$script:uw = $null
$script:uwText = $null
$script:uwBar = $null
function Show-UpdWindow([string]$Title) {
    if ($Console) { Write-Host ''; Write-Host "  $Title" -ForegroundColor Cyan; return }
    try {
        Add-Type -AssemblyName PresentationFramework
        $w = New-Object System.Windows.Window
        $w.WindowStyle = 'None'; $w.ResizeMode = 'NoResize'
        $w.Width = 440; $w.Height = 150
        $w.WindowStartupLocation = 'CenterScreen'; $w.Topmost = $true
        $w.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Convert-ThemeHex '#FF1B1B22'))
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = '24,20,24,20'
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = $Title; $t1.FontSize = 18; $t1.FontWeight = 'Bold'
        $t1.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Convert-ThemeHex '#FFE8E8EC'))
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = 'Starting'; $t2.FontSize = 13; $t2.Margin = '0,10,0,12'; $t2.TextWrapping = 'Wrap'
        $t2.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Convert-ThemeHex '#FF9AA0AA'))
        $pb = New-Object System.Windows.Controls.ProgressBar
        $pb.IsIndeterminate = $true; $pb.Height = 8; $pb.Maximum = 100
        $script:uwBar = $pb
        [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2); [void]$sp.Children.Add($pb)
        $w.Content = $sp
        $w.Show()
        $script:uw = $w; $script:uwText = $t2
        Update-UpdWindow 'Starting'
    } catch { $script:uw = $null }
}

function Update-UpdWindow([string]$Msg) {
    Write-UpdLog $Ws ("updater: " + $Msg)
    if ($Console) { Write-Host "  $Msg"; return }
    if ($null -eq $script:uw) { return }
    try {
        $script:uwText.Text = $Msg
        # "Downloading 12 of 40" fills the bar (2026-10-17: something to
        # watch, so a long wait never looks stuck).
        if ($null -ne $script:uwBar) {
            if ($Msg -match '(\d+) of (\d+)' -and [int]$Matches[2] -gt 0) {
                $script:uwBar.IsIndeterminate = $false
                $script:uwBar.Value = [math]::Min(100, 100.0 * [int]$Matches[1] / [int]$Matches[2])
            }
            elseif ($Msg -match '^Installing') { $script:uwBar.IsIndeterminate = $true }
        }
        # Let the window repaint before the next slow step starts.
        $script:uw.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    } catch { }
}

function Close-UpdWindow {
    if ($null -ne $script:uw) { try { $script:uw.Close() } catch { } }
    $script:uw = $null
}

function Show-UpdResult([string]$Msg, [bool]$Ok) {
    Write-UpdLog $Ws ("updater: result - " + $Msg)
    if ($Console) {
        Write-Host ''
        $c = if ($Ok) { 'Green' } else { 'Yellow' }
        Write-Host "  $Msg" -ForegroundColor $c
        return
    }
    if ($Ok -and $Relaunch) {
        # The wizard opening again IS the good news. A box to click first
        # would only be in the way.
        Update-UpdWindow $Msg
        Start-Sleep -Milliseconds 1200
        Close-UpdWindow
        return
    }
    Close-UpdWindow
    try {
        $icon = if ($Ok) { 'Information' } else { 'Warning' }
        [void][System.Windows.MessageBox]::Show($Msg, 'Wizard update', 'OK', $icon)
    } catch { }
}

function Ask-Console([string]$Question) {
    if (-not $Console) { return $true }
    Write-Host ''
    $a = Read-Host "  $Question (Y/N)"
    return ($a -match '^\s*[Yy]')
}

# A Stable / Dev switch that did not finish puts the old channel back, so
# the drive never says Dev while it still runs Stable.
function Undo-UpdSwitch {
    if ($RevertChannel -eq '') { return }
    try { Set-UpdChannel $Ws $RevertChannel; Write-UpdLog $Ws ("updater: switch did not finish, channel back to " + $RevertChannel) } catch { }
}

function Start-WizardAgain {
    if (-not $Relaunch) { return }
    try {
        $vbs = Join-UpdPath $Ws 'Program\wizard\Launch-Wizard.vbs'
        $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
        Start-Process -FilePath $wscript -ArgumentList @('//nologo', ('"' + $vbs + '"'))
        Write-UpdLog $Ws 'updater: wizard reopened'
    }
    catch { Write-UpdLog $Ws ("updater: could not reopen the wizard - " + $_.Exception.Message) }
}

# ===========================================================================
try {
    if ($Mode -eq 'Update') {
        $here = Get-UpdLocalVersion $Ws
        Show-UpdWindow $(if ($Title -ne '') { $Title } else { 'Updating the wizard' })
        if (Test-UpdRetroBatRunning) {
            Undo-UpdSwitch
            Show-UpdResult 'RetroBat is open. Close it completely, then press Update now again.' $false
            Start-WizardAgain
            exit 1
        }
        Update-UpdWindow 'Checking GitHub for the newest version'
        $st = Invoke-UpdateCheck -Ws $Ws -Progress { param($m) Update-UpdWindow $m }
        if ($st.state -eq 'uptodate') {
            $msg = "Already up to date (version $here)."
            if ($st.message) { $msg += "`n`n" + $st.message }
            Show-UpdResult $msg $true
            Start-WizardAgain
            exit 0
        }
        if ($st.state -ne 'ready') {
            $msg = if ($st.message) { $st.message } else { 'The update could not be downloaded.' }
            Undo-UpdSwitch
            Show-UpdResult ($msg + "`n`nNothing was changed.") $false
            Start-WizardAgain
            exit 1
        }
        if ($Console) {
            Write-Host ''
            Write-Host ("  Version {0} is downloaded and checked (this setup has {1})." -f $st.version, $here)
            if ($st.notes) { Write-Host ("  What's new: " + ($st.notes -replace ' \| ', "`n              ")) }
            if (-not (Ask-Console 'Install it now?')) { Write-Host '  Left as it is. Nothing changed.'; exit 0 }
        }
        Update-UpdWindow ("Installing version " + $st.version)
        $r = Invoke-UpdateInstall -Ws $Ws -Progress { param($m) Update-UpdWindow $m }
        if (-not $r.Ok) { Undo-UpdSwitch }
        Show-UpdResult $r.Message $r.Ok
        Start-WizardAgain
        if ($r.Ok) { exit 0 } else { exit 1 }
    }

    if ($Mode -eq 'GoBack') {
        $info = Get-UpdGoBackInfo $Ws
        if ($null -eq $info) {
            Show-UpdResult 'There is no update to go back from.' $false
            Start-WizardAgain
            exit 1
        }
        if ($Console) {
            Write-Host ''
            Write-Host ("  The last update took this setup from {0} to {1} on {2}." -f $info.From, $info.To, $info.Time)
            if (-not (Ask-Console ("Go back to {0}?" -f $info.From))) { Write-Host '  Left as it is. Nothing changed.'; exit 0 }
        }
        Show-UpdWindow 'Going back one update'
        Update-UpdWindow ("Putting back version " + $info.From)
        $r = Invoke-UpdateGoBack -Ws $Ws
        Show-UpdResult $r.Message $r.Ok
        Start-WizardAgain
        if ($r.Ok) { exit 0 } else { exit 1 }
    }
}
catch {
    Write-UpdLog $Ws ("updater: FATAL - " + $_.Exception.Message)
    Undo-UpdSwitch
    Show-UpdResult ("The updater hit an error: " + $_.Exception.Message + "`n`nDetails are in _Wizard\Program\update\update.log.") $false
    Start-WizardAgain
    exit 1
}
