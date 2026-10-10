@echo off
REM ---------------------------------------------------------------------------
REM  Checks GitHub for a newer version of the wizard and its scripts, shows
REM  what is new, and asks before installing anything.
REM
REM  The same thing as the Update now button in the wizard, without the
REM  window. Close RetroBat first. Only the wizard's own files change: saves,
REM  games, settings and anything you typed are never touched, and the old
REM  files are kept, so Go Back One Update.bat can put them back.
REM
REM  Everything it does is written to _ClaudeWorkspace\update\update.log.
REM ---------------------------------------------------------------------------
title RetroBat - Check For Updates
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Updater.ps1' -Mode Update -Console"

echo.
pause
