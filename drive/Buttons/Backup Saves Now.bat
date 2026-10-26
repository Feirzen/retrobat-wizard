@echo off
REM ---------------------------------------------------------------------------
REM  Runs the save backup right now.
REM  You normally never need this - it runs automatically after every game.
REM  Use it for the first run, or any time you want a version on demand.
REM ---------------------------------------------------------------------------
title RetroBat - Backup Saves Now
echo.
echo   Backing up save data...
echo.
echo ---------------------------------------------------------------------------
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Backup-RetroBatSaves.ps1'"

echo.
echo ---------------------------------------------------------------------------
echo.
echo   Backups live in the Versions folder next to this file.
echo.
pause
