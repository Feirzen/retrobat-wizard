@echo off
REM ---------------------------------------------------------------------------
REM  Makes the button at the top of the drive match the name in
REM  _ClaudeWorkspace\wizard\wizard.ini.
REM
REM  The drive's name lives in ONE place, that wizard.ini line, and everything
REM  follows it by itself: the window title, the Play tab, the Help page, and
REM  the icon at the top of the drive, which renames itself every run. The one
REM  thing that cannot follow is this .bat file, because a file cannot rename
REM  itself while Windows is running it. So this does it.
REM
REM  It renames BOTH copies: the live one at the drive root, and the master in
REM  _ClaudeWorkspace\update-restore\. Renaming only the live one would mean the
REM  next repair put the old name straight back next to the new one.
REM
REM  NOTHING IS DELETED. The old file is MOVED into
REM  _ClaudeWorkspace\_SAFE TO DELETE, which is this drive's rule for
REM  everything. If it turns out to be a mistake, the old file is right there.
REM
REM  Safe to run when there is nothing to do. It says so and changes nothing.
REM  Close RetroBat first.
REM ---------------------------------------------------------------------------
title RetroBat - Rename The Wizard Button
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Rename-WizardButton.ps1'"

echo.
pause
