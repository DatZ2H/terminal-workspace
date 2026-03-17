# terminal-workspace

PowerShell 7 + Windows Terminal configuration package.
Clone, bootstrap, done.

## Prerequisites

- Windows 10/11
- Windows Terminal (Microsoft Store or winget — both supported)

Everything else (including PowerShell 7) is installed automatically by the bootstrap script.

## Quick Start

```cmd
git clone https://github.com/DatZ2H/terminal-workspace.git %USERPROFILE%\terminal-workspace
cd %USERPROFILE%\terminal-workspace
.\bootstrap.bat
```

`bootstrap.bat` works from any shell (CMD, PowerShell 5, PowerShell 7). It bypasses ExecutionPolicy restrictions on fresh Windows installs and auto-installs PowerShell 7 if needed.

Restart Windows Terminal after bootstrap completes.

## What's Included

### Tools (auto-installed)

| Tool | Install via | Purpose |
|------|-------------|---------|
| PowerShell 7 | winget | Modern shell |
| Oh My Posh | winget | Prompt theming |
| Git | winget | Version control |
| Node.js LTS | winget | JavaScript runtime |
| Python 3.12 | winget | Python runtime |
| Scoop | script | CLI package manager |
| zoxide | scoop | Smart directory jumping |
| ripgrep (rg) | scoop | Fast file content search |
| Terminal-Icons | PS module | File/folder icons |
| CaskaydiaCove NF | OMP | Nerd Font for prompt icons |

### Themes (14 color themes)

| Name | Key | Based on |
|------|-----|----------|
| Dracula Pro | `pro` | Softer purple-tinted Dracula |
| Dracula | `dracula` | Classic high-contrast |
| Tokyo Night Storm | `tokyo` | Blue-indigo, calm |
| Catppuccin Mocha | `mocha` | Warm pastels |
| Nord | `nord` | Arctic, muted tones |
| Dark Sea Green | `seagreen` | Deep ocean-green, muted oceanic |
| Organic Green | `organic` | Light honeydew/mint, earthy greens |
| Nihileaf | `nihileaf` | Dark monochromatic green |
| Miasma | `miasma` | Warm earthy tones, olive greens |
| Jake Green Grey | `jake` | Muted green-grey, desaturated |
| Kryptonite | `kryptonite` | Neon green on black, cyberpunk |
| fl0-c0d3 | `fl0` | Nord-like base with green accents |
| Green Dark Supercharged | `greendark` | Bright neon on dark, Material-inspired |
| Green Nordic | `greennord` | Teal-dark, earthy nordic |

Run `Set-Theme` with no arguments to launch the interactive picker (arrow keys to browse, Enter to select).
Theme is auto-detected from Windows Terminal settings on each session start.
OMP prompt always matches the active WT color scheme.

### Styles (3 visual styles)

| Style | Look |
|-------|------|
| `mac` | Acrylic blur 85%, wide padding, unfocused 70% |
| `win` | Mica material 95%, standard padding, unfocused 90% |
| `linux` | Solid background 100%, block cursor, no transparency |

## Configuration

### Windows Terminal Settings

| Setting | Value | Effect |
|---------|-------|--------|
| `defaultProfile` | PowerShell 7 | PS7 opens by default |
| `font.face` | `CaskaydiaCove NF` | Nerd Font for prompt icons (auto-detected v2/v3) |
| `font.size` | `12` | Default font size |
| `colorScheme` | `Dracula Pro` | Default color scheme |
| `scrollbarState` | `visible` | Scrollbar always shown |
| `historySize` | `50000` | 50K lines scrollback |
| `bellStyle` | `none` | No beep sounds |
| `intenseTextStyle` | `bright` | Bold text renders brighter instead of thicker |
| `adjustIndistinguishableColors` | `indexed` | Auto-fix invisible text (same color as background) |
| `autoMarkPrompts` | `true` | Mark each command for Ctrl+Up/Down navigation |
| `newTabPosition` | `afterCurrentTab` | New tab opens next to current tab |
| `copyFormatting` | `none` | Paste plain text only (no colors/fonts) |
| `copyOnSelect` | `false` | Must explicitly copy (Ctrl+Shift+C) |
| `initialCols` | `120` | Default window width |
| `initialRows` | `60` | Default window height |
| `firstWindowPreference` | `persistedWindowLayout` | Restore previous window size/position |
| `showTabsFullscreen` | `true` | Show tab bar in fullscreen mode |
| `opacity` | `85` | Window transparency (mac style default) |
| `unfocusedAppearance.opacity` | `70` | More transparent when not focused |

### PSReadLine Settings

| Setting | Value | Effect |
|---------|-------|--------|
| `PredictionSource` | `History` | Suggest commands from history |
| `PredictionViewStyle` | `ListView` | Show suggestions as dropdown list |
| `EditMode` | `Windows` | Ctrl+V/Z work as expected |
| `BellStyle` | `None` | No beep in PowerShell |
| `MaximumHistoryCount` | `10000` | Remember 10K commands |
| `HistoryNoDuplicates` | `true` | Skip duplicate commands when searching |
| `HistorySearchCursorMovesToEnd` | `true` | Cursor jumps to end when recalling history |
| `ShowToolTips` | `true` | Show parameter descriptions on Tab |

### Other Profile Settings

| Setting | Effect |
|---------|--------|
| Console UTF-8 encoding | Vietnamese characters work correctly in pipes |
| `Install-Module:Scope = CurrentUser` | No admin prompt when installing modules |
| WT path auto-detection | Supports both Store and non-Store WT installs |
| Theme auto-detection | Reads `pnxTheme`/`pnxStyle` markers from WT settings on profile load |
| Nerd Font auto-repair | Detects v2/v3 font name and updates WT settings if mismatched |
| Health check on load | Reports config issues (missing font, unreadable WT settings) at startup |
| Custom theme persistence | User-created themes saved to `%LOCALAPPDATA%\pnx-terminal\themes.json`, merged into ThemeDB on load |
| `-WhatIf` / `-Verbose` support | All public functions support common parameters via `[CmdletBinding()]` |

## File Structure

```
terminal-workspace/
├── bootstrap.bat                 # Entry point — works from any shell (bypasses ExecutionPolicy)
├── bootstrap.ps1                 # Full setup logic (called by bootstrap.bat)
├── update.ps1                    # Standalone updater (git pull + redeploy + reload)
├── configs/
│   ├── profile.ps1               # PowerShell profile (source of truth)
│   ├── themes.json               # Theme & style definitions (ThemeDB + StyleDB + defaults)
│   └── terminal-settings.json    # Windows Terminal settings (schemes + WT themes)
├── themes/
│   ├── pnx-dracula-pro.omp.json
│   ├── pnx-dracula.omp.json
│   ├── pnx-tokyo-storm.omp.json
│   ├── pnx-mocha.omp.json
│   ├── pnx-nord.omp.json
│   ├── pnx-dark-sea-green.omp.json
│   ├── pnx-organic-green.omp.json
│   ├── pnx-nihileaf.omp.json
│   ├── pnx-miasma.omp.json
│   ├── pnx-jake-green-grey.omp.json
│   ├── pnx-kryptonite.omp.json
│   ├── pnx-fl0.omp.json
│   ├── pnx-green-dark.omp.json
│   └── pnx-green-nordic.omp.json
├── tests/
│   ├── common.tests.ps1          # Pester 5 tests for shared helpers
│   └── profile.tests.ps1         # Pester 5 tests for profile functions
└── scripts/
    ├── common.ps1                # Shared helpers (WT path, font, cache, markers, atomic writes)
    ├── install-tools.ps1         # Install winget + scoop packages
    ├── install-fonts.ps1         # Install Nerd Font
    ├── update-tools.ps1          # Update all tools
    ├── sync-to-repo.ps1          # Local configs -> repo (strips secrets)
    ├── sync-from-repo.ps1        # Repo configs -> local (with backup)
    └── status.ps1                # Show all tool versions + config status
```

## Cheatsheet

### Theme & Style

```powershell
Set-Theme                         # Interactive theme picker (arrow keys + Enter)
Set-Theme pro                     # Switch to Dracula Pro (keep current style)
Set-Theme tokyo win               # Switch theme + style together
Set-Theme mocha linux             # Catppuccin Mocha + Linux style
Set-Style mac                     # Switch style only (keep current theme)
Set-Style                         # Show current style
Test-ThemeIntegrity               # Check ThemeDB vs OMP files vs WT schemes
```

Tab completion is available for `Set-Theme`, `Set-Style`, `New-PnxTheme`, and `Remove-PnxTheme` parameters.

### Custom Themes

```powershell
New-PnxTheme -Name mytheme -BasedOn pro                  # Create custom theme from existing
New-PnxTheme -Name ocean -BasedOn nord -Background "#1a2b3c"  # Custom with background color
New-PnxTheme -Name test -BasedOn pro -WhatIf             # Preview without creating
Remove-PnxTheme mytheme                                   # Remove custom theme + OMP file
Remove-PnxTheme mytheme -WhatIf                           # Preview removal
```

Custom themes persist across restarts (stored in `%LOCALAPPDATA%\pnx-terminal\themes.json`).
Tab completion available for `New-PnxTheme -BasedOn` and `Remove-PnxTheme -Name`.

### Directory Navigation (zoxide)

```powershell
z <keyword>                       # Jump to best-matching directory
z proj                            # Jump to Projects folder (if visited before)
z sevt                            # Jump to Samsung-SEVT-APM990 folder
zi                                # Interactive directory picker (fuzzy)
```

> zoxide learns from your `cd` history. Use `cd` normally for a few days,
> then `z` becomes increasingly accurate.

### File Search (ripgrep)

```powershell
rg "keyword" .                    # Search current directory
rg "ISO 3691" ../Knowledge-Base/  # Search in specific folder
rg -i "lidar" --type md           # Case-insensitive, only .md files
rg -l "safety"                    # List filenames only (no content)
rg "pattern" -C 3                 # Show 3 lines of context around matches
rg "status.*active" --glob "*.md" # Regex + file filter
```

### Windows Terminal Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Alt+Shift+D` | Split pane (auto direction) |
| `Alt+Shift++` | Split pane right |
| `Alt+Shift+-` | Split pane down |
| `Ctrl+Shift+C` | Copy (multi-line) |
| `Ctrl+V` | Paste |
| `Ctrl+Shift+F` | Find in terminal |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+Up` | Jump to previous command |
| `Ctrl+Down` | Jump to next command |
| `Win+\`` | Quake mode (dropdown terminal) |

### PSReadLine Keybindings

| Key | Action |
|-----|--------|
| `Tab` | Menu-complete (cycle through options with tooltips) |
| `Up/Down` | Search history matching current input |
| `Ctrl+W` | Delete word backward (erase last word) |
| `Ctrl+D` | Delete char or exit |
| `Ctrl+Z` | Undo |

### Maintenance

```powershell
Get-Status                        # Show versions of all tools + config paths
Update-Tools                      # Update everything (winget + scoop + modules + font)
Update-Tools -Force               # Update without confirmation prompt
Update-Workspace                  # Git pull + redeploy configs + reload profile
Test-ThemeIntegrity               # Verify ThemeDB, OMP files, and WT schemes are in sync
Invoke-Pester ./tests/ -Output Detailed  # Run test suite (requires Pester 5+)
```

### Sync Between Machines

```powershell
# On current machine — save changes to repo
Sync-Config push
cd $env:PNX_TERMINAL_REPO
git add -A && git commit -m "update: description" && git push

# On another machine — pull and apply
Update-Workspace                  # Easiest: pulls + redeploys + reloads in one step

# Or manually:
cd $env:PNX_TERMINAL_REPO
git pull
Sync-Config pull                  # Auto-backup before overwriting (keeps last 3)

# Or re-bootstrap (skip tool install — works from any shell)
.\bootstrap.bat -SkipTools
# If already in PowerShell 7, can run directly:
.\bootstrap.ps1 -SkipTools
```

### Standalone Scripts

```powershell
.\update.ps1                      # Git pull + redeploy + reload (no profile needed)
.\scripts\status.ps1              # Tool versions (without loading profile)
.\scripts\install-tools.ps1       # Install all tools from scratch
.\scripts\install-fonts.ps1       # Reinstall Nerd Font
.\scripts\update-tools.ps1        # Update all tools (interactive)
.\scripts\update-tools.ps1 -Force # Update without confirmation
.\scripts\sync-to-repo.ps1        # Push local -> repo (strips environment secrets)
.\scripts\sync-from-repo.ps1      # Pull repo -> local (keeps last 3 backups)
```

## New Machine Setup

1. Install Windows Terminal from Microsoft Store (or `winget install Microsoft.WindowsTerminal`)
2. Open any terminal (CMD, PowerShell, or Windows Terminal)
3. Run:
   ```cmd
   git clone https://github.com/DatZ2H/terminal-workspace.git %USERPROFILE%\terminal-workspace
   cd %USERPROFILE%\terminal-workspace
   .\bootstrap.bat
   ```
4. Restart Windows Terminal
5. Verify: `Get-Status`
6. Pick your theme: `Set-Theme pro mac`

> `bootstrap.bat` handles everything automatically: installs PowerShell 7 if missing, sets ExecutionPolicy, installs all tools, deploys configs. No manual steps needed.

## Troubleshooting

**Font icons broken (squares/boxes instead of icons)**
```powershell
# Reinstall font
.\scripts\install-fonts.ps1
# Restart Windows Terminal — font name is auto-detected (v2 or v3)
```

If icons are still broken after restart, check the font name matches:
```powershell
Get-Status    # Look at the "Nerd Font" section — shows installed version and WT font face match
```

**OMP prompt not loading**
```powershell
oh-my-posh version                # Should show version number
Test-Path "$env:USERPROFILE\.oh-my-posh\themes\pnx-dracula-pro.omp.json"
. $PROFILE                        # Reload profile
```

**Sync-Config says "Repo not found"**
```powershell
$env:PNX_TERMINAL_REPO            # Should show path to terminal-workspace
# If empty, re-run bootstrap or set manually:
[Environment]::SetEnvironmentVariable('PNX_TERMINAL_REPO', "$env:USERPROFILE\terminal-workspace", 'User')
```

**Theme not switching (WT not updating)**
```powershell
# Windows Terminal must be running (it hot-reloads settings.json)
# Verify the settings file exists:
Get-Status    # Check "WT Settings" row under Config Locations
```

**zoxide not jumping correctly**
```powershell
zoxide query --list               # See what directories zoxide knows
# zoxide needs time to learn — use cd normally first
```

**Scoop tools not found after install**
```powershell
# Scoop adds to PATH but current session may not see it
# Restart terminal, or:
$env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
```

**Profile fails to load on fresh Windows (ExecutionPolicy)**
```cmd
:: Use bootstrap.bat instead of bootstrap.ps1 — it bypasses ExecutionPolicy automatically
.\bootstrap.bat
:: After bootstrap, ExecutionPolicy is set to RemoteSigned permanently
```

## Environment Variables

| Variable | Purpose | Set by |
|----------|---------|--------|
| `PNX_TERMINAL_REPO` | Path to this repo | bootstrap (auto) |
| `PNX_OMP_THEMES` | Custom theme directory (optional) | manual |

## Optional: Claude Code CLI

If you use [Claude Code](https://claude.ai/code), here are some useful additions (not included in this repo — configure manually):

**Status Line** — show model, context usage, cost, and working directory:
```bash
# In Claude Code, run:
/statusline show model name and context percentage with a progress bar, cost and current directory
```
This generates a status line script at `~/.claude/statusline.sh` automatically.

**Vietnamese IME Fix** — fix input bug when typing Vietnamese with Telex/VNI:
```bash
# See: https://github.com/manhit96/claude-code-vietnamese-fix
pip install claude-code-vietnamese-fix
claude-vn-fix
# Re-run after each Claude Code update
```

## Documentation

- [Architecture](docs/architecture.md) — system design, data flow, caching, error handling
- [Developer Guide](docs/developer-guide.md) — how to add themes/styles, code patterns, testing
- [Script Reference](docs/script-reference.md) — all scripts, functions, and parameters

## License

Private repository. Personal use only.
