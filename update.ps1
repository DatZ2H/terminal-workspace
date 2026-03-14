#Requires -Version 7.0
# Standalone update script — works even if profile is outdated
# Usage: cd terminal-workspace && .\update.ps1

$RepoRoot = $PSScriptRoot

Write-Host "`n  Updating Terminal Workspace..." -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

# 1. Git pull
Write-Host "`n  Pulling latest changes..." -ForegroundColor Cyan
$prevDir = Get-Location
Set-Location $RepoRoot
$pullOutput = git pull 2>&1 | Out-String
Set-Location $prevDir
if ($pullOutput -match 'Already up to date') {
    Write-Host "  Already up to date." -ForegroundColor DarkGray
} else {
    Write-Host $pullOutput.Trim() -ForegroundColor DarkGray
}

# 2. Re-deploy configs
Write-Host "`n  Re-deploying configs..." -ForegroundColor Cyan
& "$RepoRoot\scripts\sync-from-repo.ps1"

# 3. Reload profile
Write-Host "`n  Reloading profile..." -ForegroundColor Cyan
. $PROFILE

Write-Host "  Done. Workspace updated." -ForegroundColor Green
Write-Host ""
