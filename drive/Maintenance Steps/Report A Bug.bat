@echo off
REM ---------------------------------------------------------------------------
REM  Sends a bug report, an idea, or a game request. For a bug, the wizard's
REM  recent logs go too if you say yes. You see exactly what will be sent before anything goes. Your
REM  Windows name and computer name are taken out of the logs first.
REM
REM  The same thing as Report a bug on the wizard's Help tab. With no internet
REM  it is saved and sent the next time the wizard opens.
REM ---------------------------------------------------------------------------
title RetroBat - Report A Bug
echo.

REM  PowerShell is called by its FULL path on purpose. A bare powershell.exe
REM  fails completely silently when the parent did not hand down a normal
REM  PATH, which is what hid a broken save backup here for five days.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0..\scripts\Report-Bug.ps1'"

echo.
pause
