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
)

foreach ($c in $checks) {
    $ver = try { & $c.Cmd } catch { $null }
    $color = if ($ver) { "Green" } else { "Red" }
    if (-not $ver) { $ver = "not found" }
    Write-Host ("  {0,-18}" -f $c.Name) -NoNewline
    Write-Host $ver -ForegroundColor $color
}

. "$PSScriptRoot\common.ps1"
$wtSettingsPath = Get-WtSettingsPath -Mode file
if (-not $wtSettingsPath) {
    # Fallback to Store path for display purposes
    $wtSettingsPath = Get-WtSettingsPath -Mode deploy
}

Write-Host "`n  Config Locations" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────" -ForegroundColor DarkGray

$paths = @(
    @{ Name = "PS Profile";  Path = $PsProfilePath }
    @{ Name = "WT Settings"; Path = $wtSettingsPath }
    @{ Name = "OMP Themes";  Path = $OmpThemesLocal }
)

foreach ($p in $paths) {
    $exists = Test-Path $p.Path
    $status = if ($exists) { "OK" } else { "MISSING" }
    $color  = if ($exists) { "Green" } else { "Red" }
    Write-Host ("  {0,-18}" -f $p.Name) -NoNewline
    Write-Host ("{0,-10}" -f $status) -ForegroundColor $color -NoNewline
    Write-Host $p.Path -ForegroundColor DarkGray
}

# Nerd Font check
Write-Host "`n  Nerd Font" -ForegroundColor Cyan
Write-Host "  ────────────────────────────────────" -ForegroundColor DarkGray
$fi = Get-NerdFontInfo
if ($fi.Installed) {
    $_ver = if ($fi.HasV3) { "v3 ($($fi.FontFace))" } else { "v2 ($($fi.FontFace))" }
    Write-Host ("  {0,-18}" -f "CaskaydiaCove") -NoNewline
    Write-Host $_ver -ForegroundColor Green
} else {
    Write-Host ("  {0,-18}" -f "CaskaydiaCove") -NoNewline
    Write-Host "NOT INSTALLED — run: oh-my-posh font install CascadiaCode" -ForegroundColor Red
}
# Check WT font face matches installed version
if ($fi.FontFace -and $wtSettingsPath -and (Test-Path $wtSettingsPath)) {
    try {
        $_wtJson = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
        $_currentFace = $_wtJson.profiles.defaults.font.face
    } catch { $_currentFace = $null }
    if ($_currentFace -and $_currentFace -ne $fi.FontFace) {
        Write-Host ("  {0,-18}" -f "WT font face") -NoNewline
        Write-Host "MISMATCH — WT uses '$_currentFace' but '$($fi.FontFace)' is installed" -ForegroundColor Yellow
    } elseif ($_currentFace) {
        Write-Host ("  {0,-18}" -f "WT font face") -NoNewline
        Write-Host "OK" -ForegroundColor Green
    }
}

# Theme count
$themeCount = (Get-ChildItem $OmpThemesLocal -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue).Count
Write-Host "`n  PNX Themes:      $themeCount installed" -ForegroundColor $(if ($themeCount -gt 0) { "Green" } else { "Yellow" })
Write-Host ""
