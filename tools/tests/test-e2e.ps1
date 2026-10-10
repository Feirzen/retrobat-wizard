$ErrorActionPreference='Stop'
. /home/claude/work/new/_ClaudeWorkspace/scripts/UpdateEngine.ps1
$m = Read-UpdManifest '/home/claude/retrobat-wizard/manifest.txt'
"manifest ok: $($m.Ok) $($m.Problem) entries=$($m.Entries.Count)"
# the other drive: a copy of the ORIGINAL 2.1 tree
$base = '/tmp/e2e'; if (Test-Path $base) { Remove-Item -Recurse -Force $base }
New-Item -ItemType Directory $base | Out-Null
Copy-Item -Recurse /home/claude/work/orig/_ClaudeWorkspace "$base/_ClaudeWorkspace"
Remove-Item -Recurse -Force "$base/_ClaudeWorkspace/archive"
$ws = "$base/_ClaudeWorkspace"
$script:UpdFetchOverride = {
    param($Url, $OutFile)
    $u = $Url -replace '\?t=\d+$', ''
    $rest = [Uri]::UnescapeDataString($u.Substring('https://raw.githubusercontent.com/Feirzen/retrobat-wizard/'.Length))
    $ref, $path = $rest.Split('/', 2)
    Copy-Item -LiteralPath (Join-Path '/home/claude/retrobat-wizard' $path) -Destination $OutFile -Force
}
$script:UpdRunningOverride = { $false }
"local: " + (Get-UpdLocalVersion $ws)
$st = Invoke-UpdateCheck -Ws $ws -NoDownload; "peek: $($st.state) $($st.version)"
$st = Invoke-UpdateCheck -Ws $ws; "check: $($st.state) files=$($st.files) $($st.message)"
$r = Invoke-UpdateInstall -Ws $ws -NoPostSteps; "install: $($r.Ok) $($r.Message) changed=$($r.Changed) added=$($r.Added)"
"local now: " + (Get-UpdLocalVersion $ws)
"machine folder: " + (Test-Path "$ws/machine/machines") + " profiles gone: " + (-not (Test-Path "$ws/profiles"))
"wizard.ini kept: " + ((Get-Content "$ws/wizard/wizard.ini" -Raw) -match "Steven's RetroBat Wizard")
# compare every code file to the new tree
$bad = 0
foreach ($e in $m.Entries) { if ($e.Kind -eq 'code') { if ((Get-UpdHash (Join-Path $ws $e.Path)) -ne $e.Hash) { $bad++; "MISMATCH $($e.Path)" } } }
"code files not matching manifest: $bad"
$again = Invoke-UpdateCheck -Ws $ws -NoDownload; "after: $($again.state)"
Get-Content "$ws/update/previous/changes.txt" | Select-Object -First 5
$g = Invoke-UpdateGoBack -Ws $ws; "go back: $($g.Ok) $($g.Message)"
"profiles back: " + (Test-Path "$ws/profiles/machines") + "  version: " + (Get-UpdLocalVersion $ws)
# after go back, the drive's files equal the original 2.1 tree?
$diff = 0
Get-ChildItem -Recurse -File /home/claude/work/orig/_ClaudeWorkspace | Where-Object { $_.FullName -notmatch '/archive/' } | ForEach-Object {
  $rel = $_.FullName.Substring('/home/claude/work/orig/_ClaudeWorkspace/'.Length)
  $p = Join-Path $ws $rel
  if (-not (Test-Path -LiteralPath $p)) { $diff++; "missing after go back: $rel" } elseif ((Get-UpdHash $p) -ne (Get-UpdHash $_.FullName)) { $diff++; "differs after go back: $rel" }
}
"files differing from original after go back: $diff"
$extra = Get-ChildItem -Recurse -File $ws | Where-Object { $_.FullName -notmatch '/(update|_SAFE TO DELETE)/' } | Where-Object { -not (Test-Path -LiteralPath (Join-Path /home/claude/work/orig/_ClaudeWorkspace $_.FullName.Substring($ws.Length+1))) }
"extra files left after go back: $(@($extra).Count)"; $extra | Select-Object -First 5 | ForEach-Object FullName
