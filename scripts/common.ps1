# Shared constants and helpers -- single source of truth
# Dot-source this from any script that needs WT path or version constants.

# -- Version Constants --
$PythonVersion = "3.12"

# -- Shared Path Constants --
$MaxBackups      = 3
$OmpThemesLocal  = Join-Path $env:USERPROFILE ".oh-my-posh\themes"
$PsProfileDir    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell"
$PsProfilePath   = Join-Path $PsProfileDir "Microsoft.PowerShell_profile.ps1"

# -- WT Settings Path Detection (Store + non-Store) --
# Two modes:
#   "file"   -- returns path only if the file exists (for reading/reporting)
#   "deploy" -- returns path if the parent dir exists (for writing -- file may not exist yet)
function Get-WtSettingsPath {
    [CmdletBinding()]
    param(
        [ValidateSet('file', 'deploy')]
        [string]$Mode = 'file'
    )
    if (-not $env:LOCALAPPDATA) { return $null }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
    )
    if ($Mode -eq 'deploy') {
        $candidates | Where-Object { Test-Path (Split-Path $_ -Parent) } | Select-Object -First 1
    } else {
        $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}

# -- Nerd Font Detection --
# Returns object: Installed, HasV3, HasV2, FontFace
function Get-NerdFontInfo {
    [CmdletBinding()]
    param()
    $entries = @()
    foreach ($hive in @('HKCU', 'HKLM')) {
        $reg = Get-ItemProperty "${hive}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
        if ($reg) { $entries += $reg.PSObject.Properties.Name | Where-Object { $_ -match 'CaskaydiaCove' } }
    }
    $hasV3 = [bool]($entries -match 'CaskaydiaCove NF ')
    $hasV2 = [bool]($entries -match 'CaskaydiaCove Nerd Font')
    [PSCustomObject]@{
        Installed = $hasV3 -or $hasV2
        HasV3     = $hasV3
        HasV2     = $hasV2
        FontFace  = if ($hasV3) { 'CaskaydiaCove NF' } elseif ($hasV2) { 'CaskaydiaCove Nerd Font' } else { $null }
    }
}

# -- WT Font Face Repair --
# Fixes stale font name in WT settings.json (v2 <-> v3) via JSON parse. Returns $true if changed.
# Optional -WtJson and -FontInfo params accept pre-parsed data to avoid redundant I/O.
function Repair-WtFontFace {
    [CmdletBinding()]
    param(
        [string]$WtPath,
        [object]$WtJson,
        [object]$FontInfo
    )
    if (-not $WtPath -or -not (Test-Path $WtPath)) { return $false }
    $fi = if ($FontInfo) { $FontInfo } else { Get-NerdFontInfo }
    if (-not $fi.FontFace) { return $false }
    try {
        $json = if ($WtJson) { $WtJson } else { Get-Content $WtPath -Raw | ConvertFrom-Json }
    } catch { return $false }
    $d = $json.profiles.defaults
    if (-not $d -or -not $d.font -or -not $d.font.face) { return $false }
    if ($d.font.face -eq $fi.FontFace) { return $false }
    $d.font.face = $fi.FontFace
    if (-not (Save-WtSettings -Json $json -WtPath $WtPath)) {
        Write-Warning "Repair-WtFontFace: atomic write failed (WT may be locking file)."
        return $false
    }
    return $true
}

# -- Atomic WT Settings Writer --
# Backup + temp file + .NET File.Move (true atomic replace) + fallback
# Uses [IO.File]::Move(src, dst, overwrite:$true) which calls MoveFileEx
# with MOVEFILE_REPLACE_EXISTING — no delete gap for WT file watcher to see.
# Returns $true on success, $false on failure
function Save-WtSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Json,
        [Parameter(Mandatory)][string]$WtPath
    )
    # Backup
    Copy-Item $WtPath "$WtPath.pnx-backup" -Force -ErrorAction SilentlyContinue
    # Write to temp file first (safe — WT doesn't watch this path)
    $tempPath = "$WtPath.pnx-tmp"
    $Json | ConvertTo-Json -Depth 20 | Set-Content $tempPath -Encoding utf8NoBOM
    # Atomic replace via .NET (true atomic on NTFS — no delete+rename gap)
    # Retry with exponential backoff: 200, 400, 800, 1600, 3200ms (total ~6s)
    for ($retry = 0; $retry -lt 5; $retry++) {
        try {
            [System.IO.File]::Move($tempPath, $WtPath, $true)
            return $true
        } catch { Start-Sleep -Milliseconds (200 * [math]::Pow(2, $retry)) }
    }
    # All atomic retries failed — do NOT fall back to non-atomic Set-Content
    # because WT file watcher may read a partial write and show a parse error.
    # Instead, clean up temp file and report failure so caller can decide.
    Write-Warning "Save-WtSettings: atomic write failed after 5 retries (WT may be locking the file)."
    # Temp file is still valid JSON — leave it for manual recovery
    return $false
}

# -- Init Cache Infrastructure --
# Caches output of slow external processes (oh-my-posh init, zoxide init) to disk.
# Cache is invalidated when the executable or config changes (via VersionKey|ExtraKey).
$PnxCacheDir = Join-Path $env:LOCALAPPDATA "pnx-terminal\cache"

function Get-PnxCachedInit {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$VersionKey,
        [string]$ExtraKey
    )
    $cacheFile = Join-Path $PnxCacheDir "$Name.ps1"
    $metaFile  = Join-Path $PnxCacheDir "$Name.meta"
    if (-not (Test-Path $cacheFile) -or -not (Test-Path $metaFile)) { return $null }
    $expected = "$VersionKey|$ExtraKey"
    $stored = Get-Content $metaFile -Raw -ErrorAction SilentlyContinue
    if ($stored -and $stored.Trim() -eq $expected) {
        return (Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue)
    }
    return $null
}

function Save-PnxCachedInit {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$VersionKey,
        [string]$ExtraKey,
        [string]$Content
    )
    if (-not (Test-Path $PnxCacheDir)) {
        New-Item -ItemType Directory -Path $PnxCacheDir -Force | Out-Null
    }
    $Content | Set-Content (Join-Path $PnxCacheDir "$Name.ps1") -Encoding utf8NoBOM
    "$VersionKey|$ExtraKey" | Set-Content (Join-Path $PnxCacheDir "$Name.meta") -Encoding utf8NoBOM
}

function Clear-PnxCache {
    [CmdletBinding()]
    param()
    if (Test-Path $PnxCacheDir) {
        Remove-Item "$PnxCacheDir\*" -Force -ErrorAction SilentlyContinue
    }
}

# -- Manifest Defaults (lazy loaded, used by Initialize-WtPnxMarkers) --
$script:_pnxDefaults = @{ theme = 'pro'; style = 'mac' }  # fallback
$_manifestPath = if ($PSScriptRoot) {
    Join-Path (Split-Path $PSScriptRoot -Parent) "configs\themes.json"
} else { $null }
if ($_manifestPath -and (Test-Path $_manifestPath)) {
    try {
        $m = Get-Content $_manifestPath -Raw | ConvertFrom-Json
        if ($m.defaultTheme) { $script:_pnxDefaults.theme = $m.defaultTheme }
        if ($m.defaultStyle) { $script:_pnxDefaults.style = $m.defaultStyle }
        Remove-Variable m -ErrorAction SilentlyContinue
    } catch {}
}
Remove-Variable _manifestPath -ErrorAction SilentlyContinue

# -- Deduplicated pnx marker injection (used by bootstrap + sync-from-repo) --
# Ensures pnxTheme/pnxStyle markers exist in WT settings and fixes font face.
# Returns $true if any changes were made (caller should write JSON back to disk).
function Initialize-WtPnxMarkers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$WtJson,
        [string]$DefaultTheme = $(if ($script:_pnxDefaults) { $script:_pnxDefaults.theme } else { 'pro' }),
        [string]$DefaultStyle = $(if ($script:_pnxDefaults) { $script:_pnxDefaults.style } else { 'mac' })
    )
    $changed = $false
    if (-not $WtJson.profiles.defaults) {
        $WtJson.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $d = $WtJson.profiles.defaults
    if (-not $d.PSObject.Properties['pnxTheme']) {
        $d | Add-Member -NotePropertyName pnxTheme -NotePropertyValue $DefaultTheme
        $changed = $true
    }
    if (-not $d.PSObject.Properties['pnxStyle']) {
        $d | Add-Member -NotePropertyName pnxStyle -NotePropertyValue $DefaultStyle
        $changed = $true
    }
    if (-not $d.PSObject.Properties['pnxSplit']) {
        $d | Add-Member -NotePropertyName pnxSplit -NotePropertyValue $false
        $changed = $true
    }
    # Fix font face if needed
    if ($d.font -and $d.font.face) {
        $fi = Get-NerdFontInfo
        if ($fi.FontFace -and $d.font.face -ne $fi.FontFace) {
            $d.font.face = $fi.FontFace
            $changed = $true
        }
    }
    return $changed
}

# -- Claude Code Config Path Detection --
# Returns path to Claude Code config files, or $null if ~/.claude/ doesn't exist
function Get-ClaudeConfigPath {
    [CmdletBinding()]
    param(
        [ValidateSet('settings', 'claude.md', 'statusline')]
        [string]$Type = 'settings'
    )
    $claudeDir = Join-Path $env:USERPROFILE ".claude"
    if (-not (Test-Path $claudeDir)) { return $null }
    switch ($Type) {
        'settings'   { Join-Path $claudeDir "settings.json" }
        'claude.md'  { Join-Path $claudeDir "CLAUDE.md" }
        'statusline' { Join-Path $claudeDir "statusline.sh" }
    }
}

# -- Additive JSON Merge --
# Merges Source into Target (PSCustomObject) with protection rules.
# Modifies Target in-place, returns $true if any changes were made.
function Merge-JsonAdditive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Source,
        [string[]]$ProtectedKeys = @('mcpServers'),
        [string[]]$OverwriteKeys = @('statusLine')
    )
    $changed = $false
    foreach ($prop in $Source.PSObject.Properties) {
        $key = $prop.Name
        # Protected: never touch
        if ($key -in $ProtectedKeys) { continue }
        # Overwrite: always take from Source
        if ($key -in $OverwriteKeys) {
            if (-not $Target.PSObject.Properties[$key]) {
                $Target | Add-Member -NotePropertyName $key -NotePropertyValue $prop.Value
                $changed = $true
            } elseif (($Target.$key | ConvertTo-Json -Depth 10 -Compress) -ne ($prop.Value | ConvertTo-Json -Depth 10 -Compress)) {
                $Target.$key = $prop.Value
                $changed = $true
            }
            continue
        }
        # Key not in Target: add from Source
        if (-not $Target.PSObject.Properties[$key]) {
            $Target | Add-Member -NotePropertyName $key -NotePropertyValue $prop.Value
            $changed = $true
            continue
        }
        # Both are objects: recurse (no protected/overwrite propagation)
        $tVal = $Target.$key
        $sVal = $prop.Value
        if ($tVal -is [PSCustomObject] -and $sVal -is [PSCustomObject]) {
            if (Merge-JsonAdditive -Target $tVal -Source $sVal -ProtectedKeys @() -OverwriteKeys @()) {
                $changed = $true
            }
            continue
        }
        # Key exists in Target: user wins (keep existing)
    }
    return $changed
}

# -- Secret Detection Patterns --
$script:_SecretPatterns = @(
    'github_pat_[A-Za-z0-9_]+'
    'ghp_[A-Za-z0-9]+'
    'sk-ant-[A-Za-z0-9]+'
    'sk-[A-Za-z0-9]{20,}'
    'xoxb-[A-Za-z0-9\-]+'
    'xoxp-[A-Za-z0-9\-]+'
)
$script:_SecretKeywords = @('token', 'key', 'secret', 'password', 'credential', 'pat')

# -- Remove Secrets from Claude Settings JSON --
# Returns a sanitized deep copy. Does NOT mutate input.
function Remove-ClaudeSecrets {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Json)
    # Deep clone via JSON round-trip
    $clone = $Json | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    # Strip all env values in mcpServers
    if ($clone.PSObject.Properties['mcpServers'] -and $clone.mcpServers -is [PSCustomObject]) {
        foreach ($server in $clone.mcpServers.PSObject.Properties) {
            $srv = $server.Value
            if ($srv.PSObject.Properties['env'] -and $srv.env -is [PSCustomObject]) {
                foreach ($envProp in $srv.env.PSObject.Properties) {
                    $val = $envProp.Value
                    if ($val -is [string] -and $val.Length -gt 0) {
                        $isSecret = $false
                        foreach ($pattern in $script:_SecretPatterns) {
                            if ($val -match $pattern) { $isSecret = $true; break }
                        }
                        if (-not $isSecret) {
                            $keyLower = $envProp.Name.ToLower()
                            foreach ($kw in $script:_SecretKeywords) {
                                if ($keyLower -match $kw) { $isSecret = $true; break }
                            }
                        }
                        if ($isSecret) { $srv.env.($envProp.Name) = "<REDACTED>" }
                    }
                }
            }
        }
    }
    # Scan all string values for secret patterns + keywords (outside mcpServers too)
    function _RedactStrings([object]$Obj, [string]$Path) {
        if ($Obj -is [PSCustomObject]) {
            foreach ($p in $Obj.PSObject.Properties) {
                if ($p.Value -is [string] -and $p.Value.Length -gt 0) {
                    $isSecret = $false
                    foreach ($pattern in $script:_SecretPatterns) {
                        if ($p.Value -match $pattern) { $isSecret = $true; break }
                    }
                    if (-not $isSecret) {
                        $keyLower = $p.Name.ToLower()
                        foreach ($kw in $script:_SecretKeywords) {
                            if ($keyLower -match $kw -and $p.Value -ne '<REDACTED>' -and $p.Value.Length -gt 8) {
                                $isSecret = $true; break
                            }
                        }
                    }
                    if ($isSecret) { $Obj.($p.Name) = "<REDACTED>" }
                } elseif ($p.Value -is [PSCustomObject]) {
                    _RedactStrings $p.Value "$Path.$($p.Name)"
                } elseif ($p.Value -is [array]) {
                    for ($i = 0; $i -lt $p.Value.Count; $i++) {
                        $item = $p.Value[$i]
                        if ($item -is [string]) {
                            foreach ($pattern in $script:_SecretPatterns) {
                                if ($item -match $pattern) { $p.Value[$i] = "<REDACTED>"; break }
                            }
                        } elseif ($item -is [PSCustomObject]) {
                            _RedactStrings $item "$Path.$($p.Name)[$i]"
                        }
                    }
                }
            }
        }
    }
    _RedactStrings $clone ""
    return $clone
}

# -- Test for Secrets in JSON --
# Returns array of paths containing secrets (empty = safe)
function Test-ClaudeSecrets {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Json)
    $found = [System.Collections.Generic.List[string]]::new()
    function _ScanObject([object]$Obj, [string]$Path) {
        if ($Obj -is [PSCustomObject]) {
            foreach ($p in $Obj.PSObject.Properties) {
                $currentPath = if ($Path) { "$Path.$($p.Name)" } else { $p.Name }
                if ($p.Value -is [string] -and $p.Value.Length -gt 0) {
                    foreach ($pattern in $script:_SecretPatterns) {
                        if ($p.Value -match $pattern) {
                            $found.Add($currentPath)
                            break
                        }
                    }
                    if ($currentPath -notin $found) {
                        $keyLower = $p.Name.ToLower()
                        foreach ($kw in $script:_SecretKeywords) {
                            if ($keyLower -match $kw -and $p.Value -ne '<REDACTED>' -and $p.Value.Length -gt 8) {
                                $found.Add($currentPath)
                                break
                            }
                        }
                    }
                } elseif ($p.Value -is [PSCustomObject]) {
                    _ScanObject $p.Value $currentPath
                } elseif ($p.Value -is [array]) {
                    for ($i = 0; $i -lt $p.Value.Count; $i++) {
                        $item = $p.Value[$i]
                        if ($item -is [string] -and $item.Length -gt 0) {
                            foreach ($pattern in $script:_SecretPatterns) {
                                if ($item -match $pattern) { $found.Add("$currentPath[$i]"); break }
                            }
                        } elseif ($item -is [PSCustomObject]) {
                            _ScanObject $item "$currentPath[$i]"
                        }
                    }
                }
            }
        }
    }
    _ScanObject $Json ""
    return @($found)
}
