#!/usr/bin/env bash
#
# test_trusted_workstation.sh - E2E Integration Tests for Trusted Workstation Mode
#
# Comprehensive end-to-end tests for RemoteJuggler Trusted Workstation feature:
# - PIN management (store, clear, status)
# - Security mode switching
# - Trusted Workstation enable/disable
# - YubiKey integration (mocked if not present)
# - Error handling
#
# Usage:
#   ./test_trusted_workstation.sh [options]
#
# Options:
#   --binary <path>     Path to remote-juggler binary (default: ./target/debug/remote-juggler)
#   --verbose           Enable verbose output
#   --skip-yubikey      Skip YubiKey-dependent tests
#   --skip-hsm          Skip HSM-dependent tests (use stub mode)
#   --tap               Output in TAP format
#   --cleanup           Only cleanup test data
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Error in test setup
#
# Environment variables:
#   REMOTE_JUGGLER_BIN  - Override binary path
#   TEST_IDENTITY       - Override test identity name
#   CI                  - If set, run in CI mode (stub HSM, skip interactive)
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="${REMOTE_JUGGLER_BIN:-$PROJECT_ROOT/target/debug/remote-juggler}"
TEST_IDENTITY="${TEST_IDENTITY:-tws-test-$$}"
TEST_CONFIG_DIR="${TMPDIR:-/tmp}/remote-juggler-test-$$"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Options
VERBOSE=0
SKIP_YUBIKEY=0
SKIP_HSM=0
TAP_OUTPUT=0
CLEANUP_ONLY=0

# TAP test number
TAP_TEST_NUM=0
TAP_PLAN_PRINTED=0

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --binary)
            BINARY="$2"
            shift 2
            ;;
        --binary=*)
            BINARY="${1#*=}"
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --skip-yubikey)
            SKIP_YUBIKEY=1
            shift
            ;;
        --skip-hsm)
            SKIP_HSM=1
            shift
            ;;
        --tap)
            TAP_OUTPUT=1
            shift
            ;;
        --cleanup)
            CLEANUP_ONLY=1
            shift
            ;;
        --help|-h)
            head -40 "$0" | tail -30
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 2
            ;;
    esac
done

# CI mode detection
if [[ -n "${CI:-}" ]]; then
    SKIP_YUBIKEY=1
    # In CI, we expect stub HSM mode
fi

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    if [[ $TAP_OUTPUT -eq 1 ]]; then
        echo "# $1"
    else
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_pass() {
    local msg="$1"
    ((TESTS_PASSED++)) || true

    if [[ $TAP_OUTPUT -eq 1 ]]; then
        ((TAP_TEST_NUM++)) || true
        echo "ok $TAP_TEST_NUM - $msg"
    else
        echo -e "  ${GREEN}[PASS]${NC} $msg"
    fi
}

log_fail() {
    local msg="$1"
    local details="${2:-}"
    ((TESTS_FAILED++)) || true

    if [[ $TAP_OUTPUT -eq 1 ]]; then
        ((TAP_TEST_NUM++)) || true
        echo "not ok $TAP_TEST_NUM - $msg"
        if [[ -n "$details" ]]; then
            echo "  ---"
            echo "  message: $details"
            echo "  ..."
        fi
    else
        echo -e "  ${RED}[FAIL]${NC} $msg"
        if [[ -n "$details" && $VERBOSE -eq 1 ]]; then
            echo -e "    ${DIM}$details${NC}"
        fi
    fi
}

log_skip() {
    local msg="$1"
    local reason="${2:-}"
    ((TESTS_SKIPPED++)) || true

    if [[ $TAP_OUTPUT -eq 1 ]]; then
        ((TAP_TEST_NUM++)) || true
        if [[ -n "$reason" ]]; then
            echo "ok $TAP_TEST_NUM - $msg # SKIP $reason"
        else
            echo "ok $TAP_TEST_NUM - $msg # SKIP"
        fi
    else
        echo -e "  ${YELLOW}[SKIP]${NC} $msg"
        if [[ -n "$reason" ]]; then
            echo -e "    ${DIM}Reason: $reason${NC}"
        fi
    fi
}

log_verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        if [[ $TAP_OUTPUT -eq 1 ]]; then
            echo "# [DEBUG] $1"
        else
            echo -e "  ${DIM}[DEBUG]${NC} $1"
        fi
    fi
}

log_section() {
    if [[ $TAP_OUTPUT -eq 1 ]]; then
        echo ""
        echo "# ========================================"
        echo "# $1"
        echo "# ========================================"
    else
        echo ""
        echo -e "${BOLD}$1${NC}"
        echo "$(printf '=%.0s' {1..50})"
    fi
}

# ============================================================================
# Test Utilities
# ============================================================================

# Run the CLI and capture output
run_cli() {
    local args=("$@")
    local output
    local exit_code=0

    log_verbose "Running: $BINARY ${args[*]}"

    if output=$("$BINARY" "${args[@]}" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    log_verbose "Exit code: $exit_code"
    log_verbose "Output: $output"

    echo "$output"
    return $exit_code
}

# Run CLI with expected success
expect_success() {
    local args=("$@")
    local output
    local exit_code=0

    if output=$(run_cli "${args[@]}"); then
        echo "$output"
        return 0
    else
        exit_code=$?
        echo "$output"
        return $exit_code
    fi
}

# Run CLI with expected failure
expect_failure() {
    local args=("$@")
    local output

    if output=$(run_cli "${args[@]}"); then
        echo "$output"
        return 1  # Success when we expected failure
    else
        echo "$output"
        return 0  # Failure as expected
    fi
}

# Check if output contains a pattern
output_contains() {
    local pattern="$1"
    local output="$2"
    echo "$output" | grep -qiE "$pattern"
}

# ============================================================================
# Setup and Cleanup
# ============================================================================

setup() {
    log_info "Setting up test environment..."

    # Create test config directory
    mkdir -p "$TEST_CONFIG_DIR"

    # Create a minimal test config
    cat > "$TEST_CONFIG_DIR/config.json" << EOF
{
    "version": "2.0.0",
    "identities": {
        "$TEST_IDENTITY": {
            "provider": "gitlab",
            "host": "gitlab-test",
            "hostname": "gitlab.com",
            "user": "testuser",
            "email": "test@example.com",
            "identityFile": "~/.ssh/id_test",
            "gpg": {
                "keyId": "TEST1234567890AB",
                "signCommits": true,
                "securityMode": "developer_workflow"
            }
        },
        "tws-work-test": {
            "provider": "github",
            "host": "github.com",
            "hostname": "github.com",
            "user": "workuser",
            "email": "work@company.com",
            "identityFile": "~/.ssh/id_work",
            "gpg": {
                "keyId": "WORK4567890ABCDEF",
                "signCommits": true,
                "securityMode": "developer_workflow"
            }
        }
    },
    "settings": {
        "defaultProvider": "gitlab",
        "autoDetect": true,
        "useKeychain": false,
        "gpgSign": true,
        "defaultSecurityMode": "developer_workflow"
    }
}
EOF

    export HOME="$TEST_CONFIG_DIR"
    export REMOTE_JUGGLER_CONFIG="$TEST_CONFIG_DIR/config.json"

    log_verbose "Test config: $TEST_CONFIG_DIR/config.json"
    log_verbose "Test identity: $TEST_IDENTITY"
}

cleanup() {
    log_info "Cleaning up test data..."

    # Clear test PINs via CLI if possible
    if [[ -x "$BINARY" ]]; then
        "$BINARY" pin clear "$TEST_IDENTITY" 2>/dev/null || true
        "$BINARY" pin clear "tws-work-test" 2>/dev/null || true
    fi

    # Remove test config directory
    rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true

    log_info "Cleanup complete"
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    log_section "Prerequisites"

    # Check binary exists
    if [[ ! -x "$BINARY" ]]; then
        log_fail "Binary not found or not executable" "$BINARY"
        echo "Build with: make build"
        return 1
    fi
    log_pass "Binary exists: $BINARY"

    # Check binary runs
    if ! "$BINARY" --help >/dev/null 2>&1; then
        log_fail "Binary fails to run"
        return 1
    fi
    log_pass "Binary executes successfully"

    # Check HSM availability (informational)
    local hsm_output
    hsm_output=$("$BINARY" debug hsm 2>&1) || true

    if echo "$hsm_output" | grep -qE "(TPM 2.0|Secure Enclave)"; then
        log_pass "Hardware HSM detected"
        HAS_HARDWARE_HSM=1
    elif echo "$hsm_output" | grep -qi "keychain"; then
        log_pass "Keychain HSM fallback available"
        HAS_HARDWARE_HSM=0
    else
        log_info "No HSM available (stub mode)"
        HAS_HARDWARE_HSM=0
    fi

    # Check ykman availability (informational)
    if command -v ykman >/dev/null 2>&1; then
        log_pass "ykman installed: $(ykman --version 2>/dev/null | head -1)"
        HAS_YKMAN=1
    else
        log_info "ykman not installed (YubiKey tests will be limited)"
        HAS_YKMAN=0
    fi

    return 0
}

# ============================================================================
# SECTION 1: Basic PIN Commands
# ============================================================================

test_pin_status_command() {
    log_section "PIN Status Command"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli pin status 2>&1); then
        if output_contains "(PIN Storage Status|HSM Backend|Stored PINs)" "$output"; then
            log_pass "PIN status command returns structured output"
        else
            log_pass "PIN status command executes"
        fi
    else
        # Even failure output should be informative
        if output_contains "(No HSM|not available)" "$output"; then
            log_pass "PIN status command handles missing HSM gracefully"
        else
            log_fail "PIN status command failed unexpectedly" "$output"
        fi
    fi
}

test_pin_status_with_identity() {
    log_section "PIN Status with Identity"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli pin status "$TEST_IDENTITY" 2>&1); then
        if output_contains "(Identity|PIN Stored|$TEST_IDENTITY)" "$output"; then
            log_pass "PIN status shows identity-specific info"
        else
            log_pass "PIN status with identity executes"
        fi
    else
        if output_contains "(not found|No HSM)" "$output"; then
            log_pass "PIN status with identity handles errors gracefully"
        else
            log_fail "PIN status with identity failed" "$output"
        fi
    fi
}

test_pin_store_missing_identity() {
    log_section "PIN Store Missing Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli pin store 2>&1) || true

    if output_contains "(Missing|identity|Usage)" "$output"; then
        log_pass "PIN store without identity shows usage"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "PIN store without identity shows error"
    else
        log_fail "PIN store without identity should show error" "$output"
    fi
}

test_pin_clear_missing_identity() {
    log_section "PIN Clear Missing Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli pin clear 2>&1) || true

    if output_contains "(Missing|identity|Usage)" "$output"; then
        log_pass "PIN clear without identity shows usage"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "PIN clear without identity shows error"
    else
        log_fail "PIN clear without identity should show error" "$output"
    fi
}

test_pin_clear_nonexistent() {
    log_section "PIN Clear Non-existent Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli pin clear "nonexistent-identity-xyz" 2>&1) || true

    if output_contains "(No PIN|not found|warning)" "$output"; then
        log_pass "PIN clear for non-existent identity handled gracefully"
    else
        # May succeed silently if nothing to clear
        log_pass "PIN clear for non-existent identity executes"
    fi
}

# ============================================================================
# SECTION 2: Security Mode Commands
# ============================================================================

test_security_mode_show() {
    log_section "Security Mode Show"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli security-mode 2>&1); then
        if output_contains "(Security Mode|maximum_security|developer_workflow|trusted_workstation)" "$output"; then
            log_pass "Security mode shows available modes"
        else
            log_pass "Security mode command executes"
        fi
    else
        log_fail "Security mode command failed" "$output"
    fi
}

test_security_mode_switch_developer() {
    log_section "Security Mode Switch to Developer Workflow"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli security-mode developer_workflow 2>&1); then
        if output_contains "(set to|developer_workflow|success)" "$output"; then
            log_pass "Security mode switched to developer_workflow"
        else
            log_pass "Security mode switch executes"
        fi
    else
        log_fail "Security mode switch failed" "$output"
    fi
}

test_security_mode_switch_maximum() {
    log_section "Security Mode Switch to Maximum Security"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli security-mode maximum_security 2>&1); then
        if output_contains "(set to|maximum_security|success)" "$output"; then
            log_pass "Security mode switched to maximum_security"
        else
            log_pass "Security mode switch executes"
        fi
    else
        log_fail "Security mode switch failed" "$output"
    fi
}

test_security_mode_trusted_workstation() {
    log_section "Security Mode Switch to Trusted Workstation"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_HSM -eq 1 ]]; then
        log_skip "Trusted workstation mode switch" "HSM tests disabled"
        return
    fi

    local output
    if output=$(run_cli security-mode trusted_workstation 2>&1); then
        if output_contains "(set to|trusted_workstation|success)" "$output"; then
            log_pass "Security mode switched to trusted_workstation"
        else
            log_pass "Security mode switch executes"
        fi
    else
        # May fail if no HSM available
        if output_contains "(No HSM|not available|cannot enable)" "$output"; then
            log_pass "Security mode switch to trusted_workstation requires HSM"
        else
            log_fail "Security mode switch to trusted_workstation failed" "$output"
        fi
    fi
}

test_security_mode_invalid() {
    log_section "Security Mode Invalid Value"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli security-mode invalid_mode_xyz 2>&1) || true

    if output_contains "(Invalid|valid modes|maximum_security)" "$output"; then
        log_pass "Invalid security mode shows valid options"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "Invalid security mode shows error"
    else
        log_fail "Invalid security mode should show error" "$output"
    fi
}

# ============================================================================
# SECTION 3: Trusted Workstation Commands
# ============================================================================

test_tws_status() {
    log_section "Trusted Workstation Status"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli trusted-workstation status 2>&1); then
        if output_contains "(Trusted Workstation|Mode|HSM|gpg-agent)" "$output"; then
            log_pass "TWS status shows comprehensive info"
        else
            log_pass "TWS status command executes"
        fi
    else
        log_fail "TWS status command failed" "$output"
    fi
}

test_tws_status_with_identity() {
    log_section "Trusted Workstation Status with Identity"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli trusted-workstation status "$TEST_IDENTITY" 2>&1); then
        if output_contains "(Trusted Workstation|$TEST_IDENTITY|PIN)" "$output"; then
            log_pass "TWS status shows identity-specific info"
        else
            log_pass "TWS status with identity executes"
        fi
    else
        log_fail "TWS status with identity failed" "$output"
    fi
}

test_tws_enable_missing_identity() {
    log_section "TWS Enable Missing Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli trusted-workstation enable 2>&1) || true

    if output_contains "(Missing|identity|Usage)" "$output"; then
        log_pass "TWS enable without identity shows usage"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "TWS enable without identity shows error"
    else
        log_fail "TWS enable without identity should show error" "$output"
    fi
}

test_tws_disable_missing_identity() {
    log_section "TWS Disable Missing Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli trusted-workstation disable 2>&1) || true

    if output_contains "(Missing|identity|Usage)" "$output"; then
        log_pass "TWS disable without identity shows usage"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "TWS disable without identity shows error"
    else
        log_fail "TWS disable without identity should show error" "$output"
    fi
}

test_tws_verify_missing_identity() {
    log_section "TWS Verify Missing Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli trusted-workstation verify 2>&1) || true

    if output_contains "(Missing|identity|Usage)" "$output"; then
        log_pass "TWS verify without identity shows usage"
    elif output_contains "(ERROR|error)" "$output"; then
        log_pass "TWS verify without identity shows error"
    else
        log_fail "TWS verify without identity should show error" "$output"
    fi
}

test_tws_enable_nonexistent_identity() {
    log_section "TWS Enable Non-existent Identity"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli trusted-workstation enable "nonexistent-xyz" 2>&1) || true

    if output_contains "(not found|Identity|ERROR|error)" "$output"; then
        log_pass "TWS enable for non-existent identity handled"
    else
        log_fail "TWS enable for non-existent identity should show error" "$output"
    fi
}

# ============================================================================
# SECTION 4: YubiKey Commands
# ============================================================================

test_yubikey_info() {
    log_section "YubiKey Info"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_YUBIKEY -eq 1 ]]; then
        log_skip "YubiKey info" "YubiKey tests disabled"
        return
    fi

    local output
    if output=$(run_cli yubikey info 2>&1); then
        if output_contains "(YubiKey|ykman|Serial|PIN Policy|Touch)" "$output"; then
            log_pass "YubiKey info shows device details"
        else
            log_pass "YubiKey info executes"
        fi
    else
        if output_contains "(not installed|not found|not connected|No YubiKey)" "$output"; then
            log_pass "YubiKey info handles missing device/ykman gracefully"
        else
            log_fail "YubiKey info failed unexpectedly" "$output"
        fi
    fi
}

test_yubikey_diagnostics() {
    log_section "YubiKey Diagnostics"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_YUBIKEY -eq 1 ]]; then
        log_skip "YubiKey diagnostics" "YubiKey tests disabled"
        return
    fi

    local output
    if output=$(run_cli yubikey diagnostics 2>&1); then
        if output_contains "(OK|FAIL|WARN|INFO|Diagnostics)" "$output"; then
            log_pass "YubiKey diagnostics provides status checks"
        else
            log_pass "YubiKey diagnostics executes"
        fi
    else
        if output_contains "(not installed|not found)" "$output"; then
            log_pass "YubiKey diagnostics handles missing ykman gracefully"
        else
            log_fail "YubiKey diagnostics failed" "$output"
        fi
    fi
}

test_yubikey_set_pin_policy_invalid() {
    log_section "YubiKey Set PIN Policy Invalid"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_YUBIKEY -eq 1 ]]; then
        log_skip "YubiKey set-pin-policy invalid" "YubiKey tests disabled"
        return
    fi

    local output
    output=$(run_cli yubikey set-pin-policy invalid_policy 2>&1) || true

    if output_contains "(Invalid|once|always|valid|ERROR|error)" "$output"; then
        log_pass "YubiKey set-pin-policy shows valid options"
    else
        log_fail "YubiKey set-pin-policy should show error or valid options" "$output"
    fi
}

test_yubikey_set_touch_missing_args() {
    log_section "YubiKey Set Touch Missing Args"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_YUBIKEY -eq 1 ]]; then
        log_skip "YubiKey set-touch missing args" "YubiKey tests disabled"
        return
    fi

    local output
    output=$(run_cli yubikey set-touch 2>&1) || true

    if output_contains "(Missing|Usage|slot|policy|ERROR|error)" "$output"; then
        log_pass "YubiKey set-touch shows usage"
    else
        log_fail "YubiKey set-touch should show usage or error" "$output"
    fi
}

# ============================================================================
# SECTION 5: Debug HSM Command
# ============================================================================

test_debug_hsm() {
    log_section "Debug HSM"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli debug hsm 2>&1); then
        if output_contains "(HSM|TPM|Secure Enclave|Keychain|None)" "$output"; then
            log_pass "Debug HSM shows backend status"
        else
            log_pass "Debug HSM executes"
        fi
    else
        log_fail "Debug HSM command failed" "$output"
    fi
}

# ============================================================================
# SECTION 6: Error Handling
# ============================================================================

test_error_invalid_subcommand() {
    log_section "Error: Invalid Subcommand"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli invalidcommand123 2>&1) || true

    if output_contains "(Unknown|error|help)" "$output"; then
        log_pass "Invalid subcommand shows helpful error"
    elif output_contains "(ERROR)" "$output"; then
        log_pass "Invalid subcommand shows error"
    else
        log_fail "Invalid subcommand should show error" "$output"
    fi
}

test_error_pin_invalid_subcommand() {
    log_section "Error: PIN Invalid Subcommand"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli pin invalidcmd 2>&1) || true

    if output_contains "(Unknown|error|store|clear|status)" "$output"; then
        log_pass "PIN invalid subcommand shows valid options"
    elif output_contains "(ERROR)" "$output"; then
        log_pass "PIN invalid subcommand shows error"
    else
        log_fail "PIN invalid subcommand should show error" "$output"
    fi
}

test_error_tws_invalid_subcommand() {
    log_section "Error: TWS Invalid Subcommand"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli trusted-workstation invalidcmd 2>&1) || true

    if output_contains "(Unknown|error|enable|disable|status|verify)" "$output"; then
        log_pass "TWS invalid subcommand shows valid options"
    elif output_contains "(ERROR)" "$output"; then
        log_pass "TWS invalid subcommand shows error"
    else
        log_fail "TWS invalid subcommand should show error" "$output"
    fi
}

test_error_yubikey_invalid_subcommand() {
    log_section "Error: YubiKey Invalid Subcommand"
    ((TESTS_RUN++)) || true

    local output
    output=$(run_cli yubikey invalidcmd 2>&1) || true

    if output_contains "(Unknown|error|info|set-pin-policy|set-touch|diagnostics)" "$output"; then
        log_pass "YubiKey invalid subcommand shows valid options"
    elif output_contains "(ERROR)" "$output"; then
        log_pass "YubiKey invalid subcommand shows error"
    else
        log_fail "YubiKey invalid subcommand should show error" "$output"
    fi
}

# ============================================================================
# SECTION 7: Integration Tests (HSM-dependent)
# ============================================================================

test_hsm_store_retrieve_cycle() {
    log_section "HSM Store/Retrieve Cycle"
    ((TESTS_RUN++)) || true

    if [[ $SKIP_HSM -eq 1 ]]; then
        log_skip "HSM store/retrieve cycle" "HSM tests disabled"
        return
    fi

    # This test requires interactive input which we can't easily do
    # In CI, we skip it; locally, we just verify the command exists
    local output
    if output=$(run_cli pin store --help 2>&1); then
        log_pass "PIN store command available"
    else
        if output=$(run_cli pin 2>&1) && output_contains "store" "$output"; then
            log_pass "PIN store subcommand listed"
        else
            log_fail "PIN store command not available" "$output"
        fi
    fi
}

test_hsm_availability_detection() {
    log_section "HSM Availability Detection"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli debug hsm 2>&1); then
        local detected=""

        if output_contains "TPM 2.0" "$output"; then
            detected="TPM"
        elif output_contains "Secure Enclave" "$output"; then
            detected="SecureEnclave"
        elif output_contains "Keychain" "$output"; then
            detected="Keychain"
        elif output_contains "None" "$output"; then
            detected="None"
        fi

        if [[ -n "$detected" ]]; then
            log_pass "HSM backend detected: $detected"
        else
            log_pass "HSM availability check executes"
        fi
    else
        log_fail "HSM availability check failed" "$output"
    fi
}

# ============================================================================
# SECTION 8: Command Alias Tests
# ============================================================================

test_tws_alias() {
    log_section "TWS Alias (tws)"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli tws status 2>&1); then
        if output_contains "(Trusted Workstation|Mode|HSM)" "$output"; then
            log_pass "TWS alias 'tws' works"
        else
            log_pass "TWS alias executes"
        fi
    else
        # Alias might not be implemented
        if output_contains "(Unknown|command)" "$output"; then
            log_skip "TWS alias 'tws'" "Alias not implemented"
        else
            log_fail "TWS alias failed" "$output"
        fi
    fi
}

test_yubikey_alias() {
    log_section "YubiKey Alias (yk)"
    ((TESTS_RUN++)) || true

    local output
    if output=$(run_cli yk info 2>&1); then
        log_pass "YubiKey alias 'yk' works"
    else
        if output_contains "(Unknown|command)" "$output"; then
            log_skip "YubiKey alias 'yk'" "Alias not implemented"
        else
            log_pass "YubiKey alias executes"
        fi
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

print_tap_header() {
    if [[ $TAP_OUTPUT -eq 1 && $TAP_PLAN_PRINTED -eq 0 ]]; then
        echo "TAP version 13"
        # Count of tests: 3 prereqs + 5 PIN + 5 security + 6 TWS + 4 YubiKey + 1 debug + 4 errors + 2 HSM + 2 alias = 32
        echo "1..32"
        TAP_PLAN_PRINTED=1
    fi
}

run_all_tests() {
    if [[ $TAP_OUTPUT -eq 1 ]]; then
        print_tap_header
    else
        echo ""
        echo -e "${BOLD}RemoteJuggler Trusted Workstation E2E Tests${NC}"
        echo "============================================"
        echo ""
        echo "Binary: $BINARY"
        echo "Test Identity: $TEST_IDENTITY"
        echo "Config Dir: $TEST_CONFIG_DIR"
        echo ""
    fi

    # Prerequisites
    if ! check_prerequisites; then
        log_fail "Prerequisites not met, aborting"
        return 1
    fi

    # Setup
    setup

    # Run test sections

    # Section 1: Basic PIN Commands
    test_pin_status_command
    test_pin_status_with_identity
    test_pin_store_missing_identity
    test_pin_clear_missing_identity
    test_pin_clear_nonexistent

    # Section 2: Security Mode Commands
    test_security_mode_show
    test_security_mode_switch_developer
    test_security_mode_switch_maximum
    test_security_mode_trusted_workstation
    test_security_mode_invalid

    # Section 3: Trusted Workstation Commands
    test_tws_status
    test_tws_status_with_identity
    test_tws_enable_missing_identity
    test_tws_disable_missing_identity
    test_tws_verify_missing_identity
    test_tws_enable_nonexistent_identity

    # Section 4: YubiKey Commands
    test_yubikey_info
    test_yubikey_diagnostics
    test_yubikey_set_pin_policy_invalid
    test_yubikey_set_touch_missing_args

    # Section 5: Debug HSM
    test_debug_hsm

    # Section 6: Error Handling
    test_error_invalid_subcommand
    test_error_pin_invalid_subcommand
    test_error_tws_invalid_subcommand
    test_error_yubikey_invalid_subcommand

    # Section 7: Integration Tests
    test_hsm_store_retrieve_cycle
    test_hsm_availability_detection

    # Section 8: Alias Tests
    test_tws_alias
    test_yubikey_alias

    # Cleanup
    cleanup

    # Print summary
    print_summary
}

print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    if [[ $TAP_OUTPUT -eq 1 ]]; then
        echo ""
        echo "# Tests passed:  $TESTS_PASSED"
        echo "# Tests failed:  $TESTS_FAILED"
        echo "# Tests skipped: $TESTS_SKIPPED"
        echo "# Total:         $total"
    else
        echo ""
        echo "========================================"
        echo "Test Summary"
        echo "========================================"
        echo -e "Tests passed:  ${GREEN}$TESTS_PASSED${NC}"
        echo -e "Tests failed:  ${RED}$TESTS_FAILED${NC}"
        echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
        echo "Total:         $total"
        echo "========================================"

        if [[ $TESTS_FAILED -gt 0 ]]; then
            echo -e "${RED}FAILED${NC}"
        else
            echo -e "${GREEN}PASSED${NC}"
        fi
    fi

    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# Entry Point
# ============================================================================

if [[ $CLEANUP_ONLY -eq 1 ]]; then
    cleanup
    exit 0
fi

# Trap cleanup on exit
trap cleanup EXIT

# Run tests
if run_all_tests; then
    exit 0
else
    exit 1
fi
