# Pane layout management helpers
# Dot-source this from profile or other scripts that need layout support.

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
        if ($null -ne $pane.size -and $pane.ContainsKey('size')) {
            $s = [double]$pane.size
            if ($s -le 0.0 -or $s -ge 1.0) {
                $errors.Add("Layout '$LayoutName' pane[$i]: size must be between 0.0 and 1.0 exclusive, got $s")
            }
        }

        # Rule 5: parent field warning
        if ($pane.ContainsKey('parent')) {
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
