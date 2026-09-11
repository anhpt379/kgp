#!/usr/bin/env bats
# ============================================================================
# End-to-end tests for the self-sizing log preview pane
#
# log_preview.bats covers the spec the helper prints. These tests run a real fzf
# in a terminal and read the pane back, because the spec being right and fzf
# acting on it are two different things: change-preview-window has to accept the
# geometry, and it re-shows a hidden preview, which is the whole reason CTRL-/
# carries its own state.
# ============================================================================

bats_require_minimum_version 1.5.0

load test_helper

setup() {
    require_terminal_harness
    setup_test_env

    SPILL="${TEST_TMPDIR}/spill"
    LOG_LINES="${TEST_TMPDIR}/lines"
    {
        echo "[some-pod] a short line"
        printf '[some-pod] %300s\n' "" | tr ' ' x
    } >"$LOG_LINES"

    mock_kubectl_streaming "$LOG_LINES"
    start_log_viewer_in_tmux
}

teardown() {
    stop_kgp_in_tmux
    teardown_test_env
}

# kubectl stand-in that prints the given lines and then holds the stream open,
# so the viewer sees a live follow rather than an immediate EOF.
mock_kubectl_streaming() {
    local lines="$1"

    mkdir -p "${TEST_TMPDIR}/bin"
    cat >"${TEST_TMPDIR}/bin/kubectl" <<MOCK_SCRIPT
#!/bin/bash
cat "${lines}"
sleep 120
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/kubectl"
    export PATH="${TEST_TMPDIR}/bin:${PATH}"
}

# Open the real log viewer in a terminal, with the libraries loaded the way kgp
# loads them: the bindings run through $SHELL and only see exported functions.
start_log_viewer_in_tmux() {
    cat >"${TEST_TMPDIR}/viewer.sh" <<VIEWER
#!/bin/bash
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/actions.sh"
export -f colorize debug highlight_logs print_stream_closed_eof copy_log_lines
export -f preview_log_line read_log_line log_preview_window toggle_log_preview
export -f terminate_tree
export LOG_PREVIEW_PAD_TOP LOG_PREVIEW_PAD_BOTTOM
export SHELL="\$(command -v bash)"
browse_logs "some-pod" "" "${SPILL}" ""
VIEWER

    export KGP_TMUX_SESSION="kgp-preview-$$-${BATS_TEST_NUMBER:-0}"
    tmux kill-session -t "$KGP_TMUX_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$KGP_TMUX_SESSION" -x 80 -y 20 \
        "env PATH='${PATH}' \
             CONTEXT='test-context' \
             NAMESPACE='test-namespace' \
             KGP_DEBUG=0 \
             bash '${TEST_TMPDIR}/viewer.sh'; sleep 120"
}

# How many rows the pane gives the preview, counted from its top border down.
# This includes the blank padding rows above and below the text. Zero when there
# is no border on screen, which is the hidden preview.
preview_rows() {
    pane_text | awk '/──────/ { border = NR } { total = NR } END { print border ? total - border : 0 }'
}

preview_rows_is() {
    [[ "$(preview_rows)" == "$1" ]]
}

@test "e2e: the pane grows to fit a long line and shrinks back for a short one" {
    # The viewer opens on the last line, which is the long one: 300 characters
    # over a 79 column pane needs four rows, plus one blank row above and two
    # below.
    wait_for 20 preview_rows_is 7 || {
        echo "long line never got a seven row pane, saw $(preview_rows):"
        pane_text
        return 1
    }

    tmux send-keys -t "$KGP_TMUX_SESSION" Up

    wait_for 20 preview_rows_is 4 || {
        echo "short line never got a four row pane, saw $(preview_rows):"
        pane_text
        return 1
    }
}

@test "e2e: CTRL-/ hides the pane and a cursor move leaves it hidden" {
    wait_for 20 preview_rows_is 7 || {
        echo "preview never appeared:"
        pane_text
        return 1
    }

    tmux send-keys -t "$KGP_TMUX_SESSION" C-_

    wait_for 20 preview_rows_is 0 || {
        echo "CTRL-/ did not hide the preview:"
        pane_text
        return 1
    }

    # The regression this guards: the focus event resizes the pane, and a resize
    # is what re-shows a preview fzf itself considers hidden.
    tmux send-keys -t "$KGP_TMUX_SESSION" Up
    sleep 1
    preview_rows_is 0 || {
        echo "a cursor move brought the hidden preview back:"
        pane_text
        return 1
    }

    tmux send-keys -t "$KGP_TMUX_SESSION" C-_

    wait_for 20 preview_rows_is 4 || {
        echo "CTRL-/ did not bring the preview back at the size of the line:"
        pane_text
        return 1
    }
}
