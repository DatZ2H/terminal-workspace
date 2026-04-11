#Requires -Version 7.0
# Update all tools, modules, and fonts

param([switch]$Force)

. "$PSScriptRoot\common.ps1"

$results = [System.Collections.Generic.List[hashtable]]::new()

$packages = @(
    @{ Id = "Microsoft.PowerShell";            Name = "PowerShell 7" }
    @{ Id = "Microsoft.WindowsTerminal";       Name = "Windows Terminal" }
    @{ Id = "JanDeDobbeleer.OhMyPosh";         Name = "Oh My Posh" }
    @{ Id = "Git.Git";                         Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";               Name = "Node.js" }
    @{ Id = "Python.Python.$PythonVersion";    Name = "Python" }
)

# ── Banner ──────────────────────────────────────────────────────────
Write-Host "`n  Terminal Workspace — Update Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════════" -ForegroundColor DarkGray

# ── Pre-check: gather available upgrades ────────────────────────────
Write-Host ""
Write-Host "  Checking for updates..." -ForegroundColor DarkGray

# Winget: one call to get all available upgrades
$wingetUpgradeList = winget upgrade --accept-source-agreements 2>$null | Out-String

$anyUpdates = $false

Write-Host ""
Write-Host "  Available Updates:" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────" -ForegroundColor DarkGray

foreach ($pkg in $packages) {
    $hasUpgrade = $wingetUpgradeList -match [regex]::Escape($pkg.Id)
    if ($hasUpgrade) {
        Write-Host ("    {0,-22}" -f $pkg.Name) -NoNewline
        Write-Host "upgrade available" -ForegroundColor Yellow
        $anyUpdates = $true
    } else {
        Write-Host ("    {0,-22}" -f $pkg.Name) -NoNewline
        Write-Host "up to date" -ForegroundColor Green
    }
}

# Terminal-Icons + Nerd Font (no pre-check available — always updated when running)
$tiCurrent = try { (Get-Module Terminal-Icons -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1).Version.ToString() } catch { $null }
Write-Host ("    {0,-22}" -f "Terminal-Icons") -NoNewline
if ($tiCurrent) {
    Write-Host "installed ($tiCurrent) — will check" -ForegroundColor DarkGray
} else {
    Write-Host "not found" -ForegroundColor Red
}
Write-Host ("    {0,-22}" -f "Nerd Font") -NoNewline
Write-Host "will check" -ForegroundColor DarkGray

# Scoop tools
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    $scoopStatus = scoop status 2>$null | Out-String
    $scoopHasUpdates = $scoopStatus -match 'zoxide|ripgrep'
    Write-Host ("    {0,-22}" -f "Scoop tools") -NoNewline
    if ($scoopHasUpdates) {
        Write-Host "upgrade available" -ForegroundColor Yellow
        $anyUpdates = $true
    } else {
        Write-Host "up to date" -ForegroundColor Green
    }
}

# Claude Code
$claudeCurrentVer = try { (claude --version 2>$null) -replace 'claude ','' } catch { $null }
$claudeLatestVer = try { (npm view @anthropic-ai/claude-code version 2>$null) } catch { $null }
$claudeNeedsUpdate = $claudeCurrentVer -and $claudeLatestVer -and ($claudeCurrentVer.Trim() -ne $claudeLatestVer.Trim())

if ($claudeCurrentVer) {
    Write-Host ("    {0,-22}" -f "Claude Code") -NoNewline
    if ($claudeNeedsUpdate) {
        Write-Host "$($claudeCurrentVer.Trim()) -> $($claudeLatestVer.Trim())" -ForegroundColor Yellow
        $anyUpdates = $true
    } else {
        Write-Host "up to date ($($claudeCurrentVer.Trim()))" -ForegroundColor Green
    }
}

Write-Host ""

# ── Early exit if nothing to update ─────────────────────────────────
if (-not $anyUpdates -and -not $Force) {
    Write-Host "  Everything is up to date." -ForegroundColor Green
    Write-Host ""
    return
}

# ── Confirmation ────────────────────────────────────────────────────
if (-not $Force) {
    $confirm = Read-Host "  Proceed with updates? (y/N)"
    if ($confirm -notin @('y', 'Y', 'yes')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

# ── Winget packages ─────────────────────────────────────────────────
foreach ($pkg in $packages) {
    $hasUpgrade = $wingetUpgradeList -match [regex]::Escape($pkg.Id)
    if (-not $hasUpgrade -and -not $Force) {
        $results.Add(@{ Name = $pkg.Name; Status = 'up-to-date' })
        continue
    }
    Write-Host "`n  Upgrading $($pkg.Name)..." -ForegroundColor Cyan
    winget upgrade --id $pkg.Id --accept-package-agreements --accept-source-agreements --silent 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
        $results.Add(@{ Name = $pkg.Name; Status = 'updated' })
    } elseif ($pkg.Id -eq 'Microsoft.WindowsTerminal') {
        Write-Host "    skipped — close Windows Terminal to update, or update via Store" -ForegroundColor Yellow
        $results.Add(@{ Name = $pkg.Name; Status = 'skipped' })
    } else {
        Write-Host "    already up-to-date or skipped" -ForegroundColor DarkGray
        $results.Add(@{ Name = $pkg.Name; Status = 'up-to-date' })
    }
}

# ── Terminal-Icons module ───────────────────────────────────────────
Write-Host "`n  Updating Terminal-Icons module..." -ForegroundColor Cyan
try {
    Update-Module Terminal-Icons -Force -ErrorAction Stop
    Write-Host "    done" -ForegroundColor Green
    $results.Add(@{ Name = 'Terminal-Icons'; Status = 'updated' })
} catch {
    Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor Red
    $results.Add(@{ Name = 'Terminal-Icons'; Status = 'failed' })
}

# ── Scoop tools ─────────────────────────────────────────────────────
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "`n  Updating Scoop tools..." -ForegroundColor Cyan
    scoop update '*'
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
        $results.Add(@{ Name = 'Scoop tools'; Status = 'updated' })
    } else {
        Write-Host "    completed with warnings (exit $LASTEXITCODE)" -ForegroundColor Yellow
        $results.Add(@{ Name = 'Scoop tools'; Status = 'updated' })
    }
}

# ── Nerd Font ───────────────────────────────────────────────────────
Write-Host "`n  Updating Nerd Font..." -ForegroundColor Cyan
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh font install CascadiaCode 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
        $results.Add(@{ Name = 'Nerd Font'; Status = 'updated' })
    } else {
        Write-Host "    failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        $results.Add(@{ Name = 'Nerd Font'; Status = 'failed' })
    }
} else {
    Write-Host "    skipped (oh-my-posh not found)" -ForegroundColor Yellow
    $results.Add(@{ Name = 'Nerd Font'; Status = 'skipped' })
}

# ── Claude Code ─────────────────────────────────────────────────────
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "`n  Updating Claude Code..." -ForegroundColor Cyan
    $preVer = try { (claude --version 2>$null) -replace 'claude ','' } catch { $null }
    npm install -g @anthropic-ai/claude-code@latest 2>$null
    if ($LASTEXITCODE -eq 0) {
        $postVer = try { (claude --version 2>$null) -replace 'claude ','' } catch { $null }
        if ($preVer -and $postVer -and ($preVer.Trim() -ne $postVer.Trim())) {
            Write-Host "    updated: $($preVer.Trim()) -> $($postVer.Trim())" -ForegroundColor Green
            # Re-apply Vietnamese IME fix (npm overwrites cli.js)
            Write-Host "    Re-applying Vietnamese IME fix..." -ForegroundColor Cyan
            $fixScript = Join-Path $PSScriptRoot "fix-claude-vn.ps1"
            if (Test-Path $fixScript) {
                try { & $fixScript } catch { Write-Host "    IME fix failed: $_" -ForegroundColor Red }
            }
            Write-Host "    Restart any running Claude Code sessions." -ForegroundColor DarkGray
            $results.Add(@{ Name = 'Claude Code'; Status = 'updated' })
        } else {
            Write-Host "    already up-to-date ($($postVer.Trim()))" -ForegroundColor DarkGray
            $results.Add(@{ Name = 'Claude Code'; Status = 'up-to-date' })
        }
    } else {
        Write-Host "    failed (exit code $LASTEXITCODE)" -ForegroundColor Red
        $results.Add(@{ Name = 'Claude Code'; Status = 'failed' })
    }
} else {
    Write-Host "`n  Claude Code... skipped (not installed)" -ForegroundColor DarkGray
    $results.Add(@{ Name = 'Claude Code'; Status = 'skipped' })
}

# ── Summary ─────────────────────────────────────────────────────────
Write-Host "`n  Update Summary" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────" -ForegroundColor DarkGray
foreach ($r in $results) {
    $color = switch ($r.Status) {
        'updated'    { 'Green' }
        'failed'     { 'Red' }
        'skipped'    { 'Yellow' }
        default      { 'DarkGray' }
    }
    Write-Host ("    {0,-22}" -f $r.Name) -NoNewline
    Write-Host $r.Status -ForegroundColor $color
}
Write-Host ""
