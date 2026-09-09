#!/usr/bin/env bats
# ============================================================================
# Tests for the editor CTRL-V hands the log stream off to
#
# The editor runs with no user config, which also drops the user's own quit
# mapping, so browse_logs supplies one. The binding is a single string that fzf
# re-parses through a shell, so what matters is that the mapping survives that
# round trip as one argument rather than splitting on its spaces.
# ============================================================================

bats_require_minimum_version 1.5.0

load test_helper

setup() {
    setup_test_env
    source "${LIB_DIR}/core.sh"
    source "${LIB_DIR}/actions.sh"
    stub_fzf_recording_args
    mock_kubectl 0 "a log line"
}

teardown() {
    teardown_test_env
}

# fzf stand-in that records its own argv and drains the stream, so a test can
# read back the bindings browse_logs asked for.
stub_fzf_recording_args() {
    mkdir -p "${TEST_TMPDIR}/bin"
    export FZF_ARGS="${TEST_TMPDIR}/fzf-args"
    cat >"${TEST_TMPDIR}/bin/fzf" <<MOCK_SCRIPT
#!/bin/bash
printf '%s\n' "\$@" >"${FZF_ARGS}"
cat >/dev/null
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/fzf"
    export PATH="${TEST_TMPDIR}/bin:${PATH}"
}

# The ctrl-v binding, with fzf's own placeholders left as they are.
ctrl_v_command() {
    sed -n 's/^--bind=ctrl-v:execute(\(.*\))$/\1/p' "$FZF_ARGS"
}

@test "the log editor binds q to quit" {
    run browse_logs "some-pod" "" "${TEST_TMPDIR}/spill" ""
    [ "$status" -eq 0 ]

    [[ "$(ctrl_v_command)" == *"nnoremap q :qa!"* ]]
}

@test "the quit mapping reaches the editor as one argument" {
    run browse_logs "some-pod" "" "${TEST_TMPDIR}/spill" ""
    [ "$status" -eq 0 ]

    # Exactly what fzf does with an execute binding: hand the string to a shell.
    local command
    command="$(ctrl_v_command)"
    command="${command//\{1\}/7}"
    run bash -c "nvim() { printf '[%s]\n' \"\$@\"; }; $command"

    [ "$status" -eq 0 ]
    [[ "$output" == *"[+nnoremap q :qa!<CR>]"* ]]
    [[ "$output" == *"[+7]"* ]]
}

@test "overriding the editor replaces the mapping along with the command" {
    export KGP_LOG_EDITOR="some-other-editor"

    run browse_logs "some-pod" "" "${TEST_TMPDIR}/spill" ""
    [ "$status" -eq 0 ]

    [[ "$(ctrl_v_command)" == *"some-other-editor"* ]]
    [[ "$(ctrl_v_command)" != *"nnoremap"* ]]
}
