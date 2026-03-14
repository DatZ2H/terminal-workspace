# ===== Oh My Posh =====
$PnxThemes = "$env:USERPROFILE\.oh-my-posh\themes"
$Global:PnxCurrentTheme = "pro"
$Global:PnxCurrentStyle = "mac"

$_ompConfig = "$PnxThemes\pnx-dracula-pro.omp.json"
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $_ompConfig)) {
    oh-my-posh init pwsh --config $_ompConfig | Invoke-Expression
}

# ===== Terminal Icons =====
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# ===== PSReadLine =====
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z -Function Undo
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# ===== Theme & Style Database =====
$WtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

$ThemeDB = @{
    pro     = @{ omp = "$PnxThemes\pnx-dracula-pro.omp.json";  scheme = "Dracula Pro";       wtTheme = "PNX Dracula Pro"  }
    dracula = @{ omp = "$PnxThemes\pnx-dracula.omp.json";      scheme = "Dracula";            wtTheme = "PNX Dracula"      }
    tokyo   = @{ omp = "$PnxThemes\pnx-tokyo-storm.omp.json";  scheme = "Tokyo Night Storm";  wtTheme = "PNX Tokyo Night"  }
    mocha   = @{ omp = "$PnxThemes\pnx-mocha.omp.json";        scheme = "Catppuccin Mocha";   wtTheme = "PNX Mocha"        }
    nord    = @{ omp = "$PnxThemes\pnx-nord.omp.json";         scheme = "Nord";               wtTheme = "PNX Nord"         }
}

$StyleDB = @{
    mac   = @{ opacity = 85;  useAcrylic = $true;  useMica = $false; padding = "16, 12, 16, 12"; cursorShape = "bar";       scrollbarState = "hidden";  unfocusedOpacity = 70  }
    win   = @{ opacity = 95;  useAcrylic = $false; useMica = $true;  padding = "8, 8, 8, 8";     cursorShape = "bar";       scrollbarState = "hidden";  unfocusedOpacity = 90  }
    linux = @{ opacity = 100; useAcrylic = $false; useMica = $false; padding = "4, 4, 4, 4";     cursorShape = "filledBox"; scrollbarState = "visible"; unfocusedOpacity = 100 }
}

# ===== Unified Theme Switcher =====
function Set-Theme {
    param(
        [Parameter(Position=0)][string]$Theme,
        [Parameter(Position=1)][string]$Style
    )

    if (-not $Theme) {
        Write-Host ""
        Write-Host "  Current: " -NoNewline
        Write-Host "$Global:PnxCurrentTheme" -ForegroundColor Cyan -NoNewline
        Write-Host " + " -NoNewline
        Write-Host "$Global:PnxCurrentStyle" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Themes:  pro  dracula  tokyo  mocha  nord" -ForegroundColor DarkGray
        Write-Host "  Styles:  mac  win  linux" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Usage:   Set-Theme <theme> [style]" -ForegroundColor DarkGray
        Write-Host "           Set-Style <style>" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    if (-not $ThemeDB.ContainsKey($Theme)) {
        Write-Host "  Unknown theme '$Theme'" -ForegroundColor Red
        Write-Host "  Available: $($ThemeDB.Keys -join ', ')" -ForegroundColor DarkGray
        return
    }

    if (-not $Style) { $Style = $Global:PnxCurrentStyle }

    if (-not $StyleDB.ContainsKey($Style)) {
        Write-Host "  Unknown style '$Style'" -ForegroundColor Red
        Write-Host "  Available: mac, win, linux" -ForegroundColor DarkGray
        return
    }

    $t = $ThemeDB[$Theme]
    $s = $StyleDB[$Style]

    # 1. Switch OMP prompt
    oh-my-posh init pwsh --config $t.omp | Invoke-Expression

    # 2. Update Windows Terminal settings
    if (-not (Test-Path $WtSettingsPath)) {
        Write-Host "  OMP switched. WT settings not found — skipped." -ForegroundColor Yellow
        $Global:PnxCurrentTheme = $Theme
        $Global:PnxCurrentStyle = $Style
        return
    }

    $json = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json

    $d = $json.profiles.defaults
    $d.colorScheme    = $t.scheme
    $d.opacity        = $s.opacity
    $d.useAcrylic     = $s.useAcrylic
    $d.padding        = $s.padding
    $d.cursorShape    = $s.cursorShape
    $d.scrollbarState = $s.scrollbarState
    if ($d.unfocusedAppearance) {
        $d.unfocusedAppearance.opacity = $s.unfocusedOpacity
    }

    $json.theme = $t.wtTheme

    $activeTheme = $json.themes | Where-Object { $_.name -eq $t.wtTheme }
    if ($activeTheme -and $activeTheme.window) {
        $activeTheme.window.useMica = $s.useMica
    }

    $json | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding utf8NoBOM

    $Global:PnxCurrentTheme = $Theme
    $Global:PnxCurrentStyle = $Style

    Write-Host "  $Theme + $Style" -ForegroundColor Green
}

function Set-Style {
    param([Parameter(Position=0)][string]$Style)
    if (-not $Style) {
        Write-Host "  Current: $Global:PnxCurrentStyle" -ForegroundColor Cyan
        Write-Host "  Available: mac, win, linux" -ForegroundColor DarkGray
        return
    }
    Set-Theme -Theme $Global:PnxCurrentTheme -Style $Style
}

# ===== Maintenance Functions =====
function Update-Tools {
    Write-Host "`n  Updating tools..." -ForegroundColor Cyan

    $packages = @("JanDeDobbeleer.OhMyPosh", "Git.Git", "OpenJS.NodeJS.LTS", "Python.Python.3.12")
    foreach ($pkg in $packages) {
        Write-Host "  winget: $pkg" -ForegroundColor DarkGray
        winget upgrade --id $pkg --accept-package-agreements --accept-source-agreements --silent 2>$null
    }

    Write-Host "  module: Terminal-Icons" -ForegroundColor DarkGray
    Update-Module Terminal-Icons -Force -ErrorAction SilentlyContinue

    Write-Host "  font: CaskaydiaCove Nerd Font" -ForegroundColor DarkGray
    oh-my-posh font install CascadiaCode 2>$null

    Write-Host "`n  Done." -ForegroundColor Green
}

function Sync-Config {
    param([Parameter(Position=0)][ValidateSet('push','pull')][string]$Direction)

    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found." -ForegroundColor Red
        Write-Host "  Set env var PNX_TERMINAL_REPO to your terminal-workspace path." -ForegroundColor Yellow
        return
    }

    $profileLocal = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1"
    $wtLocal      = $WtSettingsPath
    $themesLocal  = "$env:USERPROFILE\.oh-my-posh\themes"

    if ($Direction -eq 'push') {
        Copy-Item $profileLocal "$repo\configs\profile.ps1" -Force
        Copy-Item $wtLocal "$repo\configs\terminal-settings.json" -Force
        Get-ChildItem $themesLocal -Filter "pnx-*.omp.json" | Copy-Item -Destination "$repo\themes\" -Force
        Write-Host "  Pushed local configs to repo." -ForegroundColor Green
    }
    elseif ($Direction -eq 'pull') {
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        if (Test-Path $profileLocal) { Copy-Item $profileLocal "$profileLocal.backup-$ts" }
        if (Test-Path $wtLocal)      { Copy-Item $wtLocal "$wtLocal.backup-$ts" }
        Copy-Item "$repo\configs\profile.ps1" $profileLocal -Force
        Copy-Item "$repo\configs\terminal-settings.json" $wtLocal -Force
        if (-not (Test-Path $themesLocal)) { New-Item -ItemType Directory -Path $themesLocal -Force | Out-Null }
        Copy-Item "$repo\themes\*.omp.json" $themesLocal -Force
        Write-Host "  Pulled repo configs to local. Restart terminal to apply." -ForegroundColor Green
    }
    else {
        Write-Host "  Usage: Sync-Config push | pull" -ForegroundColor Yellow
    }
}

function Get-Status {
    Write-Host "`n  Tool Versions" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray

    $tools = @(
        @{ Name = "PowerShell";     Cmd = { $PSVersionTable.PSVersion.ToString() } }
        @{ Name = "Oh My Posh";     Cmd = { oh-my-posh version 2>$null } }
        @{ Name = "Git";            Cmd = { (git --version 2>$null) -replace 'git version ','' } }
        @{ Name = "Node.js";        Cmd = { (node --version 2>$null) -replace 'v','' } }
        @{ Name = "npm";            Cmd = { npm --version 2>$null } }
        @{ Name = "Python";         Cmd = { (python --version 2>$null) -replace 'Python ','' } }
        @{ Name = "PSReadLine";     Cmd = { (Get-Module PSReadLine -ErrorAction SilentlyContinue).Version.ToString() } }
        @{ Name = "Terminal-Icons"; Cmd = { (Get-Module Terminal-Icons -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1).Version.ToString() } }
        @{ Name = "Claude Code";    Cmd = { claude --version 2>$null } }
    )

    foreach ($t in $tools) {
        $ver = try { & $t.Cmd } catch { $null }
        $color = if ($ver) { "Green" } else { "Red" }
        if (-not $ver) { $ver = "not found" }
        Write-Host ("  {0,-18}" -f $t.Name) -NoNewline
        Write-Host $ver -ForegroundColor $color
    }

    Write-Host "`n  Config Locations" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray
    $cfgPaths = @(
        @{ Name = "PS Profile";  Path = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell\Microsoft.PowerShell_profile.ps1") }
        @{ Name = "WT Settings"; Path = $WtSettingsPath }
        @{ Name = "OMP Themes";  Path = "$env:USERPROFILE\.oh-my-posh\themes" }
        @{ Name = "VN Fix";      Path = "$env:USERPROFILE\.claude-vn-fix\patcher.py" }
    )
    foreach ($p in $cfgPaths) {
        $exists = Test-Path $p.Path
        $status = if ($exists) { "OK" } else { "MISSING" }
        $color  = if ($exists) { "Green" } else { "Red" }
        Write-Host ("  {0,-18}{1,-10}" -f $p.Name, $status) -ForegroundColor $color
    }

    Write-Host "`n  Current Theme" -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Theme: " -NoNewline
    Write-Host $Global:PnxCurrentTheme -ForegroundColor Cyan
    Write-Host "  Style: " -NoNewline
    Write-Host $Global:PnxCurrentStyle -ForegroundColor Green
    Write-Host ""
}

# ===== Claude Code Shortcuts =====
$GuideClaudeDir = if ($env:PNX_GUIDE_CLAUDE_DIR) { $env:PNX_GUIDE_CLAUDE_DIR } else { "$env:USERPROFILE\Claude\Cowork\PNX-Vault\Guide Claude" }
function gc-doc { if (-not (Test-Path $GuideClaudeDir)) { Write-Host "  Path not found: $GuideClaudeDir" -ForegroundColor Red; Write-Host "  Set env var PNX_GUIDE_CLAUDE_DIR" -ForegroundColor Yellow; return }; Set-Location $GuideClaudeDir; claude }
function gs-doc { if (-not (Test-Path $GuideClaudeDir)) { Write-Host "  Path not found. Set PNX_GUIDE_CLAUDE_DIR" -ForegroundColor Red; return }; Set-Location $GuideClaudeDir; git status }
function gl-doc { if (-not (Test-Path $GuideClaudeDir)) { Write-Host "  Path not found. Set PNX_GUIDE_CLAUDE_DIR" -ForegroundColor Red; return }; Set-Location $GuideClaudeDir; git log --oneline -10 }
function gd-doc { if (-not (Test-Path $GuideClaudeDir)) { Write-Host "  Path not found. Set PNX_GUIDE_CLAUDE_DIR" -ForegroundColor Red; return }; Set-Location $GuideClaudeDir; git diff --stat }

Set-Alias cc claude

# ===== Vietnamese IME Fix =====
function update-claude {
    npm update -g @anthropic-ai/claude-code
    $patcher = "$env:USERPROFILE\.claude-vn-fix\patcher.py"
    if (-not (Test-Path $patcher)) {
        Write-Host "  Patcher not found: $patcher" -ForegroundColor Red
        return
    }
    $npmRoot = (npm root -g 2>$null | Out-String).Trim()
    $cliJs = Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
    if (-not (Test-Path $cliJs)) {
        Write-Host "  Claude Code cli.js not found at: $cliJs" -ForegroundColor Red
        return
    }
    if (Select-String -Path $cliJs -Pattern "Vietnamese IME fix" -Quiet) {
        Write-Host "  Vietnamese patch already applied."
    } else {
        Write-Host "  Applying Vietnamese IME patch..."
        $env:PYTHONIOENCODING = "utf-8"
        python $patcher --path $cliJs
    }
}
