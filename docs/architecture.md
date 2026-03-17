# Architecture — Terminal Workspace

## Overview

Terminal Workspace is a PowerShell 7 + Windows Terminal configuration system that manages 14 color themes, 3 visual styles, and a suite of developer tools. It follows a **data-driven architecture** where theme/style definitions live in JSON while the engine logic lives in PowerShell scripts.

```
User Commands                Engine Layer              Data Layer
──────────────                ──────────────            ──────────────
Set-Theme tokyo    ────>    configs/profile.ps1   <──  configs/themes.json
Set-Style mac      ────>    scripts/common.ps1    <──  configs/terminal-settings.json
Sync-Config push   ────>    scripts/sync-*.ps1    <──  themes/*.omp.json
Update-Workspace   ────>    bootstrap.ps1
```

## Core Principles

1. **Data/Logic Separation** — Theme and style data lives in `configs/themes.json` (JSON), not hardcoded in scripts.
2. **Single Source of Truth** — Each piece of data has exactly one canonical location.
3. **Graceful Degradation** — Profile loads with minimal fallback if manifest or tools are missing.
4. **Atomic Writes** — Windows Terminal settings are written via backup + temp file + rename to prevent corruption.
5. **Cache-First Performance** — Slow init commands (OMP, zoxide) are cached to disk and invalidated on change.

## System Architecture

### Layer Diagram

```
                  ┌──────────────────────────────────────────────────────┐
                  │                  User Interface                      │
                  │  Set-Theme  Set-Style  Sync-Config  Get-Status      │
                  │  New-PnxTheme  Remove-PnxTheme  Update-Workspace   │
                  └────────────────────┬─────────────────────────────────┘
                                       │
                  ┌────────────────────▼─────────────────────────────────┐
                  │              Profile Engine (profile.ps1)            │
                  │  ThemeDB/StyleDB loading  │  Theme detection         │
                  │  OMP/zoxide init (cached) │  Health checks           │
                  │  Interactive selector      │  Tab completion          │
                  └────────────────────┬─────────────────────────────────┘
                                       │
          ┌────────────────────────────▼────────────────────────────┐
          │                Shared Helpers (common.ps1)              │
          │  WT path detection  │  Atomic writer  │  Init cache    │
          │  Nerd Font repair   │  Marker injection                │
          └──────────┬─────────────────┬──────────────────┬────────┘
                     │                 │                  │
          ┌──────────▼──────┐ ┌───────▼────────┐ ┌──────▼───────────┐
          │  Data (JSON)    │ │ Windows Terminal│ │ Local Storage     │
          │  themes.json    │ │ settings.json   │ │ cache/            │
          │  terminal-      │ │ (live config)   │ │ themes.json       │
          │  settings.json  │ │                 │ │ (custom registry) │
          └─────────────────┘ └─────────────────┘ └──────────────────┘
```

### File Roles

| File | Layer | Responsibility |
|------|-------|----------------|
| `configs/profile.ps1` | Engine | Main profile — loads data, defines commands, inits tools |
| `scripts/common.ps1` | Engine | Shared utilities — WT detection, atomic writes, caching |
| `configs/themes.json` | Data | Theme definitions (name, OMP file, scheme, WT theme) + style definitions + defaults |
| `configs/terminal-settings.json` | Data | WT settings template — color schemes, WT themes, profiles, keybindings |
| `themes/*.omp.json` | Data | Oh My Posh prompt configurations (14 files) |
| `bootstrap.ps1` | Setup | First-run initialization — tools, fonts, config deployment |
| `scripts/sync-to-repo.ps1` | Sync | Copy local changes to repo (strips secrets) |
| `scripts/sync-from-repo.ps1` | Sync | Deploy repo configs to local (with backup) |
| `scripts/install-tools.ps1` | Setup | Install winget/scoop packages |
| `scripts/install-fonts.ps1` | Setup | Install CaskaydiaCove Nerd Font |
| `scripts/update-tools.ps1` | Maint. | Update all installed tools |
| `scripts/status.ps1` | Maint. | Report tool versions and config status |
| `update.ps1` | Maint. | Standalone updater (git pull + redeploy) |

## Data Flow

### 1. Bootstrap (First Run)

```
bootstrap.ps1
    │
    ├─ Step 0: Set ExecutionPolicy → RemoteSigned
    ├─ Step 1: install-tools.ps1 → winget + scoop packages
    ├─ Step 2: install-fonts.ps1 → CaskaydiaCove Nerd Font
    ├─ Step 3: Copy themes/*.omp.json → ~/.oh-my-posh/themes/
    ├─ Step 4: terminal-settings.json → WT settings.json (atomic, inject markers)
    ├─ Step 5: profile.ps1 → $PROFILE (with backup)
    └─ Step 6: Set PNX_TERMINAL_REPO env var (User scope, persistent)
```

### 2. Profile Load (Every Terminal Open)

```
profile.ps1 loaded by PowerShell
    │
    ├─ Dot-source common.ps1 (or inline fallback)
    ├─ Read configs/themes.json → build ThemeDB + StyleDB
    │   └─ Fallback: minimal {pro} + {mac} if manifest missing
    ├─ Merge custom themes from %LOCALAPPDATA%\pnx-terminal\themes.json
    ├─ Detect active theme/style from WT settings.json
    │   ├─ Primary: pnxTheme/pnxStyle markers
    │   ├─ Cross-validate: marker vs colorScheme (detect external changes)
    │   └─ Fallback: heuristic match (colorScheme name, opacity+acrylic+padding score)
    ├─ Init Oh My Posh (cached — invalidated on theme/version change)
    ├─ Init zoxide (cached — invalidated on version change)
    ├─ Lazy-load Terminal-Icons (OnIdle on PS 7.3+)
    ├─ Check/repair Nerd Font face (v2↔v3 auto-fix)
    └─ Report health issues (if any)
```

### 3. Theme Switch (`Set-Theme tokyo mac`)

```
Set-Theme
    │
    ├─ Validate theme key exists in ThemeDB
    ├─ Validate style key exists in StyleDB
    ├─ Re-init OMP prompt with new config
    │   └─ Save to cache for next startup
    ├─ Read WT settings.json
    ├─ Update profiles.defaults:
    │   ├─ colorScheme = theme.scheme
    │   ├─ opacity, useAcrylic, padding, cursorShape (from StyleDB)
    │   ├─ unfocusedAppearance.opacity
    │   ├─ pnxTheme = "tokyo" (marker for next load)
    │   └─ pnxStyle = "mac" (marker for next load)
    ├─ Update root theme = theme.wtTheme
    ├─ Update WT theme useMica (from StyleDB)
    ├─ Atomic write WT settings.json
    └─ Update $Global:PnxCurrentTheme/Style
```

### 4. Sync Workflow

```
Sync-Config push (local → repo):
    ├─ Test-ThemeIntegrity (warn if issues)
    └─ sync-to-repo.ps1:
        ├─ Copy $PROFILE → configs/profile.ps1
        ├─ Copy WT settings → configs/terminal-settings.json (strip environment vars)
        └─ Copy pnx-*.omp.json → themes/

Sync-Config pull (repo → local):
    └─ sync-from-repo.ps1:
        ├─ Backup + copy configs/profile.ps1 → $PROFILE
        ├─ Read terminal-settings.json → inject markers → atomic write → WT settings
        ├─ Copy themes/*.omp.json → ~/.oh-my-posh/themes/
        └─ Clear-PnxCache (force fresh init on next load)
```

## Key Data Structures

### ThemeDB (runtime hashtable)

Built from `configs/themes.json` at profile load:

```powershell
$ThemeDB = @{
    pro = @{
        omp     = "C:\Users\<user>\.oh-my-posh\themes\pnx-dracula-pro.omp.json"  # full path
        scheme  = "Dracula Pro"          # WT color scheme name
        wtTheme = "PNX Dracula Pro"      # WT theme name
    }
    # ... 13 more entries
}
```

Source JSON (`configs/themes.json`) stores only filenames:
```json
{ "omp": "pnx-dracula-pro.omp.json", "scheme": "Dracula Pro", "wtTheme": "PNX Dracula Pro" }
```

Path prefix (`$PnxThemes\`) is prepended at load time.

### StyleDB (runtime hashtable)

```powershell
$StyleDB = @{
    mac = @{
        opacity          = [int]85       # Window transparency %
        useAcrylic       = [bool]$true   # Acrylic blur effect
        useMica          = [bool]$false  # Mica material (Win11)
        padding          = "16, 12, 16, 12"
        cursorShape      = "bar"
        scrollbarState   = "visible"
        unfocusedOpacity = [int]70       # Opacity when window not focused
    }
}
```

### Custom Theme Registry

Stored at `%LOCALAPPDATA%\pnx-terminal\themes.json`. Merged into ThemeDB at load time. Built-in themes cannot be overridden by custom entries.

### pnx Markers (in WT settings.json)

```json
{
    "profiles": {
        "defaults": {
            "pnxTheme": "pro",     // written by Set-Theme
            "pnxStyle": "mac",     // written by Set-Theme
            "colorScheme": "Dracula Pro",
            ...
        }
    }
}
```

## Caching System

### Purpose
`oh-my-posh init` and `zoxide init` are slow (~200–500ms each). Caching their output saves ~400–1000ms per terminal startup.

### Location
`%LOCALAPPDATA%\pnx-terminal\cache\`

### Files
```
cache/
├── omp.ps1       # Cached OMP init script
├── omp.meta      # Version key: "<exe-ticks>|<theme>|<config-ticks>"
├── zoxide.ps1    # Cached zoxide init script
└── zoxide.meta   # Version key: "<exe-ticks>|"
```

### Invalidation
Cache is invalidated when:
- Executable changes (different `LastWriteTimeUtc`)
- Theme/config changes (different ticks or theme name)
- `Clear-PnxCache` is called (by sync-from-repo, or manually)
- Cache file is corrupt (auto-regenerate on `Invoke-Expression` failure)

## Error Handling & Health System

### Health Issues (non-fatal)
Collected during profile load, reported once at the end:
- Oh My Posh not found
- OMP theme file missing
- Terminal-Icons missing
- Nerd Font missing
- WT settings.json unreadable
- Custom theme registry corrupt
- WT font face repair failed

### Fallback Chain
```
configs/themes.json missing?
    → Fallback: ThemeDB = { pro = ... }, StyleDB = { mac = ... }

common.ps1 not loadable?
    → Fallback: inline WT path detection in profile.ps1

WT settings.json unreadable?
    → Skip theme/style detection, use defaults

OMP not installed?
    → Skip prompt init, add health issue

Cache corrupt?
    → Delete cache, regenerate from scratch

Atomic write fails (file locked)?
    → Retry 3x with 200ms delay
    → Last resort: direct Set-Content (non-atomic)
```

## Three-Way Theme Consistency

Each theme requires three synchronized components:

```
configs/themes.json          configs/terminal-settings.json    themes/
──────────────────          ──────────────────────────────    ──────────
theme entry:                 "schemes": [                     pnx-<name>.omp.json
  omp: filename    ────────>   { "name": "<scheme>" } ]      (prompt config)
  scheme: name     ────────>   ↑ must match
  wtTheme: name    ────────> "themes": [
                                { "name": "<wtTheme>" } ]
```

`Test-ThemeIntegrity` validates all three are present and consistent.

## Dependency Graph

```
External Tools                       Project Scripts
──────────────                       ───────────────
oh-my-posh  ◄──── profile.ps1 ────► common.ps1
zoxide      ◄──── profile.ps1       ├── Get-WtSettingsPath
Terminal-Icons ◄── profile.ps1      ├── Save-WtSettings
git         ◄──── bootstrap.ps1     ├── Get/Save-PnxCachedInit
winget      ◄──── install-tools.ps1 ├── Initialize-WtPnxMarkers
scoop       ◄──── install-tools.ps1 ├── Get-NerdFontInfo
                                    └── Repair-WtFontFace

Dot-source chain:
    profile.ps1 ──dot-source──► common.ps1
    bootstrap.ps1 ──dot-source──► common.ps1
    sync-to-repo.ps1 ──dot-source──► common.ps1
    sync-from-repo.ps1 ──dot-source──► common.ps1
    install-tools.ps1 ──dot-source──► common.ps1
    update-tools.ps1 ──dot-source──► common.ps1
    status.ps1 ──dot-source──► common.ps1
```

## Environment Variables

| Variable | Scope | Set By | Used By |
|----------|-------|--------|---------|
| `PNX_TERMINAL_REPO` | User (persistent) | bootstrap.ps1 | profile.ps1, all scripts |
| `PNX_OMP_THEMES` | User (optional) | manual | profile.ps1 (override theme path) |
| `LOCALAPPDATA` | System | Windows | common.ps1 (WT path, cache, registry) |
| `USERPROFILE` | System | Windows | common.ps1 (OMP themes default path) |

## Storage Locations

| What | Where | Managed By |
|------|-------|------------|
| Built-in themes (OMP) | `~/.oh-my-posh/themes/pnx-*.omp.json` | bootstrap, sync-from-repo |
| Custom theme registry | `%LOCALAPPDATA%\pnx-terminal\themes.json` | New-PnxTheme, Remove-PnxTheme |
| Init cache | `%LOCALAPPDATA%\pnx-terminal\cache/` | profile load, Clear-PnxCache |
| WT settings | `%LOCALAPPDATA%\Packages\...\settings.json` | Set-Theme, bootstrap |
| PS profile | `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` | bootstrap, sync-from-repo |
| WT settings backup | `settings.json.pnx-backup` | Save-WtSettings |

## Testing

### Framework
Pester 5 (PowerShell testing framework)

### Test Files

**`tests/common.tests.ps1`** — Tests for shared helpers:
- `Get-WtSettingsPath` (Store/non-Store detection, deploy mode)
- `Get-NerdFontInfo` (registry query, v2/v3 preference)
- Cache system (save, load, key mismatch, clear)
- `Initialize-WtPnxMarkers` (add markers, no overwrite, manifest defaults)
- `Repair-WtFontFace` (edge cases, pre-parsed data)
- `Save-WtSettings` (atomic write, backup creation)

**`tests/profile.tests.ps1`** — Tests for profile data and functions:
- ThemeDB loading from manifest + fallback
- Theme registry merge (custom themes, corruption, no override)
- `New-PnxTheme` validation (duplicates, unknown base, hex format)
- `Remove-PnxTheme` validation (missing registry, non-custom protection)
- StyleDB type correctness (`[int]`, `[bool]` from JSON)

### Running Tests
```powershell
Invoke-Pester ./tests/ -Output Detailed
```

### Test Isolation
- External tools (OMP, zoxide) are mocked
- `$TestDrive` used for temporary files
- Environment variables saved/restored in each test
