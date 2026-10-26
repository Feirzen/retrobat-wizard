@echo off
REM ---------------------------------------------------------------------------
REM  Puts this drive's buttons onto THIS computer's Start Menu, with icons
REM  that stay put when the drive is unplugged.
REM
REM  WHY IT EXISTS. The two icons at the top of the drive are built fresh
REM  every time the wizard runs, pointed at whatever letter the drive has
REM  today. Copy one of them to the Start Menu and it looks right until the
REM  drive is unplugged, at which point it goes blank: a shortcut stores its
REM  icon as a path, and that path is on a drive that is no longer there.
REM
REM  This copies the icon files onto the computer and points the shortcuts at
REM  those instead, so they keep their face either way. It also adds a
REM  Controllers button, which opens Windows' own game controller list and
REM  works with the drive unplugged.
REM
REM  NOTHING IS WRITTEN TO THE DRIVE. Everything it makes lives on this
REM  computer, and option 4 removes all of it.
REM
REM  Safe to run at any time, even with RetroBat open.
REM ---------------------------------------------------------------------------
title RetroBat - Set Up This Computer
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Show-LocalSetup.ps1'"

echo.
pause
