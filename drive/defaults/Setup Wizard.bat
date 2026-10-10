@echo off
REM ---------------------------------------------------------------------------
REM  Opens the Setup Wizard window on purpose: the big Play button, the drive
REM  health light, and tabs for your profile, games, netplay, health, this
REM  machine, saves, the on/off switches and help.
REM
REM  To rename the wizard (for a future owner): edit the "name =" line in
REM  _ClaudeWorkspace\wizard\wizard.ini, and rename this file to match. The
REM  shortcut at the top of the drive renames itself to follow that line, and
REM  the old one is moved into _ClaudeWorkspace\_SAFE TO DELETE.
REM  If something seems wrong, look in _ClaudeWorkspace\wizard\wizard.log.
REM
REM  IT GOES THROUGH A .VBS ON PURPOSE (2026-09-02). Launching PowerShell
REM  straight from here left a black console window on screen for as long as
REM  the wizard was open, and closing that window killed the wizard with it.
REM  -WindowStyle Hidden does not prevent it: the console exists before
REM  PowerShell is running to hide anything. Launch-Wizard.vbs starts the
REM  same command with window style 0, which never creates one at all.
REM
REM  If the .vbs is ever missing, the old direct call still runs. Nothing here
REM  fails closed. PowerShell is called by its FULL path on purpose: a bare
REM  "powershell.exe" fails silently when whatever launched this did not hand
REM  it a normal PATH - the exact trap that hid a broken save backup for five
REM  days in August 2026.
REM ---------------------------------------------------------------------------
if not exist "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" goto fallback
"%SystemRoot%\System32\wscript.exe" //nologo "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs"
goto :eof

:fallback
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& '%~dp0_ClaudeWorkspace\wizard\SetupWizard.ps1'"
