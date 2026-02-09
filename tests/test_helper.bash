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
