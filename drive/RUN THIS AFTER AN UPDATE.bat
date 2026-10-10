@echo off
REM ---------------------------------------------------------------------------
REM  THE ONE BUTTON TO PRESS AFTER A RETROBAT OR EMULATOR UPDATE.
REM
REM  An update replaces RetroBat's own files and throws away anything custom
REM  sitting in them. This runs every repair step, in the order they need to
REM  happen, so you do not have to remember which ones matter:
REM
REM    1  Restore protected files  - the reworded menus, the loading screen
REM                                  videos, and the Wii System Menu wrapper
REM    2  Fix drive letters        - repairs paths an update overwrote
REM    3  Apply settings           - puts your known-good settings back
REM    4  Restore theme            - the Zelda and Pokemon collection artwork
REM    5  Unpack new 3DS ROMs      - only acts if there is something new
REM    6  Fix video volume         - only acts on videos it has not seen before
REM
REM  Step 1 has to come before step 2: fixing the Wii launch command is
REM  skipped if the wrapper script it points at is not there yet.
REM
REM  Each step still lives in its own file under "Maintenance Steps" and can
REM  still be run on its own if something goes wrong and you want to look at
REM  just that one.
REM
REM  RETROBAT AND ALL EMULATORS MUST BE CLOSED. Every step checks and will
REM  stop on its own rather than make a mess.
REM
REM  To add a future step, copy one of the blocks below and change the name.
REM ---------------------------------------------------------------------------
title RetroBat - Run After An Update
setlocal

set "PS=%~dp0scripts\"

echo.
echo ===========================================================================
echo   RETROBAT MAINTENANCE - running every repair step in order
echo ===========================================================================
echo.
echo   Make sure RetroBat, Azahar, Cemu and Dolphin are all closed.
echo.
pause
echo.

REM --- step 1 of 6 -----------------------------------------------------------
echo ---------------------------------------------------------------------------
echo   STEP 1 of 6   Restoring files an update would have wiped
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Restore-ProtectedFiles.ps1'"
if errorlevel 1 goto :failed
echo.

REM --- step 2 of 6 -----------------------------------------------------------
echo ---------------------------------------------------------------------------
echo   STEP 2 of 6   Fixing drive letters
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Fix-Portability.ps1'"
if errorlevel 1 goto :failed
echo.

REM --- step 3 of 6 -----------------------------------------------------------
echo ---------------------------------------------------------------------------
echo   STEP 3 of 6   Applying saved settings
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Apply-Settings.ps1'"
if errorlevel 1 goto :failed
echo.

REM --- step 4 of 6 -----------------------------------------------------------
REM  This one returns 2 when it finishes with warnings, which is not a failure.
echo ---------------------------------------------------------------------------
echo   STEP 4 of 6   Restoring the collection theme artwork
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Restore-CkauBookTheme.ps1'"
REM  errorlevel checks are "this or higher", so these have to run biggest first.
REM  2 means "finished, but read the warnings" - not a reason to stop.
if errorlevel 3 goto :failed
if errorlevel 2 goto :themeok
if errorlevel 1 goto :failed
:themeok
echo.

REM --- step 5 of 6 -----------------------------------------------------------
echo ---------------------------------------------------------------------------
echo   STEP 5 of 6   Unpacking any new 3DS ROMs
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Decompress-3DS.ps1'"
if errorlevel 1 goto :failed
echo.

REM --- step 6 of 6 -----------------------------------------------------------
echo ---------------------------------------------------------------------------
echo   STEP 6 of 6   Checking video volumes
echo ---------------------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%Fix-VideoVolume.ps1'"
if errorlevel 1 goto :failed
echo.

echo ===========================================================================
echo   ALL DONE. Everything above finished without stopping.
echo ===========================================================================
echo.
pause
exit /b 0

:failed
echo.
echo ===========================================================================
echo   A STEP STOPPED EARLY.
echo.
echo   Read the message above it. The usual cause is RetroBat or an emulator
echo   still being open. Close everything and run this again.
echo.
echo   Nothing is broken - each script backs up before it changes anything,
echo   and refuses to run rather than half-finish.
echo ===========================================================================
echo.
pause
exit /b 1
