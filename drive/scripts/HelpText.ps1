<#
    HelpText.ps1 - the words on the Help tab, and nowhere else.

    FUNCTIONS ONLY. Dot-source it; it has no side effects and prints
    nothing, so it is safe to load from anywhere.

    WHY THIS FILE EXISTS. Every tab in the Setup Wizard also has a button
    that does the same job without the window, because the window is a
    convenience layer and must never be the only way to see something.
    Help is no different: the wizard's Help tab and
    Maintenance Steps\Show Help.bat both read THIS file, so the two can
    never drift apart and there is one place to edit the wording.

    KEEP IT SHORT. The wording rule on this drive is that new on-screen
    text is no longer than the lines already there. This is written to fit
    one screen in the wizard with no scrolling - there is a test that fails
    if it grows past the height of the window. If you add a section, take
    one out. The long explanations belong in
    _ClaudeWorkspace\docs\CUSTOMIZATION-RECORD.md, not on the screen.

    PURE ASCII on purpose. Windows PowerShell reads a script with no
    byte-order mark as ANSI, so a stray accented character or a dash that
    is not a plain hyphen renders as garbage.
#>

# Returns the whole Help page as an ordered list of sections. Each section
# is a hashtable with a 'heading' string and a 'lines' array of strings.
# Both readers walk it the same way, so they cannot disagree.
#
# Callers should wrap the result in @(), the way everything on this drive
# does, because a function that returns an empty array returns nothing at
# all and $null.Count is not 0.
function Get-HelpSections {
    [CmdletBinding()]
    param(
        # The drive's own name, from wizard\wizard.ini. Passed in rather
        # than read here so this file stays side-effect free.
        [string] $WizardName = 'the Setup Wizard',
        [string] $Version    = ''
    )

    $wiz = if ([string]::IsNullOrWhiteSpace($WizardName)) { 'the Setup Wizard' } else { $WizardName }

    $sections = @()

    $sections += @{
        heading = 'WHAT THIS SETUP IS'
        lines   = @(
            'A retro game collection on one external drive, with the emulators',
            'and every setting already done. Plug it in, press Play, that is all.'
        )
    }

    $sections += @{
        heading = 'WHAT IS AT THE TOP OF THE DRIVE'
        lines   = @(
            'SETUP RETROBAT  press ONCE on a computer you have not played on',
            'Play RetroBat   checks the drive is healthy, then starts the games',
            'Setup Wizard    opens this window on purpose'
        )
    }

    $sections += @{
        heading = 'IF THE LIGHT IS NOT GREEN'
        lines   = @(
            'Green means all seven checks passed. Otherwise open the Health tab,',
            'where each one says what is wrong and has a button that fixes it.'
        )
    }

    $sections += @{
        heading = 'THE FEATURES TAB'
        lines   = @(
            'Nine things this setup does that plain RetroBat does not, each a',
            'tick box. Untick one and RetroBat''s own behaviour comes back.'
        )
    }

    $sections += @{
        heading = 'THE THREE RULES'
        lines   = @(
            '1  Never type a drive letter into anything here. This drive gets a',
            '   different letter on every computer, and that breaks things.',
            '2  After RetroBat updates itself, run RUN THIS AFTER AN UPDATE.bat',
            '   in _ClaudeWorkspace. Pressing Play usually does it for you.',
            '3  Close RetroBat before changing settings. It throws changes away',
            '   when it exits, so the scripts refuse to run while it is open.'
        )
    }

    $sections += @{
        heading = 'IF SOMETHING BREAKS'
        lines   = @(
            'Nothing here is ever deleted, only moved into _ClaudeWorkspace\archive\.',
            'The full story: _ClaudeWorkspace\docs\CUSTOMIZATION-RECORD.md'
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
