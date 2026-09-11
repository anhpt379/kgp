#!/usr/bin/env bats
# ============================================================================
# Tests for the self-sizing log preview pane
#
# The pane holds the untruncated text of the line under the cursor, so its right
# height is however many rows that one line wraps into. log_preview_window works
# that out and hands fzf a change-preview-window spec on every focus change.
#
# The pane also keeps blank rows above and below the text, which fzf has no
# option for, so they are printed into the preview and added to the height.
#
# The hidden state is the subtle part: change-preview-window re-shows a hidden
# preview, so a plain toggle-preview binding would be undone by the next cursor
# move. The flag file beside the spill is what keeps CTRL-/ sticky.
# ============================================================================

bats_require_minimum_version 1.5.0

load test_helper

setup() {
    setup_test_env
    source "${LIB_DIR}/core.sh"
    source "${LIB_DIR}/actions.sh"

    SPILL="${TEST_TMPDIR}/spill"
}

teardown() {
    teardown_test_env
}

# The row count out of a change-preview-window spec.
spec_rows() {
    sed -n 's/^change-preview-window(down,\([0-9]*\),.*$/\1/p'
}

# The same count with the blank padding rows discounted, which is what the wrap
# arithmetic is actually about.
text_rows() {
    local rows
    rows="$(spec_rows)"
    echo $(( rows - LOG_PREVIEW_PAD_TOP - LOG_PREVIEW_PAD_BOTTOM ))
}

@test "a line that fits on one row gets a one row pane" {
    echo "short line" >"$SPILL"

    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 1 ]
}

@test "the pane carries blank rows above and below the text" {
    echo "short line" >"$SPILL"

    # One blank row, the line, two blank rows. Written to a file because bats
    # trims the blank rows off $output, which is exactly what is under test.
    local rendered="${TEST_TMPDIR}/rendered"
    preview_log_line "$SPILL" 1 >"$rendered"

    [ "$(wc -l <"$rendered")" -eq 4 ]
    [ -z "$(sed -n '1p;3p;4p' "$rendered" | tr -d '\n')" ]
    [ "$(sed -n 2p "$rendered")" = "short line" ]

    # And the pane is tall enough to hold them, or fzf would clip the text.
    run -0 log_preview_window "$SPILL" 1 80
    [ "$(spec_rows <<<"$output")" -eq 4 ]
}

@test "the pane is sized against the preview width, not the window width" {
    # fzf reports the width of the whole window, and the preview content is one
    # column narrower. A line of exactly that width still fits on one row.
    printf '%79s\n' "" | tr ' ' x >"$SPILL"

    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 1 ]

    # One character more and it has to wrap.
    printf '%80s\n' "" | tr ' ' x >"$SPILL"

    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 2 ]
}

@test "a long line gets the rows it wraps into" {
    printf '%200s\n' "" | tr ' ' x >"$SPILL"

    # 200 characters over a 79 column pane.
    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 3 ]
}

@test "a huge line stops growing and scrolls instead" {
    printf '%5000s\n' "" | tr ' ' x >"$SPILL"

    # The clamp is on the text, so padding is added on top of it rather than
    # taken out of the ten rows a long line gets to fill.
    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 10 ]
}

@test "a tab is measured as the screen width it takes, not one character" {
    printf 'a\tb\tc\n' >"$SPILL"

    # Three tab stops plus three characters is more than a ten column pane.
    run -0 log_preview_window "$SPILL" 1 11
    [ "$(text_rows <<<"$output")" -gt 1 ]
}

@test "the pane is sized for the line under the cursor" {
    {
        echo "short"
        printf '%200s\n' "" | tr ' ' x
    } >"$SPILL"

    run -0 log_preview_window "$SPILL" 1 80
    [ "$(text_rows <<<"$output")" -eq 1 ]

    run -0 log_preview_window "$SPILL" 2 80
    [ "$(text_rows <<<"$output")" -eq 3 ]
}

@test "a missing width falls back to a spec fzf can use" {
    printf '%200s\n' "" | tr ' ' x >"$SPILL"

    run -0 log_preview_window "$SPILL" 1
    [[ "$output" == change-preview-window\(down,[0-9]*,wrap,border-top\) ]]
}

@test "a line that cannot be read still yields one row" {
    : >"$SPILL"

    run -0 log_preview_window "$SPILL" 4 80
    [ "$(text_rows <<<"$output")" -eq 1 ]

    run -0 log_preview_window "${TEST_TMPDIR}/no-such-spill" 1 80
    [ "$(text_rows <<<"$output")" -eq 1 ]
}

@test "toggling hides the pane and keeps it hidden across cursor moves" {
    printf '%200s\n' "" | tr ' ' x >"$SPILL"

    run -0 toggle_log_preview "$SPILL"

    # Every later focus change repeats the hidden state back to fzf, which is
    # what stops change-preview-window from re-showing the pane.
    run -0 log_preview_window "$SPILL" 1 80
    [[ "$output" == *hidden* ]]

    run -0 log_preview_window "$SPILL" 2 80
    [[ "$output" == *hidden* ]]
}

@test "toggling again brings the pane back at the size of the line" {
    printf '%200s\n' "" | tr ' ' x >"$SPILL"

    toggle_log_preview "$SPILL"
    run -0 toggle_log_preview "$SPILL"

    run -0 log_preview_window "$SPILL" 1 80
    [[ "$output" != *hidden* ]]
    [ "$(text_rows <<<"$output")" -eq 3 ]
}

@test "the viewer asks fzf to resize the pane on every focus change" {
    stub_fzf_recording_args
    mock_kubectl 0 "a log line"

    run -0 browse_logs "some-pod" "" "$SPILL" ""

    # fzf's own line number placeholder and column count have to survive into
    # the binding, since that is what tells the helper which line to measure.
    grep -q -- "^--bind=focus:transform:log_preview_window '${SPILL}' {1} \$FZF_COLUMNS$" "$FZF_ARGS"
}

@test "CTRL-/ toggles through the flag file rather than fzf's own action" {
    stub_fzf_recording_args
    mock_kubectl 0 "a log line"

    run -0 browse_logs "some-pod" "" "$SPILL" ""

    # toggle-preview on its own would be undone by the next cursor move.
    ! grep -q -- "^--bind=ctrl-/:toggle-preview$" "$FZF_ARGS"
    grep -q -- "^--bind=ctrl-/:execute-silent(toggle_log_preview '${SPILL}')+transform:log_preview_window " "$FZF_ARGS"
}

@test "the viewer cleans up the flag file it left behind" {
    mock_kubectl 0 "a log line"
    stub_fzf_recording_args
    export LOG_SPILL_DIR="${TEST_TMPDIR}/spills"

    # As if the viewer had been left with the preview hidden.
    KGP_TEST_HIDE_PREVIEW=1 run -0 view_logs "some-pod" ""

    run -0 bash -c "ls '${LOG_SPILL_DIR}'"
    [ -z "$output" ]
}

# fzf stand-in that records its own argv and drains the stream, so a test can
# read back the bindings browse_logs asked for. It also hides the preview when
# asked, standing in for a user pressing CTRL-/ before leaving.
stub_fzf_recording_args() {
    mkdir -p "${TEST_TMPDIR}/bin"
    export FZF_ARGS="${TEST_TMPDIR}/fzf-args"
    cat >"${TEST_TMPDIR}/bin/fzf" <<MOCK_SCRIPT
#!/bin/bash
printf '%s\n' "\$@" >"${FZF_ARGS}"
if [[ "\${KGP_TEST_HIDE_PREVIEW:-0}" == "1" ]]; then
    spill="\$(sed -n 's/^--preview=preview_log_line .\(.*\). {1}$/\1/p' "${FZF_ARGS}")"
    : >"\${spill}.nopreview"
fi
cat >/dev/null
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/fzf"
    export PATH="${TEST_TMPDIR}/bin:${PATH}"
}
