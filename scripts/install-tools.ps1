#Requires -Version 7.0
# Install required tools via winget and PowerShell modules

Write-Host "`n  Installing Tools" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

$tools = @(
    @{ Id = "Microsoft.PowerShell";    Name = "PowerShell 7" }
    @{ Id = "JanDeDobbeleer.OhMyPosh"; Name = "Oh My Posh" }
    @{ Id = "Git.Git";                 Name = "Git" }
    @{ Id = "OpenJS.NodeJS.LTS";       Name = "Node.js LTS" }
    @{ Id = "Python.Python.3.12";      Name = "Python 3.12" }
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
