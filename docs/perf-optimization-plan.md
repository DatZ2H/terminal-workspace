# Profile Performance Optimization Plan

> **Context:** Research conducted 2026-03-18. Profile load measured at ~1224ms.
> **Target:** < 300ms (below human perception threshold).
> **Constraint:** Keep Oh My Posh — do NOT switch to Starship.
> **Requirements:** OMP v19+, PowerShell 7.0+ (7.3+ recommended for full optimization).

## Current Bottleneck Summary

Benchmark on PS 7.5.4, OMP v29.8.0, Windows 11:

```
Phase                          Uncached    Cached (current)
─────────────────────────────  ──────────  ────────────────
common.ps1 dot-source            125ms       125ms
themes.json parse                  1ms         1ms
Build ThemeDB+StyleDB             12ms        12ms
WT settings.json parse            11ms        11ms
OMP init (spawn process)         226ms       226ms ← cache BROKEN
OMP Invoke-Expression            264ms       264ms ← should be dot-source
Nerd Font registry check          34ms        34ms
zoxide init                      143ms         2ms (cached)
zoxide Invoke-Expression          33ms        33ms
PSReadLine config                144ms       144ms
Terminal-Icons import            440ms         0ms (proxy + OnIdle on PS 7.3+)
```

### Critical Finding: OMP Cache Is Broken

The PnxCachedInit system caches OMP's output, which is only 138 bytes:
```powershell
$env:POSH_SESSION_ID = "..."; & 'C:\...\oh-my-posh\init.384840657.ps1'
```
This is a **redirect**, not the actual init code. The real init script is at
`%LOCALAPPDATA%\oh-my-posh\init.*.ps1` (627 lines, 24KB). Caching the redirect
means Invoke-Expression still has to parse+compile 627 lines every time.

**Dot-source the file directly is 2x faster than Invoke-Expression:**
- `Invoke-Expression`: 486ms
- `. $file`: 246ms

---

## Approved Optimizations (A, B, D, E, F)

### A+B. Fix OMP Init: Dot-source + Skip Spawn on Cache Hit (~466ms saved)

**What to change:** `configs/profile.ps1`, OMP init section — search for
`# ===== Oh My Posh`.

**Current flow:**
```
1. oh-my-posh init pwsh --config $cfg | Out-String  → 226ms (spawn .exe)
2. $output | Invoke-Expression                       → 264ms (parse+compile 627 lines via redirect)
```

**New flow (cache miss):**
```
1. oh-my-posh init pwsh --config $cfg | Out-Null    → creates/updates init.*.ps1
2. Find latest init.*.ps1 in %LOCALAPPDATA%\oh-my-posh\
3. . $initFile.FullName                              → 246ms (dot-source, 1x only)
4. Save init file path + OMP exe path to PnxCachedInit
```

**New flow (cache hit):**
```
1. Read cached init file path
2. Verify file still exists (Test-Path)
3. . $cachedPath                                     → ~18ms (dot-source, file already warm)
   Total: ~20ms
```

**Implementation:**
```powershell
# ===== Oh My Posh (init with detected theme — cached) =====
$_ompConfig = $ThemeDB[$Global:PnxCurrentTheme].omp

# --- Helper: find OMP init file created by `oh-my-posh init` ---
function _Find-OmpInitFile {
    $ompInitDir = Join-Path $env:LOCALAPPDATA 'oh-my-posh'
    if (Test-Path $ompInitDir) {
        Get-ChildItem $ompInitDir -Filter 'init.*.ps1' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
}

# --- Helper: dot-source with Invoke-Expression fallback (AppLocker safety) ---
function _Load-OmpInit ([string]$Path) {
    $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
    try {
        . $Path
    } catch {
        # Dot-source blocked (AppLocker/CLM) — fallback to Invoke-Expression
        try {
            $content = Get-Content $Path -Raw
            $content | Invoke-Expression
        } catch {
            Write-Warning "OMP init failed from: $Path"
        }
    }
}

# --- Helper: cleanup stale init files older than 7 days ---
function _Cleanup-OmpInitFiles {
    $ompInitDir = Join-Path $env:LOCALAPPDATA 'oh-my-posh'
    if (Test-Path $ompInitDir) {
        $cutoff = (Get-Date).AddDays(-7)
        Get-ChildItem $ompInitDir -Filter 'init.*.ps1' |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $_ompConfig)) {
    $_healthIssues += "OMP theme file missing — run: Update-Workspace"
} else {
    # Resolve OMP exe — portable: no hardcoded paths
    $_ompExe = (Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source
    if (-not $_ompExe) {
        $_healthIssues += "Oh My Posh not found — run: winget install JanDeDobbeleer.OhMyPosh"
    } else {
        $_ompVer = (Get-Item $_ompExe).LastWriteTimeUtc.Ticks.ToString()
        $_ompCfgTicks = (Get-Item $_ompConfig).LastWriteTimeUtc.Ticks.ToString()
        $_ompExtra = "$($Global:PnxCurrentTheme)|$_ompCfgTicks"

        # Try cache: stores path to init file (not script content)
        $_ompCachedPath = if (Get-Command Get-PnxCachedInit -ErrorAction SilentlyContinue) {
            Get-PnxCachedInit -Name 'omp' -VersionKey $_ompVer -ExtraKey $_ompExtra
        } else { $null }

        $_ompLoaded = $false

        # --- Cache hit: dot-source directly, skip spawning oh-my-posh.exe ---
        if ($_ompCachedPath -and (Test-Path $_ompCachedPath)) {
            try {
                _Load-OmpInit $_ompCachedPath
                $_ompLoaded = $true
            } catch {
                # Corrupt/stale — clear cache, will regenerate below
                Remove-Item (Join-Path $PnxCacheDir "omp.*") -Force -ErrorAction SilentlyContinue
            }
        }

        # --- Cache miss: spawn OMP to create/update init file, then dot-source ---
        if (-not $_ompLoaded) {
            & $_ompExe init pwsh --config $_ompConfig | Out-Null
            $_initFile = _Find-OmpInitFile

            if ($_initFile) {
                # OMP v19+: init file created on disk — dot-source it
                _Load-OmpInit $_initFile.FullName
                if (Get-Command Save-PnxCachedInit -ErrorAction SilentlyContinue) {
                    Save-PnxCachedInit -Name 'omp' -VersionKey $_ompVer -ExtraKey $_ompExtra -Content $_initFile.FullName
                }
                # Cleanup stale files (safe: only removes files > 7 days old)
                _Cleanup-OmpInitFiles
            } else {
                # OMP v14-v18 fallback: no init file on disk — use Invoke-Expression
                $_ompInit = & $_ompExe init pwsh --config $_ompConfig | Out-String
                if ($_ompInit -and $_ompInit.Trim().Length -gt 0) {
                    $_ompInit | Invoke-Expression
                } else {
                    $_healthIssues += "OMP init produced no output — check oh-my-posh version (v19+ required for best performance)"
                }
            }
        }
    }
}

# Cleanup helper functions (not needed after init)
Remove-Item Function:\_Find-OmpInitFile, Function:\_Load-OmpInit, Function:\_Cleanup-OmpInitFiles -ErrorAction SilentlyContinue
```

**Key design decisions:**
- **No hardcoded paths** — uses `Get-Command` for OMP exe (portable across winget/scoop/choco/store)
- Cache stores **file path** (not script content) — the cached value is a path string
- **Dot-source with Invoke-Expression fallback** — handles AppLocker/Constrained Language Mode
- **OMP v14-v18 fallback** — if no `init.*.ps1` found, falls back to `Invoke-Expression` (old behavior)
- **7-day cleanup** — only removes init files older than 7 days (multi-tab safe)
- `$env:POSH_SESSION_ID` set manually (OMP needs it for session tracking)
- Helper functions are removed after init to keep global scope clean

**Compatibility matrix:**

```
Scenario                      Behavior                    Performance
──────────────────────────    ────────────────────────    ──────────
OMP v19+ (winget)             dot-source init file        ~20ms cached
OMP v19+ (scoop/choco)        dot-source init file        ~20ms cached
OMP v14-v18                   Invoke-Expression fallback  ~490ms (same as before)
OMP not installed             health warning              0ms
AppLocker blocks dot-source   Invoke-Expression fallback  ~264ms
Cache miss (first boot)       spawn + dot-source          ~246ms
Cache miss (OMP upgraded)     spawn + dot-source          ~246ms
Init file deleted externally  Test-Path fails → regen     ~246ms
```

---

### D. Defer PSReadLine Prediction to OnIdle (~100ms saved)

**What to change:** `configs/profile.ps1`, PSReadLine section — search for
`# ===== PSReadLine`.

**Implementation:**
```powershell
# ===== PSReadLine (batched for fewer calls) =====
$_pslOpts = @{
    EditMode                      = 'Windows'
    BellStyle                     = 'None'
    MaximumHistoryCount           = 10000
    HistoryNoDuplicates           = $true
    HistorySearchCursorMovesToEnd = $true
    ShowToolTips                  = $true
}
Set-PSReadLineOption @_pslOpts
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z -Function Undo
Set-PSReadLineKeyHandler -Key Ctrl+w -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Remove-Variable _pslOpts -ErrorAction SilentlyContinue

# Defer prediction engine (heavy init) — needs PSReadLine 2.2.0+ and PS 7.3+ for OnIdle
$_pslVersion = (Get-Module PSReadLine -ErrorAction SilentlyContinue).Version
if ($_pslVersion -and $_pslVersion -ge [Version]"2.2.0") {
    if ($PSVersionTable.PSVersion -ge [Version]"7.3") {
        # PS 7.3+: defer to OnIdle (~500ms after prompt, before user types)
        Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
            Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView
        } | Out-Null
    } else {
        # PS 7.0-7.2: no OnIdle — set synchronously (same as current behavior)
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView
    }
}
Remove-Variable _pslVersion -ErrorAction SilentlyContinue
```

**Compatibility:**
- PS 7.3+: deferred → saves ~100ms
- PS 7.0–7.2: synchronous → same as current (no regression)
- PSReadLine < 2.2.0: prediction not available → no change

---

### E. Defer Nerd Font Check to OnIdle (~34ms saved)

**What to change:** `configs/profile.ps1`, Nerd Font section — search for
`# ===== Nerd Font check`.

**Implementation:**
```powershell
# ===== Nerd Font check (deferred — font changes are rare) =====
if ($PSVersionTable.PSVersion -ge [Version]"7.3") {
    # PS 7.3+: defer to OnIdle (font check is not time-critical)
    # Capture $WtSettingsPath in closure since OnIdle runs in a different scope
    $_wtPathForFontCheck = $WtSettingsPath
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        $_fontInfo = if (Get-Command Get-NerdFontInfo -ErrorAction SilentlyContinue) {
            Get-NerdFontInfo
        } else { $null }

        if (-not $_fontInfo -or -not $_fontInfo.Installed) {
            if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
                try { oh-my-posh font install CascadiaCode *>$null } catch {}
            } else {
                Write-Host "  PNX: CaskaydiaCove Nerd Font missing — run: oh-my-posh font install CascadiaCode" -ForegroundColor Yellow
            }
        }

        # Auto-fix stale font face name (v2 <-> v3)
        if ($_fontInfo -and (Get-Command Repair-WtFontFace -ErrorAction SilentlyContinue)) {
            try {
                Repair-WtFontFace -WtPath $using:_wtPathForFontCheck -FontInfo $_fontInfo | Out-Null
            } catch {}
        }
    } | Out-Null
    Remove-Variable _wtPathForFontCheck -ErrorAction SilentlyContinue
} else {
    # PS < 7.3: run synchronously (same as current behavior)
    $_fontInfo = if (Get-Command Get-NerdFontInfo -ErrorAction SilentlyContinue) { Get-NerdFontInfo } else { $null }
    if (-not $_fontInfo -or -not $_fontInfo.Installed) {
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            try {
                oh-my-posh font install CascadiaCode *>$null
                if ($LASTEXITCODE -eq 0) { $_fontInfo = @{ Installed = $true } }
            } catch {}
        }
        if (-not $_fontInfo -or -not $_fontInfo.Installed) {
            $_healthIssues += "CaskaydiaCove Nerd Font missing (icons broken) — run: oh-my-posh font install CascadiaCode"
        }
    }
    if (Get-Command Repair-WtFontFace -ErrorAction SilentlyContinue) {
        try {
            Repair-WtFontFace -WtPath $WtSettingsPath -WtJson $_wtJson -FontInfo $_fontInfo | Out-Null
        } catch {
            $_healthIssues += "WT font face repair failed: $_"
        }
    }
    Remove-Variable _wtJson, _fontInfo -ErrorAction SilentlyContinue
}
```

**Note on `$using:` scope:** OnIdle scriptblocks run in a separate scope. Use
`$using:_wtPathForFontCheck` to pass the WT settings path captured before
registration. If `$using:` is not supported in your PS version for engine events,
assign to a `$Global:` variable instead.

**Compatibility:**
- PS 7.3+: deferred → saves ~34ms
- PS < 7.3: synchronous → same as current (no regression)

---

### F. Cleanup Stale OMP Init Files (hygiene)

Already included in the A+B implementation above via `_Cleanup-OmpInitFiles`.
Removes init files **older than 7 days** (multi-tab safe). Runs only on cache miss.

---

## Implementation Order

1. **A+B first** — biggest impact (~466ms), self-contained in OMP init section
2. **D next** — simple (~100ms), isolated change in PSReadLine section
3. **E last** — requires scope handling for WtSettingsPath (~34ms)

After each step: run verification, confirm no regression, then proceed.

## Verification

After implementing, run this benchmark:
```powershell
# Benchmark with cache (simulates normal terminal open)
pwsh -NoProfile -Command {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    . $PROFILE
    $sw.Stop()
    Write-Host "Profile load: $($sw.ElapsedMilliseconds)ms"
}

# Benchmark without cache (simulates first boot / post-update)
pwsh -NoProfile -Command {
    Remove-Item "$env:LOCALAPPDATA\pnx-terminal\cache\omp.*" -Force -ErrorAction SilentlyContinue
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    . $PROFILE
    $sw.Stop()
    Write-Host "Profile load (cold): $($sw.ElapsedMilliseconds)ms"
}
```

**Targets:**
- Warm cache: < 300ms
- Cold cache: < 500ms

## Expected Results

```
                            Before       After (PS 7.3+)   After (PS 7.0-7.2)
                            ────────     ───────────────    ──────────────────
OMP init (warm cache)        490ms         ~20ms              ~20ms
OMP init (cold)              490ms        ~246ms             ~246ms
PSReadLine prediction        144ms         ~44ms              144ms (no change)
Nerd Font check               34ms          0ms*              34ms (no change)
────────────────────────     ────────     ───────────────    ──────────────────
Total saved (warm)                         ~600ms             ~470ms
Estimated total (warm)       ~864ms        ~260ms             ~394ms
                                                  * = deferred to OnIdle
```

## Deferred Optimizations (C, G)

Lower priority, implement later if needed:

- **C (double-parse themes.json):** Refactor common.ps1 to accept defaults via parameter
  instead of parsing themes.json itself. Saves ~10-15ms. Requires changes to
  bootstrap.ps1 and sync-from-repo.ps1 callers.

- **G (reduce Get-Command calls):** Cache resolved paths after first Get-Command lookup.
  Saves ~20ms. Can be done without hardcoding — store resolved path in PnxCachedInit.

## Conflict Avoidance

This plan references code by **section markers** (not line numbers) to stay valid
even if the file changes before implementation:

- OMP init section = block starting with `# ===== Oh My Posh`
- PSReadLine section = block starting with `# ===== PSReadLine`
- Nerd Font section = block starting with `# ===== Nerd Font check`

If profile.ps1 has been restructured, search for these section markers.
The implementation blocks are self-contained and can be adapted to any layout.

## Risk Summary for Release

| User scenario | A+B (OMP) | D (PSReadLine) | E (Font) |
|---|---|---|---|
| winget + PS 7.3+ | dot-source (~20ms) | deferred | deferred |
| scoop/choco + PS 7.3+ | dot-source (~20ms) | deferred | deferred |
| PS 7.0-7.2 | dot-source (~20ms) | sync (no regression) | sync (no regression) |
| OMP v14-v18 | Invoke-Expression fallback (no regression) | works | works |
| OMP not installed | health warning | works | works |
| AppLocker/CLM | Invoke-Expression fallback | works | works |
| Multi-tab user | 7-day cleanup (safe) | works | works |
| First boot (no cache) | spawn + dot-source (~246ms) | works | works |

**No user scenario results in a regression from current behavior.**
