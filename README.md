# terminal-workspace

PowerShell 7 + Windows Terminal configuration package.
Clone, bootstrap, done.

## Prerequisites

- Windows 10/11
- [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) (included in Windows 11)

Everything else is installed by the bootstrap script.

## Quick Start

```powershell
git clone https://github.com/DatZ2H/terminal-workspace.git
cd terminal-workspace
.\bootstrap.ps1
```

Restart Windows Terminal after bootstrap completes.

## What's Included

### Tools (auto-installed)

| Tool | Purpose |
|------|---------|
| PowerShell 7 | Shell |
| Oh My Posh | Prompt themes |
| Git | Version control |
| Node.js LTS | JavaScript runtime |
| Python 3.12 | Python runtime |
| Terminal-Icons | File/folder icons in terminal |
| CaskaydiaCove Nerd Font | Icons in prompt |

### Themes (5 color themes)

| Name | Command | Description |
|------|---------|-------------|
| Dracula Pro | `Set-Theme pro` | Softer Dracula, purple-tinted |
| Dracula | `Set-Theme dracula` | Classic high-contrast |
| Tokyo Night | `Set-Theme tokyo` | Blue-indigo, calm |
| Catppuccin Mocha | `Set-Theme mocha` | Warm pastels |
| Nord | `Set-Theme nord` | Arctic, muted tones |

### Styles (3 visual styles)

| Style | Command | Look |
|-------|---------|------|
| mac | `Set-Style mac` | Acrylic blur, wide padding, hidden scrollbar |
| win | `Set-Style win` | Mica material, standard padding |
| linux | `Set-Style linux` | Solid background, block cursor, visible scrollbar |

Combine: `Set-Theme tokyo win` or `Set-Theme nord linux`

## File Structure

```
terminal-workspace/
├── bootstrap.ps1                 # Run once on new machine
├── configs/
│   ├── profile.ps1               # PowerShell profile (source of truth)
│   └── terminal-settings.json    # Windows Terminal settings
├── themes/
│   ├── pnx-dracula-pro.omp.json
│   ├── pnx-dracula.omp.json
│   ├── pnx-tokyo-storm.omp.json
│   ├── pnx-mocha.omp.json
│   └── pnx-nord.omp.json
└── scripts/
    ├── install-tools.ps1         # Install winget packages + PS modules
    ├── install-fonts.ps1         # Install Nerd Font
    ├── update-tools.ps1          # Update all tools
    ├── sync-to-repo.ps1          # Local configs -> repo
    ├── sync-from-repo.ps1        # Repo configs -> local (with backup)
    ├── status.ps1                # Show all tool versions
    └── claude-vn-fix/
        └── patcher.py            # Vietnamese IME fix for Claude Code
```

## Daily Usage

### Theme & Style

```powershell
Set-Theme                     # Show current theme + available options
Set-Theme pro mac             # Switch theme + style
Set-Theme tokyo               # Switch theme only (keep current style)
Set-Style linux               # Switch style only (keep current theme)
```

### Maintenance

```powershell
Get-Status                    # Show versions of all tools
Update-Tools                  # Update OMP, Git, Node.js, modules, font
update-claude                 # Update Claude Code + apply Vietnamese fix
```

### Sync Config

After changing config on current machine:
```powershell
Sync-Config push              # Copy local configs into repo
cd $env:PNX_TERMINAL_REPO
git add -A && git commit -m "update: description" && git push
```

On another machine:
```powershell
cd $env:PNX_TERMINAL_REPO
git pull
Sync-Config pull              # Copy repo configs to local (auto-backup)
```

Or re-run bootstrap:
```powershell
.\bootstrap.ps1 -SkipTools    # Skip tool installation, only deploy configs
```

### Shortcuts

| Command | Action |
|---------|--------|
| `cc` | Alias for `claude` |
| `gc-doc` | Open Claude in guide-claude repo |
| `gs-doc` | Git status in guide-claude repo |
| `Get-Status` | Show tool versions |

## Troubleshooting

**Font icons broken (squares/boxes)**
```powershell
.\scripts\install-fonts.ps1
# Then restart Windows Terminal
```

**OMP prompt not loading**
```powershell
oh-my-posh version             # Should show version number
. $PROFILE                     # Reload profile
```

**Sync-Config says "Repo not found"**
```powershell
# Check env var
$env:PNX_TERMINAL_REPO
# If empty, set it:
[Environment]::SetEnvironmentVariable('PNX_TERMINAL_REPO', 'path\to\terminal-workspace', 'User')
```

**Theme not switching (WT not updating)**
- Make sure Windows Terminal is running (it hot-reloads settings.json)
- Check that `$WtSettingsPath` in profile points to correct location

**Bootstrap on fresh machine without PowerShell 7**
```powershell
# Run from Windows PowerShell 5.1 first:
winget install Microsoft.PowerShell
# Then open PowerShell 7 and run bootstrap
```
