# Pane Management & Cheatsheet — Design Spec

## Overview

Add pane layout management and a discoverable cheatsheet to the terminal workspace. Optimized for Multi-Claude Code CLI workflows but works for any terminal use case. Supports predefined + user-saved layouts, same/different project directories, launchable from both inside and outside Windows Terminal.

**Key decisions:**
- Theme system stays independent — pane management does not interact with themes/styles
- Uses `wt.exe` CLI as the engine (Microsoft-supported, reliable)
- Layout data follows existing ThemeDB pattern (repo JSON + local JSON merge)
- **Security: no raw commands in JSON** — uses WT profile names + whitelisted launch args instead
- Pane functions extracted to separate file (`scripts/pane-layout.ps1`) to keep profile.ps1 manageable

## Data Model

### File Locations

| File | Role |
|------|------|
| `configs/layouts.json` | Predefined layouts (shipped with repo) |
| `%LOCALAPPDATA%\pnx-terminal\layouts.json` | User-saved layouts (local only, merged on top) |

### Schema: `layouts.json`

```jsonc
{
  "defaultLayout": "dual-claude",
  "layouts": {
    "<layout-name>": {
      "description": "Human-readable description",
      "panes": [
        {
          "profile": "PowerShell | Claude | null (WT default profile)",
          "dir": ". (resolves to $PWD or -Dir param) | absolute path",
          "split": "root | vertical | horizontal",
          "title": "optional pane title",
          "size": 0.5,
          // "parent" field reserved for V2 — do not use in V1
        }
      ]
    }
  }
}
```

**Field details:**
- `profile`: Windows Terminal profile name (must exist in WT `profiles.list[]`). `null` = WT default profile. Validated against installed profiles at runtime.
- `dir`: Working directory. `"."` is resolved at runtime to `$PWD` or the `-Dir` parameter value.
- `split`: `"root"` = first pane (tab), `"vertical"` = split right, `"horizontal"` = split down.
- `title` (optional): Pane tab title. Passed as `--title` to `wt.exe`.
- `size` (optional): Split ratio as float 0.0–1.0 (default 0.5). Passed as `--size` to `wt.exe`.
- `parent` (optional): **V1 limitation — sequential split only.** Each pane splits from the previous pane. Reserved for V2.

### WT Profile Mapping

Layouts reference WT profile names, not raw commands. This provides security (no arbitrary command execution) and integration (inherits profile's icon, font, color scheme, startup command).

Expected WT profiles (validated at runtime):
- `"PowerShell"` — default pwsh profile (used by all predefined layouts)
- `"Command Prompt"` — cmd.exe
- `"Claude"` — optional custom WT profile with `commandline: "claude"` (created via `New-ClaudeProfile` helper)
- `null` — WT default profile

If a referenced profile does not exist, `Open-Layout` warns and falls back to the default profile.

**Claude profile strategy:** All predefined layouts use `"PowerShell"` by default so they work out-of-the-box. Users who want dedicated Claude panes can:
1. Run `New-ClaudeProfile` (helper function) to inject a `Claude` WT profile into settings.json
2. Create custom layouts referencing `"Claude"` profile
3. Or manually create the profile in WT Settings UI

### Predefined Layouts

| Name | Description | Layout |
|------|-------------|--------|
| `dual-pane` | Two shells side by side | `[PowerShell \| PowerShell]` |
| `triple-pane` | 3 panes: 2 top + 1 bottom | `[PowerShell \| PowerShell]` + `[PowerShell below]` |
| `dev-monitor` | Shell + shell + monitoring pane | `[PowerShell \| PowerShell]` + `[PowerShell below]` |
| `side-by-side` | Two shells for compare/review | `[PowerShell \| PowerShell]` |

All predefined layouts use the `"PowerShell"` profile for maximum compatibility. Users can create custom layouts with `"Claude"` or other profiles after running `New-ClaudeProfile`.

## Commands & Functions

### Pane Functions

| Function | Description | Example |
|----------|-------------|---------|
| `Open-Layout <name> [-Dir <path>] [-NewWindow]` | Open a layout by name | `Open-Layout dual-claude` |
| `Save-Layout <name> -Panes <config> [-Description <text>]` | Save a new layout to local JSON | `Save-Layout my-setup -Panes @(...)` |
| `Remove-Layout <name>` | Delete a custom layout (predefined are protected) | `Remove-Layout old-setup` |
| `Get-LayoutList` | Display all available layouts (predefined + custom) | `Get-LayoutList` |
| `Get-LayoutCommand <name> [-Dir <path>]` | Output the raw `wt.exe` command string | `Get-LayoutCommand dual-pane` |
| `New-ClaudeProfile` | Inject a `Claude` WT profile into settings.json | `New-ClaudeProfile` |

### Cheatsheet Function

| Function | Description | Example |
|----------|-------------|---------|
| `Show-Cheatsheet [<category>]` | Display categorized command reference | `Show-Cheatsheet pane` |

Categories: `theme`, `pane`, `config`, `keys`, `all` (default).

**Output example:**
```
 PNX Terminal Cheatsheet
─────────────────────────────────────────────

 THEME
  Set-Theme <name> [style]     Switch theme (e.g., Set-Theme tokyo mac)
  Get-ThemeList                 Show all available themes
  Set-Style <style>             Switch style only (mac/win/linux)
  Select-ThemeInteractive       Arrow-key theme picker
  New-PnxTheme -Name <n> ...   Create custom theme
  Test-ThemeIntegrity           Validate theme components

 PANE LAYOUTS
  Open-Layout <name>            Open a pane layout
  Open-Layout <name> -NewWindow Open in new window
  Get-LayoutList                Show all layouts
  Save-Layout <name> -Panes .. Save custom layout
  Get-LayoutCommand <name>      Export wt.exe command
  New-ClaudeProfile             Create Claude WT profile

 CONFIG
  Sync-Config push|pull         Sync local <-> repo
  Update-Workspace              Pull + redeploy + reload
  Get-Status                    Health check
  Update-Tools                  Update all packages
  Deploy-ClaudeConfig           Deploy Claude configs

 KEYBOARD SHORTCUTS (Windows Terminal)
  Alt+Shift+D                   Auto split pane
  Alt+Shift++ / Alt+Shift+-     Split vertical / horizontal
  Alt+Arrow                     Move focus between panes
  Alt+Shift+Arrow               Resize pane
  Ctrl+Shift+W                  Close pane
  Ctrl+Shift+T                  New tab
  Ctrl+Tab / Ctrl+Shift+Tab     Next / previous tab

  Type Show-Cheatsheet <category> to filter.
```

### Welcome Line

Added to profile load output (after health check):

```
PNX Terminal | tokyo (mac) | Show-Cheatsheet for help
```

Single line, non-intrusive. Only shown in interactive sessions (not in scripts).

### `Open-Layout` Logic

1. Guard: check `wt.exe` available → if not, `Write-Warning` and return
2. Read `$LayoutDB` (already loaded at profile startup)
3. Lookup layout by name → if not found, list available layouts and return
4. Validate panes (see Validation Rules)
5. Resolve `dir`: `"."` → `-Dir` parameter or `$PWD`
6. Validate all `dir` paths exist → warn (non-blocking) for missing paths
7. Validate all `profile` names exist in WT → warn and fall back to default for missing profiles
8. Call `Build-WtCommand` (helper in `scripts/pane-layout.ps1`) → build argument list
9. Detect context via `$env:WT_SESSION`:
   - **Inside terminal (default)** → prepend `-w 0 nt` (new tab in current window)
   - **Inside terminal + `-NewWindow`** → omit `-w 0` (opens new window)
   - **Outside terminal** → omit `-w 0` (opens new window)
10. Execute via `Start-Process wt -ArgumentList $args` (safe, no string interpolation)

### `Build-WtCommand` Logic

Converts a panes array into `wt.exe` argument list (returns `[string[]]`, NOT a concatenated string):

```
Input:  panes = [
  { profile: "Claude", dir: "C:\proj", split: "root" },
  { profile: "Claude", dir: "C:\proj", split: "vertical", size: 0.4 },
  { profile: "PowerShell", dir: "C:\proj", split: "horizontal" }
]

Output (inside terminal):
  @('-w', '0', 'nt', '-p', 'Claude', '-d', 'C:\proj',
    ';', 'split-pane', '-V', '--size', '0.4', '-p', 'Claude', '-d', 'C:\proj',
    ';', 'split-pane', '-H', '-p', 'PowerShell', '-d', 'C:\proj')
```

Mapping: `vertical` → `-V`, `horizontal` → `-H`, `profile` → `-p`, `<name>` (two separate array elements — `Start-Process` handles quoting), `title` → `--title`, `<text>`, `size` → `--size`, `<float>`.

**WT profile validation timing:** Profiles are validated at `Open-Layout` call time (not cached at profile load). This reads WT `settings.json` once per `Open-Layout` invocation to check `profiles.list[].name`. Acceptable cost (~2ms) and ensures renamed/new profiles are detected immediately.

### `Save-Layout`

**Parameter-only mode** (requires `-Panes`). No interactive prompts — keeps function pipeline-safe.

**Overwrite behavior:** If a custom layout with the same name already exists, it is silently overwritten (consistent with `New-PnxTheme` using `Add-Member -Force`). Predefined layouts cannot be overwritten — `Save-Layout` with a predefined name returns an error.

```powershell
Save-Layout my-setup -Description "My daily workflow" -Panes @(
  @{ profile="Claude"; dir="."; split="root" },
  @{ profile="PowerShell"; dir="."; split="vertical" }
)
```

### `Get-LayoutCommand` — Shortcut Generator

Outputs the raw `wt.exe` command for use in `.bat` files or Windows shortcuts (NOT for direct PowerShell paste — `;` is a wt.exe subcommand separator, not a PowerShell statement separator):

```powershell
Get-LayoutCommand dual-pane -Dir "C:\myproject"
# → wt.exe -p "PowerShell" -d "C:\myproject" ; split-pane -V -p "PowerShell" -d "C:\myproject"
# (copy this into a .bat file or Windows shortcut target)
```

### Argument Completion

Tab completion for all layout functions, following existing `Register-ArgumentCompleter` pattern:
- `Open-Layout <Tab>` → all layouts (predefined + custom)
- `Remove-Layout <Tab>` → custom layouts only (predefined protected)
- `Show-Cheatsheet <Tab>` → `theme`, `pane`, `config`, `keys`, `all`

## File Changes

| File | Action | What Changes |
|------|--------|-------------|
| `configs/layouts.json` | **Create** | Predefined layouts data |
| `scripts/pane-layout.ps1` | **Create** | All pane functions + `Build-WtCommand` + `Show-Cheatsheet` |
| `configs/profile.ps1` | **Edit** | Dot-source `pane-layout.ps1`, load `$LayoutDB`, add welcome line, register argument completers |
| `tests/layout.tests.ps1` | **Create** | Pester tests for layout + cheatsheet functions |
| `bootstrap.ps1` | **No change** | Layouts load at profile time, no deploy step needed |
| `scripts/sync-to-repo.ps1` | **No change** | `configs/layouts.json` tracked by git |
| `scripts/sync-from-repo.ps1` | **No change** | Layouts reload on next profile load |

## Integration with Existing Systems

### Profile Load (additions)

```
... (existing: ThemeDB, StyleDB, OMP, zoxide) ...
├─ Dot-source scripts/pane-layout.ps1
├─ Read configs/layouts.json → $LayoutDB (predefined)
├─ Read %LOCALAPPDATA%\pnx-terminal\layouts.json → merge on top (custom)
├─ Check wt.exe availability → add to $_healthIssues if missing
├─ Register-ArgumentCompleter for Open-Layout, Remove-Layout, Show-Cheatsheet
└─ Welcome line: "PNX Terminal | <theme> (<style>) | Show-Cheatsheet for help"
```

### No Bootstrap Changes

Layouts are pure data read at profile load time — same pattern as ThemeDB. No files need to be deployed to external locations.

### Sync Compatibility

- `Sync-Config push`: `configs/layouts.json` is in the repo, synced via git automatically
- `Sync-Config pull`: Next profile reload picks up updated layouts
- Custom layouts in `%LOCALAPPDATA%` stay local-only (same as custom themes)

## `$LayoutDB` Variable

- **Type:** `[hashtable]` — key = layout name, value = `@{ description = [string]; panes = [array] }`
- **Scope:** `$LayoutDB` (no `$Script:` prefix — consistent with `$ThemeDB`)
- **Merge strategy:** Predefined wins — custom layouts with the same name as a predefined layout are ignored (same as ThemeDB: `if (-not $LayoutDB.ContainsKey($name)) { ... }`). Users who want variants should use distinct names (e.g., `my-dual-claude`).
- **Loaded at:** Profile startup, after ThemeDB/StyleDB

## Validation Rules

Validation runs in both `Save-Layout` (write time) and `Open-Layout` (runtime, in case JSON was hand-edited):

1. `panes[0].split` must be `"root"` — error: `"Layout '<name>': first pane must have split 'root'"`
2. `split` values must be one of: `root`, `vertical`, `horizontal`
3. `profile`: must be `$null` or a string matching an installed WT profile name. Unknown profiles → warning + fallback to WT default
4. `panes` array must have at least 1 entry
5. `dir` must be `"."` or a valid path — warning (non-blocking) if absolute path does not exist
6. `size` (if present): must be a float in the range (0.0, 1.0) — exclusive on both ends (0.0 and 1.0 are invalid)
7. `parent` field is ignored in V1 with a warning: `"'parent' field is reserved for future use, ignored in V1"`

## Risk Analysis & Mitigation

### Critical

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Command injection via layout data** | Arbitrary code execution if layouts.json stores raw commands | **Eliminated by design:** `profile` field references WT profile names only (validated against installed profiles). No raw command strings in JSON. Execution via `Start-Process` with argument array, never string interpolation. |
| **`wt.exe` not installed** | All pane functions fail | Guard check at profile load (`Get-Command wt -EA SilentlyContinue`). Add to `$_healthIssues`. Functions return early with `Write-Warning`. Other workspace features unaffected. |

### Medium

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Corrupted `layouts.json`** | Layout loading fails | Try/catch around `ConvertFrom-Json`. Add to `$_healthIssues`. Profile continues loading. Follows existing ThemeDB pattern. |
| **Paths with special characters** | `wt.exe` argument parsing breaks | Use `Start-Process -ArgumentList` with array (not string concat). Each argument is a separate array element — shell escaping handled by .NET. |
| **Non-existent directory in `dir`** | `wt.exe` opens to wrong/default dir | `Test-Path` check before execution. Warning for missing paths. Non-blocking (pane still opens with fallback dir). |
| **Missing WT profile referenced in layout** | `wt.exe` error or falls back silently | Query installed profiles via WT settings.json `profiles.list[].name`. Warn + use default profile for unknown names. |
| **`%LOCALAPPDATA%` write failure** | Cannot save custom layouts | Try/catch on directory creation + file write. Fallback to `$env:TEMP\pnx-terminal`. Health warning. |
| **Profile load time increase** | Terminal opens slower | `layouts.json` is small (<5KB). Single `ConvertFrom-Json` call adds <5ms. No caching needed — unlike OMP/zoxide init which take 100-500ms. |

### Low

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Function name conflicts** | Overwrites user's custom function | No conflicts found with built-in cmdlets or common modules. Verb-Noun convention matches existing functions. |
| **`$env:WT_SESSION` false negative** | Opens new window instead of new tab | Edge case with nested terminals or custom environments. Documented in Constraints. `-NewWindow` flag provides explicit control. |
| **Concurrent `Set-Theme` + `Open-Layout`** | No conflict — different mechanisms | `Set-Theme` writes `settings.json` via `Save-WtSettings`. `Open-Layout` calls `wt.exe` CLI (creates panes, does not write settings). No shared resource. |

## Constraints & Limitations

1. **No auto-detect of current pane state**: Windows Terminal does not expose an API to query open panes. `Save-Layout` requires manual input via `-Panes` parameter.
2. **No pane resize after creation**: `wt.exe` supports `--size` at split time but not resizing existing panes. Use keyboard shortcuts (`Alt+Shift+Arrow`) for manual resize.
3. **`parent` field (V1)**: Reserved for future use. WT's internal pane indexing uses a binary tree that shifts when panes are split, making arbitrary `--target-pane` targeting unreliable. V1 uses sequential splitting only.
4. **`$env:WT_SESSION`**: Only exists inside Windows Terminal sessions. Used to detect inside vs. outside context.
5. **WT profile dependency**: Layouts reference WT profile names. If a profile is renamed or deleted, layouts referencing it will fall back to default with a warning.
6. **`Claude` WT profile**: Optional. Created via `New-ClaudeProfile` helper (injects profile with `commandline: "claude"` into WT settings.json using `Save-WtSettings`). Not required — all predefined layouts use `"PowerShell"`. Users opt in when ready.
7. **`description` field**: Optional in layout schema. `Get-LayoutList` shows empty string if omitted.

## Test Plan

- `Build-WtCommand` unit tests: various pane configs → expected argument arrays
- `Build-WtCommand` with `size` and `title` fields → verify `--size` and `--title` flags
- `Open-Layout` with mocked `Start-Process`: verify correct arguments passed
- `Open-Layout` inside vs outside terminal: verify `-w 0 nt` presence/absence
- `Open-Layout` with `-NewWindow`: verify `-w 0` is omitted
- `Open-Layout` with missing `wt.exe`: verify warning and early return
- `Open-Layout` with missing WT profile: verify fallback + warning
- `Open-Layout` with non-existent `dir`: verify warning (non-blocking)
- `Save-Layout` / `Remove-Layout`: verify local JSON read/write
- `Remove-Layout` on predefined layout: verify rejection
- `Get-LayoutList`: verify merge of predefined + custom layouts
- Layout validation: reject invalid split values, missing root pane, invalid size range
- `parent` field: verify ignored with warning in V1
- `Show-Cheatsheet`: verify output for each category filter
- `Show-Cheatsheet` with unknown category: verify error message
- Corrupted `layouts.json`: verify graceful degradation + health warning
- `Save-Layout` overwrite existing custom: verify silent overwrite
- `Save-Layout` with predefined name: verify error rejection
- `New-ClaudeProfile`: verify profile injected into WT settings.json
- `New-ClaudeProfile` when profile already exists: verify skip with message
- `Get-LayoutList`: verify predefined wins over custom with same name
- `Get-LayoutCommand` output: verify `;` separator correct for batch/shortcut use
- Argument completer: verify correct completions for each function
