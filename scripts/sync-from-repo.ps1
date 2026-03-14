#Requires -Version 7.0
# Copy config files from this repo to local system (with backup)

$RepoRoot = Split-Path $PSScriptRoot -Parent

$PsProfileLocal  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$WtSettingsLocal = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$OmpThemesLocal  = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

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
    }
    Copy-Item $repoProfile $PsProfileLocal -Force
    Write-Host "  Profile          OK" -ForegroundColor Green
} else {
    Write-Host "  Profile          NOT IN REPO" -ForegroundColor Red
}

# WT Settings
$repoWt = "$RepoRoot\configs\terminal-settings.json"
if (Test-Path $repoWt) {
    if (Test-Path $WtSettingsLocal) {
        Copy-Item $WtSettingsLocal "$WtSettingsLocal.backup-$timestamp"
        Write-Host "  WT backup        created" -ForegroundColor DarkGray
    }
    Copy-Item $repoWt $WtSettingsLocal -Force
    Write-Host "  WT Settings      OK" -ForegroundColor Green
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
