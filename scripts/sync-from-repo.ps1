#Requires -Version 7.0
# Copy config files from this repo to local system (with backup)

$RepoRoot = Split-Path $PSScriptRoot -Parent
$MaxBackups = 3

$PsProfileLocal = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$OmpThemesLocal = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

. "$PSScriptRoot\common.ps1"
$WtSettingsLocal = Get-WtSettingsPath -Mode deploy

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "`n  Syncing: repo -> local" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

# Profile
$repoProfile = "$RepoRoot\configs\profile.ps1"
if (Test-Path $repoProfile) {
    $profileDir = Split-Path $PsProfileLocal -Parent
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    if (Test-Path $PsProfileLocal) {
        Copy-Item $PsProfileLocal "$PsProfileLocal.backup-$timestamp"
        Write-Host "  Profile backup   created" -ForegroundColor DarkGray
        # Cleanup old backups (keep last N)
        Get-ChildItem (Split-Path $PsProfileLocal -Parent) -Filter "Microsoft.PowerShell_profile.ps1.backup-*" |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups | Remove-Item -Force
    }
    Copy-Item $repoProfile $PsProfileLocal -Force
    Write-Host "  Profile          OK" -ForegroundColor Green
} else {
    Write-Host "  Profile          NOT IN REPO" -ForegroundColor Red
}

# WT Settings
$repoWt = "$RepoRoot\configs\terminal-settings.json"
if ($WtSettingsLocal -and (Test-Path $repoWt)) {
    if (Test-Path $WtSettingsLocal) {
        Copy-Item $WtSettingsLocal "$WtSettingsLocal.backup-$timestamp"
        Write-Host "  WT backup        created" -ForegroundColor DarkGray
        # Cleanup old backups (keep last N)
        Get-ChildItem (Split-Path $WtSettingsLocal -Parent) -Filter "settings.json.backup-*" |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups | Remove-Item -Force
    }
    Copy-Item $repoWt $WtSettingsLocal -Force
    # Post-deploy: inject pnx markers + fix font name (same as bootstrap)
    try {
        $wtJson = Get-Content $WtSettingsLocal -Raw | ConvertFrom-Json
        if ($wtJson.profiles.defaults) {
            $d = $wtJson.profiles.defaults
            $needsWrite = $false
            if (-not $d.PSObject.Properties['pnxTheme']) {
                $d | Add-Member -NotePropertyName pnxTheme -NotePropertyValue 'pro'
                $needsWrite = $true
            }
            if (-not $d.PSObject.Properties['pnxStyle']) {
                $d | Add-Member -NotePropertyName pnxStyle -NotePropertyValue 'mac'
                $needsWrite = $true
            }
            if ($d.font -and $d.font.face) {
                $fi = Get-NerdFontInfo
                if ($fi.FontFace -and $d.font.face -ne $fi.FontFace) {
                    $d.font.face = $fi.FontFace
                    $needsWrite = $true
                }
            }
            if ($needsWrite) {
                $wtJson | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsLocal -Encoding utf8NoBOM
            }
        }
        Write-Host "  WT Settings      OK" -ForegroundColor Green
    } catch {
        Write-Host "  WT Settings      WARNING: JSON marker processing failed: $_" -ForegroundColor Yellow
    }
} elseif (-not $WtSettingsLocal) {
    Write-Host "  WT Settings      NOT FOUND (neither Store nor non-Store)" -ForegroundColor Red
} else {
    Write-Host "  WT Settings      NOT IN REPO" -ForegroundColor Red
}

# Themes
if (-not (Test-Path $OmpThemesLocal)) { New-Item -ItemType Directory -Path $OmpThemesLocal -Force | Out-Null }
$themeFiles = Get-ChildItem "$RepoRoot\themes" -Filter "*.omp.json" -ErrorAction SilentlyContinue
if ($themeFiles) {
    $themeFiles | Copy-Item -Destination $OmpThemesLocal -Force
    Write-Host "  Themes           OK ($($themeFiles.Count) files)" -ForegroundColor Green
} else {
    Write-Host "  Themes           NONE IN REPO" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Restart terminal to apply changes." -ForegroundColor Yellow
Write-Host ""
