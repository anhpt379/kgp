#!/usr/bin/env bats
# ============================================================================
# Tests for lib/display.sh
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
# list_pods() tests
# ============================================================================

@test "list_pods: shows header with context and namespace" {
    export CONTEXT="prod-cluster"
    export NAMESPACE="production"

    result=$(list_pods)

    [[ "$result" == *"prod-cluster"* ]]
    [[ "$result" == *"production"* ]]
}

@test "list_pods: shows cached data when available" {
    create_sample_pods_cache

    result=$(list_pods)

    [[ "$result" == *"pod-1"* ]]
    [[ "$result" == *"pod-2"* ]]
    [[ "$result" == *"pod-3"* ]]
}

@test "list_pods: shows loading message when no cache" {
    rm -f "${CACHE_DIR}/pods"

    result=$(list_pods)

    [[ "$result" == *"Loading pod data"* ]]
}

# ============================================================================
# list_containers() tests
# ============================================================================

@test "list_containers: shows header with pod name" {
    export POD="my-pod"
    create_sample_containers_cache

    result=$(list_containers)

    [[ "$result" == *"my-pod"* ]]
}

@test "list_containers: filters containers by pod" {
    export POD="pod-2"
    create_sample_containers_cache

    result=$(list_containers)

    [[ "$result" == *"container-2a"* ]]
    [[ "$result" == *"container-2b"* ]]
}

# ============================================================================
# list_contexts() tests
# ============================================================================

@test "list_contexts: shows current context marked" {
    export CONTEXT="test-context"
    mock_kubectl_smart

    result=$(list_contexts)

    [[ "$result" == *"test-context"* ]]
}

@test "list_contexts: shows header" {
    mock_kubectl_smart

    result=$(list_contexts)

    [[ "$result" == *"NAME"* ]]
}

# ============================================================================
# list_resources() tests
# ============================================================================

@test "list_resources: shows all resource types" {
    result=$(list_resources)

    [[ "$result" == *"Deployments"* ]]
    [[ "$result" == *"StatefulSets"* ]]
    [[ "$result" == *"Services"* ]]
    [[ "$result" == *"ConfigMaps"* ]]
    [[ "$result" == *"Secrets"* ]]
}

@test "list_resources: shows header with context" {
    export CONTEXT="my-context"
    export NAMESPACE="my-namespace"

    result=$(list_resources)

    [[ "$result" == *"my-context"* ]]
    [[ "$result" == *"my-namespace"* ]]
}

# ============================================================================
# list_objects() tests
# ============================================================================

@test "list_objects: shows cached resource data" {
    echo "my-deployment   1/1   1   1d" > "${CACHE_DIR}/Deployments.cache"
    export RESOURCE="Deployments"

    result=$(list_objects "Deployments")

    [[ "$result" == *"my-deployment"* ]]
}

@test "list_objects: refreshes cache if not exists" {
    rm -f "${CACHE_DIR}/Services.cache"
    export RESOURCE="Services"
    mock_kubectl 0 "NAME          TYPE        CLUSTER-IP"

    # This will call refresh_objects_cache
    list_objects "Services" > /dev/null

    [ -f "${CACHE_DIR}/Services.cache" ]
}

# ============================================================================
# display_data() tests
# ============================================================================

@test "display_data: shows pods in pods mode" {
    save_state "pods"
    create_sample_pods_cache

    result=$(display_data)

    [[ "$result" == *"pod-1"* ]]
}

@test "display_data: shows containers in containers mode" {
    export POD="pod-2"
    save_state "containers" "pod-2"
    create_sample_containers_cache

    result=$(display_data)

    [[ "$result" == *"container-2a"* ]]
}

@test "display_data: shows resources in resources mode" {
    save_state "resources"

    result=$(display_data)

    [[ "$result" == *"Deployments"* ]]
    [[ "$result" == *"Services"* ]]
}

@test "display_data: shows objects in objects mode" {
    echo "nginx-deploy   1/1   1   5d" > "${CACHE_DIR}/Deployments.cache"
    save_state "objects" "" "Deployments"
    export RESOURCE="Deployments"

    result=$(display_data)

    [[ "$result" == *"nginx-deploy"* ]]
}

# ============================================================================
# show_help() tests
# ============================================================================

@test "show_help: displays keyboard shortcuts" {
    result=$(show_help)

    [[ "$result" == *"ENTER"* ]]
    [[ "$result" == *"ESC"* ]]
    [[ "$result" == *"CTRL-S"* ]]
    [[ "$result" == *"CTRL-R"* ]]
    [[ "$result" == *"CTRL-E"* ]]
}

@test "show_help: displays context and namespace" {
    export CONTEXT="help-context"
    export NAMESPACE="help-namespace"

    result=$(show_help)

    [[ "$result" == *"help-context"* ]]
    [[ "$result" == *"help-namespace"* ]]
}
