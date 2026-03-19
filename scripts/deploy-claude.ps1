#Requires -Version 7.0
# Deploy Claude Code configs (statusline, settings, CLAUDE.md, Vietnamese IME fix)
# Safe: additive merge for settings.json, never overwrites user secrets/plugins

param([switch]$Force)

$RepoRoot = Split-Path $PSScriptRoot -Parent

. "$PSScriptRoot\common.ps1"

function Write-Ok($msg)   { Write-Host "   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   $msg" -ForegroundColor Yellow }

# 1. Check Claude Code installed
$claudeDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $claudeDir)) {
    if ($Force) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
        Write-Ok "Created ~/.claude/"
    } else {
        Write-Skip "~/.claude/ not found (Claude Code not installed?) -- skipping"
        return
    }
}

# 2. Deploy statusline.sh (always overwrite -- repo is source of truth)
$statuslineSrc = Join-Path $RepoRoot "configs\statusline.sh"
if (Test-Path $statuslineSrc) {
    Copy-Item $statuslineSrc (Join-Path $claudeDir "statusline.sh") -Force
    Write-Ok "statusline.sh deployed"
} else {
    Write-Skip "configs/statusline.sh not in repo -- skipped"
}

# 3. Merge settings.json (additive-only)
$settingsPath = Join-Path $claudeDir "settings.json"
$templatePath = Join-Path $RepoRoot "configs\claude-settings.template.json"
if (Test-Path $templatePath) {
    if (Test-Path $settingsPath) {
        try {
            $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $template = Get-Content $templatePath -Raw | ConvertFrom-Json
            $changed = Merge-JsonAdditive -Target $existing -Source $template
            if ($changed) {
                $existing | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8NoBOM
                Write-Ok "settings.json merged (additive)"
            } else {
                Write-Ok "settings.json up to date"
            }
        } catch {
            Write-Skip "settings.json merge failed: $_ -- skipped to protect existing config"
        }
    } else {
        Copy-Item $templatePath $settingsPath
        Write-Ok "settings.json created from template"
    }
} else {
    Write-Skip "configs/claude-settings.template.json not in repo -- skipped"
}

# 4. Deploy CLAUDE.md (only if missing, unless -Force)
$claudeMdPath = Join-Path $claudeDir "CLAUDE.md"
$claudeMdSrc = Join-Path $RepoRoot "configs\claude.md"
if (Test-Path $claudeMdSrc) {
    if (-not (Test-Path $claudeMdPath) -or $Force) {
        Copy-Item $claudeMdSrc $claudeMdPath -Force
        Write-Ok "CLAUDE.md deployed"
    } else {
        Write-Skip "CLAUDE.md already exists (use -Force to overwrite)"
    }
} else {
    Write-Skip "configs/claude.md not in repo -- skipped"
}

# 5. Vietnamese IME fix (existing script)
$fixScript = Join-Path $RepoRoot "scripts\fix-claude-vn.ps1"
if (Test-Path $fixScript) {
    try {
        & $fixScript
    } catch {
        Write-Skip "Vietnamese IME fix skipped: $_"
    }
}
