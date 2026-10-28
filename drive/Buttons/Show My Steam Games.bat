@echo off
REM ---------------------------------------------------------------------------
REM  Shows what this drive knows about Steam on this computer: whether Steam is
REM  installed, who is signed in, which party games have finished downloading
REM  onto the drive, and whether their tiles are showing in RetroBat.
REM
REM  IT ONLY LOOKS. Nothing is written, nothing is changed, nothing is closed.
REM  Safe to run with Steam and RetroBat both open.
REM
REM  To actually set Steam up on a computer, use Connect Steam on the wizard's
REM  Machine tab instead.
REM ---------------------------------------------------------------------------
title RetroBat - Show My Steam Games
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Show-Steam.ps1'"

echo.
pause
