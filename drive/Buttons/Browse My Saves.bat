@echo off
REM ---------------------------------------------------------------------------
REM  Browse your saves BY GAME and put a whole game back the way it was.
REM
REM  This is the same thing the Setup Wizard's Saves tab does. It is here as a
REM  button as well, on purpose: the window is a convenience, never something
REM  the drive depends on.
REM
REM  "Restore A Save.bat" next to this one is the older, one-file-at-a-time
REM  version. It still works. Use it when you want a single file back.
REM
REM  No drive letter anywhere: %~dp0 is wherever this file happens to be, and
REM  PowerShell is called by its full path because a bare "powershell.exe"
REM  fails silently when it is not on the PATH.
REM ---------------------------------------------------------------------------
title RetroBat - Browse My Saves

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Show-SaveHistory.ps1'"

echo.
pause
