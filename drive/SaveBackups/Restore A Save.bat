@echo off
setlocal enabledelayedexpansion
REM ---------------------------------------------------------------------------
REM  Find an old version of a save file and put it back.
REM  Type a game name, pick a date from the list, done.
REM ---------------------------------------------------------------------------
title RetroBat - Restore a Save

set "PS=%~dp0..\scripts\Restore-RetroBatSave.ps1"

:search
cls
echo.
echo ===========================================================================
echo   RESTORE A SAVE
echo ===========================================================================
echo.
echo   Type part of a game name, for example:  zelda
echo.
echo   Or type a SYSTEM name to see everything for it:
echo      gamecube   n64   gba   gbc   nds   wii   3ds   psp
echo.
echo ---------------------------------------------------------------------------
echo   IMPORTANT - WII AND 3DS
echo ---------------------------------------------------------------------------
echo   Those two systems split ONE game's save across SEVERAL files.
echo   Restoring only one of them will NOT work and can leave the save broken.
echo   Restore every file listed for that game, all from the SAME date/time.
echo   Everything else (GameCube, N64, DS, GBA, GBC) is one file per game.
echo ---------------------------------------------------------------------------
echo.
echo   GameCube and Wii saves are named by Nintendo game code, not game name.
echo   Shortcuts for kirby / strikers / star fox already work. To add more,
echo   edit game-name-shortcuts.txt in this folder - it explains how.
echo.
echo   Leave blank and press Enter to quit.
echo.

set "TERM="
set /p "TERM=  Game or system: "

if "%TERM%"=="" goto :done

echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%' -Search '%TERM%'"

echo ---------------------------------------------------------------------------
echo.
echo   Enter the Index number to restore that version.
echo   Leave blank to search again.
echo.

set "PICK="
set /p "PICK=  Index number: "

if "%PICK%"=="" goto :search

echo.
echo ---------------------------------------------------------------------------
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS%' -Search '%TERM%' -Pick %PICK% -Confirm:$false"

echo.
echo ---------------------------------------------------------------------------
echo.
echo   The file that was there before was kept as a 'prerestore' version,
echo   so this is undoable if you picked the wrong one.
echo.
pause
goto :search

:done
endlocal
