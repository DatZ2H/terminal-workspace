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
          "parent": 0  // optional: index of pane to split from (default: previous pane)
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
- `parent` (optional): Zero-based index of the pane to split from. Defaults to the previous pane in the array. Enables complex layouts (e.g., L-shaped).

### Predefined Layouts

| Name | Description | Layout |
|------|-------------|--------|
| `dual-claude` | Two Claude Code instances side by side | `[claude \| claude]` |
| `claude-terminal` | Claude Code + plain shell | `[claude \| pwsh]` |
| `triple-claude` | 3 Claude: 2 top + 1 bottom | `[claude \| claude]` + `[claude below pane 0]` |
| `claude-dev` | Claude + terminal + git log | `[claude \| pwsh]` + `[git log below pane 1]` |

## Commands & Functions

### Core Functions

| Function | Description | Example |
|----------|-------------|---------|
| `Open-Layout <name> [-Dir <path>]` | Open a layout by name | `Open-Layout dual-claude` |
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
   - **Inside terminal** → prepend `-w 0` (target current window)
   - **Outside terminal** → omit `-w 0` (opens new window)
6. Execute `wt.exe` with built arguments

### `Build-WtCommand` Logic

Converts a panes array into `wt.exe` CLI syntax:

```
Input:  panes = [
  { command: "claude", dir: "C:\proj", split: "root" },
  { command: "claude", dir: "C:\proj", split: "vertical" },
  { command: null,     dir: "C:\proj", split: "horizontal", parent: 0 }
]

Output: -d "C:\proj" -- claude ; split-pane -V -d "C:\proj" -- claude ; split-pane -H -s 0 -d "C:\proj"
```

Mapping: `vertical` → `-V`, `horizontal` → `-H`, `parent` → `-s <index>` (WT `--target-pane` flag).

### `Save-Layout` — Two Modes

**Interactive mode** (no `-Panes` parameter):
```
Save-Layout my-workflow
→ How many panes? 3
→ Pane 1: command? claude  | dir? .  | split? root
→ Pane 2: command? claude  | dir? .  | split? vertical
→ Pane 3: command? (enter) | dir? .  | split? horizontal | parent? 0
→ Saved "my-workflow" to local layouts.json
```

**One-liner mode** (with `-Panes`):
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
| `configs/profile.ps1` | **Edit** | Add layout functions + `$LayoutDB` loading + argument completers |
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

## Constraints & Limitations

1. **No auto-detect of current pane state**: Windows Terminal does not expose an API to query open panes. `Save-Layout` requires manual input.
2. **No pane resize**: `wt.exe` supports `--size` at split time but not resizing existing panes. Layouts define split direction only.
3. **`parent` index**: Uses zero-based index into the panes array. WT's `--target-pane` flag maps to the order panes were created, which matches our array order.
4. **`$env:WT_SESSION`**: Only exists inside Windows Terminal sessions. Used to detect inside vs. outside context.

## Test Plan

- `Build-WtCommand` unit tests: various pane configs → expected `wt.exe` argument strings
- `Open-Layout` with mocked `wt.exe`: verify correct arguments passed
- `Save-Layout` / `Remove-Layout`: verify local JSON read/write
- `Get-LayoutList`: verify merge of predefined + custom layouts
- Layout validation: reject invalid split values, missing root pane, circular parent references
- Argument completer: verify correct completions for each function
