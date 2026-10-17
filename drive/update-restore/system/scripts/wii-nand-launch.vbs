' ============================================================
'  RetroBat -> Wii System Menu launch wrapper
'  Sits between EmulationStation and emulatorLauncher.exe.
'
'  Any launch that is NOT loading a RetroBat savestate gets
'  routed into the Wii System Menu, with the game you picked
'  sitting in the Disc Channel. That covers both
'  "START NEW GAME" and "START NEW AUTO SAVE".
'
'  If you pick an actual savestate slot, EmulationStation
'  sends -state_file and this passes everything through
'  untouched, so the game boots directly and resumes.
'
'  Runs under wscript.exe so no console window appears.
'
'  PORTABILITY (2026-08-20):
'  This script no longer contains any drive letter. It works
'  out where RetroBat lives from its own location on disk, so
'  the same external drive runs identically whether Windows
'  mounts it as R:, D:, or anything else.
'
'  This file must stay at:  <RetroBat>\system\scripts\
'  If you move it, the two GetParentFolderName calls below
'  need to change to match the new depth.
' ============================================================

Option Explicit

Dim fso, scriptDir, ROOT, LAUNCHER, SYSMENU_TMD
Set fso = CreateObject("Scripting.FileSystemObject")

' --- work out <RetroBat> from where this script sits ---------
'     ...\RetroBat\system\scripts\wii-nand-launch.vbs
'        up 1 -> ...\RetroBat\system
'        up 2 -> ...\RetroBat
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ROOT      = fso.GetParentFolderName(fso.GetParentFolderName(scriptDir))

LAUNCHER    = fso.BuildPath(ROOT, "emulationstation\emulatorLauncher.exe")
SYSMENU_TMD = fso.BuildPath(ROOT, "saves\wii\dolphin-emu\User\Wii\title\00000001\00000002\content\title.tmd")

Dim args, i, a, cmd, hasStateFile, isWad, useWiiMenu, sh, rc

Set args = WScript.Arguments

' --- safety net: if we cannot find the launcher, say so -----
'     Silent failure here is what made the old drive-letter
'     bug so hard to spot, so this one speaks up.
If Not fso.FileExists(LAUNCHER) Then
    MsgBox "RetroBat Wii launcher could not find:" & vbCrLf & vbCrLf & _
           LAUNCHER & vbCrLf & vbCrLf & _
           "This script expects to live in <RetroBat>\system\scripts\." & vbCrLf & _
           "It is currently at:" & vbCrLf & WScript.ScriptFullName, _
           vbExclamation, "RetroBat - Wii launch failed"
    WScript.Quit 1
End If

' --- did EmulationStation ask us to load a savestate? --------
hasStateFile = False
For i = 0 To args.Count - 1
    If LCase(args(i)) = "-state_file" Then hasStateFile = True
Next

' --- is this a WiiWare / Virtual Console .wad? --------------
'     A .wad is a downloadable channel, not a disc. Routing one
'     through the Wii System Menu would look for it in the Disc
'     Channel, where it does not exist. WiiWare titles therefore
'     skip the Wii Menu and boot straight into the game.
'     Regular disc games (.iso .wbfs .rvz .nkit and friends) are
'     unaffected and still go through the Wii Menu as before.
isWad = False
For i = 0 To args.Count - 1
    a = args(i)
    If Len(a) >= 4 Then
        If LCase(Right(a, 4)) = ".wad" Then isWad = True
    End If
Next

useWiiMenu = (Not hasStateFile) And (Not isWad)

' --- only route to the Wii Menu if it is actually installed --
If useWiiMenu Then
    If Not fso.FileExists(SYSMENU_TMD) Then useWiiMenu = False
End If

' --- Wii Remotes or a controller? (Claude, 2026-10-17) ------
'     Steven: "if it can play with pro maybe we skip the NAND
'     launch so that I don't have to connect Wii controllers just
'     to launch the game". Only for games that play either way
'     (controllers.ini kind remote-or-pad), only when the Wii
'     Menu would be used. The chooser answers 20 for a controller
'     (straight into the game), 40 for Back. Anything missing or
'     going wrong: the Wii Menu as always.
Dim CHOOSER, PSEXE, code, romArg
If useWiiMenu Then
    Set sh = CreateObject("WScript.Shell")
    CHOOSER = fso.BuildPath(ROOT, "_ClaudeWorkspace\scripts\ControllerChooser.ps1")
    PSEXE = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
    romArg = ""
    For i = 0 To args.Count - 2
        If LCase(args(i)) = "-rom" Then romArg = args(i + 1)
    Next
    If fso.FileExists(CHOOSER) And fso.FileExists(PSEXE) And romArg <> "" Then
        On Error Resume Next
        code = sh.Run("""" & PSEXE & """ -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & _
                      CHOOSER & """ -Root """ & ROOT & """ -System wii -Rom """ & romArg & """", 0, True)
        If Err.Number <> 0 Then code = 30
        On Error GoTo 0
        If code = 40 Then WScript.Quit 0
        If code = 20 Then useWiiMenu = False
    End If
End If

' --- rebuild the command line -------------------------------
cmd = """" & LAUNCHER & """"

For i = 0 To args.Count - 1
    a = args(i)
    cmd = cmd & " """ & a & """"
Next

If useWiiMenu Then cmd = cmd & " -dolphin_wiimenu true"

' --- run and wait -------------------------------------------
Set sh = CreateObject("WScript.Shell")
rc = sh.Run(cmd, 1, True)
WScript.Quit rc
