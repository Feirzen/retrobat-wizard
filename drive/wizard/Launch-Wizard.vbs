' ---------------------------------------------------------------------------
'  Launch-Wizard.vbs - starts the Setup Wizard with NO console window at all.
'
'  WHY THIS FILE EXISTS. Launching PowerShell from a .bat leaves a black
'  console window on screen for as long as the wizard is open, and closing
'  that window kills the wizard with it. "-WindowStyle Hidden" does not stop
'  it: the console is created before PowerShell is running to hide anything.
'  WScript.Shell's Run takes a window style of its own, and 0 means the
'  window is never created. That is the whole trick.
'
'  The two icons at the top of the drive point straight at this file, so
'  clicking one shows nothing whatsoever until the wizard or RetroBat opens.
'  The two .bat files call it too; those still flash their own console for a
'  moment, because every .bat does.
'
'  NO DRIVE LETTER. This file lives in <RetroBat>\_ClaudeWorkspace\wizard\
'  and works out where it is from its own location, the same way
'  system\scripts\wii-nand-launch.vbs does.
'
'  ONE ARGUMENT, OPTIONAL: -Play runs the quiet check-then-launch flow,
'  -Setup runs the once-per-new-computer flow and lands on the Play tab,
'  -Pad opens the full window full screen for a controller.
'  With no argument the full window opens.
'
'  PowerShell is called by its FULL path on purpose. A bare "powershell.exe"
'  fails completely silently when the parent did not hand down a normal PATH,
'  which is the trap that hid a broken save backup here for five days.
' ---------------------------------------------------------------------------

Option Explicit

Dim fso, shell, q, wizardDir, script, ps, mode, cmd

Set fso   = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

q         = Chr(34)
wizardDir = fso.GetParentFolderName(WScript.ScriptFullName)
script    = fso.BuildPath(wizardDir, "SetupWizard.ps1")

mode = ""
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "-play"  Then mode = " -Play"
    If LCase(WScript.Arguments(0)) = "-setup" Then mode = " -Setup"
    ' -pad: sent by PadWatch.ps1 when SELECT + START is pressed on a controller.
    ' The wizard opens full screen, ready for the controller. (2026-09-23)
    If LCase(WScript.Arguments(0)) = "-pad"   Then mode = " -Pad"
    ' -netplay: sent by the friends helper's Join button. (2026-10-12)
    If LCase(WScript.Arguments(0)) = "-netplay" Then mode = " -Tab netplay"
End If

ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
     "\System32\WindowsPowerShell\v1.0\powershell.exe"

' -Command "& 'script' -Play" and not -File, deliberately. Under -File,
' $PSScriptRoot is empty while PowerShell works out parameter defaults, and a
' script that builds a path there dies before it can log anything. That bug
' cost this drive a week of silent backups. This is the exact invocation the
' .bat files have always used and that is known to work.
cmd = q & ps & q & " -NoProfile -ExecutionPolicy Bypass -Command " & _
      q & "& '" & script & "'" & mode & q

' 0 = no window ever created. False = do not wait, so this script exits at
' once and the wizard is not a child of anything the user can close.
shell.Run cmd, 0, False
