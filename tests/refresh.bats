#!/usr/bin/env bats
# ============================================================================
# Tests for the background refresh loop in lib/cache.sh
#
# refresh_cache itself is covered in cache.bats. What these tests cover is the
# loop around it: that it keeps running on its own, that it tells fzf to redraw
# through the port fzf publishes after the loop has already started, that a
# failing cluster does not kill it, and that it can be stopped.
# ============================================================================

load test_helper

setup() {
    setup_test_env
    export PODS_JSON="${TEST_TMPDIR}/pods.json"
    write_pods_json "$PODS_JSON" alpha-pod
    mock_kubectl_from_file "$PODS_JSON"
    mock_format_pods_names
    mock_curl_recorder
    source_libs

    # kgp holds this as a readonly constant; the loop reads it every iteration.
    CACHE_REFRESH_INTERVAL=1
    BG_REFRESH_PID=""

    save_state "pods"
}

teardown() {
    stop_background_refresh
    teardown_test_env
}

cache_has() {
    grep -q "$1" "${CACHE_DIR}/pods" 2>/dev/null
}

curl_log_has() {
    grep -q -- "$1" "$CURL_LOG" 2>/dev/null
}

kubectl_call_count() {
    grep -c "get pods -o json" "$KUBECTL_CALLS" 2>/dev/null || true
}

# A predicate, not a value: wait_for re-runs it, whereas $(...) in the argument
# list would be expanded once and never change.
kubectl_calls_at_least() {
    [ "$(kubectl_call_count)" -ge "$1" ]
}

@test "background refresh: updates the cache without any user input" {
    start_background_refresh

    wait_for 10 cache_has "alpha-pod"

    write_pods_json "$PODS_JSON" alpha-pod beta-pod
    wait_for 10 cache_has "beta-pod"

    cache_has "alpha-pod"
    cache_has "beta-pod"
}

@test "background refresh: drops pods that left the cluster" {
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"

    write_pods_json "$PODS_JSON" beta-pod
    wait_for 10 cache_has "beta-pod"

    ! cache_has "alpha-pod"
}

@test "background refresh: tells fzf to reload on the port from the state file" {
    echo "FZF_PORT=54321" >>"$STATE_FILE"

    start_background_refresh

    wait_for 10 curl_log_has "reload(display_data)"
    curl_log_has "http://localhost:54321"
}

@test "background refresh: picks up the fzf port published after it started" {
    # The loop starts before fzf, so on the first pass there is no port yet. fzf
    # appends one at startup and the loop has to notice on a later pass.
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"
    [ ! -s "$CURL_LOG" ]

    echo "FZF_PORT=45678" >>"$STATE_FILE"

    wait_for 10 curl_log_has "http://localhost:45678"
}

@test "background refresh: does not post anywhere while the port is unknown" {
    start_background_refresh

    wait_for 10 cache_has "alpha-pod"
    sleep 2

    [ ! -s "$CURL_LOG" ]
}

@test "background refresh: ignores a state file port that is not a number" {
    echo "FZF_PORT=not-a-port" >>"$STATE_FILE"

    start_background_refresh

    wait_for 10 cache_has "alpha-pod"
    sleep 2

    [ ! -s "$CURL_LOG" ]
}

@test "background refresh: retries quickly until the cluster first answers" {
    # A long interval must not apply before the first successful refresh, or a
    # cluster that is briefly unreachable at startup leaves the view empty for
    # a full interval.
    CACHE_REFRESH_INTERVAL=3600
    rm -f "$PODS_JSON"

    start_background_refresh

    wait_for 10 kubectl_calls_at_least 3
    [ "$(kubectl_call_count)" -ge 3 ]
}

@test "background refresh: survives a failing cluster and recovers" {
    rm -f "$PODS_JSON"
    start_background_refresh
    wait_for 10 kubectl_calls_at_least 2

    write_pods_json "$PODS_JSON" recovered-pod

    wait_for 10 cache_has "recovered-pod"
}

@test "background refresh: keeps a populated cache when the cluster fails" {
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"

    rm -f "$PODS_JSON"
    sleep 2

    cache_has "alpha-pod"
    ! grep -q "Unable to connect" "${CACHE_DIR}/pods"
}

@test "background refresh: follows a namespace change made mid-run" {
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"

    NAMESPACE="other-namespace"
    save_state "pods"
    local other_cache="${CACHE_BASE_DIR}/test-context/other-namespace"

    wait_for 10 test -f "${other_cache}/pods"
    grep -q "alpha-pod" "${other_cache}/pods"
}

@test "stop_background_refresh: stops the loop and clears the pid" {
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"
    local pid="$BG_REFRESH_PID"

    stop_background_refresh

    [ -z "$BG_REFRESH_PID" ]
    ! kill -0 "$pid" 2>/dev/null

    local before after
    before=$(kubectl_call_count)
    sleep 2
    after=$(kubectl_call_count)
    [ "$before" -eq "$after" ]
}

@test "stop_background_refresh: is safe when nothing is running" {
    BG_REFRESH_PID=""

    run stop_background_refresh

    [ "$status" -eq 0 ]
}

# ============================================================================
# Refresh failure is visible in the header
#
# A refresh that fails while a good cache exists keeps that cache, so the list
# looks live when it is not. Expired credentials are the everyday case: nothing
# breaks, the data just stops moving.
# ============================================================================

fail_kubectl_with() {
    cat >"${TEST_TMPDIR}/bin/kubectl" <<MOCK_SCRIPT
#!/bin/bash
echo "\$*" >>"${KUBECTL_CALLS}"
case "\$*" in
"config current-context") echo "test-context" ;;
"config view --minify --output jsonpath={..namespace}") echo "test-namespace" ;;
"get pods -o json")
    echo "$1" >&2
    exit 1
    ;;
*) exit 0 ;;
esac
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/kubectl"
}

header_has_warning() {
    show_pod_header | grep -q "⚠️"
}

@test "refresh failure: header warns about expired credentials" {
    refresh_cache
    fail_kubectl_with "error: You must be logged in to the server (Unauthorized)"

    refresh_cache || true

    run show_pod_header
    [[ "$output" == *"⚠️"* ]]
    [[ "$output" == *"credentials expired"* ]]
    [[ "$output" == *"F5 to retry"* ]]
}

@test "refresh failure: header names an unreachable cluster differently" {
    refresh_cache
    fail_kubectl_with "Unable to connect to the server: dial tcp 10.0.0.1:443: i/o timeout"

    refresh_cache || true

    run show_pod_header
    [[ "$output" == *"cluster unreachable"* ]]
}

@test "refresh failure: header still warns when the reason is unrecognised" {
    refresh_cache
    fail_kubectl_with "some brand new kubectl complaint"

    refresh_cache || true

    run show_pod_header
    [[ "$output" == *"⚠️"* ]]
    [[ "$output" == *"refresh failing"* ]]
}

@test "refresh failure: a healthy header carries no warning" {
    refresh_cache

    run show_pod_header
    [[ "$output" != *"⚠️"* ]]
}

@test "refresh failure: the warning clears once the cluster answers again" {
    refresh_cache
    fail_kubectl_with "error: You must be logged in to the server (Unauthorized)"
    refresh_cache || true
    header_has_warning

    mock_kubectl_from_file "$PODS_JSON"
    refresh_cache

    ! header_has_warning
}

@test "refresh failure: keeps the first reason and time across repeated failures" {
    refresh_cache
    fail_kubectl_with "error: You must be logged in to the server (Unauthorized)"
    refresh_cache || true
    local first_marker
    first_marker=$(stat -c %Y "${CACHE_DIR}/.refresh_error" 2>/dev/null || stat -f %m "${CACHE_DIR}/.refresh_error")

    sleep 1
    fail_kubectl_with "Unable to connect to the server: dial tcp 10.0.0.1:443: i/o timeout"
    refresh_cache || true

    # The age shown has to keep counting from the first failure, not reset on
    # every attempt, or a long outage reads as a fresh blip.
    local second_marker
    second_marker=$(stat -c %Y "${CACHE_DIR}/.refresh_error" 2>/dev/null || stat -f %m "${CACHE_DIR}/.refresh_error")
    [ "$first_marker" -eq "$second_marker" ]
    show_pod_header | grep -q "credentials expired"
}

@test "refresh failure: the container and object headers warn too" {
    refresh_cache
    fail_kubectl_with "error: You must be logged in to the server (Unauthorized)"
    refresh_cache || true

    POD="alpha-pod"
    RESOURCE="Deployments"

    show_container_header | grep -q "⚠️"
    show_objects_header | grep -q "⚠️"
}

@test "refresh failure: the background loop raises the warning on its own" {
    start_background_refresh
    wait_for 10 cache_has "alpha-pod"
    ! header_has_warning

    fail_kubectl_with "error: You must be logged in to the server (Unauthorized)"

    wait_for 10 header_has_warning
    cache_has "alpha-pod"
}

@test "refresh failure: the age reads in seconds, minutes or hours" {
    local marker="${CACHE_DIR}/.refresh_error"
    echo "refresh failing" >"$marker"

    [[ "$(refresh_error_age "$marker")" == *s ]]

    touch -d "@$(($(date +%s) - 300))" "$marker" 2>/dev/null || touch -t "$(date -v-5M +%Y%m%d%H%M)" "$marker"
    [ "$(refresh_error_age "$marker")" = "5m" ]

    touch -d "@$(($(date +%s) - 7200))" "$marker" 2>/dev/null || touch -t "$(date -v-2H +%Y%m%d%H%M)" "$marker"
    [ "$(refresh_error_age "$marker")" = "2h" ]
}
