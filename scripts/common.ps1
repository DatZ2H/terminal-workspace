# Shared constants and helpers -- single source of truth
# Dot-source this from any script that needs WT path or version constants.

# -- Version Constants --
$PythonVersion = "3.12"

# -- Shared Path Constants --
$MaxBackups      = 3
$OmpThemesLocal  = Join-Path $env:USERPROFILE ".oh-my-posh\themes"
$PsProfileDir    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell"
$PsProfilePath   = Join-Path $PsProfileDir "Microsoft.PowerShell_profile.ps1"

# -- WT Settings Path Detection (Store + non-Store) --
# Two modes:
#   "file"   -- returns path only if the file exists (for reading/reporting)
#   "deploy" -- returns path if the parent dir exists (for writing -- file may not exist yet)
function Get-WtSettingsPath {
    [CmdletBinding()]
    param(
        [ValidateSet('file', 'deploy')]
        [string]$Mode = 'file'
    )
    if (-not $env:LOCALAPPDATA) { return $null }
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
    [CmdletBinding()]
    param()
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
# Optional -WtJson and -FontInfo params accept pre-parsed data to avoid redundant I/O.
function Repair-WtFontFace {
    [CmdletBinding()]
    param(
        [string]$WtPath,
        [object]$WtJson,
        [object]$FontInfo
    )
    if (-not $WtPath -or -not (Test-Path $WtPath)) { return $false }
    $fi = if ($FontInfo) { $FontInfo } else { Get-NerdFontInfo }
    if (-not $fi.FontFace) { return $false }
    try {
        $json = if ($WtJson) { $WtJson } else { Get-Content $WtPath -Raw | ConvertFrom-Json }
    } catch { return $false }
    $d = $json.profiles.defaults
    if (-not $d -or -not $d.font -or -not $d.font.face) { return $false }
    if ($d.font.face -eq $fi.FontFace) { return $false }
    $d.font.face = $fi.FontFace
    $tempPath = "$WtPath.pnx-tmp"
    $json | ConvertTo-Json -Depth 20 | Set-Content $tempPath -Encoding utf8NoBOM
    try {
        Move-Item $tempPath $WtPath -Force -ErrorAction Stop
    } catch {
        # Fallback: direct write if Move-Item fails
        $json | ConvertTo-Json -Depth 20 | Set-Content $WtPath -Encoding utf8NoBOM
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
    return $true
}

# -- Atomic WT Settings Writer --
# Backup + temp file + Move-Item with retry + fallback Set-Content
# Returns $true on success, $false on failure
function Save-WtSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Json,
        [Parameter(Mandatory)][string]$WtPath
    )
    # Backup
    Copy-Item $WtPath "$WtPath.pnx-backup" -Force -ErrorAction SilentlyContinue
    # Write to temp file
    $tempPath = "$WtPath.pnx-tmp"
    $Json | ConvertTo-Json -Depth 20 | Set-Content $tempPath -Encoding utf8NoBOM
    # Try Move-Item with retry (WT may hold file lock briefly)
    for ($retry = 0; $retry -lt 3; $retry++) {
        try {
            Move-Item $tempPath $WtPath -Force -ErrorAction Stop
            return $true
        } catch { Start-Sleep -Milliseconds 200 }
    }
    # Last resort: direct write (non-atomic but better than silent failure)
    try {
        $Json | ConvertTo-Json -Depth 20 | Set-Content $WtPath -Encoding utf8NoBOM
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# -- Init Cache Infrastructure --
# Caches output of slow external processes (oh-my-posh init, zoxide init) to disk.
# Cache is invalidated when the executable or config changes (via VersionKey|ExtraKey).
$PnxCacheDir = Join-Path $env:LOCALAPPDATA "pnx-terminal\cache"

function Get-PnxCachedInit {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$VersionKey,
        [string]$ExtraKey
    )
    $cacheFile = Join-Path $PnxCacheDir "$Name.ps1"
    $metaFile  = Join-Path $PnxCacheDir "$Name.meta"
    if (-not (Test-Path $cacheFile) -or -not (Test-Path $metaFile)) { return $null }
    $expected = "$VersionKey|$ExtraKey"
    $stored = Get-Content $metaFile -Raw -ErrorAction SilentlyContinue
    if ($stored -and $stored.Trim() -eq $expected) {
        return (Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue)
    }
    return $null
}

function Save-PnxCachedInit {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$VersionKey,
        [string]$ExtraKey,
        [string]$Content
    )
    if (-not (Test-Path $PnxCacheDir)) {
        New-Item -ItemType Directory -Path $PnxCacheDir -Force | Out-Null
    }
    $Content | Set-Content (Join-Path $PnxCacheDir "$Name.ps1") -Encoding utf8NoBOM
    "$VersionKey|$ExtraKey" | Set-Content (Join-Path $PnxCacheDir "$Name.meta") -Encoding utf8NoBOM
}

function Clear-PnxCache {
    [CmdletBinding()]
    param()
    if (Test-Path $PnxCacheDir) {
        Remove-Item "$PnxCacheDir\*" -Force -ErrorAction SilentlyContinue
    }
}

# -- Deduplicated pnx marker injection (used by bootstrap + sync-from-repo) --
# Ensures pnxTheme/pnxStyle markers exist in WT settings and fixes font face.
# Returns $true if any changes were made (caller should write JSON back to disk).
function Initialize-WtPnxMarkers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$WtJson,
        [string]$DefaultTheme = 'pro',
        [string]$DefaultStyle = 'mac'
    )
    $changed = $false
    if (-not $WtJson.profiles.defaults) {
        $WtJson.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $d = $WtJson.profiles.defaults
    if (-not $d.PSObject.Properties['pnxTheme']) {
        $d | Add-Member -NotePropertyName pnxTheme -NotePropertyValue $DefaultTheme
        $changed = $true
    }
    if (-not $d.PSObject.Properties['pnxStyle']) {
        $d | Add-Member -NotePropertyName pnxStyle -NotePropertyValue $DefaultStyle
        $changed = $true
    }
    # Fix font face if needed
    if ($d.font -and $d.font.face) {
        $fi = Get-NerdFontInfo
        if ($fi.FontFace -and $d.font.face -ne $fi.FontFace) {
            $d.font.face = $fi.FontFace
            $changed = $true
        }
    }
    return $changed
}
