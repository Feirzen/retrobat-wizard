@echo off
REM ---------------------------------------------------------------------------
REM  Undoes the last wizard update: puts back every file it replaced, takes
REM  away every file it added, and undoes any renames it made. Asks first.
REM
REM  The same thing as the Go back button on the wizard's Help tab. Close
REM  RetroBat first. The version you went back from is not offered again;
REM  a newer one will be. Nothing is deleted: the files it takes away go into
REM  _Wizard\Cache\Trash\updates.
REM ---------------------------------------------------------------------------
title RetroBat - Go Back One Update
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Updater.ps1' -Mode GoBack -Console"

echo.
pause
