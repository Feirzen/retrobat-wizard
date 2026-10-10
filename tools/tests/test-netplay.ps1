$ErrorActionPreference='Stop'
. /home/claude/work/new/_ClaudeWorkspace/scripts/NetplayEngine.ps1
$pass=0;$fail=0; function A($c,$n){ if($c){$script:pass++}else{$script:fail++;"FAIL $n"} }
$R = Join-Path ([IO.Path]::GetTempPath()) ('np-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$R/emulationstation/.emulationstation","$R/emulators/dolphin-emu/User/Config","$R/_ClaudeWorkspace/archive" | Out-Null
Copy-Item /mnt/user-data/uploads/RetroBat/emulationstation/.emulationstation/es_settings.cfg "$R/emulationstation/.emulationstation/"
Copy-Item /mnt/user-data/uploads/RetroBat/emulators/dolphin-emu/User/Config/Dolphin.ini "$R/emulators/dolphin-emu/User/Config/"
$before = [IO.File]::ReadAllText("$R/emulationstation/.emulationstation/es_settings.cfg")
$s = Get-NetplaySettings $R
A ($s.Ok -and $s.Enabled -and $s.Nickname -eq 'RETROBAT Player' -and $s.Relay -eq '' -and -not $s.Private) "reads the real file ($($s.Nickname))"
$res = Set-NetplaySettings $R @{ Nickname = 'Naverog'; Relay = $false; Private = $true }
A ($res.Ok -and $res.Changed -eq 2) "name + password written ($($res.Changed) $($res.Message))"
$s = Get-NetplaySettings $R
A ($s.Nickname -eq 'Naverog' -and $s.Private -and $s.Relay -eq '') 'read back'
$res = Set-NetplaySettings $R @{ Nickname = 'Naverog'; Relay = $false; Private = $true }
A ($res.Ok -and $res.Changed -eq 0) 'second time changes nothing'
A (@(Get-ChildItem "$R/_ClaudeWorkspace/archive" -Directory).Count -eq 1) 'one backup only'
$res = Set-NetplaySettings $R @{ Relay = $true; Private = $false }
$s = Get-NetplaySettings $R
A ($s.Relay -eq 'nyc' -and -not $s.Private) 'relay on, public'
$after = [IO.File]::ReadAllText("$R/emulationstation/.emulationstation/es_settings.cfg")
# every other line of the file is untouched
$a = @($before -split "`r?`n" | Where-Object { $_ -notmatch 'global\.netplay' -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
$b = @($after -split "`r?`n" | Where-Object { $_ -notmatch 'global\.netplay' -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
A (($a -join '|') -eq ($b -join '|')) 'nothing else in es_settings changed'
A ($after.StartsWith('<?xml') -and [IO.File]::ReadAllBytes("$R/emulationstation/.emulationstation/es_settings.cfg")[0] -eq 60) 'no BOM, xml header kept'
[xml]$chk = $after; A ($null -ne $chk.config) 'still valid xml'
# Dolphin
$dbefore = [IO.File]::ReadAllLines("$R/emulators/dolphin-emu/User/Config/Dolphin.ini")
A (Set-DolphinNetplayIni $R 'Naverog') 'dolphin ini written'
$d = [IO.File]::ReadAllLines("$R/emulators/dolphin-emu/User/Config/Dolphin.ini")
A ($d -contains 'TraversalChoice = traversal' -and $d -contains 'Nickname = Naverog' -and $d -contains 'TraversalServer = stun.dolphin-emu.org') 'netplay keys'
A (@($d | Where-Object { $_ -match '^TraversalChoice' }).Count -eq 1) 'no duplicate key'
A ($d.Count -eq $dbefore.Count + 3) "only 3 lines added ($($d.Count) vs $($dbefore.Count))"
$i = [array]::IndexOf($d, '[NetPlay]'); $j = [array]::IndexOf($d, '[AutoUpdate]')
A ($i -ge 0 -and $j -gt $i -and $d[$i+1] -like 'TraversalChoice*') 'keys inside the NetPlay section'
A (Set-DolphinNetplayIni $R "Na'v<e>rog") 'odd name ok'
A (([IO.File]::ReadAllLines("$R/emulators/dolphin-emu/User/Config/Dolphin.ini")) -contains 'Nickname = Naverog') 'odd characters stripped'
A (Set-EsStringSetting $R 'ThemeSet' 'es-theme-carbon') 'theme changed'; A (Set-EsStringSetting $R 'ThemeSet' 'ckau-book') 'theme set back'
A (-not (Set-EsStringSetting $R 'ThemeSet' 'ckau-book')) 'theme second time no change'
[xml]$t = [IO.File]::ReadAllText("$R/emulationstation/.emulationstation/es_settings.cfg")
A (@($t.config.string | Where-Object { $_.name -eq 'ThemeSet' }).Count -eq 1 -and @($t.config.string | Where-Object { $_.name -eq 'ThemeSet' })[0].value -eq 'ckau-book') 'one ThemeSet line'
Remove-Item -Recurse -Force $R
"netplay tests: $pass passed, $fail failed"
