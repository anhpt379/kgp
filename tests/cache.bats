#!/usr/bin/env bats
# ============================================================================
# Tests for lib/cache.sh
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
# initialize_cache() tests
# ============================================================================

@test "initialize_cache: creates cache directory" {
    rm -rf "$CACHE_DIR"

    initialize_cache

    [ -d "$CACHE_DIR" ]
}

@test "initialize_cache: creates pods placeholder when file doesn't exist" {
    rm -f "${CACHE_DIR}/pods"

    initialize_cache

    [ -f "${CACHE_DIR}/pods" ]
    grep -q "Loading pod data" "${CACHE_DIR}/pods"
}

@test "initialize_cache: creates containers placeholder when file doesn't exist" {
    rm -f "${CACHE_DIR}/containers"

    initialize_cache

    [ -f "${CACHE_DIR}/containers" ]
    grep -q "Loading" "${CACHE_DIR}/containers"
}

@test "initialize_cache: preserves existing pods cache" {
    mkdir -p "$CACHE_DIR"
    echo "existing pod data" > "${CACHE_DIR}/pods"

    initialize_cache

    grep -q "existing pod data" "${CACHE_DIR}/pods"
    ! grep -q "Loading pod data" "${CACHE_DIR}/pods"
}

@test "initialize_cache: preserves existing containers cache" {
    mkdir -p "$CACHE_DIR"
    echo "existing container data" > "${CACHE_DIR}/containers"

    initialize_cache

    grep -q "existing container data" "${CACHE_DIR}/containers"
}

# ============================================================================
# refresh_cache() tests - successful refresh
# ============================================================================

@test "refresh_cache: returns 0 on successful kubectl" {
    save_state "pods"
    mock_kubectl 0 '{"items":[]}'

    run refresh_cache
    [ "$status" -eq 0 ]
}

@test "refresh_cache: creates raw_data.json on success" {
    save_state "pods"
    mock_kubectl 0 '{"items":[]}'

    refresh_cache

    [ -f "${CACHE_DIR}/raw_data.json" ]
}

# ============================================================================
# refresh_cache() tests - failed refresh (the fix we made)
# ============================================================================

@test "refresh_cache: returns 1 on failed kubectl" {
    save_state "pods"
    mock_kubectl 1 "error"

    run refresh_cache
    [ "$status" -eq 1 ]
}

@test "refresh_cache: shows error when no cache exists and kubectl fails" {
    save_state "pods"
    rm -f "${CACHE_DIR}/pods"
    mock_kubectl 1 "connection refused"

    # refresh_cache returns 1 on failure, but we want to check the cache file
    refresh_cache || true

    [ -f "${CACHE_DIR}/pods" ]
    grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "refresh_cache: shows error when only loading placeholder exists" {
    save_state "pods"
    echo "Loading pod data from cluster..." > "${CACHE_DIR}/pods"
    mock_kubectl 1 "connection refused"

    refresh_cache || true

    grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "refresh_cache: preserves existing cache when kubectl fails" {
    save_state "pods"
    # Create valid cached data
    cat > "${CACHE_DIR}/pods" <<'EOF'
pod-1    1/1   Running   0   1d
pod-2    2/2   Running   0   2d
EOF
    mock_kubectl 1 "connection refused"

    refresh_cache || true

    # Should still have the original data, not error message
    grep -q "pod-1" "${CACHE_DIR}/pods"
    grep -q "pod-2" "${CACHE_DIR}/pods"
    ! grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "refresh_cache: preserves containers cache when kubectl fails and valid cache exists" {
    save_state "pods"
    cat > "${CACHE_DIR}/pods" <<'EOF'
pod-1    1/1   Running   0   1d
EOF
    cat > "${CACHE_DIR}/containers" <<'EOF'
POD       CONTAINER     READY
pod-1     container-1   true
EOF
    mock_kubectl 1 "connection refused"

    refresh_cache || true

    # Containers cache should be preserved
    grep -q "container-1" "${CACHE_DIR}/containers"
    ! grep -q "Loading..." "${CACHE_DIR}/containers"
}

# ============================================================================
# refresh_cache() tests - mode handling
# ============================================================================

@test "refresh_cache: only refreshes pods/containers in pods mode" {
    save_state "pods"
    mock_kubectl 0 '{"items":[]}'

    run refresh_cache
    [ "$status" -eq 0 ]
}

@test "refresh_cache: only refreshes pods/containers in containers mode" {
    save_state "containers" "my-pod"
    mock_kubectl 0 '{"items":[]}'

    run refresh_cache
    [ "$status" -eq 0 ]
}

# ============================================================================
# refresh_objects_cache() tests
# ============================================================================

@test "refresh_objects_cache: creates cache file for resource" {
    mock_kubectl 0 "NAME        READY   STATUS"

    refresh_objects_cache "Deployments"

    [ -f "${CACHE_DIR}/Deployments.cache" ]
    grep -q "NAME" "${CACHE_DIR}/Deployments.cache"
}

@test "refresh_objects_cache: writes error on failure" {
    mock_kubectl 1 "error"

    refresh_objects_cache "Deployments"

    [ -f "${CACHE_DIR}/Deployments.cache" ]
    grep -q "Error" "${CACHE_DIR}/Deployments.cache"
}

# ============================================================================
# Integration tests - simulating startup scenario
# ============================================================================

@test "startup scenario: fresh start shows loading then error" {
    # Simulate fresh start - no cache exists
    rm -rf "$CACHE_DIR"
    mkdir -p "$CACHE_DIR"

    # Initialize creates loading placeholder
    initialize_cache
    grep -q "Loading pod data" "${CACHE_DIR}/pods"

    # First refresh fails
    save_state "pods"
    mock_kubectl 1 "connection refused"
    refresh_cache || true

    # Should show error since only placeholder existed
    grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "startup scenario: with existing cache, preserves data on transient failure" {
    # Simulate previous session left valid cache
    mkdir -p "$CACHE_DIR"
    cat > "${CACHE_DIR}/pods" <<'EOF'
my-app-pod-1    1/1   Running   0   5d
my-app-pod-2    1/1   Running   0   5d
EOF

    # Initialize should preserve it
    initialize_cache
    grep -q "my-app-pod-1" "${CACHE_DIR}/pods"

    # First refresh fails (transient network issue)
    save_state "pods"
    mock_kubectl 1 "connection refused"
    refresh_cache || true

    # Cache should still have the old data
    grep -q "my-app-pod-1" "${CACHE_DIR}/pods"
    grep -q "my-app-pod-2" "${CACHE_DIR}/pods"
    ! grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "startup scenario: successful refresh updates cache" {
    # Start with old cache
    mkdir -p "$CACHE_DIR"
    echo "old-pod    1/1   Running   0   10d" > "${CACHE_DIR}/pods"

    # Mock successful kubectl
    mock_kubectl 0 '{"items":[]}'

    save_state "pods"
    refresh_cache

    # raw_data.json should be created
    [ -f "${CACHE_DIR}/raw_data.json" ]
    # Mock FORMAT_PODS creates pod-mock
    grep -q "pod-mock" "${CACHE_DIR}/pods"
}
