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

# Context used percentage
CTX_PCT=$(echo "$INPUT" | sed -n 's/.*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)

# Cost
COST=$(echo "$INPUT" | sed -n 's/.*"total_cost_usd"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)

# Duration ms
DUR_MS=$(echo "$INPUT" | sed -n 's/.*"total_duration_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Token counts
IN_TOKENS=$(echo "$INPUT" | sed -n 's/.*"total_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
OUT_TOKENS=$(echo "$INPUT" | sed -n 's/.*"total_output_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

# Cache tokens
CACHE_READ=$(echo "$INPUT" | sed -n 's/.*"cache_read_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
CACHE_CREATE=$(echo "$INPUT" | sed -n 's/.*"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)

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

COLS=$(tput cols 2>/dev/null || echo 120)
NARROW=false
[ "$COLS" -lt 90 ] 2>/dev/null && NARROW=true

# ── Line 1: Model + Style + Git branch + Context bar ──

printf "%b%b%s%b" "$BOLD" "$CYAN" "$MODEL" "$RST"

if [ -n "$OUT_STYLE" ]; then
    printf "  %b%s%b" "$MAGENTA" "$OUT_STYLE" "$RST"
fi

if [ -n "$GIT_BRANCH" ]; then
    # Truncate long branch names when narrow
    if [ "$NARROW" = true ] && [ "${#GIT_BRANCH}" -gt 15 ]; then
        GIT_BRANCH="${GIT_BRANCH:0:14}…"
    fi
    printf "  %b%s%b" "$BLUE" "$GIT_BRANCH" "$RST"
fi

if [ -n "$CTX_PCT" ]; then
    if [ "$NARROW" = true ]; then
        # Compact: just percentage, no bar
        printf "  %bctx%b %b%.0f%%%b" "$DIM" "$RST" "$(pct_color "$CTX_PCT")" "$CTX_PCT" "$RST"
    else
        printf "  %bctx%b " "$DIM" "$RST"
        build_bar "$CTX_PCT"
        printf " %b%.1f%%%b" "$(pct_color "$CTX_PCT")" "$CTX_PCT" "$RST"
    fi
else
    printf "  %bctx n/a%b" "$DIM" "$RST"
fi
echo ""

# ── Line 2: Cost + Duration + Tokens + Cache ratio + CWD ──

if [ -n "$COST" ]; then
    printf "%b\$%.4f%b" "$GREEN" "$COST" "$RST"
else
    printf "%b\$--%b" "$DIM" "$RST"
fi

if [ -n "$DUR_MS" ]; then
    printf "  %b%s%b" "$DIM" "$(format_duration "$DUR_MS")" "$RST"
fi

if [ -n "$IN_TOKENS" ] && [ -n "$OUT_TOKENS" ]; then
    printf "  %bin:%b%s %bout:%b%s" "$DIM" "$RST" "$(format_tokens "$IN_TOKENS")" "$DIM" "$RST" "$(format_tokens "$OUT_TOKENS")"
fi

# Hide cache ratio when narrow
if [ "$NARROW" != true ] && [ -n "$CACHE_READ" ] && [ -n "$CACHE_CREATE" ]; then
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

SHORT_CWD=$(shorten_path "$CWD")
printf "  %b%s%b" "$WHITE" "$SHORT_CWD" "$RST"
echo ""
