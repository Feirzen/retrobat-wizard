<#
    Theme.ps1 - light, dark, or follow Windows, for EVERY window on the drive.

    FUNCTIONS ONLY. Dot-source it. Used by the wizard, the Steam setup window,
    the shortcut maker, the updater window and the friends pop-ups, so they
    can never disagree (Steven, 2026-10-13: "make all the windows follow suit
    and be all the same", with "follow the computer" as the default).

    THE CHOICE lives in Settings\theme.txt:
        system   follow Windows' own "app mode" setting  (the default, and
                 what no file at all means)
        light    always light
        dark     always dark
    Windows' setting is HKCU\Software\Microsoft\Windows\CurrentVersion\
    Themes\Personalize\AppsUseLightTheme (1 = light). Read only, never written.

    HOW LIGHT MODE WORKS. Every window here was drawn in one dark palette, and
    every colour reaches the screen through one brush helper or the window's
    XAML. So light mode is ONE translation of each colour:
        greys          flip (dark backgrounds go light, light text goes dark)
        near-black     soft grey (edges, pixel shadows)
        pale accents   go deep so they read on white
        dark tints     become a pale wash of the same hue
        mid accents    (the green Play button, gold) stay, a touch deeper
    In dark mode every colour passes through untouched.

    THE ACCENT (2026-10-17, "two-colour themes" on Steven's list) lives in
    Settings\accent.txt: gold (the default, and what no file means), blue,
    violet or rose. Every gold in every window turns to that colour, at the
    same brightness, in light and dark alike. Green and red are left out on
    purpose: they mean "fine" and "problem" all over the wizard.

    ASCII ONLY, Windows PowerShell 5.1. Never throws.
#>

$script:ThemeCache = @{}

function Get-WizThemeFile { return (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Settings\theme.txt') }

# 'system', 'light' or 'dark' - what was chosen.
function Get-WizThemeMode {
    try {
        $f = Get-WizThemeFile
        if (Test-Path -LiteralPath $f) {
            $t = ([System.IO.File]::ReadAllText($f)).Trim().ToLower()
            if (@('system', 'light', 'dark') -contains $t) { return $t }
        }
    } catch { }
    return 'system'
}

function Set-WizThemeMode([string]$Mode) {
    try { [System.IO.File]::WriteAllText((Get-WizThemeFile), $Mode) } catch { }
}

# 'light' or 'dark' - what to draw right now.
function Resolve-WizTheme {
    $m = Get-WizThemeMode
    if ($m -ne 'system') { return $m }
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop).AppsUseLightTheme
        if ([int]$v -eq 1) { return 'light' }
    } catch { }
    return 'dark'
}

$script:WizTheme = Resolve-WizTheme

$script:WizAccents = [ordered]@{ gold = 44; blue = 212; violet = 268; rose = 334 }
function Get-WizAccentFile { return (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Settings\accent.txt') }
function Get-WizAccent {
    try {
        $f = Get-WizAccentFile
        if (Test-Path -LiteralPath $f) { $t = ([System.IO.File]::ReadAllText($f)).Trim().ToLower(); if ($script:WizAccents.Contains($t)) { return $t } }
    } catch { }
    return 'gold'
}
function Set-WizAccent([string]$Name) { try { [System.IO.File]::WriteAllText((Get-WizAccentFile), $Name) } catch { } }
$script:WizAccent = Get-WizAccent

function Convert-ThemeHex([string]$hex) {
    $light = ($script:WizTheme -eq 'light')
    $acc = $(if ($null -ne $script:WizAccent) { [string]$script:WizAccent } else { 'gold' })
    if (-not $light -and $acc -eq 'gold') { return $hex }
    if ($hex -notmatch '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $hex }
    if ($script:ThemeCache.ContainsKey($hex)) { return $script:ThemeCache[$hex] }
    try {
        $h = $hex.Substring(1); if ($h.Length -eq 6) { $h = 'FF' + $h }
        $a = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $r = [Convert]::ToInt32($h.Substring(2, 2), 16) / 255.0
        $g = [Convert]::ToInt32($h.Substring(4, 2), 16) / 255.0
        $b = [Convert]::ToInt32($h.Substring(6, 2), 16) / 255.0
        $mx = [Math]::Max($r, [Math]::Max($g, $b)); $mn = [Math]::Min($r, [Math]::Min($g, $b))
        $l = ($mx + $mn) / 2.0; $d = $mx - $mn
        $sat = 0.0; $hue = 0.0
        if ($d -gt 0.0001) {
            if ($l -gt 0.5) { $sat = $d / (2.0 - $mx - $mn) } else { $sat = $d / ($mx + $mn) }
            if ($mx -eq $r) { $hue = (($g - $b) / $d) % 6 }
            elseif ($mx -eq $g) { $hue = (($b - $r) / $d) + 2 }
            else { $hue = (($r - $g) / $d) + 4 }
            $hue = $hue * 60; if ($hue -lt 0) { $hue += 360 }
        }
        # the accent: golds take the chosen colour's hue
        if ($acc -ne 'gold' -and $sat -gt 0.40 -and $hue -ge 32 -and $hue -le 56) { $hue = [double]$script:WizAccents[$acc] }
        if (-not $light) { }
        elseif ($sat -lt 0.22) {
            # Near-black is used for edges and the pixel shadows under tiles;
            # those become a soft grey rather than vanishing into white.
            if ($l -lt 0.075) { $l = 0.80 }
            elseif ($l -lt 0.5) { $l = [Math]::Min(0.97, 1.08 - $l) } else { $l = [Math]::Max(0.08, 1.03 - $l) }
        }
        elseif ($l -gt 0.7)  { $l = 0.30 }
        elseif ($l -lt 0.25) { $l = 0.90; $sat = [Math]::Min($sat, 0.45) }
        elseif ($l -gt 0.5)  { $l = 0.42 }
        $c = (1 - [Math]::Abs(2 * $l - 1)) * $sat
        $x = $c * (1 - [Math]::Abs((($hue / 60) % 2) - 1))
        $m = $l - $c / 2
        $rr = 0; $gg = 0; $bb = 0
        if ($hue -lt 60) { $rr = $c; $gg = $x } elseif ($hue -lt 120) { $rr = $x; $gg = $c }
        elseif ($hue -lt 180) { $gg = $c; $bb = $x } elseif ($hue -lt 240) { $gg = $x; $bb = $c }
        elseif ($hue -lt 300) { $rr = $x; $bb = $c } else { $rr = $c; $bb = $x }
        $out = '#{0:X2}{1:X2}{2:X2}{3:X2}' -f $a, [int][Math]::Round(($rr + $m) * 255), [int][Math]::Round(($gg + $m) * 255), [int][Math]::Round(($bb + $m) * 255)
        $script:ThemeCache[$hex] = $out
        return $out
    }
    catch { return $hex }
}

function Convert-ThemeXaml([string]$Xaml) {
    if ($script:WizTheme -ne 'light' -and ([string]$script:WizAccent -eq 'gold' -or [string]$script:WizAccent -eq '')) { return $Xaml }
    return [regex]::Replace($Xaml, '#[0-9A-Fa-f]{8}\b', [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) Convert-ThemeHex $mm.Value })
}

# For windows that make brushes themselves.
function New-ThemedBrush([string]$hex) {
    (New-Object System.Windows.Media.BrushConverter).ConvertFromString((Convert-ThemeHex $hex))
}
