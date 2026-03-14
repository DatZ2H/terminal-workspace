#Requires -Version 7.0
# Update all tools, modules, and fonts

param([switch]$Force)

Write-Host "`n  Terminal Workspace — Update Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  This will update:"
Write-Host "    - Oh My Posh, Git, Node.js, Python (via winget)"
Write-Host "    - Terminal-Icons module"
Write-Host "    - CaskaydiaCove Nerd Font"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "  Proceed? (y/N)"
    if ($confirm -notin @('y', 'Y', 'yes')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

$packages = @(
    @{ Id = "JanDeDobbeleer.OhMyPosh"; Name = "Oh My Posh" }
    @{ Id = "Git.Git";                 Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";       Name = "Node.js" }
    @{ Id = "Python.Python.3.12";      Name = "Python" }
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
Update-Module Terminal-Icons -Force -ErrorAction SilentlyContinue
Write-Host "    done" -ForegroundColor Green

Write-Host "`n  Updating Nerd Font..." -ForegroundColor Cyan
oh-my-posh font install CascadiaCode 2>$null
Write-Host "    done" -ForegroundColor Green

Write-Host "`n  All updates complete." -ForegroundColor Green
Write-Host ""
