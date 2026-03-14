#Requires -Version 7.0
# Install CaskaydiaCove Nerd Font via Oh My Posh

Write-Host "`n  Installing Nerd Font" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

try {
    Get-Command oh-my-posh -ErrorAction Stop | Out-Null
} catch {
    Write-Host "  Oh My Posh not found. Run install-tools.ps1 first." -ForegroundColor Red
    return
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  Note: Running without admin. Font will install per-user." -ForegroundColor Yellow
    Write-Host "  If prompt icons look broken, re-run as Administrator." -ForegroundColor Yellow
}

Write-Host "  CaskaydiaCove Nerd Font... " -NoNewline
oh-my-posh font install CascadiaCode
Write-Host "  done" -ForegroundColor Green
Write-Host ""
Write-Host "  Restart Windows Terminal for the font to take effect." -ForegroundColor Yellow
