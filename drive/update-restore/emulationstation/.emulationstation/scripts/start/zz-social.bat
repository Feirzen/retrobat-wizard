@echo off
REM ---------------------------------------------------------------------------
REM  RetroBat start hook: the Profile tab's background helper.
REM  Lives in emulationstation\.emulationstation\scripts\start\
REM  EmulationStation runs every .bat in this folder when it starts up.
REM
REM  Social-Helper.ps1 checks in as online, tells friends what game is on,
REM  shows a small popup when a friend comes online, and signs off by itself
REM  when RetroBat closes. For a guest, or a drive with no profile, it exits
REM  straight away and does nothing at all. Only one copy ever runs.
REM
REM  Runs in the background with no window, the same way zz-backup-watcher.bat
REM  starts the Dolphin watcher. NO DRIVE LETTERS: the "for" line resolves the
REM  RetroBat folder from this file's own location.
REM ---------------------------------------------------------------------------

for %%I in ("%~dp0..\..\..\..") do set "RBROOT=%%~fI"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "HELPER=%RBROOT%\_ClaudeWorkspace\scripts\Social-Helper.ps1"

if not exist "%PSEXE%" exit /b 0
if not exist "%HELPER%" exit /b 0
if not exist "%RBROOT%\_ClaudeWorkspace\profile\profile.ini" exit /b 0

start "RetroBat social helper" /min "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%HELPER%"
exit /b 0
