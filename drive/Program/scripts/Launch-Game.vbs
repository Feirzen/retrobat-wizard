' ---------------------------------------------------------------------------
'  Launch-Game.vbs - what a desktop or Start Menu shortcut to ONE game points at.
'
'  It takes one argument, the game, as a path inside the RetroBat folder
'  (for example  roms\gamecube\Wind Waker.rvz ), and starts Launch-Game.ps1
'  with NO console window at all (window style 0), the same trick as
'  wizard\Launch-Wizard.vbs.
'
'  The game is handed over in an environment variable, RB_GAME, rather than
'  typed into the PowerShell command. Game names are full of apostrophes and
'  brackets ("Kirby's Epic Yarn"), and passing them through a command line
'  means quoting rules that break on exactly those names. A variable needs
'  no quoting at all.
'
'  NO DRIVE LETTER. This file lives in <RetroBat>\_Wizard\Program\scripts\
'  and works everything out from its own location.
' ---------------------------------------------------------------------------

Option Explicit

Dim fso, shell, q, scriptsDir, script, ps, cmd

If WScript.Arguments.Count < 1 Then WScript.Quit 1

Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

q          = Chr(34)
scriptsDir = fso.GetParentFolderName(WScript.ScriptFullName)
script     = fso.BuildPath(scriptsDir, "Launch-Game.ps1")

shell.Environment("PROCESS")("RB_GAME") = WScript.Arguments(0)

ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
     "\System32\WindowsPowerShell\v1.0\powershell.exe"

' -Command "& 'script'" and not -File, for the same reason as Launch-Wizard.vbs.
cmd = q & ps & q & " -NoProfile -ExecutionPolicy Bypass -Command " & _
      q & "& '" & script & "'" & q

shell.Run cmd, 0, False
