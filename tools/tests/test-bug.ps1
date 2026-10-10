$ErrorActionPreference='Stop'
$S='/home/claude/work/new/_ClaudeWorkspace/scripts'
. "$S/SocialEngine.ps1"; . "$S/BugReport.ps1"
$pass=0;$fail=0; function A($c,$n){ if($c){$script:pass++}else{$script:fail++;"FAIL $n"} }
$Ws = Join-Path ([IO.Path]::GetTempPath()) ('bug-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force "$Ws/wizard","$Ws/machine" | Out-Null
$env:USERNAME='Steven'; $env:COMPUTERNAME='STEVEN-LT002'; $env:USERPROFILE='C:\Users\Steven'
[IO.File]::WriteAllText("$Ws/version.txt","2.3.0-dev`n")
[IO.File]::WriteAllText("$Ws/machine/active.txt","gpu     = Intel Iris Xe`ntier    = low`n")
[IO.File]::WriteAllText("$Ws/wizard/wizard.log",("line`n" * 100) + "2026 FATAL: C:\Users\Steven\AppData\x on STEVEN-LT002 by steven, also D:\Users\Bob\y`n")
$body = New-BugReport $Ws "The tab froze when I clicked ""Refresh""" $true 'Exception at C:\Users\Steven\foo'
A ($body -notmatch '(?i)steven') 'no username/pc anywhere'
A ($body -match '<home>\\AppData' -and $body -match '<pc>' -and $body -match 'D:\\Users\\<user>') 'replacements in place'
A ($body -match 'Wizard version:\*\* 2.3.0-dev' -and $body -match 'tier:\*\* low') 'facts'
A (($body -split "`n" | Where-Object { $_ -eq 'line' }).Count -le 80) 'log tail capped'
A ((Get-BugTitle 'x' ) -eq '[bug] x') 'title'
A ((Get-BugTitle '' 'boom at C:\Users\Steven') -match '^\[bug\] Crash: boom') 'crash title'
$j = ConvertTo-BugJsonText "a`"b\c`nd`te" ; A ($j -eq '"a\"b\\c\nd\te"') "json escape ($j)"
A (((('{"x":' + (ConvertTo-BugJsonText $body) + '}') | ConvertFrom-Json).x) -eq $body) 'body survives JSON'
$script:posts=@(); $script:up=$false
$script:SocialApiOverride={ param($M,$U,$B,$Acc) if($script:up){ $script:posts += ,@($U,$B); return @{Status=201;Body='{"html_url":"https://github.com/x/1"}'} } else { return @{Status=0;Body='down'} } }
$r = Send-BugReport $Ws '[bug] t' $body
A (-not $r.Ok -and $r.Message -match 'saved') 'offline -> queued'
A (@(Get-ChildItem "$Ws/social/reports/outbox").Count -eq 1) 'one in outbox'
$script:up=$true
$n = Send-BugOutbox $Ws
A ($n -eq 1 -and @(Get-ChildItem "$Ws/social/reports/outbox").Count -eq 0 -and @(Get-ChildItem "$Ws/social/reports/sent").Count -eq 1) 'outbox sent once, one copy kept'
A ($script:posts[0][0] -eq 'https://api.github.com/repos/Feirzen/retrobat-wizard-social/issues') 'goes to social repo issues'
$sentBody = ($script:posts[0][1] | ConvertFrom-Json)
A ($sentBody.title -eq '[bug] t' -and $sentBody.body.Trim() -eq $body.Trim()) 'outbox round-trip intact'
$r = Send-BugReport $Ws '[bug] t2' 'short'
A ($r.Ok -and $r.Url -eq 'https://github.com/x/1' -and @(Get-ChildItem "$Ws/social/reports/sent").Count -eq 2) 'direct send ok'
Remove-Item -Recurse -Force $Ws
"bug tests: $pass passed, $fail failed"
