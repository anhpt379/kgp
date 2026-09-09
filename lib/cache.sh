#!/bin/bash
# ============================================================================
# Cache management and background refresh
# ============================================================================
initialize_cache() {
    debug "Initializing cache directory: $CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    
    # Create initial loading placeholders
    if [[ ! -f "${CACHE_DIR}/pods" ]]; then
        echo "$(colorize WHITE "Loading pod data from cluster $CONTEXT...")" > "${CACHE_DIR}/pods"
    fi
    if [[ ! -f "${CACHE_DIR}/containers" ]]; then
        echo "Loading..." > "${CACHE_DIR}/containers"
    fi
}

# ============================================================================
# Refresh failure marker
#
# A refresh that fails while a populated cache exists keeps showing that cache,
# which is the right call for a blip but leaves the view looking live when it is
# not: expired credentials just stop the data from moving. The marker below is
# how the fzf header learns to say so, and it lives in the cache directory
# because the refresh loop and the header run in separate processes.
# ============================================================================
REFRESH_ERROR_FILE=".refresh_error"

# Keep the first failure's reason and time: the message from a later attempt is
# usually the same, and the age of the original failure is what tells a reader
# how stale the list is.
mark_refresh_error() {
    local error_text="$1"
    local marker="${CACHE_DIR}/${REFRESH_ERROR_FILE}"

    [[ -f "$marker" ]] && return 0

    local reason
    case "$error_text" in
    *Unauthorized* | *"must be logged in"* | *"401"* | *"invalid bearer token"* | \
        *"credentials"* | *"token has expired"* | *"error: You must be logged in"*)
        reason="credentials expired, log in again"
        ;;
    *"connection refused"* | *"no such host"* | *"i/o timeout"* | *"dial tcp"* | \
        *"unreachable"* | *"context deadline exceeded"*)
        reason="cluster unreachable"
        ;;
    *Forbidden* | *"cannot list resource"*)
        reason="not allowed to list this namespace"
        ;;
    *)
        reason="refresh failing"
        ;;
    esac

    printf '%s\n' "$reason" >"$marker"
    debug "Marked refresh error: $reason"
}

clear_refresh_error() {
    rm -f "${CACHE_DIR}/${REFRESH_ERROR_FILE}"
}

# How long the marker has been sitting there, in a form that fits a header.
refresh_error_age() {
    local marker="$1"
    local marked now seconds

    marked=$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null) || return 1
    now=$(date +%s)
    seconds=$((now - marked))
    ((seconds < 0)) && seconds=0

    if ((seconds < 60)); then
        echo "${seconds}s"
    elif ((seconds < 3600)); then
        echo "$((seconds / 60))m"
    else
        echo "$((seconds / 3600))h"
    fi
}

# The note the view headers append. Empty when the last refresh was fine, so a
# healthy header is unchanged.
refresh_error_note() {
    local marker="${CACHE_DIR}/${REFRESH_ERROR_FILE}"
    [[ -f "$marker" ]] || return 0

    local reason age
    reason=$(head -1 "$marker")
    age=$(refresh_error_age "$marker")

    printf '%s' "$(colorize ORANGE "⚠ ${reason} — data ${age:+$age }stale, F5 to retry")"
}

refresh_cache() {
    load_state

    # Ensure cache directory exists (important after context/namespace switch)
    mkdir -p "$CACHE_DIR"

    debug "Refreshing cache for MODE=$MODE, CONTEXT=$CONTEXT, NAMESPACE=$NAMESPACE"

    if [[ "$MODE" == "pods" ]] || [[ "$MODE" == "containers" ]]; then
        local raw_data_file="${CACHE_DIR}/raw_data.json"
        local temp_file=$(mktemp)

        if kubectl get pods -o json >"$temp_file" 2>&1; then
            mv "$temp_file" "$raw_data_file"
            debug "Successfully fetched pod data, processing with $FORMAT_PODS"
            "$FORMAT_PODS" -i "$raw_data_file" -o "$CACHE_DIR"
            clear_refresh_error
            return 0
        else
            debug "Failed to fetch pod data: kubectl command failed"

            # kubectl's own complaint was redirected into the temp file; it is
            # what distinguishes an expired login from an unreachable cluster.
            mark_refresh_error "$(head -c 2000 "$temp_file" 2>/dev/null)"

            # Only overwrite cache with error if there's no valid cached data
            # This preserves the previous session's cache on transient connection failures
            if [[ ! -f "${CACHE_DIR}/pods" ]] || grep -q "Loading pod data" "${CACHE_DIR}/pods" 2>/dev/null; then
                echo "$(colorize RED "✗ Unable to connect to cluster: $CONTEXT")" > "${CACHE_DIR}/pods"
                echo "$(colorize YELLOW "  Possible causes:")" >> "${CACHE_DIR}/pods"
                echo "  • Cluster is unreachable or not running" >> "${CACHE_DIR}/pods"
                echo "  • Invalid kubeconfig or credentials expired" >> "${CACHE_DIR}/pods"
                echo "  • Network connectivity issues" >> "${CACHE_DIR}/pods"
                echo "$(colorize CYAN "  Press F5 to retry")" >> "${CACHE_DIR}/pods"

                echo -e "Loading..." > "${CACHE_DIR}/containers"
            else
                debug "Keeping existing cache data despite connection failure"
            fi
            rm -f "$temp_file"
            return 1
        fi
    elif [[ "$MODE" == "objects" ]] && [[ -n "$RESOURCE" ]]; then
        refresh_objects_cache "$RESOURCE"
    fi
}

refresh_objects_cache() {
    local resource="$1"
    local cache_file="${CACHE_DIR}/${resource}.cache"
    local temp_file=$(mktemp)

    debug "Refreshing cache for resource type: $resource"

    if kubectl get "$resource" -o wide >"$temp_file" 2>&1; then
        mv "$temp_file" "$cache_file"
        clear_refresh_error
        debug "Successfully cached $resource data"
    else
        debug "Failed to fetch $resource data: kubectl command failed"
        mark_refresh_error "$(head -c 2000 "$temp_file" 2>/dev/null)"
        echo "Error: Unable to fetch $resource data. Check cluster connection." > "$cache_file"
        rm -f "$temp_file"
    fi
}

start_background_refresh() {
    debug "Starting background refresh with interval: $CACHE_REFRESH_INTERVAL seconds"

    # Initial delay to allow FZF to fully initialize and set FZF_PORT
    (sleep 1
    local retry_interval=2
    local connected=false

    while true; do
        debug "Background refresh: starting cache update..."
        load_state

        if refresh_cache; then
            connected=true
        else
            debug "Background refresh: refresh_cache failed, continuing..."
        fi

        # Trigger reload if FZF is running
        if [[ -n "${FZF_PORT:-}" ]] && [[ "${FZF_PORT:-}" =~ ^[0-9]+$ ]]; then
            curl -sf -XPOST "http://localhost:${FZF_PORT}" -d 'reload(display_data)' 2>/dev/null && debug "Background refresh: triggered fzf reload" || debug "Background refresh: failed to trigger fzf reload (port: $FZF_PORT)"
        else
            debug "Background refresh: FZF_PORT not available yet"
        fi

        # Use short retry interval until first successful connection, then normal interval
        if [[ "$connected" == "true" ]]; then
            sleep "$CACHE_REFRESH_INTERVAL"
        else
            sleep "$retry_interval"
        fi
    done) &

    BG_REFRESH_PID=$!
    debug "Background refresh started with PID: $BG_REFRESH_PID"
}

stop_background_refresh() {
    if [[ -n "$BG_REFRESH_PID" ]]; then
        debug "Stopping background refresh process: $BG_REFRESH_PID"
        kill "$BG_REFRESH_PID" 2>/dev/null || true
        wait "$BG_REFRESH_PID" 2>/dev/null || true
        BG_REFRESH_PID=""
    fi
}
