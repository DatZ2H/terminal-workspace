#Requires -Modules Pester
# Tests for scripts/common.ps1

BeforeAll {
    . "$PSScriptRoot\..\scripts\common.ps1"
}

Describe "Get-WtSettingsPath" {
    It "Returns `$null when LOCALAPPDATA not set" {
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $null
            Get-WtSettingsPath | Should -BeNullOrEmpty
        } finally {
            $env:LOCALAPPDATA = $saved
        }
    }

    It "Returns path when Store WT settings exist" {
        $storePath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path $storePath) {
            Get-WtSettingsPath -Mode file | Should -Be $storePath
        } else {
            Set-ItResult -Skipped -Because "Store WT not installed"
        }
    }

    It "Returns path when non-Store WT settings exist" {
        $nonStorePath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json"
        if (Test-Path $nonStorePath) {
            $result = Get-WtSettingsPath -Mode file
            # May return Store path first if both exist
            $result | Should -Not -BeNullOrEmpty
        } else {
            Set-ItResult -Skipped -Because "Non-Store WT not installed"
        }
    }

    It "Mode 'deploy' returns path if parent dir exists even without file" {
        $result = Get-WtSettingsPath -Mode deploy
        if ($result) {
            # Parent directory should exist
            Test-Path (Split-Path $result -Parent) | Should -BeTrue
        } else {
            Set-ItResult -Skipped -Because "No WT installation found"
        }
    }
}

Describe "Get-NerdFontInfo" {
    It "Returns an object with expected properties" {
        $info = Get-NerdFontInfo
        $info | Should -Not -BeNullOrEmpty
        $info.PSObject.Properties.Name | Should -Contain 'Installed'
        $info.PSObject.Properties.Name | Should -Contain 'HasV3'
        $info.PSObject.Properties.Name | Should -Contain 'HasV2'
        $info.PSObject.Properties.Name | Should -Contain 'FontFace'
    }

    It "FontFace is null when not installed, or correct value when installed" {
        $info = Get-NerdFontInfo
        if ($info.Installed) {
            $info.FontFace | Should -Match 'CaskaydiaCove'
        } else {
            $info.FontFace | Should -BeNullOrEmpty
        }
    }

    It "Prefers v3 over v2 naming" {
        $info = Get-NerdFontInfo
        if ($info.HasV3 -and $info.HasV2) {
            $info.FontFace | Should -Be 'CaskaydiaCove NF'
        } else {
            Set-ItResult -Skipped -Because "Both v2 and v3 not installed"
        }
    }
}

Describe "Get-PnxCachedInit / Save-PnxCachedInit / Clear-PnxCache" {
    BeforeAll {
        # Use a temp cache dir for isolation
        $script:OrigCacheDir = $PnxCacheDir
        $script:PnxCacheDir = Join-Path $TestDrive "cache"
        # Re-bind module-scope variable
        Set-Variable -Name PnxCacheDir -Value $script:PnxCacheDir -Scope Script
    }

    AfterAll {
        Set-Variable -Name PnxCacheDir -Value $script:OrigCacheDir -Scope Script
    }

    It "Returns `$null when cache doesn't exist" {
        $result = Get-PnxCachedInit -Name 'test' -VersionKey 'v1' -ExtraKey 'e1'
        $result | Should -BeNullOrEmpty
    }

    It "Returns content when cache matches key" {
        Save-PnxCachedInit -Name 'test' -VersionKey 'v1' -ExtraKey 'e1' -Content 'Write-Host "hello"'
        $result = Get-PnxCachedInit -Name 'test' -VersionKey 'v1' -ExtraKey 'e1'
        $result.TrimEnd() | Should -Be 'Write-Host "hello"'
    }

    It "Returns `$null when cache key mismatches (version changed)" {
        Save-PnxCachedInit -Name 'test2' -VersionKey 'v1' -ExtraKey 'e1' -Content 'cached'
        $result = Get-PnxCachedInit -Name 'test2' -VersionKey 'v2' -ExtraKey 'e1'
        $result | Should -BeNullOrEmpty
    }

    It "Clear-PnxCache removes all cache files" {
        Save-PnxCachedInit -Name 'clear-test' -VersionKey 'v1' -ExtraKey '' -Content 'data'
        Clear-PnxCache
        Get-PnxCachedInit -Name 'clear-test' -VersionKey 'v1' -ExtraKey '' | Should -BeNullOrEmpty
    }
}

Describe "Initialize-WtPnxMarkers" {
    It "Adds pnxTheme when missing" {
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{}
            }
        }
        $result = Initialize-WtPnxMarkers -WtJson $json
        $result | Should -BeTrue
        $json.profiles.defaults.pnxTheme | Should -Be 'pro'
    }

    It "Adds pnxStyle when missing" {
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{}
            }
        }
        Initialize-WtPnxMarkers -WtJson $json | Out-Null
        $json.profiles.defaults.pnxStyle | Should -Be 'mac'
    }

    It "Does not overwrite existing markers" {
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    pnxTheme = 'tokyo'
                    pnxStyle = 'linux'
                }
            }
        }
        $result = Initialize-WtPnxMarkers -WtJson $json
        $result | Should -BeFalse
        $json.profiles.defaults.pnxTheme | Should -Be 'tokyo'
        $json.profiles.defaults.pnxStyle | Should -Be 'linux'
    }

    It "Creates profiles.defaults when missing" {
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{}
        }
        Initialize-WtPnxMarkers -WtJson $json | Out-Null
        $json.profiles.defaults | Should -Not -BeNullOrEmpty
        $json.profiles.defaults.pnxTheme | Should -Be 'pro'
    }

    It "Returns `$true when changes made, `$false otherwise" {
        $json1 = [PSCustomObject]@{
            profiles = [PSCustomObject]@{ defaults = [PSCustomObject]@{} }
        }
        Initialize-WtPnxMarkers -WtJson $json1 | Should -BeTrue

        $json2 = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{ pnxTheme = 'pro'; pnxStyle = 'mac' }
            }
        }
        Initialize-WtPnxMarkers -WtJson $json2 | Should -BeFalse
    }

    It "Accepts custom default theme and style" {
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{ defaults = [PSCustomObject]@{} }
        }
        Initialize-WtPnxMarkers -WtJson $json -DefaultTheme 'tokyo' -DefaultStyle 'linux' | Out-Null
        $json.profiles.defaults.pnxTheme | Should -Be 'tokyo'
        $json.profiles.defaults.pnxStyle | Should -Be 'linux'
    }
}

Describe "Repair-WtFontFace" {
    It "Returns `$false when WtPath is null" {
        Repair-WtFontFace -WtPath $null | Should -BeFalse
    }

    It "Returns `$false when WtPath does not exist" {
        Repair-WtFontFace -WtPath (Join-Path $TestDrive "nonexistent.json") | Should -BeFalse
    }

    It "Returns `$false when font already correct" {
        $fi = Get-NerdFontInfo
        if (-not $fi.FontFace) {
            Set-ItResult -Skipped -Because "No Nerd Font installed"
            return
        }

        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    font = [PSCustomObject]@{ face = $fi.FontFace }
                }
            }
        }
        $wtPath = Join-Path $TestDrive "settings.json"
        $json | ConvertTo-Json -Depth 10 | Set-Content $wtPath -Encoding utf8NoBOM

        Repair-WtFontFace -WtPath $wtPath -WtJson $json -FontInfo $fi | Should -BeFalse
    }

    It "Uses pre-parsed WtJson when provided" {
        $fi = Get-NerdFontInfo
        if (-not $fi.FontFace) {
            Set-ItResult -Skipped -Because "No Nerd Font installed"
            return
        }

        $staleName = if ($fi.HasV3) { 'CaskaydiaCove Nerd Font' } else { 'CaskaydiaCove NF' }
        $json = [PSCustomObject]@{
            profiles = [PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    font = [PSCustomObject]@{ face = $staleName }
                }
            }
        }
        $wtPath = Join-Path $TestDrive "settings-preparse.json"
        $json | ConvertTo-Json -Depth 10 | Set-Content $wtPath -Encoding utf8NoBOM

        $result = Repair-WtFontFace -WtPath $wtPath -WtJson $json -FontInfo $fi
        $result | Should -BeTrue
    }
}

Describe "Save-WtSettings" {
    It "Writes JSON to file and returns `$true" {
        $wtPath = Join-Path $TestDrive "wt-save-test.json"
        '{}' | Set-Content $wtPath -Encoding utf8NoBOM
        $json = [PSCustomObject]@{ test = "value" }

        $result = Save-WtSettings -Json $json -WtPath $wtPath
        $result | Should -BeTrue
        $content = Get-Content $wtPath -Raw | ConvertFrom-Json
        $content.test | Should -Be "value"
    }

    It "Creates backup file" {
        $wtPath = Join-Path $TestDrive "wt-backup-test.json"
        '{"original": true}' | Set-Content $wtPath -Encoding utf8NoBOM
        $json = [PSCustomObject]@{ updated = $true }

        Save-WtSettings -Json $json -WtPath $wtPath | Out-Null
        Test-Path "$wtPath.pnx-backup" | Should -BeTrue
    }
}
