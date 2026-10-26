' ============================================================
'  RetroBat -> "how to play" launch wrapper (Claude, 2026-10-17)
'  Sits between EmulationStation and emulatorLauncher.exe for
'  Flash, ScummVM and PC games, the same way wiiu-launch.vbs
'  does for the Wii U.
'
'  Before the game starts it shows a short "how this game
'  plays" screen (_Wizard\Program\scripts\ControllerChooser.ps1
'  with -System): made for mouse and keyboard, how the
'  controller works in it (the couch mouse, the game's own key
'  layout), and PLAY or Back. Steven, 2026-10-17: "a window
'  saying this game is for mouse and keyboard, however custom
'  controller bindings have been set up ... with a back button".
'
'  SAFE BY DESIGN: if PowerShell or the chooser is missing, or
'  anything goes wrong, the game launches exactly as RetroBat
'  would have launched it. Only Back stops a launch.
'
'  Put in RetroBat's launch commands by Fix-Portability.ps1
'  (job 1c), which also puts it back after a RetroBat update.
'  Switch it off with  howtoplay = off  in
'  _Wizard\Settings\features.ini.
'
'  NO DRIVE LETTERS. Must stay at <RetroBat>\system\scripts\.
' ============================================================
Option Explicit

Dim fso, sh, scriptDir, ROOT, LAUNCHER, CHOOSER, PSEXE
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ROOT      = fso.GetParentFolderName(fso.GetParentFolderName(scriptDir))
LAUNCHER  = fso.BuildPath(ROOT, "emulationstation\emulatorLauncher.exe")
CHOOSER   = fso.BuildPath(ROOT, "_Wizard\Program\scripts\ControllerChooser.ps1")
PSEXE     = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(LAUNCHER) Then
    MsgBox "RetroBat's launcher could not be found:" & vbCrLf & vbCrLf & LAUNCHER, _
           vbExclamation, "RetroBat - launch failed"
    WScript.Quit 1
End If

Dim args, i, rom, sys, cmd, code, hasState
Set args = WScript.Arguments

rom = "": sys = "": hasState = False
For i = 0 To args.Count - 1
    If LCase(args(i)) = "-state_file" Then hasState = True
    If i < args.Count - 1 Then
        If LCase(args(i)) = "-rom" Then rom = args(i + 1)
        If LCase(args(i)) = "-system" Then sys = args(i + 1)
    End If
Next

' --- show how it plays, and wait ----------------------------
'     Not when resuming a save: that is somebody who has played.
If fso.FileExists(CHOOSER) And fso.FileExists(PSEXE) And rom <> "" And sys <> "" And Not hasState Then
    On Error Resume Next
    code = sh.Run("""" & PSEXE & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
                  CHOOSER & """ -Root """ & ROOT & """ -System """ & sys & """ -Rom """ & rom & """", 0, True)
    If Err.Number <> 0 Then code = 30
    On Error GoTo 0
    If code = 40 Then WScript.Quit 0
End If

' --- launch, exactly as RetroBat would ----------------------
cmd = """" & LAUNCHER & """"
For i = 0 To args.Count - 1
    cmd = cmd & " """ & args(i) & """"
Next
WScript.Quit sh.Run(cmd, 1, True)
