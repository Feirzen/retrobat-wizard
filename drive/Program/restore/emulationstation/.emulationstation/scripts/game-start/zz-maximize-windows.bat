@echo off
REM ---------------------------------------------------------------------------
REM  RetroBat game-start hook: make certain PC game windows fill the screen.
REM  Lives in emulationstation\.emulationstation\scripts\game-start\
REM  EmulationStation runs every .bat in this folder as a game starts.
REM
REM  Starts _Wizard\Program\scripts\Maximize-GameWindow.ps1 hidden and returns
REM  at once, so the game is never held up. That script only acts on programs
REM  named in _Wizard\Settings\maximize-windows.txt (added 2026-09-25
REM  for the Jackbox Megapicker, which always opens small).
REM
REM  A master copy lives in _Wizard\Program\restore\, so a RetroBat
REM  update that clears this folder gets it back automatically.
REM
REM  NO DRIVE LETTERS. The "for" line resolves the RetroBat folder properly.
REM ---------------------------------------------------------------------------

for %%I in ("%~dp0..\..\..\..") do set "RBROOT=%%~fI"
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%RBROOT%\_Wizard\Settings\maximize-windows.txt" exit /b 0
if not exist "%PSEXE%" exit /b 0

start "RetroBat window fix" /min "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%RBROOT%\_Wizard\Program\scripts\Maximize-GameWindow.ps1"
exit /b 0
