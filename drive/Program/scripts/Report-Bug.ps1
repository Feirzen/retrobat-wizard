<#
    Report-Bug.ps1 - the console way to report a bug, for
    Maintenance Steps\Report A Bug.bat. The wizard's Help tab does the same
    thing in a window. The engine is scripts\BugReport.ps1.

    Asks what happened, shows exactly what will be sent, asks once more, then
    sends it (or saves it to send later when there is no internet).

    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Ws = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'SocialEngine.ps1')
. (Join-Path $PSScriptRoot 'BugReport.ps1')

Write-Host ''
Write-Host '  Report a bug, or suggest something' -ForegroundColor Cyan
Write-Host '    1  Something is broken'
Write-Host '    2  A feature or idea'
Write-Host '    3  A game I would like on the drive'
Write-Host ''
$pick = Read-Host '  Which one (1, 2 or 3)'
$kind = @{ '1' = 'bug'; '2' = 'idea'; '3' = 'game' }[$pick.Trim()]
if ($null -eq $kind) { $kind = 'bug' }
$ask = @{ bug = '  What happened'; idea = '  Your idea'; game = '  Which game (and console)' }[$kind]
$what = Read-Host $ask
$logs = $false
if ($kind -eq 'bug') { $logs = (Read-Host '  Include the recent logs? They help a lot (Y/N)') -match '^\s*[Yy]' }
$title = Get-BugTitle $what '' $kind
$body = New-BugReport $Ws $what $logs '' $kind
Write-Host ''
Write-Host '  ----- this is exactly what will be sent -----' -ForegroundColor DarkGray
Write-Host $body
Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray
if ((Read-Host '  Send it? (Y/N)') -notmatch '^\s*[Yy]') { Write-Host '  Not sent. Nothing left the drive.'; exit 0 }
$r = Send-BugReport $Ws $title $body
Write-Host ''
Write-Host ('  ' + $r.Message) -ForegroundColor $(if ($r.Ok) { 'Green' } else { 'Yellow' })
