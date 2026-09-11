#!/usr/bin/env bats
# ============================================================================
# End-to-end tests for the refresh path
#
# refresh.bats covers the loop with fzf stubbed out. These tests run the real
# thing: kgp in a terminal, a real fzf holding the list, and the loop's POST
# going to the port that fzf actually opened. That is the only level at which a
# broken redraw shows up, because the loop can do everything right and still
# leave a stale or empty list on screen.
# ============================================================================

load test_helper

setup() {
    require_terminal_harness
    setup_test_env
    export PODS_JSON="${TEST_TMPDIR}/pods.json"
    write_pods_json "$PODS_JSON" alpha-pod
    mock_kubectl_from_file "$PODS_JSON"
}

teardown() {
    stop_kgp_in_tmux
    teardown_test_env
}

pane_free_of_warning() {
    # Matched on the warning sign alone, without the emoji variation selector
    # that follows it in the header: a terminal that drops the selector would
    # otherwise make this negative check pass with the warning still on screen.
    ! pane_has "⚠"
}

@test "e2e: the list redraws with new pods while sitting idle" {
    start_kgp_in_tmux

    wait_for 20 pane_has "alpha-pod" || {
        echo "initial list never appeared:"
        pane_text
        return 1
    }

    write_pods_json "$PODS_JSON" alpha-pod beta-pod

    # No keys are sent: fzf has to redraw because the loop told it to.
    wait_for 20 pane_has "beta-pod" || {
        echo "list never picked up the new pod:"
        pane_text
        return 1
    }
}

@test "e2e: the list redraws when the login shell is not bash" {
    # The failure this guards against: fzf runs reload(display_data) through
    # $SHELL, and under a shell that cannot see exported bash functions the
    # reload returns nothing, so the first refresh blanks the list instead of
    # updating it.
    local not_bash
    not_bash="$(create_non_bash_shell)"

    start_kgp_in_tmux "SHELL='${not_bash}'"

    wait_for 20 pane_has "alpha-pod" || {
        echo "initial list never appeared:"
        pane_text
        return 1
    }

    write_pods_json "$PODS_JSON" alpha-pod beta-pod

    wait_for 20 pane_has "beta-pod" || {
        echo "list never picked up the new pod:"
        pane_text
        return 1
    }

    ! pane_has "Command failed"
}

@test "e2e: a refresh does not blank a list it cannot improve" {
    start_kgp_in_tmux
    wait_for 20 pane_has "alpha-pod" || {
        echo "initial list never appeared:"
        pane_text
        return 1
    }

    # Cluster goes away. Several refresh intervals pass.
    rm -f "$PODS_JSON"
    sleep 4

    wait_for 10 pane_has "alpha-pod"
}

@test "e2e: an expired login is called out in the header, not hidden" {
    start_kgp_in_tmux

    wait_for 20 pane_has "alpha-pod" || {
        echo "initial list never appeared:"
        pane_text
        return 1
    }

    # The login expires. kubectl starts failing, the cached list stays on screen,
    # and without a warning there is nothing to tell the two states apart.
    touch "${TEST_TMPDIR}/expired"

    wait_for 20 pane_has "credentials expired" || {
        echo "no warning appeared after the login expired:"
        pane_text
        return 1
    }

    # The pods stay listed: stale data beats an empty screen, as long as it says so.
    wait_for 10 pane_has "alpha-pod"
}

@test "e2e: the warning goes away after logging back in" {
    start_kgp_in_tmux
    wait_for 20 pane_has "alpha-pod" || {
        echo "initial list never appeared:"
        pane_text
        return 1
    }

    touch "${TEST_TMPDIR}/expired"
    wait_for 20 pane_has "credentials expired" || {
        echo "no warning appeared after the login expired:"
        pane_text
        return 1
    }

    rm -f "${TEST_TMPDIR}/expired"

    wait_for 20 pane_free_of_warning || {
        echo "warning stayed after the cluster answered again:"
        pane_text
        return 1
    }
    wait_for 10 pane_has "alpha-pod"
}
