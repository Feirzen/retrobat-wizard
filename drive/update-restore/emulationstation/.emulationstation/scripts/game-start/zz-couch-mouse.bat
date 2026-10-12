@echo off
REM ---------------------------------------------------------------------------
REM  RetroBat game-start hook: the couch mouse.
REM  Lives in emulationstation\.emulationstation\scripts\game-start\
REM  EmulationStation runs every .bat in this folder as a game starts.
REM
REM  Starts _ClaudeWorkspace\scripts\CouchMouse.ps1 hidden and returns at once.
REM  It turns the controller into a mouse ONLY for the consoles listed in
REM  _ClaudeWorkspace\couch-mouse.txt (Flash to start with) and browser games
REM  and quits by itself for everything else, and when the game ends.
REM
REM  A master copy lives in _ClaudeWorkspace\update-restore\, so a RetroBat
REM  update that clears this folder gets it back automatically.
REM
REM  NO DRIVE LETTERS. The "for" line resolves the RetroBat folder properly.
REM ---------------------------------------------------------------------------

for %%I in ("%~dp0..\..\..\..") do set "RBROOT=%%~fI"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%RBROOT%\_ClaudeWorkspace\couch-mouse.txt" exit /b 0
if not exist "%PSEXE%" exit /b 0

start "RetroBat couch mouse" /min "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%RBROOT%\_ClaudeWorkspace\scripts\CouchMouse.ps1"
exit /b 0
