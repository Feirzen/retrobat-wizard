@echo off
REM ---------------------------------------------------------------------------
REM  Sweep any savestates sitting in the emulator folders into quarantine.
REM  Normally automatic - this is here for a manual check or a one-off cleanup.
REM ---------------------------------------------------------------------------
title RetroBat - Quarantine Savestates
echo.
echo   Moving any savestates out of the emulator folders...
echo.
echo ---------------------------------------------------------------------------
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Quarantine-Savestates.ps1'"

echo.
echo ---------------------------------------------------------------------------
echo.
echo   Nothing was deleted. Anything moved is in:
echo   _Wizard\Backups\Archive\quarantined-savestates\
echo.
pause
