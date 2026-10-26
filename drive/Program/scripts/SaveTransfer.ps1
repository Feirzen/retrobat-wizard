<#
    SaveTransfer.ps1 - every save in one file, and back again.

    FUNCTIONS ONLY. Dot-source it. Used by the wizard's Saves page
    (2026-10-17, "save export/import" on Steven's list): take your saves to
    a new setup or a new computer, or hand a friend a copy.

    EXPORT  <RetroBat>\saves, all of it, into one .zip, with a little
            retrobat-saves.txt inside saying what it is. Left out: the Wii
            Menu's own system files (Nintendo's, never to be passed on) and
            emulator caches.
    IMPORT  only a .zip this made. Before anything is replaced, the saves
            here now are packed into _Wizard\Backups\Archive\ the same way,
            so an import can always be undone by importing that file. Then
            every save in the file is put in place, replacing the one here.

    RetroBat must be closed: emulators write saves as they close.
    ASCII ONLY, Windows PowerShell 5.1.
#>

$script:StSkip = @('wii\dolphin-emu\User\Wii\title\00000001\', '\Cache\', '\cache\', '\ShaderCache\', '\shadercache\')
# Installed games, updates and DLC that some consoles keep beside their saves
# (2026-10-25: Steven's Wii U folder held 37,867 files of a game update, so
# the export took over ten minutes). Not saves, never packed. Matched against
# the path inside saves\, with \ between folders.
$script:StSkipRe = @(
    '^wiiu\\cemu\\mlc01\\usr\\title\\',          # Wii U updates and DLC
    '^wiiu\\cemu\\mlc01\\sys\\',                    # Wii U system files
    '^ps3\\rpcs3\\dev_hdd0\\(game|disc|data|tmp)\\', # PS3 installed games
    '^ps3\\rpcs3\\dev_flash',                           # PS3 system files
    '^psvita\\vita3k\\ux0\\(app|patch|addcont)\\',   # Vita installed games
    '\\nand\\system\\', '\\nand\\user\\Contents\\', '\\registered\\',   # Switch system and installed games
    '\\Nintendo 3DS\\.*\\title\\[0-9a-fA-F]{8}\\[0-9a-fA-F]{8}\\content\\'  # 3DS installed games (saves are in ...\data)
)

function Get-StSavesDir([string]$Root) { return [System.IO.Path]::Combine($Root, 'saves') }

function Test-StSkip([string]$Rel) {
    $r = $Rel.Replace('/', '\')
    foreach ($re in $script:StSkipRe) { if ($r -match $re) { return $true } }
    foreach ($s in $script:StSkip) { if (('\' + $r).IndexOf($s, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or $r.StartsWith($s, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

# Packs the saves into $OutFile. Returns @{ Ok; Message; Files; Bytes }.
function Export-RetroBatSaves([string]$Root, [string]$OutFile, [string]$Note = '', $Progress = $null) {
    $src = Get-StSavesDir $Root
    if (-not (Test-Path -LiteralPath $src)) { return @{ Ok = $false; Files = 0; Bytes = 0; Message = 'There is no saves folder in this setup yet.' } }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = $OutFile + '.part'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $n = 0; $bytes = [long]0
    $fs = [System.IO.File]::Open($tmp, 'CreateNew')
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $base = $src.TrimEnd('\', '/')
            # The list first, so the bar can say how far along it is.
            $todo = New-Object System.Collections.ArrayList
            foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                $rel = $f.FullName.Substring($base.Length).TrimStart('\', '/')
                if (-not (Test-StSkip $rel)) { [void]$todo.Add(@($f, $rel)) }
            }
            foreach ($pair in $todo) {
                $f = $pair[0]; $rel = $pair[1]
                if ($null -ne $Progress -and ($n % 25 -eq 0)) { try { & $Progress $n $todo.Count } catch { } }
                # Fastest: saves are small and mostly already packed; the
                # slower setting saved almost no space for a lot more time.
                $entry = $zip.CreateEntry(('saves/' + $rel.Replace('\', '/')), [System.IO.Compression.CompressionLevel]::Fastest)
                $entry.LastWriteTime = $f.LastWriteTime
                $es = $entry.Open()
                try { $in = [System.IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite'); try { $in.CopyTo($es) } finally { $in.Close() } } finally { $es.Close() }
                $n++; $bytes += $f.Length
            }
            $info = $zip.CreateEntry('retrobat-saves.txt')
            $w = New-Object System.IO.StreamWriter($info.Open())
            try {
                $w.WriteLine('RetroBat saves, packed by the RetroBat Wizard. Bring them back with: wizard, Saves, Import saves.')
                $w.WriteLine('made = ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
                $w.WriteLine('files = ' + $n)
                if ($Note -ne '') { $w.WriteLine('note = ' + $Note) }
            } finally { $w.Close() }
        } finally { $zip.Dispose() }
    } finally { $fs.Close() }
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    Move-Item -LiteralPath $tmp -Destination $OutFile
    return @{ Ok = $true; Files = $n; Bytes = $bytes; Message = ("Packed {0} save file(s) into {1}." -f $n, [System.IO.Path]::GetFileName($OutFile)) }
}

# Puts the saves from a file made by Export-RetroBatSaves in place. Returns
# @{ Ok; Message; Files; Undo } (Undo = the safety copy of what was here).
function Import-RetroBatSaves([string]$Root, [string]$Ws, [string]$ZipFile) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $ZipFile)) { return @{ Ok = $false; Files = 0; Undo = ''; Message = 'That file is not there.' } }
    $zip = $null
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipFile) } catch { return @{ Ok = $false; Files = 0; Undo = ''; Message = 'That is not a saves file (it would not open as a .zip).' } }
    try {
        if ($null -eq $zip.GetEntry('retrobat-saves.txt')) { return @{ Ok = $false; Files = 0; Undo = ''; Message = 'That .zip was not made by the wizard''s Export saves, so nothing was changed.' } }
        # safety copy of what is here now
        $arch = [System.IO.Path]::Combine($Ws, 'Backups', 'Archive')
        if (-not (Test-Path -LiteralPath $arch)) { [void](New-Item -ItemType Directory -Path $arch -Force) }
        $undo = [System.IO.Path]::Combine($arch, ('saves-before-import_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.zip'))
        if (Test-Path -LiteralPath (Get-StSavesDir $Root)) {
            $b = Export-RetroBatSaves $Root $undo 'the saves that were here before an import'
            if (-not $b.Ok) { return @{ Ok = $false; Files = 0; Undo = ''; Message = 'The safety copy could not be made, so nothing was changed.' } }
        } else { $undo = '' }
        $dest = (Get-StSavesDir $Root).TrimEnd('\', '/')
        $n = 0
        foreach ($e in $zip.Entries) {
            $name = [string]$e.FullName
            if (-not $name.StartsWith('saves/') -or $name.EndsWith('/')) { continue }
            $rel = $name.Substring(6)
            if ($rel -match '(^|/)\.\.(/|$)' -or $rel -match '^[A-Za-z]:' -or $rel.StartsWith('/')) { continue }   # never outside saves
            if (Test-StSkip $rel) { continue }
            $to = [System.IO.Path]::Combine($dest, $rel.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            $dir = [System.IO.Path]::GetDirectoryName($to)
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            $in = $e.Open()
            try { $out = [System.IO.File]::Create($to); try { $in.CopyTo($out) } finally { $out.Close() } } finally { $in.Close() }
            try { [System.IO.File]::SetLastWriteTime($to, $e.LastWriteTime.DateTime) } catch { }
            $n++
        }
        $msg = ("Done: {0} save file(s) put in place." -f $n)
        if ($undo -ne '') { $msg += (" The saves that were here before are kept in _Wizard\Backups\Archive\{0}; importing that file puts them back." -f [System.IO.Path]::GetFileName($undo)) }
        return @{ Ok = $true; Files = $n; Undo = $undo; Message = $msg }
    }
    finally { $zip.Dispose() }
}
