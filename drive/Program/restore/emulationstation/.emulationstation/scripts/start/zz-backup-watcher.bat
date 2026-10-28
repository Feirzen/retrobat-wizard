@echo off
REM ---------------------------------------------------------------------------
REM  RetroBat start hook: launch the Dolphin savestate watcher.
REM  Lives in emulationstation\.emulationstation\scripts\start\
REM  EmulationStation runs every .bat in this folder when it starts up.
REM
REM  While Dolphin is running, moves any savestate it produces into the
REM  quarantine folder every 3 minutes. Idle the rest of the time. Exits by
REM  itself when RetroBat closes.
REM
REM  This one DOES run in the background, because it stays alive for the whole
REM  session and cannot be waited on. It launches PowerShell.exe directly by
REM  full path, which Windows is happy to do - the problem the game-end hook
REM  ran into was specifically "start" being handed a .bat file.
REM
REM  NO DRIVE LETTERS. The "for" line resolves the RetroBat folder properly.
REM ---------------------------------------------------------------------------

for %%I in ("%~dp0..\..\..\..") do set "RBROOT=%%~fI"

set "LOG=%RBROOT%\_Wizard\Backups\Saves\hook.log"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

>>"%LOG%" echo [%DATE% %TIME%] start hook fired, launching Dolphin watcher

if not exist "%PSEXE%" (
    >>"%LOG%" echo [%DATE% %TIME%]   ERROR: PowerShell not found at %PSEXE%
    exit /b 0
)

start "RetroBat Dolphin watcher" /min "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%RBROOT%\_Wizard\Program\scripts\Watch-Dolphin.ps1" -SweepMinutes 3
exit /b 0
