# Keep library uploads going when the wizard closes

Flag: fmvio9zbk. Built on 3.1 dev build 4 (commit c89b0e6).

## What it does
- Closing the wizard (X, or PLAY, which closes it first) while games are uploading
  now asks: **Keep uploading** or **Stop the upload and close**.
- Keep uploading drops the wizard to the taskbar; the upload finishes while you play.
- While it's in the taskbar, the "done" pop-up is skipped so it can't jump in front
  of a game. The result shows on the Admin page.

Why: uploads run in their own runspace and aren't counted in `$script:busyDepth`,
so the existing "still working" check never saw them.

## Edit 1 of 2: `_ClaudeWorkspace\wizard\SetupWizard.ps1`

Find the `Add_Closing` handler. Find this:

```powershell
                else { Log ("closed while still working on: {0}" -f $script:busyLabel) }
            }
        } catch { }
    })
```

Replace with:

```powershell
                else { Log ("closed while still working on: {0}" -f $script:busyLabel) }
            }
            # A library upload runs in its own runspace and is not counted in
            # busyDepth, so closing (X, or PLAY, which closes first) used to end
            # it without a word. Offer to keep the wizard down in the taskbar
            # until it finishes instead (Steven, 2026-10-21).
            elseif ($null -ne $script:adminLibJob -and -not $script:adminLibJob.Handle.IsCompleted) {
                $pick = Show-Choice $WizardName ("Games are still uploading to the online library ({0}).`n`nClosing the wizard stops the upload. Keep it running in the taskbar and it finishes by itself, even while you play." -f $script:adminLibJob.Title) @('Keep uploading', 'Stop the upload and close')
                if ($pick -ne 'Stop the upload and close') {
                    $e2.Cancel = $true
                    try { $script:win.WindowState = 'Minimized' } catch { }
                    Log ("kept open in the taskbar: still uploading {0}" -f $script:adminLibJob.Title)
                }
                else { Log ("closed while uploading: {0}" -f $script:adminLibJob.Title) }
            }
        } catch { }
    })
```

## Edit 2 of 2: `_ClaudeWorkspace\scripts\AdminUI.ps1`

In `Invoke-AdminPublishTick`, find this:

```powershell
        Render-Admin
        [void](Show-Choice $WizardName $r.Message @('OK'))
    } catch { Log "admin: publish tick - $_" }
```

Replace with:

```powershell
        Render-Admin
        # Kept in the taskbar so the upload could finish (see Add_Closing): no
        # pop-up that could jump in front of a game. The note is on the Admin page.
        $down = $false; try { $down = ([string]$script:win.WindowState -eq 'Minimized') } catch { }
        if (-not $down) { [void](Show-Choice $WizardName $r.Message @('OK')) }
    } catch { Log "admin: publish tick - $_" }
```

## Try it on the PC
1. Admin tab, Publish games, start a big one.
2. Press PLAY. The question should pop up. Pick Keep uploading.
3. The wizard drops to the taskbar and RetroBat opens. When the upload is done, no
   pop-up appears; open the wizard and the Admin page shows the result.
4. Start another upload, press X, pick Stop the upload and close. The wizard closes.

Both files stay plain ASCII (Windows PowerShell reads them as ANSI). Both parsed
cleanly in PowerShell 7 in the cloud; not yet run on Windows.
