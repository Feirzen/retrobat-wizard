<#
    BugReport.ps1 - "Report a bug" and "Suggest something", sent to GitHub
    as Issues. Three kinds, told apart by the start of the title:
        [bug]            something broken (logs go with it by default)
        [idea]           a feature or change somebody would like
        [game request]   a game somebody would like on the drive
    (Suggestions added 2026-10-10, Steven.)

    FUNCTIONS ONLY. Dot-source it AFTER SocialEngine.ps1 (it uses the same
    token and the same way of talking to GitHub). Used by:
        wizard\SetupWizard.ps1          the Help tab button, and the offer
                                        after the wizard itself crashes
        scripts\Report-Bug.ps1          Buttons\Report A Bug.bat

    WHAT A REPORT HOLDS
    -------------------
    What the person typed, then the facts that make it fixable: wizard
    version, RetroBat version, Windows version, the machine tier and graphics
    card, and the last lines of the wizard's own logs. Logs are optional and on
    by default.

    THE LOGS ARE CLEANED FIRST. The Windows user name, the computer's name and
    the user folder path are swapped for <user>, <pc> and <home> before
    anything leaves the drive. A report is SHOWN before it is sent.

    It goes to the private social repo as an Issue, where Claude reads it with
    the GitHub connector. A report is sent even from a guest, because pressing
    Send is the person choosing to send it, and only then.

    NO INTERNET: the report is saved in social\reports\outbox\ and sent the
    next time the wizard opens. A copy of every report sent is kept in
    social\reports\sent\.

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Get-BugTail([string]$Path, [int]$Lines) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        # The hook logs are written while games run, so open them shared.
        $fs = New-Object System.IO.FileStream($Path, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object System.IO.StreamReader($fs)
        $all = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
        $arr = $all -split "`r?`n"
        if ($arr.Count -gt $Lines) { $arr = $arr[($arr.Count - $Lines)..($arr.Count - 1)] }
        return ($arr -join "`n").TrimEnd()
    } catch { return "(could not read: $($_.Exception.Message))" }
}

# Swaps out what identifies the person or their computer. Longest first, so
# C:\Users\Steven goes before Steven on its own.
function Protect-BugText([string]$Text) {
    if ($null -eq $Text) { return '' }
    $t = $Text
    $pairs = @()
    if ($env:USERPROFILE)  { $pairs += ,@($env:USERPROFILE, '<home>') }
    if ($env:USERNAME)     { $pairs += ,@($env:USERNAME, '<user>') }
    if ($env:COMPUTERNAME) { $pairs += ,@($env:COMPUTERNAME, '<pc>') }
    foreach ($p in ($pairs | Sort-Object { -($_[0].Length) })) {
        if ($p[0].Length -ge 3) { $t = [regex]::Replace($t, [regex]::Escape($p[0]), $p[1], 'IgnoreCase') }
    }
    # Any other user folder that turns up in a path.
    $t = [regex]::Replace($t, '(?i)([A-Z]:\\Users\\)[^\\\r\n]+', '$1<user>')
    return ($t -replace '[^\x09\x0A\x0D\x20-\x7E]', '?')
}

function Get-BugFacts([string]$Ws) {
    $root = Split-Path $Ws -Parent
    $f = [ordered]@{}
    $f['Wizard version'] = '?'
    $vf = Join-Path $Ws 'version.txt'
    if (Test-Path -LiteralPath $vf) { $f['Wizard version'] = ([System.IO.File]::ReadAllLines($vf) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1) }
    $rb = Join-Path $root 'system\version.info'
    $f['RetroBat'] = $(if (Test-Path -LiteralPath $rb) { ([System.IO.File]::ReadAllText($rb)).Trim() } else { '?' })
    try { $f['Windows'] = [string][Environment]::OSVersion.VersionString } catch { $f['Windows'] = '?' }
    $act = Join-Path $Ws 'Settings\computers\active.txt'
    if (Test-Path -LiteralPath $act) {
        foreach ($line in [System.IO.File]::ReadAllLines($act)) {
            if ($line -match '^\s*(gpu|tier)\s*=\s*(.+)$') { $f[$Matches[1]] = $Matches[2].Trim() }
        }
    }
    $who = 'guest'
    try { $p = Read-SocialProfile $Ws; if ($null -ne $p -and -not $p.Guest) { $who = $p.Username + ' (' + $p.Id + ')' } } catch { }
    $f['From'] = $who
    return $f
}

# The whole report as Markdown. $Extra is for a crash: the error itself.
function New-BugReport([string]$Ws, [string]$What, [bool]$IncludeLogs, [string]$Extra = '', [string]$Kind = 'bug') {
    $nl = "`n"
    $b = New-Object System.Text.StringBuilder
    $head = @{ bug = 'What happened'; idea = 'The idea'; game = 'The game' }[$Kind]
    if ($null -eq $head) { $head = 'What happened' }
    [void]$b.Append('## ' + $head + $nl + $nl)
    $w = ([string]$What).Trim()
    if ($w -eq '') { $w = '(nothing typed)' }
    [void]$b.Append((Protect-BugText $w) + $nl + $nl)
    if ($Extra -ne '') { [void]$b.Append('## The error' + $nl + $nl + '```' + $nl + (Protect-BugText $Extra) + $nl + '```' + $nl + $nl) }
    [void]$b.Append('## This drive' + $nl + $nl)
    $facts = Get-BugFacts $Ws
    foreach ($k in $facts.Keys) { [void]$b.Append(('- **{0}:** {1}' -f $k, (Protect-BugText ([string]$facts[$k]))) + $nl) }
    if ($IncludeLogs) {
        $logs = [ordered]@{
            'wizard.log'  = @((Join-Path $Ws 'Cache\logs\wizard.log'), 80)
            'update.log'  = @((Join-Path $Ws 'Program\update\update.log'), 25)
            'social.log'  = @((Join-Path $Ws 'Cache\logs\social.log'), 25)
            'hook.log'    = @((Join-Path $Ws 'Backups\Saves\hook.log'), 25)
        }
        foreach ($k in $logs.Keys) {
            $tail = Get-BugTail $logs[$k][0] $logs[$k][1]
            if ($tail -eq '') { continue }
            [void]$b.Append($nl + '<details><summary>' + $k + ' (last lines)</summary>' + $nl + $nl + '```' + $nl + (Protect-BugText $tail) + $nl + '```' + $nl + '</details>' + $nl)
        }
    }
    $text = $b.ToString()
    if ($text.Length -gt 60000) { $text = $text.Substring(0, 60000) + $nl + '(cut short)' }
    return $text
}

function Get-BugTitle([string]$What, [string]$Extra = '', [string]$Kind = 'bug') {
    $w = (Get-SocialClean (Protect-BugText ([string]$What)) 70)
    if ($w -eq '' -and $Extra -ne '') { $w = 'Crash: ' + (Get-SocialClean (Protect-BugText $Extra) 60) }
    $prefix = @{ bug = '[bug] '; idea = '[idea] '; game = '[game request] ' }[$Kind]
    if ($null -eq $prefix) { $prefix = '[bug] ' }
    if ($w -eq '') { $w = $(if ($Kind -eq 'bug') { 'Bug report' } else { 'Suggestion' }) }
    return ($prefix + $w)
}

# The phone ping for a report: "Game request from Steven" over the report's
# own words. Who sent it comes from the report's From line, so a report that
# waited in the outbox still names the person who wrote it. That line has the
# Windows user name blanked out (<user>), so when a profile name matches it,
# the name comes from the profile signed in on this drive instead.
function Get-BugPing([string]$Title, [string]$Body, [string]$Ws = '') {
    $kinds = [ordered]@{ '[game request] ' = 'Game request'; '[idea] ' = 'Idea'; '[bug] ' = 'Bug report'; '[password] ' = 'Password reset' }
    $kind = 'New report'; $text = [string]$Title
    foreach ($k in $kinds.Keys) {
        if ($text.StartsWith($k)) { $kind = $kinds[$k]; $text = $text.Substring($k.Length); break }
    }
    $who = ''
    $m = [regex]::Match([string]$Body, '(?m)^- \*\*From:\*\* (.+?)\s*$')
    if ($m.Success) { $who = ($m.Groups[1].Value -replace '\s*\([^()]*\)$', '').Trim() }
    if ($who -match '[<?]' -and $Ws -ne '') {
        $who = ''
        try { $p = Read-SocialProfile $Ws; if ($null -ne $p -and -not $p.Guest) { $who = [string]$p.Username } } catch { }
    }
    $who = ($who -replace '[^\x20-\x7E]', '').Trim()   # the ping's title travels as a web header: plain letters only
    $from = $(if ($who -eq '') { '' } elseif ($who -eq 'guest') { ' from a guest' } else { ' from ' + $who })
    if ($text.Trim() -eq '') { $text = [string]$Title }
    return @{ Title = ($kind + $from); Text = $text }
}

# Sends one report. Returns @{ Ok; Url; Message }. On failure the report is
# put in the outbox so it goes next time.
function Send-BugReport([string]$Ws, [string]$Title, [string]$Body, [bool]$Queue = $true) {
    $res = @{ Ok = $false; Url = ''; Message = '' }
    $repo = Get-SocialRepo $Ws
    $json = '{"title":' + (ConvertTo-SocialJsonString $Title) + ',"body":' + (ConvertTo-BugJsonText $Body) + '}'
    $r = Invoke-SocialApi $Ws 'POST' "https://api.github.com/repos/$repo/issues" $json
    $P = Get-SocialPaths $Ws
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss_fff'
    if ($r.Status -eq 201) {
        try { $res.Url = [string](($r.Body | ConvertFrom-Json).html_url) } catch { }
        $res.Ok = $true
        $res.Message = 'Sent. Thank you!'
        if ($Queue) { try {
            $d = Join-SocialPath $P.SocialDir 'reports\sent'; New-SocialDir $d
            [System.IO.File]::WriteAllText((Join-SocialPath $d ($stamp + '.md')), ('# ' + $Title + "`n`n" + $Body))
        } catch { } }
        Write-SocialLog $Ws ("bug report sent: " + $Title)
        # Pings the admins' phones when they set that up (ntfy). Best effort.
        # (2026-10-31, Steven) The ping says what kind it is and who sent it.
        $ping = @{ Title = 'New report'; Text = $Title }
        try { $ping = Get-BugPing $Title $Body $Ws } catch { }
        [void](Send-SocialNotify $Ws $ping.Title $ping.Text)
        return $res
    }
    $res.Message = $(if ($r.Status -eq 0) { 'Could not reach GitHub.' } else { "GitHub said $($r.Status)." })
    Write-SocialLog $Ws ("bug report not sent: {0} {1}" -f $r.Status, $r.Body)
    if ($Queue) {
        try {
            $d = Join-SocialPath $P.SocialDir 'reports\outbox'; New-SocialDir $d
            [System.IO.File]::WriteAllText((Join-SocialPath $d ($stamp + '.md')), ('# ' + $Title + "`n`n" + $Body))
            $res.Message += ' It is saved and will be sent the next time the wizard opens with internet.'
        } catch { }
    }
    return $res
}

# Full JSON string escaping for a report body (it has newlines and quotes).
function ConvertTo-BugJsonText([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 32 -or [int]$ch -gt 126) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Sends whatever is waiting in the outbox. Returns how many went.
function Send-BugOutbox([string]$Ws) {
    $P = Get-SocialPaths $Ws
    $d = Join-SocialPath $P.SocialDir 'reports\outbox'
    if (-not (Test-Path -LiteralPath $d)) { return 0 }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.md' | Sort-Object Name)) {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $nl = $text.IndexOf("`n")
        if ($nl -lt 3) { continue }
        $title = $text.Substring(2, $nl - 2).Trim()
        $body = $text.Substring($nl + 1).TrimStart("`n")
        $r = Send-BugReport $Ws $title $body $false
        if (-not $r.Ok) { break }
        $sent = Join-SocialPath $P.SocialDir 'reports\sent'; New-SocialDir $sent
        Move-Item -LiteralPath $f.FullName -Destination (Join-SocialPath $sent $f.Name) -Force
        $n++
    }
    return $n
}
