@echo off
REM ---------------------------------------------------------------------------
REM  Switches on the per-game Cemu settings this drive wants, for the handful
REM  of Wii U games that need them.
REM
REM  RIGHT NOW THAT MEANS BREATH OF THE WILD, which is far heavier than
REM  anything else in this collection. RetroBat's own settings work one whole
REM  console at a time, so the only way to make BOTW behave without punishing
REM  twenty other Wii U games is Cemu's graphic packs, which are per-game.
REM  They are already downloaded on this drive; this just switches them on.
REM
REM  CLOSE RETROBAT AND CEMU FIRST. Both of them rewrite Cemu's settings file
REM  when they close, so anything written while one is open gets thrown away a
REM  minute later. This checks, and refuses rather than wasting your time.
REM
REM  It never switches OFF a pack you turned on yourself in Cemu's own window.
REM
REM  To change what it applies, edit the list at the top of
REM  _Wizard\Program\scripts\Apply-GraphicPacks.ps1. It explains itself.
REM ---------------------------------------------------------------------------
title RetroBat - Apply Cemu Graphic Packs
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Apply-GraphicPacks.ps1'"

echo.
pause
