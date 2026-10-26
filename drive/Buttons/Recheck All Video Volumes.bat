@echo off
REM ---------------------------------------------------------------------------
REM  Force EVERY video to be measured again from scratch.
REM
REM  The normal "Fix Video Volume" button keeps a list of what it has already
REM  checked, so it skips anything it has seen before. That is what makes it
REM  fast. This button ignores that list and re-measures the lot.
REM
REM  YOU DO NOT NORMALLY NEED THIS. If you change one of the target numbers or
REM  the tolerance at the top of Fix-VideoVolume.ps1, the normal button already
REM  notices and re-checks everything by itself. This is here for the case
REM  where you suspect the list itself has gone stale, or you have restored
REM  videos from a backup and want a clean sweep.
REM
REM  It takes about a minute for a hundred videos. RETROBAT MUST BE CLOSED.
REM ---------------------------------------------------------------------------
title RetroBat - Recheck All Video Volumes
echo.
echo   Re-measuring EVERY video, ignoring what was checked before...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Fix-VideoVolume.ps1' -Recheck"

echo ---------------------------------------------------------------------------
echo.
pause
