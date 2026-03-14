# Shared constants and helpers — single source of truth
# Dot-source this from any script that needs WT path or version constants.

# ── Version Constants ──
$PythonVersion = "3.12"

# ── WT Settings Path Detection (Store + non-Store) ──
# Two modes:
#   "file"   — returns path only if the file exists (for reading/reporting)
#   "deploy" — returns path if the parent dir exists (for writing — file may not exist yet)
function Get-WtSettingsPath {
    param(
        [ValidateSet('file', 'deploy')]
        [string]$Mode = 'file'
    )
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json")
    )
    if ($Mode -eq 'deploy') {
        $candidates | Where-Object { Test-Path (Split-Path $_ -Parent) } | Select-Object -First 1
    } else {
        $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}
