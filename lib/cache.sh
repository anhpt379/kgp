#!/bin/bash
# ============================================================================
# Cache management and background refresh
# ============================================================================
initialize_cache() {
    debug "Initializing cache directory: $CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    
    # Create initial loading placeholders
    if [[ ! -f "${CACHE_DIR}/pods" ]]; then
        echo "$(colorize CYAN "⟳ Loading pod data from cluster $CONTEXT...")" > "${CACHE_DIR}/pods"
        echo "$(colorize GRAY "  This may take a few seconds on first launch")" >> "${CACHE_DIR}/pods"
    fi
    if [[ ! -f "${CACHE_DIR}/containers" ]]; then
        echo "⟳ Loading..." > "${CACHE_DIR}/containers"
    fi
}

refresh_cache() {
    load_state
    debug "Refreshing cache for MODE=$MODE, CONTEXT=$CONTEXT, NAMESPACE=$NAMESPACE"

    if [[ "$MODE" == "pods" ]] || [[ "$MODE" == "containers" ]]; then
        local raw_data_file="${CACHE_DIR}/raw_data.json"
        local temp_file=$(mktemp)

        if kubectl get pods -o json >"$temp_file" 2>&1; then
            mv "$temp_file" "$raw_data_file"
            debug "Successfully fetched pod data, processing with $FORMAT_PODS"
            "$FORMAT_PODS" -i "$raw_data_file" -o "$CACHE_DIR"
        else
            debug "Failed to fetch pod data: kubectl command failed"

            # Check if this is first attempt (only has loading message)
            local is_first_attempt=false
            if grep -q "⟳ Loading" "${CACHE_DIR}/pods" 2>/dev/null; then
                is_first_attempt=true
            fi
            
            # Create error message files
            if [[ "$is_first_attempt" == "true" ]]; then
                echo "$(colorize RED "✗ Unable to connect to cluster: $CONTEXT")" > "${CACHE_DIR}/pods"
                echo "$(colorize YELLOW "  Possible causes:")" >> "${CACHE_DIR}/pods"
                echo "  • Cluster is unreachable or not running" >> "${CACHE_DIR}/pods"
                echo "  • Invalid kubeconfig or credentials expired" >> "${CACHE_DIR}/pods"
                echo "  • Network connectivity issues" >> "${CACHE_DIR}/pods"
                echo "$(colorize CYAN "  Press F5 to retry")" >> "${CACHE_DIR}/pods"
            else
                echo "$(colorize RED "✗ Connection lost to cluster: $CONTEXT")" > "${CACHE_DIR}/pods"
                echo "$(colorize CYAN "  Press F5 to retry")" >> "${CACHE_DIR}/pods"
            fi
            
            echo -e "Loading..." > "${CACHE_DIR}/containers"
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
        debug "Failed to fetch $resource data: kubectl command failed"
        echo "Error: Unable to fetch $resource data. Check cluster connection." > "$cache_file"
        rm -f "$temp_file"
        return 1
    fi
}

start_background_refresh() {
    debug "Starting background refresh with interval: $CACHE_REFRESH_INTERVAL seconds"

    while true; do
        sleep "$CACHE_REFRESH_INTERVAL"
        debug "Background refresh: starting cache update..."
        load_state
        refresh_cache

        # Trigger reload if FZF is running
        if [[ -n "$FZF_PORT" ]] && [[ "$FZF_PORT" =~ ^[0-9]+$ ]]; then
            curl -sf -XPOST "http://localhost:${FZF_PORT}" -d 'reload(display_data)' 2>/dev/null && debug "Background refresh: triggered fzf reload" || debug "Background refresh: failed to trigger fzf reload (port: $FZF_PORT)"
        else
            debug "Background refresh: FZF_PORT not available yet"
        fi

        sleep "$CACHE_REFRESH_INTERVAL"
    done &

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
