@echo off
REM ---------------------------------------------------------------------------
REM  Installs the RetroBat Wizard into the RetroBat folder this file sits in.
REM  Put it next to RetroBat.exe, close RetroBat, then double-click it.
REM  It downloads the wizard from GitHub, checks every file, and then opens the
REM  wizard's setup. Safe to run again.
REM ---------------------------------------------------------------------------
title Install the RetroBat Wizard
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Install-Wizard.ps1'"
echo.
pause
