@echo off
REM ---------------------------------------------------------------------------
REM  Unpacks any .7z files sitting in roms\3ds into plain .3ds files.
REM
REM  RUN THIS AFTER ADDING A NEW 3DS GAME. If there is nothing new it does
REM  nothing, so running it out of habit is harmless.
REM
REM  Why: RetroBat cannot hand a .7z straight to the emulator, so it extracts
REM  the whole archive - sometimes over a gigabyte - off the external drive
REM  before every single launch. Unpacking once removes that wait for good.
REM
REM  Your box art and videos are carried across automatically. The original
REM  .7z files are moved to roms\3ds\.compressed, not deleted.
REM
REM  RETROBAT MUST BE CLOSED so the game list picks up the change.
REM ---------------------------------------------------------------------------
title RetroBat - Unpack 3DS ROMs
echo.
echo   Looking for 3DS archives to unpack...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Decompress-3DS.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
