WHAT THIS FOLDER IS
===================

(Renamed from profiles\ on 2026-10-10. "Profile" now means the PERSON
using the drive. This folder is about the COMPUTER, and its tab in the
wizard is called Machine.)

This drive moves between computers, and a weak laptop and a strong tower
should not run the emulators with the same picture settings. This folder is
how the drive adapts by itself.

When "Apply My Settings" runs (on its own or as step 3 of RUN THIS AFTER AN
UPDATE), it works out which computer it is on, picks the right settings for
it, and writes them. On a computer it has never seen, it detects the graphics
card, picks Low, Medium or High from a lookup table, and creates a file
for that machine automatically. Nothing to set up.

Four layers, each beating the one before it:

  1. TIER          tiers\low.ini / medium.ini / high.ini
                   How strong the graphics card is. Shared by all machines.
  2. CONSOLE TIER  machines\<COMPUTER>.ini, the [console-tiers] section
                   One console running at a different tier from the rest of
                   the machine. For when everything is fine except one
                   emulator. One line: "wii = low".
  3. BRAND RULES   rules\vendor-rules.ini
                   OpenGL vs Vulkan vs DirectX depends on the card's BRAND,
                   not its strength, so it beats both tiers above.
  4. OVERRIDES     machines\<COMPUTER>.ini, the [overrides] section
                   Individual settings pinned for one machine only.

Reach for layer 2 before layer 4. Dropping one console a tier is one readable
line, and that console keeps improving whenever that tier file improves.
Pinning individual settings freezes them forever, which is sometimes what you
want and usually is not.

WHAT IS IN HERE
===============

  tiers\           the three base tiers. Editing one changes every machine
                   on that tier (except pinned settings).
  rules\           gpu-table.txt   = card name -> tier lookup
                   vendor-rules.ini = graphics backend per brand
  machines\        one small file per computer this drive has met
  active.txt       which machine was applied last, written automatically

COMMON JOBS
===========

  See what this computer would get ...... Maintenance Steps\Show My Machine.bat
                                          (read-only, changes nothing)
  One console stutters on one machine ... add a line under [console-tiers] in
                                          machines\<COMPUTER>.ini, such as
                                          "wii = low", then run Apply My
                                          Settings. Try this FIRST
  Change one setting on one machine ..... add a line under [overrides] in
                                          machines\<COMPUTER>.ini, then run
                                          Apply My Settings
  Move a machine to another tier ........ change its "tier =" line, then run
                                          Apply My Settings
  Wrong tier picked for a new PC ........ same fix - change the tier line
  A machine you no longer use ........... just delete its file in machines\

Only these six consoles are managed here: GameCube, Wii, Wii U, 3DS, DS, N64.
Everything older runs at full speed on any computer, so those systems are
deliberately left alone.
