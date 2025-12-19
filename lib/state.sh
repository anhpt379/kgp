#!/bin/bash
# ============================================================================
# State management functions
# ============================================================================

save_state() {
    local mode="$1"
    local pod="${2:-}"
    local resource="${3:-}"
    local object="${4:-}"

    cat >"$STATE_FILE" <<EOF
MODE=$mode
POD=$pod
RESOURCE=$resource
OBJECT=$object
CONTEXT=$CONTEXT
NAMESPACE=$NAMESPACE
CACHE_DIR=${CACHE_BASE_DIR}/${CONTEXT}/${NAMESPACE}
FZF_PORT=${FZF_PORT:-}
EOF
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
    fi
}
