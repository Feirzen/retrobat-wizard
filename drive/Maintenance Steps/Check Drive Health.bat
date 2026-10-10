@echo off
REM ---------------------------------------------------------------------------
REM  READ-ONLY health check for the whole drive. Six lights:
REM
REM    Save backups     is the automatic backup still working?
REM    Protected files  are the custom files an update would wipe all there?
REM    Settings         does everything still match what was last applied?
REM    Drive letters    is the drive still fully portable?
REM    Video volume     are all the videos still levelled?
REM    Free space       how full is the drive?
REM
REM  Green is fine, yellow is worth knowing, red says what is wrong AND which
REM  button fixes it. Changes nothing, so it is safe any time, even with
REM  RetroBat open. Also saves the report to _ClaudeWorkspace\status.json.
REM ---------------------------------------------------------------------------
title RetroBat - Check Drive Health
echo.
echo   Checking the drive (read-only)...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Check-DriveHealth.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
