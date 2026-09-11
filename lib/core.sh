#!/bin/bash
# ============================================================================
# Core utility functions
# ============================================================================

debug() {
    if [[ "${KGP_DEBUG:-0}" == "1" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local message="[$timestamp] [DEBUG] $*"

        echo "$message" >>"/tmp/kgp/debug.log"
    fi
    return 0
}

check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required commands: ${missing[*]}" >&2
        exit 1
    fi
}

copy_to_clipboard() {
    local text="$1"

    if [[ -z "$text" ]]; then
        echo "Nothing to copy"
        return 1
    fi

    # Try different clipboard utilities in order of preference
    if command -v pbcopy >/dev/null 2>&1; then
        # macOS
        echo -n "$text" | pbcopy
    elif command -v xclip >/dev/null 2>&1; then
        # Linux X11
        echo -n "$text" | xclip -selection clipboard
    elif command -v wl-copy >/dev/null 2>&1; then
        # Linux Wayland
        echo -n "$text" | wl-copy
    else
        echo "Error: No clipboard utility found (pbcopy, xclip or wl-copy)"
        return 1
    fi

    return 0
}

clipboard_from_stdin() {
    if command -v pbcopy >/dev/null 2>&1; then
        pbcopy
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    elif command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    else
        cat >/dev/null
        echo "Error: No clipboard utility found (pbcopy, xclip or wl-copy)" >&2
        return 1
    fi
}

# Copy fzf-selected log lines. The selection file carries the hidden line-number
# field and may carry color codes, so strip both before reaching the clipboard.
copy_log_lines() {
    local file="$1"

    [[ -s "$file" ]] || return 0
    cut -f2- "$file" | sed 's/\x1b\[[0-9;]*m//g' | clipboard_from_stdin
}

colorize() {
    local color="$1"
    local text="$2"
    local color_code=""

    case "$color" in
    RED) color_code="$RED" ;;
    GREEN) color_code="$GREEN" ;;
    YELLOW) color_code="$YELLOW" ;;
    ORANGE) color_code="$ORANGE" ;;
    CYAN) color_code="$CYAN" ;;
    GRAY) color_code="$GRAY" ;;
    MAGENTA) color_code="$MAGENTA" ;;
    WHITE) color_code="$WHITE" ;;
    *)
        echo "$text"
        return
        ;;
    esac

    echo -e "${color_code}${text}${RESET}"
}

# Colorize a kubectl log stream for display in fzf.
#
# Field 1 of every output line is the 1-based line number of the corresponding
# line in the spill file; fzf hides it with --with-nth=2.. and reads it back as
# {1} to hand off to an editor. That mapping holds only because this filter is
# strictly one output line per input line -- do not add rules that drop, split,
# or reorder lines.
highlight_logs() {
    awk 'BEGIN {
        # Color codes
        colors[0]=31; colors[1]=32; colors[2]=33; colors[3]=34; colors[4]=35; colors[5]=36
        colors[6]=91; colors[7]=92; colors[8]=93; colors[9]=94; colors[10]=95; colors[11]=96
        color_count = 12
        next_color = 0
    }
    {
        # Match pattern: [pod/container] timestamp message
        if (match($0, /^\[([^]]+)\] ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z) (.*)$/, parts)) {
            full_container = parts[1]
            timestamp = parts[2]
            message = parts[3]

            # Extract just the container name from pod/pod-name/container-name
            split(full_container, container_parts, "/")
            container = container_parts[length(container_parts)]

            # Assign color to container if not seen before
            if (!(container in container_colors)) {
                container_colors[container] = colors[next_color]
                next_color = (next_color + 1) % color_count
            }

            # Print with colors: timestamp first, then container, then message
            printf "%d\t\033[0;90m%s\033[0m \033[%dm%s\033[0m %s\n",
                NR, timestamp, container_colors[container], container, message
        } else if ($0 ~ /stream closed EOF/) {
            printf "%d\t\033[38;5;214m\033[1m%s\033[0m\n", NR, $0
        } else {
            # Print non-matching lines as-is
            printf "%d\t%s\n", NR, $0
        }

        # Without this, awk block-buffers into the fzf pipe and a quiet pod
        # shows an empty view even though lines have already arrived.
        fflush()
    }'
}

# Emitted as plain text so the spill file stays free of escape codes;
# highlight_logs is what colors this line for display.
print_stream_closed_eof() {
    local pod="$1"
    local container="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")

    if [[ -n "$container" ]]; then
        echo "${timestamp} stream closed EOF for ${pod} (${container})"
    else
        echo "${timestamp} stream closed EOF for ${pod}"
    fi
}

show_less_help() {
    echo "Output will be viewed using \`less\`. Below are some useful keys:"
    echo "  q          = quit"
    echo "  /          = search forward"
    echo "  ?          = search backward"
    echo "  n          = repeat search forward"
    echo "  N          = repeat search backward"
    echo "  g          = go to beginning of file"
    echo "  G          = go to end of file"
    echo "  f or SPACE = page down"
    echo "  b          = page up"
    echo "  F          = follow mode (like tail -f)"
    echo "  CTRL-C     = stop follow mode"
    echo
    echo -n "Show this help again next time? (Y/n): "
    read -r -n 1 answer </dev/tty
    answer=${answer,,} # to lowercase
    if [[ "$answer" == "n" ]]; then
        touch "${CACHE_BASE_DIR}/.less_help_dismissed"
    fi
}

less_help() {
    if [[ ! -f "${CACHE_BASE_DIR}/.less_help_dismissed" ]]; then
        show_less_help
    fi
    less "$@"
}

# Blank rows the preview keeps above and below the log line, so the text is not
# pressed against the top border and the bottom of the terminal. The bottom gets
# the wider gap: the top only has to clear a border, while the bottom sits on the
# edge of the terminal. Both the pane height and the pane contents are built from
# these, and fzf bindings run in a child shell that only sees what kgp exports,
# hence variables over literals.
LOG_PREVIEW_PAD_TOP="${LOG_PREVIEW_PAD_TOP:-1}"
LOG_PREVIEW_PAD_BOTTOM="${LOG_PREVIEW_PAD_BOTTOM:-2}"

# Read one line out of the spill file, untouched.
#
# The sed range quits at the target line rather than scanning the whole file,
# which matters because the preview re-runs on every cursor move and the spill
# file can be large.
read_log_line() {
    local spill="$1"
    local lineno="$2"

    [[ -f "$spill" ]] || return 0
    [[ "$lineno" =~ ^[0-9]+$ ]] || return 0
    sed -n "${lineno}{p;q}" "$spill"
}

# Render the full text of one log line for the fzf preview pane. This is what
# replaces line wrapping: the list stays one line per entry and the untruncated
# text is read here instead.
#
# The padding is printed rather than configured because fzf has no preview
# padding of its own: --preview-window takes a border, and the content starts on
# the row below it. log_preview_window sizes the pane to match these rows.
preview_log_line() {
    local spill="$1"
    local lineno="$2"
    local pad

    for (( pad = 0; pad < LOG_PREVIEW_PAD_TOP; pad++ )); do
        echo
    done

    read_log_line "$spill" "$lineno"

    for (( pad = 0; pad < LOG_PREVIEW_PAD_BOTTOM; pad++ )); do
        echo
    done
}

# Pick the geometry of the log preview pane for the line under the cursor. The
# pane grows to just fit the wrapped line -- one row for a short line, more for
# a JSON payload -- so every row the preview does not need stays with the list.
#
# fzf re-shows a hidden preview whenever change-preview-window runs, so CTRL-/
# cannot use fzf's own toggle-preview action: the next cursor move would pop the
# pane straight back open. toggle_log_preview keeps that state in a flag file
# beside the spill, and the spec repeats "hidden" back to fzf until it clears.
log_preview_window() {
    local spill="$1"
    local lineno="$2"
    local cols="${3:-0}"
    local line rows

    # Ten rows of text is enough to read a long JSON payload while leaving most
    # of the terminal to the list; a longer line scrolls inside the pane.
    local max_rows=10

    if [[ -f "${spill}.nopreview" ]]; then
        echo "change-preview-window(down,1,wrap,border-top,hidden)"
        return 0
    fi

    # FZF_COLUMNS counts the whole window, and the preview content is one column
    # narrower than that. Guessing too wide would leave the tail of a line that
    # only just overflows with no row to wrap into.
    if (( cols > 1 )); then
        (( cols -= 1 ))
    else
        cols=80
    fi

    line="$(read_log_line "$spill" "$lineno")"

    # A tab is one character in the string but a whole tab stop on screen.
    line="${line//$'\t'/        }"

    rows=$(( (${#line} + cols - 1) / cols ))
    (( rows < 1 )) && rows=1
    (( rows > max_rows )) && rows=$max_rows

    # The clamp is on the rows of text, so the blank rows above and below are
    # added on top of it: padding never eats into what a long line can show.
    (( rows += LOG_PREVIEW_PAD_TOP + LOG_PREVIEW_PAD_BOTTOM ))

    echo "change-preview-window(down,${rows},wrap,border-top)"
}

# Flip the log preview between shown and hidden. See log_preview_window for why
# this stands in for fzf's toggle-preview action.
toggle_log_preview() {
    local flag="${1}.nopreview"

    if [[ -f "$flag" ]]; then
        rm -f "$flag"
    else
        : >"$flag"
    fi
}

# Kill a process and everything below it. Needed because fzf exiting does not
# reliably tear down a kubectl log stream: on a quiet pod nothing writes, so no
# SIGPIPE ever arrives, and kubectl can outlive the viewer holding the pipe open.
terminate_tree() {
    local pid="$1" child

    [[ -n "$pid" ]] || return 0
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        terminate_tree "$child"
    done
    kill "$pid" 2>/dev/null || true
}

cleanup() {
    stop_background_refresh
    rm -f "$STATE_FILE"

    # view_logs removes its own spill file; this catches ones orphaned by a kill.
    if [[ -n "${LOG_SPILL_DIR:-}" ]] && [[ -d "$LOG_SPILL_DIR" ]]; then
        find "$LOG_SPILL_DIR" -maxdepth 1 -name 'log.*' -mtime +1 -delete 2>/dev/null || true
    fi
}
