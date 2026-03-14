# ===== Load shared helpers (WT path detection, etc.) =====
$_commonScript = if ($env:PNX_TERMINAL_REPO) { "$env:PNX_TERMINAL_REPO\scripts\common.ps1" } else { $null }
if ($_commonScript -and (Test-Path $_commonScript)) {
    . $_commonScript
    $WtSettingsPath = Get-WtSettingsPath -Mode file
} else {
    # Inline fallback if common.ps1 not available (first boot before bootstrap)
    $WtSettingsPath = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
Remove-Variable _commonScript -ErrorAction SilentlyContinue

# ===== Theme & Style Database =====
$PnxThemes = if ($env:PNX_OMP_THEMES) { $env:PNX_OMP_THEMES } else { "$env:USERPROFILE\.oh-my-posh\themes" }

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
        if ($_defaults) {
            # Prefer stored pnx markers (written by Set-Theme), fallback to heuristic match
            # Cross-validate: if marker exists but conflicts with colorScheme, trust colorScheme
            if ($_defaults.pnxTheme -and $ThemeDB.ContainsKey($_defaults.pnxTheme)) {
                $markerScheme = $ThemeDB[$_defaults.pnxTheme].scheme
                if ($_defaults.colorScheme -and $markerScheme -ne $_defaults.colorScheme) {
                    # Marker stale — colorScheme was changed outside Set-Theme, fallback to heuristic
                    $Global:PnxCurrentTheme = "pro"
                    foreach ($k in $ThemeDB.Keys) {
                        if ($ThemeDB[$k].scheme -eq $_defaults.colorScheme) { $Global:PnxCurrentTheme = $k; break }
                    }
                } else {
                    $Global:PnxCurrentTheme = $_defaults.pnxTheme
                }
            } else {
                foreach ($k in $ThemeDB.Keys) {
                    if ($ThemeDB[$k].scheme -eq $_defaults.colorScheme) { $Global:PnxCurrentTheme = $k; break }
                }
            }
            if ($_defaults.pnxStyle -and $StyleDB.ContainsKey($_defaults.pnxStyle)) {
                $Global:PnxCurrentStyle = $_defaults.pnxStyle
            } else {
                # Multi-field heuristic: match on opacity + useAcrylic + padding (needs 2+ matches)
                $bestMatch = $null; $bestScore = 0
                foreach ($k in $StyleDB.Keys) {
                    $s = $StyleDB[$k]; $score = 0
                    if ($null -ne $_defaults.opacity    -and $s.opacity    -eq $_defaults.opacity)    { $score++ }
                    if ($null -ne $_defaults.useAcrylic -and $s.useAcrylic -eq $_defaults.useAcrylic) { $score++ }
                    if ($null -ne $_defaults.padding    -and $s.padding    -eq $_defaults.padding)    { $score++ }
                    if ($score -gt $bestScore) { $bestScore = $score; $bestMatch = $k }
                }
                if ($bestMatch -and $bestScore -ge 2) { $Global:PnxCurrentStyle = $bestMatch }
            }
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
    zoxide init powershell | Out-String | Invoke-Expression
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

# ===== Tab Completion for Set-Theme / Set-Style =====
# Note: ScriptBlocks run in their own scope — cannot access $ThemeDB/$StyleDB, so values are listed explicitly.
Register-ArgumentCompleter -CommandName Set-Theme -ParameterName Theme -ScriptBlock {
    param($cmd, $param, $word)
    @('pro','dracula','tokyo','mocha','nord') | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -CommandName Set-Theme -ParameterName Style -ScriptBlock {
    param($cmd, $param, $word)
    @('mac','win','linux') | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -CommandName Set-Style -ParameterName Style -ScriptBlock {
    param($cmd, $param, $word)
    @('mac','win','linux') | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
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

    # Guard: ensure profiles.defaults exists
    if (-not $json.profiles.defaults) {
        $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{})
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

    # Store pnx markers for reliable detection on next profile load
    foreach ($prop in @('pnxTheme', 'pnxStyle')) {
        $val = if ($prop -eq 'pnxTheme') { $Theme } else { $Style }
        if (-not $d.PSObject.Properties[$prop]) {
            $d | Add-Member -NotePropertyName $prop -NotePropertyValue $val
        } else { $d.$prop = $val }
    }

    $json.theme = $t.wtTheme

    $activeTheme = $json.themes | Where-Object { $_.name -eq $t.wtTheme }
    if ($activeTheme -and $activeTheme.window) {
        $activeTheme.window.useMica = $s.useMica
    } elseif ($s.useMica) {
        Write-Host "  WT theme '$($t.wtTheme)' not found — Mica not applied." -ForegroundColor Yellow
    }

    # Atomic write: backup → temp file → rename (with retry if WT holds file lock)
    Copy-Item $WtSettingsPath "$WtSettingsPath.pnx-backup" -Force -ErrorAction SilentlyContinue
    $tempPath = "$WtSettingsPath.pnx-tmp"
    $json | ConvertTo-Json -Depth 20 | Set-Content $tempPath -Encoding utf8NoBOM
    $written = $false
    for ($retry = 0; $retry -lt 3; $retry++) {
        try {
            Move-Item $tempPath $WtSettingsPath -Force -ErrorAction Stop
            $written = $true
            break
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $written) {
        # Last resort: direct write (non-atomic but better than silent failure)
        try {
            $json | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding utf8NoBOM
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            $written = $true
        } catch {
            Write-Host "  OMP switched but WT settings locked — restart terminal and retry." -ForegroundColor Red
            return
        }
    }

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
    param(
        [Parameter(Position=0)][ValidateSet('push','pull')][string]$Direction,
        [switch]$Force
    )
    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }
    if ($Direction -eq 'push') { & "$repo\scripts\sync-to-repo.ps1" -Force:$Force }
    elseif ($Direction -eq 'pull') { & "$repo\scripts\sync-from-repo.ps1" }
    else { Write-Host "  Usage: Sync-Config push|pull [-Force]" -ForegroundColor Yellow }
}

function Get-Status {
    $script = "$env:PNX_TERMINAL_REPO\scripts\status.ps1"
    if (Test-Path $script) { & $script }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}

function Update-Workspace {
    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }

    Write-Host "`n  Updating Terminal Workspace..." -ForegroundColor Cyan
    Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

    # 1. Git pull
    Write-Host "`n  Pulling latest changes..." -ForegroundColor Cyan
    $prevDir = Get-Location
    Set-Location $repo
    $pullOutput = git pull 2>&1 | Out-String
    Set-Location $prevDir
    $hasChanges = $pullOutput -notmatch 'Already up to date'
    if ($hasChanges) {
        Write-Host $pullOutput.Trim() -ForegroundColor DarkGray
    } else {
        Write-Host "  Already up to date." -ForegroundColor DarkGray
    }

    # 2. Re-deploy configs (always — user may want to re-apply even without new commits)
    Write-Host "`n  Re-deploying configs..." -ForegroundColor Cyan
    & "$repo\scripts\sync-from-repo.ps1"

    # 3. Reload profile
    Write-Host "`n  Reloading profile..." -ForegroundColor Cyan
    . $PROFILE
    Write-Host "  Done. Workspace updated." -ForegroundColor Green
    Write-Host ""
}
