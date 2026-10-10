@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Add a game disc to ScummVM

rem ============================================================
rem  HOW TO USE: drag a .iso file and drop it onto this file.
rem  It copies the disc into RetroBat\roms\scummvm and makes the
rem  small marker file RetroBat needs. Your .iso is never changed.
rem  It finds the RetroBat folder by itself (no drive letters).
rem ============================================================

if "%~1"=="" goto :usage
if /i not "%~x1"==".iso" goto :notiso
if not exist "%~1" goto :usage

set "ISO_PATH=%~f1"
set "NAME=%~n1"

rem ---- find roms\scummvm by looking in this folder, then upward ----
set "ROOT=%~dp0"
:findroms
if exist "%ROOT%RetroBat\roms\scummvm\" set "DEST=%ROOT%RetroBat\roms\scummvm" & goto :gotroms
if exist "%ROOT%roms\scummvm\" set "DEST=%ROOT%roms\scummvm" & goto :gotroms
pushd "%ROOT%.." 2>nul || goto :noroms
set "PARENT=%CD%"
popd
if not "%PARENT:~-1%"=="\" set "PARENT=%PARENT%\"
if /i "%PARENT%"=="%ROOT%" goto :noroms
set "ROOT=%PARENT%"
goto :findroms

:gotroms
set "GAME=%DEST%\%NAME%"

rem ---- ask which game it is ----
:pickgame
cls
echo.
echo  Disc image: %NAME%
echo.
echo  Which game is it?
echo.
echo     1  Pajama Sam 1: No Need to Hide When It's Dark Outside
echo     2  Pajama Sam 2: Thunder and Lightning Aren't so Frightening
echo     3  Pajama Sam 3: You Are What You Eat
echo     4  Putt-Putt Joins the Parade
echo     5  Putt-Putt Saves the Zoo
echo     6  Putt-Putt Travels Through Time
echo     7  Putt-Putt Goes to the Moon
echo     8  Putt-Putt Enters the Race
echo     9  Putt-Putt Joins the Circus
echo    10  Freddi Fish 1: Missing Kelp Seeds
echo    11  Freddi Fish 2: Haunted Schoolhouse
echo    12  Freddi Fish 3: Stolen Conch Shell
echo    13  Freddi Fish 4: Hogfish Rustlers of Briny Gulch
echo    14  Freddi Fish 5: Creature of Coral Cove
echo    15  Spy Fox: Dry Cereal
echo    16  Spy Fox 2: Some Assembly Required
echo    17  Spy Fox: Operation Ozone
echo    18  Fatty Bear's Birthday Surprise
echo    19  Something else - I will type the ID myself
echo.
set "CHOICE="
set /p "CHOICE=  Type a number and press Enter: "

set "ID="
if "%CHOICE%"=="1" set "ID=pajama"
if "%CHOICE%"=="2" set "ID=pajama2"
if "%CHOICE%"=="3" set "ID=pajama3"
if "%CHOICE%"=="4" set "ID=puttputt"
if "%CHOICE%"=="5" set "ID=puttzoo"
if "%CHOICE%"=="6" set "ID=putttime"
if "%CHOICE%"=="7" set "ID=puttmoon"
if "%CHOICE%"=="8" set "ID=puttrace"
if "%CHOICE%"=="9" set "ID=puttcircus"
if "%CHOICE%"=="10" set "ID=freddi"
if "%CHOICE%"=="11" set "ID=freddi2"
if "%CHOICE%"=="12" set "ID=freddi3"
if "%CHOICE%"=="13" set "ID=freddi4"
if "%CHOICE%"=="14" set "ID=freddicove"
if "%CHOICE%"=="15" set "ID=spyfox"
if "%CHOICE%"=="16" set "ID=spyfox2"
if "%CHOICE%"=="17" set "ID=spyozon"
if "%CHOICE%"=="18" set "ID=fbear"
if "%CHOICE%"=="19" goto :typeid
if not defined ID goto :pickgame
goto :haveid

:typeid
echo.
set "ID="
set /p "ID=  Type the ScummVM ID, letters and numbers only (example: pajama): "
if not defined ID goto :pickgame

:haveid
if exist "%GAME%\%ID%.scummvm" goto :already

echo.
echo  Mounting the disc image...
set "DRV="
for /f "delims=" %%L in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Mount-DiskImage -ImagePath $env:ISO_PATH | Out-Null; (Get-DiskImage -ImagePath $env:ISO_PATH | Get-Volume).DriveLetter"') do set "DRV=%%L"
if not defined DRV goto :mountfail

echo  Copying the game files. This can take a few minutes, please wait...
robocopy "%DRV%:\." "%GAME%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "RC=%ERRORLEVEL%"

echo  Cleaning up...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Dismount-DiskImage -ImagePath $env:ISO_PATH | Out-Null"

if %RC% GEQ 8 goto :copyfail

attrib -R "%GAME%\*" /S /D >nul 2>&1

rem ---- make the marker file (just the ID, no extra lines) ----
>"%GAME%\%ID%.scummvm" <nul set /p "=%ID%"

echo.
echo  ============================================================
echo   Done! Added to: %GAME%
echo   Marker file:    %ID%.scummvm
echo.
echo   Restart RetroBat and the game should show up in ScummVM.
echo   Your original .iso was not changed.
echo  ============================================================
echo.
pause
exit /b 0

:already
echo.
echo  This game already has a marker file here:
echo    %GAME%\%ID%.scummvm
echo  Nothing was changed.
echo.
pause
exit /b 0

:mountfail
echo.
echo  Could not open the disc image. Nothing was copied.
echo  Try double-clicking the .iso yourself to see if Windows can open it.
echo.
pause
exit /b 1

:copyfail
echo.
echo  Something went wrong while copying (robocopy code %RC%).
echo  The folder may be partly filled: %GAME%
echo  You can delete that folder and try again.
echo.
pause
exit /b 1

:noroms
echo.
echo  Could not find the RetroBat roms\scummvm folder.
echo  Keep this file somewhere inside your RetroBat drive, for example
echo  in the _ClaudeWorkspace folder, and try again.
echo.
pause
exit /b 1

:notiso
echo.
echo  That is not a .iso file. Nothing was changed.
echo.
pause
exit /b 1

:usage
echo.
echo  Drag a .iso file and drop it onto this file.
echo  (Double-clicking it does nothing on its own.)
echo.
pause
exit /b 0
