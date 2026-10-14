' ============================================================
'  RetroBat -> Wii U launch wrapper (Claude, 2026-10-13)
'  Sits between EmulationStation and emulatorLauncher.exe,
'  the same way wii-nand-launch.vbs does for the Wii.
'
'  Before the game starts it shows the "Wii Remotes or Pro
'  Controller?" screen (_ClaudeWorkspace\scripts\
'  ControllerChooser.ps1) and waits for an answer, then adds
'  the choice to the launch line:
'     Wii Remotes     -use_wiimotes 4
'     Pro Controller  -use_wiimotes 0
'  A choice on the launch line beats the per-game setting, so
'  nothing is rewritten anywhere.
'
'  SAFE BY DESIGN: if PowerShell or the chooser is missing, or
'  anything goes wrong, the game launches exactly as RetroBat
'  would have launched it. Only pressing B / Esc on the chooser
'  stops a launch, and that is on purpose.
'
'  Put in RetroBat's Wii U launch command by Fix-Portability.ps1,
'  which also puts it back after a RetroBat update. Switch it off
'  with  wiiuchooser = off  in _ClaudeWorkspace\features.ini.
'
'  NO DRIVE LETTERS. Must stay at <RetroBat>\system\scripts\.
' ============================================================
Option Explicit

Dim fso, sh, scriptDir, ROOT, LAUNCHER, CHOOSER, PSEXE, FOCUS, LOGF
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ROOT      = fso.GetParentFolderName(fso.GetParentFolderName(scriptDir))
LAUNCHER  = fso.BuildPath(ROOT, "emulationstation\emulatorLauncher.exe")
CHOOSER   = fso.BuildPath(ROOT, "_ClaudeWorkspace\scripts\ControllerChooser.ps1")
FOCUS     = fso.BuildPath(ROOT, "_ClaudeWorkspace\scripts\Focus-GameWindow.ps1")
LOGF      = fso.BuildPath(ROOT, "_ClaudeWorkspace\wizard\controller-chooser.log")
PSEXE     = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(LAUNCHER) Then
    MsgBox "RetroBat Wii U launcher could not find:" & vbCrLf & vbCrLf & LAUNCHER, _
           vbExclamation, "RetroBat - Wii U launch failed"
    WScript.Quit 1
End If

Dim args, i, a, rom, cmd, extra, code
Set args = WScript.Arguments

rom = ""
For i = 0 To args.Count - 2
    If LCase(args(i)) = "-rom" Then rom = args(i + 1)
Next

' --- ask, and wait ------------------------------------------
extra = ""
If fso.FileExists(CHOOSER) And fso.FileExists(PSEXE) And rom <> "" Then
    On Error Resume Next
    code = sh.Run("""" & PSEXE & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
                  CHOOSER & """ -Root """ & ROOT & """ -Rom """ & rom & """", 0, True)
    If Err.Number <> 0 Then code = 30
    On Error GoTo 0
    If code = 10 Then extra = " -use_wiimotes 4"
    If code = 20 Then extra = " -use_wiimotes 0"
    If code = 40 Then WScript.Quit 0
End If

' --- launch, exactly as RetroBat would, plus the choice -----
cmd = """" & LAUNCHER & """"
For i = 0 To args.Count - 1
    cmd = cmd & " """ & args(i) & """"
Next
cmd = cmd & extra

' --- bring Cemu to the front once it opens (2026-10-14) ----
' This helper is not the window at the front, so Windows would
' open Cemu BEHIND RetroBat. Focus-GameWindow.ps1 waits for the
' Cemu window, brings it forward once, and exits. Missing = the
' game still starts, just maybe behind.
If fso.FileExists(FOCUS) And fso.FileExists(PSEXE) Then
    On Error Resume Next
    sh.Run """" & PSEXE & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
           FOCUS & """ -Name cemu -Log """ & LOGF & """", 0, False
    On Error GoTo 0
End If

WScript.Quit sh.Run(cmd, 1, True)
