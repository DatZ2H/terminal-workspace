#Requires -Version 7.0
# Show version of all tools and config status

Write-Host "`n  Terminal Workspace — Status" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════════" -ForegroundColor DarkGray

# Tool versions
$checks = @(
    @{ Name = "PowerShell";     Cmd = { $PSVersionTable.PSVersion.ToString() } }
    @{ Name = "Oh My Posh";     Cmd = { oh-my-posh version 2>$null } }
    @{ Name = "Git";            Cmd = { (git --version 2>$null) -replace 'git version ','' } }
    @{ Name = "Node.js";        Cmd = { (node --version 2>$null) -replace 'v','' } }
    @{ Name = "Python";         Cmd = { (python --version 2>$null) -replace 'Python ','' } }
    @{ Name = "npm";            Cmd = { npm --version 2>$null } }
    @{ Name = "PSReadLine";     Cmd = { (Get-Module PSReadLine -ErrorAction SilentlyContinue).Version.ToString() } }
    @{ Name = "Terminal-Icons"; Cmd = { (Get-Module Terminal-Icons -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1).Version.ToString() } }
    @{ Name = "Scoop";          Cmd = { (scoop --version 2>$null | Select-Object -First 1) -replace 'v','' } }
    @{ Name = "zoxide";         Cmd = { (zoxide --version 2>$null) -replace 'zoxide ','' } }
    @{ Name = "ripgrep";        Cmd = { (rg --version 2>$null | Select-Object -First 1) -replace 'ripgrep ','' } }
    @{ Name = "Claude Code";    Cmd = { claude --version 2>$null } }
)

foreach ($c in $checks) {
    $ver = try { & $c.Cmd } catch { $null }
    $color = if ($ver) { "Green" } else { "Red" }
    if (-not $ver) { $ver = "not found" }
    Write-Host ("  {0,-18}" -f $c.Name) -NoNewline
    Write-Host $ver -ForegroundColor $color
}

# Config paths
Write-Host "`n  Config Locations" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────" -ForegroundColor DarkGray

$paths = @(
    @{ Name = "PS Profile";  Path = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1") }
    @{ Name = "WT Settings"; Path = (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json") }
    @{ Name = "OMP Themes";  Path = (Join-Path $env:USERPROFILE ".oh-my-posh\themes") }
    @{ Name = "VN Fix";      Path = (Join-Path $env:USERPROFILE ".claude-vn-fix\patcher.py") }
)

foreach ($p in $paths) {
    $exists = Test-Path $p.Path
    $status = if ($exists) { "OK" } else { "MISSING" }
    $color  = if ($exists) { "Green" } else { "Red" }
    Write-Host ("  {0,-18}" -f $p.Name) -NoNewline
    Write-Host ("{0,-10}" -f $status) -ForegroundColor $color -NoNewline
    Write-Host $p.Path -ForegroundColor DarkGray
}

# Theme count
$themeDir = Join-Path $env:USERPROFILE ".oh-my-posh\themes"
$themeCount = (Get-ChildItem $themeDir -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue).Count
Write-Host "`n  PNX Themes:      $themeCount installed" -ForegroundColor $(if ($themeCount -ge 5) { "Green" } else { "Yellow" })
Write-Host ""
