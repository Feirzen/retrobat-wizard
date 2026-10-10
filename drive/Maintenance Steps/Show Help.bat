@echo off
REM ---------------------------------------------------------------------------
REM  Explains this drive in plain English: what it is, what the two icons on
REM  the drive do, what to do when a light is not green, the three rules, and
REM  where everything is written down.
REM
REM  READ-ONLY. It changes nothing, so it is safe to run at any time, even
REM  with RetroBat open.
REM
REM  This is the same page as the Help tab in the Setup Wizard. Both read
REM  _ClaudeWorkspace\scripts\HelpText.ps1, so they can never disagree. It is
REM  a button as well as a tab on purpose: the window is a convenience, never
REM  something the drive depends on.
REM ---------------------------------------------------------------------------
title RetroBat - Help
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Show-Help.ps1'"

echo.
pause
