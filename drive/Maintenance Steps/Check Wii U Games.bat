@echo off
REM ---------------------------------------------------------------------------
REM  Checks every Wii U disc image (.wux) in roms\wiiu for a half-finished
REM  download or a half-finished unzip.
REM
REM  WHY YOU WANT THIS. A .wux missing the end of the file still boots. The
REM  start of a disc is the menu and the first load, so the game runs for a
REM  while and then crashes when it reaches a part that was never written. That
REM  looks exactly like an emulator problem and it is not one.
REM
REM  Run it after unpacking a new Wii U game, before you sink an evening into
REM  wondering why it keeps dying. It only looks - nothing is changed or moved.
REM
REM  It does NOT check whether the key in keys.txt is right. A complete file can
REM  still refuse to start for that reason, and the error message says so.
REM ---------------------------------------------------------------------------
title RetroBat - Check Wii U Games
echo.
echo   Checking Wii U disc images for missing pieces...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Test-WiiUGames.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
