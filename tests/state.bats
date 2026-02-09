#!/usr/bin/env bats
# ============================================================================
# Tests for lib/state.sh
# ============================================================================

load test_helper

setup() {
    setup_test_env
    source_libs
}

teardown() {
    teardown_test_env
}

# ============================================================================
# save_state() tests
# ============================================================================

@test "save_state: creates state file with mode" {
    save_state "pods"

    [ -f "$STATE_FILE" ]
    grep -q "MODE=pods" "$STATE_FILE"
}

@test "save_state: saves mode and pod" {
    save_state "containers" "my-pod"

    grep -q "MODE=containers" "$STATE_FILE"
    grep -q "POD=my-pod" "$STATE_FILE"
}

@test "save_state: saves mode, pod, resource, and object" {
    save_state "objects" "my-pod" "Deployments" "my-deployment"

    grep -q "MODE=objects" "$STATE_FILE"
    grep -q "POD=my-pod" "$STATE_FILE"
    grep -q "RESOURCE=Deployments" "$STATE_FILE"
    grep -q "OBJECT=my-deployment" "$STATE_FILE"
}

@test "save_state: includes context and namespace" {
    export CONTEXT="prod-cluster"
    export NAMESPACE="production"

    save_state "pods"

    grep -q "CONTEXT=prod-cluster" "$STATE_FILE"
    grep -q "NAMESPACE=production" "$STATE_FILE"
}

@test "save_state: includes cache directory path" {
    export CONTEXT="my-context"
    export NAMESPACE="my-namespace"
    export CACHE_BASE_DIR="/tmp/test-cache"

    save_state "pods"

    grep -q "CACHE_DIR=/tmp/test-cache/my-context/my-namespace" "$STATE_FILE"
}

# ============================================================================
# load_state() tests
# ============================================================================

@test "load_state: loads mode from state file" {
    echo "MODE=containers" > "$STATE_FILE"
    echo "POD=test-pod" >> "$STATE_FILE"

    load_state

    [ "$MODE" = "containers" ]
    [ "$POD" = "test-pod" ]
}

@test "load_state: does nothing if state file doesn't exist" {
    rm -f "$STATE_FILE"
    export MODE="original"

    load_state

    [ "$MODE" = "original" ]
}

@test "load_state: loads all state variables" {
    cat > "$STATE_FILE" <<EOF
MODE=objects
POD=my-pod
RESOURCE=Services
OBJECT=my-service
CONTEXT=prod
NAMESPACE=default
EOF

    load_state

    [ "$MODE" = "objects" ]
    [ "$POD" = "my-pod" ]
    [ "$RESOURCE" = "Services" ]
    [ "$OBJECT" = "my-service" ]
    [ "$CONTEXT" = "prod" ]
    [ "$NAMESPACE" = "default" ]
}

# ============================================================================
# Round-trip tests
# ============================================================================

@test "state: round-trip save and load" {
    export CONTEXT="test-ctx"
    export NAMESPACE="test-ns"

    save_state "resources" "pod-1" "ConfigMaps" "my-config"

    # Reset variables
    MODE=""
    POD=""
    RESOURCE=""
    OBJECT=""

    load_state

    [ "$MODE" = "resources" ]
    [ "$POD" = "pod-1" ]
    [ "$RESOURCE" = "ConfigMaps" ]
    [ "$OBJECT" = "my-config" ]
}
