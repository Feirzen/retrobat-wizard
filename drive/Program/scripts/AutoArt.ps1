<#
    AutoArt.ps1 - box art, by itself, for games that have no pictures at all.

    Steven, 2026-11-04: "automatically scrape for any games missing ALL media?
    Not missing ANY, but ALL? That way friends dont have to bother learning
    how to do that."

    RetroBat cannot be told to scrape from outside (no command for it, and
    its web control has no scrape call), and ScreenScraper wants a developer
    key the wizard does not have. So this uses the libretro thumbnails: free
    box art on GitHub, named after the No-Intro file names most game files
    already have ("Metroid Fusion (USA).zip" -> "Metroid Fusion (USA).png").

    WHICH GAMES: a game file in a console folder with NO picture of any kind:
    nothing in its gamelist.xml entry (image, thumbnail, marquee, video and the
    rest), or no entry at all. A game with even one picture is never touched.

    TWO HALVES, because RetroBat rewrites its game lists when it closes:
      Invoke-AutoArtFetch   downloads the pictures into roms\<console>\images\
                            as "<file name>-thumb.png". Any time; it never
                            opens a game list. Run hidden by PLAY and by the
                            wizard (Start-AutoArt), at most once a day.
      Sync-AutoArt          puts the pictures it fetched into the game lists.
                            Only while RetroBat is closed: at PLAY, and at the
                            end of a fetch when RetroBat is not running.
    A game whose picture was not found is tried again after a week.
    Switched by 'autoart' in features.ini (off unless it says on; 3.3.1).

    FUNCTIONS ONLY. Dot-source it (no param block on purpose: the wizard
    dot-sources it, and one would overwrite the wizard's own $Root).
    The hidden run is Invoke-AutoArtRun, started by Start-AutoArt.
    ASCII ONLY, Windows PowerShell 5.1.
#>

$script:AaRepos = @{
    nes = 'Nintendo_-_Nintendo_Entertainment_System'; fds = 'Nintendo_-_Family_Computer_Disk_System'
    snes = 'Nintendo_-_Super_Nintendo_Entertainment_System'; n64 = 'Nintendo_-_Nintendo_64'
    gb = 'Nintendo_-_Game_Boy'; gbc = 'Nintendo_-_Game_Boy_Color'; gba = 'Nintendo_-_Game_Boy_Advance'
    nds = 'Nintendo_-_Nintendo_DS'; '3ds' = 'Nintendo_-_Nintendo_3DS'; virtualboy = 'Nintendo_-_Virtual_Boy'
    gamecube = 'Nintendo_-_GameCube'; wii = 'Nintendo_-_Wii'; wiiu = 'Nintendo_-_Wii_U'
    psx = 'Sony_-_PlayStation'; ps2 = 'Sony_-_PlayStation_2'; ps3 = 'Sony_-_PlayStation_3'; psp = 'Sony_-_PlayStation_Portable'
    megadrive = 'Sega_-_Mega_Drive_-_Genesis'; genesis = 'Sega_-_Mega_Drive_-_Genesis'; mastersystem = 'Sega_-_Master_System_-_Mark_III'
    gamegear = 'Sega_-_Game_Gear'; segacd = 'Sega_-_Mega-CD_-_Sega_CD'; sega32x = 'Sega_-_32X'; saturn = 'Sega_-_Saturn'; dreamcast = 'Sega_-_Dreamcast'
    xbox = 'Microsoft_-_Xbox'; xbox360 = 'Microsoft_-_Xbox_360'
    pcengine = 'NEC_-_PC_Engine_-_TurboGrafx_16'; atari2600 = 'Atari_-_2600'; lynx = 'Atari_-_Lynx'; ngp = 'SNK_-_Neo_Geo_Pocket'; ngpc = 'SNK_-_Neo_Geo_Pocket_Color'
}
# Every gamelist tag that is a picture or a video: a game with any of them is left alone.
$script:AaMediaTags = @('image', 'thumbnail', 'marquee', 'video', 'fanart', 'titleshot', 'boxback', 'boxart', 'wheel', 'cartridge', 'mix', 'map', 'bezel')

function Join-AaPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

# OFF unless features.ini says "autoart = on" (3.3.1, Steven: RetroBat's own
# ScreenScraper tool is the first choice; this is for whoever ticks it).
function Test-AaOn([string]$Root) {
    $f = Join-AaPath $Root '_Wizard\Settings\features.ini'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) { if ($l -match '^\s*autoart\s*=\s*(on|true|yes|1)\b') { return $true } }
    return $false
}

function Test-AaRetroBatOpen {
    return (@(Get-Process -Name 'emulationstation', 'retrobat' -ErrorAction SilentlyContinue).Count -gt 0)
}

# Each console folder's game file extensions, from RetroBat's es_systems.cfg.
function Get-AaExtensions([string]$Root) {
    $out = @{}
    $cfg = Join-AaPath $Root 'emulationstation\.emulationstation\es_systems.cfg'
    if (-not (Test-Path -LiteralPath $cfg)) { return $out }
    try { [xml]$x = [System.IO.File]::ReadAllText($cfg) } catch { return $out }
    foreach ($s in @($x.SelectNodes('/systemList/system'))) {
        $n = ([string]$s.name).Trim().ToLower()
        if (-not $script:AaRepos.ContainsKey($n)) { continue }
        $out[$n] = @(([string]$s.extension).Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -ne '' -and $_ -ne '.m3u' })
    }
    return $out
}

# The games with no pictures at all: @( @{ Sys; Dir; File; Base; Art } ).
function Get-AutoArtMissing([string]$Root) {
    $out = New-Object System.Collections.ArrayList
    $exts = Get-AaExtensions $Root
    foreach ($sys in @($exts.Keys | Sort-Object)) {
        $dir = Join-AaPath $Root ('roms\' + $sys)
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $has = @{}
        $gl = Join-AaPath $dir 'gamelist.xml'
        if (Test-Path -LiteralPath $gl) {
            try {
                [xml]$x = [System.IO.File]::ReadAllText($gl)
                foreach ($g in @($x.SelectNodes('/gameList/game'))) {
                    $pn = $g.SelectSingleNode('path'); if ($null -eq $pn) { continue }
                    $p = (([string]$pn.InnerText).Trim() -replace '\\', '/') -replace '^\./', ''
                    $any = $false
                    foreach ($t in $script:AaMediaTags) { $n = $g.SelectSingleNode($t); if ($null -ne $n -and ([string]$n.InnerText).Trim() -ne '') { $any = $true; break } }
                    $has[$p.ToLower()] = $any
                }
            } catch { continue }   # a game list that cannot be read is left alone
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($exts[$sys] -notcontains $f.Extension.ToLower()) { continue }
            $k = $f.Name.ToLower()
            if ($has.ContainsKey($k) -and $has[$k]) { continue }
            [void]$out.Add([pscustomobject]@{ Sys = $sys; Dir = $dir; File = $f.Name; Base = $f.BaseName
                                              Art = (Join-AaPath $dir ('images\' + $f.BaseName + '-thumb.png')) })
        }
    }
    return @($out)
}

# The names to try for one game: its own file name, then the same title with
# the commonest regions, for a file whose tags are a little different.
function Get-AaNames([string]$Base) {
    $clean = { param($s) $s -replace '[&\*/:`<>\?\\\|"]', '_' }
    $names = @(& $clean $Base)
    $i = $Base.IndexOf(' (')
    if ($i -gt 0) {
        $title = $Base.Substring(0, $i)
        foreach ($r in @('(USA)', '(USA, Europe)', '(World)', '(USA, Australia)', '(Europe)')) { $names += (& $clean ($title + ' ' + $r)) }
    }
    return @($names | Select-Object -Unique)
}

# Downloads the missing box art, 8 at a time. Returns @{ Found; Missed; Tried }.
function Invoke-AutoArtFetch([string]$Root, [string]$Ws) {
    $res = @{ Found = 0; Missed = 0; Tried = 0 }
    $cache = Join-AaPath $Ws 'Cache\autoart'
    if (-not (Test-Path -LiteralPath $cache)) { [void](New-Item -ItemType Directory -Path $cache -Force) }
    # games looked for in the last week and not found: not asked for again yet
    $triedF = Join-AaPath $cache 'not-found.txt'
    $tried = @{}
    if (Test-Path -LiteralPath $triedF) {
        foreach ($l in [System.IO.File]::ReadAllLines($triedF)) { $p = $l.Split('|'); if ($p.Count -eq 3) { $d = [DateTime]::MinValue; if ([DateTime]::TryParse($p[0], [ref]$d) -and $d -gt (Get-Date).AddDays(-7)) { $tried[($p[1] + '|' + $p[2]).ToLower()] = $p[0] } } }
    }
    $todo = @(Get-AutoArtMissing $Root | Where-Object { -not (Test-Path -LiteralPath $_.Art) -and -not $tried.ContainsKey(($_.Sys + '|' + $_.File).ToLower()) })
    if ($todo.Count -eq 0) { return $res }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(45)
    [void]$client.DefaultRequestHeaders.UserAgent.TryParseAdd('RetroBat-Wizard')
    try {
        for ($i = 0; $i -lt $todo.Count; $i += 8) {
            $batch = @($todo[$i..([Math]::Min($i + 7, $todo.Count - 1))])
            $left = @($batch)
            # the game's own name first, then each fallback name, for the ones still missing
            for ($try = 0; $try -lt 6 -and $left.Count -gt 0; $try++) {
                $ask = @($left | ForEach-Object { $n = @(Get-AaNames $_.Base); if ($try -lt $n.Count) { $_ } })
                if ($ask.Count -eq 0) { break }
                $tasks = @($ask | ForEach-Object {
                    $n = @(Get-AaNames $_.Base)[$try]
                    $client.GetAsync(('https://raw.githubusercontent.com/libretro-thumbnails/{0}/master/Named_Boxarts/{1}.png' -f $script:AaRepos[$_.Sys], [Uri]::EscapeDataString($n)))
                })
                try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks, 60000) } catch { }
                $still = @()
                for ($k = 0; $k -lt $ask.Count; $k++) {
                    $ok = $false
                    try {
                        $t = $tasks[$k]
                        if ($t.Status -eq 'RanToCompletion' -and $t.Result.IsSuccessStatusCode) {
                            $bytes = $t.Result.Content.ReadAsByteArrayAsync().Result
                            # a real PNG, and not something huge
                            if ($bytes.Length -gt 100 -and $bytes.Length -le 5MB -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) {
                                $imgDir = Split-Path $ask[$k].Art -Parent
                                if (-not (Test-Path -LiteralPath $imgDir)) { [void](New-Item -ItemType Directory -Path $imgDir -Force) }
                                $part = $ask[$k].Art + '.part'
                                [System.IO.File]::WriteAllBytes($part, $bytes)
                                Move-Item -LiteralPath $part -Destination $ask[$k].Art -Force
                                $ok = $true; $res.Found++
                            }
                        }
                    } catch { }
                    if (-not $ok) { $still += $ask[$k] }
                }
                $left = @($left | Where-Object { $still -contains $_ })
            }
            foreach ($m in $left) { $tried[($m.Sys + '|' + $m.File).ToLower()] = (Get-Date -Format 's'); $res.Missed++ }
            $res.Tried += $batch.Count
        }
    }
    finally { $client.Dispose() }
    $lines = @($tried.Keys | ForEach-Object { $p = $_.Split('|', 2); '{0}|{1}|{2}' -f $tried[$_], $p[0], $p[1] })
    try { [System.IO.File]::WriteAllLines($triedF, [string[]]$lines) } catch { }
    return $res
}

# Puts the fetched box art into the game lists: the game's entry gets it as
# its thumbnail and image, and a game with no entry gets one. Only games that
# still have no picture at all. RetroBat must be closed. Returns how many.
function Sync-AutoArt([string]$Root, [string]$Ws) {
    if (Test-AaRetroBatOpen) { return 0 }
    $ready = @(Get-AutoArtMissing $Root | Where-Object { Test-Path -LiteralPath $_.Art })
    if ($ready.Count -eq 0) { return 0 }
    $done = 0
    $bak = Join-AaPath $Ws ('Backups\Archive\autoart_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($grp in @($ready | Group-Object Sys)) {
        $dir = $grp.Group[0].Dir
        $gl = Join-AaPath $dir 'gamelist.xml'
        try {
            if (Test-Path -LiteralPath $gl) {
                [xml]$x = [System.IO.File]::ReadAllText($gl)
                if (-not (Test-Path -LiteralPath $bak)) { [void](New-Item -ItemType Directory -Path $bak -Force) }
                Copy-Item -LiteralPath $gl -Destination (Join-AaPath $bak ($grp.Name + '-gamelist.xml')) -Force
            }
            else { $x = New-Object System.Xml.XmlDocument; [void]$x.AppendChild($x.CreateXmlDeclaration('1.0', $null, $null)); [void]$x.AppendChild($x.CreateElement('gameList')) }
            $list = $x.SelectSingleNode('/gameList')
            if ($null -eq $list) { continue }
            foreach ($m in $grp.Group) {
                $g = $null
                foreach ($c in @($x.SelectNodes('/gameList/game'))) {
                    $pn = $c.SelectSingleNode('path')
                    if ($null -ne $pn -and ((([string]$pn.InnerText).Trim() -replace '\\', '/') -replace '^\./', '').ToLower() -eq $m.File.ToLower()) { $g = $c; break }
                }
                if ($null -eq $g) {
                    $g = $x.CreateElement('game')
                    $p = $x.CreateElement('path'); $p.InnerText = './' + $m.File; [void]$g.AppendChild($p)
                    $nm = $m.Base; $i = $nm.IndexOf(' ('); if ($i -gt 0) { $nm = $nm.Substring(0, $i) }
                    $n = $x.CreateElement('name'); $n.InnerText = $nm; [void]$g.AppendChild($n)
                    [void]$list.AppendChild($g)
                }
                $rel = './images/' + [System.IO.Path]::GetFileName($m.Art)
                foreach ($t in @('thumbnail', 'image')) {
                    $e = $g.SelectSingleNode($t)
                    if ($null -eq $e) { $e = $x.CreateElement($t); [void]$g.AppendChild($e) }
                    $e.InnerText = $rel
                }
                $done++
            }
            $set = New-Object System.Xml.XmlWriterSettings
            $set.Indent = $true; $set.IndentChars = "`t"; $set.Encoding = $utf8
            $tmp = $gl + '.autoart-tmp'
            $w = [System.Xml.XmlWriter]::Create($tmp, $set)
            try { $x.Save($w) } finally { $w.Close() }
            Move-Item -LiteralPath $tmp -Destination $gl -Force
        }
        catch { }
    }
    return $done
}

# Starts the hidden fetch, at most once every 20 hours. Returns $true when it started.
function Start-AutoArt([string]$Root, [string]$Ws, [switch]$Force) {
    if (-not (Test-AaOn $Root)) { return $false }
    $mark = Join-AaPath $Ws 'Cache\autoart\last-run.txt'
    if (-not $Force -and (Test-Path -LiteralPath $mark) -and (((Get-Date) - (Get-Item -LiteralPath $mark).LastWriteTime).TotalHours -lt 20)) { return $false }
    $me = Join-AaPath $Ws 'Program\scripts\AutoArt.ps1'
    if (-not (Test-Path -LiteralPath $me)) { return $false }
    $ps = Join-AaPath $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cmd = ". '{0}'; Invoke-AutoArtRun '{1}'" -f $me.Replace("'", "''"), $Root.Replace("'", "''")
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', ('"' + $cmd + '"')) -WorkingDirectory $env:TEMP
    return $true
}

# --- the hidden run ----------------------------------------------------------
function Invoke-AutoArtRun([string]$Root) {
    if ($Root -eq '') { return }
    $Ws = Join-AaPath $Root '_Wizard'
    $log = Join-AaPath $Ws 'Cache\logs\wizard.log'
    $say = { param($m) try { Add-Content -LiteralPath $log -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) } catch { } }
    if (-not (Test-AaOn $Root)) { return }
    $cache = Join-AaPath $Ws 'Cache\autoart'
    if (-not (Test-Path -LiteralPath $cache)) { [void](New-Item -ItemType Directory -Path $cache -Force) }
    # one at a time: a second run while one is going just stops
    $lock = $null
    try { $lock = [System.IO.File]::Open((Join-AaPath $cache 'run.lock'), 'OpenOrCreate', 'ReadWrite', 'None') } catch { return }
    try {
        [System.IO.File]::WriteAllText((Join-AaPath $cache 'last-run.txt'), (Get-Date -Format 's'))
        $r = Invoke-AutoArtFetch $Root $Ws
        if ($r.Tried -gt 0) { & $say ('box art: {0} found, {1} not found yet, of {2} game(s) with no pictures' -f $r.Found, $r.Missed, $r.Tried) }
        $n = Sync-AutoArt $Root $Ws
        if ($n -gt 0) { & $say ('box art: put in the game lists for {0} game(s)' -f $n) }
    }
    catch { & $say ('box art: ' + $_.Exception.Message) }
    finally { try { $lock.Close() } catch { } }
}
