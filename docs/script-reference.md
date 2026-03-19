# Script Reference — Terminal Workspace

Quick reference for all PowerShell scripts, their purpose, parameters, and dependencies.

## Entry Points

### `bootstrap.bat`

Windows batch wrapper that launches `bootstrap.ps1` with ExecutionPolicy bypass. Works from CMD, PowerShell 5, or PowerShell 7.

```cmd
.\bootstrap.bat
.\bootstrap.bat -SkipTools
```

### `bootstrap.ps1`

Full setup script. Installs tools, deploys configs, sets environment variables.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-SkipTools` | Switch | Skip tool installation (only deploy configs) |

**Steps:** ExecutionPolicy → install-tools → install-fonts → deploy themes → deploy WT settings (atomic) → deploy profile → set PNX_TERMINAL_REPO

**Dependencies:** Dot-sources `scripts/common.ps1`

### `update.ps1`

Standalone updater. Works even if profile is broken.

```powershell
.\update.ps1
```

**Steps:** git pull → sync-from-repo.ps1 → reload profile

---

## Scripts

### `scripts/common.ps1`

Shared utility library. Dot-sourced by all other scripts and profile.

**Constants:**

| Name | Value | Purpose |
|------|-------|---------|
| `$PythonVersion` | `"3.12"` | Python version to install |
| `$MaxBackups` | `3` | Number of backup files to keep |
| `$OmpThemesLocal` | `~/.oh-my-posh/themes` | OMP themes directory |
| `$PsProfilePath` | `Documents/PowerShell/Microsoft.PowerShell_profile.ps1` | Profile path |
| `$PnxCacheDir` | `%LOCALAPPDATA%/pnx-terminal/cache` | Cache directory |

**Functions:**

| Function | Returns | Purpose |
|----------|---------|---------|
| `Get-WtSettingsPath [-Mode file\|deploy]` | string/null | Find WT settings.json path |
| `Get-NerdFontInfo` | PSCustomObject | Detect Nerd Font {Installed, HasV3, HasV2, FontFace} |
| `Repair-WtFontFace -WtPath -WtJson -FontInfo` | bool | Fix stale v2↔v3 font name in WT |
| `Save-WtSettings -Json -WtPath` | bool | Atomic JSON write with backup + retry |
| `Get-PnxCachedInit -Name -VersionKey -ExtraKey` | string/null | Read cached init script |
| `Save-PnxCachedInit -Name -VersionKey -ExtraKey -Content` | void | Write init script to cache |
| `Clear-PnxCache` | void | Delete all cache files |
| `Initialize-WtPnxMarkers -WtJson [-DefaultTheme] [-DefaultStyle]` | bool | Inject pnx markers |

**Manifest defaults:** Reads `configs/themes.json` at load time via `$PSScriptRoot` to set `$_pnxDefaults` for `Initialize-WtPnxMarkers` default parameters.

---

### `scripts/fix-claude-vn.ps1`

Patches Claude Code CLI (`cli.js`) to fix Vietnamese IME input (backspace+replace technique used by OpenKey, EVKey, Unikey).

**No dependencies** — standalone script, no dot-sourcing needed.

**How it works:** Finds `cli.js` in the npm global prefix, backs up the original, then patches the readline handling to correctly process Vietnamese IME keystrokes.

**Profile command:** `Fix-ClaudeVN` (defined in `profile.ps1`)

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `-Restore` | `$false` | Rollback to backup instead of patching |

**Called by:** `bootstrap.ps1` Step 7 (auto-runs during first setup)

---

### `scripts/install-tools.ps1`

Installs all project dependencies.

**Dependencies:** Dot-sources `common.ps1`; requires `winget`

**Tools installed:**

| Tool | Method | ID |
|------|--------|----|
| PowerShell 7 | winget | `Microsoft.PowerShell` |
| Oh My Posh | winget | `JanDeDobbeleer.OhMyPosh` |
| Git | winget | `Git.Git` |
| Node.js LTS | winget | `OpenJS.NodeJS.LTS` |
| Python 3.12 | winget | `Python.Python.3.12` |
| Scoop | script | `get.scoop.sh` (integrity-checked) |
| zoxide | scoop | `zoxide` |
| ripgrep | scoop | `ripgrep` |
| Terminal-Icons | PS module | `Install-Module` |

**Exit code:** 0 = all OK, 1 = some tools failed

---

### `scripts/install-fonts.ps1`

Installs CaskaydiaCove Nerd Font via Oh My Posh.

**Dependencies:** `oh-my-posh` must be installed

**Note:** Non-admin installs font per-user only.

---

### `scripts/update-tools.ps1`

Updates all installed tools.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Force` | Switch | Skip confirmation prompt |

**Dependencies:** Dot-sources `common.ps1`

**Updates:** winget packages (OMP, Git, Node, Python) + Terminal-Icons module + Scoop packages + Nerd Font

---

### `scripts/sync-to-repo.ps1`

Copies local machine configs back to the repository.

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Force` | Switch | Skip confirmation prompt |

**Dependencies:** Dot-sources `common.ps1`

**Copies:**
1. `$PROFILE` → `configs/profile.ps1`
2. WT settings → `configs/terminal-settings.json` (strips `environment` vars for security)
3. `pnx-*.omp.json` → `themes/`

---

### `scripts/sync-from-repo.ps1`

Deploys repo configs to local machine.

**Dependencies:** Dot-sources `common.ps1`

**Steps:**
1. Backup + copy `configs/profile.ps1` → `$PROFILE`
2. Read `terminal-settings.json` → inject pnx markers → atomic write → WT settings
3. Copy `themes/*.omp.json` → `~/.oh-my-posh/themes/`
4. `Clear-PnxCache` (force fresh init on next terminal open)

**Backup management:** Keeps last 3 backups (configurable via `$MaxBackups`)

---

### `scripts/status.ps1`

Displays version info for all tools and config status.

**Dependencies:** Dot-sources `common.ps1`

**Reports on:**
- Tool versions: PowerShell, OMP, Git, Node.js, Python, npm, PSReadLine, Terminal-Icons, Scoop, zoxide, ripgrep
- Config locations: PS Profile, WT Settings, OMP Themes directory
- Nerd Font: installed version (v2/v3), WT font face match
- Theme count: number of `pnx-*.omp.json` files deployed

---

## Profile Commands

These are defined in `configs/profile.ps1` and available after profile loads:

### Theme Management

```powershell
Set-Theme                           # Interactive picker (TUI)
Set-Theme <theme>                   # Switch theme (keep current style)
Set-Theme <theme> <style>           # Switch both
Set-Style <style>                   # Switch style only
Get-ThemeList                       # Display all themes with active marker
Test-ThemeIntegrity [-Quiet]        # Validate OMP/scheme/WT consistency
```

### Custom Themes

```powershell
New-PnxTheme -Name <n> -BasedOn <b> [-Scheme <s>] [-Background <hex>] [-WhatIf]
Remove-PnxTheme -Name <n> [-WhatIf]
```

### Maintenance

```powershell
Sync-Config push [-Force]           # Local → repo
Sync-Config pull                    # Repo → local + reload
Update-Tools [-Force]               # Update all tools
Update-Workspace                    # Git pull + redeploy + reload
Get-Status                          # Show versions and config status
Fix-ClaudeVN                        # Patch Claude Code for Vietnamese IME
Fix-ClaudeVN -Restore               # Rollback Claude Code patch
```

### Tab Completion

Available for: `Set-Theme -Theme`, `Set-Theme -Style`, `Set-Style -Style`, `New-PnxTheme -BasedOn`, `Remove-PnxTheme -Name`
