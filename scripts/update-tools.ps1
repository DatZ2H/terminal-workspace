#Requires -Version 7.0
# Update all tools, modules, and fonts

param([switch]$Force)

Write-Host "`n  Terminal Workspace — Update Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  This will update:"
Write-Host "    - Oh My Posh, Git, Node.js, Python (via winget)"
Write-Host "    - Terminal-Icons module"
Write-Host "    - Scoop tools (zoxide, ripgrep)"
Write-Host "    - CaskaydiaCove Nerd Font"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "  Proceed? (y/N)"
    if ($confirm -notin @('y', 'Y', 'yes')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

. "$PSScriptRoot\common.ps1"

$packages = @(
    @{ Id = "JanDeDobbeleer.OhMyPosh";         Name = "Oh My Posh" }
    @{ Id = "Git.Git";                         Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";               Name = "Node.js" }
    @{ Id = "Python.Python.$PythonVersion";    Name = "Python" }
)

foreach ($pkg in $packages) {
    Write-Host "`n  Upgrading $($pkg.Name)..." -ForegroundColor Cyan
    winget upgrade --id $pkg.Id --accept-package-agreements --accept-source-agreements --silent 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
    } else {
        Write-Host "    already up-to-date or skipped" -ForegroundColor DarkGray
    }
}

Write-Host "`n  Updating Terminal-Icons module..." -ForegroundColor Cyan
try {
    Update-Module Terminal-Icons -Force -ErrorAction Stop
    Write-Host "    done" -ForegroundColor Green
} catch {
    Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor Red
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "`n  Updating Scoop tools..." -ForegroundColor Cyan
    scoop update '*'
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
    } else {
        Write-Host "    completed with warnings (exit $LASTEXITCODE)" -ForegroundColor Yellow
    }
}

Write-Host "`n  Updating Nerd Font..." -ForegroundColor Cyan
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh font install CascadiaCode 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    done" -ForegroundColor Green
    } else {
        Write-Host "    failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    }
} else {
    Write-Host "    skipped (oh-my-posh not found)" -ForegroundColor Yellow
}

Write-Host "`n  All updates complete." -ForegroundColor Green
Write-Host ""
