@echo off
REM ---------------------------------------------------------------------------
REM  Keeps every video on this setup at a sensible, consistent volume.
REM
REM  Two kinds get handled:
REM    - the little game preview videos, which the idle screen also plays
REM    - the console video behind each system and collection on the main menu,
REM      set deliberately a bit louder than the previews
REM
REM  EmulationStation has no volume control for either, so the volume has to
REM  live in the files themselves. This measures every one and re-records
REM  anything off target, with a gentle fade-in so nothing startles you.
REM
REM  It remembers what it has already checked, so the first run takes about a
REM  minute and every run after that is instant. That is why it is safe to
REM  have inside RUN THIS AFTER AN UPDATE.
REM
REM  Run it after scraping new games or changing theme. Or do not - the update
REM  button runs it for you.
REM
REM  RETROBAT MUST BE CLOSED. EmulationStation keeps videos open while it is
REM  running and they cannot be replaced underneath it.
REM
REM  To make it louder or quieter, edit the two target numbers at the top of
REM  Fix-VideoVolume.ps1 in the scripts folder. Changing a number re-checks
REM  everything by itself - there is nothing else to remember.
REM ---------------------------------------------------------------------------
title RetroBat - Fix Video Volume
echo.
echo   Checking video volumes...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Fix-VideoVolume.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
