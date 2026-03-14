# Terminal Workspace Bootstrap — Setup everything in one run
# Usage: git clone <repo> && cd terminal-workspace && .\bootstrap.ps1

param([switch]$SkipTools)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Guard: script path must be available for re-launch
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        Write-Host ""
        Write-Host "  Cannot auto-relaunch: script path unknown (dot-sourced?)." -ForegroundColor Red
        Write-Host "  Run directly:  .\bootstrap.ps1" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Case 1: pwsh already installed — re-launch automatically
    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($pwshPath) {
        Write-Host ""
        Write-Host "  Detected PowerShell 7 at: $pwshPath" -ForegroundColor Cyan
        Write-Host "  Re-launching bootstrap in PowerShell 7..." -ForegroundColor Yellow
        Write-Host ""
        $scriptArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
        if ($SkipTools) { $scriptArgs += '-SkipTools' }
        & $pwshPath @scriptArgs
        exit $LASTEXITCODE
    }

    # Case 2: pwsh not found — try installing via winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "  PowerShell 7+ required. Installing automatically..." -ForegroundColor Yellow
        Write-Host ""
        winget install --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            # Refresh PATH to find newly installed pwsh
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
            $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
            if ($pwshPath) {
                Write-Host "  PowerShell 7 installed. Re-launching bootstrap..." -ForegroundColor Green
                Write-Host ""
                $scriptArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
                if ($SkipTools) { $scriptArgs += '-SkipTools' }
                & $pwshPath @scriptArgs
                exit $LASTEXITCODE
            }
        }
        Write-Host "  Install failed. Please install manually:" -ForegroundColor Red
        Write-Host "    winget install Microsoft.PowerShell" -ForegroundColor Yellow
        Write-Host "  Then open 'PowerShell 7' and re-run." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Case 3: No winget — manual instructions only
    Write-Host ""
    Write-Host "  PowerShell 7+ required." -ForegroundColor Red
    Write-Host "  winget not available — install PowerShell 7 manually:" -ForegroundColor Yellow
    Write-Host "    https://aka.ms/powershell-release?tag=stable" -ForegroundColor Cyan
    Write-Host "  Then open 'PowerShell 7' (not Windows PowerShell) and re-run." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$RepoRoot = $PSScriptRoot
$MaxBackups = 3

$PsProfileLocal = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
$OmpThemesLocal = Join-Path $env:USERPROFILE ".oh-my-posh\themes"

. "$RepoRoot\scripts\common.ps1"
$WtSettingsLocal = Get-WtSettingsPath -Mode deploy

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
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Skip "install-tools.ps1 exited with code $LASTEXITCODE — continuing"
    }
}

# ── Step 2: Install fonts ──
# Refresh PATH so oh-my-posh (installed in step 1) is found
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Step "Installing fonts..."
& "$RepoRoot\scripts\install-fonts.ps1"
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Skip "install-fonts.ps1 exited with code $LASTEXITCODE — continuing"
}

# ── Step 3: Deploy OMP themes (before profile, so OMP init can find them) ──
Write-Step "Deploying OMP themes..."
if (-not (Test-Path $OmpThemesLocal)) {
    New-Item -ItemType Directory -Path $OmpThemesLocal -Force | Out-Null
}
$themeFiles = Get-ChildItem "$RepoRoot\themes" -Filter "*.omp.json" -ErrorAction SilentlyContinue
if ($themeFiles) {
    $themeFiles | Copy-Item -Destination $OmpThemesLocal -Force
    Write-Ok "$($themeFiles.Count) themes deployed"
} else {
    Write-Skip "No theme files found in $RepoRoot\themes"
}

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
    # Post-deploy: inject pnx markers + fix font name for installed version
    try {
        $wtJson = Get-Content $WtSettingsLocal -Raw | ConvertFrom-Json
        if ($wtJson.profiles -and -not $wtJson.profiles.defaults) {
            $wtJson.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{})
        }
        if ($wtJson.profiles.defaults) {
            $d = $wtJson.profiles.defaults
            $needsWrite = $false
            # Ensure pnx markers exist (only add if missing — preserve repo's theme/style choice)
            if (-not $d.PSObject.Properties['pnxTheme']) {
                $d | Add-Member -NotePropertyName pnxTheme -NotePropertyValue 'pro'
                $needsWrite = $true
            }
            if (-not $d.PSObject.Properties['pnxStyle']) {
                $d | Add-Member -NotePropertyName pnxStyle -NotePropertyValue 'mac'
                $needsWrite = $true
            }
            # Detect installed Nerd Font version and fix font face name
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
    } catch {
        Write-Skip "Could not inject pnx markers: $_"
    }
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
