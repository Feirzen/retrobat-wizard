@echo off
REM ---------------------------------------------------------------------------
REM  Dry run. Shows exactly what the backup WOULD do and writes nothing at all.
REM  Safe to double-click any time.
REM ---------------------------------------------------------------------------
title RetroBat - Test Backup (no changes)
echo.
echo   TEST RUN - nothing will be written.
echo   This just shows what the real backup would do.
echo.
echo ---------------------------------------------------------------------------
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Backup-RetroBatSaves.ps1' -WhatIf"

echo.
echo ---------------------------------------------------------------------------
echo.
echo   Done. Nothing was changed.
echo.
pause
