' ---------------------------------------------------------------------------
'  THE BRIDGE (wizard 3.2, 2026-10-26).
'
'  On a drive updated from 3.1, this file sits at the OLD launcher's place,
'  RetroBat\_ClaudeWorkspace\wizard\Launch-Wizard.vbs, because every button
'  that drive already has (PLAY, the wizard button, desktop and Start menu
'  icons, the controller shortcut, the updater's "reopen") points here.
'
'  The first time any of them is used it:
'    1. copies Move-ToWizardLayout.ps1 and Paths.ps1 to this computer's TEMP
'       folder and runs them from there (so nothing inside the folder being
'       renamed is in use), which renames _ClaudeWorkspace to _Wizard, sorts
'       everything into its room and points every button at the new place;
'    2. then starts the real launcher, _Wizard\Program\wizard\Launch-Wizard.vbs,
'       with the same argument (-Play, -Setup, -Pad ...).
'  After that this file is in _Wizard\Cache\Trash and nothing points at it.
'
'  Its source is _Wizard\Program\scripts\Bridge-Launch.vbs; the publishing
'  step ships it at the old place (see ship-list.txt).
' ---------------------------------------------------------------------------
Option Explicit
Dim fso, shell, q, here, wsDir, root, newVbs, oldMove, oldPaths, tmpDir, ps, cmd, rc, i, args

Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
q = Chr(34)

here  = fso.GetParentFolderName(WScript.ScriptFullName)   ' ...\_ClaudeWorkspace\wizard
wsDir = fso.GetParentFolderName(here)                       ' ...\_ClaudeWorkspace
root  = fso.GetParentFolderName(wsDir)                      ' RetroBat
newVbs = fso.BuildPath(root, "_Wizard\Program\wizard\Launch-Wizard.vbs")

args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & q & WScript.Arguments(i) & q
Next

If fso.FolderExists(fso.BuildPath(root, "_ClaudeWorkspace")) Then
    oldMove  = fso.BuildPath(wsDir, "Program\scripts\Move-ToWizardLayout.ps1")
    oldPaths = fso.BuildPath(wsDir, "Program\scripts\Paths.ps1")
    If fso.FileExists(oldMove) And fso.FileExists(oldPaths) Then
        tmpDir = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), "RetroBatWizardMove")
        If Not fso.FolderExists(tmpDir) Then fso.CreateFolder tmpDir
        fso.CopyFile oldMove, fso.BuildPath(tmpDir, "Move-ToWizardLayout.ps1"), True
        fso.CopyFile oldPaths, fso.BuildPath(tmpDir, "Paths.ps1"), True
        shell.CurrentDirectory = tmpDir
        ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
        cmd = q & ps & q & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
              q & fso.BuildPath(tmpDir, "Move-ToWizardLayout.ps1") & q & " -Root " & q & root & q
        ' 0 = no console window; True = wait until the move is done
        rc = shell.Run(cmd, 0, True)
    End If
End If

If fso.FileExists(newVbs) Then
    shell.Run q & shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wscript.exe" & q & " //nologo " & q & newVbs & q & args, 0, False
Else
    MsgBox "The wizard could not finish moving to its new folder (_Wizard)." & vbCrLf & vbCrLf & _
           "Nothing was lost. Close RetroBat and every wizard window, then try again." & vbCrLf & _
           "If it keeps happening, restart the computer first." & vbCrLf & vbCrLf & _
           "Details: RetroBat\_ClaudeWorkspace\move.log", vbExclamation, "RetroBat Wizard"
End If
