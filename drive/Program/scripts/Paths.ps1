<#
    Paths.ps1 - WHERE EVERYTHING LIVES (3.2, 2026-10-26).

    The wizard's folder is RetroBat\_Wizard, and everything in it lives in
    one of eight rooms. The room is decided by WHO OWNS the file, because
    that is what decides whether an update may touch it:

      Program\   the wizard itself. Updates own it and replace it; nobody
                 edits anything in here by hand.
                   scripts\  wizard\  defaults\  restore\  restore-off\
                   machine\ (tiers, rules)  docs\  drive-root\  theme-assets\
                   update\ (the updater's own records and downloads)
      Settings\  this setup's choices. An update only adds files that are
                 missing, never overwrites one.
      People\    profiles, friends, play time, favourites, each person's
                 saves (People\saves-of), the browser games' own profile.
      Backups\   Saves\, Steam\, Archive\.
      Buttons\   the one-click .bat files.
      Apps\      helper programs fetched or copied in (NewCP, MQReborn,
                 tools\ffmpeg.exe ...).
      Owner\     the admin's own things, never shipped: library uploads,
                 keys, the Zelda/Pokemon theme art, notes.
      Cache\     safe to delete at any time; everything in it rebuilds.
                   logs\  library\  social\  status.json  Trash\

    Only START HERE.txt and version.txt sit loose at the top.

    THE RULE FOR NEW CODE: every path starts with one of these room names,
    built with Join-Path from the _Wizard folder. Nothing else is invented.

    FUNCTIONS ONLY. ASCII, Windows PowerShell 5.1.
#>

$script:WizRooms = @('Program', 'Settings', 'People', 'Backups', 'Buttons', 'Apps', 'Owner', 'Cache')
$script:WizFolderName = '_Wizard'
$script:WizOldFolderName = '_ClaudeWorkspace'

# _Wizard from a script's own folder: <_Wizard>\Program\<scripts|wizard>.
function Get-WizRootFromScript([string]$ScriptDir) {
    return (Split-Path (Split-Path $ScriptDir -Parent) -Parent)
}

# Joins any number of segments ("Settings\features.ini" or "Settings",
# "features.ini") onto a base, with \ or / both accepted.
function Join-WizPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

# THE MOVE MAP: every old place (relative to _ClaudeWorkspace) and its new
# place (relative to _Wizard). Read by Move-ToWizardLayout.ps1, top to
# bottom, first match wins; a line ending in \ is a folder and everything
# under it. Kept here, next to the rooms, so the two can never disagree.
function Get-WizMoveMap {
    return @(
        # --- leftovers from older layouts -------------------------------------------
        @('profiles\machines\',          'Settings\computers\'),
        @('profiles\tiers\',             'Cache\Trash\layout-move\profiles-tiers\'),
        @('profiles\rules\',             'Cache\Trash\layout-move\profiles-rules\'),
        @('profiles\',                   'Settings\computers\'),
        @('Maintenance Steps\Show My Profile.bat', 'Cache\Trash\layout-move\Show My Profile.bat'),
        @('SteamArtworkDebug\',          'Cache\Trash\layout-move\SteamArtworkDebug\'),
        @('Try the new wizard look.vbs', 'Cache\Trash\layout-move\Try the new wizard look.vbs'),
        @('*.log',                       'Cache\logs\'),
        @('INSTALL BOTW Update and DLC.bat', 'Owner\INSTALL BOTW Update and DLC.bat'),
        # --- the program -----------------------------------------------------
        @('scripts\',                    'Program\scripts\'),
        @('wizard\wizard.ini',            'Settings\wizard.ini'),
        @('wizard\state.ini',             'Settings\state.ini'),
        @('wizard\theme.txt',             'Settings\theme.txt'),
        @('wizard\accent.txt',            'Settings\accent.txt'),
        @('wizard\shortcuts.txt',         'Settings\shortcuts.txt'),
        @('wizard\SetupWizard-v3.ps1',   'Owner\old\SetupWizard-v3.ps1'),
        @('wizard\*.log',                'Cache\logs\'),
        @('wizard\',                     'Program\wizard\'),
        @('defaults\scraper.txt',        'Owner\scraper.txt'),
        @('defaults\',                   'Program\defaults\'),
        @('docs\PER-GAME-SETTINGS.md',   'Program\docs\PER-GAME-SETTINGS.md'),
        @('docs\art\',                   'Program\docs\art\'),
        @('docs\',                       'Owner\docs\'),
        @('drive-root\',                 'Program\drive-root\'),
        @('update-restore-off\',         'Program\restore-off\'),
        @('update-restore\',             'Program\restore\'),
        @('update\',                     'Program\update\'),
        @('theme-assets\steam.mp4',      'Program\theme-assets\steam.mp4'),
        @('theme-assets\',               'Owner\theme-assets\'),
        @('ship-list.txt',               'Program\ship-list.txt'),
        @('machine\README.txt',          'Program\machine\README.txt'),
        @('machine\tiers\',              'Program\machine\tiers\'),
        @('machine\rules\',              'Program\machine\rules\'),
        # --- settings ----------------------------------------------------------
        @('machine\machines\',           'Settings\computers\'),
        @('machine\active.txt',          'Settings\computers\active.txt'),
        @('machine\last-applied.json',   'Settings\computers\last-applied.json'),
        @('machine\pinned.txt',          'Settings\computers\pinned.txt'),
        @('machine\game-settings.ini',   'Settings\game-settings.ini'),
        @('machine\maximize-windows.txt','Settings\maximize-windows.txt'),
        @('machine\steam-*.txt',         'Settings\steam\'),
        @('machine\',                    'Settings\computers\'),
        @('steam-parked\',               'Settings\steam\parked\'),
        @('features.ini',                'Settings\features.ini'),
        @('controllers.ini',             'Settings\controllers.ini'),
        @('couch-mouse.txt',             'Settings\couch-mouse.txt'),
        @('browser-games.ini',           'Settings\browser-games.ini'),
        @('flash-games.ini',             'Settings\flash-games.ini'),
        @('collections.ini',             'Settings\collections.ini'),
        @('player-counts.ini',           'Settings\player-counts.ini'),
        @('player-counts-todo.txt',      'Settings\player-counts-todo.txt'),
        @('family-hide.txt',             'Settings\family-hide.txt'),
        @('family-hidden.txt',           'Settings\family-hidden.txt'),
        @('new-games-to-check.txt',      'Settings\new-games-to-check.txt'),
        @('first-run.txt',               'Settings\first-run.txt'),
        # --- people --------------------------------------------------------------
        @('profile\',                    'People\'),
        @('social\cache\',               'Cache\social\'),
        @('social\wizard-alive.txt',     'Cache\social\wizard-alive.txt'),
        @('social\goto.txt',             'Cache\social\goto.txt'),
        @('social\*.log',                'Cache\logs\'),
        @('social\library-key.txt',      'Owner\library-key.txt'),
        @('social\Test Dummies.bat',     'Owner\test\Test Dummies.bat'),
        @('social\TestDummies.ps1',      'Owner\test\TestDummies.ps1'),
        @('social\',                     'People\social\'),
        @('browser-profile\',            'People\browser\'),
        # --- backups, buttons, apps ------------------------------------------------
        @('SaveBackups\*.bat',           'Buttons\'),
        @('SaveBackups\',                'Backups\Saves\'),
        @('SteamBackups\',               'Backups\Steam\'),
        @('archive\',                    'Backups\Archive\'),
        @('Maintenance Steps\',          'Buttons\'),
        @('RUN THIS AFTER AN UPDATE.bat','Buttons\RUN THIS AFTER AN UPDATE.bat'),
        @('apps\',                       'Apps\'),
        @('tools\',                      'Apps\tools\'),
        # --- owner, cache ------------------------------------------------------------
        @('library-to-publish\',         'Owner\library-to-publish\'),
        @('library\',                    'Cache\library\'),
        @('status.json',                 'Cache\status.json'),
        @('_SAFE TO DELETE\',            'Cache\Trash\'),
        @('START HERE.txt',              'START HERE.txt'),
        @('version.txt',                 'version.txt')
    )
}

# Where one old relative path goes ('' when the map has no line for it).
function Get-WizNewPath([string]$OldRel) {
    $o = ($OldRel -replace '/', '\').TrimStart('\')
    foreach ($m in (Get-WizMoveMap)) {
        $from = $m[0]; $to = $m[1]
        if ($from.EndsWith('\')) {
            if ($o.StartsWith($from, [System.StringComparison]::OrdinalIgnoreCase)) { return ($to + $o.Substring($from.Length)) }
            if ($o -ieq $from.TrimEnd('\')) { return $to.TrimEnd('\') }
            continue
        }
        if ($from.Contains('*')) {
            $dir = Split-Path $from -Parent; $pat = Split-Path $from -Leaf
            $odir = Split-Path $o -Parent; $leaf = Split-Path $o -Leaf
            if ($odir -ieq $dir -and $leaf -like $pat) { return ($to + $leaf) }
            continue
        }
        if ($o -ieq $from) { return $to }
    }
    return ''
}
