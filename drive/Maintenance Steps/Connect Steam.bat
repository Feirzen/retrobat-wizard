@echo off
REM ---------------------------------------------------------------------------
REM  Sets Steam up on THIS computer so the party games on this drive show up
REM  inside RetroBat as ordinary game tiles.
REM
REM  It opens one window and walks through four steps: install Steam if it is
REM  missing, sign in as you, let Steam see this drive, then build the tiles.
REM  Everything is done for you except typing your password, which is always
REM  your job and never goes anywhere near this drive.
REM
REM  It is remembered PER COMPUTER. Plug this drive into a different one and
REM  the Steam games stay hidden until this is run there too. That is on
REM  purpose: nobody else's RetroBat should show games they cannot play.
REM
REM  CLOSE RETROBAT FIRST. It only reads its game list when it starts, so new
REM  tiles would not appear until it was restarted. This checks and says so.
REM
REM  To undo it, use Disconnect Steam on the wizard's Machine tab, or run
REM  this file with the word disconnect after it.
REM ---------------------------------------------------------------------------
title RetroBat - Connect Steam
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
if /I "%~1"=="disconnect" goto :disconnect

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Show-ConnectSteam.ps1'"
goto :done

:disconnect
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Show-ConnectSteam.ps1' -Disconnect"

:done
echo.
pause
