<#
    KeyLayouts.ps1 - which keyboard key each controller button presses in a
    keyboard game (Flash, browser and PC games).

    FUNCTIONS ONLY. Dot-source it, with $Ws (the _Wizard folder)
    passed in. Used by the wizard (the layouts page and the editor), the
    "how this game plays" screen (ControllerChooser.ps1) and the couch mouse
    (CouchMouse.ps1), so all three always agree.

    TWO LAYERS (Steven, 2026-10-25: "a default per game that I add, and every
    person on their own accounts can create a custom keybindings"):
      the game's DEFAULT   its [section] in flash-games.ini or browser-games.ini
      a person's OWN       its [section] in profile\play\<person id>.keys.ini
    A person's own wins for them; everybody else gets the default. A guest
    gets the default.

    One section per game, headed by the game's file name:
        [Learn To Fly 3.swf]
        keys  = A:Space, B:Z, Up:W
        stick = arrows

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Join-KlPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

# Who is using this setup ('' = a guest or nobody).
function Get-KlPersonId([string]$Ws) {
    $f = Join-KlPath $Ws 'People\profile.ini'
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $id = ''; $guest = $false
    foreach ($l in [System.IO.File]::ReadAllLines($f)) {
        if ($l -match '^\s*id\s*=\s*([A-Za-z0-9_\-]{1,40})\s*$') { $id = $Matches[1] }
        if ($l -match '^\s*guest\s*=\s*yes') { $guest = $true }
    }
    if ($guest) { return '' }
    return $id
}

function Get-KlPersonFile([string]$Ws, [string]$Id) { return (Join-KlPath $Ws ('People\play\' + $Id + '.keys.ini')) }

# One game's section in one file: @{ Keys; Stick; Found }.
function Read-KlSection([string]$Path, [string]$Leaf) {
    $r = @{ Keys = ''; Stick = ''; Found = $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $r }
    $in = $false
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $t = $raw.Trim()
        if ($t -match '^\[(.+)\]$') { if ($in) { break }; $in = ($Matches[1].Trim() -ieq $Leaf); if ($in) { $r.Found = $true }; continue }
        if (-not $in -or $t.StartsWith(';')) { continue }
        if ($t -match '^keys\s*=\s*(.*)$') { $r.Keys = $Matches[1].Trim() }
        if ($t -match '^stick\s*=\s*(.*)$') { $r.Stick = $Matches[1].Trim().ToLower() }
    }
    return $r
}

# The game's default: @{ Keys; Stick; Ini } (Ini = the file it lives in, or
# the one it belongs in by its kind).
function Get-KlDefault([string]$Ws, [string]$Leaf) {
    foreach ($ini in @('flash-games.ini', 'browser-games.ini')) {
        $s = Read-KlSection (Join-KlPath $Ws ('Settings\' + $ini)) $Leaf
        if ($s.Keys -ne '' -or $s.Stick -ne '') { return @{ Keys = $s.Keys; Stick = $s.Stick; Ini = $ini } }
    }
    $ini = $(if ($Leaf -match '\.swf$') { 'flash-games.ini' } else { 'browser-games.ini' })
    return @{ Keys = ''; Stick = ''; Ini = $ini }
}

# What the controller does in this game for the person using the setup now:
# @{ Keys; Stick; From } with From = 'mine', 'default' or '' (none: the mouse).
# $PersonId: '?' (the default) = whoever is using the setup now; '' = nobody.
function Get-KlLayout([string]$Ws, [string]$Leaf, [string]$PersonId = '?') {
    if ($PersonId -eq '?') { $PersonId = Get-KlPersonId $Ws }
    if ($PersonId -ne '') {
        $m = Read-KlSection (Get-KlPersonFile $Ws $PersonId) $Leaf
        if ($m.Found -and ($m.Keys -ne '' -or $m.Stick -ne '')) { return @{ Keys = $m.Keys; Stick = $m.Stick; From = 'mine' } }
    }
    $d = Get-KlDefault $Ws $Leaf
    if ($d.Keys -ne '' -or $d.Stick -ne '') { return @{ Keys = $d.Keys; Stick = $d.Stick; From = 'default' } }
    return @{ Keys = ''; Stick = ''; From = '' }
}

# "A = Space, B = Z, left stick = the arrow keys" for people to read.
function Format-KlLayout($Layout) {
    $parts = @()
    foreach ($pr in ([string]$Layout.Keys).Split(',')) { $kv = $pr.Split(':'); if ($kv.Count -eq 2 -and $kv[1].Trim() -ne '') { $parts += ('{0} = {1}' -f $kv[0].Trim().ToUpperInvariant(), $kv[1].Trim()) } }
    if ([string]$Layout.Stick -eq 'arrows') { $parts += 'left stick = the arrow keys' }
    return ($parts -join ',   ')
}

# Writes (or clears, with '' and '') one game's keys and stick lines in one
# file. The rest of its section, and the rest of the file, stay as they were.
function Set-KlSection([string]$Path, [string]$Leaf, [string]$Name, [string]$Keys, [string]$Stick) {
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $Path) { foreach ($l in [System.IO.File]::ReadAllLines($Path)) { [void]$lines.Add($l) } }
    $start = -1; $end = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = ([string]$lines[$i]).Trim()
        if ($t -match '^\[(.+)\]$') {
            if ($start -ge 0) { $end = $i; break }
            if ($Matches[1].Trim() -ieq $Leaf) { $start = $i }
        }
    }
    $add = @()
    if ($Keys -ne '') { $add += ('keys      = ' + $Keys) }
    if ($Stick -ne '') { $add += ('stick     = ' + $Stick) }
    if ($start -lt 0) {
        if ($add.Count -eq 0) { return }
        if ($lines.Count -gt 0 -and ([string]$lines[$lines.Count - 1]).Trim() -ne '') { [void]$lines.Add('') }
        [void]$lines.Add('[' + $Leaf + ']')
        if ($Name -ne '') { [void]$lines.Add('name      = ' + $Name) }
        foreach ($a in $add) { [void]$lines.Add($a) }
    }
    else {
        for ($i = $end - 1; $i -gt $start; $i--) { if (([string]$lines[$i]).Trim() -match '^(keys|stick)\s*=') { $lines.RemoveAt($i) } }
        $at = $start + 1
        while ($at -lt $lines.Count -and ([string]$lines[$at]).Trim() -ne '' -and ([string]$lines[$at]).Trim() -notmatch '^\[') { $at++ }
        foreach ($a in $add) { $lines.Insert($at, $a); $at++ }
    }
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines.ToArray())
}

# Saves a layout. $For = 'default' (everybody) or a person id (just them).
function Set-KlLayout([string]$Ws, [string]$Leaf, [string]$Name, [string]$Keys, [string]$Stick, [string]$For) {
    if ($For -eq 'default') {
        $d = Get-KlDefault $Ws $Leaf
        Set-KlSection (Join-KlPath $Ws ('Settings\' + $d.Ini)) $Leaf $Name $Keys $Stick
    }
    elseif ($For -match '^[A-Za-z0-9_\-]{1,40}$') {
        Set-KlSection (Get-KlPersonFile $Ws $For) $Leaf $Name $Keys $Stick
    }
}
