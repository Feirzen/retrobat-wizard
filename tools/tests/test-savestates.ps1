# The save-state system (SaveStates.ps1 + the Saves tab reader in SaveIndex.ps1)
# on a fake RetroBat folder built from the drive's REAL es_savestates.cfg,
# es_systems.cfg, retroarch.cfg and Dolphin Hotkeys.ini.
param(
    [string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'),
    [string]$Real    = '/mnt/user-data/uploads/RetroBat'
)
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function A($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SaveStates.ps1')
. (Join-Path $Scripts 'SaveIndex.ps1')

$TR = Join-Path ([IO.Path]::GetTempPath()) ('ss' + [guid]::NewGuid().ToString('N').Substring(0, 6))
function F([string]$rel, [string]$text = 'x') { $p = Join-SsPath $TR $rel; $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; [IO.File]::WriteAllText($p, $text); return $p }
$es = 'emulationstation/.emulationstation'
New-Item -ItemType Directory -Force (Join-SsPath $TR $es) | Out-Null
Copy-Item "$Real/$es/es_savestates.cfg" (Join-SsPath $TR $es)
Copy-Item "$Real/$es/es_systems.cfg" (Join-SsPath $TR $es)
F "$es/es_settings.cfg" '<?xml version="1.0"?><config><string name="n64.core" value="mupen64plus_next" /></config>' | Out-Null
F 'emulators/retroarch/retroarch.cfg' ([IO.File]::ReadAllText("$Real/emulators/retroarch/retroarch.cfg")) | Out-Null
F 'emulators/dolphin-emu/User/Config/Hotkeys.ini' ([IO.File]::ReadAllText("$Real/emulators/dolphin-emu/User/Config/Hotkeys.ini")) | Out-Null

# the drive's shape: a placeholder FILE where RetroArch's n64 state folder would be
F 'saves/n64/libretro.mupen64plus_next' '' | Out-Null
F 'saves/n64/Super Smash Bros. (USA).srm' 'SRAM' | Out-Null
F 'emulators/retroarch/states/Super Smash Bros. (USA).state1' 'SMASH' | Out-Null
F 'emulators/retroarch/states/Super Smash Bros. (USA).state1.png' 'PNG' | Out-Null
F 'saves/snes/libretro.snes9x/Mario World.state2' 'MARIO' | Out-Null
F 'saves/snes/libretro.snes9x/Mario World.state2.png' 'PNG' | Out-Null
F 'saves/gamecube/dolphin/Kirby Air Ride (USA).s01' 'KIRBY' | Out-Null
F 'saves/gamecube/dolphin/Kirby Air Ride (USA).s01.png' 'PNG' | Out-Null
F 'emulators/dolphin-emu/User/StateSaves/GKYE01.s01' 'KIRBY' | Out-Null
F 'emulators/dolphin-emu/User/StateSaves/lastState.sav' 'LAST' | Out-Null
F 'saves/nds/melonds/sstates/Spirit Tracks.ml1' 'DS' | Out-Null
F 'saves/nds/Spirit Tracks.sav' 'DSSAVE' | Out-Null
F 'saves/psx/duckstation/Crash_01.sav' 'PSX' | Out-Null
F 'saves/psx/duckstation/Crash.mcd' 'CARD' | Out-Null

# --- templates and sources -------------------------------------------------
A ('Mario.state1' -match (Convert-SsTemplateToRegex '{{romfilename}}.state{{slot}}')) 'template: state slot'
A ('Mario.state' -match (Convert-SsTemplateToRegex '{{romfilename}}.state{{slot}}')) 'template: slot 0 has no number'
A (-not ('Mario.srm' -match (Convert-SsTemplateToRegex '{{romfilename}}.state{{slot}}'))) 'template: a save is not a state'
A ('Kirby.s01' -match (Convert-SsTemplateToRegex '{{romfilename}}.s{{slot2d}}')) 'template: dolphin'
$src = @(Get-SavestateSources $TR)
$dirs = @($src | ForEach-Object { Get-SsRel $TR $_.Dir })
A ($dirs -contains 'saves\snes\libretro.snes9x') 'RetroArch per-core folder found from RetroBat''s own list'
A (-not ($dirs -contains 'saves\n64\libretro.mupen64plus_next')) 'the placeholder FILE is never treated as a folder'
A ($dirs -contains 'emulators\retroarch\states') 'RetroArch loose folder'
A ($dirs -contains 'emulators\dolphin-emu\User\StateSaves') 'Dolphin own folder'
A ($dirs -contains 'saves\gamecube\dolphin') 'Dolphin menu folder'
A ($dirs -contains 'saves\nds\melonds\sstates') 'melonDS'
A ($dirs -contains 'saves\psx\duckstation') 'DuckStation from RetroBat''s list'
A (-not ($dirs | Where-Object { $_ -like 'saves\*\azahar' -or $_ -like 'saves\*\windows' })) 'confirmation-only entries are not swept'

# --- the sweep -------------------------------------------------------------
$sw = Invoke-SavestateSweep -Root $TR
$arch = Get-SsArchiveRoot $TR
$day = Get-ChildItem $arch -Directory | Select-Object -First 1
$swept = @(Get-ChildItem $day.FullName -File | Where-Object Name -ne 'origins.txt')
A ($sw.Moved -eq 9) ("nine files swept ($($sw.Moved))")
A ($swept.Count -eq 9) 'nine files in the archive'
A (Test-Path (Join-SsPath $TR 'saves/n64/Super Smash Bros. (USA).srm')) 'ordinary save left alone'
A (Test-Path (Join-SsPath $TR 'saves/nds/Spirit Tracks.sav')) 'DS save left alone'
A (Test-Path (Join-SsPath $TR 'saves/psx/duckstation/Crash.mcd')) 'memory card left alone'
A (Test-Path (Join-SsPath $TR 'emulators/dolphin-emu/User/StateSaves/lastState.sav')) 'Dolphin lastState.sav left alone'
A ($sw.Retired -eq 1 -and -not (Test-Path (Join-SsPath $TR 'saves/n64/libretro.mupen64plus_next')) -and (Test-Path (Join-SsPath $TR '_Wizard/Cache/Trash/retroarch-placeholders/saves/n64/libretro.mupen64plus_next'))) 'old placeholder retired to _SAFE TO DELETE (2026-10-12), not deleted'
$org = [IO.File]::ReadAllLines((Join-Path $day.FullName 'origins.txt'))
A ($org.Count -eq 9) 'every file has an origin line'
A (@($org | Where-Object { $_ -like "*Super Smash Bros. (USA).state1`temulators\retroarch\states\*" }).Count -eq 1) 'origin recorded'
$stamps = @($swept | ForEach-Object { $_.Name.Substring(0, 6) } | Select-Object -Unique)
A ($stamps.Count -eq 1) 'one time stamp per sweep, so a state and its picture stay paired'
$r2 = Invoke-SavestateSweep -Root $TR
A ($r2.Moved -eq 0) 'second sweep finds nothing'

# --- the Saves tab reader --------------------------------------------------
$states = @(Get-QuarantinedSavestates $arch)
A ($states.Count -eq 6) ("six states listed, pictures not counted ($($states.Count))")
$smash = @($states | Where-Object Key -eq 'SUPER SMASH BROS. (USA)')[0]
A ($null -ne $smash -and $smash.Slot -eq '1' -and $smash.Thumb -ne '' -and $smash.Kind -eq 'retroarch-loose') 'RetroArch state read with its picture'
$mario = @($states | Where-Object Key -eq 'MARIO WORLD')[0]
A ($null -ne $mario -and $mario.System -eq 'snes' -and $mario.Kind -eq 'retroarch') 'console from the origin'
A (@($states | Where-Object Key -eq 'GKYE').Count -eq 1) 'Dolphin game id cut to four'
A (@($states | Where-Object Key -eq 'KIRBY AIR RIDE (USA)').Count -eq 1) 'Dolphin rom-named copy'
A (@($states | Where-Object Key -eq 'SPIRIT TRACKS').Count -eq 1) 'melonDS state read'
A (@($states | Where-Object { $_.Key -eq 'CRASH' -and $_.Slot -eq '01' }).Count -eq 1) 'DuckStation state read'
$games = @(
    [pscustomobject]@{ System = 'n64'; GameId = 'Super Smash Bros. (USA)'; Kind = 'name'; Category = 'game'; Why = ''; DisplayName = 'Smash'; Name = ''; NameSource = ''; Image = ''; Files = New-Object System.Collections.ArrayList; Changed = (Get-Date); Bytes = 0 }
)
$all = @(Add-SavestatesToGames -Games $games -Savestates $states -Found @{})
$sg = @($all | Where-Object GameId -eq 'Super Smash Bros. (USA)')[0]
A ($sg.Savestates.Count -eq 1 -and $sg.Savestates[0].Kind -eq 'retroarch-loose') 'state listed against its game, kind kept'

# --- jump in: RetroArch behind a placeholder -------------------------------
# (a drive that still has one: put it back for this part)
F 'saves/n64/libretro.mupen64plus_next' '' | Out-Null
A (Test-SavestateJumpIn $sg.Savestates[0] 'n64') 'RetroArch can jump in'
$j = Set-SavestateJumpIn $TR $sg.Savestates[0] 'n64' 'Smash'
A $j.Ok ('jump in placed: ' + $j.Message)
$placed = Join-SsPath $TR 'saves/n64/libretro.mupen64plus_next/Super Smash Bros. (USA).state1'
A ([IO.Directory]::Exists((Join-SsPath $TR 'saves/n64/libretro.mupen64plus_next'))) 'placeholder moved aside, real folder made'
A ((Test-Path $placed) -and (Test-Path ($placed + '.png'))) 'state and picture where the launch menu looks'
A (Test-Path (Join-SsPath $TR '_Wizard/Backups/Saves/jump-in-placeholders/n64/libretro.mupen64plus_next')) 'placeholder waiting'
$h = @(Get-SsHolds $TR)
A ($h.Count -eq 4) ("hold list: 2 files + 1 placeholder + the game ($($h.Count))")
A (@($h | Where-Object Type -eq 'game')[0].Other -like 'Super Smash Bros. (USA)|*|Smash') 'hold remembers which game'
A ((Test-Path $smash.Path)) 'archived original still there'
$m1 = Invoke-SavestateSweep -Root $TR -MidGame
A ($m1.Moved -eq 0 -and (Test-Path $placed)) 'mid-game sweep leaves the held copy alone'
F 'saves/n64/libretro.mupen64plus_next/Super Smash Bros. (USA).state2' 'NEW' | Out-Null
$m2 = Invoke-SavestateSweep -Root $TR -MidGame
A ($m2.Moved -eq 1 -and (Test-Path $placed)) 'mid-game sweep takes a new state but not the held one'
# another game ending is just another game (Steven 2026-10-12: he only
# looked at the menu, and the jump in was gone)
Set-SsLastGame $TR 'R:/RetroBat/roms/nes/Galaga (USA).nes'
$ox = Invoke-SavestateSweep -Root $TR
A ($ox.Dropped -eq 0 -and (Test-Path $placed) -and @(Get-SsHolds $TR).Count -eq 4) 'another game ended: still ready'
A ((Get-SavestateJumpInState $TR).Ready -and (Get-SavestateJumpInState $TR).Name -eq 'Smash') 'Saves tab sees it waiting'
Set-SsLastGame $TR 'R:/RetroBat/roms/n64/Super Smash Bros. (USA).z64'
$e1 = Invoke-SavestateSweep -Root $TR
A ($e1.Dropped -eq 2 -and -not (Test-Path $placed)) 'game end: unchanged held copy and picture removed'
A ($e1.Restored -eq 1) 'game end: placeholder back'
A ($e1.Retired -eq 1 -and -not [IO.File]::Exists((Join-SsPath $TR 'saves/n64/libretro.mupen64plus_next')) -and (Test-Path (Join-SsPath $TR '_Wizard/Cache/Trash/retroarch-placeholders/saves/n64/libretro.mupen64plus_next.2'))) 'then retired, nothing overwritten'
A (@(Get-SsHolds $TR).Count -eq 0) 'hold list cleared'
A ((Test-Path $smash.Path)) 'archived original kept'
$states2 = @(Get-QuarantinedSavestates $arch)
A (@($states2 | Where-Object Key -eq 'SUPER SMASH BROS. (USA)').Count -eq 2) 'no duplicate of the jumped-into state (just the new one)'

# --- jump in: a held copy the game changed is swept, not removed -----------
$j2 = Set-SavestateJumpIn $TR $sg.Savestates[0] 'n64'
[IO.File]::WriteAllText($placed, 'CHANGED')
Set-SsLastGame $TR 'R:\RetroBat\roms\n64\Super Smash Bros. (USA).z64'
$e2 = Invoke-SavestateSweep -Root $TR
A ($e2.Moved -ge 1 -and -not (Test-Path $placed)) 'changed held copy swept into the archive'

# --- jump in: Dolphin, both copies -----------------------------------------
$kgames = @([pscustomobject]@{ System = 'gamecube'; GameId = 'GKYE'; Kind = 'code'; Category = 'game'; Why = ''; DisplayName = 'Kirby'; Name = 'Kirby Air Ride (USA)'; NameSource = 'found'; Image = ''; Files = New-Object System.Collections.ArrayList; Changed = (Get-Date); Bytes = 0 })
# game-names-found.txt knows a game by its id AND by its rom file name
$found = @{ 'GKYE' = [pscustomobject]@{ Name = 'Kirby Air Ride (USA)'; Image = '' }; 'KIRBY AIR RIDE (USA)' = [pscustomobject]@{ Name = 'Kirby Air Ride (USA)'; Image = '' } }
$k = @(Add-SavestatesToGames -Games $kgames -Savestates @(Get-QuarantinedSavestates $arch) -Found $found)
$kg = @($k | Where-Object GameId -eq 'GKYE')[0]
A ($kg.Savestates.Count -eq 1 -and @($kg.Savestates[0].Copies).Count -eq 2) 'Dolphin: one moment, two copies merged'
$j3 = Set-SavestateJumpIn $TR $kg.Savestates[0] 'gamecube'
A ($j3.Ok -and (Test-Path (Join-SsPath $TR 'saves/gamecube/dolphin/Kirby Air Ride (USA).s01')) -and (Test-Path (Join-SsPath $TR 'emulators/dolphin-emu/User/StateSaves/GKYE01.s01'))) 'Dolphin: both copies back where they came from'
Set-SsLastGame $TR 'R:/RetroBat/roms/gamecube/Kirby Air Ride (USA).iso'
$e3 = Invoke-SavestateSweep -Root $TR
A (-not (Test-Path (Join-SsPath $TR 'saves/gamecube/dolphin/Kirby Air Ride (USA).s01'))) 'Dolphin: cleared after the game'

# --- cancelling, and only one at a time -----------------------------------
$j5 = Set-SavestateJumpIn $TR $sg.Savestates[0] 'n64' 'Smash'
$j6 = Set-SavestateJumpIn $TR $kg.Savestates[0] 'gamecube' 'Kirby'
A ($j6.Ok -and -not (Test-Path $placed) -and (Get-SavestateJumpInState $TR).Name -eq 'Kirby') 'a second jump in replaces the first'
A (-not [IO.File]::Exists((Join-SsPath $TR 'saves/n64/libretro.mupen64plus_next'))) 'replaced: no placeholder file comes back'
$c1 = Clear-SavestateJumpIn $TR
A (-not (Test-Path (Join-SsPath $TR 'saves/gamecube/dolphin/Kirby Air Ride (USA).s01')) -and -not (Get-SavestateJumpInState $TR).Ready) 'cancel clears it'
A ((Get-SsRomKey 'Mario (USA).state1') -eq 'Mario (USA)' -and (Get-SsRomKey 'X.nkit.s03') -eq 'X.nkit' -and (Get-SsRomKey 'Y.state.auto') -eq 'Y') 'rom key from a state name'

# --- jump in: not possible -------------------------------------------------
$ds = @($states | Where-Object Key -eq 'SPIRIT TRACKS')[0]
A (-not (Test-SavestateJumpIn $ds 'nds')) 'melonDS: no jump in'
$j4 = Set-SavestateJumpIn $TR $ds 'nds'
A (-not $j4.Ok -and $j4.Message -like '*cannot be jumped into*') 'melonDS: plain words'
$psx = @($states | Where-Object Key -eq 'CRASH')[0]
A (Test-SavestateJumpIn $psx 'psx') 'DuckStation (RetroBat reads its folder): jump in allowed'

# --- old archives (Dolphin, no origins.txt) --------------------------------
$old = Join-SsPath $arch '2026-09-17'
F '_Wizard/Backups/Archive/quarantined-savestates/2026-09-17/101010__GALE01.s02' 'OLD' | Out-Null
F '_Wizard/Backups/Archive/quarantined-savestates/2026-09-17/101010__Melee.s02' 'OLD' | Out-Null
$st3 = @(Get-QuarantinedSavestates $arch)
$o1 = @($st3 | Where-Object Key -eq 'GALE')[0]
A ($null -ne $o1 -and $o1.Kind -eq 'dolphin-legacy') 'old Dolphin archive still read'
A (Test-SavestateJumpIn $o1 'gamecube') 'old Dolphin archive can jump in'

# --- the auto-save timer ---------------------------------------------------
A (-not (Test-SsTimerDue 44.9 0)) 'timer: not before 45'
A (Test-SsTimerDue 45 0) 'timer: at 45'
A (-not (Test-SsTimerDue 74 1)) 'timer: not before 75 once one is done'
A (Test-SsTimerDue 75.2 1) 'timer: at 75'
A ((Get-SsTimerTarget $TR 'retroarch') -eq 'retroarch') 'timer: RetroArch F2 confirmed from its own config'
A ((Get-SsTimerTarget $TR 'Dolphin') -eq 'dolphin') 'timer: Dolphin F2 confirmed from its own config'
A ((Get-SsTimerTarget $TR 'melonDS') -eq '') 'timer: melonDS left alone'
A ((Get-SsTimerTarget $TR 'explorer') -eq '') 'timer: anything else left alone'
[IO.File]::WriteAllText((Join-SsPath $TR 'emulators/retroarch/retroarch.cfg'), 'input_save_state = "f5"')
A ((Get-SsTimerTarget $TR 'retroarch') -eq '') 'timer: a different key means hands off'

Remove-Item -Recurse -Force $TR

# --- the backup: PC ports' own save folders, and the storage limit (2026-10-11)
$B = Join-Path ([IO.Path]::GetTempPath()) ('bk' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Force "$B/_Wizard/Program/scripts", "$B/saves/n64", "$B/emulators/soh/Save" | Out-Null
Copy-Item (Join-Path $Scripts 'Backup-RetroBatSaves.ps1'), (Join-Path $Scripts 'SaveIndex.ps1') "$B/_Wizard/Program/scripts/"
[IO.File]::WriteAllText("$B/saves/n64/Paper Mario.srm", 'v1')
[IO.File]::WriteAllText("$B/emulators/soh/Save/file1.sav", 'link1')
& pwsh -NoProfile -File "$B/_Wizard/Program/scripts/Backup-RetroBatSaves.ps1" -Quiet | Out-Null
$ix = Get-Content "$B/_Wizard/Backups/Saves/index.json" -Raw | ConvertFrom-Json
# (keys use \ on Windows; this test also runs on Linux, where / sneaks in)
$keys = @($ix.PSObject.Properties.Name)
A (@($keys | Where-Object { $_ -match '^soh\\_port\\[\\/]?file1\.sav$' }).Count -eq 1) 'Ship of Harkinian save backed up'
A (@($keys | Where-Object { $_ -match 'n64.Paper Mario\.srm$' }).Count -eq 1) 'ordinary save still backed up'
$gi = Get-SaveGroupInfo 'soh\_port\file1.sav'
A ($gi.Category -eq 'game' -and $gi.GameId -eq 'Ship of Harkinian') 'port save listed as a game'
A ((Resolve-SaveTarget "$B/saves" 'soh\_port\file1.sav') -eq (Join-Path "$B" 'emulators\soh\Save' | Join-Path -ChildPath 'file1.sav')) 'port save goes back to its own folder'
A ((Resolve-SaveTarget "$B/saves" 'n64\Paper Mario.srm') -eq (Join-Path "$B/saves" 'n64\Paper Mario.srm')) 'ordinary save goes back to saves'
# storage: keep 2 versions, whatever their age
[IO.File]::WriteAllText("$B/_Wizard/Backups/Saves/storage.ini", "versions = 2`r`nstates = 0`r`n")
foreach ($v in 2..5) {
    Start-Sleep -Milliseconds 1100
    [IO.File]::WriteAllText("$B/saves/n64/Paper Mario.srm", "v$v")
    & pwsh -NoProfile -File "$B/_Wizard/Program/scripts/Backup-RetroBatSaves.ps1" -Quiet | Out-Null
}
$hist = @(Get-ChildItem -Recurse -File "$B/_Wizard/Backups/Saves/Versions" | Where-Object Name -like '*Paper Mario.srm')
A ($hist.Count -eq 2) ("storage limit keeps the newest 2 versions ($($hist.Count))")
Remove-Item -Recurse -Force $B

# --- trimming save states (states = N) --------------------------------------
$P = Join-Path ([IO.Path]::GetTempPath()) ('pr' + [guid]::NewGuid().ToString('N').Substring(0, 6))
foreach ($i in 1..4) { $d = "$P/_Wizard/Backups/Archive/quarantined-savestates/2026-10-0$i"; New-Item -ItemType Directory -Force $d | Out-Null
    [IO.File]::WriteAllText("$d/120000__Mario World.state$i", 's'); [IO.File]::WriteAllText("$d/120000__Mario World.state$i.png", 'p')
    [IO.File]::WriteAllText("$d/120000__Zelda.state1", 'z') }
$gone = Invoke-SsStatePrune $P 2
A ($gone -eq 4) ("keeps the newest 2 per game ($gone trimmed)")
A ((Test-Path "$P/_Wizard/Backups/Archive/quarantined-savestates/2026-10-04/120000__Mario World.state4") -and -not (Test-Path "$P/_Wizard/Backups/Archive/quarantined-savestates/2026-10-01/120000__Mario World.state1.png")) 'newest kept, old picture gone too'
Set-SsStorage $P 10 3
$st = Get-SsStorage $P
A ($st.Versions -eq 10 -and $st.States -eq 3) 'storage settings round trip'
Remove-Item -Recurse -Force $P
Write-Host ("savestate tests (with backup): {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
