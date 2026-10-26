@echo off
REM ---------------------------------------------------------------------------
REM  RUN THIS ONLY AFTER YOU CHANGE A PROTECTED FILE ON PURPOSE.
REM
REM  "Restore Protected Files" keeps master copies of a few files that live
REM  inside RetroBat's own folders. If you deliberately change one of them -
REM  swap a loading screen video, reword another menu item - the next restore
REM  would helpfully undo your change.
REM
REM  This does the opposite: it takes what is live right now and makes THAT
REM  the new master. Run it once after any deliberate change.
REM ---------------------------------------------------------------------------
title RetroBat - Update Master Copies
echo.
echo   Taking the live files as the new known-good masters...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Restore-ProtectedFiles.ps1' -Adopt"

echo ---------------------------------------------------------------------------
echo.
pause
