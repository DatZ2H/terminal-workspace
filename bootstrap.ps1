# Terminal Workspace Bootstrap — Setup everything in one run
# Usage: git clone <repo> && cd terminal-workspace && .\bootstrap.ps1

param([switch]$SkipTools)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  PowerShell 7+ required." -ForegroundColor Red
    Write-Host "  Run this first:  winget install Microsoft.PowerShell" -ForegroundColor Yellow
    Write-Host "  Then open 'PowerShell 7' (not Windows PowerShell) and re-run." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$RepoRoot = $PSScriptRoot
$MaxBackups = 3

$PsProfileLocal = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$OmpThemesLocal = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

# Detect WT settings path (Store + non-Store)
$_wtPaths = @(
    (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
)
$WtSettingsLocal = $_wtPaths | Where-Object { Test-Path (Split-Path $_ -Parent) } | Select-Object -First 1

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

# ── Step 3: Deploy OMP themes (before profile, so OMP init can find them) ──
Write-Step "Deploying OMP themes..."
if (-not (Test-Path $OmpThemesLocal)) {
    New-Item -ItemType Directory -Path $OmpThemesLocal -Force | Out-Null
}
$themeFiles = Get-ChildItem "$RepoRoot\themes" -Filter "*.omp.json"
$themeFiles | Copy-Item -Destination $OmpThemesLocal -Force
Write-Ok "$($themeFiles.Count) themes deployed"

# ── Step 4: Deploy Windows Terminal settings ──
Write-Step "Deploying Windows Terminal settings..."
if ($WtSettingsLocal) {
    if (Test-Path $WtSettingsLocal) {
        Copy-Item $WtSettingsLocal "$WtSettingsLocal.backup-$timestamp"
        Write-Ok "Backed up existing WT settings"
        # Cleanup old backups (keep last N)
        Get-ChildItem (Split-Path $WtSettingsLocal -Parent) -Filter "settings.json.backup-*" |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups | Remove-Item -Force
    }
    Copy-Item "$RepoRoot\configs\terminal-settings.json" $WtSettingsLocal -Force
    Write-Ok "WT settings deployed"
} else {
    Write-Skip "Windows Terminal not found (install from Microsoft Store or winget)"
}

# ── Step 5: Deploy PowerShell profile ──
Write-Step "Deploying PowerShell profile..."
$profileDir = Split-Path $PsProfileLocal -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (Test-Path $PsProfileLocal) {
    Copy-Item $PsProfileLocal "$PsProfileLocal.backup-$timestamp"
    Write-Ok "Backed up existing profile"
    # Cleanup old backups (keep last N)
    Get-ChildItem (Split-Path $PsProfileLocal -Parent) -Filter "Microsoft.PowerShell_profile.ps1.backup-*" |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups | Remove-Item -Force
}
Copy-Item "$RepoRoot\configs\profile.ps1" $PsProfileLocal -Force
Write-Ok "Profile deployed"

# ── Step 6: Set environment variable ──
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
