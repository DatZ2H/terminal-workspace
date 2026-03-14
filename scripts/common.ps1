# Shared constants and helpers -- single source of truth
# Dot-source this from any script that needs WT path or version constants.

# -- Version Constants --
$PythonVersion = "3.12"

# -- WT Settings Path Detection (Store + non-Store) --
# Two modes:
#   "file"   -- returns path only if the file exists (for reading/reporting)
#   "deploy" -- returns path if the parent dir exists (for writing -- file may not exist yet)
function Get-WtSettingsPath {
    param(
        [ValidateSet('file', 'deploy')]
        [string]$Mode = 'file'
    )
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
    )
    if ($Mode -eq 'deploy') {
        $candidates | Where-Object { Test-Path (Split-Path $_ -Parent) } | Select-Object -First 1
    } else {
        $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}

# -- Nerd Font Detection --
# Returns object: Installed, HasV3, HasV2, FontFace
function Get-NerdFontInfo {
    $entries = @()
    foreach ($hive in @('HKCU', 'HKLM')) {
        $reg = Get-ItemProperty "${hive}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
        if ($reg) { $entries += $reg.PSObject.Properties.Name | Where-Object { $_ -match 'CaskaydiaCove' } }
    }
    $hasV3 = [bool]($entries -match 'CaskaydiaCove NF ')
    $hasV2 = [bool]($entries -match 'CaskaydiaCove Nerd Font')
    [PSCustomObject]@{
        Installed = $hasV3 -or $hasV2
        HasV3     = $hasV3
        HasV2     = $hasV2
        FontFace  = if ($hasV3) { 'CaskaydiaCove NF' } elseif ($hasV2) { 'CaskaydiaCove Nerd Font' } else { $null }
    }
}

# -- WT Font Face Repair --
# Fixes stale font name in WT settings.json (v2 <-> v3) via JSON parse. Returns $true if changed.
function Repair-WtFontFace {
    param([string]$WtPath)
    if (-not $WtPath -or -not (Test-Path $WtPath)) { return $false }
    $fi = Get-NerdFontInfo
    if (-not $fi.FontFace) { return $false }
    try {
        $json = Get-Content $WtPath -Raw | ConvertFrom-Json
    } catch { return $false }
    $d = $json.profiles.defaults
    if (-not $d -or -not $d.font -or -not $d.font.face) { return $false }
    if ($d.font.face -eq $fi.FontFace) { return $false }
    $d.font.face = $fi.FontFace
    $json | ConvertTo-Json -Depth 20 | Set-Content $WtPath -Encoding utf8NoBOM
    return $true
}
