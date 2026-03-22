# Pane Management & Cheatsheet Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pane layout management and cheatsheet to the PowerShell terminal workspace, enabling one-command multi-pane setups via `wt.exe` CLI.

**Architecture:** Layouts stored in JSON (repo predefined + local custom, merged at profile load with predefined-wins strategy). `Build-WtCommand` converts pane definitions into `wt.exe` argument arrays. All pane functions extracted to `scripts/pane-layout.ps1`, dot-sourced from profile. `Show-Cheatsheet` provides discoverable command reference.

**Tech Stack:** PowerShell 7, Windows Terminal `wt.exe` CLI, Pester 5 for tests.

**Spec:** `docs/superpowers/specs/2026-03-22-pane-management-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `configs/layouts.json` | Predefined layout definitions (data only) |
| `scripts/pane-layout.ps1` | All pane functions: `Build-WtCommand`, `Open-Layout`, `Save-Layout`, `Remove-Layout`, `Get-LayoutList`, `Get-LayoutCommand`, `New-ClaudeProfile`, `Show-Cheatsheet` |
| `configs/profile.ps1` | Load `$LayoutDB`, dot-source pane-layout.ps1, register argument completers, welcome line |
| `tests/layout.tests.ps1` | Pester tests for all layout + cheatsheet functions |

---

## Chunk 1: Data Layer + Build-WtCommand

### Task 1: Create `configs/layouts.json`

**Files:**
- Create: `configs/layouts.json`

- [ ] **Step 1: Create layouts.json with predefined layouts**

```json
{
  "defaultLayout": "dual-pane",
  "layouts": {
    "dual-pane": {
      "description": "Two shells side by side",
      "panes": [
        { "profile": "PowerShell", "dir": ".", "split": "root" },
        { "profile": "PowerShell", "dir": ".", "split": "vertical" }
      ]
    },
    "triple-pane": {
      "description": "3 panes: 2 top + 1 bottom",
      "panes": [
        { "profile": "PowerShell", "dir": ".", "split": "root" },
        { "profile": "PowerShell", "dir": ".", "split": "vertical" },
        { "profile": "PowerShell", "dir": ".", "split": "horizontal" }
      ]
    },
    "dev-monitor": {
      "description": "Shell + shell + monitoring pane",
      "panes": [
        { "profile": "PowerShell", "dir": ".", "split": "root" },
        { "profile": "PowerShell", "dir": ".", "split": "vertical" },
        { "profile": "PowerShell", "dir": ".", "split": "horizontal", "title": "Monitor" }
      ]
    },
    "side-by-side": {
      "description": "Two shells for compare/review",
      "panes": [
        { "profile": "PowerShell", "dir": ".", "split": "root" },
        { "profile": "PowerShell", "dir": ".", "split": "vertical", "size": 0.5 }
      ]
    }
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

Run: `pwsh -NoProfile -Command "[void](Get-Content configs/layouts.json -Raw | ConvertFrom-Json); Write-Host 'Valid JSON'"`
Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add configs/layouts.json
git commit -m "feat: add predefined pane layouts data"
```

---

### Task 2: Create `scripts/pane-layout.ps1` with `Build-WtCommand`

**Files:**
- Create: `scripts/pane-layout.ps1`
- Create: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests for `Build-WtCommand`**

Create `tests/layout.tests.ps1`:

```powershell
#Requires -Modules Pester

BeforeAll {
    $env:PNX_TERMINAL_REPO = Split-Path $PSScriptRoot -Parent
    . "$PSScriptRoot\..\scripts\common.ps1"
    . "$PSScriptRoot\..\scripts\pane-layout.ps1"
}

Describe "Build-WtCommand" {
    It "Builds args for single root pane" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "C:\proj"; split = "root" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $result | Should -Be @('-p', 'PowerShell', '-d', 'C:\proj')
    }

    It "Builds args for two-pane vertical split" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $expected = @('-p', 'PowerShell', '-d', 'C:\proj',
                      ';', 'split-pane', '-V', '-p', 'PowerShell', '-d', 'C:\proj')
        $result | Should -Be $expected
    }

    It "Builds args for three-pane mixed split" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" },
            @{ profile = "PowerShell"; dir = "."; split = "horizontal" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $expected = @('-p', 'PowerShell', '-d', 'C:\proj',
                      ';', 'split-pane', '-V', '-p', 'PowerShell', '-d', 'C:\proj',
                      ';', 'split-pane', '-H', '-p', 'PowerShell', '-d', 'C:\proj')
        $result | Should -Be $expected
    }

    It "Includes --size when size is specified" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; size = 0.4 }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $result | Should -Contain '--size'
        $result | Should -Contain '0.4'
    }

    It "Includes --title when title is specified" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root"; title = "Main" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $result | Should -Contain '--title'
        $result | Should -Contain 'Main'
    }

    It "Uses null profile (omits -p flag)" {
        $panes = @(
            @{ profile = $null; dir = "."; split = "root" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        $result | Should -Not -Contain '-p'
        $result | Should -Be @('-d', 'C:\proj')
    }

    It "Resolves absolute dir instead of dot" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "C:\other"; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\proj"
        # First pane uses its own absolute dir, second uses ResolvedDir
        $result[3] | Should -Be 'C:\other'
        $result[7] | Should -Be 'C:\proj'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: FAIL — `Build-WtCommand` not defined

- [ ] **Step 3: Implement `Build-WtCommand` in `scripts/pane-layout.ps1`**

Create `scripts/pane-layout.ps1`:

```powershell
# Pane Layout Management for PNX Terminal Workspace
# Dot-sourced from profile.ps1. Depends on common.ps1 being loaded first.

function Build-WtCommand {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][array]$Panes,
        [Parameter(Mandatory)][string]$ResolvedDir
    )
    $args_list = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $Panes.Count; $i++) {
        $pane = $Panes[$i]
        $dir = if ($pane.dir -and $pane.dir -ne '.') { $pane.dir } else { $ResolvedDir }

        if ($i -gt 0) {
            $args_list.Add(';')
            $args_list.Add('split-pane')
            switch ($pane.split) {
                'vertical'   { $args_list.Add('-V') }
                'horizontal' { $args_list.Add('-H') }
            }
            if ($pane.size) {
                $args_list.Add('--size')
                $args_list.Add([string]$pane.size)
            }
        }

        if ($pane.profile) {
            $args_list.Add('-p')
            $args_list.Add([string]$pane.profile)
        }
        if ($pane.title) {
            $args_list.Add('--title')
            $args_list.Add([string]$pane.title)
        }
        $args_list.Add('-d')
        $args_list.Add($dir)
    }

    return [string[]]$args_list
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Build-WtCommand with tests"
```

---

### Task 3: Add layout validation function

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests for `Test-LayoutPanes`**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Test-LayoutPanes" {
    It "Passes valid layout" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It "Fails when first pane is not root" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
        $result.Errors | Should -Contain "Layout 'test': first pane must have split 'root'"
    }

    It "Fails on invalid split value" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "diagonal" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
    }

    It "Fails on empty panes array" {
        $result = Test-LayoutPanes -Panes @() -LayoutName "test"
        $result.Valid | Should -BeFalse
    }

    It "Fails on invalid size (out of range)" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; size = 1.5 }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
    }

    It "Warns on parent field (V1 ignored)" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; parent = 0 }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeTrue
        $result.Warnings | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: `Test-LayoutPanes` tests FAIL — function not defined

- [ ] **Step 3: Implement `Test-LayoutPanes`**

Add to `scripts/pane-layout.ps1`:

```powershell
function Test-LayoutPanes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Panes,
        [Parameter(Mandatory)][string]$LayoutName
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $validSplits = @('root', 'vertical', 'horizontal')

    if ($Panes.Count -eq 0) {
        $errors.Add("Layout '$LayoutName': panes array must have at least 1 entry")
        return @{ Valid = $false; Errors = [string[]]$errors; Warnings = [string[]]$warnings }
    }

    if ($Panes[0].split -ne 'root') {
        $errors.Add("Layout '$LayoutName': first pane must have split 'root'")
    }

    for ($i = 0; $i -lt $Panes.Count; $i++) {
        $pane = $Panes[$i]
        if ($pane.split -and $pane.split -notin $validSplits) {
            $errors.Add("Layout '$LayoutName': pane[$i] has invalid split '$($pane.split)'")
        }
        if ($null -ne $pane.size) {
            $s = [double]$pane.size
            if ($s -le 0.0 -or $s -ge 1.0) {
                $errors.Add("Layout '$LayoutName': pane[$i] size must be in (0.0, 1.0), got $s")
            }
        }
        if ($null -ne $pane.parent) {
            $warnings.Add("'parent' field is reserved for future use, ignored in V1")
        }
    }

    return @{
        Valid    = ($errors.Count -eq 0)
        Errors   = [string[]]$errors
        Warnings = [string[]]$warnings
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All 13 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Test-LayoutPanes validation with tests"
```

---

## Chunk 2: Core Layout Functions

### Task 4: Implement `Get-LayoutList`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Get-LayoutList" {
    BeforeAll {
        # Build a mock $LayoutDB
        $script:LayoutDB = @{
            'dual-pane' = @{ description = "Two shells"; panes = @(
                @{ profile = "PowerShell"; dir = "."; split = "root" },
                @{ profile = "PowerShell"; dir = "."; split = "vertical" }
            )}
            'triple-pane' = @{ description = "Three panes"; panes = @(
                @{ profile = "PowerShell"; dir = "."; split = "root" },
                @{ profile = "PowerShell"; dir = "."; split = "vertical" },
                @{ profile = "PowerShell"; dir = "."; split = "horizontal" }
            )}
        }
    }

    It "Returns output containing layout names" {
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -Match 'dual-pane'
        $output | Should -Match 'triple-pane'
    }

    It "Shows pane count for each layout" {
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -Match '2 panes'
        $output | Should -Match '3 panes'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: `Get-LayoutList` tests FAIL — function not defined

- [ ] **Step 3: Implement `Get-LayoutList`**

Add to `scripts/pane-layout.ps1`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Get-LayoutList function"
```

---

### Task 5: Implement `Open-Layout`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Open-Layout" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{ description = "Two shells"; panes = @(
                @{ profile = "PowerShell"; dir = "."; split = "root" },
                @{ profile = "PowerShell"; dir = "."; split = "vertical" }
            )}
        }
        # Mock wt.exe as available
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith {
            [PSCustomObject]@{ Name = 'wt'; Source = 'wt.exe' }
        }
        # Capture Start-Process calls instead of executing
        $script:CapturedWtArgs = $null
        Mock -CommandName Start-Process -MockWith {
            $script:CapturedWtArgs = $ArgumentList
        }
        # Mock WT settings for profile validation
        $script:WtSettingsPath = $null
    }

    It "Calls Start-Process with correct args for dual-pane" {
        Open-Layout -Name 'dual-pane' -Dir 'C:\test'
        $script:CapturedWtArgs | Should -Not -BeNullOrEmpty
        $script:CapturedWtArgs | Should -Contain '-p'
        $script:CapturedWtArgs | Should -Contain 'PowerShell'
        $script:CapturedWtArgs | Should -Contain 'C:\test'
    }

    It "Returns warning for unknown layout" {
        $output = Open-Layout -Name 'nonexistent' 3>&1 | Out-String
        $output | Should -Match 'not found'
    }

    It "Returns warning when wt.exe is missing" {
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'wt' } -MockWith { $null }
        $output = Open-Layout -Name 'dual-pane' 3>&1 | Out-String
        $output | Should -Match 'Windows Terminal'
    }

    It "Includes -w 0 nt when inside WT session" {
        $env:WT_SESSION = "fake-session-id"
        Open-Layout -Name 'dual-pane' -Dir 'C:\test'
        $script:CapturedWtArgs | Should -Contain '-w'
        $script:CapturedWtArgs | Should -Contain 'nt'
        Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
    }

    It "Omits -w 0 when -NewWindow is used" {
        $env:WT_SESSION = "fake-session-id"
        Open-Layout -Name 'dual-pane' -Dir 'C:\test' -NewWindow
        $script:CapturedWtArgs | Should -Not -Contain '-w'
        Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
    }

    It "Omits -w 0 when outside WT session" {
        Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
        Open-Layout -Name 'dual-pane' -Dir 'C:\test'
        $script:CapturedWtArgs | Should -Not -Contain '-w'
    }

    It "Warns on missing WT profile and falls back to default" {
        # Mock WT settings with only PowerShell profile
        $testWtDir = Join-Path $env:TEMP "pnx-wt-test-$(Get-Random)"
        New-Item $testWtDir -ItemType Directory -Force | Out-Null
        $script:WtSettingsPath = Join-Path $testWtDir "settings.json"
        @{ profiles = @{ list = @(@{ name = "PowerShell" }) } } |
            ConvertTo-Json -Depth 10 | Set-Content $script:WtSettingsPath
        $script:LayoutDB['profile-test'] = @{
            description = "test"; panes = @(
                @{ profile = "NonExistent"; dir = "."; split = "root" }
            )
        }
        $output = Open-Layout -Name 'profile-test' -Dir 'C:\test' 3>&1 | Out-String
        $output | Should -Match 'not found'
        $script:CapturedWtArgs | Should -Not -Contain 'NonExistent'
        Remove-Item $testWtDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Warns on non-existent directory (non-blocking)" {
        $script:LayoutDB['dir-test'] = @{
            description = "test"; panes = @(
                @{ profile = "PowerShell"; dir = "C:\nonexistent-path-12345"; split = "root" }
            )
        }
        $output = Open-Layout -Name 'dir-test' 3>&1 | Out-String
        $output | Should -Match 'does not exist'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: `Open-Layout` tests FAIL

- [ ] **Step 3: Implement `Open-Layout`**

Add to `scripts/pane-layout.ps1`:

```powershell
function Open-Layout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [string]$Dir,
        [switch]$NewWindow
    )

    # Guard: wt.exe required
    if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
        Write-Warning "Windows Terminal (wt.exe) not found. Install via: winget install Microsoft.WindowsTerminal"
        return
    }

    # Lookup layout
    if (-not $LayoutDB -or -not $LayoutDB.ContainsKey($Name)) {
        Write-Warning "Layout '$Name' not found. Available layouts:"
        if ($LayoutDB) { $LayoutDB.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan } }
        return
    }

    $layout = $LayoutDB[$Name]
    $panes = @($layout.panes)

    # Validate
    $validation = Test-LayoutPanes -Panes $panes -LayoutName $Name
    foreach ($w in $validation.Warnings) { Write-Warning $w }
    if (-not $validation.Valid) {
        foreach ($e in $validation.Errors) { Write-Host "  $e" -ForegroundColor Red }
        return
    }

    # Resolve dir
    $resolvedDir = if ($Dir) { $Dir } else { (Get-Location).Path }

    # Warn on non-existent dirs (non-blocking)
    foreach ($pane in $panes) {
        if ($pane.dir -and $pane.dir -ne '.' -and -not (Test-Path $pane.dir)) {
            Write-Warning "Directory '$($pane.dir)' does not exist — wt.exe will use fallback."
        }
    }

    # Validate WT profile names (read WT settings once per invocation)
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

    # Build wt.exe arguments
    $wtArgs = Build-WtCommand -Panes $panes -ResolvedDir $resolvedDir

    # Prepend window targeting
    $prefix = @()
    if ($env:WT_SESSION -and -not $NewWindow) {
        $prefix = @('-w', '0', 'nt')
    }
    $finalArgs = $prefix + $wtArgs

    # Execute
    Start-Process wt -ArgumentList $finalArgs
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Open-Layout function with tests"
```

---

### Task 6: Implement `Save-Layout` and `Remove-Layout`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Save-Layout" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{ description = "predefined"; panes = @(@{ split = "root" }) }
        }
        $script:_predefinedLayoutNames = @('dual-pane')
        $testDir = Join-Path $env:TEMP "pnx-layout-test-$(Get-Random)"
        New-Item $testDir -ItemType Directory -Force | Out-Null
        $script:_customLayoutPath = Join-Path $testDir "layouts.json"
    }
    AfterAll {
        Remove-Item (Split-Path $script:_customLayoutPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Saves a new custom layout" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        Save-Layout -Name "my-setup" -Panes $panes -Description "Test layout"
        $LayoutDB.ContainsKey('my-setup') | Should -BeTrue
        Test-Path $script:_customLayoutPath | Should -BeTrue
    }

    It "Silently overwrites existing custom layout" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" }
        )
        Save-Layout -Name "my-setup" -Panes $panes -Description "Updated"
        $LayoutDB['my-setup'].panes.Count | Should -Be 1
    }

    It "Rejects saving with predefined name" {
        $panes = @(@{ profile = "PowerShell"; dir = "."; split = "root" })
        $output = Save-Layout -Name "dual-pane" -Panes $panes 3>&1 2>&1 | Out-String
        $output | Should -Match 'predefined'
    }
}

Describe "Remove-Layout" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{ description = "predefined"; panes = @(@{ split = "root" }) }
            'custom-one' = @{ description = "custom"; panes = @(@{ split = "root" }) }
        }
        $script:_predefinedLayoutNames = @('dual-pane')
        $testDir = Join-Path $env:TEMP "pnx-layout-test-$(Get-Random)"
        New-Item $testDir -ItemType Directory -Force | Out-Null
        $script:_customLayoutPath = Join-Path $testDir "layouts.json"
        # Write initial custom file
        @{ 'custom-one' = @{ description = "custom"; panes = @(@{ split = "root" }) } } |
            ConvertTo-Json -Depth 10 | Set-Content $script:_customLayoutPath
    }
    AfterAll {
        Remove-Item (Split-Path $script:_customLayoutPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Removes a custom layout" {
        Remove-Layout -Name "custom-one"
        $LayoutDB.ContainsKey('custom-one') | Should -BeFalse
    }

    It "Rejects removing a predefined layout" {
        $output = Remove-Layout -Name "dual-pane" 3>&1 2>&1 | Out-String
        $output | Should -Match 'predefined'
        $LayoutDB.ContainsKey('dual-pane') | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: Save/Remove tests FAIL

- [ ] **Step 3: Implement `Save-Layout` and `Remove-Layout`**

Add to `scripts/pane-layout.ps1`:

```powershell
function Save-Layout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][array]$Panes,
        [string]$Description = ""
    )

    # Block saving with predefined name
    if ($_predefinedLayoutNames -contains $Name) {
        Write-Warning "Cannot save layout '$Name' — it is a predefined layout. Use a different name."
        return
    }

    # Validate panes
    $validation = Test-LayoutPanes -Panes $Panes -LayoutName $Name
    foreach ($w in $validation.Warnings) { Write-Warning $w }
    if (-not $validation.Valid) {
        foreach ($e in $validation.Errors) { Write-Host "  $e" -ForegroundColor Red }
        return
    }

    # Update runtime DB
    $LayoutDB[$Name] = @{ description = $Description; panes = $Panes }

    # Persist to local file
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

    # Update local file
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Save-Layout and Remove-Layout with tests"
```

---

### Task 7: Implement `Get-LayoutCommand`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing test**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Get-LayoutCommand" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{ description = "Two shells"; panes = @(
                @{ profile = "PowerShell"; dir = "."; split = "root" },
                @{ profile = "PowerShell"; dir = "."; split = "vertical" }
            )}
        }
    }

    It "Outputs wt.exe command string" {
        $result = Get-LayoutCommand -Name 'dual-pane' -Dir 'C:\proj' 6>&1 | Out-String
        $result | Should -Match 'wt\.exe'
        $result | Should -Match 'split-pane'
        $result | Should -Match 'PowerShell'
    }

    It "Uses semicolons as wt subcommand separators" {
        $result = Get-LayoutCommand -Name 'dual-pane' -Dir 'C:\proj' 6>&1 | Out-String
        $result | Should -Match ';'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: FAIL

- [ ] **Step 3: Implement `Get-LayoutCommand`**

Add to `scripts/pane-layout.ps1`:

```powershell
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

    # Build display string (for batch/shortcut use)
    $cmdParts = @('wt.exe')
    foreach ($arg in $wtArgs) {
        if ($arg -match '\s') { $cmdParts += "`"$arg`"" }
        else { $cmdParts += $arg }
    }
    $cmdString = $cmdParts -join ' '
    Write-Host $cmdString
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Get-LayoutCommand shortcut generator"
```

---

## Chunk 3: New-ClaudeProfile, Show-Cheatsheet, Profile Integration

### Task 8: Implement `New-ClaudeProfile`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "New-ClaudeProfile" {
    BeforeAll {
        # Mock WT settings with no Claude profile
        $testWtDir = Join-Path $env:TEMP "pnx-wt-test-$(Get-Random)"
        New-Item $testWtDir -ItemType Directory -Force | Out-Null
        $script:WtSettingsPath = Join-Path $testWtDir "settings.json"
        @{
            profiles = @{
                defaults = @{}
                list = @(
                    @{ name = "PowerShell"; guid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"; source = "Windows.Terminal.PowershellCore" }
                )
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $script:WtSettingsPath

        # Mock Save-WtSettings to just write directly
        function Save-WtSettings { param($Json, $WtPath) $Json | ConvertTo-Json -Depth 20 | Set-Content $WtPath -Encoding utf8NoBOM; return $true }
    }
    AfterAll {
        Remove-Item (Split-Path $script:WtSettingsPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Creates Claude profile in WT settings" {
        New-ClaudeProfile
        $wt = Get-Content $script:WtSettingsPath -Raw | ConvertFrom-Json
        $claude = $wt.profiles.list | Where-Object { $_.name -eq 'Claude' }
        $claude | Should -Not -BeNullOrEmpty
        $claude.commandline | Should -Be 'claude'
    }

    It "Skips if Claude profile already exists" {
        $output = New-ClaudeProfile 6>&1 3>&1 | Out-String
        $output | Should -Match 'already exists'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: FAIL

- [ ] **Step 3: Implement `New-ClaudeProfile`**

Add to `scripts/pane-layout.ps1`:

```powershell
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

    # Check if Claude profile already exists
    $existing = $wtJson.profiles.list | Where-Object { $_.name -eq 'Claude' }
    if ($existing) {
        Write-Host "  Claude profile already exists in Windows Terminal." -ForegroundColor DarkGray
        return
    }

    # Generate a deterministic GUID for Claude profile
    $claudeGuid = "{c1a0de00-c0de-4c1a-bde0-000000000001}"
    $claudeProfile = [PSCustomObject]@{
        name        = "Claude"
        commandline = "claude"
        guid        = $claudeGuid
        hidden      = $false
        icon        = "\u2728"
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add New-ClaudeProfile helper"
```

---

### Task 9: Implement `Show-Cheatsheet`

**Files:**
- Modify: `scripts/pane-layout.ps1`
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Write failing tests**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "Show-Cheatsheet" {
    It "Shows all categories by default" {
        $output = Show-Cheatsheet 6>&1 | Out-String
        $output | Should -Match 'THEME'
        $output | Should -Match 'PANE'
        $output | Should -Match 'CONFIG'
        $output | Should -Match 'KEYBOARD'
    }

    It "Filters by theme category" {
        $output = Show-Cheatsheet -Category 'theme' 6>&1 | Out-String
        $output | Should -Match 'Set-Theme'
        $output | Should -Not -Match 'Open-Layout'
    }

    It "Filters by pane category" {
        $output = Show-Cheatsheet -Category 'pane' 6>&1 | Out-String
        $output | Should -Match 'Open-Layout'
        $output | Should -Not -Match 'Set-Theme'
    }

    It "Filters by keys category" {
        $output = Show-Cheatsheet -Category 'keys' 6>&1 | Out-String
        $output | Should -Match 'Alt\+Shift'
    }

    It "Errors on unknown category" {
        { Show-Cheatsheet -Category 'invalid' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: FAIL

- [ ] **Step 3: Implement `Show-Cheatsheet`**

Add to `scripts/pane-layout.ps1`:

```powershell
function Show-Cheatsheet {
    [CmdletBinding()]
    param(
        [ValidateSet('theme', 'pane', 'config', 'keys', 'all')]
        [string]$Category = 'all'
    )

    $line = [string]::new([char]0x2500, 45)
    $sections = @{
        theme = @(
            ""
            "  THEME"
            "  $line"
            "  Set-Theme <name> [style]     Switch theme (e.g., Set-Theme tokyo mac)"
            "  Get-ThemeList                 Show all available themes"
            "  Set-Style <style>             Switch style only (mac/win/linux)"
            "  Select-ThemeInteractive       Arrow-key theme picker"
            "  New-PnxTheme -Name <n> ...   Create custom theme"
            "  Test-ThemeIntegrity           Validate theme components"
        )
        pane = @(
            ""
            "  PANE LAYOUTS"
            "  $line"
            "  Open-Layout <name>            Open a pane layout"
            "  Open-Layout <name> -NewWindow Open in new window"
            "  Get-LayoutList                Show all layouts"
            "  Save-Layout <name> -Panes ..  Save custom layout"
            "  Get-LayoutCommand <name>      Export wt.exe command"
            "  New-ClaudeProfile             Create Claude WT profile"
        )
        config = @(
            ""
            "  CONFIG"
            "  $line"
            "  Sync-Config push|pull         Sync local <-> repo"
            "  Update-Workspace              Pull + redeploy + reload"
            "  Get-Status                    Health check"
            "  Update-Tools                  Update all packages"
            "  Deploy-ClaudeConfig           Deploy Claude configs"
        )
        keys = @(
            ""
            "  KEYBOARD SHORTCUTS (Windows Terminal)"
            "  $line"
            "  Alt+Shift+D                   Auto split pane"
            "  Alt+Shift++ / Alt+Shift+-     Split vertical / horizontal"
            "  Alt+Arrow                     Move focus between panes"
            "  Alt+Shift+Arrow               Resize pane"
            "  Ctrl+Shift+W                  Close pane"
            "  Ctrl+Shift+T                  New tab"
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/pane-layout.ps1 tests/layout.tests.ps1
git commit -m "feat: add Show-Cheatsheet with category filtering"
```

---

### Task 10: Integrate into `configs/profile.ps1`

**Files:**
- Modify: `configs/profile.ps1:92` (after ThemeDB + StyleDB + defaults fully loaded)
- Modify: `configs/profile.ps1:279` (after health check + Remove-Variable _healthIssues)
- Modify: `configs/profile.ps1:320` (after existing argument completers)

- [ ] **Step 1: Add LayoutDB loading after ThemeDB section**

Insert after line 92 (`Remove-Variable _pnxManifest, _manifestPath`) in `configs/profile.ps1` — this is after ThemeDB, StyleDB, and defaults are fully loaded:

```powershell
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
```

- [ ] **Step 2: Add argument completers after existing completers (after line 320)**

Insert after the existing `Register-ArgumentCompleter` block:

```powershell
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
```

- [ ] **Step 3: Add welcome line after health check (after line 278)**

Insert after line 279 (`Remove-Variable _healthIssues -ErrorAction SilentlyContinue`):

```powershell
# ===== Welcome line (interactive sessions only) =====
if ([Environment]::UserInteractive -and -not $env:PNX_NO_WELCOME) {
    $_themeName = if ($Global:PnxCurrentTheme) { $Global:PnxCurrentTheme } else { "default" }
    $_styleName = if ($Global:PnxCurrentStyle) { "($Global:PnxCurrentStyle)" } else { "" }
    Write-Host "  PNX Terminal | $_themeName $_styleName | Show-Cheatsheet for help" -ForegroundColor DarkGray
    Remove-Variable _themeName, _styleName -ErrorAction SilentlyContinue
}
```

- [ ] **Step 4: Validate profile syntax**

Run: `pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('configs/profile.ps1', [ref]\$null, [ref]\$errors); if (\$errors) { \$errors | ForEach-Object { Write-Host \$_ } } else { Write-Host 'Syntax OK' }"`
Expected: `Syntax OK`

- [ ] **Step 5: Run all tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/ -Output Detailed"`
Expected: All tests PASS (both profile.tests.ps1 and layout.tests.ps1)

- [ ] **Step 6: Commit**

```bash
git add configs/profile.ps1
git commit -m "feat: integrate LayoutDB loading, completers, and welcome line into profile"
```

---

### Task 11: Add remaining edge case tests

**Files:**
- Modify: `tests/layout.tests.ps1`

- [ ] **Step 1: Add missing tests from spec test plan**

Append to `tests/layout.tests.ps1`:

```powershell
Describe "LayoutDB Merge — Predefined Wins" {
    It "Predefined layout overrides custom with same name" {
        $predefined = @{ 'dual-pane' = @{ description = "predefined"; panes = @(@{ split = "root" }) } }
        $custom = [PSCustomObject]@{ 'dual-pane' = [PSCustomObject]@{ description = "custom"; panes = @(@{ split = "root" }) } }
        $db = @{}
        foreach ($k in $predefined.Keys) { $db[$k] = $predefined[$k] }
        foreach ($p in $custom.PSObject.Properties) {
            if (-not $db.ContainsKey($p.Name)) { $db[$p.Name] = @{ description = $p.Value.description; panes = @($p.Value.panes) } }
        }
        $db['dual-pane'].description | Should -Be "predefined"
    }

    It "Custom layout with unique name is added" {
        $db = @{ 'dual-pane' = @{ description = "predefined"; panes = @() } }
        $custom = [PSCustomObject]@{ 'my-custom' = [PSCustomObject]@{ description = "mine"; panes = @(@{ split = "root" }) } }
        foreach ($p in $custom.PSObject.Properties) {
            if (-not $db.ContainsKey($p.Name)) { $db[$p.Name] = @{ description = $p.Value.description; panes = @($p.Value.panes) } }
        }
        $db.ContainsKey('my-custom') | Should -BeTrue
    }
}

Describe "Corrupted layouts.json" {
    It "Gracefully handles malformed JSON" {
        $tempFile = Join-Path $env:TEMP "pnx-corrupt-test-$(Get-Random).json"
        "{ invalid json" | Set-Content $tempFile
        $result = $null
        try {
            $result = Get-Content $tempFile -Raw | ConvertFrom-Json
        } catch {
            $result = $null
        }
        $result | Should -BeNullOrEmpty
        Remove-Item $tempFile -Force
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/layout.tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add tests/layout.tests.ps1
git commit -m "test: add edge case tests for merge strategy and corrupted JSON"
```

---

## Chunk 4: Final Verification

### Task 12: End-to-end verification

- [ ] **Step 1: Validate all file syntax**

Run:
```bash
pwsh -NoProfile -Command "
  @('configs/profile.ps1', 'scripts/pane-layout.ps1', 'scripts/common.ps1') | ForEach-Object {
    \$errors = \$null
    [System.Management.Automation.Language.Parser]::ParseFile(\$_, [ref]\$null, [ref]\$errors)
    if (\$errors) { Write-Host \"FAIL: \$_\" -ForegroundColor Red; \$errors | ForEach-Object { Write-Host \"  \$_\" } }
    else { Write-Host \"OK: \$_\" -ForegroundColor Green }
  }
"
```
Expected: All 3 files OK

- [ ] **Step 2: Run full test suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/ -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 3: Validate layouts.json integrity**

Run: `pwsh -NoProfile -Command "$d = Get-Content configs/layouts.json -Raw | ConvertFrom-Json; Write-Host \"Layouts: $(@($d.layouts.PSObject.Properties).Count)\"; $d.layouts.PSObject.Properties | ForEach-Object { Write-Host \"  $($_.Name): $(@($_.Value.panes).Count) panes\" }"`
Expected: 4 layouts listed with correct pane counts

- [ ] **Step 4: Smoke test (manual)**

Open a new PowerShell terminal and verify:
1. Welcome line appears: `PNX Terminal | <theme> (<style>) | Show-Cheatsheet for help`
2. `Show-Cheatsheet` displays all categories
3. `Show-Cheatsheet pane` filters correctly
4. `Get-LayoutList` shows 4 predefined layouts
5. `Open-Layout dual-pane` opens a new tab with 2 panes (requires WT)
6. `Open-Layout <Tab>` shows completion
7. `Get-LayoutCommand dual-pane` outputs wt.exe command string

- [ ] **Step 5: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address issues found during e2e verification"
```
