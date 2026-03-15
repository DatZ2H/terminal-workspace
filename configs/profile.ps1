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
    pro        = @{ omp = "$PnxThemes\pnx-dracula-pro.omp.json";    scheme = "Dracula Pro";            wtTheme = "PNX Dracula Pro"      }
    dracula    = @{ omp = "$PnxThemes\pnx-dracula.omp.json";        scheme = "Dracula";                wtTheme = "PNX Dracula"          }
    tokyo      = @{ omp = "$PnxThemes\pnx-tokyo-storm.omp.json";    scheme = "Tokyo Night Storm";      wtTheme = "PNX Tokyo Night"      }
    mocha      = @{ omp = "$PnxThemes\pnx-mocha.omp.json";          scheme = "Catppuccin Mocha";       wtTheme = "PNX Mocha"            }
    nord       = @{ omp = "$PnxThemes\pnx-nord.omp.json";           scheme = "Nord";                   wtTheme = "PNX Nord"             }
    seagreen   = @{ omp = "$PnxThemes\pnx-dark-sea-green.omp.json"; scheme = "Dark Sea Green";         wtTheme = "PNX Dark Sea Green"   }
    organic    = @{ omp = "$PnxThemes\pnx-organic-green.omp.json";  scheme = "Organic Green";          wtTheme = "PNX Organic Green"    }
    nihileaf   = @{ omp = "$PnxThemes\pnx-nihileaf.omp.json";       scheme = "Nihileaf";               wtTheme = "PNX Nihileaf"         }
    miasma     = @{ omp = "$PnxThemes\pnx-miasma.omp.json";         scheme = "Miasma";                 wtTheme = "PNX Miasma"           }
    jake       = @{ omp = "$PnxThemes\pnx-jake-green-grey.omp.json";scheme = "Jake Green Grey";        wtTheme = "PNX Jake Green Grey"  }
    kryptonite = @{ omp = "$PnxThemes\pnx-kryptonite.omp.json";     scheme = "Kryptonite";             wtTheme = "PNX Kryptonite"       }
    fl0        = @{ omp = "$PnxThemes\pnx-fl0.omp.json";            scheme = "fl0-c0d3";               wtTheme = "PNX fl0-c0d3"         }
    greendark  = @{ omp = "$PnxThemes\pnx-green-dark.omp.json";     scheme = "Green Dark Supercharged";wtTheme = "PNX Green Dark"       }
    greennord  = @{ omp = "$PnxThemes\pnx-green-nordic.omp.json";   scheme = "Green Nordic";           wtTheme = "PNX Green Nordic"     }
}

$StyleDB = @{
    mac   = @{ opacity = 85;  useAcrylic = $true;  useMica = $false; padding = "16, 12, 16, 12"; cursorShape = "bar";       scrollbarState = "visible"; unfocusedOpacity = 70  }
    win   = @{ opacity = 95;  useAcrylic = $false; useMica = $true;  padding = "8, 8, 8, 8";     cursorShape = "bar";       scrollbarState = "visible"; unfocusedOpacity = 90  }
    linux = @{ opacity = 100; useAcrylic = $false; useMica = $false; padding = "4, 4, 4, 4";     cursorShape = "filledBox"; scrollbarState = "visible"; unfocusedOpacity = 100 }
}

# ===== Health Check (collect issues, report once at end) =====
$_healthIssues = @()

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
    } catch {
        $_healthIssues += "WT settings.json unreadable — theme/style detection skipped"
    }
}

# ===== Oh My Posh (init with detected theme) =====
$_ompConfig = $ThemeDB[$Global:PnxCurrentTheme].omp
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    $_healthIssues += "Oh My Posh not found — run:  winget install JanDeDobbeleer.OhMyPosh"
} elseif (-not (Test-Path $_ompConfig)) {
    $_healthIssues += "OMP theme file missing — run:  Update-Workspace"
    # Try fallback to any available PNX theme
    $_fallback = Get-ChildItem $PnxThemes -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($_fallback) { oh-my-posh init pwsh --config $_fallback.FullName | Invoke-Expression }
} else {
    oh-my-posh init pwsh --config $_ompConfig | Invoke-Expression
}

# ===== Terminal Icons (auto-install if missing) =====
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
} else {
    # Try auto-install silently (ensure NuGet provider + PSGallery trust first)
    try {
        # Pre-install NuGet provider to avoid interactive prompt that blocks terminal startup
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [Version]"2.8.5.201" })) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop *>$null
        }
        Install-Module Terminal-Icons -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop *>$null
        Import-Module Terminal-Icons
    } catch {
        $_healthIssues += "Terminal-Icons missing (ls has no icons) -- run:  Install-Module Terminal-Icons -Force"
    }
}

# ===== Nerd Font check (verify CaskaydiaCove is available) =====
$_fontInfo = if (Get-Command Get-NerdFontInfo -ErrorAction SilentlyContinue) { Get-NerdFontInfo } else { $null }
if (-not $_fontInfo -or -not $_fontInfo.Installed) {
    # Auto-install if oh-my-posh is available
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        try {
            oh-my-posh font install CascadiaCode *>$null
            if ($LASTEXITCODE -eq 0) { $_fontInfo = @{ Installed = $true } }
        } catch {}
    }
    if (-not $_fontInfo -or -not $_fontInfo.Installed) {
        $_healthIssues += "CaskaydiaCove Nerd Font missing (icons broken) — run:  oh-my-posh font install CascadiaCode"
    }
}
Remove-Variable _fontInfo -ErrorAction SilentlyContinue

# ===== Auto-fix WT font face if using stale v2/v3 name =====
if (Get-Command Repair-WtFontFace -ErrorAction SilentlyContinue) {
    try { Repair-WtFontFace -WtPath $WtSettingsPath | Out-Null } catch {
        $_healthIssues += "WT font face repair failed: $_"
    }
}

# ===== Zoxide =====
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    zoxide init powershell | Out-String | Invoke-Expression
}

# ===== Encoding (Vietnamese support) =====
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ===== PSReadLine =====
$_pslVersion = (Get-Module PSReadLine -ErrorAction SilentlyContinue).Version
if ($_pslVersion -and $_pslVersion -ge [Version]"2.2.0") {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
}
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
Remove-Variable _pslVersion -ErrorAction SilentlyContinue

# ===== Report health issues (once, non-intrusive) =====
if ($_healthIssues.Count -gt 0) {
    Write-Host ""
    Write-Host "  PNX Health:" -ForegroundColor Yellow
    foreach ($issue in $_healthIssues) {
        Write-Host "    - $issue" -ForegroundColor Yellow
    }
    Write-Host ""
}
Remove-Variable _healthIssues -ErrorAction SilentlyContinue

# ===== Default Parameters =====
$PSDefaultParameterValues['Install-Module:Scope'] = 'CurrentUser'

# ===== Tab Completion for Set-Theme / Set-Style =====
Register-ArgumentCompleter -CommandName Set-Theme -ParameterName Theme -ScriptBlock {
    param($cmd, $param, $word)
    $ThemeDB.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $ThemeDB[$_].scheme)
    }
}.GetNewClosure()
Register-ArgumentCompleter -CommandName Set-Theme -ParameterName Style -ScriptBlock {
    param($cmd, $param, $word)
    $StyleDB.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}.GetNewClosure()
Register-ArgumentCompleter -CommandName Set-Style -ParameterName Style -ScriptBlock {
    param($cmd, $param, $word)
    $StyleDB.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}.GetNewClosure()

# ===== Theme List Display =====
function Get-ThemeList {
    $sorted = $ThemeDB.Keys | Sort-Object
    $count  = $sorted.Count
    Write-Host ""
    Write-Host "  PNX Themes ($count available)" -ForegroundColor White
    Write-Host ""

    foreach ($key in $sorted) {
        $scheme = $ThemeDB[$key].scheme
        $active = $key -eq $Global:PnxCurrentTheme
        $marker = if ($active) { "> " } else { "  " }
        $color  = if ($active) { "Cyan" } else { "DarkGray" }
        Write-Host "  $marker$($key.PadRight(13))$scheme" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Style: $Global:PnxCurrentStyle" -ForegroundColor DarkGray
    Write-Host ""
}

# ===== Interactive Theme Selector =====
function Select-ThemeInteractive {
    $esc = [char]27
    $sorted = $ThemeDB.Keys | Sort-Object
    if ($sorted.Count -eq 0) { return $null }

    # Find initial cursor position (current active theme)
    $idx = 0
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i] -eq $Global:PnxCurrentTheme) { $idx = $i; break }
    }

    $count = $sorted.Count

    # --- Render helpers ---
    function Format-Row($key, $pos, $curIdx, $activeKey) {
        $scheme = $ThemeDB[$key].scheme
        $isCursor = $pos -eq $curIdx
        $isActive = $key -eq $activeKey
        if ($isCursor) {
            $marker = "> "
        } elseif ($isActive) {
            $marker = "* "
        } else {
            $marker = "  "
        }
        $text = "  $marker$($key.PadRight(13))$scheme"
        if ($isCursor) {
            return "$esc[7m$text$esc[0m"
        } elseif ($isActive) {
            return "$esc[36m$text$esc[0m"
        } else {
            return "$esc[90m$text$esc[0m"
        }
    }

    try {
        # Hide cursor
        [Console]::Write("$esc[?25l")

        # Initial full render
        [Console]::WriteLine("")
        [Console]::WriteLine("$esc[97m  PNX Themes ($count available)$esc[0m")
        [Console]::WriteLine("")
        for ($i = 0; $i -lt $count; $i++) {
            [Console]::WriteLine((Format-Row $sorted[$i] $i $idx $Global:PnxCurrentTheme))
        }
        [Console]::WriteLine("")
        [Console]::WriteLine("$esc[90m  Up/Down: navigate  Enter: apply  Esc: cancel$esc[0m")
        [Console]::WriteLine("")

        # Input loop
        while ($true) {
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'Escape') {
                return $null
            }

            if ($key.Key -eq 'Enter') {
                return $sorted[$idx]
            }

            $prevIdx = $idx
            if ($key.Key -eq 'UpArrow' -and $idx -gt 0) {
                $idx--
            } elseif ($key.Key -eq 'DownArrow' -and $idx -lt ($count - 1)) {
                $idx++
            } else {
                continue
            }

            # Redraw only changed rows (previous and new cursor position)
            # Distance from current cursor (after footer) to a theme row:
            # footer has 3 lines, themes are 0-indexed from top of theme block
            # Row $i is at offset: (footer 3 lines) + ($count - 1 - $i) lines up from current pos

            foreach ($ri in @($prevIdx, $idx)) {
                $linesUp = 3 + ($count - 1 - $ri)
                $line = Format-Row $sorted[$ri] $ri $idx $Global:PnxCurrentTheme
                [Console]::Write("$esc[$($linesUp)A$esc[2K$line$esc[$($linesUp)B`r")
            }
        }
    } finally {
        # Restore cursor
        [Console]::Write("$esc[?25h")
    }
}

# ===== Unified Theme Switcher =====
function Set-Theme {
    param(
        [Parameter(Position=0)][string]$Theme,
        [Parameter(Position=1)][string]$Style
    )

    if (-not $Theme) {
        $picked = Select-ThemeInteractive
        if ($picked) {
            Set-Theme $picked
        } else {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
        }
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
    elseif ($Direction -eq 'pull') {
        & "$repo\scripts\sync-from-repo.ps1"
        Write-Host "  Reloading profile..." -ForegroundColor Cyan
        . $PROFILE
    }
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
    try {
        Set-Location $repo
        $pullOutput = git pull 2>&1 | Out-String
    } finally {
        Set-Location $prevDir
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  git pull failed (exit $LASTEXITCODE). Check network or credentials." -ForegroundColor Red
        Write-Host $pullOutput.Trim() -ForegroundColor DarkGray
        return
    } elseif ($pullOutput -match 'Already up to date') {
        Write-Host "  Already up to date." -ForegroundColor DarkGray
    } else {
        Write-Host $pullOutput.Trim() -ForegroundColor DarkGray
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
