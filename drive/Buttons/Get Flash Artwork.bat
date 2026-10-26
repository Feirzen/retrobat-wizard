@echo off
REM ---------------------------------------------------------------------------
REM  Names, descriptions and pictures for the Flash shelf.
REM
REM  RetroBat's scraper knows almost no Flash games, so the shelf showed a
REM  blank cartridge for each one. The list is _Wizard\Settings\flash-games.ini
REM  instead: this writes it into the game list and fetches each game's
REM  pictures, from Steam when the game is sold there (copied from this
REM  computer's Steam when it has them) and from archive.org otherwise.
REM
REM  TO ADD A GAME: put the .swf in roms\flash, add it to flash-games.ini, run
REM  this. Close RetroBat first. Safe to run as often as you like: what is
REM  already there is kept, the game list is backed up first, nothing is
REM  deleted.
REM ---------------------------------------------------------------------------
setlocal
title RetroBat - Get Flash Artwork
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
set SCRIPT=%~dp0..\Program\scripts\Show-FlashArtwork.ps1
cls
echo.
echo   ===================================================================
echo     NAMES AND PICTURES FOR THE FLASH SHELF
echo   ===================================================================
echo.
echo     1.  Fill in what is missing          ^<- the normal one
echo.
echo     2.  Redo everything (replaces pictures AND any names or
echo         descriptions you typed in yourself)
echo.
choice /c 12 /n /m "    Press 1 or 2: "
if errorlevel 2 goto :force
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
goto :eof
:force
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Force
