#Requires -Modules Pester
# Tests for scripts/pane-layout.ps1

BeforeAll {
    # pane-layout.ps1 has no dependency on common.ps1
    . "$PSScriptRoot\..\scripts\pane-layout.ps1"
}

Describe "Build-WtCommand" {
    It "Single root pane returns correct args" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $result | Should -BeOfType [string]
        $result.Count | Should -BeGreaterOrEqual 4
        $joined = $result -join " "
        $joined | Should -BeLike "*-p PowerShell*"
        $joined | Should -BeLike "*-d C:\Projects*"
    }

    It "Two-pane vertical split returns correct args with split-pane -V" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -BeLike "*; split-pane -V*"
        $joined | Should -BeLike "*-p PowerShell*"
    }

    It "Three-pane mixed split returns correct args" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" },
            @{ profile = "PowerShell"; dir = "."; split = "horizontal" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -BeLike "*; split-pane -V*"
        $joined | Should -BeLike "*; split-pane -H*"
    }

    It "Size specified includes --size" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; size = 0.3 }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -BeLike "*--size 0.3*"
    }

    It "Title specified includes --title" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root"; title = "Main" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; title = "Side" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -BeLike "*--title Main*"
        $joined | Should -BeLike "*--title Side*"
    }

    It "Null profile omits -p flag" {
        $panes = @(
            @{ profile = $null; dir = "."; split = "root" },
            @{ profile = $null; dir = "."; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -Not -BeLike "*-p *"
    }

    It "Absolute dir is used as-is, dot is resolved" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "D:\Other"; split = "vertical" }
        )
        $result = Build-WtCommand -Panes $panes -ResolvedDir "C:\Projects"
        $joined = $result -join " "
        $joined | Should -BeLike "*-d C:\Projects*"
        $joined | Should -BeLike "*-d D:\Other*"
    }
}

Describe "Test-LayoutPanes" {
    It "Valid layout returns Valid=true with no errors" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeTrue
        $result.Errors.Count | Should -Be 0
    }

    It "First pane not root returns Valid=false" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
        $result.Errors | Should -Not -BeNullOrEmpty
    }

    It "Invalid split value returns Valid=false" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "diagonal" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
        $result.Errors | Should -Not -BeNullOrEmpty
    }

    It "Empty panes returns Valid=false" {
        $result = Test-LayoutPanes -Panes @() -LayoutName "test"
        $result.Valid | Should -BeFalse
        $result.Errors | Should -Not -BeNullOrEmpty
    }

    It "Invalid size returns Valid=false" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; size = 1.5 }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
        $result.Errors | Should -Not -BeNullOrEmpty
    }

    It "Size of 0 returns Valid=false" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical"; size = 0.0 }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeFalse
    }

    It "Parent field present returns Valid=true with warning" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root"; parent = 0 },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $result = Test-LayoutPanes -Panes $panes -LayoutName "test"
        $result.Valid | Should -BeTrue
        $result.Warnings | Should -Not -BeNullOrEmpty
        $result.Warnings[0] | Should -BeLike "*reserved*"
    }
}

Describe "Get-LayoutList" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{
                description = 'Two shells side by side'
                panes = @(
                    @{ profile = "PowerShell"; dir = "."; split = "root" },
                    @{ profile = "PowerShell"; dir = "."; split = "vertical" }
                )
            }
            'triple-pane' = @{
                description = '3 panes layout'
                panes = @(
                    @{ profile = "PowerShell"; dir = "."; split = "root" },
                    @{ profile = "PowerShell"; dir = "."; split = "vertical" },
                    @{ profile = "PowerShell"; dir = "."; split = "horizontal" }
                )
            }
        }
    }

    It "Output contains layout names" {
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -BeLike "*dual-pane*"
        $output | Should -BeLike "*triple-pane*"
    }

    It "Output contains pane counts" {
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -BeLike "*2 panes*"
        $output | Should -BeLike "*3 panes*"
    }

    It "Output shows count of available layouts" {
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -BeLike "*2 available*"
    }

    It "Shows message when LayoutDB is empty" {
        $savedDB = $script:LayoutDB
        $script:LayoutDB = @{}
        $output = Get-LayoutList 6>&1 | Out-String
        $output | Should -BeLike "*No layouts available*"
        $script:LayoutDB = $savedDB
    }
}
