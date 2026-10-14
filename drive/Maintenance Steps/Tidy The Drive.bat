@echo off
REM ---------------------------------------------------------------------------
REM  Clears out old backups and leftovers nothing on the drive uses any more.
REM  It shows the whole list with sizes first and deletes nothing until you
REM  type Y. Saves, games and settings are never touched. Close RetroBat first.
REM ---------------------------------------------------------------------------
setlocal
title RetroBat - Tidy The Drive
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Tidy-Drive.ps1"
