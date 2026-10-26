$ErrorActionPreference='Stop'
$S=(Join-Path $PSScriptRoot '../../drive/Program/scripts')
. "$S/SocialEngine.ps1"
# pull the helper's functions and the console table out of the shipping file
$ast=[System.Management.Automation.Language.Parser]::ParseFile("$S/Social-Helper.ps1",[ref]$null,[ref]$null)
foreach($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)){ if($f.Name -ne 'Show-Popup'){ . ([scriptblock]::Create($f.Extent.Text)) } }
$tbl=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:ConsoleNames'},$false)[0]
. ([scriptblock]::Create($tbl.Extent.Text))
$Root="/tmp/noroot"; $pass=0;$fail=0; function A($c,$n){ if($c){$script:pass++}else{$script:fail++;"FAIL $n"} }
A ((Get-ConsoleName 'wii') -eq 'Wii') 'wii'
A ((Get-ConsoleName '3ds') -eq '3DS') '3ds'
A ((Get-ConsoleName 'switch') -eq 'Switch') 'switch'
A ((Get-ConsoleName 'megadrive') -eq 'MEGADRIVE') 'unknown upper'
A ($null -eq (Get-RunningGame)) 'no ES -> no game'
A (-not (Test-EsRunning)) 'no ES'
# Send-CheckIn with a fake API
$Ws = Join-Path ([IO.Path]::GetTempPath()) ('hlp-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $Ws | Out-Null
Write-SocialProfile $Ws (New-SocialProfile 'Tester' 'icon:n64')
$script:sent=@()
$script:SocialApiOverride={ param($M,$U,$B,$Acc) if($M -eq 'PUT'){ $script:sent += $B; return @{Status=201;Body='{}'} }; return @{Status=404;Body=''} }
$version='2.2.0'; $game=[pscustomobject]@{Name='Super Smash Bros. Brawl';Console='Wii'}; $since=(Format-SocialTime (Get-SocialNowUtc))
A (Send-CheckIn 'on') 'check-in ok'
$rec=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($script:sent[-1] | ConvertFrom-Json).content)) | ConvertFrom-Json
A ($rec.game -eq 'Super Smash Bros. Brawl' -and $rec.console -eq 'Wii' -and $rec.ingame -eq $true -and $rec.state -eq 'on') 'game sent'
$game=$null
A (Send-CheckIn 'offline') 'offline ok'
$rec=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($script:sent[-1] | ConvertFrom-Json).content)) | ConvertFrom-Json
A ($rec.state -eq 'offline' -and $rec.ingame -eq $false) 'offline sent'
Remove-Item -Recurse -Force $Ws
"helper tests: $pass passed, $fail failed"
