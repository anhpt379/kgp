#!/bin/bash
# ============================================================================
# Core utility functions
# ============================================================================

debug() {
    if [[ "${KGP_DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
    return 0
}

find_library() {
    for path in "${LIB_SEARCH_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    echo "Error: Cannot find format-pods.py library" >&2
    exit 1
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
            printf "\033[0;90m%s\033[0m \033[%dm%s\033[0m %s\n",
                timestamp, container_colors[container], container, message
        } else {
            # Print non-matching lines as-is
            print $0
        }
    }'
}

print_stream_closed_eof() {
    local pod="$1"
    local container="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")

    local msg
    if [[ -n "$container" ]]; then
        msg="stream closed EOF for ${pod} (${container})"
    else
        msg="stream closed EOF for ${pod}"
    fi

    echo "$(colorize GRAY "${timestamp}") $(colorize ORANGE "\033[1m$msg\033[0m")"
}

show_less_help() {
    echo "Logs will be viewed using \`less\`. Bellow are some useful keys:"
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

cleanup() {
    stop_background_refresh
    rm -f "$STATE_FILE"
}
