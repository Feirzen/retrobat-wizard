@echo off
REM ---------------------------------------------------------------------------
REM  Shows what this drive is set to do for you, and what it is not.
REM
REM  READ-ONLY. It changes nothing, so it is safe to run at any time, even
REM  with RetroBat open.
REM
REM  Each line is one thing this drive does that plain RetroBat does not:
REM  the reworded menus, the confirmation before a slow launch, the video
REM  volume levelling, and so on. [ON ] means it is happening, [off] means it
REM  is not, and the line underneath says what that means for you.
REM
REM  To change one, use the Features tab in the Setup Wizard, or edit
REM  _Wizard\Settings\features.ini by hand and then run
REM  RUN THIS AFTER AN UPDATE.bat.
REM ---------------------------------------------------------------------------
title RetroBat - Show My Features
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Show-Features.ps1'"

echo.
pause
