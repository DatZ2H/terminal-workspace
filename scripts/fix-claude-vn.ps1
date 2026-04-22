#Requires -Version 7.0
# Claude Code Vietnamese IME Fix (PowerShell port)
# Patches cli.js to handle Vietnamese IME backspace+insert correctly.
#
# Original: https://github.com/manhit96/claude-code-vietnamese-fix
# Ported to PowerShell for Terminal Workspace integration.
#
# Usage:
#   .\fix-claude-vn.ps1              Auto-detect and fix
#   .\fix-claude-vn.ps1 -Restore     Restore from backup
#   .\fix-claude-vn.ps1 -Path FILE   Fix specific file

[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Restore
)

# Ensure UTF-8 output (script may run before profile sets encoding)
[console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$PatchMarker = '/* Vietnamese IME fix */'
$DelChar = [char]127  # 0x7F - character used by Vietnamese IME for backspace
$MaxBackups = 3

function Find-ClaudeCliJs {
    <#
    .SYNOPSIS
    Auto-detect Claude Code npm cli.js location on Windows.
    #>
    $searchDirs = @(
        (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'),
        (Join-Path $env:APPDATA 'npm\node_modules')
    )

    # nvm-windows: detect from npm prefix or NVM_SYMLINK
    if ($env:NVM_SYMLINK) {
        $searchDirs += (Join-Path $env:NVM_SYMLINK 'node_modules')
    }
    try {
        $npmPrefix = (npm config get prefix 2>$null)
        if ($npmPrefix -and (Test-Path $npmPrefix)) {
            $searchDirs += (Join-Path $npmPrefix 'node_modules')
        }
    } catch {}

    foreach ($dir in $searchDirs) {
        if (-not $dir -or -not (Test-Path $dir)) { continue }
        $found = Get-ChildItem $dir -Recurse -Filter 'cli.js' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '@anthropic-ai[\\/]claude-code[\\/]cli\.js$' } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "Khong tim thay Claude Code npm cli.js.`nCai dat truoc: npm install -g @anthropic-ai/claude-code"
}

function Find-BugBlock {
    <#
    .SYNOPSIS
    Find the if-block containing the Vietnamese IME bug pattern (Claude Code <= 2.0.x).
    Returns: start index, end index, block text. Returns $null if pattern absent.
    #>
    param([string]$Content)

    $pattern = ".includes(`"$DelChar`")"
    $idx = $Content.IndexOf($pattern)

    if ($idx -eq -1) { return $null }

    # Find the containing if(
    $searchStart = [Math]::Max(0, $idx - 150)
    $searchRegion = $Content.Substring($searchStart, $idx - $searchStart)
    $ifPos = $searchRegion.LastIndexOf('if(')
    if ($ifPos -eq -1) {
        throw "Khong tim thay block if chua pattern"
    }
    $blockStart = $searchStart + $ifPos

    # Find matching closing brace (scan up to 5000 chars for safety)
    $depth = 0
    $blockEnd = -1
    $maxLen = [Math]::Min(5000, $Content.Length - $blockStart)
    for ($i = 0; $i -lt $maxLen; $i++) {
        $c = $Content[$blockStart + $i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $blockEnd = $blockStart + $i + 1
                break
            }
        }
    }

    if ($depth -ne 0) {
        throw "Khong tim thay closing brace cua block if"
    }

    $blockText = $Content.Substring($blockStart, $blockEnd - $blockStart)
    return @{ Start = $blockStart; End = $blockEnd; Text = $blockText }
}

function Get-BugVariables {
    <#
    .SYNOPSIS
    Extract dynamic variable names from the bug block.
    #>
    param([string]$Block)

    # Normalize DEL char for regex
    $normalized = $Block.Replace([string]$DelChar, '\x7f')

    # Match: let COUNT=(INPUT.match(/\x7f/g)||[]).length,STATE=CURSTATE;
    if ($normalized -notmatch 'let ([\w$]+)=\([\w$]+\.match\(/\\x7f/g\)\|\|\[\]\)\.length[,;]([\w$]+)=([\w$]+)[;,]') {
        throw "Khong trich xuat duoc bien count/state"
    }
    $stateVar = $Matches[2]
    $curStateVar = $Matches[3]

    # Match: UPDATETEXT(STATE.text);UPDATEOFFSET(STATE.offset)
    $escapedState = [regex]::Escape($stateVar)
    if ($Block -notmatch "([\w`$]+)\($escapedState\.text\);([\w`$]+)\($escapedState\.offset\)") {
        throw "Khong trich xuat duoc update functions"
    }
    $updateText = $Matches[1]
    $updateOffset = $Matches[2]

    # Match: INPUT.includes("
    if ($Block -notmatch '([\w$]+)\.includes\("') {
        throw "Khong trich xuat duoc input variable"
    }
    $inputVar = $Matches[1]

    return @{
        inputVar      = $inputVar
        stateVar      = $stateVar
        curStateVar   = $curStateVar
        updateText    = $updateText
        updateOffset  = $updateOffset
    }
}

function New-FixCode {
    <#
    .SYNOPSIS
    Generate the fix code: backspace + insert replacement text.
    #>
    param([hashtable]$V, [string]$Marker)

    $i = $V.inputVar; $s = $V.stateVar; $cs = $V.curStateVar
    $ut = $V.updateText; $uo = $V.updateOffset

    return (
        "${Marker}" +
        "if(${i}.includes(`"\x7f`")){" +
        "let _n=(${i}.match(/\x7f/g)||[]).length," +
        "_vn=${i}.replace(/\x7f/g,`"`")," +
        "${s}=${cs};" +
        "for(let _i=0;_i<_n;_i++)${s}=${s}.backspace();" +
        "for(const _c of _vn)${s}=${s}.insert(_c);" +
        "if(!${cs}.equals(${s})){" +
        "if(${cs}.text!==${s}.text)" +
        "${ut}(${s}.text);" +
        "${uo}(${s}.offset)" +
        "}return;}"
    )
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
    Keep only the N most recent backups, remove the rest.
    #>
    param([string]$FilePath, [int]$Keep = $MaxBackups)

    $dir = Split-Path $FilePath -Parent
    $filename = Split-Path $FilePath -Leaf
    Get-ChildItem $dir -Filter "$filename.backup-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Invoke-Patch {
    <#
    .SYNOPSIS
    Apply Vietnamese IME fix to cli.js.
    #>
    param([string]$FilePath)

    Write-Host "  -> File: $FilePath" -ForegroundColor DarkGray

    if (-not (Test-Path $FilePath)) {
        Write-Host "  File khong ton tai: $FilePath" -ForegroundColor Red
        return $false
    }

    $content = Get-Content $FilePath -Raw -Encoding utf8

    # Already patched?
    if ($content.Contains($PatchMarker)) {
        Write-Host "  Da patch truoc do." -ForegroundColor Green
        return $true
    }

    # Only the legacy pattern (Claude Code <= 2.0.x: `.includes("\x7f")`) needs patching.
    # Starting from 2.1.x Anthropic refactored cli.js into a state-machine parser that
    # already routes DEL (0x7F) through the key decoder as a backspace event — Vietnamese
    # IME works natively. If the legacy pattern is absent, we exit cleanly without touching
    # cli.js.
    $block = Find-BugBlock -Content $content
    if (-not $block) {
        Write-Host "  Khong tim thay bug pattern cu (legacy)." -ForegroundColor DarkGray
        Write-Host "  Claude Code 2.1.x tu xu ly Vietnamese IME — khong can patch." -ForegroundColor Green
        return $true
    }

    # Backup (only when we're actually going to patch)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$FilePath.backup-$timestamp"
    Copy-Item $FilePath $backupPath -Force
    Write-Host "  Backup: $backupPath" -ForegroundColor DarkGray

    try {
        $vars = Get-BugVariables -Block $block.Text
        Write-Host "  Legacy patch: input=$($vars.inputVar), state=$($vars.stateVar), cur=$($vars.curStateVar)" -ForegroundColor DarkGray
        $fixCode = New-FixCode -V $vars -Marker $PatchMarker
        $patched = $content.Substring(0, $block.Start) + $fixCode + $content.Substring($block.End)

        # Write
        [System.IO.File]::WriteAllText($FilePath, $patched, [System.Text.UTF8Encoding]::new($false))

        # Verify
        $verify = Get-Content $FilePath -Raw -Encoding utf8
        if (-not $verify.Contains($PatchMarker)) {
            throw "Verify failed: patch marker not found after write"
        }

        # Cleanup old backups (keep last N)
        Remove-OldBackups -FilePath $FilePath

        Write-Host "  Patch thanh cong! Khoi dong lai Claude Code." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Loi: $_" -ForegroundColor Red
        Write-Host "  Bao loi tai: https://github.com/manhit96/claude-code-vietnamese-fix/issues" -ForegroundColor DarkGray

        # Rollback
        if (Test-Path $backupPath) {
            Copy-Item $backupPath $FilePath -Force
            Remove-Item $backupPath -Force
            Write-Host "  Da rollback ve ban goc." -ForegroundColor Yellow
        }
        return $false
    }
}

function Invoke-Restore {
    <#
    .SYNOPSIS
    Restore cli.js from latest backup.
    #>
    param([string]$FilePath)

    $dir = Split-Path $FilePath -Parent
    $filename = Split-Path $FilePath -Leaf
    $backups = Get-ChildItem $dir -Filter "$filename.backup-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Host "  Khong tim thay backup cho $FilePath" -ForegroundColor Red
        return $false
    }

    $latest = $backups[0].FullName
    Copy-Item $latest $FilePath -Force
    Write-Host "  Da khoi phuc tu: $latest" -ForegroundColor Green
    Write-Host "  Khoi dong lai Claude Code." -ForegroundColor DarkGray
    return $true
}

# ===== Main =====
Write-Host ""
Write-Host "  Claude Code Vietnamese IME Fix" -ForegroundColor Cyan
Write-Host "  --------------------------------" -ForegroundColor DarkGray

try {
    $filePath = if ($Path) { $Path } else { Find-ClaudeCliJs }

    if ($Restore) {
        $result = Invoke-Restore -FilePath $filePath
    } else {
        $result = Invoke-Patch -FilePath $filePath
    }

    Write-Host ""
    if (-not $result -and -not $Restore) { exit 1 }
}
catch {
    Write-Host "  Loi: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}
