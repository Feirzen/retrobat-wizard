# Test harness for UpdateEngine.ps1 + Migrations.ps1. PowerShell 7, Linux.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($cond, [string]$name) {
    if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $name" -ForegroundColor Red }
}
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }

. (Join-Path $Scripts 'UpdateEngine.ps1')
. (Join-Path $Scripts 'Migrations.ps1')

$base = Join-Path ([IO.Path]::GetTempPath()) ('updtest-' + [guid]::NewGuid().ToString('N'))
$gh = Join-Path $base 'github'          # fake raw.githubusercontent.com/<repo>/<ref>/...
$ws = Join-Path $base 'drive/RetroBat/_Wizard'

# fetch override: map URL -> file under $gh/<ref>/<path>
$script:fetchLog = New-Object System.Collections.ArrayList
$script:UpdFetchOverride = {
    param($Url, $OutFile)
    [void]$script:fetchLog.Add($Url)
    $u = $Url -replace '\?t=\d+$', ''
    $rest = $u.Substring('https://raw.githubusercontent.com/Feirzen/retrobat-wizard/'.Length)
    $rest = [Uri]::UnescapeDataString($rest)
    $src = Join-Path $gh $rest
    if (-not (Test-Path -LiteralPath $src)) { throw "404 $rest" }
    $d = Split-Path -Parent $OutFile; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    Copy-Item -LiteralPath $src -Destination $OutFile -Force
}
$script:running = $false
$script:UpdRunningOverride = { $script:running }

# Publishes a version into the fake GitHub: files = @{ 'rel' = @('code'|'seed', 'content') }
function Publish([string]$ver, [hashtable]$files, [string]$notes = 'n1 | n2') {
    $tag = "v$ver"
    $lines = @("version`t$ver")
    foreach ($k in ($files.Keys | Sort-Object)) {
        $kind = $files[$k][0]; $content = $files[$k][1]
        $p = Join-Path (Join-Path (Join-Path $gh $tag) 'drive') $k
        W $p $content
        $lines += ("{0}`t{1}`t{2}`t{3}" -f $kind, (Sha $p), (Get-Item $p).Length, $k)
    }
    W (Join-Path (Join-Path $gh $tag) 'manifest.txt') (($lines -join "`n") + "`n")
    W (Join-Path (Join-Path $gh 'main') 'latest.ini') ("version = $ver`ntag = $tag`nnotes = $notes`n")
}

# ---------------------------------------------------------------------------
# The fake drive, as Steven's other drive looks today: 2.1, profiles\ folder
# ---------------------------------------------------------------------------
W (Join-Path $ws 'Settings/wizard.ini') "name = Test Wizard`nversion = 2.1`n"
W (Join-Path $ws 'Program/scripts/A.ps1') 'old A'
W (Join-Path $ws 'Program/scripts/Same.ps1') 'same'
W (Join-Path $ws 'Settings\features.ini') 'mine'
W (Join-Path $ws 'Program/machine/tiers/low.ini') 'old low'
W (Join-Path $ws 'Settings/computers/PC.ini') 'my pc'
W (Join-Path $ws 'Settings/computers/active.txt') 'active'
W (Join-Path $ws 'Backups/Saves/save.srm') 'SAVE'

Assert ((Get-UpdLocalVersion $ws) -eq '2.1') 'local version from wizard.ini'
Assert (Test-UpdNewer '2.2.0' '2.1') 'version compare 2.2.0 > 2.1'
Assert (-not (Test-UpdNewer '2.1' '2.1.0')) '2.1 == 2.1.0'
Assert (Test-UpdNewer 'v2.10' '2.9') 'v2.10 > 2.9'
Assert (-not (Test-UpdNewer 'garbage' '0.1')) 'garbage is old'

# safe paths (3.2: the rooms)
Assert (Test-UpdSafePath 'Program/scripts/A.ps1') 'safe normal'
Assert (Test-UpdSafePath 'Buttons/X Y.bat') 'safe spaces'
Assert (Test-UpdSafePath 'version.txt') 'top file version.txt'
Assert (-not (Test-UpdSafePath 'loose.txt')) 'any other top file refused'
Assert (Test-UpdSafePath 'Settings/features.ini' 'seed') 'Settings seed ok'
Assert (-not (Test-UpdSafePath 'Settings/features.ini' 'code')) 'Settings code refused'
Assert (-not (Test-UpdSafePath 'Program/update/installed.ini')) 'Program/update refused'
Assert (-not (Test-UpdSafePath 'People/profile.ini')) 'People refused'
Assert (-not (Test-UpdSafePath 'Backups/Saves/x.srm')) 'Backups refused'
Assert (-not (Test-UpdSafePath 'Owner/library-key.txt')) 'Owner refused'
Assert (-not (Test-UpdSafePath 'Cache/x')) 'Cache refused'
Assert (-not (Test-UpdSafePath 'Apps/x.exe')) 'Apps refused'
Assert (Test-UpdSafePath 'wizard/Launch-Wizard.vbs') 'the bridge allowed'
Assert (-not (Test-UpdSafePath 'wizard/SetupWizard.ps1')) 'nothing else in the old wizard folder'
Assert (-not (Test-UpdSafePath ('scr' + 'ipts/A.ps1'))) 'old scripts folder refused'
Assert (-not (Test-UpdSafePath '../x')) 'unsafe ..'
Assert (-not (Test-UpdSafePath 'a/../b')) 'unsafe mid ..'
Assert (-not (Test-UpdSafePath '/etc/x')) 'unsafe rooted'
Assert (-not (Test-UpdSafePath 'C:/x')) 'unsafe drive'
Assert (-not (Test-UpdSafePath 'a\b')) 'unsafe backslash'
Assert (-not (Test-UpdSafePath ('Program/scripts/caf' + [char]0xE9 + '.ps1'))) 'non-ascii refused'

# --- offline -----------------------------------------------------------------
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'offline') "offline when no latest.ini (got $($st.state))"
Assert ((Read-UpdStatus $ws)['state'] -eq 'offline') 'status file says offline'

# --- publish 2.2.0 -----------------------------------------------------------
Publish '2.2.0' @{
    'version.txt'              = @('code', "2.2.0`n")
    'Program/scripts/A.ps1'            = @('code', 'new A')
    'Program/scripts/Same.ps1'         = @('code', 'same')
    'Program/scripts/New.ps1'          = @('code', 'brand new')
    'Program/scripts/Migrations.ps1'   = @('code', [IO.File]::ReadAllText((Join-Path $Scripts 'Migrations.ps1')))
    'Settings/features.ini'    = @('seed', 'default features')
    'Settings/controllers.ini' = @('seed', 'default controllers')
    'Program/machine/tiers/low.ini'    = @('code', 'new low')
    'Program/machine/README.txt'       = @('code', 'readme')
    'Buttons/Show My Machine.bat' = @('code', 'new bat')
}

# peek
$script:fetchLog.Clear()
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available') "peek finds 2.2.0 (got $($st.state))"
Assert ($script:fetchLog.Count -eq 1) "peek fetches exactly one file (got $($script:fetchLog.Count))"
Assert ($script:fetchLog[0] -match '/main/latest\.ini\?t=\d+$') 'peek url is latest.ini with cache buster'
Assert (-not (Test-Path (Join-Path $ws 'Program/update/incoming'))) 'peek downloads nothing'
Assert ((Read-UpdStatus $ws)['notes'] -eq 'n1 | n2') 'notes in status'

# install with nothing downloaded is refused
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert (-not $r.Ok) 'install without download refused'

# full check: corrupt one file on "GitHub" first
$good = Join-Path $gh 'v2.2.0/drive/Program/scripts/New.ps1'
[IO.File]::WriteAllText($good, 'tampered')
$st = Invoke-UpdateCheck -Ws $ws
Assert ($st.state -eq 'error') "checksum mismatch -> error (got $($st.state))"
Assert (-not (Test-Path (Join-Path $ws 'Program/update/incoming/2.2.0/READY.txt'))) 'not READY after mismatch'
Assert ((Get-UpdReadyVersion $ws) -eq '') 'no ready version after mismatch'
[IO.File]::WriteAllText($good, 'brand new')

$script:fetchLog.Clear()
$st = Invoke-UpdateCheck -Ws $ws
Assert ($st.state -eq 'ready') "full check ready (got $($st.state) $($st.message))"
$inc = Join-Path $ws 'Program/update/incoming/2.2.0/files'
$dl = @(Get-ChildItem -Recurse -File $inc | ForEach-Object { $_.FullName.Substring($inc.Length + 1) -replace '\\', '/' })
Assert (@($script:fetchLog | Where-Object { $_ -match '/v2.2.0/drive/Program/scripts/New.ps1' }).Count -eq 1) 'resume: only the failed file fetched again'
Assert ($dl -notcontains 'Program/scripts/Same.ps1') 'unchanged file not downloaded'
Assert ($dl -notcontains 'Settings/features.ini') 'existing seed not downloaded'
Assert ($dl -contains 'Settings/controllers.ini') 'missing seed downloaded'
Assert ($dl -contains 'Program/scripts/A.ps1') 'changed file downloaded'
Assert ($dl -contains 'Buttons/Show My Machine.bat') 'space path downloaded'
Assert (@(Get-UpdRawUrl @{Repo='r/x'} 'v1' 'Maintenance Steps/A B.bat') -eq 'https://raw.githubusercontent.com/r/x/v1/Maintenance%20Steps/A%20B.bat') 'space is escaped in url'
Assert ((Get-UpdReadyVersion $ws) -eq '2.2.0') 'ready version 2.2.0'

# second check reuses the download
$script:fetchLog.Clear()
$st = Invoke-UpdateCheck -Ws $ws
Assert ($st.state -eq 'ready' -and $script:fetchLog.Count -eq 1) 'second check reuses ready download'

# refused while RetroBat runs
$script:running = $true
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert (-not $r.Ok -and $r.Message -match 'RetroBat is open') 'install refused while running'
Assert ((Get-UpdLocalVersion $ws) -eq '2.1') 'nothing changed while running'
$script:running = $false

# --- install -----------------------------------------------------------------
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert $r.Ok ("install ok: " + $r.Message)
Assert ((Get-UpdLocalVersion $ws) -eq '2.2.0') 'version now 2.2.0'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/scripts/A.ps1')) -eq 'new A') 'A replaced'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings\features.ini')) -eq 'mine') 'seed features.ini untouched'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings\controllers.ini')) -eq 'default controllers') 'missing seed written'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings/computers/PC.ini')) -eq 'my pc') 'machine file untouched'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/machine/tiers/low.ini')) -eq 'new low') 'tier replaced'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/update/previous/files/Program/machine/tiers/low.ini')) -eq 'old low') 'old tier kept in previous'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/update/previous/files/Program/scripts/A.ps1')) -eq 'old A') 'old A kept in previous'
Assert (Test-Path (Join-Path $ws 'Buttons/Show My Machine.bat')) 'new bat there'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Backups/Saves/save.srm')) -eq 'SAVE') 'save untouched'
Assert (-not (Test-Path (Join-Path $ws 'Program/update/incoming/2.2.0'))) 'incoming moved away'
Assert (@(Get-ChildItem (Join-Path $ws 'Cache/Trash/updates') -Directory | Where-Object Name -like 'downloaded-2.2.0-*').Count -eq 1) 'download parked in SAFE'
Assert ((Read-UpdStatus $ws)['state'] -eq 'installed') 'status installed'
Assert (Test-Path (Join-Path $ws 'Program/update/installed-manifest.txt')) 'installed manifest written'
$jl = @([IO.File]::ReadAllLines((Join-Path $ws 'Program/update/previous/changes.txt')))
Assert (($jl -contains "changed`tProgram/scripts/A.ps1") -and ($jl -contains "added`tProgram/scripts/New.ps1")) 'journal has changed + added'
Assert ($jl -notcontains "changed`tProgram/scripts/Same.ps1") 'identical file not journaled'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') 'up to date after install'

# --- go back -----------------------------------------------------------------
$info = Get-UpdGoBackInfo $ws
Assert ($null -ne $info -and $info.From -eq '2.1' -and $info.To -eq '2.2.0') 'go back info'
$r = Invoke-UpdateGoBack -Ws $ws
Assert $r.Ok ("go back ok: " + $r.Message)
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/scripts/A.ps1')) -eq 'old A') 'A restored'
Assert (-not (Test-Path (Join-Path $ws 'Program/scripts/New.ps1'))) 'added file moved away'
Assert (-not (Test-Path (Join-Path $ws 'version.txt'))) 'version.txt moved away'
Assert ((Get-UpdLocalVersion $ws) -eq '2.1') 'version back to 2.1'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/machine/tiers/low.ini')) -eq 'old low') 'old tier back'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings/computers/PC.ini')) -eq 'my pc') 'machine file still there'
Assert (-not (Test-Path (Join-Path $ws 'Buttons/Show My Machine.bat'))) 'new bat gone'
Assert (-not (Test-Path (Join-Path $ws 'Settings\controllers.ini'))) 'seed added by update moved away'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings\features.ini')) -eq 'mine') 'features.ini still mine'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Backups/Saves/save.srm')) -eq 'SAVE') 'save still untouched'
Assert (-not (Test-Path (Join-Path $ws 'Program/update/previous'))) 'previous used up'
Assert ($null -eq (Get-UpdGoBackInfo $ws)) 'nothing more to go back from'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/update/skip.txt')) -eq '2.2.0') 'skip = 2.2.0'
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'uptodate') "skipped version not offered (got $($st.state))"

# newer version is offered past the skip
Publish '2.2.1' @{
    'version.txt'   = @('code', "2.2.1`n")
    'Program/scripts/A.ps1' = @('code', 'A 221')
    'Program/scripts/Migrations.ps1' = @('code', [IO.File]::ReadAllText((Join-Path $Scripts 'Migrations.ps1')))
    'Program/machine/tiers/low.ini'  = @('code', 'low 221')
}
$st = Invoke-UpdateCheck -Ws $ws -NoDownload
Assert ($st.state -eq 'available' -and $st.version -eq '2.2.1') 'newer than skip is offered'
$st = Invoke-UpdateCheck -Ws $ws
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert $r.Ok ('install 2.2.1: ' + $r.Message)
Assert (-not (Test-Path (Join-Path $ws 'Program/update/skip.txt'))) 'skip cleared by install'
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Settings/computers/PC.ini')) -eq 'my pc') 'machine file still there on 2.2.1'

# --- removed files: 2.2.2 drops scripts/A.ps1 ---------------------------------
Publish '2.2.2' @{
    'version.txt'   = @('code', "2.2.2`n")
    'Program/scripts/Migrations.ps1' = @('code', [IO.File]::ReadAllText((Join-Path $Scripts 'Migrations.ps1')))
    'Program/machine/tiers/low.ini'  = @('code', 'low 221')
}
[void](Invoke-UpdateCheck -Ws $ws)
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert ($r.Ok -and $r.Removed -eq 1) "dropped file removed (removed=$($r.Removed))"
Assert (-not (Test-Path (Join-Path $ws 'Program/scripts/A.ps1'))) 'A gone after 2.2.2'
Assert (Test-Path (Join-Path $ws 'Program/update/previous/files/Program/scripts/A.ps1')) 'A kept in previous'
Assert (@(Get-ChildItem (Join-Path $ws 'Cache/Trash/updates') -Directory | Where-Object Name -like 'previous-from-*').Count -ge 1) 'older previous parked in SAFE'
$r = Invoke-UpdateGoBack -Ws $ws
Assert ($r.Ok -and [IO.File]::ReadAllText((Join-Path $ws 'Program/scripts/A.ps1')) -eq 'A 221') 'go back restores removed file'
Assert ((Get-UpdLocalVersion $ws) -eq '2.2.1') 'back at 2.2.1'

# --- a user-edited file that the new version drops is left alone -------------
[void](Invoke-UpdateCheck -Ws $ws -NoDownload)   # skip is 2.2.2 now
Publish '2.2.3' @{
    'version.txt'   = @('code', "2.2.3`n")
    'Program/scripts/Migrations.ps1' = @('code', [IO.File]::ReadAllText((Join-Path $Scripts 'Migrations.ps1')))
    'Program/machine/tiers/low.ini'  = @('code', 'low 221')
}
[IO.File]::WriteAllText((Join-Path $ws 'Program/scripts/A.ps1'), 'A edited by hand')
[void](Invoke-UpdateCheck -Ws $ws)
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert ($r.Ok -and $r.Removed -eq 0 -and (Test-Path (Join-Path $ws 'Program/scripts/A.ps1'))) 'hand-edited dropped file kept'

# --- failure partway rolls back ----------------------------------------------
Publish '2.2.4' @{
    'version.txt'   = @('code', "2.2.4`n")
    'Program/scripts/Migrations.ps1' = @('code', [IO.File]::ReadAllText((Join-Path $Scripts 'Migrations.ps1')))
    'Program/machine/tiers/low.ini'  = @('code', 'low 224')
    'Program/scripts/Z.ps1' = @('code', 'z')
}
[void](Invoke-UpdateCheck -Ws $ws)
# damage one downloaded file AFTER it was checked
$dmg = Join-Path $ws 'Program/update/incoming/2.2.4/files/Program/scripts/Z.ps1'
[IO.File]::WriteAllText($dmg, 'damaged')
$before = [IO.File]::ReadAllText((Join-Path $ws 'Program/machine/tiers/low.ini'))
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert (-not $r.Ok -and $r.Message -match 'put back') "damaged install rolls back ($($r.Message))"
Assert ([IO.File]::ReadAllText((Join-Path $ws 'Program/machine/tiers/low.ini')) -eq $before) 'tier rolled back'
Assert ((Get-UpdLocalVersion $ws) -eq '2.2.3') "version rolled back (got $(Get-UpdLocalVersion $ws))"
Assert (-not (Test-Path (Join-Path $ws 'Program/scripts/Z.ps1'))) 'no partial Z'

# --- manifest that tries to escape is refused ---------------------------------
$bad = Join-Path $base 'bad.txt'
W $bad ("version`t9`ncode`t" + ('a' * 64) + "`t1`t../../evil.txt`n")
Assert (-not (Read-UpdManifest $bad).Ok) 'escaping manifest refused'
W $bad ("version`t9`ncode`t" + ('a' * 64) + "`t1`tPeople/social/social-token.txt`n")
Assert (-not (Read-UpdManifest $bad).Ok) 'People manifest refused'
W $bad ("version`t9`ncode`t" + ('a' * 64) + "`t1`tSettings/features.ini`n")
Assert (-not (Read-UpdManifest $bad).Ok) 'Settings as code refused'
W $bad ("version`t9`nseed`t" + ('a' * 64) + "`t1`tSettings/features.ini`n")
Assert ((Read-UpdManifest $bad).Ok) 'Settings as seed fine'

# --- the bridge: a 3.2 drive never gets the old launcher back -------------------
Publish '2.2.5' @{
    'version.txt'   = @('code', "2.2.5`n")
    'Program/machine/tiers/low.ini' = @('code', 'low 224')
    'wizard/Launch-Wizard.vbs' = @('code', 'bridge')
}
[void](Invoke-UpdateCheck -Ws $ws)
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps
Assert ($r.Ok) "2.2.5 installs ($($r.Message))"
Assert (-not (Test-Path (Join-Path $ws 'wizard'))) 'no old wizard folder made on a 3.2 drive'

# --- migrations: nothing left for the old layout (the move covers it) ------------
Assert (@(Invoke-DriveMigrations -Ws $ws).Count -eq 0) 'no migrations to run on a 3.2 drive'

Remove-Item -Recurse -Force $base
Write-Host ("update tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
