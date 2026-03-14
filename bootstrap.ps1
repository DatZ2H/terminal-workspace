#Requires -Version 7.0
# Terminal Workspace Bootstrap — Setup everything in one run
# Usage: git clone <repo> && cd terminal-workspace && .\bootstrap.ps1

param([switch]$SkipTools)

$RepoRoot = $PSScriptRoot

$PsProfileLocal  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$WtSettingsLocal = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$OmpThemesLocal  = Join-Path $env:USERPROFILE ".oh-my-posh\themes"
$VnFixLocal      = Join-Path $env:USERPROFILE ".claude-vn-fix"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Terminal Workspace — Bootstrap     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan

# ── Step 1: Install tools ──
if ($SkipTools) {
    Write-Step "Skipping tools installation (-SkipTools)"
} else {
    Write-Step "Installing tools..."
    & "$RepoRoot\scripts\install-tools.ps1"
}

# ── Step 2: Install fonts ──
Write-Step "Installing fonts..."
& "$RepoRoot\scripts\install-fonts.ps1"

# ── Step 3: Deploy PowerShell profile ──
Write-Step "Deploying PowerShell profile..."
$profileDir = Split-Path $PsProfileLocal -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (Test-Path $PsProfileLocal) {
    Copy-Item $PsProfileLocal "$PsProfileLocal.backup-$timestamp"
    Write-Ok "Backed up existing profile"
}
Copy-Item "$RepoRoot\configs\profile.ps1" $PsProfileLocal -Force
Write-Ok "Profile deployed"

# ── Step 4: Deploy Windows Terminal settings ──
Write-Step "Deploying Windows Terminal settings..."
$wtDir = Split-Path $WtSettingsLocal -Parent
if (Test-Path $wtDir) {
    if (Test-Path $WtSettingsLocal) {
        Copy-Item $WtSettingsLocal "$WtSettingsLocal.backup-$timestamp"
        Write-Ok "Backed up existing WT settings"
    }
    Copy-Item "$RepoRoot\configs\terminal-settings.json" $WtSettingsLocal -Force
    Write-Ok "WT settings deployed"
} else {
    Write-Skip "Windows Terminal not found (install it from Microsoft Store)"
}

# ── Step 5: Deploy OMP themes ──
Write-Step "Deploying OMP themes..."
if (-not (Test-Path $OmpThemesLocal)) {
    New-Item -ItemType Directory -Path $OmpThemesLocal -Force | Out-Null
}
$themeFiles = Get-ChildItem "$RepoRoot\themes" -Filter "*.omp.json"
$themeFiles | Copy-Item -Destination $OmpThemesLocal -Force
Write-Ok "$($themeFiles.Count) themes deployed"

# ── Step 6: Deploy Vietnamese IME fix ──
Write-Step "Deploying Vietnamese IME fix..."
if (Test-Path "$RepoRoot\scripts\claude-vn-fix\patcher.py") {
    if (-not (Test-Path $VnFixLocal)) {
        New-Item -ItemType Directory -Path $VnFixLocal -Force | Out-Null
    }
    Copy-Item "$RepoRoot\scripts\claude-vn-fix\patcher.py" $VnFixLocal -Force
    Write-Ok "Patcher deployed to $VnFixLocal"
} else {
    Write-Skip "patcher.py not found in repo"
}

# ── Step 7: Set environment variable ──
Write-Step "Setting PNX_TERMINAL_REPO environment variable..."
[Environment]::SetEnvironmentVariable('PNX_TERMINAL_REPO', $RepoRoot, 'User')
$env:PNX_TERMINAL_REPO = $RepoRoot
Write-Ok "PNX_TERMINAL_REPO = $RepoRoot"

# ── Summary ──
Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║       Bootstrap Complete!             ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Restart Windows Terminal"
Write-Host "    2. Verify:  Get-Status"
Write-Host "    3. Try:     Set-Theme pro mac"
Write-Host ""
