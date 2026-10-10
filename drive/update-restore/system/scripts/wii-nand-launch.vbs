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
