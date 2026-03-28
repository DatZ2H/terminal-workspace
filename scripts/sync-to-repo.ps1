#Requires -Version 7.0
# Copy config files from local system to this repo

param([switch]$Force)

$RepoRoot = Split-Path $PSScriptRoot -Parent

. "$PSScriptRoot\common.ps1"

$PsProfileLocal = $PsProfilePath
$WtSettingsLocal = Get-WtSettingsPath -Mode file

Write-Host "`n  Syncing: local -> repo" -ForegroundColor Cyan
Write-Host "  ════════════════════════════════" -ForegroundColor DarkGray

if (-not $Force) {
    Write-Host ""
    Write-Host "  This will overwrite repo files with your local configs." -ForegroundColor Yellow
    Write-Host "  Changes can be reverted via:  cd $RepoRoot && git checkout ." -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  Proceed? (y/N)"
    if ($confirm -notin @('y', 'Y', 'yes')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }
}

# Profile
if (Test-Path $PsProfileLocal) {
    Copy-Item $PsProfileLocal "$RepoRoot\configs\profile.ps1" -Force
    Write-Host "  Profile          OK" -ForegroundColor Green
} else {
    Write-Host "  Profile          NOT FOUND: $PsProfileLocal" -ForegroundColor Red
}

# WT Settings (sanitize machine-specific data before copying to repo)
if ($WtSettingsLocal) {
    try {
        $wtJson = Get-Content $WtSettingsLocal -Raw | ConvertFrom-Json
        # Strip environment variables from all profiles (may contain secrets)
        foreach ($p in $wtJson.profiles.list) {
            if ($p.PSObject.Properties['environment']) {
                $p.PSObject.Properties.Remove('environment')
            }
        }
        # Strip pnx markers from defaults (local state, not portable)
        if ($wtJson.profiles.defaults) {
            foreach ($marker in @('pnxTheme', 'pnxStyle', 'pnxSplit')) {
                if ($wtJson.profiles.defaults.PSObject.Properties[$marker]) {
                    $wtJson.profiles.defaults.PSObject.Properties.Remove($marker)
                }
            }
        }
        $wtJson | ConvertTo-Json -Depth 20 | Set-Content "$RepoRoot\configs\terminal-settings.json" -Encoding utf8NoBOM
        Write-Host "  WT Settings      OK" -ForegroundColor Green
    } catch {
        Write-Host "  WT Settings      FAILED (JSON parse error -- skipped to avoid exposing secrets)" -ForegroundColor Red
        Write-Host "                   Fix settings.json manually or run: Sync-Config push" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WT Settings      NOT FOUND (neither Store nor non-Store)" -ForegroundColor Red
}

# Themes (only pnx-*)
$themeFiles = Get-ChildItem $OmpThemesLocal -Filter "pnx-*.omp.json" -ErrorAction SilentlyContinue
if ($themeFiles) {
    $themeFiles | Copy-Item -Destination "$RepoRoot\themes\" -Force
    Write-Host "  Themes           OK ($($themeFiles.Count) files)" -ForegroundColor Green
} else {
    Write-Host "  Themes           NONE FOUND" -ForegroundColor Red
}

# Claude Code Settings (strip secrets before saving to repo)
$claudeSettings = Get-ClaudeConfigPath -Type settings
if ($claudeSettings -and (Test-Path $claudeSettings)) {
    try {
        $claudeJson = Get-Content $claudeSettings -Raw | ConvertFrom-Json
        $secrets = Test-ClaudeSecrets -Json $claudeJson
        if ($secrets.Count -gt 0) {
            Write-Host "  Stripping $($secrets.Count) secret(s) from Claude settings..." -ForegroundColor Yellow
        }
        $sanitized = Remove-ClaudeSecrets -Json $claudeJson
        $sanitized | ConvertTo-Json -Depth 10 | Set-Content "$RepoRoot\configs\claude-settings.template.json" -Encoding utf8NoBOM
        Write-Host "  Claude Settings  OK (secrets stripped)" -ForegroundColor Green
    } catch {
        Write-Host "  Claude Settings  FAILED: $_ -- skipped to avoid exposing secrets" -ForegroundColor Red
    }
} else {
    Write-Host "  Claude Settings  NOT FOUND" -ForegroundColor DarkGray
}

# Statusline (direct copy, no secrets)
$statusline = Get-ClaudeConfigPath -Type statusline
if ($statusline -and (Test-Path $statusline)) {
    Copy-Item $statusline "$RepoRoot\configs\statusline.sh" -Force
    Write-Host "  Statusline       OK" -ForegroundColor Green
} else {
    Write-Host "  Statusline       NOT FOUND" -ForegroundColor DarkGray
}

# CLAUDE.md (direct copy)
$claudeMd = Get-ClaudeConfigPath -Type 'claude.md'
if ($claudeMd -and (Test-Path $claudeMd)) {
    Copy-Item $claudeMd "$RepoRoot\configs\claude.md" -Force
    Write-Host "  CLAUDE.md        OK" -ForegroundColor Green
} else {
    Write-Host "  CLAUDE.md        NOT FOUND" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Review changes:" -ForegroundColor DarkGray
Write-Host "    cd $RepoRoot && git diff" -ForegroundColor DarkGray
Write-Host ""
