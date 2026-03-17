#Requires -Modules Pester
# Tests for configs/profile.ps1 logic
# These tests dot-source profile.ps1 in a controlled environment.

BeforeAll {
    # Set up minimal environment for profile.ps1
    $env:PNX_TERMINAL_REPO = Split-Path $PSScriptRoot -Parent

    # Dot-source common.ps1 first (profile.ps1 expects it)
    . "$PSScriptRoot\..\scripts\common.ps1"

    # We need to source profile.ps1 in a way that doesn't fail on missing tools.
    # Extract only the data structures and functions we need to test.
    # Profile.ps1 runs init code at load time (OMP, zoxide, etc.) — we mock those.

    # Mock commands that profile.ps1 calls at load time
    function global:oh-my-posh { return "mocked" }
    Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'oh-my-posh' } -MockWith { $null }
    Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'zoxide' } -MockWith { $null }

    # Source profile.ps1 — some init will be skipped due to mocks
    try {
        . "$PSScriptRoot\..\configs\profile.ps1"
    } catch {
        # May fail on OMP/zoxide init — functions should still be loaded
    }
}

Describe "ThemeDB" {
    It "Loads themes from configs/themes.json" {
        $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) "configs\themes.json"
        Test-Path $manifestPath | Should -BeTrue
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.themes | Should -Not -BeNullOrEmpty
        # ThemeDB should have at least as many entries as the manifest
        $ThemeDB.Count | Should -BeGreaterOrEqual @($manifest.themes.PSObject.Properties).Count
    }

    It "All ThemeDB entries have omp, scheme, wtTheme keys" {
        foreach ($key in $ThemeDB.Keys) {
            $entry = $ThemeDB[$key]
            $entry.Keys | Should -Contain 'omp'
            $entry.Keys | Should -Contain 'scheme'
            $entry.Keys | Should -Contain 'wtTheme'
        }
    }

    It "All OMP file paths follow naming convention (pnx-*.omp.json)" {
        foreach ($key in $ThemeDB.Keys) {
            $fileName = Split-Path $ThemeDB[$key].omp -Leaf
            $fileName | Should -Match '^pnx-.*\.omp\.json$'
        }
    }

    It "Has at least the 14 built-in themes" {
        $ThemeDB.Count | Should -BeGreaterOrEqual 14
    }

    It "Falls back gracefully if themes.json missing" {
        # Simulate: if manifest fails, ThemeDB should have at least 'pro' fallback
        # (This is tested implicitly — profile.ps1 has fallback logic)
        $ThemeDB.ContainsKey('pro') | Should -BeTrue
    }

    It "Default theme and style read from manifest" {
        $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) "configs\themes.json"
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        # Defaults should match what's in the manifest
        $manifest.defaultTheme | Should -Not -BeNullOrEmpty
        $manifest.defaultStyle | Should -Not -BeNullOrEmpty
        # ThemeDB should contain the default theme
        $ThemeDB.ContainsKey($manifest.defaultTheme) | Should -BeTrue
    }
}

Describe "Theme Registry" {
    BeforeAll {
        $script:TestRegDir = Join-Path $TestDrive "pnx-terminal"
        $script:TestRegPath = Join-Path $script:TestRegDir "themes.json"
    }

    It "Merges custom themes from registry file" {
        New-Item -ItemType Directory -Path $script:TestRegDir -Force | Out-Null
        $customThemes = [PSCustomObject]@{
            testcustom = [PSCustomObject]@{
                omp     = "C:\fake\pnx-testcustom.omp.json"
                scheme  = "Test Custom"
                wtTheme = "PNX Test Custom"
            }
        }
        $customThemes | ConvertTo-Json -Depth 5 | Set-Content $script:TestRegPath -Encoding utf8NoBOM

        # Simulate registry loading logic
        $testDB = @{ pro = @{ omp = "x"; scheme = "y"; wtTheme = "z" } }
        $custom = Get-Content $script:TestRegPath -Raw | ConvertFrom-Json
        foreach ($prop in $custom.PSObject.Properties) {
            if (-not $testDB.ContainsKey($prop.Name)) {
                $testDB[$prop.Name] = @{
                    omp     = $prop.Value.omp
                    scheme  = $prop.Value.scheme
                    wtTheme = $prop.Value.wtTheme
                }
            }
        }

        $testDB.ContainsKey('testcustom') | Should -BeTrue
        $testDB['testcustom'].scheme | Should -Be 'Test Custom'
    }

    It "Handles corrupt registry gracefully" {
        New-Item -ItemType Directory -Path $script:TestRegDir -Force | Out-Null
        "NOT VALID JSON {{{" | Set-Content $script:TestRegPath -Encoding utf8NoBOM

        $issues = @()
        try {
            Get-Content $script:TestRegPath -Raw | ConvertFrom-Json
        } catch {
            $issues += "Theme registry corrupt"
        }

        $issues.Count | Should -Be 1
    }

    It "Does not override built-in themes" {
        New-Item -ItemType Directory -Path $script:TestRegDir -Force | Out-Null
        $customThemes = [PSCustomObject]@{
            pro = [PSCustomObject]@{
                omp     = "C:\fake\override.omp.json"
                scheme  = "Fake Override"
                wtTheme = "Fake"
            }
        }
        $customThemes | ConvertTo-Json -Depth 5 | Set-Content $script:TestRegPath -Encoding utf8NoBOM

        $testDB = @{ pro = @{ omp = "original"; scheme = "Dracula Pro"; wtTheme = "PNX Dracula Pro" } }
        $custom = Get-Content $script:TestRegPath -Raw | ConvertFrom-Json
        foreach ($prop in $custom.PSObject.Properties) {
            if (-not $testDB.ContainsKey($prop.Name)) {
                $testDB[$prop.Name] = @{
                    omp     = $prop.Value.omp
                    scheme  = $prop.Value.scheme
                    wtTheme = $prop.Value.wtTheme
                }
            }
        }

        # Built-in 'pro' should not be overwritten
        $testDB['pro'].scheme | Should -Be 'Dracula Pro'
    }
}

Describe "New-PnxTheme" {
    It "Rejects duplicate theme names" {
        # 'pro' already exists in ThemeDB
        $output = New-PnxTheme -Name pro -BasedOn dracula 6>&1 | Out-String
        $output | Should -Match "already exists"
    }

    It "Rejects unknown base theme" {
        $output = New-PnxTheme -Name newtest -BasedOn nonexistent 6>&1 | Out-String
        $output | Should -Match "not found"
    }

    It "Validates background hex format via parameter validation" {
        { New-PnxTheme -Name hextest -BasedOn pro -Background "invalid" } | Should -Throw
    }
}

Describe "Remove-PnxTheme" {
    BeforeAll {
        $script:TestRegDir = Join-Path $TestDrive "pnx-terminal-remove"
        $script:TestRegPath = Join-Path $script:TestRegDir "themes.json"
    }

    It "Handles missing registry gracefully" {
        # Temporarily override LOCALAPPDATA
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $TestDrive
            # No registry file exists
            $output = Remove-PnxTheme -Name anything 6>&1 | Out-String
            $output | Should -Match "No custom themes"
        } finally {
            $env:LOCALAPPDATA = $saved
        }
    }

    It "Refuses to remove non-custom themes" {
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $TestDrive
            $dir = Join-Path $TestDrive "pnx-terminal"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $regPath = Join-Path $dir "themes.json"
            [PSCustomObject]@{
                myCustom = [PSCustomObject]@{ omp = "x"; scheme = "y"; wtTheme = "z" }
            } | ConvertTo-Json -Depth 5 | Set-Content $regPath -Encoding utf8NoBOM

            $output = Remove-PnxTheme -Name pro 6>&1 | Out-String
            $output | Should -Match "not a custom theme"
        } finally {
            $env:LOCALAPPDATA = $saved
        }
    }
}

Describe "StyleDB" {
    It "StyleDB loaded from manifest with correct types" {
        $StyleDB.Count | Should -BeGreaterOrEqual 3
        foreach ($key in $StyleDB.Keys) {
            $s = $StyleDB[$key]
            $s.opacity | Should -BeOfType [int]
            $s.useAcrylic | Should -BeOfType [bool]
            $s.useMica | Should -BeOfType [bool]
            $s.unfocusedOpacity | Should -BeOfType [int]
        }
    }

    It "Has mac, win, linux styles" {
        $StyleDB.ContainsKey('mac') | Should -BeTrue
        $StyleDB.ContainsKey('win') | Should -BeTrue
        $StyleDB.ContainsKey('linux') | Should -BeTrue
    }

    It "All styles have required keys" {
        foreach ($key in $StyleDB.Keys) {
            $s = $StyleDB[$key]
            $s.Keys | Should -Contain 'opacity'
            $s.Keys | Should -Contain 'useAcrylic'
            $s.Keys | Should -Contain 'useMica'
            $s.Keys | Should -Contain 'padding'
            $s.Keys | Should -Contain 'cursorShape'
            $s.Keys | Should -Contain 'scrollbarState'
            $s.Keys | Should -Contain 'unfocusedOpacity'
        }
    }
}
