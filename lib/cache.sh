#!/bin/bash
# ============================================================================
# Cache management and background refresh
# ============================================================================

refresh_cache() {
    load_state
    debug "Refreshing cache for MODE=$MODE, CONTEXT=$CONTEXT, NAMESPACE=$NAMESPACE"
    mkdir -p "$CACHE_DIR"

    if [[ "$MODE" == "pods" ]] || [[ "$MODE" == "containers" ]]; then
        local raw_data_file="${CACHE_DIR}/raw_data.json"
        local temp_file=$(mktemp)

        if kubectl get pods -o json >"$temp_file" 2>&1; then
            mv "$temp_file" "$raw_data_file"
            debug "Successfully fetched pod data, processing with $LIB_PATH"
            "$LIB_PATH" -i "$raw_data_file" -o "$CACHE_DIR"
        else
            echo "Failed to fetch pod data" >&2
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
        debug "Successfully cached $resource data"
    else
        echo "Failed to fetch $resource data" >&2
        rm -f "$temp_file"
        return 1
    fi
}

start_background_refresh() {
    debug "Starting background refresh with interval: $CACHE_REFRESH_INTERVAL seconds"

    while true; do
        refresh_cache
        load_state

        # Trigger reload if FZF is running
        if [[ -n "$FZF_PORT" ]]; then
            curl -XPOST localhost:$FZF_PORT -d 'reload(display_data)'
        fi

        sleep "$CACHE_REFRESH_INTERVAL"
    done &

    BG_REFRESH_PID=$!
}

stop_background_refresh() {
    if [[ -n "$BG_REFRESH_PID" ]]; then
        debug "Stopping background refresh process: $BG_REFRESH_PID"
        kill "$BG_REFRESH_PID" 2>/dev/null || true
        wait "$BG_REFRESH_PID" 2>/dev/null || true
        BG_REFRESH_PID=""
    fi
}
