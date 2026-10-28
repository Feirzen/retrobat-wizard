@echo off
REM ---------------------------------------------------------------------------
REM  Writes the known-good settings back into EmulationStation and the
REM  emulators' own config files.
REM
REM  RETROBAT MUST BE CLOSED. EmulationStation rewrites its settings file when
REM  it exits, so anything changed while it is open gets thrown away. The
REM  script checks for this and will stop rather than waste your time.
REM
REM  Included in RUN THIS AFTER AN UPDATE. Also run it any time a setting seems
REM  to have reverted. To change what it applies, open Apply-Settings.ps1 in
REM  the scripts folder and edit the lists near the top - they are clearly
REM  marked and that is the intended way to change this setup.
REM ---------------------------------------------------------------------------
title RetroBat - Apply My Settings
echo.
echo   Applying saved RetroBat settings...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Apply-Settings.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
