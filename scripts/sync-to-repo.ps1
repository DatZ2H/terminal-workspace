#Requires -Version 7.0
# Copy config files from local system to this repo

$RepoRoot = Split-Path $PSScriptRoot -Parent

$PsProfileLocal  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$WtSettingsLocal = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$OmpThemesLocal  = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

Write-Host "`n  Syncing: local -> repo" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

# Profile
if (Test-Path $PsProfileLocal) {
    Copy-Item $PsProfileLocal "$RepoRoot\configs\profile.ps1" -Force
    Write-Host "  Profile          OK" -ForegroundColor Green
} else {
    Write-Host "  Profile          NOT FOUND: $PsProfileLocal" -ForegroundColor Red
}

# WT Settings
if (Test-Path $WtSettingsLocal) {
    Copy-Item $WtSettingsLocal "$RepoRoot\configs\terminal-settings.json" -Force
    Write-Host "  WT Settings      OK" -ForegroundColor Green
} else {
    Write-Host "  WT Settings      NOT FOUND" -ForegroundColor Red
}

# Themes (only pnx-*)
$themeFiles = Get-ChildItem $OmpThemesLocal -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue
if ($themeFiles) {
    $themeFiles | Copy-Item -Destination "$RepoRoot\themes\" -Force
    Write-Host "  Themes           OK ($($themeFiles.Count) files)" -ForegroundColor Green
} else {
    Write-Host "  Themes           NONE FOUND" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Review changes:" -ForegroundColor DarkGray
Write-Host "    cd $RepoRoot && git diff" -ForegroundColor DarkGray
Write-Host ""
