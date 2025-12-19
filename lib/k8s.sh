#!/bin/bash
# ============================================================================
# Kubernetes-specific functions
# ============================================================================

get_current_context() {
    kubectl config current-context
}

get_current_namespace() {
    local namespace
    namespace=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    echo "${namespace:-default}"
}

get_contexts() {
    kubectl config get-contexts -o name | sort
}

switch_context() {
    local new_context="$1"
    # Remove trailing marker if present
    new_context="${new_context% \*}"

    echo "Switching to context: $new_context..."
    if kubectl config use-context "$new_context" >/dev/null 2>&1; then
        # Update global variables
        export CONTEXT="$new_context"
        export NAMESPACE=$(get_current_namespace)
        export CACHE_DIR="${CACHE_BASE_DIR}/${CONTEXT}/${NAMESPACE}"
        debug "Switched to context: $CONTEXT, namespace: $NAMESPACE"
        save_state "pods"
    fi
}
