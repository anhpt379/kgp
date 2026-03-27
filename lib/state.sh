#!/bin/bash
# ============================================================================
# State management functions
# ============================================================================

save_state() {
    local mode="$1"
    local pod="${2:-}"
    local resource="${3:-}"
    local object="${4:-}"

    # Preserve FZF_PORT if it exists in current state
    local fzf_port=""
    if [[ -f "$STATE_FILE" ]]; then
        fzf_port=$(grep "^FZF_PORT=" "$STATE_FILE" 2>/dev/null || true)
    fi

    cat >"$STATE_FILE" <<EOF
MODE=$mode
POD=$pod
RESOURCE=$resource
OBJECT=$object
CONTEXT=$CONTEXT
NAMESPACE=$NAMESPACE
CACHE_DIR=${CACHE_BASE_DIR}/${CONTEXT}/${NAMESPACE}
${fzf_port}
EOF
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
    fi
}
