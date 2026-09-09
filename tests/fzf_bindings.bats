#!/usr/bin/env bats
# ============================================================================
# Tests for the shell fzf bindings run in
#
# fzf executes the command string of a reload or execute binding through $SHELL.
# Every one of those commands is a bash function exported with export -f, which
# only a bash child can see, so under a login shell such as fish the bindings
# fail and the pod list empties out on the first background refresh.
# ============================================================================

bats_require_minimum_version 1.5.0

load test_helper

setup() {
    setup_test_env
    mock_kubectl_smart
}

teardown() {
    teardown_test_env
}

@test "kgp points SHELL at bash so fzf bindings can see exported functions" {
    export SHELL="$(create_non_bash_shell)"

    source_kgp

    [[ "$(basename "$SHELL")" == "bash" ]]
    [[ -x "$SHELL" ]]
}

@test "display_data succeeds through \$SHELL when the login shell is not bash" {
    export SHELL="$(create_non_bash_shell)"

    source_kgp
    echo "regression-pod  1/1  Running  0  1d" >"${CACHE_DIR}/pods"

    # Exactly what fzf does for reload(display_data).
    run "$SHELL" -c display_data

    [ "$status" -eq 0 ]
    [[ "$output" == *"regression-pod"* ]]
}

@test "the non-bash shell stand-in really does drop exported functions" {
    local not_bash
    not_bash="$(create_non_bash_shell)"
    hello() { echo "hello from a bash function"; }
    export -f hello

    run -127 "$not_bash" -c hello

    run bash -c hello
    [ "$status" -eq 0 ]
}
