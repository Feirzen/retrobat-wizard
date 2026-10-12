' ---------------------------------------------------------------------------
'  Launch-Browser.vbs - how RetroBat starts a game on the Browser Games shelf.
'
'  es_systems_browser.cfg runs:  wscript.exe //nologo "...\Launch-Browser.vbs" %ROM%
'  (wscript.exe is always found, whatever PATH a program hands down, which is
'  why the Wii launcher uses the same trick). This starts Launch-Browser.ps1
'  with NO console window and WAITS for it, so RetroBat waits too, exactly
'  like any other game, and comes back when the game is closed.
'
'  The game is handed over in RB_GAME, not on a command line, so names with
'  apostrophes and brackets need no quoting (same as Launch-Game.vbs).
'
'  NO DRIVE LETTER: everything is worked out from this file's own location.
' ---------------------------------------------------------------------------

Option Explicit

Dim fso, shell, q, scriptsDir, script, ps, cmd

If WScript.Arguments.Count < 1 Then WScript.Quit 1

Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

q          = Chr(34)
scriptsDir = fso.GetParentFolderName(WScript.ScriptFullName)
script     = fso.BuildPath(scriptsDir, "Launch-Browser.ps1")

shell.Environment("PROCESS")("RB_GAME") = WScript.Arguments(0)

ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
     "\System32\WindowsPowerShell\v1.0\powershell.exe"

cmd = q & ps & q & " -NoProfile -ExecutionPolicy Bypass -Command " & _
      q & "& '" & Replace(script, "'", "''") & "'" & q

' 0 = no window, True = wait until it finishes.
WScript.Quit shell.Run(cmd, 0, True)
