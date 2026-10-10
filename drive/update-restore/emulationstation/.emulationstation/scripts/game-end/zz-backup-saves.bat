@echo off
REM ---------------------------------------------------------------------------
REM  RetroBat game-end hook.
REM  Lives in emulationstation\.emulationstation\scripts\game-end\
REM  EmulationStation runs every .bat in this folder when a game exits.
REM
REM  1. Sweeps any savestates the session produced into quarantine.
REM  2. Backs up save data.
REM
REM  Everything it does is written to
REM     _ClaudeWorkspace\SaveBackups\hook.log
REM  including whatever PowerShell has to say and the exit code of each step.
REM
REM  DESIGN NOTES - both of these were learned the hard way.
REM
REM  1. It runs the two scripts DIRECTLY instead of with "start". An earlier
REM     version used "start" to fire them off in the background, and Windows
REM     refused to launch a .bat that way, leaving an error window open behind
REM     the frontend every single time a game exited. Running them in line is
REM     simpler, always works, and everything ends up in the log. The cost is
REM     that returning to the menu waits a second or two for the backup, which
REM     is fast because it only looks at files that actually changed.
REM
REM  2. It calls PowerShell by its FULL PATH. EmulationStation does not always
REM     hand its child processes a normal PATH, and a bare "powershell.exe"
REM     that cannot be found fails silently, which is what hid the broken
REM     backup for five days in August 2026.
REM
REM  NO DRIVE LETTERS. The "for" line below turns
REM     <this folder>\..\..\..\..
REM  into a clean, fully spelled out path to the RetroBat folder, whatever
REM  letter the drive has today. Resolving it properly matters: a path with
REM  ..\..\ still in it works for some Windows commands and not others.
REM ---------------------------------------------------------------------------

for %%I in ("%~dp0..\..\..\..") do set "RBROOT=%%~fI"

set "LOG=%RBROOT%\_ClaudeWorkspace\SaveBackups\hook.log"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

>>"%LOG%" echo [%DATE% %TIME%] game-end hook fired, RetroBat at %RBROOT%

if not exist "%PSEXE%" (
    >>"%LOG%" echo [%DATE% %TIME%]   ERROR: PowerShell not found at %PSEXE%
    exit /b 0
)

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%RBROOT%\_ClaudeWorkspace\scripts\Quarantine-Savestates.ps1" -Quiet >>"%LOG%" 2>&1
>>"%LOG%" echo [%DATE% %TIME%]   quarantine finished, exit code %ERRORLEVEL%

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%RBROOT%\_ClaudeWorkspace\scripts\Backup-RetroBatSaves.ps1" -Quiet >>"%LOG%" 2>&1
>>"%LOG%" echo [%DATE% %TIME%]   backup finished, exit code %ERRORLEVEL%

exit /b 0
