<#
    HelpText.ps1 - the words of "How this setup works", and nowhere else.

    FUNCTIONS ONLY. Dot-source it; it has no side effects and prints
    nothing, so it is safe to load from anywhere.

    WHY THIS FILE EXISTS. Every tab in the Setup Wizard also has a button
    that does the same job without the window, because the window is a
    convenience layer and must never be the only way to see something.
    Help is no different: the Help tab's "How this setup works" window and
    Buttons\Show Help.bat both read THIS file, so the two can never drift
    apart and there is one place to edit the wording.

    REWRITTEN FOR 3.3 (Steven's flag, 2026-10-27: "the how this setup works
    text really needs to be updated so that it explains the current setup,
    and maybe have a blurb for coding nerds"). It opens in its own window
    now, so it may run longer than one screen, but keep each part short.
    The long explanations belong in _Wizard\Owner\docs\CUSTOMIZATION-RECORD.md.

    Each 'lines' entry is one piece of a paragraph: the window joins them
    with spaces and wraps them, Show Help.bat prints them one per line.

    PURE ASCII on purpose. Windows PowerShell reads a script with no
    byte-order mark as ANSI, so a stray accented character or a dash that
    is not a plain hyphen renders as garbage.
#>

# Returns the whole text as an ordered list of sections. Each section is a
# hashtable with a 'heading' string and a 'lines' array of strings. Both
# readers walk it the same way, so they cannot disagree.
#
# Callers should wrap the result in @(), the way everything on this drive
# does, because a function that returns an empty array returns nothing at
# all and $null.Count is not 0.
function Get-HelpSections {
    [CmdletBinding()]
    param(
        # The drive's own name, from Settings\wizard.ini. Passed in rather
        # than read here so this file stays side-effect free.
        [string] $WizardName = 'the RetroBat Wizard',
        [string] $Version    = ''
    )

    $wiz = if ([string]::IsNullOrWhiteSpace($WizardName)) { 'the RetroBat Wizard' } else { $WizardName }

    $sections = @()

    $sections += @{
        heading = 'THE TWO BUTTONS'
        lines   = @(
            'In the RetroBat folder there are two buttons. PLAY checks that everything is fine',
            'and starts RetroBat; you only see a window if something needs a decision.',
            'The wizard button opens this window. Nothing is installed on the computer',
            'unless you ask for it (Settings, This computer, Set this computer up).'
        )
    }

    $sections += @{
        heading = 'WHAT EACH PAGE IS FOR'
        lines   = @(
            'Games is the online library: pick games and they download in a line, two at a time.',
            'Social is your profile, your friends and your three favourite games, and it follows',
            'you to any setup you log in on. Play online sets up netplay and invites a friend,',
            'who gets a banner with a Join button. Saves backs up and brings back your saves.',
            'Features is the list of things this setup does that plain RetroBat does not, each',
            'one a tick box. Settings is this computer, this setup, and the Health checks.'
        )
    }

    $sections += @{
        heading = 'IF THE LIGHT IS NOT GREEN'
        lines   = @(
            'The light along the bottom is the Health check. If it is not green, open Settings,',
            'Health: each check says what is wrong and has a button that fixes it.'
        )
    }

    $sections += @{
        heading = 'THE THREE RULES'
        lines   = @(
            '1. Close RetroBat before changing settings here. It rewrites its settings when it',
            'closes, so the wizard waits until it is closed.',
            '2. After RetroBat updates itself, just press PLAY: the wizard puts its settings back.',
            '3. Nothing is ever deleted. Anything the wizard replaces goes to _Wizard\Backups\Archive',
            'or _Wizard\Cache\Trash first.'
        )
    }

    $sections += @{
        heading = 'SOMETHING WRONG?'
        lines   = @(
            'Use Send feedback on the Help page: it goes straight to whoever looks after this',
            'wizard, and you see exactly what is sent first. The wizard''s own notes are in',
            '_Wizard\Cache\logs\wizard.log.'
        )
    }

    $sections += @{
        heading = 'FOR CODING NERDS'
        lines   = @(
            'The wizard is Windows PowerShell 5.1 with a WPF window, nothing to install and no',
            'admin rights. The code is in _Wizard\Program (an update replaces it), this setup''s',
            'choices are plain .ini and .txt files in _Wizard\Settings (an update never touches',
            'them), and people, play time and favourites live in _Wizard\People. Updates come',
            'from GitHub with a manifest of every file and its hash, and can be undone with Go',
            'back one update. Friends, invites and the online library talk to GitHub too: each',
            'person writes only their own small file, and everybody reads everybody''s. The',
            'wizard never writes to RetroBat while it is open, and keeps a copy of anything',
            'it changes.'
        )
    }

    $stamp = $wiz
    if (-not [string]::IsNullOrWhiteSpace($Version)) { $stamp = "$wiz  -  version $Version" }
    $sections += @{
        heading = ''
        lines   = @($stamp)
    }

    return $sections
}
