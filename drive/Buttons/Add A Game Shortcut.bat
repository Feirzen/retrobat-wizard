@echo off
REM ---------------------------------------------------------------------------
REM  Puts one game on this computer's desktop or Start Menu, so it starts
REM  straight away without opening RetroBat first.
REM
REM  It asks four things: which console, which game, which picture to use for
REM  the icon, and where to put it. The pictures are the ones RetroBat already
REM  scraped, shown at roughly icon size so you can see which one still reads
REM  when it is that small - that is different for nearly every game.
REM
REM  NOTHING IS WRITTEN TO THE DRIVE. The shortcut and its icon both go on the
REM  computer. The icon is copied there on purpose, so it still looks right
REM  after the drive is unplugged instead of turning into a blank square.
REM  Clicking it with the drive gone just says it cannot find the game.
REM
REM  To undo one, delete the shortcut like any other.
REM ---------------------------------------------------------------------------
title RetroBat - Add A Game Shortcut
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Show-ShortcutMaker.ps1'"

echo.
pause
