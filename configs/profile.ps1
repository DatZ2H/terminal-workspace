# ===== WT Settings Path Detection (Store + non-Store) =====
$_wtPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$WtSettingsPath = $_wtPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

# ===== Theme & Style Database =====
$PnxThemes = "$env:USERPROFILE\.oh-my-posh\themes"

$ThemeDB = @{
    pro     = @{ omp = "$PnxThemes\pnx-dracula-pro.omp.json";  scheme = "Dracula Pro";       wtTheme = "PNX Dracula Pro"  }
    dracula = @{ omp = "$PnxThemes\pnx-dracula.omp.json";      scheme = "Dracula";            wtTheme = "PNX Dracula"      }
    tokyo   = @{ omp = "$PnxThemes\pnx-tokyo-storm.omp.json";  scheme = "Tokyo Night Storm";  wtTheme = "PNX Tokyo Night"  }
    mocha   = @{ omp = "$PnxThemes\pnx-mocha.omp.json";        scheme = "Catppuccin Mocha";   wtTheme = "PNX Mocha"        }
    nord    = @{ omp = "$PnxThemes\pnx-nord.omp.json";         scheme = "Nord";               wtTheme = "PNX Nord"         }
}

$StyleDB = @{
    mac   = @{ opacity = 85;  useAcrylic = $true;  useMica = $false; padding = "16, 12, 16, 12"; cursorShape = "bar";       scrollbarState = "visible"; unfocusedOpacity = 70  }
    win   = @{ opacity = 95;  useAcrylic = $false; useMica = $true;  padding = "8, 8, 8, 8";     cursorShape = "bar";       scrollbarState = "visible"; unfocusedOpacity = 90  }
    linux = @{ opacity = 100; useAcrylic = $false; useMica = $false; padding = "4, 4, 4, 4";     cursorShape = "filledBox"; scrollbarState = "visible"; unfocusedOpacity = 100 }
}

# ===== Detect Current Theme & Style from WT Settings =====
$Global:PnxCurrentTheme = "pro"
$Global:PnxCurrentStyle = "mac"

if ($WtSettingsPath) {
    try {
        $_wtJson = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
        $_defaults = $_wtJson.profiles.defaults
        foreach ($k in $ThemeDB.Keys) {
            if ($ThemeDB[$k].scheme -eq $_defaults.colorScheme) { $Global:PnxCurrentTheme = $k; break }
        }
        foreach ($k in $StyleDB.Keys) {
            if ($StyleDB[$k].opacity -eq $_defaults.opacity) { $Global:PnxCurrentStyle = $k; break }
        }
        Remove-Variable _wtJson, _defaults -ErrorAction SilentlyContinue
    } catch {}
}

# ===== Oh My Posh (init with detected theme) =====
$_ompConfig = $ThemeDB[$Global:PnxCurrentTheme].omp
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $_ompConfig)) {
    oh-my-posh init pwsh --config $_ompConfig | Invoke-Expression
}

# ===== Terminal Icons =====
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# ===== Zoxide =====
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ===== Encoding (Vietnamese support) =====
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ===== PSReadLine =====
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -HistoryNoDuplicates:$true
Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true
Set-PSReadLineOption -ShowToolTips:$true
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z -Function Undo
Set-PSReadLineKeyHandler -Key Ctrl+w -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# ===== Default Parameters =====
$PSDefaultParameterValues['Install-Module:Scope'] = 'CurrentUser'

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
    if (-not (Test-Path $t.omp)) {
        Write-Host "  Theme file not found: $($t.omp)" -ForegroundColor Red
        return
    }
    oh-my-posh init pwsh --config $t.omp | Invoke-Expression

    # 2. Update Windows Terminal settings
    if (-not $WtSettingsPath) {
        Write-Host "  OMP switched. WT not found — skipped." -ForegroundColor Yellow
        $Global:PnxCurrentTheme = $Theme
        $Global:PnxCurrentStyle = $Style
        return
    }

    try {
        $json = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  OMP switched. WT settings.json is corrupt — skipped." -ForegroundColor Red
        $Global:PnxCurrentTheme = $Theme
        $Global:PnxCurrentStyle = $Style
        return
    }

    $d = $json.profiles.defaults
    $d.colorScheme    = $t.scheme
    $d.opacity        = $s.opacity
    $d.useAcrylic     = $s.useAcrylic
    $d.padding        = $s.padding
    $d.cursorShape    = $s.cursorShape
    $d.scrollbarState = $s.scrollbarState

    if (-not $d.unfocusedAppearance) {
        $d | Add-Member -NotePropertyName unfocusedAppearance -NotePropertyValue ([PSCustomObject]@{ opacity = $s.unfocusedOpacity })
    } else {
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

# ===== Maintenance Functions (delegate to standalone scripts) =====
function Update-Tools {
    $script = "$env:PNX_TERMINAL_REPO\scripts\update-tools.ps1"
    if (Test-Path $script) { & $script @args }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}

function Sync-Config {
    param([Parameter(Position=0)][ValidateSet('push','pull')][string]$Direction)
    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }
    if ($Direction -eq 'push') { & "$repo\scripts\sync-to-repo.ps1" }
    elseif ($Direction -eq 'pull') { & "$repo\scripts\sync-from-repo.ps1" }
    else { Write-Host "  Usage: Sync-Config push | pull" -ForegroundColor Yellow }
}

function Get-Status {
    $script = "$env:PNX_TERMINAL_REPO\scripts\status.ps1"
    if (Test-Path $script) { & $script }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}
