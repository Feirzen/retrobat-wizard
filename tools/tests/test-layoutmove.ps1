# The one-time move from _ClaudeWorkspace to _Wizard (Move-ToWizardLayout.ps1),
# against a copy of the real drive's layout (every top-level item it had on
# 2026-10-26, with samples inside), as it looks right after a 3.1 -> 3.2
# update: the 3.2 files already landed beside the old ones. PowerShell 7.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }
function T([string]$p) { if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { '<none>' } }
function J([string]$a, [string]$b) { $p = $a; foreach ($s in ($b -split '[\\/]')) { if ($s) { $p = [IO.Path]::Combine($p, $s) } }; $p }

. (Join-Path $Scripts 'Paths.ps1')
$base = Join-Path ([IO.Path]::GetTempPath()) ('lm-' + [guid]::NewGuid().ToString('N'))
$R = Join-Path $base 'RetroBat'
$O = J $R '_ClaudeWorkspace'
W (J $R 'retrobat.ini') '[RetroBat]'
W (J $R 'RetroBat.exe') 'exe'

# --- the old layout (3.1 user data, as on Steven's drive) --------------------
$old = [ordered]@{
    'START HERE.txt' = 'start here'; 'version.txt' = "3.2.0`n"
    'RUN THIS AFTER AN UPDATE.bat' = 'old run-after'
    'INSTALL BOTW Update and DLC.bat' = 'botw'
    'Try the new wizard look.vbs' = 'v3 test'
    'wiiu-test.log' = 'log'
    'features.ini' = 'familyfilter = on'          # his own choice
    'controllers.ini' = 'his controllers'
    'couch-mouse.txt' = 'flash'
    'browser-games.ini' = '[NewCP.bat]'
    'flash-games.ini' = '[game.swf]'
    'collections.ini' = 'zelda'
    'player-counts.ini' = 'counts'
    'new-games-to-check.txt' = 'todo'
    'status.json' = '{}'
    'ship-list.txt' = 'old ship list'
    'mystery.txt' = 'a file the map has never heard of'
    'scripts\Updater.ps1' = 'OLD updater (modified, so the update left it)'
    'scripts\OldOnly.ps1' = 'a script 3.2 no longer ships'
    'wizard\Launch-Wizard.vbs' = 'THE BRIDGE'
    'wizard\wizard.ini' = 'name = Steven the Setup Wizard'
    'wizard\state.ini' = 'ckaubookswitched = yes'
    'wizard\theme.txt' = 'dark'
    'wizard\shortcuts.txt' = 'made'
    'wizard\wizard.log' = 'the log'
    'wizard\SetupWizard-v3.ps1' = 'v3 test copy'
    'wizard\mage.png' = 'OLD mage (modified)'
    'defaults\scraper.txt' = 'login'
    'defaults\wizard.ini' = 'name = The RetroBat Wizard'
    'docs\CUSTOMIZATION-RECORD.md' = 'record'
    'docs\art\README.txt' = 'art'
    'drive-root\README.txt' = 'dr'
    'machine\README.txt' = 'readme'
    'machine\tiers\low.ini' = 'low'
    'machine\machines\ZTower.ini' = 'ztower'
    'machine\active.txt' = 'machine = ZTower'
    'machine\last-applied.json' = '{}'
    'machine\game-settings.ini' = 'his game settings'
    'machine\steam-owner.txt' = 'steam'
    'profile\profile.ini' = '[profile]'
    'profile\avatar.png' = 'png'
    'profile\play\abc.fav' = 'fav'
    'profile\saves-of\owner.txt' = 'abc'
    'profile\people\abc\profile.ini' = 'p'
    'social\social-token.txt' = 'rb1:x'
    'social\library-key.txt' = 'key'
    'social\social.log' = 'slog'
    'social\cache\players.json' = '[]'
    'social\wizard-alive.txt' = 'alive'
    'social\reports\sent\a.md' = 'report'
    'social\Test Dummies.bat' = 'td'
    'SaveBackups\Backup Saves Now.bat' = 'OLD bat'
    'SaveBackups\Versions\wii\a.bin' = 'save version'
    'SaveBackups\index.json' = '{}'
    'SaveBackups\hook.log' = 'hook'
    'SteamBackups\PC\libraryfolders.vdf' = 'vdf'
    'archive\quarantined-savestates\x.state' = 'state'
    'archive\features.ini.before' = 'b'
    'apps\NewCP\NewCP.exe' = 'exe'
    'tools\ffmpeg.exe' = 'ff'
    'library\library.json' = '{}'
    'library\art\a.png' = 'art'
    'library-to-publish\README.txt' = 'pub'
    'browser-profile\chrome\Default\Local Storage\x' = 'poptropica save'
    'steam-parked\Castle Crashers.url' = 'url'
    'theme-assets\ZELDA.mp4' = 'zelda'
    'theme-assets\steam.mp4' = 'old steam'
    'update\installed.ini' = 'version = 3.2.0'
    'update\installed-manifest.txt' = 'manifest'
    'update\update.ini' = 'channel = dev'
    'update\workshop.txt' = 'serial ='
    'update\previous\info.ini' = 'from = 3.1.0'
    'update-restore\PLAY.bat' = 'old master'
    'update-restore-off\x.po' = 'po'
    'Maintenance Steps\Show Help.bat' = 'OLD help (modified)'
    'Maintenance Steps\Show My Profile.bat' = 'ancient'
    '_SAFE TO DELETE\old.lnk' = 'lnk'
    'SteamArtworkDebug\notes.txt' = 'dbg'
}
foreach ($k in $old.Keys) { W (J $O $k) $old[$k] }
# --- what the 3.2 update landed beside it ------------------------------------
$landed = [ordered]@{
    'Program\scripts\Updater.ps1' = 'NEW updater'
    'Program\scripts\Paths.ps1' = 'paths'
    'Program\wizard\mage.png' = 'NEW mage'
    'Program\wizard\Launch-Wizard.vbs' = 'NEW launcher'
    'Program\defaults\wizard.ini' = 'name = The RetroBat Wizard'
    'Program\theme-assets\steam.mp4' = 'NEW steam'
    'Buttons\Show Help.bat' = 'NEW help'
    'Buttons\Backup Saves Now.bat' = 'NEW bat'
    'Settings\features.ini' = 'the shipped seed'
    'Settings\wizard.ini' = 'name = The RetroBat Wizard'
}
foreach ($k in $landed.Keys) { W (J $O $k) $landed[$k] }
# --- outside --------------------------------------------------------------------
W (J $R 'PLAY.bat') ('"%SystemRoot%\System32\wscript.exe" //nologo "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" -Play' + "`r`n")
W (J $R 'Steven the Setup Wizard.bat') ('if not exist "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" goto fallback' + "`r`n" + 'start "" powershell -Command "& ''%~dp0_ClaudeWorkspace\wizard\SetupWizard.ps1''"' + "`r`n")
W (J $R 'emulationstation\.emulationstation\scripts\game-end\zz-backup-saves.bat') ('set "LOG=%RBROOT%\_ClaudeWorkspace\SaveBackups\hook.log"' + "`r`n" + '"%PSEXE%" -File "%RBROOT%\_ClaudeWorkspace\scripts\Backup-RetroBatSaves.ps1" -Quiet' + "`r`n")
W (J $R 'emulationstation\.emulationstation\scripts\start\zz-social.bat') ('if not exist "%RBROOT%\_ClaudeWorkspace\profile\profile.ini" exit /b 0' + "`r`n")
W (J $R 'system\scripts\wiiu-launch.vbs') ('CHOOSER = fso.BuildPath(ROOT, "_ClaudeWorkspace\scripts\ControllerChooser.ps1")' + "`r`n" + 'LOGF = fso.BuildPath(ROOT, "_ClaudeWorkspace\wizard\controller-chooser.log")' + "`r`n")
W (J $R 'roms\windows\New Club Penguin.bat') ('REM  kept on this drive in _ClaudeWorkspace\apps\NewCP, so it goes' + "`r`n" + '"%SystemRoot%\System32\wscript.exe" //nologo "%~dp0..\..\_ClaudeWorkspace\scripts\Launch-Browser.vbs" "%~f0"' + "`r`n")
W (J $R 'roms\snes\Zelda.sfc') 'a game, never touched'
W (J $R 'emulationstation\.emulationstation\scripts\game-start\other.bat') 'nothing of ours'

function Snapshot([string]$dir) {
    $h = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) { $h[$f.FullName.Substring($dir.Length)] = [IO.File]::ReadAllText($f.FullName) }
    return $h
}
$before = Snapshot $R
$fileCount = @(Get-ChildItem -LiteralPath $R -Recurse -File).Count

# --- the text translator on its own ------------------------------------------------
$env:RBW_NOTHING = ''
$src = [IO.File]::ReadAllText((Join-Path $Scripts 'Move-ToWizardLayout.ps1'))
$fn = [regex]::Match($src, '(?s)function Convert-LegacyText.*?\n}\r?\n').Value
. ([scriptblock]::Create($fn))
$cases = @{
    '"%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" -Play' = '"%~dp0_Wizard\Program\wizard\Launch-Wizard.vbs" -Play'
    'REM  kept on this drive in _ClaudeWorkspace\apps\NewCP, so it goes' = 'REM  kept on this drive in _Wizard\Apps\NewCP, so it goes'
    '"%RBROOT%\_ClaudeWorkspace\profile\profile.ini"' = '"%RBROOT%\_Wizard\People\profile.ini"'
    'see _ClaudeWorkspace\features.ini by hand' = 'see _Wizard\Settings\features.ini by hand'
    'the _ClaudeWorkspace folder' = 'the _Wizard folder'
    '"_ClaudeWorkspace\wizard\controller-chooser.log")' = '"_Wizard\Cache\logs\controller-chooser.log")'
    '"%~dp0..\..\_ClaudeWorkspace\scripts\Launch-Browser.vbs"' = '"%~dp0..\..\_Wizard\Program\scripts\Launch-Browser.vbs"'
    'in _ClaudeWorkspace\Maintenance Steps\Show Help.bat now' = 'in _Wizard\Buttons\Show Help.bat now'
}
foreach ($k in $cases.Keys) { $got = Convert-LegacyText $k; Assert ($got -eq $cases[$k]) ("translate: [$k] -> [$got]") }

# --- the move -------------------------------------------------------------------
$mv = Join-Path $Scripts 'Move-ToWizardLayout.ps1'
& $mv -Root $R -Quiet -NoProcessCheck
Assert ($LASTEXITCODE -eq 0) "move exit code ($LASTEXITCODE)"
$N = J $R '_Wizard'
Assert (-not (Test-Path (J $R '_ClaudeWorkspace'))) 'old folder gone (renamed)'
Assert (Test-Path $N) '_Wizard there'
$top = @(Get-ChildItem -LiteralPath $N -Force | ForEach-Object Name | Sort-Object)
$want = @('Apps', 'Backups', 'Buttons', 'Cache', 'Owner', 'People', 'Program', 'Settings', 'START HERE.txt', 'Settings', 'version.txt') | Sort-Object -Unique
Assert (($top -join ',') -eq ($want -join ',')) ("only the rooms at the top: " + ($top -join ', '))

# settings: the person's old file wins over the shipped seed
Assert ((T (J $N 'Settings\features.ini')) -eq 'familyfilter = on') 'features.ini: his, not the seed'
Assert ((T (J $N 'Settings\wizard.ini')) -eq 'name = Steven the Setup Wizard') 'wizard.ini: his name kept'
Assert ((T (J $N 'Settings\state.ini')) -eq 'ckaubookswitched = yes') 'state.ini moved'
Assert ((T (J $N 'Settings\theme.txt')) -eq 'dark') 'theme.txt moved'
Assert ((T (J $N 'Settings\computers\ZTower.ini')) -eq 'ztower') 'computer profile moved'
Assert ((T (J $N 'Settings\computers\active.txt')) -eq 'machine = ZTower') 'active.txt moved'
Assert ((T (J $N 'Settings\game-settings.ini')) -eq 'his game settings') 'game-settings moved'
Assert ((T (J $N 'Settings\steam\steam-owner.txt')) -eq 'steam') 'steam record moved'
Assert ((T (J $N 'Settings\steam\parked\Castle Crashers.url')) -eq 'url') 'parked steam game moved'
foreach ($f in 'controllers.ini', 'couch-mouse.txt', 'browser-games.ini', 'flash-games.ini', 'collections.ini', 'player-counts.ini', 'new-games-to-check.txt') {
    Assert ((T (J $N ('Settings\' + $f))) -eq $old[$f]) "$f moved"
}
# program: the new 3.2 file wins, the old one goes to the trash
Assert ((T (J $N 'Program\scripts\Updater.ps1')) -eq 'NEW updater') 'new Updater kept'
Assert ((T (J $N 'Program\wizard\mage.png')) -eq 'NEW mage') 'new mage kept'
Assert ((T (J $N 'Program\wizard\Launch-Wizard.vbs')) -eq 'NEW launcher') 'new launcher kept, bridge set aside'
Assert ((T (J $N 'Program\theme-assets\steam.mp4')) -eq 'NEW steam') 'new steam video kept'
Assert ((T (J $N 'Buttons\Show Help.bat')) -eq 'NEW help') 'new button kept'
Assert ((T (J $N 'Cache\Trash\layout-move\old\scripts\Updater.ps1')) -like 'OLD updater*') 'old updater in the trash'
Assert ((T (J $N 'Cache\Trash\layout-move\old\wizard\Launch-Wizard.vbs')) -eq 'THE BRIDGE') 'bridge in the trash'
Assert ((T (J $N 'Program\scripts\OldOnly.ps1')) -eq 'a script 3.2 no longer ships') 'an unshipped old script still kept'
Assert ((T (J $N 'Program\machine\tiers\low.ini')) -eq 'low') 'tiers in Program'
# people, backups, apps, owner, cache
Assert ((T (J $N 'People\profile.ini')) -eq '[profile]') 'profile -> People'
Assert ((T (J $N 'People\saves-of\owner.txt')) -eq 'abc') 'saves-of -> People'
Assert ((T (J $N 'People\people\abc\profile.ini')) -eq 'p') 'friends pictures -> People'
Assert ((T (J $N 'People\social\social-token.txt')) -eq 'rb1:x') 'friends key -> People\social'
Assert ((T (J $N 'People\social\reports\sent\a.md')) -eq 'report') 'sent reports kept'
Assert ((T (J $N 'People\browser\chrome\Default\Local Storage\x')) -eq 'poptropica save') 'browser games profile -> People\browser'
Assert ((T (J $N 'Backups\Saves\Versions\wii\a.bin')) -eq 'save version') 'save versions -> Backups\Saves'
Assert ((T (J $N 'Backups\Saves\index.json')) -eq '{}') 'save index moved'
Assert ((T (J $N 'Buttons\Backup Saves Now.bat')) -eq 'NEW bat') 'save button: new one'
Assert ((T (J $N 'Backups\Steam\PC\libraryfolders.vdf')) -eq 'vdf') 'Steam backups'
Assert ((T (J $N 'Backups\Archive\quarantined-savestates\x.state')) -eq 'state') 'quarantined states kept (Saves tab needs them)'
Assert ((T (J $N 'Apps\NewCP\NewCP.exe')) -eq 'exe') 'apps -> Apps'
Assert ((T (J $N 'Apps\tools\ffmpeg.exe')) -eq 'ff') 'ffmpeg -> Apps\tools'
Assert ((T (J $N 'Owner\library-key.txt')) -eq 'key') 'library key -> Owner'
Assert ((T (J $N 'Owner\scraper.txt')) -eq 'login') 'scraper login -> Owner'
Assert ((T (J $N 'Owner\library-to-publish\README.txt')) -eq 'pub') 'library-to-publish -> Owner'
Assert ((T (J $N 'Owner\theme-assets\ZELDA.mp4')) -eq 'zelda') 'collection art -> Owner'
Assert ((T (J $N 'Owner\docs\CUSTOMIZATION-RECORD.md')) -eq 'record') 'his notes -> Owner\docs'
Assert ((T (J $N 'Owner\INSTALL BOTW Update and DLC.bat')) -eq 'botw') 'BotW installer -> Owner'
Assert ((T (J $N 'Owner\old\SetupWizard-v3.ps1')) -eq 'v3 test copy') 'v3 test copy -> Owner\old'
Assert ((T (J $N 'Owner\loose\mystery.txt')) -eq 'a file the map has never heard of') 'unknown file kept in Owner\loose'
Assert ((T (J $N 'Owner\test\Test Dummies.bat')) -eq 'td') 'test dummies -> Owner'
Assert ((T (J $N 'Cache\logs\wizard.log')) -eq 'the log') 'wizard.log -> Cache\logs'
Assert ((T (J $N 'Cache\logs\social.log')) -eq 'slog') 'social.log -> Cache\logs'
Assert ((T (J $N 'Cache\logs\wiiu-test.log')) -eq 'log') 'stray log -> Cache\logs'
Assert ((T (J $N 'Cache\social\players.json')) -eq '[]') 'social cache -> Cache'
Assert ((T (J $N 'Cache\library\library.json')) -eq '{}') 'library cache -> Cache'
Assert ((T (J $N 'Cache\status.json')) -eq '{}') 'status -> Cache'
Assert ((T (J $N 'Cache\Trash\old.lnk')) -eq 'lnk') 'SAFE TO DELETE -> Cache\Trash'
Assert ((T (J $N 'Cache\Trash\layout-move\Show My Profile.bat')) -eq 'ancient') 'ancient button to the trash'
Assert ((T (J $N 'Program\update\installed.ini')) -eq 'version = 3.2.0') 'update records -> Program\update'
Assert ((T (J $N 'Program\update\update.ini')) -eq 'channel = dev') 'channel kept'
Assert (-not (Test-Path (J $N 'Program\update\previous'))) 'go-back data set aside (no going back across the move)'
Assert (Test-Path (J $N 'Program\update\layout.txt')) 'move recorded'
Assert (Test-Path (J $N 'Cache\logs\move.log')) 'move log written'

# outside
foreach ($f in 'PLAY.bat', 'Steven the Setup Wizard.bat', 'emulationstation\.emulationstation\scripts\game-end\zz-backup-saves.bat', 'emulationstation\.emulationstation\scripts\start\zz-social.bat', 'system\scripts\wiiu-launch.vbs', 'roms\windows\New Club Penguin.bat') {
    Assert ((T (J $R $f)) -notmatch '_ClaudeWorkspace') "$f no longer says _ClaudeWorkspace"
}
Assert ((T (J $R 'PLAY.bat')) -match [regex]::Escape('"%~dp0_Wizard\Program\wizard\Launch-Wizard.vbs" -Play')) 'PLAY points at the new launcher'
Assert ((T (J $R 'emulationstation\.emulationstation\scripts\game-end\zz-backup-saves.bat')) -match [regex]::Escape('_Wizard\Backups\Saves\hook.log')) 'hook log path'
Assert ((T (J $R 'emulationstation\.emulationstation\scripts\start\zz-social.bat')) -match [regex]::Escape('_Wizard\People\profile.ini')) 'social hook profile path'
Assert ((T (J $R 'system\scripts\wiiu-launch.vbs')) -match [regex]::Escape('"_Wizard\Cache\logs\controller-chooser.log"')) 'Wii U launcher log path'
Assert ((T (J $R 'roms\windows\New Club Penguin.bat')) -match [regex]::Escape('_Wizard\Program\scripts\Launch-Browser.vbs')) 'browser game launcher path'
Assert ((T (J $R 'PLAY.bat')).EndsWith("`r`n")) 'Windows line ends kept'
Assert ((T (J $R 'roms\snes\Zelda.sfc')) -eq 'a game, never touched') 'games untouched'
Assert (@(Get-ChildItem -LiteralPath (J $N 'Backups\Archive') -Directory | Where-Object Name -like 'layout-move_*').Count -eq 1) 'outside files backed up'

# nothing lost: every file that was there is somewhere, plus the backups
$after = @(Get-ChildItem -LiteralPath $R -Recurse -File).Count
Assert ($after -ge $fileCount) "no file lost ($fileCount before, $after after)"

# --- again: nothing to do --------------------------------------------------------
$snap1 = Snapshot $R
& $mv -Root $R -Quiet -NoProcessCheck
Assert ($LASTEXITCODE -eq 0) 'second run fine'
$snap2 = Snapshot $R
$diff = @($snap2.Keys | Where-Object { -not $snap1.ContainsKey($_) -or $snap1[$_] -ne $snap2[$_] } | Where-Object { $_ -notmatch 'move\.log|layout\.txt' })
Assert ($diff.Count -eq 0) ("second run changes nothing (" + ($diff -join ', ') + ")")

# --- undo puts the old layout back exactly ----------------------------------------
& $mv -Root $R -Undo -Quiet
$back = Snapshot $R
$missing = @($before.Keys | Where-Object { -not $back.ContainsKey($_) -or $back[$_] -ne $before[$_] })
Assert ($missing.Count -eq 0) ("undo restores every original file (" + (($missing | Select-Object -First 8) -join ', ') + ")")
Assert (Test-Path (J $R '_ClaudeWorkspace')) 'undo: old folder name back'
Assert (-not (Test-Path (J $R '_Wizard'))) 'undo: no _Wizard left'

# --- a cut-short move finishes ------------------------------------------------------
& $mv -Root $R -Quiet -NoProcessCheck
Assert ((T (J $R '_Wizard\Settings\features.ini')) -eq 'familyfilter = on') 'moved again after undo'
# simulate: the rename happened, then it stopped (put two old things back at the top)
Move-Item (J $R '_Wizard\People') (J $R '_Wizard\profile')
Move-Item (J $R '_Wizard\Settings\features.ini') (J $R '_Wizard\features.ini')
& $mv -Root $R -Quiet -NoProcessCheck
Assert ((T (J $R '_Wizard\People\profile.ini')) -eq '[profile]') 'cut short: profile finished'
Assert ((T (J $R '_Wizard\Settings\features.ini')) -eq 'familyfilter = on') 'cut short: features finished'

# --- both folders at once (an old one beside a fresh _Wizard) -----------------------
W (J $R '_ClaudeWorkspace\features.ini') 'from a second old copy'
W (J $R '_ClaudeWorkspace\profile\play\zzz.fav') 'new fav'
& $mv -Root $R -Quiet -NoProcessCheck
Assert (-not (Test-Path (J $R '_ClaudeWorkspace'))) 'both: old folder folded in and gone'
Assert ((T (J $R '_Wizard\People\play\zzz.fav')) -eq 'new fav') 'both: its new file arrived'

Remove-Item -LiteralPath $base -Recurse -Force
Write-Host ("layout move: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
