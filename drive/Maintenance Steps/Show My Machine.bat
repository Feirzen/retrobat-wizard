@echo off
REM ---------------------------------------------------------------------------
REM  READ-ONLY. Shows which machine settings this computer gets - its name, graphics
REM  card, tier (Low / Medium / High) - and every setting Apply My Settings
REM  would write for it, with where each one comes from.
REM
REM  Changes nothing, so it is safe to run any time, even with RetroBat open.
REM  Handy on a new computer to see what the drive is about to pick, or to
REM  check that pinned settings in machine\machines are being read.
REM ---------------------------------------------------------------------------
title RetroBat - Show My Machine
echo.
echo   Working out this computer's machine settings (read-only)...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Show-MachineProfile.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
