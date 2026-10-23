<#
    WiiMenu.ps1 - puts a person's OWN Wii system files (the "NAND") where
    RetroBat's Dolphin looks for them, so Wii games start at the real Wii Menu.

    FUNCTIONS ONLY. Dot-source it. Used by the wizard's Settings > This setup
    page, "Wii Menu" (Steven, 2026-10-17: "an easy spot where someone can
    click and it will ask them for a NAND file ... they can do it themselves
    and it will copy my setup for them").

    WHY IT IS NOT SHIPPED: the Wii Menu is Nintendo's own system software. It
    cannot be shared, so each person brings the copy from their own Wii (or
    their own Dolphin). Everything else - the launch wrapper, the Wii Menu
    switch in features.ini - is already in place on every setup, so once the
    files are there, Wii games go through the Wii Menu by themselves.

    WHERE: <RetroBat>\saves\wii\dolphin-emu\User\Wii, the folder RetroBat
    hands Dolphin. The same place system\scripts\wii-nand-launch.vbs and
    Restore-ProtectedFiles.ps1 look for the Wii Menu.

    NOTHING IS OVERWRITTEN. Only files that are not there yet are copied, so
    Wii saves already on this setup are never replaced by older ones.

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Get-WiiNandDir([string]$Root) {
    return [System.IO.Path]::Combine($Root, 'saves', 'wii', 'dolphin-emu', 'User', 'Wii')
}

function Get-WiiMenuTmd([string]$NandDir) {
    return [System.IO.Path]::Combine($NandDir, 'title', '00000001', '00000002', 'content', 'title.tmd')
}

# Is the Wii Menu on this setup?
function Test-WiiMenuInstalled([string]$Root) {
    return (Test-Path -LiteralPath (Get-WiiMenuTmd (Get-WiiNandDir $Root)))
}

# The folder that IS the Wii NAND, starting from whatever was picked: the
# Wii folder itself, or a folder above it (a Dolphin "User" folder, a whole
# Dolphin folder, a backup folder). '' when there is no Wii Menu in it.
function Find-WiiNandRoot([string]$Picked) {
    if ([string]::IsNullOrWhiteSpace($Picked) -or -not (Test-Path -LiteralPath $Picked)) { return '' }
    foreach ($rel in @('', 'Wii', 'User\Wii', 'Dolphin Emulator\Wii', 'dolphin-emu\User\Wii')) {
        $cand = $Picked
        foreach ($seg in ($rel -split '\\')) { if ($seg -ne '') { $cand = [System.IO.Path]::Combine($cand, $seg) } }
        if (Test-Path -LiteralPath (Get-WiiMenuTmd $cand)) { return $cand }
    }
    return ''
}

# Copies the Wii files in. Returns @{ Ok; Message; Copied }.
function Import-WiiNand([string]$Root, [string]$Picked) {
    $src = Find-WiiNandRoot $Picked
    if ($src -eq '') {
        return @{ Ok = $false; Copied = 0; Message = "There is no Wii Menu in that folder.`n`nPick the Wii folder from your own Dolphin (Dolphin: File > Open User Folder, then the Wii folder inside), or a folder that has it inside." }
    }
    $dst = Get-WiiNandDir $Root
    if ([System.IO.Path]::GetFullPath($src).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($dst).TrimEnd('\')) {
        return @{ Ok = $true; Copied = 0; Message = 'Those are already the Wii files this setup uses.' }
    }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($src.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $to = [System.IO.Path]::Combine($dst, $rel)
        if (Test-Path -LiteralPath $to) { continue }
        $dir = [System.IO.Path]::GetDirectoryName($to)
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        Copy-Item -LiteralPath $f.FullName -Destination $to
        $n++
    }
    if (-not (Test-Path -LiteralPath (Get-WiiMenuTmd $dst))) {
        return @{ Ok = $false; Copied = $n; Message = 'The files were copied, but the Wii Menu still is not where Dolphin looks. Nothing else was changed.' }
    }
    return @{ Ok = $true; Copied = $n; Message = ("Done: {0} file(s) copied. Wii games now start at the Wii Menu, like a real Wii. (Saves that were already here were left alone.)" -f $n) }
}
