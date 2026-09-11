#!/bin/bash
# ============================================================================
# Test helper - common setup for all bats tests
# ============================================================================

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${PROJECT_ROOT}/lib"

# Setup test environment
setup_test_env() {
    # Create temporary directories for testing
    export TEST_TMPDIR=$(mktemp -d)
    export CACHE_BASE_DIR="${TEST_TMPDIR}/cache"
    export STATE_FILE="${TEST_TMPDIR}/.state"
    export CACHE_DIR="${CACHE_BASE_DIR}/test-context/test-namespace"

    mkdir -p "$CACHE_DIR"

    # Set required color variables
    export RED='\033[0;31m'
    export GREEN='\033[0;32m'
    export YELLOW='\033[0;33m'
    export ORANGE='\033[38;5;214m'
    export CYAN='\033[0;36m'
    export GRAY='\033[0;90m'
    export MAGENTA='\033[0;35m'
    export WHITE='\033[0;37m'
    export RESET='\033[0m'

    # Set context variables
    export CONTEXT="test-context"
    export NAMESPACE="test-namespace"
    export MODE="pods"
    export POD=""
    export RESOURCE=""
    export OBJECT=""

    # Disable debug logging during tests
    export KGP_DEBUG=0

    # Create a mock FORMAT_PODS script
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/format-pods.py" <<'MOCK_SCRIPT'
#!/bin/bash
# Mock format-pods.py - just creates empty cache files
while [[ $# -gt 0 ]]; do
    case $1 in
        -i) INPUT="$2"; shift 2 ;;
        -o) OUTPUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo "pod-mock    1/1   Running   0   1d" > "${OUTPUT}/pods"
echo "POD         CONTAINER   READY" > "${OUTPUT}/containers"
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/format-pods.py"
    export FORMAT_PODS="${TEST_TMPDIR}/bin/format-pods.py"
}

# Cleanup test environment
teardown_test_env() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Source library files
source_libs() {
    source "${LIB_DIR}/core.sh"
    source "${LIB_DIR}/state.sh"
    source "${LIB_DIR}/cache.sh"
    source "${LIB_DIR}/k8s.sh"
    source "${LIB_DIR}/display.sh"
}

# Mock kubectl command
mock_kubectl() {
    local exit_code="${1:-0}"
    local output="${2:-}"

    # Create a mock script in the temp directory
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/kubectl" <<MOCK_SCRIPT
#!/bin/bash
if [[ -n "$output" ]]; then
    echo "$output"
fi
exit $exit_code
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/kubectl"
    export PATH="${TEST_TMPDIR}/bin:$PATH"
}

# Mock kubectl to return specific output for different subcommands
mock_kubectl_smart() {
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/kubectl" <<'MOCK_SCRIPT'
#!/bin/bash
case "$1" in
    config)
        case "$2" in
            current-context)
                echo "test-context"
                ;;
            view)
                echo "test-namespace"
                ;;
            get-contexts)
                echo -e "context-1\ncontext-2\ntest-context"
                ;;
            use-context)
                exit 0
                ;;
        esac
        ;;
    get)
        if [[ "$2" == "pods" ]]; then
            echo '{"items":[]}'
        fi
        ;;
    *)
        exit 0
        ;;
esac
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/kubectl"
    export PATH="${TEST_TMPDIR}/bin:$PATH"
}

# Create a sample pods cache file
create_sample_pods_cache() {
    cat > "${CACHE_DIR}/pods" <<'EOF'
pod-1                    1/1   Running   0   1d
pod-2                    2/2   Running   0   2d
pod-3                    1/1   Pending   0   1h
EOF
}

# Create a sample containers cache file
create_sample_containers_cache() {
    cat > "${CACHE_DIR}/containers" <<'EOF'
POD                      CONTAINER        READY   RESTARTS   AGE
pod-1                    container-1      true    0          1d
pod-2                    container-2a     true    0          2d
pod-2                    container-2b     true    0          2d
EOF
}

# Assert file contains string
assert_file_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -q "$expected" "$file"; then
        echo "Expected file '$file' to contain '$expected'"
        echo "Actual content:"
        cat "$file"
        return 1
    fi
}

# Assert file does not contain string
assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"

    if grep -q "$unexpected" "$file"; then
        echo "Expected file '$file' NOT to contain '$unexpected'"
        echo "Actual content:"
        cat "$file"
        return 1
    fi
}

# Stand in for a login shell that does not import bash's exported functions,
# which is how fish behaves. fzf runs every binding command through $SHELL, so
# this is what a binding faces when kgp does not pick the shell itself.
create_non_bash_shell() {
    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/not-bash" <<'MOCK_SHELL'
#!/bin/bash
[[ "$1" == "-c" ]] || exit 127
strip=()
while read -r name; do
    strip+=(-u "$name")
done < <(env | sed -n 's/^\(BASH_FUNC_[^=]*\)=.*/\1/p')
exec env "${strip[@]}" bash --noprofile --norc -c "$2"
MOCK_SHELL
    chmod +x "${TEST_TMPDIR}/bin/not-bash"
    echo "${TEST_TMPDIR}/bin/not-bash"
}

# Run kgp's setup the way the real entry point does, stopping short of the fzf
# call, which kgp itself guards with a BASH_SOURCE check.
source_kgp() {
    export KGP_CACHE_DIR="${TEST_TMPDIR}/kgp-cache"
    export KGP_LOG_DIR="${TEST_TMPDIR}/kgp-logs"
    source "${PROJECT_ROOT}/kgp"
}

# Poll for a condition instead of sleeping a fixed guess, so tests that wait on
# the background refresh loop stay quick without being timing-fragile.
wait_for() {
    local timeout="$1"
    shift
    local deadline=$((SECONDS + timeout))

    while ((SECONDS <= deadline)); do
        if "$@"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# kubectl stand-in that serves pod JSON from a file, so a test can change what
# the cluster reports mid-run. Deleting the file makes kubectl fail. Every call
# is recorded in $KUBECTL_CALLS.
mock_kubectl_from_file() {
    local pods_json="$1"

    mkdir -p "${TEST_TMPDIR}/bin"
    export KUBECTL_CALLS="${TEST_TMPDIR}/kubectl-calls"
    : >"$KUBECTL_CALLS"

    cat >"${TEST_TMPDIR}/bin/kubectl" <<MOCK_SCRIPT
#!/bin/bash
echo "\$*" >>"${KUBECTL_CALLS}"
case "\$*" in
"config current-context")
    echo "test-context"
    ;;
"config view --minify --output jsonpath={..namespace}")
    echo "test-namespace"
    ;;
"get pods -o json")
    # Stand in for an expired login, which is a failure with a message rather
    # than a missing cluster.
    if [[ -f "${TEST_TMPDIR}/expired" ]]; then
        echo "error: You must be logged in to the server (Unauthorized)" >&2
        exit 1
    fi
    [[ -f "${pods_json}" ]] || exit 1
    cat "${pods_json}"
    ;;
*)
    exit 0
    ;;
esac
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/kubectl"
    export PATH="${TEST_TMPDIR}/bin:$PATH"
}

# Write pod JSON in the shape format-pods.py reads, one entry per name given.
write_pods_json() {
    local target="$1"
    shift

    python3 - "$target" "$@" <<'PY'
import json, sys

target, names = sys.argv[1], sys.argv[2:]
items = []
for name in names:
    items.append({
        "metadata": {"name": name, "namespace": "test-namespace",
                     "creationTimestamp": "2026-01-01T00:00:00Z"},
        "spec": {"containers": [{"name": "app", "image": "registry/app:1.0"}],
                 "nodeName": "node-1"},
        "status": {"phase": "Running", "podIP": "10.0.0.1",
                   "startTime": "2026-01-01T00:00:00Z",
                   "containerStatuses": [{
                       "name": "app", "image": "registry/app:1.0",
                       "ready": True, "restartCount": 0,
                       "state": {"running": {"startedAt": "2026-01-01T00:00:00Z"}}}],
                   "conditions": [{"type": "Ready", "status": "True"}]},
    })
with open(target, "w") as handle:
    json.dump({"apiVersion": "v1", "kind": "List", "items": items}, handle)
PY
}

# format-pods.py stand-in that carries pod names through to the cache, so a test
# can tell one refresh from the next by what the cache holds.
mock_format_pods_names() {
    mkdir -p "${TEST_TMPDIR}/bin"
    cat >"${TEST_TMPDIR}/bin/format-pods.py" <<'MOCK_SCRIPT'
#!/usr/bin/env python3
import json, sys

args = sys.argv[1:]
source = args[args.index("-i") + 1]
target = args[args.index("-o") + 1]

with open(source) as handle:
    names = [i["metadata"]["name"] for i in json.load(handle).get("items", [])]

with open(f"{target}/pods", "w") as handle:
    handle.write("NAME  READY  STATUS  RESTARTS  AGE\n")
    for name in names:
        handle.write(f"{name}  1/1  Running  0  1d\n")

with open(f"{target}/containers", "w") as handle:
    handle.write("POD  CONTAINER  READY\n")
    for name in names:
        handle.write(f"{name}  app  true\n")
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/format-pods.py"
    export FORMAT_PODS="${TEST_TMPDIR}/bin/format-pods.py"
}

# curl stand-in that records the reload requests the refresh loop fires at fzf.
mock_curl_recorder() {
    mkdir -p "${TEST_TMPDIR}/bin"
    export CURL_LOG="${TEST_TMPDIR}/curl.log"
    : >"$CURL_LOG"

    cat >"${TEST_TMPDIR}/bin/curl" <<MOCK_SCRIPT
#!/bin/bash
echo "\$*" >>"${CURL_LOG}"
exit 0
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/curl"
    export PATH="${TEST_TMPDIR}/bin:$PATH"
}

# ============================================================================
# End-to-end helpers: a real kgp, with a real fzf, in a real terminal
# ============================================================================

# fzf needs a tty, so the end-to-end tests drive kgp inside tmux and read the
# pane back. Both are optional: tests that need them skip when they are absent.
require_terminal_harness() {
    command -v tmux >/dev/null 2>&1 || skip "tmux is not installed"
    command -v fzf >/dev/null 2>&1 || skip "fzf is not installed"
}

# Launch the real kgp entry point in tmux. Extra arguments are passed to env, so
# a test can set things like SHELL for the run.
start_kgp_in_tmux() {
    export KGP_TMUX_SESSION="kgp-test-$$-${BATS_TEST_NUMBER:-0}"
    tmux kill-session -t "$KGP_TMUX_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$KGP_TMUX_SESSION" -x 120 -y 30 \
        "env PATH='${PATH}' \
             KGP_CACHE_DIR='${TEST_TMPDIR}/kgp-cache' \
             KGP_LOG_DIR='${TEST_TMPDIR}/kgp-logs' \
             KGP_CACHE_REFRESH=1 \
             KGP_DEBUG=0 \
             $* \
             '${PROJECT_ROOT}/kgp'; sleep 60"
}

stop_kgp_in_tmux() {
    if [[ -n "${KGP_TMUX_SESSION:-}" ]]; then
        tmux kill-session -t "$KGP_TMUX_SESSION" 2>/dev/null || true
        KGP_TMUX_SESSION=""
    fi
}

pane_text() {
    tmux capture-pane -p -t "$KGP_TMUX_SESSION" 2>/dev/null || true
}

pane_has() {
    pane_text | grep -q -- "$1"
}

# fzf stand-in that records that it was reached and what list it was handed.
# Lets a test run the real kgp entry point as its own process -- the only way to
# see set -e abort the startup path -- without needing a terminal.
mock_fzf_recorder() {
    mkdir -p "${TEST_TMPDIR}/bin"
    export FZF_LOG="${TEST_TMPDIR}/fzf.log"
    rm -f "$FZF_LOG"

    cat >"${TEST_TMPDIR}/bin/fzf" <<MOCK_SCRIPT
#!/bin/bash
cat >"${FZF_LOG}"
MOCK_SCRIPT
    chmod +x "${TEST_TMPDIR}/bin/fzf"
    export PATH="${TEST_TMPDIR}/bin:$PATH"
}

# Run the real kgp entry point as a separate process, with fzf stubbed out.
run_kgp() {
    env PATH="$PATH" \
        KGP_CACHE_DIR="${TEST_TMPDIR}/kgp-cache" \
        KGP_LOG_DIR="${TEST_TMPDIR}/kgp-logs" \
        KGP_CACHE_REFRESH=60 \
        KGP_DEBUG=0 \
        "${PROJECT_ROOT}/kgp" </dev/null
}
