# Pane Management — Design Spec

## Overview

Add pane layout management to the terminal workspace, optimized for Multi-Claude Code CLI workflows. Supports predefined + user-saved layouts, same/different project directories, launchable from both inside and outside Windows Terminal.

**Key decisions:**
- Theme system stays independent — pane management does not interact with themes/styles
- Uses `wt.exe` CLI as the engine (Microsoft-supported, reliable)
- Layout data follows existing ThemeDB pattern (repo JSON + local JSON merge)

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
          "command": "claude | pwsh | null (default shell)",
          "dir": ". (resolves to $PWD or -Dir param) | absolute path",
          "split": "root | vertical | horizontal",
          // "parent" field reserved for V2 — do not use in V1
        }
      ]
    }
  }
}
```

**Field details:**
- `command`: Command to run in the pane. `"claude"` for Claude Code, `"pwsh"` for PowerShell, `null` for default shell.
- `dir`: Working directory. `"."` is resolved at runtime to `$PWD` or the `-Dir` parameter value.
- `split`: `"root"` = first pane (tab), `"vertical"` = split right, `"horizontal"` = split down.
- `parent` (optional): **V1 limitation — sequential split only.** Each pane splits from the previous pane (default behavior). The `parent` field is reserved for future use when WT pane indexing can be reliably mapped. In V1, omit this field.

### Predefined Layouts

| Name | Description | Layout |
|------|-------------|--------|
| `dual-claude` | Two Claude Code instances side by side | `[claude \| claude]` |
| `claude-terminal` | Claude Code + plain shell | `[claude \| pwsh]` |
| `triple-claude` | 3 Claude: 2 top + 1 bottom | `[claude \| claude]` + `[claude below]` (sequential split) |
| `claude-dev` | Claude + terminal + git log | `[claude \| pwsh]` + `[git log below]` (sequential split) |

## Commands & Functions

### Core Functions

| Function | Description | Example |
|----------|-------------|---------|
| `Open-Layout <name> [-Dir <path>] [-NewWindow]` | Open a layout by name | `Open-Layout dual-claude` |
| `Save-Layout <name> [-Panes <config>]` | Save a new layout to local JSON | `Save-Layout my-setup` |
| `Remove-Layout <name>` | Delete a custom layout (predefined are protected) | `Remove-Layout old-setup` |
| `Get-LayoutList` | Display all available layouts (predefined + custom) | `Get-LayoutList` |
| `Get-LayoutCommand <name> [-Dir <path>]` | Output the raw `wt.exe` command string | `Get-LayoutCommand dual-claude` |

### `Open-Layout` Logic

1. Read `$LayoutDB` (already loaded at profile startup)
2. Lookup layout by name → get `panes[]` array
3. Resolve `dir`: `"."` → `-Dir` parameter or `$PWD`
4. Call `Build-WtCommand` (helper in `common.ps1`) → build `wt.exe` argument string
5. Detect context via `$env:WT_SESSION`:
   - **Inside terminal (default)** → prepend `-w 0 nt` (new tab in current window)
   - **Inside terminal + `-NewWindow`** → omit `-w 0` (opens new window)
   - **Outside terminal** → omit `-w 0` (opens new window)
6. Execute `wt.exe` with built arguments

### `Build-WtCommand` Logic

Converts a panes array into `wt.exe` CLI syntax:

```
Input:  panes = [
  { command: "claude", dir: "C:\proj", split: "root" },
  { command: "claude", dir: "C:\proj", split: "vertical" },
  { command: null,     dir: "C:\proj", split: "horizontal" }
]

Output (inside terminal):
  wt.exe -w 0 nt -d "C:\proj" -- claude ; split-pane -V -d "C:\proj" -- claude ; split-pane -H -d "C:\proj"

Output (outside terminal):
  wt.exe -d "C:\proj" -- claude ; split-pane -V -d "C:\proj" -- claude ; split-pane -H -d "C:\proj"
```

Mapping: `vertical` → `-V`, `horizontal` → `-H`. Each pane splits from the previously created pane (sequential).

### `Save-Layout` — Two Modes

**Parameter-only mode** (requires `-Panes`). No interactive prompts — keeps function pipeline-safe:
```powershell
Save-Layout quick -Panes @(
  @{ command="claude"; dir="."; split="root" },
  @{ command="claude"; dir="."; split="vertical" }
)
```

### `Get-LayoutCommand` — Shortcut Generator

Outputs the raw `wt.exe` command for use in `.bat` files or Windows shortcuts:

```powershell
Get-LayoutCommand dual-claude -Dir "C:\myproject"
# → wt.exe -d "C:\myproject" -- claude ; split-pane -V -d "C:\myproject" -- claude
```

### Argument Completion

Tab completion for all layout functions, following existing `Register-ArgumentCompleter` pattern:
- `Open-Layout <Tab>` → all layouts (predefined + custom)
- `Remove-Layout <Tab>` → custom layouts only (predefined protected)

## File Changes

| File | Action | What Changes |
|------|--------|-------------|
| `configs/layouts.json` | **Create** | Predefined layouts data |
| `configs/profile.ps1` | **Edit** | Add layout functions (`Open-Layout`, `Save-Layout`, `Remove-Layout`, `Get-LayoutList`, `Get-LayoutCommand`), `$LayoutDB` loading, argument completers |
| `scripts/common.ps1` | **Edit** | Add `Build-WtCommand` helper |
| `tests/layout.tests.ps1` | **Create** | Pester tests for layout functions |
| `bootstrap.ps1` | **No change** | Layouts load at profile time, no deploy step needed |
| `scripts/sync-to-repo.ps1` | **No change** | `configs/layouts.json` tracked by git |
| `scripts/sync-from-repo.ps1` | **No change** | Layouts reload on next profile load |

## Integration with Existing Systems

### Profile Load (additions)

```
... (existing: ThemeDB, StyleDB, OMP, zoxide) ...
├─ Read configs/layouts.json → $LayoutDB (predefined)
├─ Read %LOCALAPPDATA%\pnx-terminal\layouts.json → merge on top (custom)
└─ Register-ArgumentCompleter for Open-Layout, Remove-Layout
```

### No Bootstrap Changes

Layouts are pure data read at profile load time — same pattern as ThemeDB. No files need to be deployed to external locations.

### Sync Compatibility

- `Sync-Config push`: `configs/layouts.json` is in the repo, synced via git automatically
- `Sync-Config pull`: Next profile reload picks up updated layouts
- Custom layouts in `%LOCALAPPDATA%` stay local-only (same as custom themes)

## `$LayoutDB` Variable

- **Type:** `[hashtable]` — key = layout name, value = `@{ description = [string]; panes = [array] }`
- **Scope:** `$Script:LayoutDB` (same scope as `$ThemeDB`)
- **Merge strategy:** Overwrite by key — custom layout with same name as predefined replaces it entirely (same as ThemeDB custom theme override)
- **Loaded at:** Profile startup, after ThemeDB/StyleDB

## Validation Rules

Validation runs in both `Save-Layout` (write time) and `Open-Layout` (runtime, in case JSON was hand-edited):

1. `panes[0].split` must be `"root"` — error: `"Layout '<name>': first pane must have split 'root'"`
2. `split` values must be one of: `root`, `vertical`, `horizontal`
3. `command`: any non-empty string is valid (e.g., `"claude"`, `"pwsh"`, `"git log --oneline --graph"`). `$null` maps to default shell.
4. `panes` array must have at least 1 entry
5. `dir` must be a valid path or `"."` — warning if absolute path does not exist (non-blocking)
6. `parent` field is ignored in V1 with a warning: `"'parent' field is reserved for future use, ignored in V1"`

## Constraints & Limitations

1. **No auto-detect of current pane state**: Windows Terminal does not expose an API to query open panes. `Save-Layout` requires manual input.
2. **No pane resize**: `wt.exe` supports `--size` at split time but not resizing existing panes. Layouts define split direction only.
3. **`parent` field (V1)**: Reserved for future use. WT's internal pane indexing uses a binary tree that shifts when panes are split, making arbitrary `--target-pane` targeting unreliable. V1 uses sequential splitting only (each pane splits from the previous one).
4. **`$env:WT_SESSION`**: Only exists inside Windows Terminal sessions. Used to detect inside vs. outside context.

## Test Plan

- `Build-WtCommand` unit tests: various pane configs → expected `wt.exe` argument strings
- `Open-Layout` with mocked `wt.exe`: verify correct arguments passed
- `Save-Layout` / `Remove-Layout`: verify local JSON read/write
- `Get-LayoutList`: verify merge of predefined + custom layouts
- Layout validation: reject invalid split values, missing root pane, verify `parent` field is ignored with warning in V1
- Argument completer: verify correct completions for each function
