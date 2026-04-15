#!/bin/bash
# Claude Code Status Line - 3-line layout
# Line 1: Model + Output style + Git branch + Context bar
# Line 2: Cost + Duration + Tokens (in/out) + Cache hit ratio
# Line 3: CWD (shortened)

# Read JSON from stdin
INPUT=$(cat)

# ANSI colors
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
WHITE='\033[37m'
MAGENTA='\033[35m'
BLUE='\033[34m'

# ── Extract values using simple parsing ──

# Model name
MODEL=$(echo "$INPUT" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$MODEL" ] && MODEL="Claude"

# Output style
OUT_STYLE=$(echo "$INPUT" | sed -n 's/.*"output_style".*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Context used % — anchored to "remaining_percentage" which only follows the context_window one,
# avoiding false match on rate_limits.{five_hour,seven_day}.used_percentage
CTX_PCT=$(echo "$INPUT" | sed -n 's/.*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\)[[:space:]]*,[[:space:]]*"remaining_percentage".*/\1/p' | head -1)

# Context window size (200000 default, 1000000 for extended)
CW_SIZE=$(echo "$INPUT" | sed -n 's/.*"context_window_size"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Cost
COST=$(echo "$INPUT" | sed -n 's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)

# Duration ms
DUR_MS=$(echo "$INPUT" | sed -n 's/.*"total_duration_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Session cumulative tokens (top-level context_window.total_*)
SESS_IN=$(echo "$INPUT" | sed -n 's/.*"total_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
SESS_OUT=$(echo "$INPUT" | sed -n 's/.*"total_output_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Live tokens from context_window.current_usage (field names unique, no scoping needed on single-line JSON)
LIVE_IN=$(echo "$INPUT" | sed -n 's/.*[^l]"input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
LIVE_OUT=$(echo "$INPUT" | sed -n 's/.*[^l]"output_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Cache tokens (nested inside current_usage)
CACHE_READ=$(echo "$INPUT" | sed -n 's/.*"cache_read_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
CACHE_CREATE=$(echo "$INPUT" | sed -n 's/.*"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Total live context tokens = what's actually loaded in context right now
if [ -n "$LIVE_IN" ] && [ -n "$CACHE_CREATE" ] && [ -n "$CACHE_READ" ]; then
    LIVE_CTX=$((LIVE_IN + CACHE_CREATE + CACHE_READ))
fi

# Rate limits (Pro/Max only — may be absent). Use scoped awk-sed on multi-line; for single-line JSON, head -1 on ordered occurrence.
RL_5H=$(echo "$INPUT" | sed -n 's/.*"five_hour"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)
RL_7D=$(echo "$INPUT" | sed -n 's/.*"seven_day"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)

# exceeds_200k flag
EXCEEDS_200K=$(echo "$INPUT" | sed -n 's/.*"exceeds_200k_tokens"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)

# API duration (for "thinking vs waiting" ratio)
API_MS=$(echo "$INPUT" | sed -n 's/.*"total_api_duration_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Lines of code changed
LINES_ADD=$(echo "$INPUT" | sed -n 's/.*"total_lines_added"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
LINES_REM=$(echo "$INPUT" | sed -n 's/.*"total_lines_removed"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Session name (optional — only when user ran /rename or --name)
SESSION_NAME=$(echo "$INPUT" | sed -n 's/.*"session_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Git worktree (optional — only inside a linked worktree)
GIT_WORKTREE=$(echo "$INPUT" | sed -n 's/.*"git_worktree"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Rate limit reset epochs (scoped by preceding block name, no closing brace in between)
RL_5H_RESET=$(echo "$INPUT" | sed -n 's/.*"five_hour"[^}]*"resets_at"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
RL_7D_RESET=$(echo "$INPUT" | sed -n 's/.*"seven_day"[^}]*"resets_at"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# CWD
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$CWD" ] && CWD="$(pwd)"

# Git branch (cached 5s)
CACHE_FILE="/tmp/.statusline-git-cache"
CACHE_MAX_AGE=5
NOW=$(date +%s)
if [ -f "$CACHE_FILE" ]; then
    CACHE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - CACHE_TIME))
else
    AGE=$((CACHE_MAX_AGE + 1))
fi
if [ "$AGE" -gt "$CACHE_MAX_AGE" ]; then
    GIT_BRANCH=$(git -C "${CWD//\\//}" branch --show-current 2>/dev/null)
    echo "$GIT_BRANCH" > "$CACHE_FILE" 2>/dev/null
else
    GIT_BRANCH=$(cat "$CACHE_FILE" 2>/dev/null)
fi

# ── Progress bar ──

build_bar() {
    local pct=$1
    local width=15
    local filled=$(printf "%.0f" "$(awk "BEGIN{print $pct * $width / 100}" 2>/dev/null || echo 0)")
    [ "$filled" -gt "$width" ] 2>/dev/null && filled=$width
    [ "$filled" -lt 0 ] 2>/dev/null && filled=0
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Color by threshold
    local color="$GREEN"
    local pct_int=${pct%.*}
    [ "$pct_int" -ge 60 ] 2>/dev/null && color="$YELLOW"
    [ "$pct_int" -ge 80 ] 2>/dev/null && color="$RED"

    printf "%b%s%b" "$color" "$bar" "$RST"
}

pct_color() {
    local pct_int=${1%.*}
    [ "$pct_int" -ge 80 ] 2>/dev/null && { printf "%b" "$RED"; return; }
    [ "$pct_int" -ge 60 ] 2>/dev/null && { printf "%b" "$YELLOW"; return; }
    printf "%b" "$GREEN"
}

# ── Format helpers ──

format_duration() {
    local ms=$1
    local total_sec=$((ms / 1000))
    local h=$((total_sec / 3600))
    local m=$(( (total_sec % 3600) / 60 ))
    local s=$((total_sec % 60))

    if [ "$h" -gt 0 ]; then
        printf "%dh%dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf "%dm%ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

format_tokens() {
    local t=$1
    if [ "$t" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(awk "BEGIN{print $t / 1000000}" 2>/dev/null)"
    elif [ "$t" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(awk "BEGIN{print $t / 1000}" 2>/dev/null)"
    else
        printf "%d" "$t"
    fi
}

format_cw_size() {
    local s=$1
    if [ "$s" -ge 1000000 ] 2>/dev/null; then
        printf "%dM" "$((s / 1000000))"
    elif [ "$s" -ge 1000 ] 2>/dev/null; then
        printf "%dk" "$((s / 1000))"
    else
        printf "%s" "$s"
    fi
}

format_reset_time() {
    # Convert Unix epoch to relative delta like "4d12h" or "45m"
    local target=$1
    local now
    now=$(date +%s)
    local delta=$((target - now))
    if [ "$delta" -le 0 ] 2>/dev/null; then
        echo "now"
        return
    fi
    local d=$((delta / 86400))
    local h=$(( (delta % 86400) / 3600 ))
    local m=$(( (delta % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then
        printf "%dd%dh" "$d" "$h"
    elif [ "$h" -gt 0 ]; then
        printf "%dh%dm" "$h" "$m"
    else
        printf "%dm" "$m"
    fi
}

format_burn_rate() {
    # Returns $/h given (cost_usd, duration_ms). Only when duration > 60s to avoid noise.
    local cost=$1
    local dur_ms=$2
    if [ "$dur_ms" -lt 60000 ] 2>/dev/null; then
        return
    fi
    awk "BEGIN{printf \"%.1f\", $cost * 3600000 / $dur_ms}" 2>/dev/null
}

cost_color() {
    # Green < $5, yellow $5-$15, red ≥ $15
    local c=$1
    local c_int=${c%.*}
    [ "$c_int" -ge 15 ] 2>/dev/null && { printf "%b" "$RED"; return; }
    [ "$c_int" -ge 5 ] 2>/dev/null && { printf "%b" "$YELLOW"; return; }
    printf "%b" "$GREEN"
}

shorten_path() {
    local p="$1"
    p="${p//\\//}"
    local parent=$(basename "$(dirname "$p")")
    local leaf=$(basename "$p")
    if [ "$parent" = "." ] || [ "$parent" = "/" ]; then
        echo "$leaf"
    else
        echo "…/$parent/$leaf"
    fi
}

# ── Detect terminal width for responsive layout ──
# Claude Code forces COLS=80 when spawning statusline, so use a low threshold.

COLS=$(tput cols 2>/dev/null || echo 120)
NARROW=false
[ "$COLS" -lt 70 ] 2>/dev/null && NARROW=true

# ── Line 1: Model + Style + Git branch + Context bar ──

printf "%b%b%s%b" "$BOLD" "$CYAN" "$MODEL" "$RST"

# Hide output style when "default" to save horizontal space
if [ -n "$OUT_STYLE" ] && [ "$OUT_STYLE" != "default" ]; then
    printf "  %b%s%b" "$MAGENTA" "$OUT_STYLE" "$RST"
fi

# Prefer worktree badge over branch when inside a linked worktree
if [ -n "$GIT_WORKTREE" ]; then
    WT_DISPLAY="$GIT_WORKTREE"
    [ "${#WT_DISPLAY}" -gt 20 ] && WT_DISPLAY="${WT_DISPLAY:0:19}…"
    printf "  %b⎇ %s%b" "$BLUE" "$WT_DISPLAY" "$RST"
elif [ -n "$GIT_BRANCH" ]; then
    if [ "$NARROW" = true ] && [ "${#GIT_BRANCH}" -gt 15 ]; then
        GIT_BRANCH="${GIT_BRANCH:0:14}…"
    fi
    printf "  %b%s%b" "$BLUE" "$GIT_BRANCH" "$RST"
fi

if [ -n "$CTX_PCT" ]; then
    if [ "$NARROW" = true ]; then
        printf "  %bctx%b %b%.0f%%%b" "$DIM" "$RST" "$(pct_color "$CTX_PCT")" "$CTX_PCT" "$RST"
    else
        printf "  %bctx%b " "$DIM" "$RST"
        build_bar "$CTX_PCT"
        printf " %b%.0f%%%b" "$(pct_color "$CTX_PCT")" "$CTX_PCT" "$RST"
    fi
    # Show live context tokens / window size, e.g. "266k/1M"
    if [ -n "$LIVE_CTX" ] && [ -n "$CW_SIZE" ]; then
        printf " %b%s/%s%b" "$DIM" "$(format_tokens "$LIVE_CTX")" "$(format_cw_size "$CW_SIZE")" "$RST"
    elif [ -n "$CW_SIZE" ]; then
        printf " %b(%s)%b" "$DIM" "$(format_cw_size "$CW_SIZE")" "$RST"
    fi
    # Warn when exceeds 200k threshold
    if [ "$EXCEEDS_200K" = "true" ]; then
        printf " %b!200k%b" "$YELLOW" "$RST"
    fi
else
    if [ -n "$CW_SIZE" ]; then
        printf "  %bctx n/a (%s)%b" "$DIM" "$(format_cw_size "$CW_SIZE")" "$RST"
    else
        printf "  %bctx n/a%b" "$DIM" "$RST"
    fi
fi
echo ""

# ── Line 2: Cost (smart color) + burn rate + duration + api ratio + tokens + lines + cache ──

if [ -n "$COST" ]; then
    printf "%b\$%.4f%b" "$(cost_color "$COST")" "$COST" "$RST"
    # Burn rate $/h — only when duration ≥ 60s (avoid division noise at session start)
    if [ -n "$DUR_MS" ]; then
        BURN=$(format_burn_rate "$COST" "$DUR_MS")
        if [ -n "$BURN" ]; then
            printf "%b(%s/h)%b" "$DIM" "$BURN" "$RST"
        fi
    fi
else
    printf "%b\$--%b" "$DIM" "$RST"
fi

if [ -n "$DUR_MS" ]; then
    printf "  %b%s%b" "$DIM" "$(format_duration "$DUR_MS")" "$RST"
    # API thinking ratio — % of wall time spent waiting for Claude API
    if [ -n "$API_MS" ] && [ "$DUR_MS" -gt 0 ] 2>/dev/null; then
        API_PCT=$((API_MS * 100 / DUR_MS))
        printf "%b(api:%d%%)%b" "$DIM" "$API_PCT" "$RST"
    fi
fi

# Session cumulative tokens
if [ -n "$SESS_IN" ] && [ -n "$SESS_OUT" ]; then
    printf "  %b%s/%s%b" "$DIM" "$(format_tokens "$SESS_IN")" "$(format_tokens "$SESS_OUT")" "$RST"
fi

# Lines delta (hide when both zero — nothing to show)
if [ -n "$LINES_ADD" ] && [ -n "$LINES_REM" ]; then
    LINES_TOTAL=$((LINES_ADD + LINES_REM))
    if [ "$LINES_TOTAL" -gt 0 ] 2>/dev/null; then
        printf "  %b+%b%s%b/%b-%b%s%b" "$GREEN" "$RST" "$LINES_ADD" "$DIM" "$RST" "$RED" "$LINES_REM" "$RST"
    fi
fi

# Cache hit ratio
if [ -n "$CACHE_READ" ] && [ -n "$CACHE_CREATE" ]; then
    CACHE_TOTAL=$((CACHE_READ + CACHE_CREATE))
    if [ "$CACHE_TOTAL" -gt 0 ] 2>/dev/null; then
        CACHE_RATIO=$(awk "BEGIN{print $CACHE_READ * 100 / $CACHE_TOTAL}" 2>/dev/null)
        CACHE_INT=${CACHE_RATIO%.*}
        if [ "$CACHE_INT" -ge 70 ] 2>/dev/null; then
            C_COLOR="$GREEN"
        elif [ "$CACHE_INT" -ge 40 ] 2>/dev/null; then
            C_COLOR="$YELLOW"
        else
            C_COLOR="$RED"
        fi
        printf "  %bcache:%b%b%.0f%%%b" "$DIM" "$RST" "$C_COLOR" "$CACHE_RATIO" "$RST"
    fi
fi
echo ""

# ── Line 3: Rate limits (with reset time) + CWD + session name ──

LINE3_HAS_CONTENT=false

# Rate limits — show only when ≥ 50% consumed, append reset time when epoch available
if [ -n "$RL_5H" ]; then
    RL_5H_INT=${RL_5H%.*}
    if [ "$RL_5H_INT" -ge 50 ] 2>/dev/null; then
        printf "%b5h:%b%b%.0f%%%b" "$DIM" "$RST" "$(pct_color "$RL_5H")" "$RL_5H" "$RST"
        if [ -n "$RL_5H_RESET" ]; then
            printf "%b(%s)%b" "$DIM" "$(format_reset_time "$RL_5H_RESET")" "$RST"
        fi
        LINE3_HAS_CONTENT=true
    fi
fi
if [ -n "$RL_7D" ]; then
    RL_7D_INT=${RL_7D%.*}
    if [ "$RL_7D_INT" -ge 50 ] 2>/dev/null; then
        [ "$LINE3_HAS_CONTENT" = true ] && printf " "
        printf "%b7d:%b%b%.0f%%%b" "$DIM" "$RST" "$(pct_color "$RL_7D")" "$RL_7D" "$RST"
        if [ -n "$RL_7D_RESET" ]; then
            printf "%b(%s)%b" "$DIM" "$(format_reset_time "$RL_7D_RESET")" "$RST"
        fi
        LINE3_HAS_CONTENT=true
    fi
fi

# CWD — always shown
SHORT_CWD=$(shorten_path "$CWD")
[ "$LINE3_HAS_CONTENT" = true ] && printf "  "
printf "%b%s%b" "$WHITE" "$SHORT_CWD" "$RST"

# Session name (truncated if long) — only when explicitly set by user
if [ -n "$SESSION_NAME" ]; then
    SN_DISPLAY="$SESSION_NAME"
    [ "${#SN_DISPLAY}" -gt 20 ] && SN_DISPLAY="${SN_DISPLAY:0:19}…"
    printf "  %b[%s]%b" "$DIM" "$SN_DISPLAY" "$RST"
fi
echo ""
