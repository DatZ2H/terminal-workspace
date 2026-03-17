# Developer Guide — Terminal Workspace

## Project Overview

Terminal Workspace is a self-contained PowerShell 7 + Windows Terminal configuration system. It provides:

- **14 built-in themes** — each consisting of an OMP prompt, a WT color scheme, and a WT theme
- **3 visual styles** — mac (acrylic), win (mica), linux (solid)
- **One-command switching** — `Set-Theme tokyo mac` updates prompt + terminal in one step
- **Cross-machine sync** — `Sync-Config push/pull` keeps multiple machines in sync
- **Auto-bootstrap** — `bootstrap.bat` sets up everything from a fresh Windows install

## Prerequisites for Development

- Windows 10/11
- Windows Terminal (Store or non-Store)
- PowerShell 7+ (`winget install Microsoft.PowerShell`)
- Pester 5+ (`Install-Module Pester -Force`)
- Git

## Directory Structure

```
terminal-workspace/
├── bootstrap.bat                 # Entry point (CMD-compatible, bypasses ExecutionPolicy)
├── bootstrap.ps1                 # Full setup logic (auto-installs PS7 if needed)
├── update.ps1                    # Standalone updater (git pull + redeploy)
├── CLAUDE.md                     # Project brief for AI assistants
├── README.md                     # User documentation
├── configs/
│   ├── profile.ps1               # PowerShell profile — the main engine
│   ├── themes.json               # Theme + style definitions (single source of truth)
│   └── terminal-settings.json    # Windows Terminal settings template
├── themes/
│   └── pnx-*.omp.json           # 14 Oh My Posh prompt theme files
├── scripts/
│   ├── common.ps1                # Shared helpers (WT detection, atomic writes, caching)
│   ├── install-tools.ps1         # Tool installer (winget + scoop)
│   ├── install-fonts.ps1         # Nerd Font installer
│   ├── update-tools.ps1          # Tool updater
│   ├── sync-to-repo.ps1          # Local → repo sync (strips secrets)
│   ├── sync-from-repo.ps1        # Repo → local sync (with backup)
│   └── status.ps1                # Version and config report
├── tests/
│   ├── common.tests.ps1          # Pester tests for common.ps1
│   └── profile.tests.ps1         # Pester tests for profile.ps1
└── docs/
    ├── architecture.md           # System architecture and data flow
    └── developer-guide.md        # This file
```

## How to Add a New Theme

Adding a theme requires editing **3 files** and creating **1 new file**:

### Step 1: Create OMP prompt file

Copy an existing theme and modify colors:

```powershell
# Copy a base theme
Copy-Item themes/pnx-dracula-pro.omp.json themes/pnx-mytheme.omp.json
```

Edit `themes/pnx-mytheme.omp.json`:
- Change `background` colors in each segment
- Change `foreground` colors
- The structure (blocks, segments, templates) should stay the same

Naming convention: `pnx-<key>.omp.json` where `<key>` is your theme's short name.

### Step 2: Add theme entry to `configs/themes.json`

```json
{
  "themes": {
    "mytheme": {
      "omp": "pnx-mytheme.omp.json",
      "scheme": "My Theme Display Name",
      "wtTheme": "PNX My Theme"
    }
  }
}
```

- `omp`: filename only (path prefix added at load time)
- `scheme`: must match the color scheme name in terminal-settings.json
- `wtTheme`: must match the WT theme name in terminal-settings.json

### Step 3: Add color scheme to `configs/terminal-settings.json`

Add to the `schemes` array:

```json
{
    "name": "My Theme Display Name",
    "background": "#1E1E2E",
    "foreground": "#CDD6F4",
    "cursorColor": "#F5E0DC",
    "selectionBackground": "#585B70",
    "black": "#45475A",
    "red": "#F38BA8",
    "green": "#A6E3A1",
    "yellow": "#F9E2AF",
    "blue": "#89B4FA",
    "purple": "#F5C2E7",
    "cyan": "#94E2D5",
    "white": "#BAC2DE",
    "brightBlack": "#585B70",
    "brightRed": "#F38BA8",
    "brightGreen": "#A6E3A1",
    "brightYellow": "#F9E2AF",
    "brightBlue": "#89B4FA",
    "brightPurple": "#F5C2E7",
    "brightCyan": "#94E2D5",
    "brightWhite": "#A6ADC8"
}
```

### Step 4: Add WT theme to `configs/terminal-settings.json`

Add to the `themes` array:

```json
{
    "name": "PNX My Theme",
    "tab": {
        "background": "#1E1E2EFF",
        "iconStyle": "default",
        "showCloseButton": "hover",
        "unfocusedBackground": "#1E1E2E99"
    },
    "tabRow": {
        "background": "#1E1E2E99",
        "unfocusedBackground": "#1E1E2E66"
    },
    "window": {
        "applicationTheme": "dark",
        "experimental.rainbowFrame": false,
        "frame": null,
        "unfocusedFrame": null,
        "useMica": false
    }
}
```

### Step 5: Verify

```powershell
# Run tests
Invoke-Pester ./tests/ -Output Detailed

# Validate JSON
pwsh -NoProfile -Command 'Get-Content configs/themes.json -Raw | ConvertFrom-Json | Out-Null; Write-Host "OK"'

# Check three-way consistency
Test-ThemeIntegrity

# Test the theme
Set-Theme mytheme
```

## How to Add a New Style

Edit `configs/themes.json`, add to the `styles` object:

```json
{
  "styles": {
    "mystyle": {
      "opacity": 90,
      "useAcrylic": true,
      "useMica": false,
      "padding": "12, 10, 12, 10",
      "cursorShape": "bar",
      "scrollbarState": "visible",
      "unfocusedOpacity": 80
    }
  }
}
```

No other files need to be changed — the profile loads styles from the manifest dynamically.

## Key Code Patterns

### Atomic Writes

Windows Terminal watches its settings.json for changes. To prevent corruption from partial writes:

```powershell
# Save-WtSettings in common.ps1:
# 1. Backup existing → settings.json.pnx-backup
# 2. Write to temp file → settings.json.pnx-tmp
# 3. Move-Item temp → settings.json (atomic on NTFS)
# 4. Retry 3x if WT holds file lock
# 5. Last resort: direct Set-Content (non-atomic but better than silent failure)
```

### Init Caching

```powershell
# Get cached init (fast path)
$cached = Get-PnxCachedInit -Name 'omp' -VersionKey $exeTicks -ExtraKey "$theme|$cfgTicks"
if ($cached) {
    $cached | Invoke-Expression    # ~5ms vs ~300ms
} else {
    # Slow path: run oh-my-posh init, cache the output
    $init = oh-my-posh init pwsh --config $config | Out-String
    $init | Invoke-Expression
    Save-PnxCachedInit -Name 'omp' -VersionKey $exeTicks -ExtraKey "$theme|$cfgTicks" -Content $init
}
```

### Theme Detection Heuristic

Profile detects the active theme via a three-level fallback:

1. **pnx markers** — `pnxTheme`/`pnxStyle` properties in WT `profiles.defaults` (written by `Set-Theme`)
2. **Cross-validation** — if marker exists but `colorScheme` doesn't match marker's scheme, someone edited WT settings externally → fall back to heuristic
3. **Heuristic match** — scan ThemeDB for matching `colorScheme` name; for styles, score on `opacity` + `useAcrylic` + `padding` (needs 2+ matches)

### Manifest Loading with Fallback

```powershell
# Profile reads themes.json via $env:PNX_TERMINAL_REPO
# If missing (first boot before bootstrap): fallback to minimal hardcoded values
if ($ThemeDB.Count -eq 0) {
    $ThemeDB = @{ pro = @{ ... } }   # just enough to not crash
}
```

## Common.ps1 Function Reference

| Function | Purpose | Parameters |
|----------|---------|------------|
| `Get-WtSettingsPath` | Find WT settings.json (Store or non-Store) | `-Mode` (file/deploy) |
| `Get-NerdFontInfo` | Detect CaskaydiaCove Nerd Font from registry | (none) |
| `Repair-WtFontFace` | Fix stale font name (v2↔v3) in WT settings | `-WtPath`, `-WtJson`, `-FontInfo` |
| `Save-WtSettings` | Atomic JSON write with backup and retry | `-Json`, `-WtPath` |
| `Get-PnxCachedInit` | Read cached init script if version matches | `-Name`, `-VersionKey`, `-ExtraKey` |
| `Save-PnxCachedInit` | Write init script + meta to cache dir | `-Name`, `-VersionKey`, `-ExtraKey`, `-Content` |
| `Clear-PnxCache` | Delete all cache files | (none) |
| `Initialize-WtPnxMarkers` | Inject pnxTheme/pnxStyle markers + fix font | `-WtJson`, `-DefaultTheme`, `-DefaultStyle` |

## Profile.ps1 Function Reference

| Function | Purpose | Key Parameters |
|----------|---------|----------------|
| `Set-Theme` | Switch theme and/or style | `-Theme`, `-Style` (both optional) |
| `Set-Style` | Switch style only | `-Style` |
| `Get-ThemeList` | Display available themes | (none) |
| `Test-ThemeIntegrity` | Validate OMP/scheme/WT theme consistency | `-Quiet` (returns bool) |
| `New-PnxTheme` | Create custom theme from existing | `-Name`, `-BasedOn`, `-Scheme`, `-Background` |
| `Remove-PnxTheme` | Delete custom theme | `-Name` |
| `Select-ThemeInteractive` | TUI theme picker (arrow keys) | (none) |
| `Sync-Config` | Sync local ↔ repo | `-Direction` (push/pull), `-Force` |
| `Update-Tools` | Update all installed tools | (none) |
| `Update-Workspace` | Git pull + redeploy + reload | (none) |
| `Get-Status` | Show tool versions and config status | (none) |

## Testing

### Run All Tests

```powershell
Invoke-Pester ./tests/ -Output Detailed
```

### What Tests Cover

- **Data integrity**: ThemeDB/StyleDB loaded correctly from JSON, correct types
- **Registry merge**: Custom themes merge without overriding built-ins
- **Edge cases**: Corrupt JSON, missing files, null paths
- **Helpers**: WT path detection, font detection, atomic writes, caching
- **Marker injection**: pnxTheme/pnxStyle added correctly, not overwritten
- **Input validation**: Hex color format, duplicate names, unknown base themes

### Test Isolation

Tests mock external tools (`oh-my-posh`, `zoxide`) so they run without those tools installed. Pester's `$TestDrive` provides isolated temp directories.

### Validate PowerShell Syntax (No Execution)

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("configs/profile.ps1", [ref]$null, [ref]$errors)
$errors  # should be empty
```

## Sync Workflow

### Pushing Local Changes to Repo

```powershell
Sync-Config push              # Copies profile, WT settings (stripped), themes to repo
cd $env:PNX_TERMINAL_REPO
git diff                      # Review changes
git add -A && git commit -m "update: description"
git push
```

`sync-to-repo.ps1` strips `environment` properties from WT settings to prevent leaking secrets.

### Pulling Repo Changes to Local

```powershell
Update-Workspace              # Shortcut: git pull + sync-from-repo + reload profile
# Or:
Sync-Config pull              # Just deploy + reload (no git pull)
```

### Security: What Gets Stripped

`sync-to-repo.ps1` removes `environment` variables from WT settings before copying to repo. This prevents accidentally committing API keys, tokens, or paths set in WT's environment section.

## Troubleshooting Development Issues

### Profile won't load after editing

```powershell
# Validate syntax without loading
pwsh -NoProfile -Command '[System.Management.Automation.Language.Parser]::ParseFile("configs/profile.ps1", [ref]$null, [ref]$e); $e'

# Load profile with verbose errors
pwsh -NoProfile -Command '. configs/profile.ps1'
```

### Tests fail with "command not found"

Tests mock `oh-my-posh` and `zoxide`. If you add new external commands to profile.ps1, add corresponding mocks in `tests/profile.tests.ps1` BeforeAll.

### Theme shows in ThemeDB but not in WT

Check `Test-ThemeIntegrity` — it validates all three components:
- OMP file exists in `~/.oh-my-posh/themes/`
- Color scheme exists in WT `settings.json`
- WT theme exists in WT `settings.json`

### Cache seems stale

```powershell
Clear-PnxCache    # Delete all cached init scripts
. $PROFILE        # Reload profile (regenerates cache)
```
