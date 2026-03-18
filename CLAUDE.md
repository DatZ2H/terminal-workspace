# CLAUDE.md — Terminal Workspace

## Project Purpose

PowerShell 7 + Windows Terminal theme management system. Provides:
- 14 built-in themes (OMP prompts + color schemes + WT themes)
- 3 terminal styles (mac/win/linux — opacity, acrylic, padding)
- One-command theme switching: `Set-Theme tokyo mac`
- Interactive theme picker: `Set-Theme` (no args)
- Theme scaffolding: `New-PnxTheme -Name myTheme -BasedOn pro`
- Sync between repo and local machine: `Sync-Config push|pull`

## Architecture

```
Engine (logic)          Content (data)
├── scripts/            ├── configs/themes.json    ← ThemeDB + StyleDB + defaults
│   ├── common.ps1      ├── configs/terminal-settings.json
│   ├── sync-to-repo    ├── themes/*.omp.json      ← OMP prompt configs
│   └── sync-from-repo  └── configs/profile.ps1    ← PS profile (loads JSON)
├── bootstrap.ps1
└── tests/
```

## Key Files

| File | Role |
|------|------|
| `configs/themes.json` | Single source of truth for themes, styles, and defaults |
| `configs/profile.ps1` | PowerShell profile — loads ThemeDB/StyleDB from JSON, inits OMP/zoxide |
| `configs/terminal-settings.json` | WT settings template (schemes + WT themes inline) |
| `scripts/common.ps1` | Shared helpers: WT path detection, atomic writes, init cache, markers |
| `bootstrap.ps1` | First-run setup: install tools, deploy configs, set env vars |
| `themes/*.omp.json` | Oh My Posh prompt theme files (deployed to ~/.oh-my-posh/themes/) |

## Data Flow

1. `bootstrap.ps1` → sets `PNX_TERMINAL_REPO` env var, deploys themes + profile + WT settings
2. Profile load → reads `configs/themes.json` via `$env:PNX_TERMINAL_REPO` → builds ThemeDB/StyleDB
3. `Set-Theme <name>` → updates OMP prompt + WT settings.json (atomic write) + pnx markers
4. `Sync-Config push` → copies local changes back to repo (OMP files, WT settings)
5. `Sync-Config pull` → deploys from repo to local, clears init cache, reloads profile

## ThemeDB Structure

Loaded from `configs/themes.json`. Each theme has:
- `omp`: filename only (e.g., `pnx-dracula-pro.omp.json`) — path prefix added at load time
- `scheme`: WT color scheme name (must exist in terminal-settings.json)
- `wtTheme`: WT theme name (must exist in terminal-settings.json)

Custom themes (created via `New-PnxTheme`) are stored in `%LOCALAPPDATA%\pnx-terminal\themes.json` and merged on top at profile load.

## Critical Invariants

- **Naming convention:** OMP files must be `pnx-*.omp.json`
- **pnx markers:** `pnxTheme`/`pnxStyle` in WT `profiles.defaults` track active theme/style
- **Atomic writes:** WT settings written via `Save-WtSettings` (backup → temp → rename)
- **Cache invalidation:** `Clear-PnxCache` after any config change (OMP/zoxide init cache)
- **Type coercion:** StyleDB values from JSON need explicit `[int]`/`[bool]` cast in PowerShell

## How to Add a New Theme

1. Add entry to `configs/themes.json` under `themes`
2. Create `themes/pnx-<name>.omp.json` (copy + modify existing)
3. Add color scheme to `configs/terminal-settings.json` → `schemes[]`
4. Add WT theme to `configs/terminal-settings.json` → `themes[]`
5. Run `Test-ThemeIntegrity` to verify all 3 components present

## Test Commands

```powershell
# Run all tests
Invoke-Pester ./tests/ -Output Detailed

# Run specific test file
Invoke-Pester ./tests/profile.tests.ps1 -Output Detailed
Invoke-Pester ./tests/common.tests.ps1 -Output Detailed

# Validate PS1 syntax (no execution)
[System.Management.Automation.Language.Parser]::ParseFile("configs/profile.ps1", [ref]$null, [ref]$null)
```

## Claude Code Vietnamese IME Fix

Fixes Vietnamese input in Claude Code CLI. Vietnamese IME (OpenKey, EVKey, Unikey)
uses backspace+replace technique that Claude Code doesn't handle correctly.

- **Script:** `scripts/fix-claude-vn.ps1` — PowerShell port of [claude-code-vietnamese-fix](https://github.com/manhit96/claude-code-vietnamese-fix)
- **Command:** `Fix-ClaudeVN` — auto-detect and patch `cli.js`
- **Restore:** `Fix-ClaudeVN -Restore` — rollback to backup
- **Bootstrap:** Runs automatically during `bootstrap.ps1` (Step 7)
- **After update:** Run `Fix-ClaudeVN` after each Claude Code npm update

## Common Claude Tasks

- **Adding themes:** Edit `configs/themes.json` + create OMP file + add scheme/WT theme
- **Fixing sync issues:** Check `scripts/sync-to-repo.ps1` and `sync-from-repo.ps1`
- **Updating engine:** Edit `configs/profile.ps1` (ThemeDB loading, Set-Theme logic)
- **Shared helpers:** Edit `scripts/common.ps1` (WT path, atomic writes, cache, markers)
