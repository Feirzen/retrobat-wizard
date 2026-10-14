<#
    Apply-Settings.ps1
    ---------------------------------------------------------------------------
    Writes a known-good set of values into es_settings.cfg.

    Why this exists: EmulationStation rewrites es_settings.cfg every time it
    closes, and a RetroBat update can reset values. Rather than hunting through
    menus again, keep the list here and re-run this file.

    To change a setting later, or add a new one, edit the $Settings table
    below. That is the only part you need to touch. Format is:

        'system.setting_name' = 'value'

    Use 'global.' as the system for anything that should apply everywhere.

    There is a second list further down, $RemoveSettings, for keys that need
    to be DELETED rather than given a value. Some RetroBat options only act
    normally when the key is absent entirely.

    SINCE 2026-08-27: the per-console PERFORMANCE settings (resolutions and
    graphics backends for GameCube, Wii, Wii U, 3DS, DS and N64) no longer
    live in the lists here. They come from the machine profile system in
    _ClaudeWorkspace\machine\ (see machine\README.txt), which picks the
    right values for whichever computer the drive is plugged into. This
    script reads that system and applies its result through the same flow,
    so running it is still the one action that sets everything.

    IMPORTANT: RetroBat must be CLOSED when this runs, or EmulationStation
    will overwrite your changes when it exits. The script checks and refuses
    to run if it sees RetroBat open.

    Run it from:  Maintenance Steps\Apply My Settings.bat
#>

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# ===========================================================================
#  THE SETTINGS - edit this list, nothing else
# ===========================================================================
$Settings = [ordered]@{

    # --- Archive handling --------------------------------------------------
    # Stops the "keep the extracted files?" dialog that opens behind
    # EmulationStation and hangs the return to the frontend.
    # 'keep' = silently keep them in roms\.uncompressed on this drive.
    'global.decompressedfolders'  = 'keep'

    # --- 3DS / Azahar ------------------------------------------------------
    # How the two 3DS screens are arranged on the TV.
    #   0 = top screen above bottom screen, both at the same scale, like the
    #       real console. This is what we use.
    #   2 = one big screen with a small one beside it. That was the old
    #       setting, and the small screen ended up a quarter size and
    #       unreadable.
    # Other choices: 1 single screen, 3 side by side, 5 hybrid.
    '3ds.azahar_layout_option'     = '0'

    # (3ds.azahar_resolution_factor moved to the machine profile system on
    #  2026-08-27 - it is a performance setting, so it now depends on which
    #  computer the drive is plugged into. On the ZTower it is pinned to 3
    #  in _ClaudeWorkspace\machine\machines\ZTOWER.ini.)

    # --- DS / melonDS ------------------------------------------------------
    # (nds.melonds_internal_resolution moved to the machine profile system on
    #  2026-08-27. On the ZTower it is pinned to 8 in
    #  _ClaudeWorkspace\machine\machines\ZTOWER.ini. The hard limit is
    #  unchanged: DS 2D backgrounds and sprites are always 256x192, only the
    #  3D games get sharper.)

    # Frames OFF for DS, same reason as 3DS below. The frame is a separate
    # see-through window that sits on top of the emulator, and it swallows the
    # Select+Start close command, which is why DS took several tries to quit.
    # There was never a visible DS frame anyway - RetroBat's own developers
    # disabled the working method for standalone melonDS.
    # Trade: no button overlay on DS. Delete this line and re-run to undo.
    'nds.bezel'                       = 'none'

    # --- Wii / Dolphin -----------------------------------------------------
    # 0 = REAL Wii Remotes. This was on 1 (EMULATED), which told RetroBat to
    # build a fake Wii Remote out of whatever pad it found and hand it slot 1.
    # Dolphin then connected the actual remotes to whatever slots were left,
    # which is why two real remotes turned into players 2 and 3 with a dead
    # emulated remote sitting in player 1.
    # On 0, the real remotes take slots 1-4 in the order you turn them on, and
    # RetroBat additionally sets up any wired pads as GameCube controllers, so
    # games that support a GC pad (Smash Bros. Brawl, Mario Kart Wii) still
    # work with the wired pads.
    'wii.emulatedwiimotes'         = '0'

    # Frames OFF for Wii, in the game only. Same reasoning as DS and 3DS: the
    # frame is a separate see-through window sitting on top of the emulator,
    # and every time that has been on here it has caused a problem. There is
    # nothing to gain from it on a system whose whole point is pointing at
    # the screen.
    #
    # This does NOT affect the idle screen. The screensaver draws its own
    # frames from ScreenSaverDecorations further down, which is a completely
    # separate thing, so Wii still gets its console frame while idling.
    'wii.bezel'                    = 'none'


    # --- Wii U / Cemu ------------------------------------------------------
    # Present player 1's pad to the game as a Wii U PRO CONTROLLER instead of
    # the GamePad. Games that offer "GamePad or Pro Controller" will then
    # actually accept the Pro Controller option.
    # If a game ever insists on the GamePad, change this to 'gamepad'.
    'wiiu.cemu_controllerp0'       = 'procontroller'

    # Frames OFF for Wii U, in the game only. Same as Wii above - the idle
    # screen keeps its console frame regardless.
    'wiiu.bezel'                   = 'none'

    # Bezels OFF for 3DS. The bezel frame is drawn as a see-through window
    # floating on top of the game, and Azahar's own pop-up questions (pick a
    # Mii, etc.) open BEHIND it, which looks exactly like a frozen game.
    # Turning the frame off also means no button tattoo for 3DS - that is the
    # trade. Delete this line and re-run to put the frame back.
    '3ds.bezel'                    = 'none'

    # (3ds.graphics_api moved to the BRAND RULES of the machine profile
    #  system on 2026-08-27: _ClaudeWorkspace\machine\rules\vendor-rules.ini.
    #  The rule itself is unchanged and still hard: OpenGL on Nvidia cards,
    #  always, because Azahar's Vulkan backend is badly broken on Nvidia and
    #  the report was closed with no fix planned:
    #  https://github.com/azahar-emu/azahar/issues/1179 )

    # --- Where RetroBat opens ----------------------------------------------
    # Which system EmulationStation lands on when it starts.
    #
    # With this key ABSENT, EmulationStation restores whatever you were last
    # looking at, so it reopens on the console you happened to quit from.
    # 'all' is the All Games auto-collection: every game on the drive in one
    # list, whatever console it belongs to. That collection is already switched
    # on in CollectionSystemsAuto, so this value is valid as-is.
    #
    # If this ever stops working after an update, the other value worth trying
    # is 'auto-allgames', which is what the theme calls the same collection.
    'StartupSystem'                = 'all'

    # --- Idle screen (screensaver) -----------------------------------------
    # Clock format. '%I:%M %p' is 12-hour with AM/PM. The other two choices
    # EmulationStation accepts are '%H:%M:%S' (24-hour, the old default) and
    # '%p %I:%M'.
    # --- Look and feel -----------------------------------------------------
    # These four were set through the RetroBat menus rather than a script, so
    # an update could quietly put them back to stock and nobody would notice
    # until the frames disappeared. They live here now.
    #
    # The frame set. This is the one that decides which console frame each
    # system gets, on the idle screen as well as in game. Wii, Wii U and DS
    # frames were copied into this set by hand and are kept alive by
    # update-restore, so changing this name would lose them.
    'global.bezel'                 = 'default_curve_night'

    # Show the control overlay. Worth more than the frames here, because the
    # controllers get swapped around a lot.
    'global.tattoo'                = '1'

    # What the idle screen does: play a random game preview video.
    'ScreenSaverBehavior'          = 'random video'

    # Show the game name at the start and end of each idle screen video.
    'ScreenSaverGameInfo'          = 'start & end'

    'ScreenSaverTimeFormat'        = '%I:%M %p'

    # Date line under the clock. Was the ISO default, 2026-08-24.
    'ScreenSaverDateFormat'        = '%b %d, %Y'

    # Console frames ON for the idle screen.
    #
    # Each system gets its own frame if the decoration set has one, and the
    # plain curved-TV frame if it does not. The one exception is 3DS - see
    # $DecorationsToHide further down for why, and how to undo it.
    # Other accepted values: 'none' and 'random'.
    'ScreenSaverDecorations'       = 'systems'
}
# ===========================================================================


# ===========================================================================
#  ON/OFF SETTINGS - the ones EmulationStation stores as <bool>, not <string>
# ===========================================================================
#  EmulationStation keeps true/false options in a different kind of line in
#  es_settings.cfg. Putting one in the list above would write the wrong kind
#  of line and EmulationStation would quietly ignore it. Put those here.
#  Values must be exactly 'true' or 'false'.
# ---------------------------------------------------------------------------
$BoolSettings = [ordered]@{

    # Idle screen videos play their sound instead of being silent.
    # EmulationStation has no volume slider for this - it is only on or off -
    # so the videos themselves were re-recorded quieter, with a gentle
    # fade-in, by 10 - QUIET THE IDLE SCREEN VIDEOS.bat.
    'ScreenSaverVideoMute' = 'false'

    # Show the clock and date on the idle screen.
    'ScreenSaverDateTime'  = 'true'

    # Land on the All Games TILE, not inside the list of games.
    #
    # 'false' shows All Games in the carousel with its artwork and video, and
    # you press A to go in - which also means you can still scroll sideways to
    # a single console. 'true' would drop you straight into the list of every
    # game and skip the carousel entirely.
    #
    # 'false' is also EmulationStation's own default, so this line states the
    # intention rather than changing anything today. It is here so that if a
    # future RetroBat ships a different default, this holds the behaviour.
    'StartupOnGameList'    = 'false'

    # Let the controller DO something while the idle screen is running,
    # instead of any button simply waking it up. Added 2026-09-06.
    #
    # With this on, and the idle screen set to random video or slideshow:
    #     RIGHT or SELECT   skip to a different video
    #     START             launch the game that is showing
    #     anything else     wake up, as before
    #
    # Read out of EmulationStation's own source, not guessed: the setting is
    # a bool called ScreenSaverControls and it is handled in Window.cpp,
    # guarded on the idle screen being one of those two types.
    #
    # Like StartupOnGameList above, 'true' is ALSO EmulationStation's own
    # default, so this line changes nothing today. It is here because Steven
    # asked for a skip button and the honest answer turned out to be that he
    # already had one: writing it down means a future RetroBat cannot quietly
    # take it away, and means the next person to ask can read this instead of
    # going through the source again.
    'ScreenSaverControls'  = 'true'
}
# ===========================================================================


# ===========================================================================
#  SETTINGS EMULATIONSTATION THROWS AWAY BECAUSE THEY ARE ITS OWN DEFAULT
# ===========================================================================
#  EmulationStation rewrites es_settings.cfg every time it closes, and while
#  doing so it DROPS any key whose value is the same as its own built-in
#  default. That is not a fault and nothing is lost - the setting still
#  behaves the way we asked, because the way we asked for is what it does
#  when the key is absent.
#
#  It did cause a permanent false alarm. The health check compares the file
#  against what was last applied, saw four keys missing, and read that as
#  "something reverted your settings". Pressing its Fix button wrote them
#  back, the next game night stripped them again, and the light went red
#  again. Nothing was ever wrong.
#
#  So: every key named below is one we write ON PURPOSE even though it
#  changes nothing today (a future RetroBat could ship a different default,
#  and then the line starts doing work), and which the health check must
#  treat as FINE when it is absent. Absent is the only forgiven state - a
#  key that is present with the WRONG value is still real drift.
#
#  The list is saved into machine\last-applied.json by Save-AppliedSnapshot
#  below, so the health check reads it from there rather than keeping a
#  second copy of it. Add a key here and the health check follows.
#
#  Each entry was confirmed against the drive's own behaviour on 2026-09-18,
#  not guessed from documentation: with all four keys absent, the idle screen
#  still shows the per-system console frames, still plays video sound, still
#  answers RIGHT / SELECT / START, and RetroBat still opens on the carousel.
# ---------------------------------------------------------------------------
$EsOwnDefaults = @(
    'ScreenSaverDecorations'   # 'systems' - per-system frames on the idle screen
    'ScreenSaverVideoMute'     # 'false'   - idle screen videos keep their sound
    'StartupOnGameList'        # 'false'   - land on the All Games tile, not in the list
    'ScreenSaverControls'      # 'true'    - RIGHT / SELECT skip, START launches
)
# ===========================================================================


# ===========================================================================
#  SETTINGS TO REMOVE - keys that should not exist at all
# ===========================================================================
#  Some RetroBat settings only behave correctly when the key is ABSENT.
#  Setting them back to "auto" is not the same thing as never having set them.
#  Anything listed here is deleted from es_settings.cfg if it is found.
# ---------------------------------------------------------------------------
$RemoveSettings = @(

    # --- N64 ---------------------------------------------------------------
    # Tried 'xbox' to make the tattoo agree with the buttons. It changed the
    # tattoo but not the actual controls, so it made things worse. RetroBat's
    # original behaviour is this key not existing at all, so remove it rather
    # than setting it back to a value.
    'n64.lr_n64_buttons'
)
# ===========================================================================


# ===========================================================================
#  EMULATOR CONFIG FILES - settings inside an emulator's OWN file
# ===========================================================================
#  For things RetroBat has no menu option for. Format is:
#
#      'path\to\file.ini' = [ordered]@{ 'key' = 'value' }
#
#  Paths are relative to the RetroBat folder. Only keys that ALREADY exist in
#  the file are changed - nothing is ever added, so a typo cannot corrupt a
#  config. The file is backed up before it is touched.
# ---------------------------------------------------------------------------
$EmulatorIniSettings = [ordered]@{

    # --- Azahar (3DS) ------------------------------------------------------
    # lle_applets = true tells Azahar to run the REAL 3DS system programs for
    # things like the Mii picker and the on-screen keyboard, instead of its own
    # stand-ins. Those programs live in the emulated NAND.
    #
    # It was 'false' for most of 2026 because the NAND was empty, so any game
    # that asked for one waited forever and looked exactly like a frozen game.
    # That was the Luigi's Mansion / Mario 3D Land / Mario Kart 7 bug.
    #
    # On 2026-08-25 the real system files were pulled off a genuine console
    # with the Azahar Artic Setup Tool, so the NAND now has the shared font
    # (0004009b\00010202), the Mii resources (000400db\00010302) and the whole
    # set of system applets under 00040030. With those present 'true' is both
    # correct and better: the keyboard and the Mii picker draw on the bottom
    # screen inside the game, like real hardware, instead of opening a Windows
    # dialog over the top.
    #
    # It also side-steps the pause bug below, because a dialog that never opens
    # can never steal focus.
    #
    # IF A 3DS GAME HANGS AFTER THIS: put it back to 'false'. That would mean
    # the applet that game wants is not in the NAND after all.
    #
    # shaders_accurate_mul = true makes Azahar reproduce one specific quirk of
    # real 3DS maths exactly. It is correct, and it is slow - it is the main
    # reason 3DS games stutter on a machine that should have power to spare.
    # false is Azahar's own shipped default and what almost everybody runs.
    # If one particular game develops odd flickering or missing effects, this
    # is the first thing to put back.
    #
    # WARNING: RETROBAT OVERWRITES THIS ONE. Setting it here is not enough.
    # Proven on 2026-08-25: this script wrote false, one 3DS game was launched,
    # and RetroBat's launcher had put it back to true before the next run.
    # RetroBat regenerates Azahar's config on every launch and forces this
    # value, and there is no RetroBat menu option for it.
    #
    # It is still listed because it costs nothing and would take effect if
    # RetroBat ever stops forcing it. The real fix is lle_applets above.
    #
    # What the bug actually was:
    #
    # pauseWhenInBackground = true was the real cause of "3DS games freeze".
    # Whenever Azahar needs to ask you something - the on-screen keyboard, the
    # Mii picker - it opens an ordinary Windows dialog. The game window loses
    # focus, and Azahar PAUSES the emulation. Citra used to un-pause by itself
    # when the window came back. Azahar deliberately does not: you have to
    # press Continue. So you answer the question, the dialog closes, and the
    # game sits there paused, looking exactly like a hang.
    #
    # false = never auto-pause, so the game carries straight on.
    #
    # If a 3DS game ever looks frozen again, press P on a keyboard or
    # Select + A on a pad. Both are Azahar's continue command. If it springs
    # back to life, this setting has been reset and needs re-applying.
    #
    # NOTE on the '\default' lines: Azahar reads a companion key next to every
    # setting. If that companion says 'true', Azahar throws away the stored
    # value and uses its built-in one instead. So both lines have to be set,
    # or the change does nothing at all.
    'emulators\azahar\user\config\qt-config.ini' = [ordered]@{
        'lle_applets'                    = 'true'
        'lle_applets\default'            = 'false'
        'shaders_accurate_mul'           = 'false'
        'shaders_accurate_mul\default'   = 'false'
        'pauseWhenInBackground'          = 'false'
        'pauseWhenInBackground\default'  = 'false'
    }
}
# ===========================================================================


# ===========================================================================
#  CLOSE-THE-EMULATOR OVERRIDES - es_padtokey.cfg
# ===========================================================================
#  es_padtokey.cfg is what turns Select+Start on a pad into "shut this
#  emulator down". It offers two ways of doing it:
#
#     (%{CLOSE})  ask the window politely to close. Correct, but it only
#                 reaches the window that currently has focus.
#     (%{KILL})   end the program outright. Always works.
#
#  Cemu is listed below because CLOSE does not reach it: in fullscreen, the
#  window on top is Cemu's drawing surface, which has no idea what to do with
#  a close request, so nothing happens and the Wii U game just keeps running.
#  KILL is what RetroBat already uses for a long list of other emulators for
#  the same reason. Wii U games write their saves at save points, exactly like
#  the real console, so this loses nothing that was already saved.
#
#  Format is:  'AppNameInPadToKey' = '(%{KILL})'
#  The name has to match the <app name="..."> entry, which is the emulator's
#  .exe name without the extension.
# ---------------------------------------------------------------------------
$PadToKeyOverrides = [ordered]@{
    'Cemu' = '(%{KILL})'
}
# ===========================================================================


# ===========================================================================
#  IDLE SCREEN FRAMES TO SUPPRESS
# ===========================================================================
#  The idle screen picks a frame by looking for an image named after the
#  system inside the decoration set. If there isn't one, it falls back to the
#  plain curved-TV frame, which fits any video.
#
#  The 3DS frame is the problem. Its see-through cut-out is a tall dual-screen
#  shape, 800x956, because a real 3DS picture would be both screens stacked.
#  Every scraped 3DS preview video on this drive is 800x480 - the top screen
#  only. So the video landed straddling the console's hinge, half in the top
#  screen and half in the bottom, with the sides hidden behind the plastic.
#
#  Rather than turn frames off everywhere, the 3DS image is moved out of the
#  way so 3DS falls back to the plain frame, which looks right. Every other
#  system keeps its proper console frame.
#
#  Nothing is deleted. Files land in
#      _ClaudeWorkspace\archive\decorations-hidden\
#  and can be copied straight back to undo this. A RetroBat update will put
#  the originals back, and this script will move them out again next run.
#
#  Paths are relative to system\decorations.
# ---------------------------------------------------------------------------
$DecorationsToHide = @(
    'default_curve_night\systems\3ds.png'
    'default_curve_night\systems\3ds.info'
)
# ===========================================================================


# ===========================================================================
#  LAUNCH CONFIRMATION MENU - which emulators get the "LAUNCH GAME" screen
# ===========================================================================
#  RetroBat only shows that menu for emulators listed in es_savestates.cfg.
#  Standalone emulators are not listed, so pressing A launches them instantly
#  with no way to back out of a slow 40-second load.
#
#  Listing one here gives it the menu. Because these emulators never write
#  savestate files RetroBat can see, the menu will only ever offer the single
#  "LAUNCH GAME" entry - which is exactly the confirmation screen we want.
#
#  Existing entries are never touched, so a RetroBat update that adds real
#  savestate support for one of these will win and this will leave it alone.
#
#  Since 2026-10-11 (Steven: the "Launch game?" screen on every system) the
#  list below is only the start: EVERY emulator named in RetroBat's own
#  es_systems*.cfg gets the same entry, unless RetroBat already lists it. So a
#  console added later gets the screen too. Each added entry points at an
#  empty folder (saves\<system>\<emulator>), which is why the menu shows only
#  LAUNCH GAME. The emulators whose save states RetroBat really reads
#  (RetroArch, Dolphin...) keep RetroBat's own entries, and the save-state
#  sweep (SaveStates.ps1) keeps their folders empty.
# ---------------------------------------------------------------------------
$SaveStateMenuEmulators = @(
    'azahar'      # 3DS
    'cemu'        # Wii U
    'melonds'     # DS
    'soh'         # Ship of Harkinian (Ocarina of Time PC port)
    '2ship'       # 2 Ship 2 Harkinian (Majora's Mask PC port)
    'starship'    # Starship (Star Fox 64 PC port)
    'ghostship'   # Ghostship (Luigi's Mansion PC port)
    'windows'     # the Steam shelf, added 2026-09-19. The steam system
                  # runs on the 'windows' emulator, so this one line is
                  # what gives a Steam game the same launch menu as a
                  # 3DS or Wii U game. Also covers roms\windows itself.
)
# ===========================================================================

# --- locate RetroBat -------------------------------------------------------
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    exit 1
}

$cfgPath = Join-Path $Root 'emulationstation\.emulationstation\es_settings.cfg'
if (-not (Test-Path $cfgPath)) {
    Write-Host "ERROR: es_settings.cfg not found at $cfgPath" -ForegroundColor Red
    exit 1
}

# --- refuse to run while RetroBat is open ----------------------------------
$running = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui', 'azahar', 'cemu' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Write-Host "  RetroBat (or an emulator) is currently running." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Close it completely, then run this again." -ForegroundColor Yellow
    Write-Host "  (EmulationStation rewrites es_settings.cfg when it exits, so" -ForegroundColor Gray
    Write-Host "   any change made now would just be thrown away.)" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Say ""
Say "RetroBat found at: $Root" 'Cyan'
Say ""
# --- which switches are on -------------------------------------------------
#  Two of the things this script does are switchable in features.ini. Both
#  default to ON: if Features.ps1 or features.ini is missing or unreadable,
#  these stay $true and the script behaves exactly as it always has. Turning
#  one OFF does not merely stop reapplying it, it UNDOES it, because the
#  change is already sitting in RetroBat's own files and a switch that left
#  it there would look broken. See scripts\Features.ps1.
$featLaunchMenu      = $true
$featHideDecorations = $true

$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib

    # Safety net: if the file has been deleted, write a fresh one with every
    # switch on and all its comments. It is never overwritten when it exists.
    [void](New-FeaturesFile -Root $Root)

    $feat = Get-Features $Root
    $featLaunchMenu      = [bool]$feat['launchmenu']
    # 'fixed3dsframe' ON is the good setting and means KEEP the 3DS frame,
    # so hiding it is the other way round. The switch was renamed and turned
    # round on 2026-09-18 - see Get-FeatureCatalogue in Features.ps1.
    $featHideDecorations = -not [bool]$feat['fixed3dsframe']

    $offList = @($feat.Keys | Where-Object { -not $feat[$_] })
    if ($offList.Count -gt 0) {
        Say ("Switched off in features.ini: {0}" -f ($offList -join ', ')) 'Yellow'
        Say ""
    }
}


# --- machine profile: which computer is this, and what should it get -------
# Layer 1 (tier for the graphics card's strength) + layer 2 (brand rules for
# OpenGL/Vulkan/DirectX) + layer 3 (this machine's own pinned overrides),
# merged by ProfileEngine.ps1. On a computer the drive has never seen, this
# detects the GPU and creates the machine's profile automatically.
# If anything in the profile system fails, this script still applies the
# hand-kept lists above - the profile system is additive, never a dependency.
$MachineProfile = $null
try {
    . (Join-Path $PSScriptRoot 'ProfileEngine.ps1')
    $MachineProfile = Resolve-MachineProfile -Root $Root
}
catch {
    Say ("Machine settings skipped: {0}" -f $_.Exception.Message) 'Yellow'
}

$EffectiveSettings = $Settings
if ($null -ne $MachineProfile) {
    Say "Machine profile:" 'White'
    foreach ($m in $MachineProfile.Messages) { Say ("  {0}" -f $m) 'Yellow' }
    if ($MachineProfile.Ok) {
        $profLine = "  {0} on {1} ({2}) -> {3} tier, {4} setting(s)" -f `
            $MachineProfile.ProfileName, $MachineProfile.Machine, $MachineProfile.Gpu,
            $MachineProfile.Tier.ToUpper(), $MachineProfile.Settings.Count
        Say $profLine 'Cyan'

        # Profile settings first, then the hand-kept $Settings list on top.
        # If the same key ever turns up in both, the hand-kept list wins and
        # a note is printed - move it out of one of the two places.
        $EffectiveSettings = [ordered]@{}
        foreach ($k in $MachineProfile.Settings.Keys) {
            $EffectiveSettings[$k] = $MachineProfile.Settings[$k]
        }
        foreach ($k in $Settings.Keys) {
            if ($EffectiveSettings.Contains($k)) {
                Say ("  NOTE     {0} is set by the Machine tab AND by the list in this script - the script's value wins" -f $k) 'Yellow'
            }
            $EffectiveSettings[$k] = $Settings[$k]
        }
    }
    Say ""
}

# --- launch confirmation menu ----------------------------------------------
# The rules live in LaunchMenu.ps1 since 2026-10-12, shared with the wizard's
# PLAY button, which now checks this before every launch. Every emulator
# RetroBat knows gets the screen; the list above is the start.
$lmLib = Join-Path $PSScriptRoot 'LaunchMenu.ps1'
if (Test-Path -LiteralPath $lmLib) {
    . $lmLib
    $script:LaunchMenuBase = @($SaveStateMenuEmulators)
    Say "Launch confirmation menu:" 'White'
    $lm = Update-LaunchMenu -Root $Root -On $featLaunchMenu
    if (-not $lm.Ok) { Say ("  skipped: {0}" -f $lm.Message) 'Yellow' }
    else {
        foreach ($emu in @($lm.Added))   { Say ("  ADDED    {0,-16} will now show the launch menu" -f $emu) 'Green' }
        foreach ($emu in @($lm.Removed)) { Say ("  REMOVED  {0,-16} launches straight away now" -f $emu) 'Green' }
        if ($featLaunchMenu) { Say ("  ok       {0} emulators already had it" -f $lm.Already) 'DarkGray' }
        if ($lm.Backup -ne '') { Say ("  Backup: {0}" -f $lm.Backup) 'DarkGray' }
    }
    Say ""
}
else { Say "LaunchMenu.ps1 is missing - skipping the launch menu step." 'Yellow'; Say "" }

# --- emulator config files -------------------------------------------------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($EmulatorIniSettings.Count -gt 0) {
    Say "Emulator config files:" 'White'

    foreach ($relPath in $EmulatorIniSettings.Keys) {
        $iniPath = Join-Path $Root $relPath

        if (-not (Test-Path $iniPath)) {
            Say ("  SKIPPED  {0}" -f $relPath) 'Yellow'
            Say  "           (file not found - emulator may not be installed)" 'DarkGray'
            continue
        }

        Say ("  {0}" -f $relPath) 'Cyan'

        # Read as UTF-8 explicitly. Letting PowerShell guess can mangle any
        # non-English character in the file when it is written back out.
        $lines       = @([System.IO.File]::ReadAllLines($iniPath, $utf8NoBom))
        $fileChanged = $false

        foreach ($key in $EmulatorIniSettings[$relPath].Keys) {
            $wanted  = [string]$EmulatorIniSettings[$relPath][$key]
            $pattern = '^' + [regex]::Escape($key) + '='
            $found   = $false

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $pattern) {
                    $found = $true
                    if ($lines[$i] -ne "$key=$wanted") {
                        Say ("    CHANGED  {0,-22} : {1} -> {2}" -f $key, $lines[$i], $wanted) 'Yellow'
                        $lines[$i]   = "$key=$wanted"
                        $fileChanged = $true
                    }
                    else {
                        Say ("    ok       {0,-22} = {1}" -f $key, $wanted) 'DarkGray'
                    }
                }
            }

            if (-not $found) {
                Say ("    MISSING  {0,-22} (not in file - left alone)" -f $key) 'Yellow'
            }
        }

        if ($fileChanged) {
            $stampIni  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
            $backupIni = Join-Path $Root "_ClaudeWorkspace\archive\emuconfig_$stampIni"
            New-Item -ItemType Directory -Path $backupIni -Force | Out-Null
            Copy-Item $iniPath (Join-Path $backupIni (Split-Path $iniPath -Leaf)) -Force
            [System.IO.File]::WriteAllLines($iniPath, $lines, $utf8NoBom)
            Say ("    Backup: _ClaudeWorkspace\archive\emuconfig_{0}\" -f $stampIni) 'DarkGray'
        }
    }

    Say ""
}

# --- idle screen frames to suppress ----------------------------------------
if ($DecorationsToHide.Count -gt 0) {
    $decoRoot = Join-Path $Root 'system\decorations'
    $hiddenRoot = Join-Path $Root '_ClaudeWorkspace\archive\decorations-hidden'

    if (-not (Test-Path $decoRoot)) {
        Say "system\decorations not found - skipping idle screen frame step." 'Yellow'
        Say ""
    }
    elseif (-not $featHideDecorations) {
        # SWITCHED OFF. Put the frames back where RetroBat had them. The
        # parked copy in archive\decorations-hidden is the one that was moved
        # aside, so this is a real undo rather than a re-download.
        Say "Idle screen frames:" 'White'

        foreach ($rel in $DecorationsToHide) {
            $live   = Join-Path $decoRoot $rel
            $parked = Join-Path $hiddenRoot $rel

            if (Test-Path $live) {
                Say ("  ok       {0,-40} already back" -f $rel) 'DarkGray'
                continue
            }

            if (-not (Test-Path $parked)) {
                Say ("  MISSING  {0,-40} no parked copy to put back" -f $rel) 'Yellow'
                Say  "           a RetroBat update will supply a fresh one" 'DarkGray'
                continue
            }

            New-Item -ItemType Directory -Path (Split-Path $live -Parent) -Force | Out-Null
            Move-Item -LiteralPath $parked -Destination $live -Force
            Say ("  PUT BACK {0,-40} back on the idle screen" -f $rel) 'Green'
        }

        Say ""
    }
    else {
        Say "Idle screen frames:" 'White'

        foreach ($rel in $DecorationsToHide) {
            $src = Join-Path $decoRoot $rel

            if (-not (Test-Path $src)) {
                Say ("  ok       {0,-40} already out of the way" -f $rel) 'DarkGray'
                continue
            }

            $dst = Join-Path $hiddenRoot $rel
            New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null

            # If a copy is already parked there, this one is a fresh file put
            # back by an update. Keep the parked copy and overwrite it, so the
            # folder never grows a pile of near-identical files.
            Move-Item -LiteralPath $src -Destination $dst -Force
            Say ("  MOVED    {0,-40} out of the way" -f $rel) 'Green'
        }

        Say ""
    }
}

# --- close-the-emulator overrides (es_padtokey.cfg) ------------------------
if ($PadToKeyOverrides.Count -gt 0) {
    $p2kPath = Join-Path $Root 'emulationstation\.emulationstation\es_padtokey.cfg'

    if (-not (Test-Path $p2kPath)) {
        Say "es_padtokey.cfg not found - skipping close-button step." 'Yellow'
        Say ""
    }
    else {
        Say "Close-the-emulator buttons:" 'White'

        [xml]$p2kXml = Get-Content -LiteralPath $p2kPath -Raw
        $p2kRoot     = $p2kXml.SelectSingleNode('/padToKey')
        $p2kChanged  = 0

        if ($null -eq $p2kRoot) {
            Say "  ERROR: es_padtokey.cfg has no <padToKey> root - left alone." 'Red'
        }
        else {
            foreach ($appName in $PadToKeyOverrides.Keys) {
                $wantedKey = [string]$PadToKeyOverrides[$appName]
                $appNode   = $p2kRoot.SelectSingleNode("app[@name='$appName']")

                if ($null -eq $appNode) {
                    Say ("  SKIPPED  {0,-16} (no entry in es_padtokey.cfg)" -f $appName) 'Yellow'
                    continue
                }

                $inputNode = $appNode.SelectSingleNode("input[@name='hotkey start']")

                if ($null -eq $inputNode) {
                    $inputNode = $p2kXml.CreateElement('input')
                    $inputNode.SetAttribute('name', 'hotkey start')
                    $inputNode.SetAttribute('key',  $wantedKey)
                    [void]$appNode.AppendChild($inputNode)
                    Say ("  ADDED    {0,-16} Select+Start -> {1}" -f $appName, $wantedKey) 'Green'
                    $p2kChanged++
                }
                elseif ($inputNode.GetAttribute('key') -ne $wantedKey) {
                    $oldKey = $inputNode.GetAttribute('key')
                    $inputNode.SetAttribute('key', $wantedKey)
                    $inputNode.RemoveAttribute('code')
                    Say ("  CHANGED  {0,-16} Select+Start : {1} -> {2}" -f $appName, $oldKey, $wantedKey) 'Yellow'
                    $p2kChanged++
                }
                else {
                    Say ("  ok       {0,-16} Select+Start = {1}" -f $appName, $wantedKey) 'DarkGray'
                }
            }
        }

        if ($p2kChanged -gt 0) {
            $stampP2K  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
            $backupP2K = Join-Path $Root "_ClaudeWorkspace\archive\padtokey_$stampP2K"
            New-Item -ItemType Directory -Path $backupP2K -Force | Out-Null
            Copy-Item $p2kPath (Join-Path $backupP2K 'es_padtokey.cfg') -Force

            $p2kSet             = New-Object System.Xml.XmlWriterSettings
            $p2kSet.Indent      = $true
            $p2kSet.IndentChars = "    "
            $p2kSet.Encoding    = New-Object System.Text.UTF8Encoding($false)

            $p2kWriter = [System.Xml.XmlWriter]::Create($p2kPath, $p2kSet)
            try   { $p2kXml.Save($p2kWriter) }
            finally { $p2kWriter.Close() }

            Say ("  Backup: _ClaudeWorkspace\archive\padtokey_{0}\" -f $stampP2K) 'DarkGray'
        }

        Say ""
    }
}

# --- snapshot helper for the health check ----------------------------------
# Saves exactly what this run applied (machine\last-applied.json). The
# health check compares es_settings.cfg against this snapshot, so it can
# spot anything an update or a menu visit reverted - without keeping a
# second copy of the lists anywhere.
function Save-AppliedSnapshot {
    try {
        $snapDir = Join-Path $Root '_ClaudeWorkspace\machine'
        if (-not (Test-Path -LiteralPath $snapDir)) {
            New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
        }
        $strings = [ordered]@{}
        foreach ($k in $EffectiveSettings.Keys) { $strings[$k] = [string]$EffectiveSettings[$k] }
        $bools = [ordered]@{}
        foreach ($k in $BoolSettings.Keys) { $bools[$k] = ([string]$BoolSettings[$k]).ToLower() }
        $games = [ordered]@{}
        foreach ($k in $WantedGameSettings.Keys) { $games[$k] = [string]$WantedGameSettings[$k] }
        $snap = [ordered]@{
            applied = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            machine = [string]$env:COMPUTERNAME
            strings = $strings
            bools   = $bools
            removed = @($RemoveSettings)
            # The keys EmulationStation strips because they are its own
            # default. The health check reads this instead of holding its
            # own copy of the list - see $EsOwnDefaults at the top.
            esdefaults = @($EsOwnDefaults)
            # The per-game settings THIS DRIVE wrote. The next run reads this
            # to know which ones are its own to take away again, so a setting
            # somebody made by hand in RetroBat's menus is never disturbed.
            games = $games
        }
        $json = $snap | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText((Join-Path $snapDir 'last-applied.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        Say ("  (could not save the settings snapshot: {0})" -f $_.Exception.Message) 'Yellow'
    }
}

# --- apply (in memory first - nothing is written unless something changed) --
# ===========================================================================
#  SETTINGS FOR ONE GAME                              (added 2026-09-18)
# ===========================================================================
#  RetroBat can hold a setting for a single game as well as for a whole
#  console. It stores them in es_settings.cfg under a name shaped like
#
#      wiiu["Mario Kart 8 (USA) (En,Fr,Es) (Rev 5).wux"].use_wiimotes
#
#  Ten of those were set by hand from RetroBat's own menus and were written
#  down in docs\PER-GAME-SETTINGS.md because nothing else on the drive knew
#  about them. Now the machine profiles do: a [game-settings] section holds
#  them per profile, which is what makes "this game runs lower on the
#  laptop" possible without touching the tower.
#
#  THE PROFILE WRITES THE INNER QUOTES, NOT THE PERSON. In the profile the
#  key reads wiiu[Mario Kart 8 ... .wux].use_wiimotes, with no quotes around
#  the file name, because that is what somebody can type and read. The
#  quotes EmulationStation wants are added here.
#
#  XPATH IS NOT USED FOR THESE, and that is not fussiness. A game called
#  "Yoshi's Woolly World" puts an apostrophe in the key, and an XPath
#  predicate written as [@name='...'] cannot hold one - the query does not
#  fail, it throws. Every lookup below walks the child nodes and compares
#  the attribute directly, which cannot be confused by any character.
# ---------------------------------------------------------------------------
function ConvertTo-GameSettingName([string]$Key) {
    # wiiu[Some Game.wux].setting  ->  wiiu["Some Game.wux"].setting
    $open  = $Key.IndexOf('[')
    $close = $Key.LastIndexOf(']')
    if ($open -lt 1 -or $close -lt $open) { return '' }
    $console = $Key.Substring(0, $open)
    $game    = $Key.Substring($open + 1, $close - $open - 1)
    $rest    = $Key.Substring($close + 1)
    if (-not $rest.StartsWith('.') -or $rest.Length -lt 2) { return '' }
    if ($game.StartsWith('"') -and $game.EndsWith('"')) { $game = $game.Substring(1, $game.Length - 2) }
    if ($console -eq '' -or $game -eq '') { return '' }
    return ('{0}["{1}"]{2}' -f $console, $game, $rest)
}

function Find-SettingNode($Parent, [string]$Name, [string]$Tag = '') {
    foreach ($n in @($Parent.ChildNodes)) {
        if ($n.NodeType -ne 'Element') { continue }
        if ($Tag -ne '' -and $n.get_Name() -ne $Tag) { continue }
        if ($n.GetAttribute('name') -eq $Name) { return $n }
    }
    return $null
}

# What this profile wants, keyed by the name EmulationStation stores.
$WantedGameSettings = [ordered]@{}
if ($null -ne $MachineProfile -and $MachineProfile.GameSettings) {
    foreach ($k in $MachineProfile.GameSettings.Keys) {
        $full = ConvertTo-GameSettingName ([string]$k)
        if ($full -eq '') {
            Say ("  SKIPPED  per-game line '{0}' is not shaped like console[game file].setting" -f $k) 'Red'
            continue
        }
        $WantedGameSettings[$full] = [string]$MachineProfile.GameSettings[$k]
    }
}

# What the LAST run wrote, so a setting dropped from the profile - or a
# profile switched away from - actually goes away again. Only ever keys this
# drive wrote itself: a per-game setting made by hand in RetroBat's own menus
# and never put in a profile is not ours and is never touched.
$PreviousGameSettings = @()
try {
    $snapPrev = Join-Path $Root '_ClaudeWorkspace\machine\last-applied.json'
    if (Test-Path -LiteralPath $snapPrev) {
        $sp = Get-Content -LiteralPath $snapPrev -Raw | ConvertFrom-Json
        if ($sp.PSObject.Properties.Name -contains 'games' -and $null -ne $sp.games) {
            $PreviousGameSettings = @($sp.games.PSObject.Properties.Name)
        }
    }
}
catch { }

[xml]$xml = Get-Content -LiteralPath $cfgPath -Raw
$config = $xml.SelectSingleNode('/config')
if (-not $config) { Write-Host "ERROR: es_settings.cfg has no <config> root." -ForegroundColor Red; exit 1 }

$changed = 0
$already = 0

foreach ($name in $EffectiveSettings.Keys) {
    $wanted = [string]$EffectiveSettings[$name]

    # Values here are all written as <string> entries, which is what
    # EmulationStation uses for these particular settings.
    $node = $config.SelectSingleNode("string[@name='$name']")

    if ($null -eq $node) {
        $node = $xml.CreateElement('string')
        $node.SetAttribute('name', $name)
        $node.SetAttribute('value', $wanted)
        [void]$config.AppendChild($node)
        Say ("  ADDED    {0,-32} = {1}" -f $name, $wanted) 'Green'
        $changed++
    }
    elseif ($node.GetAttribute('value') -ne $wanted) {
        $old = $node.GetAttribute('value')
        $node.SetAttribute('value', $wanted)
        Say ("  CHANGED  {0,-32} : {1} -> {2}" -f $name, $old, $wanted) 'Yellow'
        $changed++
    }
    else {
        Say ("  ok       {0,-32} = {1}" -f $name, $wanted) 'DarkGray'
        $already++
    }
}

foreach ($name in $BoolSettings.Keys) {
    $wanted = ([string]$BoolSettings[$name]).ToLower()

    if ($wanted -ne 'true' -and $wanted -ne 'false') {
        Say ("  SKIPPED  {0,-32} (value must be true or false, got '{1}')" -f $name, $wanted) 'Red'
        continue
    }

    # These live as <bool> lines. If an old <string> line with the same name
    # is lying around it would confuse things, so clear it out first.
    foreach ($stray in @($config.SelectNodes("string[@name='$name']"))) {
        [void]$config.RemoveChild($stray)
        Say ("  CLEANED  {0,-32} (removed a wrong-type entry)" -f $name) 'Magenta'
        $changed++
    }

    $node = $config.SelectSingleNode("bool[@name='$name']")

    if ($null -eq $node) {
        $node = $xml.CreateElement('bool')
        $node.SetAttribute('name', $name)
        $node.SetAttribute('value', $wanted)
        [void]$config.AppendChild($node)
        Say ("  ADDED    {0,-32} = {1}" -f $name, $wanted) 'Green'
        $changed++
    }
    elseif ($node.GetAttribute('value') -ne $wanted) {
        $old = $node.GetAttribute('value')
        $node.SetAttribute('value', $wanted)
        Say ("  CHANGED  {0,-32} : {1} -> {2}" -f $name, $old, $wanted) 'Yellow'
        $changed++
    }
    else {
        Say ("  ok       {0,-32} = {1}" -f $name, $wanted) 'DarkGray'
        $already++
    }
}

foreach ($name in $RemoveSettings) {
    # A key can be stored as <string>, <bool> or <int>, so check all three.
    $nodes = @($config.SelectNodes("*[@name='$name']"))

    if ($nodes.Count -eq 0) {
        Say ("  ok       {0,-32} (absent, as it should be)" -f $name) 'DarkGray'
        $already++
    }
    else {
        foreach ($n in $nodes) {
            $old = $n.GetAttribute('value')
            [void]$config.RemoveChild($n)
            Say ("  REMOVED  {0,-32} (was {1})" -f $name, $old) 'Magenta'
            $changed++
        }
    }
}

# --- settings for one game -------------------------------------------------
foreach ($name in $WantedGameSettings.Keys) {
    $wanted = [string]$WantedGameSettings[$name]
    $node = Find-SettingNode $config $name 'string'
    if ($null -eq $node) {
        $node = $xml.CreateElement('string')
        $node.SetAttribute('name', $name)
        $node.SetAttribute('value', $wanted)
        [void]$config.AppendChild($node)
        Say ("  ADDED    {0} = {1}" -f $name, $wanted) 'Green'
        $changed++
    }
    elseif ($node.GetAttribute('value') -ne $wanted) {
        $old = $node.GetAttribute('value')
        $node.SetAttribute('value', $wanted)
        Say ("  CHANGED  {0} : {1} -> {2}" -f $name, $old, $wanted) 'Yellow'
        $changed++
    }
    else {
        Say ("  ok       {0} = {1}" -f $name, $wanted) 'DarkGray'
        $already++
    }
}

# Anything THIS DRIVE wrote last time and does not want now. That is what
# makes switching profiles mean something: the tower's per-game settings
# stop applying when the laptop's profile takes over.
foreach ($name in $PreviousGameSettings) {
    if ($WantedGameSettings.Contains($name)) { continue }
    $node = Find-SettingNode $config $name 'string'
    if ($null -eq $node) { continue }
    $old = $node.GetAttribute('value')
    [void]$config.RemoveChild($node)
    Say ("  REMOVED  {0} (was {1}, not in this profile)" -f $name, $old) 'Magenta'
    $changed++
}

if ($changed -eq 0) {
    if ($null -ne $MachineProfile) { Write-ActiveProfile -Root $Root -MachineProfile $MachineProfile }
    Save-AppliedSnapshot
    Say ""
    Say "Nothing to change - everything was already set." 'Green'
    Say ""
    exit 0
}

# --- back up only now, because we know we are actually changing something --
$stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $Root "_ClaudeWorkspace\archive\settings_$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item $cfgPath (Join-Path $backupDir 'es_settings.cfg') -Force
Say ""
Say "Backup saved: _ClaudeWorkspace\archive\settings_$stamp\es_settings.cfg" 'DarkGray'
Say "  (to undo everything, copy that file back over the original)" 'DarkGray'

# --- save, keeping the tab-indented layout EmulationStation writes ---------
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.IndentChars = "`t"
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)

$writer = [System.Xml.XmlWriter]::Create($cfgPath, $settings)
try   { $xml.Save($writer) }
finally { $writer.Close() }

# remember which profile is now applied (read by people and, later, by the
# health check)
if ($null -ne $MachineProfile) { Write-ActiveProfile -Root $Root -MachineProfile $MachineProfile }
Save-AppliedSnapshot

Say ""
Say "$changed setting(s) written, $already already correct." 'Cyan'
Say ""
Say "Start RetroBat and check:" 'White'
Say "  3DS  - both screens now stacked top over bottom, both readable." 'Gray'
Say "         Sharper, and should run better than before." 'Gray'
Say "  DS   - Select+Start should close it first try now." 'Gray'
Say "  Wii  - real Wii Remotes become players 1-4 in the order you" 'Gray'
Say "         switch them on. Wired pads act as GameCube controllers." 'Gray'
Say "  WiiU - Select+Start now force-closes Cemu, which is the only" 'Gray'
Say "         thing that reliably works there." 'Gray'
Say "  Idle - clock is 12-hour, videos have sound and fade in, console" 'Gray'
Say "         frames on everything except 3DS." 'Gray'
Say ""
