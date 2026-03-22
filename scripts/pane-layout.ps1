# Pane layout management helpers
# Dot-source this from profile or other scripts that need layout support.
# Expects $LayoutDB, $_predefinedLayoutNames, $_customLayoutPath from profile.ps1.
# Falls back to defaults if not set (allows standalone use).

# Default paths — profile.ps1 sets these before dot-sourcing, but provide
# fallbacks for standalone use. Uses script-scope to not shadow caller's variables.
if (-not (Get-Variable _customLayoutPath -ValueOnly -ErrorAction SilentlyContinue)) {
    $script:_customLayoutPath = Join-Path $env:LOCALAPPDATA "pnx-terminal\layouts.json"
}
if (-not (Get-Variable _predefinedLayoutNames -ValueOnly -ErrorAction SilentlyContinue)) {
    $script:_predefinedLayoutNames = @()
}

# -- Build wt.exe argument list from panes array --
# Returns [string[]] array suitable for: & wt.exe @result
function Build-WtCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Panes,
        [Parameter(Mandatory)][string]$ResolvedDir
    )

    $args_list = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $Panes.Count; $i++) {
        $pane = $Panes[$i]

        # Resolve directory
        $dir = $pane.dir
        if (-not $dir -or $dir -eq '.') {
            $dir = $ResolvedDir
        }

        if ($i -eq 0) {
            # Root pane: -p <profile> -d <dir> [--title <title>]
            if ($pane.profile) {
                $args_list.Add('-p')
                $args_list.Add($pane.profile)
            }
            if ($pane.title) {
                $args_list.Add('--title')
                $args_list.Add($pane.title)
            }
            $args_list.Add('-d')
            $args_list.Add($dir)
        } else {
            # Subsequent panes: ; split-pane -V|-H ...
            $args_list.Add(';')
            $args_list.Add('split-pane')

            # Split direction
            switch ($pane.split) {
                'vertical'   { $args_list.Add('-V') }
                'horizontal' { $args_list.Add('-H') }
            }

            if ($pane.profile) {
                $args_list.Add('-p')
                $args_list.Add($pane.profile)
            }
            if ($pane.size) {
                $args_list.Add('--size')
                $args_list.Add([string]$pane.size)
            }
            if ($pane.title) {
                $args_list.Add('--title')
                $args_list.Add($pane.title)
            }
            $args_list.Add('-d')
            $args_list.Add($dir)
        }
    }

    return [string[]]$args_list.ToArray()
}

# -- Validate panes array --
# Returns @{ Valid = [bool]; Errors = [string[]]; Warnings = [string[]] }
function Test-LayoutPanes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Panes,
        [string]$LayoutName = 'unknown'
    )

    $errors   = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $validSplits = @('root', 'vertical', 'horizontal')

    # Rule 1: must have at least 1 pane
    if ($Panes.Count -eq 0) {
        $errors.Add("Layout '$LayoutName': panes array must have at least 1 entry")
        return @{ Valid = $false; Errors = @($errors); Warnings = @($warnings) }
    }

    # Rule 2: first pane must be root
    if ($Panes[0].split -ne 'root') {
        $errors.Add("Layout '$LayoutName': first pane split must be 'root', got '$($Panes[0].split)'")
    }

    for ($i = 0; $i -lt $Panes.Count; $i++) {
        $pane = $Panes[$i]

        # Rule 3: split values must be valid
        if ($pane.split -notin $validSplits) {
            $errors.Add("Layout '$LayoutName' pane[$i]: invalid split '$($pane.split)' (must be root, vertical, or horizontal)")
        }

        # Rule 4: size must be in (0.0, 1.0) exclusive
        $hasSize = if ($pane -is [hashtable]) { $pane.ContainsKey('size') } else { $pane.PSObject.Properties.Name -contains 'size' }
        if ($null -ne $pane.size -and $hasSize) {
            $s = [double]$pane.size
            if ($s -le 0.0 -or $s -ge 1.0) {
                $errors.Add("Layout '$LayoutName' pane[$i]: size must be between 0.0 and 1.0 exclusive, got $s")
            }
        }

        # Rule 5: parent field warning
        $hasParent = if ($pane -is [hashtable]) { $pane.ContainsKey('parent') } else { $pane.PSObject.Properties.Name -contains 'parent' }
        if ($hasParent) {
            $warnings.Add("Layout '$LayoutName' pane[$i]: 'parent' field is reserved for future use, ignored in V1")
        }
    }

    return @{
        Valid    = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}

# -- List all layouts --
function Get-LayoutList {
    [CmdletBinding()]
    param()
    if (-not $LayoutDB -or $LayoutDB.Count -eq 0) {
        Write-Host "  No layouts available." -ForegroundColor Yellow
        return
    }
    $sorted = $LayoutDB.Keys | Sort-Object
    Write-Host ""
    Write-Host "  PNX Layouts ($($sorted.Count) available)" -ForegroundColor White
    $line = [string]::new([char]0x2500, 45)
    Write-Host "  $line" -ForegroundColor DarkGray
    foreach ($name in $sorted) {
        $layout = $LayoutDB[$name]
        $desc = if ($layout.description) { $layout.description } else { "" }
        $paneCount = @($layout.panes).Count
        Write-Host "  $name" -ForegroundColor Cyan -NoNewline
        Write-Host "  ($paneCount panes) $desc" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# -- Open a layout by name --
function Open-Layout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Dir,
        [switch]$NewWindow
    )

    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Warning "Windows Terminal (wt.exe) not found. Install via: winget install Microsoft.WindowsTerminal"
        return
    }

    if (-not $LayoutDB -or -not $LayoutDB.ContainsKey($Name)) {
        Write-Warning "Layout '$Name' not found. Available layouts:"
        if ($LayoutDB) { $LayoutDB.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan } }
        return
    }

    $layout = $LayoutDB[$Name]
    $panes = @($layout.panes)

    $validation = Test-LayoutPanes -Panes $panes -LayoutName $Name
    foreach ($w in $validation.Warnings) { Write-Warning $w }
    if (-not $validation.Valid) {
        foreach ($e in $validation.Errors) { Write-Host "  $e" -ForegroundColor Red }
        return
    }

    $resolvedDir = if ($Dir) { $Dir } else { (Get-Location).Path }

    # Warn on non-existent directories (non-blocking)
    foreach ($pane in $panes) {
        if ($pane.dir -and $pane.dir -ne '.' -and -not (Test-Path $pane.dir)) {
            Write-Warning "Directory '$($pane.dir)' does not exist — wt.exe will use fallback."
        }
    }

    # Validate WT profile names against installed profiles
    if ($WtSettingsPath -and (Test-Path $WtSettingsPath)) {
        try {
            $wtJson = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
            $installedProfiles = @($wtJson.profiles.list | ForEach-Object { $_.name })
            foreach ($pane in $panes) {
                if ($pane.profile -and $pane.profile -notin $installedProfiles) {
                    Write-Warning "WT profile '$($pane.profile)' not found — using default profile."
                    $pane.profile = $null
                }
            }
        } catch {
            Write-Warning "Could not read WT profiles for validation."
        }
    }

    $wtArgs = Build-WtCommand -Panes $panes -ResolvedDir $resolvedDir

    $prefix = @()
    if ($env:WT_SESSION -and -not $NewWindow) {
        $prefix = @('-w', '0', 'nt')
    }
    $finalArgs = $prefix + $wtArgs

    Start-Process wt -ArgumentList $finalArgs
}

# -- Save a custom layout --
function Save-Layout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][array]$Panes,
        [string]$Description = ""
    )

    if ($_predefinedLayoutNames -contains $Name) {
        Write-Warning "Cannot save layout '$Name' — it is a predefined layout. Use a different name."
        return
    }

    $validation = Test-LayoutPanes -Panes $Panes -LayoutName $Name
    foreach ($w in $validation.Warnings) { Write-Warning $w }
    if (-not $validation.Valid) {
        foreach ($e in $validation.Errors) { Write-Host "  $e" -ForegroundColor Red }
        return
    }

    $LayoutDB[$Name] = @{ description = $Description; panes = $Panes }

    $dir = Split-Path $_customLayoutPath -Parent
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $existing = if (Test-Path $_customLayoutPath) {
            try { Get-Content $_customLayoutPath -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{} }
        } else { [PSCustomObject]@{} }

        $existing | Add-Member -NotePropertyName $Name -NotePropertyValue ([PSCustomObject]@{
            description = $Description
            panes       = $Panes
        }) -Force

        $existing | ConvertTo-Json -Depth 10 | Set-Content $_customLayoutPath -Encoding utf8NoBOM
        Write-Host "  Layout '$Name' saved." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to save layout: $_"
    }
}

# -- Remove a custom layout --
function Remove-Layout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name
    )

    if ($_predefinedLayoutNames -contains $Name) {
        Write-Warning "Cannot remove '$Name' — it is a predefined layout."
        return
    }

    if (-not $LayoutDB.ContainsKey($Name)) {
        Write-Warning "Layout '$Name' not found."
        return
    }

    $LayoutDB.Remove($Name)

    if (Test-Path $_customLayoutPath) {
        try {
            $existing = Get-Content $_customLayoutPath -Raw | ConvertFrom-Json
            $existing.PSObject.Properties.Remove($Name)
            $existing | ConvertTo-Json -Depth 10 | Set-Content $_customLayoutPath -Encoding utf8NoBOM
        } catch {
            Write-Warning "Failed to update layout file: $_"
        }
    }

    Write-Host "  Layout '$Name' removed." -ForegroundColor Green
}

# -- Get raw wt.exe command string for a layout --
function Get-LayoutCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [string]$Dir
    )

    if (-not $LayoutDB -or -not $LayoutDB.ContainsKey($Name)) {
        Write-Warning "Layout '$Name' not found."
        return
    }

    $resolvedDir = if ($Dir) { $Dir } else { (Get-Location).Path }
    $panes = @($LayoutDB[$Name].panes)
    $wtArgs = Build-WtCommand -Panes $panes -ResolvedDir $resolvedDir

    $cmdParts = @('wt.exe')
    foreach ($arg in $wtArgs) {
        if ($arg -match '\s') { $cmdParts += "`"$arg`"" }
        else { $cmdParts += $arg }
    }
    $cmdString = $cmdParts -join ' '
    Write-Host $cmdString
}

# -- Create Claude WT profile --
function New-ClaudeProfile {
    [CmdletBinding()]
    param()
    if (-not $WtSettingsPath -or -not (Test-Path $WtSettingsPath)) {
        Write-Warning "Windows Terminal settings not found."
        return
    }
    try {
        $wtJson = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "WT settings.json is corrupt: $_"
        return
    }
    $existing = $wtJson.profiles.list | Where-Object { $_.name -eq 'Claude' }
    if ($existing) {
        Write-Host "  Claude profile already exists in Windows Terminal." -ForegroundColor DarkGray
        return
    }
    $claudeGuid = "{c1a0de00-c0de-4c1a-bde0-000000000001}"
    $claudeProfile = [PSCustomObject]@{
        name        = "Claude"
        commandline = "claude"
        guid        = $claudeGuid
        hidden      = $false
        icon        = "`u{2728}"
    }
    $wtJson.profiles.list = @($wtJson.profiles.list) + $claudeProfile
    if (Get-Command Save-WtSettings -ErrorAction SilentlyContinue) {
        if (-not (Save-WtSettings -Json $wtJson -WtPath $WtSettingsPath)) {
            Write-Warning "Failed to write WT settings (file locked?)."
            return
        }
    } else {
        $wtJson | ConvertTo-Json -Depth 20 | Set-Content $WtSettingsPath -Encoding utf8NoBOM
    }
    Write-Host "  Claude profile created in Windows Terminal." -ForegroundColor Green
    Write-Host "  You can now use 'Claude' profile in custom layouts." -ForegroundColor DarkGray
}

# -- Show categorized command cheatsheet --
function Show-Cheatsheet {
    [CmdletBinding()]
    param(
        [ValidateSet('theme', 'pane', 'config', 'keys', 'all')]
        [string]$Category = 'all'
    )
    $line = [string]::new([char]0x2500, 45)
    $sections = @{
        theme = @(
            "", "  THEME", "  $line",
            "  Set-Theme <name> [style]     Switch theme (e.g., Set-Theme tokyo mac)",
            "  Get-ThemeList                 Show all available themes",
            "  Set-Style <style>             Switch style only (mac/win/linux)",
            "  Select-ThemeInteractive       Arrow-key theme picker",
            "  New-PnxTheme -Name <n> ...   Create custom theme",
            "  Test-ThemeIntegrity           Validate theme components"
        )
        pane = @(
            "", "  PANE LAYOUTS", "  $line",
            "  Open-Layout <name>            Open a pane layout",
            "  Open-Layout <name> -NewWindow Open in new window",
            "  Get-LayoutList                Show all layouts",
            "  Save-Layout <name> -Panes ..  Save custom layout",
            "  Get-LayoutCommand <name>      Export wt.exe command",
            "  New-ClaudeProfile             Create Claude WT profile"
        )
        config = @(
            "", "  CONFIG", "  $line",
            "  Sync-Config push|pull         Sync local <-> repo",
            "  Update-Workspace              Pull + redeploy + reload",
            "  Get-Status                    Health check",
            "  Update-Tools                  Update all packages",
            "  Deploy-ClaudeConfig           Deploy Claude configs"
        )
        keys = @(
            "", "  KEYBOARD SHORTCUTS (Windows Terminal)", "  $line",
            "  Alt+Shift+D                   Auto split pane",
            "  Alt+Shift++ / Alt+Shift+-     Split vertical / horizontal",
            "  Alt+Arrow                     Move focus between panes",
            "  Alt+Shift+Arrow               Resize pane",
            "  Ctrl+Shift+W                  Close pane",
            "  Ctrl+Shift+T                  New tab",
            "  Ctrl+Tab / Ctrl+Shift+Tab     Next / previous tab"
        )
    }
    Write-Host ""
    Write-Host "  PNX Terminal Cheatsheet" -ForegroundColor White
    $toShow = if ($Category -eq 'all') { @('theme', 'pane', 'config', 'keys') } else { @($Category) }
    foreach ($cat in $toShow) {
        foreach ($s in $sections[$cat]) {
            if ($s -match '^\s{2}[A-Z]') { Write-Host $s -ForegroundColor Cyan }
            elseif ($s -match '^\s{2}[─]') { Write-Host $s -ForegroundColor DarkGray }
            else { Write-Host $s }
        }
    }
    Write-Host ""
    Write-Host "  Type Show-Cheatsheet <category> to filter." -ForegroundColor DarkGray
    Write-Host ""
}
