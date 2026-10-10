===========================================================================
 What this folder is
===========================================================================

The master copy of everything that belongs at the TOP of the drive, one
level above the RetroBat folder.

    SETUP RETROBAT.bat     press once on a new computer

WHY A MASTER COPY AND NOT JUST THE FILE. Everything else this drive protects
lives inside the RetroBat folder, and update-restore\ puts it back if a
RetroBat update wipes it. The drive root is one level ABOVE that, so nothing
was watching it. Update-RootFiles in scripts\Shortcuts.ps1 watches it now:
every time the wizard runs, in any mode, it compares the file at the top of
the drive against the copy in here and repairs it if it is missing or
different.

WHAT THAT MEANS IN PRACTICE. You cannot lose the SETUP RETROBAT button. Drag
it to the bin and the next launch puts it back. Copy this whole drive onto a
new drive and the new one grows its own copy the first time it is used.

IT ONLY EVER ADDS. If the button is MISSING from the top of the drive it is
put back. If a file of that name is already there it is left completely
alone, even if it differs - somebody may have edited it on purpose, and
nothing on this drive overwrites or deletes anything. A file at the top of
the drive that is not named in here is never touched at all.

This README is skipped by name and is never copied up.

===========================================================================
 If you are reading this because the button is missing
===========================================================================

Copy "SETUP RETROBAT.bat" from this folder to the top of the drive, beside
the RetroBat folder. That is all. Or just run PLAY.bat once and it puts
itself back.
