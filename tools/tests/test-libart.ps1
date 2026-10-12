# Box art in the wizard's online library (GameLibrary.ps1 Get-LibCatalog, 2026-10-12).
param([string]$Scripts = '/mnt/user-data/outputs/r2/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function A($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'GameLibrary.ps1')
$Ws = Join-Path ([IO.Path]::GetTempPath()) ('la' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory $Ws | Out-Null
$sha = 'a' * 64
$script:json = '{"version":1,"games":[{"id":"one","title":"One","system":"nes","art":"library/art/one.png","files":[{"name":"one.nes","url":"private:one__one.nes","size":3,"sha256":"' + $sha + '"}]},' +
  '{"id":"two","title":"Two","system":"nes","art":"../../evil.png","files":[{"name":"two.nes","url":"private:two__two.nes","size":3,"sha256":"' + $sha + '"}]},' +
  '{"id":"three","title":"Three","system":"snes","files":[{"name":"t.sfc","url":"private:t","size":3,"sha256":"' + $sha + '"}]}]}'
$script:fetched = @(); $script:offline = $false
$script:LibFetchOverride = {
    param($u, $o)
    if ($script:offline) { throw 'offline' }
    $script:fetched += $u
    if ($u -like '*library.json*') { [IO.File]::WriteAllText($o, $script:json) }
    elseif ($u -like '*library/art/one.png*') { [IO.File]::WriteAllBytes($o, [byte[]](137, 80, 78, 71)) }
    else { throw 'no such file' }
}
$c = Get-LibCatalog $Ws
$one = @($c.Games | Where-Object Id -eq 'one')[0]; $two = @($c.Games | Where-Object Id -eq 'two')[0]; $three = @($c.Games | Where-Object Id -eq 'three')[0]
A ($c.Ok -and $one.Art -ne '' -and (Test-Path $one.Art)) 'art fetched and kept'
A ($two.Art -eq '' -and $two.ArtRel -eq '') 'an odd art path is ignored'
A ($three.Art -eq '') 'no art: empty (console picture shows)'
$n1 = @($script:fetched | Where-Object { $_ -like '*art*' }).Count
$c2 = Get-LibCatalog $Ws
A (@($script:fetched | Where-Object { $_ -like '*art*' }).Count -eq $n1) 'second time: from the copy here, not fetched again'
$script:offline = $true
$c3 = Get-LibCatalog $Ws
A ($c3.Ok -and $c3.FromCache -and (@($c3.Games | Where-Object Id -eq 'one')[0]).Art -ne '') 'offline: the copy here still shows'
Remove-Item -Recurse -Force $Ws
Write-Host ("library art tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
