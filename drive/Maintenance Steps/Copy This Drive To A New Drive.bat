@echo off
REM ---------------------------------------------------------------------------
REM  Copies EVERYTHING on this drive onto a new drive, exactly as it is, then
REM  checks every file against the original.
REM
REM    - Copies FROM the drive this button is on. No drive letters stored.
REM    - Asks which drive to copy TO, from a list.
REM    - Deletes nothing, on either drive.
REM    - Keeps the computer awake, and can be run again if interrupted -
REM      the second run only copies what is missing or different.
REM    - Afterwards, rebuilds the icons at the top of the new drive and saves
REM      its log into the new drive's _ClaudeWorkspace\archive folder.
REM
REM  Close RetroBat first. It checks and refuses otherwise.
REM ---------------------------------------------------------------------------
title RetroBat - Copy This Drive To A New Drive

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Copy-ToNewDrive.ps1"

echo.
pause
