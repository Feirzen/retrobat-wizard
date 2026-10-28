@echo off
REM ---------------------------------------------------------------------------
REM  Removes hardcoded drive letters so the setup works on any PC.
REM
REM  Updates regenerate es_systems.cfg, which wipes out the custom Wii System
REM  Menu launch command. This puts it back. Dolphin also rewrites its own
REM  config every time it closes, which is the other place letters creep in.
REM
REM  Included in RUN THIS AFTER AN UPDATE. Also worth running on its own after
REM  changing settings inside Dolphin's own menus. Safe to run any time - it
REM  changes nothing that is already correct.
REM ---------------------------------------------------------------------------
title RetroBat - Fix Drive Letters
echo.
echo   Checking the setup for hardcoded drive letters...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Fix-Portability.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
