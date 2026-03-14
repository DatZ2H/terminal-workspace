#Requires -Version 7.0
# Install required tools via winget and PowerShell modules

Write-Host "`n  Installing Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

. "$PSScriptRoot\common.ps1"
$script:errorCount = 0

$tools = @(
    @{ Id = "Microsoft.PowerShell";            Name = "PowerShell 7" }
    @{ Id = "JanDeDobbeleer.OhMyPosh";         Name = "Oh My Posh" }
    @{ Id = "Git.Git";                         Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";               Name = "Node.js LTS" }
    @{ Id = "Python.Python.$PythonVersion";    Name = "Python $PythonVersion" }
)

foreach ($tool in $tools) {
    Write-Host "  $($tool.Name)... " -NoNewline
    $check = winget list --id $tool.Id --exact --accept-source-agreements 2>$null | Out-String
    if ($check -match [regex]::Escape($tool.Id)) {
        Write-Host "installed" -ForegroundColor Green
    } else {
        Write-Host "installing..." -ForegroundColor Yellow
        winget install --id $tool.Id --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    done" -ForegroundColor Green
        } else {
            Write-Host "    failed (install manually)" -ForegroundColor Red
            $script:errorCount++
        }
    }
}

# Scoop + CLI Tools
Write-Host "`n  Scoop CLI Tools" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "  Scoop... " -NoNewline
    Write-Host "installing..." -ForegroundColor Yellow
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
        $scoopInstaller = Invoke-RestMethod -Uri https://get.scoop.sh
        # Verify content is the real Scoop installer (integrity check)
        if ($scoopInstaller -match 'github\.com/ScoopInstaller' -and $scoopInstaller -match 'function\s+Install-Scoop') {
            $scoopBlock = [scriptblock]::Create($scoopInstaller)
            if ($isAdmin) {
                & $scoopBlock -RunAsAdmin
            } else {
                & $scoopBlock
            }
        } else {
            throw "Downloaded content failed integrity check -- may not be the official Scoop installer"
        }
        Write-Host "    done" -ForegroundColor Green
    } catch {
        Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    install manually: https://scoop.sh" -ForegroundColor DarkGray
        $script:errorCount++
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
                $script:errorCount++
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
        try {
            Install-Module $mod -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "    done" -ForegroundColor Green
        } catch {
            Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor Red
            $script:errorCount++
        }
    }
}

if ($script:errorCount -gt 0) {
    Write-Host "`n  Tools installation finished with $($script:errorCount) error(s)." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n  Tools installation complete." -ForegroundColor Green
}
