@echo off
REM ---------------------------------------------------------------------------
REM  The everyday button. Checks the drive quietly, only shows a window if
REM  something actually needs a decision (a RetroBat update, a brand-new
REM  computer, a red health light), then launches RetroBat.
REM
REM  When everything is fine you see nothing but RetroBat starting.
REM  The full window lives on the other button next to this one.
REM  If something seems wrong, look in _ClaudeWorkspace\wizard\wizard.log.
REM
REM  IT GOES THROUGH A .VBS ON PURPOSE (2026-09-02). Launching PowerShell
REM  straight from here left a black console window on screen for as long as
REM  the wizard was open, and closing that window killed the wizard with it.
REM  -WindowStyle Hidden does not prevent it: the console exists before
REM  PowerShell is running to hide anything. Launch-Wizard.vbs starts the
REM  same command with window style 0, which never creates one at all.
REM  This file still flashes its own console for a moment, because every .bat
REM  does. The icons at the top of the drive point straight at the .vbs and
REM  show nothing at all, which is why they are the nicer way in.
REM
REM  If the .vbs is ever missing, the old direct call still runs. Nothing here
REM  fails closed. PowerShell is called by its FULL path on purpose: a bare
REM  "powershell.exe" fails silently when whatever launched this did not hand
REM  it a normal PATH - the exact trap that hid a broken save backup for five
REM  days in August 2026.
REM ---------------------------------------------------------------------------
if not exist "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" goto fallback
"%SystemRoot%\System32\wscript.exe" //nologo "%~dp0_ClaudeWorkspace\wizard\Launch-Wizard.vbs" -Play
goto :eof

:fallback
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& '%~dp0_ClaudeWorkspace\wizard\SetupWizard.ps1' -Play"
