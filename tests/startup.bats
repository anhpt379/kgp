#!/usr/bin/env bats
# ============================================================================
# Tests for the setup path kgp runs before fzf takes over
#
# The refresh loop's own failure handling is covered in refresh.bats, and the
# header warning in refresh_e2e.bats. What is covered here is the first refresh,
# which runs at the top level of a script under set -e: a cluster that refuses on
# that very first call used to abort kgp right there, and because kubectl's
# complaint is captured for classification rather than printed, the abort left
# nothing on screen at all -- an expired token looked like kgp doing nothing.
#
# These tests run kgp as its own process, because that is the only level at which
# set -e can abort it: bats' own `run` turns errexit off, and a sourced kgp under
# `|| true` is exempt from it too, so both would pass against the bug.
# ============================================================================

load test_helper

setup() {
    setup_test_env
    export PODS_JSON="${TEST_TMPDIR}/pods.json"
    write_pods_json "$PODS_JSON" alpha-pod
    mock_kubectl_from_file "$PODS_JSON"
    mock_fzf_recorder

    # Where kgp puts its cache, given the dirs run_kgp hands it.
    KGP_CACHE_UNDER_TEST="${TEST_TMPDIR}/kgp-cache/test-context/test-namespace"
}

teardown() {
    teardown_test_env
}

@test "startup: an expired login still opens the view" {
    touch "${TEST_TMPDIR}/expired"

    run run_kgp

    [ "$status" -eq 0 ]
    [ -s "$FZF_LOG" ]
}

@test "startup: an expired login says so in the list kgp opens on" {
    touch "${TEST_TMPDIR}/expired"

    run run_kgp

    grep -q "credentials expired" "$FZF_LOG"
    grep -q "Unable to connect" "$FZF_LOG"
}

@test "startup: an unreachable cluster opens the view too" {
    rm -f "$PODS_JSON"

    run run_kgp

    [ "$status" -eq 0 ]
    grep -q "Unable to connect" "$FZF_LOG"
}

@test "startup: a working first refresh is unaffected" {
    run run_kgp

    [ "$status" -eq 0 ]
    grep -q "alpha-pod" "$FZF_LOG"
    [ ! -f "${KGP_CACHE_UNDER_TEST}/.refresh_error" ]
}

@test "startup: a cold cache is filled before the view opens" {
    # Nothing on disk but the placeholder, so there is no list to open on and the
    # fetch has to come first.
    run run_kgp

    [ "$status" -eq 0 ]
    assert_file_contains "$KUBECTL_CALLS_AT_FZF" "get pods -o json"
    grep -q "alpha-pod" "$FZF_LOG"
}

@test "startup: a warm cache opens without waiting on the cluster" {
    # A first run leaves a populated cache behind, which is what a second launch
    # on the same context finds.
    run run_kgp
    [ "$status" -eq 0 ]
    assert_file_contains "${KGP_CACHE_UNDER_TEST}/pods" "alpha-pod"

    # The cluster now reports a different pod, so the list fzf is handed says
    # which copy it came from.
    write_pods_json "$PODS_JSON" beta-pod
    : >"$KUBECTL_CALLS"

    run run_kgp

    [ "$status" -eq 0 ]
    # The regression: kgp used to fetch here too, so opening the view waited on a
    # whole cluster round trip to show a list that was already on disk.
    assert_file_not_contains "$KUBECTL_CALLS_AT_FZF" "get pods -o json"
    grep -q "alpha-pod" "$FZF_LOG"
}

@test "startup: the placeholder alone does not count as a warm cache" {
    # initialize_cache writes this before anything has been fetched, and it must
    # not be mistaken for a list worth opening on.
    mkdir -p "$KGP_CACHE_UNDER_TEST"
    echo "Loading pod data from cluster test-context..." \
        >"${KGP_CACHE_UNDER_TEST}/pods"

    run run_kgp

    [ "$status" -eq 0 ]
    assert_file_contains "$KUBECTL_CALLS_AT_FZF" "get pods -o json"
}
