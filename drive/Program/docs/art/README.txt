===========================================================================
 Where the wizard's pixel pictures come from
===========================================================================

NOTHING ON THE DRIVE RUNS ANY OF THIS. The wizard reads the finished .png
files in _Wizard\Program\wizard\ and never looks in here, so deleting this
whole folder breaks nothing. It is kept only so the art can be changed later
without redrawing from scratch.

To rebuild the pictures you need Python and Pillow, neither of which is on
the drive:

    pip install pillow
    python build.py

The four files:

    pal.py      the colours, by name. Change a colour here and every
                picture that uses it changes.
    kit.py      the drawing toolkit: ellipses, rings, outlines, sparkles,
                directional shading. No pictures in here.
    pieces.py   the pictures themselves, one function each, drawn twice -
                small for the tab strip and bigger for the page corner.
    build.py    renders them all into an output folder.

    wizard_art-v1.py   the first version, from 2026-09-07, kept for
                       reference. It drew everything as text grids, one
                       character per pixel. Not used any more.

THE TWO RULES THE WIZARD ENFORCES, so keep to them if you redraw:

 1. A tab picture must stay SMALL, roughly 20 to 30 pixels. It sits in the
    tab strip next to the word.

 2. An animation strip (page-<name>-anim.png) must be exactly the same
    WIDTH as its still picture, and a whole number of frames tall. The
    wizard works the frame count out by dividing, so if that does not come
    out whole it gives up and shows the still picture instead. That is the
    right answer, not a bug.

 3. lights.png must be four square frames side by side, in this order:
    ok, warn, bad, unknown. So the file has to be exactly four times as
    wide as it is high.

Every loop closes on itself. Nothing may be random per frame or the
animation would jump when it wraps around.

===========================================================================
 The controller pictures                            (added 2026-09-18)
===========================================================================

    controllers-source.png   the four controllers Steven supplied, redrawn
                             onto their own pixel grid: NES, SNES, N64 and
                             GameCube, top left to bottom right. 126 x 92.

build.py does NOT make these - they came from a picture rather than from
code, which is why the source is kept here beside the others. They were cut
out of it with Pillow, each one trimmed to its own edges:

    wizard\controllers.png        the GameCube pad, 46 x 37. The Play tab's
                                  controller button, and nothing else
    wizard\controllers.ico        the same, at 16 / 24 / 32 / 48 / 64 / 128
                                  / 256, for the Controllers shortcut this
                                  drive writes onto a computer. Sizes at or
                                  above 46px are whole-number scales so the
                                  pixels stay square; the two smaller ones
                                  are resampled, because a 16px icon cannot
                                  be anything else
    wizard\profile-nes.png        one per controller, for the little picture
    wizard\profile-snes.png       beside each profile on the Profiles tab.
    wizard\profile-n64.png        Which profile wears which is worked out
    wizard\profile-gamecube.png   from its name - see Get-ProfileIcon in
                                  scripts\ProfileEngine.ps1

To add more, put a picture at wizard\profile-<name>.png and add <name> to
$script:ProfileIcons in ProfileEngine.ps1. A profile with an icon the wizard
has no picture for simply shows no picture, like every other picture here.

===========================================================================
 The status lights changed colour on 2026-09-18
===========================================================================

The OK gem was a yellow-green, borrowed from the cauldron's brew. It is now
its own colour, 'okg' in pal.py, which is exactly the Play button's green and
exactly the plain coloured dot the wizard falls back to when lights.png is
missing. The other three frames are byte-for-byte what they were.

===========================================================================
 Nine more profile pictures                         (added 2026-09-18)
===========================================================================

    wizard\profile-pc.png            a desktop tower, monitor and keyboard
    wizard\profile-laptop.png        a laptop
    wizard\profile-brokenlaptop.png  a laptop on fire, for the one that is
    wizard\profile-monitor.png       a monitor on its own
    wizard\profile-gameboy.png       Game Boy
    wizard\profile-gba.png           Game Boy Advance
    wizard\profile-ds.png            DS
    wizard\profile-switch.png        a pair of Joy-Cons
    wizard\profile-wiimote.png       a Wii Remote

Cut out of pictures Steven supplied, one per file, not from build.py. The
backgrounds were removed by FLOODING INWARDS FROM THE EDGES rather than by
picking a colour to delete - a white key in the middle of a keyboard is the
same white as the background behind the whole picture, and a colour-based
removal eats it. Then trimmed to their own edges and brought down to about
forty pixels tall.

The Wii one is the Remote ALONE. The original had the nunchuk beside it, and
at icon size the pair came out about fifteen pixels each, which is not a
picture of anything.

WHICH PICTURE A PROFILE WEARS. A profile with no 'icon =' line picks one by
itself from its NAME, and only from the four controllers - see
$script:ProfileIcons in scripts\ProfileEngine.ps1. Everything above is
offered when somebody presses Rename on a profile and chooses one on
purpose: $script:ProfileIconChoices, in the same file. Adding another is a
.png in wizard\ and a line in that list. A name with no picture simply shows
no picture, like every other picture in this window.

===========================================================================
 The moving pictures were redrawn                   (added 2026-09-23)
===========================================================================

    motion.py   draws every MOVING picture now: the five page-*-anim.png
                strips and the mage on the Play tab (mage.png and
                mage-anim.png). build.py still draws the tab pictures and
                the status lights, and its page drawings are no longer the
                ones on the drive.

        pip install pillow
        python motion.py            everything, into .\out
        python motion.py mage       just one (page-health, mage, ...)

WHAT CHANGED. The wizard's clock went from 8 frames a second to 20, and the
strips went from 6-10 frames to 120 (160 for the mage). Each page picture
now has small idle motion all the time plus one bigger moment per six
second loop: the blue cork pops, the crystal ball flares, the chest lid
bumps open and coins hop out, the cauldron bloops and splashes, a page of
the book turns. The mage floats, blinks, glows and casts a spell once every
eight seconds. The rules above still hold - same width as the still, a
whole number of frames tall - except that a strip may now be up to 400
frames. The old pictures are in archive\wizard-anim-revamp_2026-09-23.

===========================================================================
 The four newer tabs                                (added 2026-10-11)
===========================================================================

    motion2.py          Profile, Games, Netplay and Admin: the four page
                        pictures (moving) and their tab pictures. Borrows
                        motion.py's helpers. python motion2.py
    hat-source.png      Steven's blue wizard hat, put back onto its own
                        25 x 22 grid, six colours. motion2.py draws the
                        Profile pictures FROM it (the tab is this file as
                        it is) and moves its tail.
    sword-source.png    Steven's sword, 11 x 48, five colours. The Admin
                        page picture is this with gold flames round it.

Redraw either source in any pixel editor and run motion2.py again; the
animations follow. The hat's moving tail is the pixels left of column 7,
rows 3 to 8 - keep the tail there if you redraw it.

===========================================================================
 The v3 icons and the new wordmark                   (added 2026-10-14)
===========================================================================

    icons3.py           the 32 x 32 icon set for the rail, the Home tiles and
                        the Settings tiles: chest (Games), crystal ball
                        (Social), mirror (Play online), potions (Saves), gold
                        gears (Settings), book (Help), hearts (Health), floppy
                        (This drive), key (Admin), controller (Controllers).
                        Each is wizard\icon-<name>.png plus a 60-frame
                        icon-<name>-anim.png (3 seconds at 20 a second).
                        Frame 0 of each strip IS the still.
                        python icons3.py            all of them, into .\out
                        python icons3.py gears      just one
    pad-source.png      Steven's Xbox-style controller picture. The
                        controller icon is drawn from it, and
                        wizard\pro-controller.png (the Wii U chooser) is it,
                        recoloured.
    wordmark3.py        "THE RETROBAT WIZARD" with fire that rises.
                        python wordmark3.py wordmark-v2-source.png out
    wordmark-v2-source.png  the older two-line wordmark it reads the pixel
                        font from (one font pixel = 3 x 3 screen pixels).

The wizard decides when icons move: the rail's current page all the time,
the Home and Settings tiles one or two at a time every 5 to 10 seconds.
