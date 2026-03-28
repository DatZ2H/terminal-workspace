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

# ===== Load Theme & Style config from manifest =====
$_pnxManifest = $null
if ($env:PNX_TERMINAL_REPO) {
    $_manifestPath = "$env:PNX_TERMINAL_REPO\configs\themes.json"
    if (Test-Path $_manifestPath) {
        try { $_pnxManifest = Get-Content $_manifestPath -Raw | ConvertFrom-Json } catch {}
    }
}

$PnxThemes = if ($env:PNX_OMP_THEMES) { $env:PNX_OMP_THEMES } else { "$env:USERPROFILE\.oh-my-posh\themes" }

# Build ThemeDB from manifest
$ThemeDB = @{}
if ($_pnxManifest -and $_pnxManifest.themes) {
    foreach ($p in $_pnxManifest.themes.PSObject.Properties) {
        $ThemeDB[$p.Name] = @{
            omp     = "$PnxThemes\$($p.Value.omp)"
            scheme  = $p.Value.scheme
            wtTheme = $p.Value.wtTheme
        }
    }
}

# ===== Health Check (collect issues, report once at end) =====
$_healthIssues = @()

# Merge user-created themes from registry (survives restart)
$_themeRegistry = Join-Path $env:LOCALAPPDATA "pnx-terminal\themes.json"
if (Test-Path $_themeRegistry) {
    try {
        $custom = Get-Content $_themeRegistry -Raw | ConvertFrom-Json
        foreach ($prop in $custom.PSObject.Properties) {
            if (-not $ThemeDB.ContainsKey($prop.Name)) {
                $ThemeDB[$prop.Name] = @{
                    omp     = $prop.Value.omp
                    scheme  = $prop.Value.scheme
                    wtTheme = $prop.Value.wtTheme
                }
            }
        }
    } catch {
        $_healthIssues += "Theme registry corrupt — custom themes not loaded. Delete $(Join-Path $env:LOCALAPPDATA 'pnx-terminal\themes.json') to fix."
    }
}
Remove-Variable _themeRegistry -ErrorAction SilentlyContinue

# Build StyleDB from manifest
$StyleDB = @{}
if ($_pnxManifest -and $_pnxManifest.styles) {
    foreach ($p in $_pnxManifest.styles.PSObject.Properties) {
        $StyleDB[$p.Name] = @{
            opacity          = [int]$p.Value.opacity
            useAcrylic       = [bool]$p.Value.useAcrylic
            useMica          = [bool]$p.Value.useMica
            padding          = $p.Value.padding
            cursorShape      = $p.Value.cursorShape
            scrollbarState   = $p.Value.scrollbarState
            unfocusedOpacity = [int]$p.Value.unfocusedOpacity
        }
    }
}

# Fallback: if manifest didn't load (first boot before bootstrap)
if ($ThemeDB.Count -eq 0) {
    $ThemeDB = @{
        pro = @{ omp = "$PnxThemes\pnx-dracula-pro.omp.json"; scheme = "Dracula Pro"; wtTheme = "PNX Dracula Pro" }
    }
}
if ($StyleDB.Count -eq 0) {
    $StyleDB = @{
        mac = @{ opacity = 85; useAcrylic = $true; useMica = $false; padding = "16, 12, 16, 12"; cursorShape = "bar"; scrollbarState = "visible"; unfocusedOpacity = 70 }
    }
}

# Read defaults from manifest (single source of truth)
$_defaultTheme = if ($_pnxManifest.defaultTheme) { $_pnxManifest.defaultTheme } else { 'pro' }
$_defaultStyle = if ($_pnxManifest.defaultStyle) { $_pnxManifest.defaultStyle } else { 'mac' }

# Load split overrides (modifier on top of OS style)
$Global:PnxSplitOverrides = @{}
if ($_pnxManifest.splitOverrides) {
    foreach ($p in $_pnxManifest.splitOverrides.PSObject.Properties) {
        $Global:PnxSplitOverrides[$p.Name] = switch ($p.Name) {
            { $_ -in @('opacity', 'unfocusedOpacity') } { [int]$p.Value }
            { $_ -in @('useAcrylic', 'useMica') }       { [bool]$p.Value }
            default                                       { $p.Value }
        }
    }
}
Remove-Variable _pnxManifest, _manifestPath -ErrorAction SilentlyContinue

# ===== Load Pane Layout Management =====
$_paneLayoutScript = if ($env:PNX_TERMINAL_REPO) { "$env:PNX_TERMINAL_REPO\scripts\pane-layout.ps1" } else { $null }
if ($_paneLayoutScript -and (Test-Path $_paneLayoutScript)) {
    . $_paneLayoutScript
}
Remove-Variable _paneLayoutScript -ErrorAction SilentlyContinue

# Build LayoutDB from manifest
$LayoutDB = @{}
$_predefinedLayoutNames = @()
if ($env:PNX_TERMINAL_REPO) {
    $_layoutManifest = "$env:PNX_TERMINAL_REPO\configs\layouts.json"
    if (Test-Path $_layoutManifest) {
        try {
            $_layoutData = Get-Content $_layoutManifest -Raw | ConvertFrom-Json
            foreach ($p in $_layoutData.layouts.PSObject.Properties) {
                $LayoutDB[$p.Name] = @{
                    description = $p.Value.description
                    panes       = @($p.Value.panes)
                }
            }
            $_predefinedLayoutNames = @($LayoutDB.Keys)
        } catch {
            $_healthIssues += "layouts.json corrupt — pane layouts not loaded."
        }
    }
    Remove-Variable _layoutManifest, _layoutData -ErrorAction SilentlyContinue
}

# Merge custom layouts (predefined wins — custom only adds new names)
$_customLayoutPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\layouts.json"
if (Test-Path $_customLayoutPath) {
    try {
        $custom = Get-Content $_customLayoutPath -Raw | ConvertFrom-Json
        foreach ($prop in $custom.PSObject.Properties) {
            if (-not $LayoutDB.ContainsKey($prop.Name)) {
                $LayoutDB[$prop.Name] = @{
                    description = $prop.Value.description
                    panes       = @($prop.Value.panes)
                }
            }
        }
    } catch {
        $_healthIssues += "Custom layouts.json corrupt — custom layouts not loaded."
    }
}

# Check wt.exe availability
if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
    $_healthIssues += "wt.exe not found — pane layout commands unavailable. Install: winget install Microsoft.WindowsTerminal"
}

# ===== Detect Current Theme & Style from WT Settings =====
$Global:PnxCurrentTheme = $_defaultTheme
$Global:PnxCurrentStyle = $_defaultStyle
$Global:PnxSplitMode    = $false

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
                    $Global:PnxCurrentTheme = $_defaultTheme
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
            # Detect split mode marker
            if ($_defaults.pnxSplit -eq $true) { $Global:PnxSplitMode = $true }
        }
        Remove-Variable _defaults -ErrorAction SilentlyContinue
    } catch {
        $_healthIssues += "WT settings.json unreadable — theme/style detection skipped"
    }
}

# ===== Oh My Posh (init with detected theme — cached) =====
$_ompConfig = $ThemeDB[$Global:PnxCurrentTheme].omp
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    $_healthIssues += "Oh My Posh not found — run:  winget install JanDeDobbeleer.OhMyPosh"
} elseif (-not (Test-Path $_ompConfig)) {
    $_healthIssues += "OMP theme file missing — run:  Update-Workspace"
    $_fallback = Get-ChildItem $PnxThemes -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($_fallback) { oh-my-posh init pwsh --config $_fallback.FullName | Invoke-Expression }
} else {
    $_ompExe = (Get-Command oh-my-posh).Source
    $_ompVer = (Get-Item $_ompExe).LastWriteTimeUtc.Ticks.ToString()
    $_ompCfgTicks = (Get-Item $_ompConfig).LastWriteTimeUtc.Ticks.ToString()
    $_ompExtra = "$($Global:PnxCurrentTheme)|$_ompCfgTicks"
    $_ompCached = if (Get-Command Get-PnxCachedInit -ErrorAction SilentlyContinue) {
        Get-PnxCachedInit -Name 'omp' -VersionKey $_ompVer -ExtraKey $_ompExtra
    } else { $null }
    if ($_ompCached) {
        try { $_ompCached | Invoke-Expression } catch {
            # Corrupt cache — regenerate
            Remove-Item (Join-Path $PnxCacheDir "omp.*") -Force -ErrorAction SilentlyContinue
            $_ompInit = oh-my-posh init pwsh --config $_ompConfig | Out-String
            $_ompInit | Invoke-Expression
            if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
                Save-PnxCachedInit -Name 'omp' -VersionKey $_ompVer -ExtraKey $_ompExtra -Content $_ompInit
            }
        }
    } else {
        $_ompInit = oh-my-posh init pwsh --config $_ompConfig | Out-String
        $_ompInit | Invoke-Expression
        if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
            Save-PnxCachedInit -Name 'omp' -VersionKey $_ompVer -ExtraKey $_ompExtra -Content $_ompInit
        }
    }
}
Remove-Variable _ompConfig, _fallback, _ompExe, _ompVer, _ompCfgTicks, _ompExtra, _ompCached, _ompInit -ErrorAction SilentlyContinue

# ===== Terminal Icons (lazy-load on idle for fast startup) =====
if (Get-Module Terminal-Icons -ListAvailable -ErrorAction SilentlyContinue) {
    if ($PSVersionTable.PSVersion -ge [Version]"7.3") {
        # Proxy: auto-import on first ls/Get-ChildItem call (before OnIdle fires)
        # NOTE: Must remove proxy BEFORE Import-Module — Terminal-Icons internally
        # calls Get-ChildItem (to scan icon dirs), which would re-enter this proxy
        # and hit the module nesting limit (10 levels).
        function Global:Get-ChildItem {
            Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
            Import-Module Terminal-Icons -ErrorAction SilentlyContinue
            Microsoft.PowerShell.Management\Get-ChildItem @args
        }
        # OnIdle: import + clean up proxy if still present
        Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
            Import-Module Terminal-Icons -ErrorAction SilentlyContinue
            Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
        } | Out-Null
    } else {
        # PS < 7.3: import directly (no OnIdle event available)
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
} else {
    $_healthIssues += "Terminal-Icons missing (ls has no icons) -- run:  Install-Module Terminal-Icons -Force"
}

# ===== Nerd Font check (verify CaskaydiaCove is available) =====
$_fontInfo = if (Get-Command Get-NerdFontInfo -ErrorAction SilentlyContinue) { Get-NerdFontInfo } else { $null }
if (-not $_fontInfo -or -not $_fontInfo.Installed) {
    $_healthIssues += "CaskaydiaCove Nerd Font missing (icons broken) — run:  oh-my-posh font install CascadiaCode"
}
# ===== Auto-fix WT font face if using stale v2/v3 name =====
if (Get-Command Repair-WtFontFace -ErrorAction SilentlyContinue) {
    try {
        Repair-WtFontFace -WtPath $WtSettingsPath -WtJson $_wtJson -FontInfo $_fontInfo | Out-Null
    } catch {
        $_healthIssues += "WT font face repair failed: $_"
    }
}
Remove-Variable _wtJson, _fontInfo -ErrorAction SilentlyContinue

# ===== Zoxide (cached init) =====
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $_zoxExe = (Get-Command zoxide).Source
    $_zoxVer = (Get-Item $_zoxExe).LastWriteTimeUtc.Ticks.ToString()
    $_zoxCached = if (Get-Command Get-PnxCachedInit -ErrorAction SilentlyContinue) {
        Get-PnxCachedInit -Name 'zoxide' -VersionKey $_zoxVer -ExtraKey ''
    } else { $null }
    if ($_zoxCached) {
        try { $_zoxCached | Invoke-Expression } catch {
            Remove-Item (Join-Path $PnxCacheDir "zoxide.*") -Force -ErrorAction SilentlyContinue
            $_zoxInit = zoxide init powershell | Out-String
            $_zoxInit | Invoke-Expression
            if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
                Save-PnxCachedInit -Name 'zoxide' -VersionKey $_zoxVer -ExtraKey '' -Content $_zoxInit
            }
        }
    } else {
        $_zoxInit = zoxide init powershell | Out-String
        $_zoxInit | Invoke-Expression
        if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
            Save-PnxCachedInit -Name 'zoxide' -VersionKey $_zoxVer -ExtraKey '' -Content $_zoxInit
        }
    }
    Remove-Variable _zoxExe, _zoxVer, _zoxCached, _zoxInit -ErrorAction SilentlyContinue
}

# ===== Encoding (Vietnamese support) =====
[console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ===== PSReadLine (batched for fewer calls) =====
$_pslOpts = @{
    EditMode                      = 'Windows'
    BellStyle                     = 'None'
    MaximumHistoryCount           = 10000
    HistoryNoDuplicates           = $true
    HistorySearchCursorMovesToEnd = $true
    ShowToolTips                  = $true
}
$_pslVersion = (Get-Module PSReadLine -ErrorAction SilentlyContinue).Version
if ($_pslVersion -and $_pslVersion -ge [Version]"2.2.0") {
    $_pslOpts['PredictionSource']    = 'History'
    $_pslOpts['PredictionViewStyle'] = 'ListView'
}
Set-PSReadLineOption @_pslOpts
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z -Function Undo
Set-PSReadLineKeyHandler -Key Ctrl+w -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Remove-Variable _pslOpts, _pslVersion -ErrorAction SilentlyContinue

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

# ===== Welcome line (interactive sessions only) =====
if ([Environment]::UserInteractive -and -not $env:PNX_NO_WELCOME) {
    $_themeName = if ($Global:PnxCurrentTheme) { $Global:PnxCurrentTheme } else { "default" }
    $_styleName = if ($Global:PnxCurrentStyle) { "($Global:PnxCurrentStyle)" } else { "" }
    $_splitLabel = if ($Global:PnxSplitMode) { " + split" } else { "" }
    Write-Host "  PNX Terminal | $_themeName $_styleName$_splitLabel | Show-Cheatsheet for help" -ForegroundColor DarkGray
    Remove-Variable _themeName, _styleName, _splitLabel -ErrorAction SilentlyContinue
}

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
Register-ArgumentCompleter -CommandName New-PnxTheme -ParameterName BasedOn -ScriptBlock {
    param($cmd, $param, $word)
    $ThemeDB.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $ThemeDB[$_].scheme)
    }
}.GetNewClosure()
Register-ArgumentCompleter -CommandName Remove-PnxTheme -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    $regPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\themes.json"
    if (Test-Path $regPath) {
        try {
            $reg = Get-Content $regPath -Raw | ConvertFrom-Json
            $reg.PSObject.Properties.Name | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Custom theme: $_")
            }
        } catch {}
    }
}

# Tab completion for layout functions
Register-ArgumentCompleter -CommandName Open-Layout -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    $LayoutDB.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
        $desc = if ($LayoutDB[$_].description) { $LayoutDB[$_].description } else { $_ }
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
    }
}.GetNewClosure()
Register-ArgumentCompleter -CommandName Remove-Layout -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    $_customLayoutPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\layouts.json"
    if (Test-Path $_customLayoutPath) {
        try {
            $reg = Get-Content $_customLayoutPath -Raw | ConvertFrom-Json
            $reg.PSObject.Properties.Name | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Custom layout: $_")
            }
        } catch {}
    }
}
Register-ArgumentCompleter -CommandName Show-Cheatsheet -ParameterName Category -ScriptBlock {
    param($cmd, $param, $word)
    @('theme', 'pane', 'config', 'keys', 'all') | Where-Object { $_ -like "$word*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# ===== Theme List Display =====
function Get-ThemeList {
    [CmdletBinding()]
    param()
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

# ===== Theme Integrity Validation =====
function Test-ThemeIntegrity {
    [CmdletBinding()]
    param([switch]$Quiet)

    # Read WT settings for scheme/theme validation
    $wtSchemes = @()
    $wtThemes  = @()
    if ($WtSettingsPath -and (Test-Path $WtSettingsPath)) {
        try {
            $wtJson = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
            if ($wtJson.schemes) { $wtSchemes = @($wtJson.schemes | ForEach-Object { $_.name }) }
            if ($wtJson.themes)  { $wtThemes  = @($wtJson.themes  | ForEach-Object { $_.name }) }
        } catch {
            if ($Quiet) { return $false }
            Write-Host "  Cannot read WT settings.json — aborting integrity check." -ForegroundColor Red
            return
        }
    }

    $issues = 0
    $results = @()

    foreach ($key in ($ThemeDB.Keys | Sort-Object)) {
        $entry = $ThemeDB[$key]
        $ompOk    = Test-Path $entry.omp
        $schemeOk = $wtSchemes -contains $entry.scheme
        $wtOk     = $wtThemes  -contains $entry.wtTheme

        if (-not $ompOk -or -not $schemeOk -or -not $wtOk) { $issues++ }

        $results += [PSCustomObject]@{
            Key      = $key
            OmpOk    = $ompOk
            SchemeOk = $schemeOk
            WtOk     = $wtOk
        }
    }

    if ($Quiet) { return ($issues -eq 0) }

    # Display table
    Write-Host ""
    Write-Host "  Theme Integrity Check" -ForegroundColor White
    $line = [string]::new([char]0x2500, 21)
    Write-Host "  $line" -ForegroundColor DarkGray

    foreach ($r in $results) {
        $allOk = $r.OmpOk -and $r.SchemeOk -and $r.WtOk
        $status = if ($allOk) { "OK" } else { "FAIL" }
        $statusColor = if ($allOk) { "Green" } else { "Red" }
        $ompMark    = if ($r.OmpOk)    { "OK" } else { "MISSING" }
        $schemeMark = if ($r.SchemeOk) { "OK" } else { "MISSING" }
        $wtMark     = if ($r.WtOk)     { "OK" } else { "MISSING" }

        $ompColor    = if ($r.OmpOk)    { "Green" } else { "Red" }
        $schemeColor = if ($r.SchemeOk) { "Green" } else { "Red" }
        $wtColor     = if ($r.WtOk)     { "Green" } else { "Red" }

        Write-Host "  " -NoNewline
        Write-Host "$($status.PadRight(6))" -ForegroundColor $statusColor -NoNewline
        Write-Host "$($r.Key.PadRight(14))" -NoNewline
        Write-Host "OMP " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($ompMark.PadRight(9))" -ForegroundColor $ompColor -NoNewline
        Write-Host "Scheme " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($schemeMark.PadRight(9))" -ForegroundColor $schemeColor -NoNewline
        Write-Host "WtTheme " -ForegroundColor DarkGray -NoNewline
        Write-Host "$wtMark" -ForegroundColor $wtColor
    }

    Write-Host ""
    if ($issues -gt 0) {
        Write-Host "  $issues issue(s) found. Fix before Sync-Config push." -ForegroundColor Yellow
    } else {
        Write-Host "  All $($results.Count) themes OK." -ForegroundColor Green
    }
    Write-Host ""
}

# ===== Theme Scaffolding =====
function New-PnxTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$BasedOn,
        [string]$Scheme,
        [ValidatePattern('^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$')]
        [string]$Background
    )

    # Validate
    if (-not $ThemeDB.ContainsKey($BasedOn)) {
        Write-Host "  Base theme '$BasedOn' not found in ThemeDB." -ForegroundColor Red
        Write-Host "  Available: $(($ThemeDB.Keys | Sort-Object) -join ', ')" -ForegroundColor DarkGray
        return
    }
    if ($ThemeDB.ContainsKey($Name)) {
        Write-Host "  Theme '$Name' already exists in ThemeDB." -ForegroundColor Red
        return
    }

    $displayName = if ($Scheme) { $Scheme } else {
        (Get-Culture).TextInfo.ToTitleCase($Name)
    }
    $wtThemeName = "PNX $displayName"

    # 1. Copy OMP file
    $baseOmp = $ThemeDB[$BasedOn].omp
    $newOmp  = "$PnxThemes\pnx-$Name.omp.json"
    if (-not (Test-Path $baseOmp)) {
        Write-Host "  Base OMP file not found: $baseOmp" -ForegroundColor Red
        return
    }
    $ompContent = Get-Content $baseOmp -Raw
    if ($Background) {
        # Replace only the first background color (palette/global), preserve per-segment colors
        $ompContent = ([regex]'"background"\s*:\s*"#[0-9a-fA-F]{3,8}"').Replace($ompContent, "`"background`": `"$Background`"", 1)
    }
    if (-not $PSCmdlet.ShouldProcess($newOmp, "Create OMP theme file")) { return }
    $ompContent | Set-Content $newOmp -Encoding utf8NoBOM

    # 2. Clone color scheme in WT settings
    if (-not $WtSettingsPath -or -not (Test-Path $WtSettingsPath)) {
        Write-Host "  OMP file created but WT settings not found — manual scheme/theme setup needed." -ForegroundColor Yellow
        $ThemeDB[$Name] = @{ omp = $newOmp; scheme = $displayName; wtTheme = $wtThemeName }
        return
    }

    try {
        $wtJson = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  OMP file created but WT settings.json is corrupt." -ForegroundColor Red
        return
    }

    if (-not $wtJson.schemes) { $wtJson | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force }
    $baseScheme = $wtJson.schemes | Where-Object { $_.name -eq $ThemeDB[$BasedOn].scheme }
    if ($baseScheme) {
        $newScheme = $baseScheme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $newScheme.name = $displayName
        if ($Background) { $newScheme.background = $Background }
        $wtJson.schemes = @($wtJson.schemes) + $newScheme
    } else {
        Write-Host "  Base scheme '$($ThemeDB[$BasedOn].scheme)' not found in WT — scheme not cloned." -ForegroundColor Yellow
    }

    # 3. Create WT theme (derive from base)
    if (-not $wtJson.themes) { $wtJson | Add-Member -NotePropertyName themes -NotePropertyValue @() -Force }
    $baseWtTheme = $wtJson.themes | Where-Object { $_.name -eq $ThemeDB[$BasedOn].wtTheme }
    if ($baseWtTheme) {
        $newWtTheme = $baseWtTheme | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $newWtTheme.name = $wtThemeName
        if ($Background -and $newWtTheme.tab)    { $newWtTheme.tab.background    = $Background }
        if ($Background -and $newWtTheme.tabRow)  { $newWtTheme.tabRow.background = $Background }
        $wtJson.themes = @($wtJson.themes) + $newWtTheme
    } else {
        Write-Host "  Base WT theme '$($ThemeDB[$BasedOn].wtTheme)' not found — WT theme not created." -ForegroundColor Yellow
    }

    # Write WT settings (atomic)
    if (Get-Command Save-WtSettings -ErrorAction SilentlyContinue) {
        if (-not (Save-WtSettings -Json $wtJson -WtPath $WtSettingsPath)) {
            Write-Host "  WT settings locked — OMP file created but WT changes not saved." -ForegroundColor Red
        }
    } else {
        $wtJson | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding utf8NoBOM
    }

    # 4. Add to runtime ThemeDB
    $ThemeDB[$Name] = @{ omp = $newOmp; scheme = $displayName; wtTheme = $wtThemeName }

    # 5. Persist to registry so theme survives restart
    $regPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\themes.json"
    $regDir = Split-Path $regPath -Parent
    if (-not (Test-Path $regDir)) { New-Item -ItemType Directory -Path $regDir -Force | Out-Null }
    $registry = if (Test-Path $regPath) {
        try { Get-Content $regPath -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{} }
    } else { [PSCustomObject]@{} }
    $registry | Add-Member -NotePropertyName $Name -NotePropertyValue ([PSCustomObject]@{
        omp     = $newOmp
        scheme  = $displayName
        wtTheme = $wtThemeName
    }) -Force
    $registry | ConvertTo-Json -Depth 10 | Set-Content $regPath -Encoding utf8NoBOM

    # 6. Summary
    Write-Host ""
    Write-Host "  Created theme: $Name (based on $BasedOn)" -ForegroundColor Green
    $line = [string]::new([char]0x2500, 37)
    Write-Host "  $line" -ForegroundColor DarkGray
    Write-Host "  OMP file:    $newOmp" -ForegroundColor DarkGray
    Write-Host "  Scheme:      $displayName" -ForegroundColor DarkGray
    Write-Host "  WT Theme:    $wtThemeName" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor White
    Write-Host "    Set-Theme $Name            # preview" -ForegroundColor DarkGray
    Write-Host "    Sync-Config push            # save to repo" -ForegroundColor DarkGray
    Write-Host ""
}

# ===== Remove Custom Theme =====
function Remove-PnxTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position=0)][string]$Name)

    $regPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\themes.json"
    if (-not (Test-Path $regPath)) {
        Write-Host "  No custom themes registered." -ForegroundColor Yellow
        return
    }
    try {
        $registry = Get-Content $regPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Custom theme registry unreadable ($regPath) — skipped."
        return
    }
    if (-not $registry.PSObject.Properties[$Name]) {
        Write-Host "  '$Name' is not a custom theme (only custom themes can be removed)." -ForegroundColor Yellow
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Remove custom theme")) { return }

    # Remove OMP file
    $entry = $registry.$Name
    if ($entry.omp -and (Test-Path $entry.omp)) { Remove-Item $entry.omp -Force }

    # Remove from registry
    $registry.PSObject.Properties.Remove($Name)
    $registry | ConvertTo-Json -Depth 10 | Set-Content $regPath -Encoding utf8NoBOM

    # Remove from runtime ThemeDB
    if ($ThemeDB.ContainsKey($Name)) { $ThemeDB.Remove($Name) }

    Write-Host "  Removed theme: $Name" -ForegroundColor Green
}

# ===== Interactive Theme Selector =====
function Select-ThemeInteractive {
    [CmdletBinding()]
    param()
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
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Theme,
        [Parameter(Position=1)][string]$Style,
        [switch]$Split,
        [switch]$NoSplit
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
        Write-Host "  Available: $($StyleDB.Keys | Sort-Object | Join-String -Separator ', ')" -ForegroundColor DarkGray
        return
    }

    $t = $ThemeDB[$Theme]
    $s = $StyleDB[$Style]

    # 1. Switch OMP prompt (and update cache)
    if (-not (Test-Path $t.omp)) {
        Write-Host "  Theme file not found: $($t.omp)" -ForegroundColor Red
        return
    }
    $_stInit = oh-my-posh init pwsh --config $t.omp | Out-String
    $_stInit | Invoke-Expression
    if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
        $_stExe = (Get-Command oh-my-posh).Source
        $_stVer = (Get-Item $_stExe).LastWriteTimeUtc.Ticks.ToString()
        $_stCfgTicks = (Get-Item $t.omp).LastWriteTimeUtc.Ticks.ToString()
        Save-PnxCachedInit -Name 'omp' -VersionKey $_stVer -ExtraKey "$Theme|$_stCfgTicks" -Content $_stInit
        Remove-Variable _stInit, _stExe, _stVer, _stCfgTicks -ErrorAction SilentlyContinue
    }

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

    # Resolve split mode: explicit switch > current state
    $_splitActive = if ($Split) { $true } elseif ($NoSplit) { $false } else { $Global:PnxSplitMode }

    # Apply split overrides on top of OS style
    if ($_splitActive -and $Global:PnxSplitOverrides.Count -gt 0) {
        foreach ($k in $Global:PnxSplitOverrides.Keys) {
            switch ($k) {
                'padding'           { $d.padding = $Global:PnxSplitOverrides[$k] }
                'unfocusedOpacity'  { $d.unfocusedAppearance.opacity = [int]$Global:PnxSplitOverrides[$k] }
                'opacity'           { $d.opacity = [int]$Global:PnxSplitOverrides[$k] }
            }
        }
    }

    # Store pnx markers for reliable detection on next profile load
    foreach ($prop in @('pnxTheme', 'pnxStyle', 'pnxSplit')) {
        $val = switch ($prop) {
            'pnxTheme' { $Theme }
            'pnxStyle' { $Style }
            'pnxSplit'  { $_splitActive }
        }
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
    if (Get-Command Save-WtSettings -ErrorAction SilentlyContinue) {
        $written = Save-WtSettings -Json $json -WtPath $WtSettingsPath
    } else {
        # Fallback if common.ps1 not loaded
        try {
            $json | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding utf8NoBOM
            $written = $true
        } catch { $written = $false }
    }
    if (-not $written) {
        Write-Host "  OMP switched but WT settings locked — restart terminal and retry." -ForegroundColor Red
        return
    }

    $Global:PnxCurrentTheme = $Theme
    $Global:PnxCurrentStyle = $Style
    $Global:PnxSplitMode    = $_splitActive

    $_splitLabel = if ($_splitActive) { " + split" } else { "" }
    Write-Host "  $Theme + $Style$_splitLabel" -ForegroundColor Green
}

function Set-Style {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Style,
        [switch]$Split,
        [switch]$NoSplit
    )
    if (-not $Style -and -not $Split -and -not $NoSplit) {
        $_splitLabel = if ($Global:PnxSplitMode) { " + split" } else { "" }
        Write-Host "  Current: $Global:PnxCurrentStyle$_splitLabel" -ForegroundColor Cyan
        Write-Host "  Available: $($StyleDB.Keys | Sort-Object | Join-String -Separator ', ')" -ForegroundColor DarkGray
        Write-Host "  Modifiers: -Split / -NoSplit" -ForegroundColor DarkGray
        return
    }
    $_style = if ($Style) { $Style } else { $Global:PnxCurrentStyle }
    Set-Theme -Theme $Global:PnxCurrentTheme -Style $_style -Split:$Split -NoSplit:$NoSplit
}

# ===== Maintenance Functions (delegate to standalone scripts) =====
function Update-Tools {
    [CmdletBinding()]
    param()
    $script = "$env:PNX_TERMINAL_REPO\scripts\update-tools.ps1"
    if (Test-Path $script) { & $script @args }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}

function Sync-Config {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][ValidateSet('push','pull')][string]$Direction,
        [switch]$Force
    )
    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }
    if ($Direction -eq 'push') {
        $integrityOk = Test-ThemeIntegrity -Quiet
        if (-not $integrityOk) {
            Write-Host "  Theme integrity issues detected:" -ForegroundColor Yellow
            Test-ThemeIntegrity
            $confirm = Read-Host "  Continue push anyway? (y/N)"
            if ($confirm -notin @('y','Y','yes')) {
                Write-Host "  Push cancelled." -ForegroundColor DarkGray
                return
            }
        }
        & "$repo\scripts\sync-to-repo.ps1" -Force:$Force
    }
    elseif ($Direction -eq 'pull') {
        & "$repo\scripts\sync-from-repo.ps1"   # sync-from-repo.ps1 already calls Clear-PnxCache
        Write-Host "  Reloading profile..." -ForegroundColor Cyan
        . $PROFILE
    }
    else { Write-Host "  Usage: Sync-Config push|pull [-Force]" -ForegroundColor Yellow }
}

function Get-Status {
    [CmdletBinding()]
    param()
    $script = "$env:PNX_TERMINAL_REPO\scripts\status.ps1"
    if (Test-Path $script) { & $script }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}

function Fix-ClaudeVN {
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$Restore
    )
    $script = "$env:PNX_TERMINAL_REPO\scripts\fix-claude-vn.ps1"
    if (-not (Test-Path $script)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }
    $params = @{}
    if ($Path)    { $params['Path'] = $Path }
    if ($Restore) { $params['Restore'] = $true }
    & $script @params
}

function Deploy-ClaudeConfig {
    [CmdletBinding()]
    param([switch]$Force)
    $script = "$env:PNX_TERMINAL_REPO\scripts\deploy-claude.ps1"
    if (Test-Path $script) { & $script -Force:$Force }
    else { Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red }
}

function Update-Workspace {
    [CmdletBinding()]
    param()
    $repo = $env:PNX_TERMINAL_REPO
    if (-not $repo -or -not (Test-Path $repo)) {
        Write-Host "  Repo not found. Set PNX_TERMINAL_REPO." -ForegroundColor Red
        return
    }

    Write-Host "`n  Updating Terminal Workspace..." -ForegroundColor Cyan
    Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

    # 1. Git pull (with 15s timeout to avoid hanging on network issues)
    Write-Host "`n  Pulling latest changes..." -ForegroundColor Cyan
    $prevDir = Get-Location
    try {
        Set-Location $repo
        $pullJob = Start-Job { git pull 2>&1 | Out-String }
        $done = $pullJob | Wait-Job -Timeout 15
        if ($done) {
            $pullOutput = Receive-Job $pullJob
        } else {
            Stop-Job $pullJob
            Remove-Job $pullJob -Force
            Write-Host "  git pull timed out (15s). Check network or VPN." -ForegroundColor Red
            return
        }
        Remove-Job $pullJob -Force -ErrorAction SilentlyContinue
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

    # 3. Re-patch Claude Code Vietnamese IME fix (idempotent — skips if already patched)
    Write-Host "`n  Checking Claude Code Vietnamese fix..." -ForegroundColor Cyan
    try {
        & "$repo\scripts\fix-claude-vn.ps1"
    } catch {
        Write-Host "  Vietnamese fix skipped: $_" -ForegroundColor Yellow
    }

    # 4. Reload profile (sync-from-repo.ps1 already cleared init cache)
    Write-Host "`n  Reloading profile..." -ForegroundColor Cyan
    . $PROFILE
    Write-Host "  Done. Workspace updated." -ForegroundColor Green
    Write-Host ""
}
