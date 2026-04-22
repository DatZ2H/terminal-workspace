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
Engine (logic)                  Content (data)
├── scripts/                    ├── configs/themes.json              ← ThemeDB + StyleDB + defaults
│   ├── common.ps1              ├── configs/terminal-settings.json
│   ├── deploy-claude.ps1       ├── configs/claude-settings.template.json ← Claude settings (no secrets)
│   ├── sync-to-repo            ├── configs/statusline.sh           ← Claude statusline script
│   ├── sync-from-repo          ├── configs/claude.md               ← Global CLAUDE.md template
│   └── fix-claude-vn.ps1       ├── themes/*.omp.json               ← OMP prompt configs
├── bootstrap.ps1               └── configs/profile.ps1             ← PS profile (loads JSON)
└── tests/
```

## Key Files

| File | Role |
|------|------|
| `configs/themes.json` | Single source of truth for themes, styles, and defaults |
| `configs/profile.ps1` | PowerShell profile — loads ThemeDB/StyleDB from JSON, inits OMP/zoxide |
| `configs/terminal-settings.json` | WT settings template (schemes + WT themes inline) |
| `scripts/common.ps1` | Shared helpers: WT path, atomic writes, init cache, markers, Claude config helpers |
| `scripts/fix-claude-vn.ps1` | Claude Code Vietnamese IME fix (patches cli.js) |
| `scripts/deploy-claude.ps1` | Deploy Claude Code configs (statusline, settings merge, CLAUDE.md, IME fix) |
| `configs/claude-settings.template.json` | Claude settings template (secrets stripped, portable statusline path) |
| `configs/statusline.sh` | Claude Code statusline script (3-line layout: model, cost, CWD) |
| `configs/claude.md` | Global CLAUDE.md template (Vietnamese rules, emoji policy) |
| `bootstrap.ps1` | First-run setup: install tools, deploy configs, set env vars, Claude setup |
| `themes/*.omp.json` | Oh My Posh prompt theme files (deployed to ~/.oh-my-posh/themes/) |

## Data Flow

1. `bootstrap.ps1` → sets `PNX_TERMINAL_REPO` env var, deploys themes + profile + WT settings
2. Profile load → reads `configs/themes.json` via `$env:PNX_TERMINAL_REPO` → builds ThemeDB/StyleDB
3. `Set-Theme <name>` → updates OMP prompt + WT settings.json (atomic write) + pnx state file
4. `Sync-Config push` → copies local changes back to repo (OMP files, WT settings, Claude configs with secrets stripped)
5. `Sync-Config pull` → deploys from repo to local, deploys Claude configs (additive merge), clears init cache, reloads profile

## ThemeDB Structure

Loaded from `configs/themes.json`. Each theme has:
- `omp`: filename only (e.g., `pnx-dracula-pro.omp.json`) — path prefix added at load time
- `scheme`: WT color scheme name (must exist in terminal-settings.json)
- `wtTheme`: WT theme name (must exist in terminal-settings.json)

Custom themes (created via `New-PnxTheme`) are stored in `%LOCALAPPDATA%\pnx-terminal\themes.json` and merged on top at profile load.

## Critical Invariants

- **Naming convention:** OMP files must be `pnx-*.omp.json`
- **pnx state:** `%LOCALAPPDATA%\pnx-terminal\state.json` stores active theme/style/split (WT-immune)
- **Atomic writes:** WT settings written via `Save-WtSettings` (backup → temp → rename)
- **Cache invalidation:** `Clear-PnxCache` after any config change (OMP/zoxide init cache)
- **Type coercion:** StyleDB values from JSON need explicit `[int]`/`[bool]` cast in PowerShell
- **Terminal-Icons proxy ordering:** Must `Remove-Item` proxy BEFORE `Import-Module` — Terminal-Icons internally calls `Get-ChildItem` which re-enters the proxy and hits module nesting limit

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

Vietnamese IME (OpenKey, EVKey, Unikey) uses backspace+replace technique. Claude Code
2.0.x had a buggy handler for this. **Starting from 2.1.x Anthropic refactored the input
parser** — DEL (0x7F) now routes through tokenizer → `ZI1` key decoder → backspace key
event → `m.backspace()`. Vietnamese IME works natively; no patch required.

`fix-claude-vn.ps1` keeps the legacy patch logic for 2.0.x installs. On 2.1.x+ it
detects the absent legacy pattern and exits cleanly with no changes.

- **Script:** `scripts/fix-claude-vn.ps1` — PowerShell port of [claude-code-vietnamese-fix](https://github.com/manhit96/claude-code-vietnamese-fix)
- **Command:** `Fix-ClaudeVN` — auto-detect and patch (legacy pattern) or no-op (2.1.x+)
- **Restore:** `Fix-ClaudeVN -Restore` — rollback to backup (only exists if legacy patch was applied)
- **Bootstrap:** Runs automatically during `bootstrap.ps1` Phase 2
- **Auto re-run:** `update-tools.ps1` tự gọi `fix-claude-vn.ps1` khi Claude Code version thay đổi (graceful no-op trên 2.1.x+)
- **Patch marker:** `'/* Vietnamese IME fix */'` — dùng khi cần detect legacy patch status

> [!WARNING]
> **Do not** patch the 2.1.x DEL ground branch (`A.push({type:"text", value:"<DEL>"})`). The raw DEL byte inside the `value` string is essential — ZI1 maps DEL → backspace via literal-byte comparison (`q==="<DEL>"`). Any rewrite that replaces the raw byte with a `"\x7f"` escape literal breaks the routing. Leave 2.1.x cli.js untouched.

## Claude Code Config Management

Two-pillar system: Terminal (themes/styles/WT) + Claude Code (statusline/settings/CLAUDE.md).

- **Deploy:** `Deploy-ClaudeConfig [-Force]` — runs `scripts/deploy-claude.ps1`
- **Settings merge:** Additive-only — `mcpServers` protected (never touched), `statusLine` always overwritten (repo = source of truth), existing user values preserved
- **Secret stripping:** `Sync-Config push` strips secrets (github_pat_, ghp_, sk-, tokens) before writing template to repo
- **Bootstrap Phase 2:** Gated on Claude Code being installed — Steps 7-8 (detect + deploy)
- **Template:** `configs/claude-settings.template.json` uses `bash ~/.claude/statusline.sh` (portable path)

## Update Tools Architecture

`scripts/update-tools.ps1` has 3 update channels:
- **Winget:** PS7, WT, OMP, Git, Node.js, Python — pre-check via `winget upgrade` (no args, one call)
- **Scoop:** zoxide, ripgrep — pre-check via `scoop status`
- **Claude Code:** pre-check via `npm view @anthropic-ai/claude-code version` vs `claude --version`; update via `claude update` (native self-updater — handles both npm-global and native installer transparently)

Pre-check phase runs first, shows available updates, exits early if nothing to update.
Winget skips packages already up-to-date (saves ~30s). WT has specific error message for file lock.

> [!NOTE]
> Workspace previously used `npm install -g @anthropic-ai/claude-code@latest` for Claude Code updates. After `claude migrate-installer` (or a fresh 2.x install) the active binary lives under `~/.claude/local/` — npm global writes don't replace it. `claude update` is the portable command for both install types.

## Common Claude Tasks

- **Adding themes:** Edit `configs/themes.json` + create OMP file + add scheme/WT theme
- **Fixing sync issues:** Check `scripts/sync-to-repo.ps1` and `sync-from-repo.ps1`
- **Updating engine:** Edit `configs/profile.ps1` (ThemeDB loading, Set-Theme logic)
- **Shared helpers:** Edit `scripts/common.ps1` (WT path, atomic writes, cache, markers)
