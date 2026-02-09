#!/usr/bin/env bats
# ============================================================================
# Tests for lib/core.sh
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
# debug() tests
# ============================================================================

@test "debug: does nothing when KGP_DEBUG is 0" {
    export KGP_DEBUG=0
    run debug "test message"
    [ "$status" -eq 0 ]
    [ ! -f "/tmp/kgp/debug.log" ] || ! grep -q "test message" "/tmp/kgp/debug.log"
}

@test "debug: writes to log when KGP_DEBUG is 1" {
    export KGP_DEBUG=1
    mkdir -p /tmp/kgp
    debug "test debug message"
    [ -f "/tmp/kgp/debug.log" ]
    grep -q "test debug message" "/tmp/kgp/debug.log"
    # Cleanup
    rm -f /tmp/kgp/debug.log
}

# ============================================================================
# check_dependencies() tests
# ============================================================================

@test "check_dependencies: passes when all commands exist" {
    run check_dependencies "ls" "cat" "echo"
    [ "$status" -eq 0 ]
}

@test "check_dependencies: fails when command is missing" {
    run check_dependencies "nonexistent_command_xyz"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required commands"* ]]
    [[ "$output" == *"nonexistent_command_xyz"* ]]
}

@test "check_dependencies: reports all missing commands" {
    run check_dependencies "missing_cmd_1" "ls" "missing_cmd_2"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing_cmd_1"* ]]
    [[ "$output" == *"missing_cmd_2"* ]]
}

# ============================================================================
# colorize() tests
# ============================================================================

@test "colorize: applies RED color" {
    result=$(colorize RED "test")
    [[ "$result" == *"31m"* ]] || [[ "$result" == *"$RED"* ]]
    [[ "$result" == *"test"* ]]
}

@test "colorize: applies GREEN color" {
    result=$(colorize GREEN "test")
    [[ "$result" == *"32m"* ]] || [[ "$result" == *"$GREEN"* ]]
    [[ "$result" == *"test"* ]]
}

@test "colorize: applies YELLOW color" {
    result=$(colorize YELLOW "test")
    [[ "$result" == *"33m"* ]] || [[ "$result" == *"$YELLOW"* ]]
    [[ "$result" == *"test"* ]]
}

@test "colorize: returns plain text for unknown color" {
    result=$(colorize UNKNOWN "test")
    [ "$result" = "test" ]
}

# ============================================================================
# copy_to_clipboard() tests
# ============================================================================

@test "copy_to_clipboard: fails with empty text" {
    run copy_to_clipboard ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Nothing to copy"* ]]
}
