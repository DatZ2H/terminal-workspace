#Requires -Version 7.0
# Copy config files from this repo to local system (with backup)

$RepoRoot = Split-Path $PSScriptRoot -Parent

. "$PSScriptRoot\common.ps1"

$PsProfileLocal = $PsProfilePath
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
    # Atomic deploy: read repo JSON, inject markers, write via Save-WtSettings
    try {
        $wtJson = Get-Content $repoWt -Raw | ConvertFrom-Json
        Initialize-WtPnxMarkers -WtJson $wtJson | Out-Null
        if (-not (Save-WtSettings -Json $wtJson -WtPath $WtSettingsLocal)) {
            Write-Host "  WT Settings      WARNING: atomic write failed, falling back to Copy-Item" -ForegroundColor Yellow
            Copy-Item $repoWt $WtSettingsLocal -Force
        }
        Write-Host "  WT Settings      OK" -ForegroundColor Green
    } catch {
        Write-Host "  WT Settings      WARNING: JSON processing failed: $_" -ForegroundColor Yellow
        Copy-Item $repoWt $WtSettingsLocal -Force
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

# Clear init cache so next profile load regenerates from fresh configs
if (Get-Command Clear-PnxCache -ErrorAction SilentlyContinue) { Clear-PnxCache }

Write-Host ""
Write-Host "  Restart terminal to apply changes." -ForegroundColor Yellow
Write-Host ""
