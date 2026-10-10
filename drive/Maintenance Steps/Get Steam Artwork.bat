@echo off
REM ---------------------------------------------------------------------------
REM  Gets proper artwork and trailers for the Steam shelf, from Steam itself.
REM
REM  WHY. RetroBat scrapes from ScreenScraper, which is a retro games database:
REM  brilliant on Wind Waker, and it has never heard of a party game from last
REM  year. Steam obviously has perfect artwork for everything it sells, so for
REM  this one shelf it is much the better source.
REM
REM  It takes the logo, the tall box art, the wide banner, the backdrop and the
REM  trailer, and writes them in where RetroBat looks. Pictures Steam has
REM  already cached on this computer are just copied, so a lot of it needs no
REM  download at all.
REM
REM  IT ASKS WHAT YOU WANT. Just double-click it.
REM
REM  It used to expect words typed after the file name, which is useless when
REM  you open something by double-clicking it - there is nowhere to type them.
REM  Changed on 2026-09-21 after exactly that went wrong. If you ARE at a
REM  command prompt, "force" and "force <game name>" still work and skip the
REM  question.
REM
REM  SAFE TO RUN AS OFTEN AS YOU LIKE. Anything already there is left alone
REM  unless you ask for it again. The game list is backed up into the archive
REM  before every write and nothing is ever deleted.
REM
REM  CLOSE RETROBAT FIRST. It rewrites the game list when it exits, which would
REM  throw away everything this wrote. It checks and says so.
REM ---------------------------------------------------------------------------
setlocal
title RetroBat - Get Steam Artwork

set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
set SCRIPT=%~dp0..\scripts\Show-SteamArtwork.ps1

REM  Typed at a command prompt? Do as told and skip the question.
if /I "%~1"=="force" goto :typed

:ask
cls
echo.
echo   ===================================================================
echo     ARTWORK FOR THE STEAM SHELF
echo   ===================================================================
echo.
echo     1.  Fill in what is missing          ^<- the normal one
echo.
echo         Only fetches artwork that is not already there. Anything you
echo         have typed in yourself is left alone. Quick.
echo.
echo     2.  Redo ONE game
echo.
echo         For a game that came out wrong. Asks which one next. Replaces
echo         its artwork AND its name and description.
echo.
echo     3.  Redo EVERYTHING
echo.
echo         Fetches the lot again for every game, and overwrites any name
echo         or description you typed in yourself. Slowest.
echo.
echo   -------------------------------------------------------------------
echo.
set "CHOICE="
set /p "CHOICE=  Type 1, 2 or 3 and press Enter (or just press Enter for 1): "

if not defined CHOICE goto :normal
if "%CHOICE%"=="1" goto :normal
if "%CHOICE%"=="2" goto :one
if "%CHOICE%"=="3" goto :all

echo.
echo   That was not 1, 2 or 3. Try again.
echo.
pause
goto :ask

:one
echo.
echo   Part of the name is enough, and capitals do not matter.
echo   For example, typing   jackbox   finds The Jackbox Megapicker.
echo.
set "GAME="
set /p "GAME=  Which game? "
if not defined GAME goto :ask
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& '%SCRIPT%' -Force -Only '%GAME%'"
goto :done

:all
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& '%SCRIPT%' -Force"
goto :done

:normal
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& '%SCRIPT%'"
goto :done

:typed
if "%~2"=="" goto :typedall
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& '%SCRIPT%' -Force -Only '%~2'"
goto :done

:typedall
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "& '%SCRIPT%' -Force"

:done
echo.
pause
endlocal
