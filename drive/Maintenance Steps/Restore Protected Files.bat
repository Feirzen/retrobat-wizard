@echo off
REM ---------------------------------------------------------------------------
REM  Puts back the custom files that live inside RetroBat's own folders and
REM  that an update deletes without asking:
REM
REM    - the reworded menus  (LAUNCH GAME, RESUME BACKUP SAVE, and so on)
REM    - the loading screen videos, including the wii.mp4 added by hand
REM    - the Wii System Menu launch wrapper
REM
REM  The master copies live in _ClaudeWorkspace\update-restore\, laid out in
REM  the same folder shape as RetroBat itself. To protect another file, just
REM  copy it in there keeping its path. Nothing to edit.
REM
REM  Included in RUN THIS AFTER AN UPDATE. Safe to run any time.
REM ---------------------------------------------------------------------------
title RetroBat - Restore Protected Files
echo.
echo   Checking the files an update would wipe out...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Restore-ProtectedFiles.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
