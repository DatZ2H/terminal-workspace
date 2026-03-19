# Terminal Workspace Bootstrap -- Setup everything in one run
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

    # Case 1: pwsh already installed -- re-launch automatically
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

    # Case 2: pwsh not found -- try installing via winget
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

    # Case 3: No winget -- manual instructions only
    Write-Host ""
    Write-Host "  PowerShell 7+ required." -ForegroundColor Red
    Write-Host "  winget not available -- install PowerShell 7 manually:" -ForegroundColor Yellow
    Write-Host "    https://aka.ms/powershell-release?tag=stable" -ForegroundColor Cyan
    Write-Host "  Then open 'PowerShell 7' (not Windows PowerShell) and re-run." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$RepoRoot = $PSScriptRoot

. "$RepoRoot\scripts\common.ps1"

$PsProfileLocal = $PsProfilePath
$WtSettingsLocal = Get-WtSettingsPath -Mode deploy

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "    Terminal Workspace -- Bootstrap      " -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan

# -- Step 0: Ensure ExecutionPolicy allows scripts --
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'Undefined') {
    Write-Step "Setting ExecutionPolicy to RemoteSigned..."
    $policySet = $false
    # Try CurrentUser scope first (persists across sessions)
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        Write-Ok "ExecutionPolicy set to RemoteSigned (CurrentUser)"
        $policySet = $true
    } catch {
        # CurrentUser may fail if Group Policy restricts it -- try Process scope (current session only)
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction Stop
            Write-Ok "ExecutionPolicy set to RemoteSigned (Process -- this session only)"
            Write-Skip "For permanent fix, run in non-admin terminal: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
            $policySet = $true
        } catch {
            Write-Skip "Could not set ExecutionPolicy: $($_.Exception.Message)"
            Write-Skip "Run manually: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
        }
    }
} else {
    Write-Step "ExecutionPolicy: $currentPolicy (OK)"
}

# -- Step 1: Install tools --
if ($SkipTools) {
    Write-Step "Skipping tools installation (-SkipTools)"
} else {
    Write-Step "Installing tools..."
    & "$RepoRoot\scripts\install-tools.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Skip "install-tools.ps1 exited with code $LASTEXITCODE -- continuing"
    }
}

# -- Step 2: Install fonts --
# Refresh PATH so oh-my-posh (installed in step 1) is found
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Step "Installing fonts..."
& "$RepoRoot\scripts\install-fonts.ps1"
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Skip "install-fonts.ps1 exited with code $LASTEXITCODE -- continuing"
}

# -- Step 3: Deploy OMP themes (before profile, so OMP init can find them) --
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

# -- Step 4: Deploy Windows Terminal settings --
Write-Step "Deploying Windows Terminal settings..."
if ($WtSettingsLocal) {
    if (Test-Path $WtSettingsLocal) {
        Copy-Item $WtSettingsLocal "$WtSettingsLocal.backup-$timestamp"
        Write-Ok "Backed up existing WT settings"
        # Cleanup old backups (keep last N)
        Get-ChildItem (Split-Path $WtSettingsLocal -Parent) -Filter "settings.json.backup-*" |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip $MaxBackups | Remove-Item -Force
    }
    # Atomic deploy: read repo JSON, inject markers, write via Save-WtSettings
    try {
        $wtJson = Get-Content "$RepoRoot\configs\terminal-settings.json" -Raw | ConvertFrom-Json
        Initialize-WtPnxMarkers -WtJson $wtJson | Out-Null
        if (-not (Save-WtSettings -Json $wtJson -WtPath $WtSettingsLocal)) {
            Write-Skip "Atomic write failed, falling back to Copy-Item"
            Copy-Item "$RepoRoot\configs\terminal-settings.json" $WtSettingsLocal -Force
        }
    } catch {
        Write-Skip "JSON processing failed: $_ — falling back to Copy-Item"
        Copy-Item "$RepoRoot\configs\terminal-settings.json" $WtSettingsLocal -Force
    }
    Write-Ok "WT settings deployed"
} else {
    Write-Skip "Windows Terminal not found (install from Microsoft Store or winget)"
}

# -- Step 5: Deploy PowerShell profile --
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

# -- Step 6: Set environment variable --
Write-Step "Setting PNX_TERMINAL_REPO environment variable..."
[Environment]::SetEnvironmentVariable('PNX_TERMINAL_REPO', $RepoRoot, 'User')
$env:PNX_TERMINAL_REPO = $RepoRoot
Write-Ok "PNX_TERMINAL_REPO = $RepoRoot"

# ════════════════════════════════════════
# Phase 2: Claude Code Setup
# ════════════════════════════════════════

# -- Step 7: Check Claude Code --
Write-Step "Checking Claude Code..."
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$claudeInstalled = (Test-Path $claudeDir) -or (Get-Command claude -ErrorAction SilentlyContinue)
if (-not $claudeInstalled) {
    Write-Skip "Claude Code not detected -- skipping Phase 2 (install via: npm i -g @anthropic-ai/claude-code)"
} else {
    Write-Ok "Claude Code detected"

    # -- Step 8: Deploy Claude Configs --
    Write-Step "Deploying Claude Code configs..."
    try {
        & "$RepoRoot\scripts\deploy-claude.ps1"
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Skip "Claude config deploy had warnings (exit $LASTEXITCODE)"
        }
    } catch {
        Write-Skip "Claude config deploy skipped: $_"
    }
}

# -- Summary --
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Green
Write-Host "         Bootstrap Complete!              " -ForegroundColor Green
Write-Host "  ========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Restart Windows Terminal"
Write-Host "    2. Verify:  Get-Status"
Write-Host "    3. Try:     Set-Theme pro mac"
Write-Host ""
