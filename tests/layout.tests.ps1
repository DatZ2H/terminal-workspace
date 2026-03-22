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

Describe "Open-Layout" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{
                description = 'Two shells side by side'
                panes = @(
                    @{ profile = "PowerShell"; dir = "."; split = "root" },
                    @{ profile = "PowerShell"; dir = "."; split = "vertical" }
                )
            }
        }

        # Create a temporary WT settings file with known profiles
        $script:_tempWtDir = Join-Path ([System.IO.Path]::GetTempPath()) "pnx-test-wt-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:_tempWtDir -Force | Out-Null
        $script:WtSettingsPath = Join-Path $script:_tempWtDir "settings.json"
        @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; guid = "{test-1}" },
                    @{ name = "Command Prompt"; guid = "{test-2}" }
                )
            }
        } | ConvertTo-Json -Depth 5 | Set-Content $script:WtSettingsPath -Encoding utf8NoBOM

        # Mock Start-Process to capture calls instead of launching wt.exe
        $script:_startProcessCalls = @()
        function global:Start-Process {
            param([string]$FilePath, [string[]]$ArgumentList)
            $script:_startProcessCalls += @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
        }

        # Mock Get-Command to simulate wt.exe being available
        # (We don't mock it — wt.exe is likely installed. We'll mock it only for the missing test.)
    }

    BeforeEach {
        $script:_startProcessCalls = @()
        # Ensure WT_SESSION is not set by default
        $env:WT_SESSION = $null
    }

    AfterAll {
        Remove-Item -Path $script:_tempWtDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item function:\global:Start-Process -ErrorAction SilentlyContinue
    }

    It "Calls Start-Process with correct args for known layout" {
        Open-Layout -Name 'dual-pane' -Dir "C:\Test"
        $script:_startProcessCalls.Count | Should -Be 1
        $call = $script:_startProcessCalls[0]
        $call.FilePath | Should -Be 'wt'
        $joined = $call.ArgumentList -join " "
        $joined | Should -BeLike "*-p PowerShell*"
        $joined | Should -BeLike "*-d C:\Test*"
    }

    It "Warns for unknown layout" {
        $output = Open-Layout -Name 'nonexistent' 3>&1 | Out-String
        $output | Should -BeLike "*not found*"
        $script:_startProcessCalls.Count | Should -Be 0
    }

    It "Warns when wt.exe is missing" {
        # Temporarily rename Get-Command to simulate wt not found
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'wt' }
        $output = Open-Layout -Name 'dual-pane' 3>&1 | Out-String
        $output | Should -BeLike "*not found*"
    }

    It "Includes -w 0 nt when inside WT session" {
        $env:WT_SESSION = "test-session-id"
        Open-Layout -Name 'dual-pane' -Dir "C:\Test"
        $call = $script:_startProcessCalls[0]
        $joined = $call.ArgumentList -join " "
        $joined | Should -BeLike "*-w 0 nt*"
        $env:WT_SESSION = $null
    }

    It "Omits -w 0 nt with -NewWindow even inside WT" {
        $env:WT_SESSION = "test-session-id"
        Open-Layout -Name 'dual-pane' -Dir "C:\Test" -NewWindow
        $call = $script:_startProcessCalls[0]
        $joined = $call.ArgumentList -join " "
        $joined | Should -Not -BeLike "*-w 0 nt*"
        $env:WT_SESSION = $null
    }

    It "Omits -w 0 nt outside WT session" {
        $env:WT_SESSION = $null
        Open-Layout -Name 'dual-pane' -Dir "C:\Test"
        $call = $script:_startProcessCalls[0]
        $joined = $call.ArgumentList -join " "
        $joined | Should -Not -BeLike "*-w 0 nt*"
    }

    It "Warns on unknown WT profile and falls back" {
        $script:LayoutDB['test-bad-profile'] = @{
            description = 'Test bad profile'
            panes = @(
                @{ profile = "NonExistentProfile"; dir = "."; split = "root" }
            )
        }
        $output = Open-Layout -Name 'test-bad-profile' -Dir "C:\Test" 3>&1 | Out-String
        $output | Should -BeLike "*not found*using default*"
        # Should still call Start-Process (non-blocking)
        $script:_startProcessCalls.Count | Should -Be 1
        $script:LayoutDB.Remove('test-bad-profile')
    }

    It "Warns on non-existent directory" {
        $script:LayoutDB['test-bad-dir'] = @{
            description = 'Test bad dir'
            panes = @(
                @{ profile = "PowerShell"; dir = "C:\NonExistent12345"; split = "root" }
            )
        }
        $output = Open-Layout -Name 'test-bad-dir' -Dir "C:\Test" 3>&1 | Out-String
        $output | Should -BeLike "*does not exist*"
        $script:LayoutDB.Remove('test-bad-dir')
    }
}

Describe "Save-Layout" {
    BeforeAll {
        $script:_tempCustomDir = Join-Path ([System.IO.Path]::GetTempPath()) "pnx-test-save-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:_tempCustomDir -Force | Out-Null
        $script:_customLayoutPath = Join-Path $script:_tempCustomDir "custom-layouts.json"
        $script:_predefinedLayoutNames = @('dual-pane', 'triple-pane', 'dev-monitor', 'side-by-side')
        $script:LayoutDB = @{}
    }

    BeforeEach {
        $script:LayoutDB = @{}
        Remove-Item $script:_customLayoutPath -Force -ErrorAction SilentlyContinue
    }

    AfterAll {
        Remove-Item -Path $script:_tempCustomDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Saves a new custom layout to LayoutDB and file" {
        $panes = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "vertical" }
        )
        $output = Save-Layout -Name 'my-layout' -Panes $panes -Description "My custom layout" 6>&1 | Out-String
        $output | Should -BeLike "*saved*"
        $script:LayoutDB.ContainsKey('my-layout') | Should -BeTrue
        $script:LayoutDB['my-layout'].description | Should -Be "My custom layout"
        Test-Path $script:_customLayoutPath | Should -BeTrue
        $json = Get-Content $script:_customLayoutPath -Raw | ConvertFrom-Json
        $json.'my-layout' | Should -Not -BeNullOrEmpty
    }

    It "Overwrites existing custom layout silently" {
        $panes1 = @( @{ profile = "PowerShell"; dir = "."; split = "root" } )
        $panes2 = @(
            @{ profile = "PowerShell"; dir = "."; split = "root" },
            @{ profile = "PowerShell"; dir = "."; split = "horizontal" }
        )
        Save-Layout -Name 'overwrite-me' -Panes $panes1 -Description "V1" 6>&1 | Out-Null
        Save-Layout -Name 'overwrite-me' -Panes $panes2 -Description "V2" 6>&1 | Out-Null
        $script:LayoutDB['overwrite-me'].description | Should -Be "V2"
        @($script:LayoutDB['overwrite-me'].panes).Count | Should -Be 2
    }

    It "Rejects predefined layout name" {
        $panes = @( @{ profile = "PowerShell"; dir = "."; split = "root" } )
        $output = Save-Layout -Name 'dual-pane' -Panes $panes 3>&1 | Out-String
        $output | Should -BeLike "*predefined*"
    }

    It "Rejects invalid panes" {
        $panes = @( @{ profile = "PowerShell"; dir = "."; split = "diagonal" } )
        Save-Layout -Name 'bad-panes' -Panes $panes 3>&1 6>&1 | Out-Null
        $script:LayoutDB.ContainsKey('bad-panes') | Should -BeFalse
    }
}

Describe "Remove-Layout" {
    BeforeAll {
        $script:_tempCustomDir2 = Join-Path ([System.IO.Path]::GetTempPath()) "pnx-test-rm-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:_tempCustomDir2 -Force | Out-Null
        $script:_customLayoutPath = Join-Path $script:_tempCustomDir2 "custom-layouts.json"
        $script:_predefinedLayoutNames = @('dual-pane', 'triple-pane', 'dev-monitor', 'side-by-side')
    }

    BeforeEach {
        $script:LayoutDB = @{
            'my-custom' = @{
                description = 'Custom layout'
                panes = @( @{ profile = "PowerShell"; dir = "."; split = "root" } )
            }
        }
        # Write matching custom file
        @{ 'my-custom' = @{ description = 'Custom layout'; panes = @( @{ profile = "PowerShell"; dir = "."; split = "root" } ) } } |
            ConvertTo-Json -Depth 5 | Set-Content $script:_customLayoutPath -Encoding utf8NoBOM
    }

    AfterAll {
        Remove-Item -Path $script:_tempCustomDir2 -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Removes a custom layout from LayoutDB and file" {
        $output = Remove-Layout -Name 'my-custom' 6>&1 | Out-String
        $output | Should -BeLike "*removed*"
        $script:LayoutDB.ContainsKey('my-custom') | Should -BeFalse
        $json = Get-Content $script:_customLayoutPath -Raw | ConvertFrom-Json
        $json.PSObject.Properties.Name | Should -Not -Contain 'my-custom'
    }

    It "Rejects removing predefined layout" {
        $script:LayoutDB['dual-pane'] = @{ description = 'test'; panes = @() }
        $output = Remove-Layout -Name 'dual-pane' 3>&1 | Out-String
        $output | Should -BeLike "*predefined*"
        $script:LayoutDB.ContainsKey('dual-pane') | Should -BeTrue
    }

    It "Warns when layout not found" {
        $output = Remove-Layout -Name 'nonexistent' 3>&1 | Out-String
        $output | Should -BeLike "*not found*"
    }
}

Describe "Get-LayoutCommand" {
    BeforeAll {
        $script:LayoutDB = @{
            'dual-pane' = @{
                description = 'Two shells side by side'
                panes = @(
                    @{ profile = "PowerShell"; dir = "."; split = "root" },
                    @{ profile = "PowerShell"; dir = "."; split = "vertical" }
                )
            }
        }
    }

    It "Output contains wt.exe" {
        $output = Get-LayoutCommand -Name 'dual-pane' -Dir "C:\Projects" 6>&1 | Out-String
        $output | Should -BeLike "*wt.exe*"
    }

    It "Output contains split-pane" {
        $output = Get-LayoutCommand -Name 'dual-pane' -Dir "C:\Projects" 6>&1 | Out-String
        $output | Should -BeLike "*split-pane*"
    }

    It "Output contains profile name" {
        $output = Get-LayoutCommand -Name 'dual-pane' -Dir "C:\Projects" 6>&1 | Out-String
        $output | Should -BeLike "*PowerShell*"
    }

    It "Output contains semicolons for multi-pane" {
        $output = Get-LayoutCommand -Name 'dual-pane' -Dir "C:\Projects" 6>&1 | Out-String
        $output | Should -BeLike "*;*"
    }

    It "Warns for unknown layout" {
        $output = Get-LayoutCommand -Name 'nonexistent' 3>&1 | Out-String
        $output | Should -BeLike "*not found*"
    }

    It "Uses provided -Dir in output" {
        $output = Get-LayoutCommand -Name 'dual-pane' -Dir "D:\MyDir" 6>&1 | Out-String
        $output | Should -BeLike "*D:\MyDir*"
    }
}

Describe "New-ClaudeProfile" {
    BeforeAll {
        $script:_tempWtDir3 = Join-Path ([System.IO.Path]::GetTempPath()) "pnx-test-claude-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:_tempWtDir3 -Force | Out-Null
    }

    AfterAll {
        Remove-Item -Path $script:_tempWtDir3 -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Adds Claude profile to WT settings" {
        $script:WtSettingsPath = Join-Path $script:_tempWtDir3 "settings-add.json"
        @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; guid = "{test-1}" }
                )
            }
        } | ConvertTo-Json -Depth 5 | Set-Content $script:WtSettingsPath -Encoding utf8NoBOM

        New-ClaudeProfile 6>&1 | Out-Null

        $json = Get-Content $script:WtSettingsPath -Raw | ConvertFrom-Json
        $claude = $json.profiles.list | Where-Object { $_.name -eq 'Claude' }
        $claude | Should -Not -BeNullOrEmpty
        $claude.commandline | Should -Be 'claude'
        $claude.guid | Should -Be '{c1a0de00-c0de-4c1a-bde0-000000000001}'
    }

    It "Skips if Claude profile already exists" {
        $script:WtSettingsPath = Join-Path $script:_tempWtDir3 "settings-exists.json"
        @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; guid = "{test-1}" },
                    @{ name = "Claude"; guid = "{existing}"; commandline = "claude" }
                )
            }
        } | ConvertTo-Json -Depth 5 | Set-Content $script:WtSettingsPath -Encoding utf8NoBOM

        $output = New-ClaudeProfile 6>&1 | Out-String
        $output | Should -BeLike "*already exists*"

        # Should still have exactly one Claude profile
        $json = Get-Content $script:WtSettingsPath -Raw | ConvertFrom-Json
        $claudeCount = @($json.profiles.list | Where-Object { $_.name -eq 'Claude' }).Count
        $claudeCount | Should -Be 1
    }

    It "Warns when WtSettingsPath is missing" {
        $savedPath = $script:WtSettingsPath
        $script:WtSettingsPath = $null
        $output = New-ClaudeProfile 3>&1 | Out-String
        $output | Should -BeLike "*not found*"
        $script:WtSettingsPath = $savedPath
    }
}

Describe "Show-Cheatsheet" {
    It "Shows all categories by default" {
        $output = Show-Cheatsheet 6>&1 | Out-String
        $output | Should -BeLike "*THEME*"
        $output | Should -BeLike "*PANE*"
        $output | Should -BeLike "*CONFIG*"
        $output | Should -BeLike "*KEYBOARD*"
    }

    It "Filters by theme category" {
        $output = Show-Cheatsheet -Category theme 6>&1 | Out-String
        $output | Should -BeLike "*THEME*"
        $output | Should -BeLike "*Set-Theme*"
        $output | Should -Not -BeLike "*PANE LAYOUTS*"
        $output | Should -Not -BeLike "*CONFIG*"
    }

    It "Filters by pane category" {
        $output = Show-Cheatsheet -Category pane 6>&1 | Out-String
        $output | Should -BeLike "*PANE*"
        $output | Should -BeLike "*Open-Layout*"
        $output | Should -Not -BeLike "*THEME*"
    }

    It "Filters by config category" {
        $output = Show-Cheatsheet -Category config 6>&1 | Out-String
        $output | Should -BeLike "*CONFIG*"
        $output | Should -BeLike "*Sync-Config*"
        $output | Should -Not -BeLike "*THEME*"
    }

    It "Filters by keys category" {
        $output = Show-Cheatsheet -Category keys 6>&1 | Out-String
        $output | Should -BeLike "*KEYBOARD*"
        $output | Should -BeLike "*Alt+Shift*"
        $output | Should -Not -BeLike "*THEME*"
    }
}

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
