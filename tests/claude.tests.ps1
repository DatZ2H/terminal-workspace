#Requires -Modules Pester
# Tests for Claude Code deploy, merge, and secret stripping

BeforeAll {
    . "$PSScriptRoot\..\scripts\common.ps1"
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}

Describe "Get-ClaudeConfigPath" {
    It "Returns settings.json path by default" {
        $result = Get-ClaudeConfigPath
        if ($result) {
            $result | Should -BeLike "*settings.json"
        } else {
            Set-ItResult -Skipped -Because "~/.claude/ not found"
        }
    }

    It "Returns CLAUDE.md path for type claude.md" {
        $result = Get-ClaudeConfigPath -Type 'claude.md'
        if ($result) {
            $result | Should -BeLike "*CLAUDE.md"
        } else {
            Set-ItResult -Skipped -Because "~/.claude/ not found"
        }
    }

    It "Returns statusline.sh path for type statusline" {
        $result = Get-ClaudeConfigPath -Type statusline
        if ($result) {
            $result | Should -BeLike "*statusline.sh"
        } else {
            Set-ItResult -Skipped -Because "~/.claude/ not found"
        }
    }

    It "Returns `$null when USERPROFILE/.claude does not exist" {
        $saved = $env:USERPROFILE
        try {
            $env:USERPROFILE = Join-Path $TestDrive "nonexistent-user"
            Get-ClaudeConfigPath | Should -BeNullOrEmpty
        } finally {
            $env:USERPROFILE = $saved
        }
    }
}

Describe "Merge-JsonAdditive" {
    It "Adds new keys from Source to Target" {
        $target = [PSCustomObject]@{ existing = "value" }
        $source = [PSCustomObject]@{ newKey = "newValue" }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @()
        $result | Should -BeTrue
        $target.newKey | Should -Be "newValue"
        $target.existing | Should -Be "value"
    }

    It "Does not overwrite existing keys (user wins)" {
        $target = [PSCustomObject]@{ myKey = "userValue" }
        $source = [PSCustomObject]@{ myKey = "templateValue" }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @()
        $result | Should -BeFalse
        $target.myKey | Should -Be "userValue"
    }

    It "Skips protected keys entirely" {
        $target = [PSCustomObject]@{}
        $source = [PSCustomObject]@{ mcpServers = @{ github = @{} } }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @('mcpServers') -OverwriteKeys @()
        $result | Should -BeFalse
        $target.PSObject.Properties['mcpServers'] | Should -BeNullOrEmpty
    }

    It "Overwrites keys in OverwriteKeys list" {
        $target = [PSCustomObject]@{ statusLine = [PSCustomObject]@{ type = "old" } }
        $source = [PSCustomObject]@{ statusLine = [PSCustomObject]@{ type = "command"; command = "bash test" } }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @('statusLine')
        $result | Should -BeTrue
        $target.statusLine.type | Should -Be "command"
        $target.statusLine.command | Should -Be "bash test"
    }

    It "Recurses into nested objects" {
        $target = [PSCustomObject]@{
            preferences = [PSCustomObject]@{ language = "vi" }
        }
        $source = [PSCustomObject]@{
            preferences = [PSCustomObject]@{ language = "en"; newPref = "value" }
        }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @()
        $result | Should -BeTrue
        $target.preferences.language | Should -Be "vi"  # user wins
        $target.preferences.newPref | Should -Be "value"  # new key added
    }

    It "Returns `$false when no changes needed" {
        $target = [PSCustomObject]@{ a = "1"; b = "2" }
        $source = [PSCustomObject]@{ a = "1"; b = "2" }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @()
        $result | Should -BeFalse
    }

    It "Handles null Source values gracefully" {
        $target = [PSCustomObject]@{ a = "1" }
        $source = [PSCustomObject]@{ b = $null }
        $result = Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @()
        $result | Should -BeTrue
        $target.b | Should -BeNullOrEmpty
    }
}

Describe "Remove-ClaudeSecrets" {
    It "Strips github_pat_ tokens from mcpServers env" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                github = [PSCustomObject]@{
                    command = "npx"
                    env = [PSCustomObject]@{
                        GITHUB_PERSONAL_ACCESS_TOKEN = "github_pat_11ABCDEF0123456789"
                    }
                }
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be "<REDACTED>"
        # Original should NOT be mutated
        $json.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be "github_pat_11ABCDEF0123456789"
    }

    It "Strips ghp_ tokens" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                test = [PSCustomObject]@{
                    env = [PSCustomObject]@{
                        TOKEN = "ghp_abc123def456"
                    }
                }
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.mcpServers.test.env.TOKEN | Should -Be "<REDACTED>"
    }

    It "Strips sk- API keys" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                openai = [PSCustomObject]@{
                    env = [PSCustomObject]@{
                        OPENAI_API_KEY = "sk-abc123def456ghi789"
                    }
                }
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.mcpServers.openai.env.OPENAI_API_KEY | Should -Be "<REDACTED>"
    }

    It "Preserves non-secret values" {
        $json = [PSCustomObject]@{
            statusLine = [PSCustomObject]@{ type = "command"; command = "bash test.sh" }
            preferences = [PSCustomObject]@{ language = "vi" }
            mcpServers = [PSCustomObject]@{
                local = [PSCustomObject]@{
                    command = "npx"
                    env = [PSCustomObject]@{
                        DEBUG = "true"
                    }
                }
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.statusLine.command | Should -Be "bash test.sh"
        $sanitized.preferences.language | Should -Be "vi"
        $sanitized.mcpServers.local.env.DEBUG | Should -Be "true"
    }

    It "Strips secrets inside arrays" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                test = [PSCustomObject]@{
                    args = @("-flag", "github_pat_11ABCDEF0123456789")
                }
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.mcpServers.test.args[1] | Should -Be "<REDACTED>"
        $sanitized.mcpServers.test.args[0] | Should -Be "-flag"
    }

    It "Redacts keyword-matched keys outside mcpServers" {
        $json = [PSCustomObject]@{
            someSection = [PSCustomObject]@{
                api_token = "my-very-long-secret-value-here"
            }
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.someSection.api_token | Should -Be "<REDACTED>"
    }

    It "Does not false-positive on short sk- strings" {
        $json = [PSCustomObject]@{
            region = "sk-east-1"
        }
        $sanitized = Remove-ClaudeSecrets -Json $json
        $sanitized.region | Should -Be "sk-east-1"
    }

    It "Does not mutate the input object" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                gh = [PSCustomObject]@{
                    env = [PSCustomObject]@{ TOKEN = "github_pat_ABCDEF" }
                }
            }
        }
        $original = $json.mcpServers.gh.env.TOKEN
        Remove-ClaudeSecrets -Json $json | Out-Null
        $json.mcpServers.gh.env.TOKEN | Should -Be $original
    }
}

Describe "Test-ClaudeSecrets" {
    It "Detects github_pat_ tokens" {
        $json = [PSCustomObject]@{
            mcpServers = [PSCustomObject]@{
                gh = [PSCustomObject]@{
                    env = [PSCustomObject]@{
                        GITHUB_PERSONAL_ACCESS_TOKEN = "github_pat_11ABC"
                    }
                }
            }
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -BeGreaterThan 0
        $result | Should -Contain "mcpServers.gh.env.GITHUB_PERSONAL_ACCESS_TOKEN"
    }

    It "Detects ghp_ tokens" {
        $json = [PSCustomObject]@{
            someKey = "ghp_abc123"
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -BeGreaterThan 0
    }

    It "Returns empty array for clean settings" {
        $json = [PSCustomObject]@{
            statusLine = [PSCustomObject]@{ type = "command" }
            preferences = [PSCustomObject]@{ language = "vi" }
            mcpServers = [PSCustomObject]@{}
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -Be 0
    }

    It "Detects sk- API keys" {
        $json = [PSCustomObject]@{
            nested = [PSCustomObject]@{
                apiKey = "sk-ant-api03-XXXXX"
            }
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -BeGreaterThan 0
    }

    It "Detects secrets inside arrays" {
        $json = [PSCustomObject]@{
            config = [PSCustomObject]@{
                args = @("normal", "github_pat_11ABCDEF")
            }
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -BeGreaterThan 0
        $result | Should -Contain "config.args[1]"
    }

    It "Does not false-positive on short sk- strings" {
        $json = [PSCustomObject]@{
            region = "sk-east-1"
        }
        $result = Test-ClaudeSecrets -Json $json
        $result.Count | Should -Be 0
    }
}

Describe "Deploy Integration" {
    BeforeAll {
        $script:TestClaudeDir = Join-Path $TestDrive ".claude"
        New-Item -ItemType Directory -Path $script:TestClaudeDir -Force | Out-Null
    }

    It "Merge-JsonAdditive preserves existing plugins and adds new ones" {
        $existing = [PSCustomObject]@{
            enabledPlugins = [PSCustomObject]@{
                "my-plugin@custom" = $true
            }
        }
        $template = [PSCustomObject]@{
            enabledPlugins = [PSCustomObject]@{
                "commit-commands@claude-plugins-official" = $true
                "context7@claude-plugins-official" = $true
            }
        }
        Merge-JsonAdditive -Target $existing -Source $template -ProtectedKeys @() -OverwriteKeys @() | Out-Null
        $existing.enabledPlugins."my-plugin@custom" | Should -BeTrue
        $existing.enabledPlugins."commit-commands@claude-plugins-official" | Should -BeTrue
        $existing.enabledPlugins."context7@claude-plugins-official" | Should -BeTrue
    }

    It "Full merge scenario: user settings + template = correct merge" {
        $userSettings = [PSCustomObject]@{
            statusLine = [PSCustomObject]@{ type = "old" }
            enabledPlugins = [PSCustomObject]@{ "user-plugin@custom" = $true }
            preferences = [PSCustomObject]@{ language = "vi"; custom_pref = "keep" }
            mcpServers = [PSCustomObject]@{
                github = [PSCustomObject]@{
                    env = [PSCustomObject]@{ TOKEN = "github_pat_SECRET" }
                }
            }
        }
        $template = [PSCustomObject]@{
            statusLine = [PSCustomObject]@{ type = "command"; command = "bash ~/.claude/statusline.sh" }
            enabledPlugins = [PSCustomObject]@{ "core-plugin@official" = $true }
            preferences = [PSCustomObject]@{ language = "en" }
            mcpServers = [PSCustomObject]@{}
        }
        Merge-JsonAdditive -Target $userSettings -Source $template | Out-Null

        # statusLine overwritten (in OverwriteKeys by default)
        $userSettings.statusLine.command | Should -Be "bash ~/.claude/statusline.sh"
        # mcpServers protected (in ProtectedKeys by default)
        $userSettings.mcpServers.github.env.TOKEN | Should -Be "github_pat_SECRET"
        # user plugin preserved, core plugin added
        $userSettings.enabledPlugins."user-plugin@custom" | Should -BeTrue
        $userSettings.enabledPlugins."core-plugin@official" | Should -BeTrue
        # user preference kept (user wins)
        $userSettings.preferences.language | Should -Be "vi"
        $userSettings.preferences.custom_pref | Should -Be "keep"
    }

    It "Idempotent: running merge twice produces same result" {
        $target = [PSCustomObject]@{ a = "1" }
        $source = [PSCustomObject]@{ a = "1"; b = "2" }
        Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @() | Out-Null
        $first = $target | ConvertTo-Json -Depth 10
        Merge-JsonAdditive -Target $target -Source $source -ProtectedKeys @() -OverwriteKeys @() | Out-Null
        $second = $target | ConvertTo-Json -Depth 10
        $first | Should -Be $second
    }

    It "Deploy creates settings.json from template when none exists" {
        $settingsPath = Join-Path $script:TestClaudeDir "settings-new.json"
        $templatePath = Join-Path $RepoRoot "configs\claude-settings.template.json"
        Test-Path $settingsPath | Should -BeFalse
        Copy-Item $templatePath $settingsPath
        Test-Path $settingsPath | Should -BeTrue
        $content = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $content.statusLine.type | Should -Be "command"
        $content.preferences.language | Should -Be "vi"
    }

    It "Statusline template uses portable path" {
        $template = Get-Content (Join-Path $RepoRoot "configs\claude-settings.template.json") -Raw | ConvertFrom-Json
        $template.statusLine.command | Should -Be "bash ~/.claude/statusline.sh"
    }
}
