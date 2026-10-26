# Per-game settings on this drive

**Rewritten 2026-09-18.** This used to be the only record of ten settings that
existed nowhere but inside `es_settings.cfg`. They are now held by the drive
itself and put back automatically, so this file explains the system rather than
being the backup for it.

## The idea

RetroBat can hold a setting for ONE game rather than a whole console. It stores
them in

```
emulationstation\.emulationstation\es_settings.cfg
```

under a name shaped like

```
wiiu["Mario Kart 8 (USA) (En,Fr,Es) (Rev 5).wux"].use_wiimotes
```

EmulationStation keeps them when it rewrites that file, so they are not in daily
danger - but if `es_settings.cfg` were lost or reset there was nothing to put
them back from. Now there is.

## The two places one can live, and how to choose

Both are plain text and both are read by `Apply-Settings.ps1`.

### `_Wizard\profiles\game-settings.ini` - the whole drive

For settings that are about the **room**, not the computer. Which controller a
game expects is the same answer at home and at a friend's house, so it belongs
to the drive and applies under every profile.

### A profile's own `[game-settings]` section - one profile

For settings about how hard **this computer** has to work. "Breath of the Wild
at 720p" is true of a laptop and wrong for the tower, so it lives in whichever
profile it is true for and stops applying when another profile is chosen.

A profile's line **wins** over the shared file, so one machine can disagree
about one game without editing the shared file.

## How a line is written

```
console[the game's file name].setting = value
```

The file name is the rom exactly as it sits in `roms\<console>\`, **with** its
extension and **without** quotes around it. `Apply-Settings.ps1` adds the quotes
EmulationStation wants. Writing them by hand in the ini would be one more thing
to get wrong, and the file is meant to be readable.

## The easy way: the wizard

**Profiles tab -> Advanced -> One game at a time.** Pick a console, pick a game
out of RetroBat's own game list, and every setting that console offers appears
with the choices RetroBat itself describes. Press Apply changes. It writes into
the profile, so it is a per-computer choice.

Only **Wii, Wii U, DS and 3DS** are offered. Those are the heavy ones where a
single game can be the problem. Another console is one entry in
`$script:GameSettingConsoles` in `SetupWizard.ps1`, and nothing else.

## The hard way, and how to find a setting's name

Highlight the game in RetroBat, press **Select** for GAME OPTIONS, then
**ADVANCED GAME OPTIONS**. Everything RetroBat can set for a whole console can be
set for one game from there, and it is stored back into `es_settings.cfg` in the
shape above - where you can read the exact name and copy it into an ini.

## What is set today

All of it lives in `profiles\game-settings.ini`, because all of it is about
controllers. Eleven lines, imported from `es_settings.cfg` on 2026-09-18.

### Nine Wii U games set to use four REAL Wii Remotes

`use_wiimotes = 4`

- Donkey Kong Country - Tropical Freeze
- LEGO Batman 2: DC Super Heroes
- LEGO Marvel Super Heroes
- Mario Kart 8
- New Super Mario Bros. U
- Rayman Legends
- Super Mario 3D World
- Super Smash Bros. for Wii U
- Yoshi's Woolly World

Every one is a same-couch multiplayer game. **This is the "use Wii Remotes for
multiplayer" idea, done by hand one game at a time.** RetroBat's own description
warns that with real Wiimotes on, other controllers will not work in that game -
which is exactly why it is right per game and would be wrong per console.

The DolphinBar has to be in **mode 4** for any of this.

### Two Wii U games set to a Pro Controller

`cemu_controllerp0 = procontroller`

- **Zelda.rpx**, which is Twilight Princess HD
- **Call of Duty - Black Ops II**

Both single player, no motion needed - the other half of the same idea. Black
Ops II was **not** in the old version of this file; it was found during the
2026-09-18 import, which is the point of having the drive hold these rather than
a document.

## How they are kept honest

- `Apply-Settings.ps1` writes them on every run and records what it wrote into
  `profiles\last-applied.json`.
- Anything it wrote **last** time and does not want **this** time is removed
  again. That is what makes switching profiles mean something.
- A per-game setting made by hand in RetroBat's menus and never written into an
  ini is **not ours** and is never touched.
- The health check compares them against the file and lights up if one has gone.

**None of this uses XPath**, and that is not fussiness. `Yoshi's Woolly World`
puts an apostrophe in the key, and an apostrophe inside an XPath `[@name='...']`
predicate does not fail to match - it throws. Every lookup walks the child nodes
and compares the attribute directly. There is a test that proves the XPath
version would have thrown.

## The one people ask for: a second GamePad window

**It is a setting, not something that needs building.**

```
SEPARATE GAMEPAD VIEW      ->   cemu_open_pad
    ADVANCED SETTINGS, submenu USER INTERFACE
    "Opens a second window for the Gamepad view."
    a three-way switch: auto / on / off
```

RetroBat's Cemu launcher writes it into Cemu's own `settings.xml` at every
launch, so it takes effect immediately and nothing has to be edited by hand. Set
it per game on the handful of Wii U games that genuinely want a second screen.
Leave it alone everywhere else.
