#Requires -Version 7.0
# Install required tools via winget and PowerShell modules

Write-Host "`n  Installing Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

# Python version — change here when upgrading (also update in update-tools.ps1)
$PythonVersion = "3.12"

$tools = @(
    @{ Id = "Microsoft.PowerShell";            Name = "PowerShell 7" }
    @{ Id = "JanDeDobbeleer.OhMyPosh";         Name = "Oh My Posh" }
    @{ Id = "Git.Git";                         Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";               Name = "Node.js LTS" }
    @{ Id = "Python.Python.$PythonVersion";    Name = "Python $PythonVersion" }
)

foreach ($tool in $tools) {
    Write-Host "  $($tool.Name)... " -NoNewline
    $check = winget list --id $tool.Id --accept-source-agreements 2>$null | Out-String
    if ($check -match [regex]::Escape($tool.Id)) {
        Write-Host "installed" -ForegroundColor Green
    } else {
        Write-Host "installing..." -ForegroundColor Yellow
        winget install --id $tool.Id --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    done" -ForegroundColor Green
        } else {
            Write-Host "    failed (install manually)" -ForegroundColor Red
        }
    }
}

# Scoop + CLI Tools
Write-Host "`n  Scoop CLI Tools" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "  Scoop... " -NoNewline
    Write-Host "installing..." -ForegroundColor Yellow
    try {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Host "    done" -ForegroundColor Green
    } catch {
        Write-Host "    failed (install manually: https://scoop.sh)" -ForegroundColor Red
    }
} else {
    Write-Host "  Scoop... installed" -ForegroundColor Green
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
    $scoopTools = @("zoxide", "ripgrep")
    foreach ($st in $scoopTools) {
        Write-Host "  $st... " -NoNewline
        $installed = scoop list $st 2>$null | Out-String
        if ($installed -match $st) {
            Write-Host "installed" -ForegroundColor Green
        } else {
            Write-Host "installing..." -ForegroundColor Yellow
            scoop install $st
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    done" -ForegroundColor Green
            } else {
                Write-Host "    failed (run: scoop install $st)" -ForegroundColor Red
            }
        }
    }
} else {
    Write-Host "  Skipped (scoop not available)" -ForegroundColor Yellow
}

# PowerShell Modules
Write-Host "`n  PowerShell Modules" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray

$modules = @("Terminal-Icons")
foreach ($mod in $modules) {
    Write-Host "  $mod... " -NoNewline
    if (Get-Module -ListAvailable -Name $mod) {
        Write-Host "installed" -ForegroundColor Green
    } else {
        Write-Host "installing..." -ForegroundColor Yellow
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
        Write-Host "    done" -ForegroundColor Green
    }
}

Write-Host "`n  Tools installation complete." -ForegroundColor Green
