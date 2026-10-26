@echo off
REM ---------------------------------------------------------------------------
REM  Restores the custom look of the Zelda and Pokemon collections in the
REM  ckau-book theme: their artwork, their video, and their background colour.
REM
REM  A theme update replaces everything inside the theme folder, which is what
REM  makes a collection fall back to the generic shared look. This puts the
REM  custom pieces back from the master copies in
REM  _Wizard\Owner\theme-assets\.
REM
REM  TO ADD A COLLECTION: drop <Name>.xml, <Name>.png and <Name>.mp4 into
REM  theme-assets, then add one line to the list at the top of
REM  Restore-CkauBookTheme.ps1.
REM
REM  Included in RUN THIS AFTER AN UPDATE. Safe to run repeatedly.
REM ---------------------------------------------------------------------------
title RetroBat - Restore Theme Collections
echo.
echo   Restoring the collection theming...
echo.
echo ---------------------------------------------------------------------------

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\Program\scripts\Restore-CkauBookTheme.ps1'"

echo ---------------------------------------------------------------------------
echo.
pause
