#Requires -Version 7.0
# Copy config files from local system to this repo

param([switch]$Force)

$RepoRoot = Split-Path $PSScriptRoot -Parent

$PsProfileLocal = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$OmpThemesLocal = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

. "$PSScriptRoot\common.ps1"
$WtSettingsLocal = Get-WtSettingsPath -Mode file

Write-Host "`n  Syncing: local -> repo" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

if (-not $Force) {
    Write-Host ""
    Write-Host "  This will overwrite repo files with your local configs." -ForegroundColor Yellow
    Write-Host "  Changes can be reverted via:  cd $RepoRoot && git checkout ." -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  Proceed? (y/N)"
    if ($confirm -notin @('y', 'Y', 'yes')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

# Profile
if (Test-Path $PsProfileLocal) {
    Copy-Item $PsProfileLocal "$RepoRoot\configs\profile.ps1" -Force
    Write-Host "  Profile          OK" -ForegroundColor Green
} else {
    Write-Host "  Profile          NOT FOUND: $PsProfileLocal" -ForegroundColor Red
}

# WT Settings (sanitize machine-specific data before copying to repo)
if ($WtSettingsLocal) {
    try {
        $wtJson = Get-Content $WtSettingsLocal -Raw | ConvertFrom-Json
        # Strip environment variables from all profiles (may contain secrets)
        foreach ($p in $wtJson.profiles.list) {
            if ($p.PSObject.Properties['environment']) {
                $p.PSObject.Properties.Remove('environment')
            }
        }
        $wtJson | ConvertTo-Json -Depth 20 | Set-Content "$RepoRoot\configs\terminal-settings.json" -Encoding utf8NoBOM
        Write-Host "  WT Settings      OK" -ForegroundColor Green
    } catch {
        Write-Host "  WT Settings      FAILED (JSON parse error -- skipped to avoid exposing secrets)" -ForegroundColor Red
        Write-Host "                   Fix settings.json manually or run: Sync-Config push" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WT Settings      NOT FOUND (neither Store nor non-Store)" -ForegroundColor Red
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
