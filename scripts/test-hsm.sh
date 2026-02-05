#!/usr/bin/env bash
#
# test-hsm.sh - HSM test runner for RemoteJuggler
#
# Builds the HSM library and runs all HSM-related tests:
# - C unit tests (test_hsm.c)
# - Integration tests (test_hsm_integration.sh)
#
# Usage:
#   ./scripts/test-hsm.sh [options]
#
# Options:
#   --unit-only       Run only C unit tests
#   --integration-only Run only integration tests
#   --skip-build      Skip building the HSM library
#   --coverage        Generate coverage report (requires gcov)
#   --verbose         Enable verbose output
#   --help            Show this help
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PINENTRY_DIR="$PROJECT_ROOT/pinentry"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Options
RUN_UNIT=1
RUN_INTEGRATION=1
SKIP_BUILD=0
COVERAGE=0
VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit-only)
            RUN_UNIT=1
            RUN_INTEGRATION=0
            shift
            ;;
        --integration-only)
            RUN_UNIT=0
            RUN_INTEGRATION=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --coverage)
            COVERAGE=1
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --unit-only        Run only C unit tests"
            echo "  --integration-only Run only integration tests"
            echo "  --skip-build       Skip building the HSM library"
            echo "  --coverage         Generate coverage report"
            echo "  --verbose          Enable verbose output"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

log_header() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Track overall test results
UNIT_PASSED=0
UNIT_FAILED=0
INTEGRATION_PASSED=0
INTEGRATION_FAILED=0

# Build HSM library
build_hsm_library() {
    log_header "Building HSM Library"

    cd "$PINENTRY_DIR"

    if [[ $COVERAGE -eq 1 ]]; then
        log_info "Building with coverage instrumentation..."
        # Build with coverage flags
        CFLAGS="-fprofile-arcs -ftest-coverage -g -O0" make clean all 2>&1
    else
        log_info "Building HSM library..."
        if [[ $VERBOSE -eq 1 ]]; then
            make clean all 2>&1
        else
            make clean all >/dev/null 2>&1
        fi
    fi

    if [[ -f "libhsm_remotejuggler.so" ]] || [[ -f "libhsm_remotejuggler.dylib" ]]; then
        log_success "HSM library built successfully"
    else
        log_error "Failed to build HSM library"
        exit 1
    fi

    cd "$PROJECT_ROOT"
}

# Run C unit tests
run_unit_tests() {
    log_header "Running C Unit Tests"

    cd "$PINENTRY_DIR"

    log_info "Building test binary..."
    if [[ $COVERAGE -eq 1 ]]; then
        CFLAGS="-fprofile-arcs -ftest-coverage -g -O0" make test_hsm 2>&1
    else
        if [[ $VERBOSE -eq 1 ]]; then
            make test_hsm 2>&1
        else
            make test_hsm >/dev/null 2>&1
        fi
    fi

    if [[ ! -f "test_hsm" ]]; then
        log_error "Failed to build test binary"
        UNIT_FAILED=1
        return 1
    fi

    log_info "Running unit tests..."
    echo ""

    # Run tests and capture output
    local test_output
    local test_exit_code=0

    if [[ "$(uname)" == "Darwin" ]]; then
        test_output=$(DYLD_LIBRARY_PATH=. ./test_hsm 2>&1) || test_exit_code=$?
    else
        test_output=$(LD_LIBRARY_PATH=. ./test_hsm 2>&1) || test_exit_code=$?
    fi

    echo "$test_output"
    echo ""

    # Parse test results (strip ANSI color codes if any)
    local passed
    local failed
    passed=$(echo "$test_output" | sed 's/\x1b\[[0-9;]*m//g' | grep "Tests passed:" | awk '{print $3}' || echo "0")
    failed=$(echo "$test_output" | sed 's/\x1b\[[0-9;]*m//g' | grep "Tests failed:" | awk '{print $3}' || echo "0")

    UNIT_PASSED=${passed:-0}
    UNIT_FAILED=${failed:-0}

    if [[ $test_exit_code -eq 0 ]] && [[ "$failed" == "0" ]]; then
        log_success "Unit tests passed: $passed"
    else
        log_error "Unit tests failed: $failed"
    fi

    cd "$PROJECT_ROOT"
    return $test_exit_code
}

# Run integration tests
run_integration_tests() {
    log_header "Running Integration Tests"

    local integration_script="$PINENTRY_DIR/test_hsm_integration.sh"

    if [[ ! -f "$integration_script" ]]; then
        log_error "Integration test script not found: $integration_script"
        return 1
    fi

    if [[ ! -x "$integration_script" ]]; then
        chmod +x "$integration_script"
    fi

    log_info "Running integration tests..."
    echo ""

    local integration_args=""
    if [[ $VERBOSE -eq 1 ]]; then
        integration_args="--verbose"
    fi

    local integration_output
    local integration_exit_code=0

    integration_output=$("$integration_script" $integration_args 2>&1) || integration_exit_code=$?

    echo "$integration_output"
    echo ""

    # Parse integration test results (strip ANSI color codes)
    local passed
    local failed
    passed=$(echo "$integration_output" | sed 's/\x1b\[[0-9;]*m//g' | grep "Tests passed:" | awk '{print $3}' | head -1 || echo "0")
    failed=$(echo "$integration_output" | sed 's/\x1b\[[0-9;]*m//g' | grep "Tests failed:" | awk '{print $3}' | head -1 || echo "0")

    INTEGRATION_PASSED=${passed:-0}
    INTEGRATION_FAILED=${failed:-0}

    if [[ $integration_exit_code -eq 0 ]]; then
        log_success "Integration tests passed"
    else
        log_error "Some integration tests failed"
    fi

    return $integration_exit_code
}

# Generate coverage report
generate_coverage_report() {
    if [[ $COVERAGE -eq 0 ]]; then
        return
    fi

    log_header "Generating Coverage Report"

    cd "$PINENTRY_DIR"

    if ! command -v gcov >/dev/null 2>&1; then
        log_warn "gcov not found, skipping coverage report"
        return
    fi

    log_info "Running gcov..."

    # Find and process .gcda files
    local gcda_files
    gcda_files=$(find . -name "*.gcda" 2>/dev/null | head -10)

    if [[ -z "$gcda_files" ]]; then
        log_warn "No coverage data found"
        cd "$PROJECT_ROOT"
        return
    fi

    # Generate coverage for each source file
    for gcda in $gcda_files; do
        local source_file="${gcda%.gcda}.c"
        if [[ -f "$source_file" ]]; then
            gcov "$source_file" >/dev/null 2>&1 || true
        fi
    done

    # Display coverage summary
    echo ""
    echo -e "${BOLD}Coverage Summary:${NC}"
    echo "----------------"

    for gcov_file in *.gcov; do
        if [[ -f "$gcov_file" ]]; then
            local source_name="${gcov_file%.gcov}"
            local total_lines
            local covered_lines
            total_lines=$(grep -c ":" "$gcov_file" 2>/dev/null || echo "0")
            covered_lines=$(grep -c "^[[:space:]]*[0-9]:" "$gcov_file" 2>/dev/null || echo "0")

            if [[ $total_lines -gt 0 ]]; then
                local percentage=$((covered_lines * 100 / total_lines))
                printf "  %-30s %3d%% (%d/%d lines)\n" "$source_name" "$percentage" "$covered_lines" "$total_lines"
            fi
        fi
    done

    echo ""

    # Cleanup coverage files
    rm -f *.gcov *.gcda *.gcno 2>/dev/null || true

    cd "$PROJECT_ROOT"
}

# Print final summary
print_summary() {
    log_header "Test Summary"

    local total_passed=$((UNIT_PASSED + INTEGRATION_PASSED))
    local total_failed=$((UNIT_FAILED + INTEGRATION_FAILED))

    echo ""
    printf "  %-20s %s\n" "Test Category" "Passed / Failed"
    printf "  %-20s %s\n" "--------------------" "----------------"

    if [[ $RUN_UNIT -eq 1 ]]; then
        printf "  %-20s ${GREEN}%d${NC} / ${RED}%d${NC}\n" "Unit Tests" "$UNIT_PASSED" "$UNIT_FAILED"
    fi

    if [[ $RUN_INTEGRATION -eq 1 ]]; then
        printf "  %-20s ${GREEN}%d${NC} / ${RED}%d${NC}\n" "Integration Tests" "$INTEGRATION_PASSED" "$INTEGRATION_FAILED"
    fi

    echo ""
    printf "  %-20s ${GREEN}%d${NC} / ${RED}%d${NC}\n" "TOTAL" "$total_passed" "$total_failed"
    echo ""

    if [[ $total_failed -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}Some tests failed.${NC}"
        return 1
    fi
}

# Cleanup function
cleanup() {
    # Remove test artifacts
    rm -f "$PINENTRY_DIR"/*.gcov 2>/dev/null || true
    rm -f "$PINENTRY_DIR"/*.gcda 2>/dev/null || true
    rm -f "$PINENTRY_DIR"/*.gcno 2>/dev/null || true
}

# Main
main() {
    log_header "RemoteJuggler HSM Test Suite"

    echo "Project root: $PROJECT_ROOT"
    echo "Pinentry dir: $PINENTRY_DIR"
    echo ""

    # Trap for cleanup
    trap cleanup EXIT

    local exit_code=0

    # Build
    if [[ $SKIP_BUILD -eq 0 ]]; then
        build_hsm_library
    else
        log_info "Skipping build (--skip-build)"
    fi

    # Run unit tests
    if [[ $RUN_UNIT -eq 1 ]]; then
        run_unit_tests || exit_code=1
    fi

    # Run integration tests
    if [[ $RUN_INTEGRATION -eq 1 ]]; then
        run_integration_tests || exit_code=1
    fi

    # Generate coverage if requested
    if [[ $COVERAGE -eq 1 ]]; then
        generate_coverage_report
    fi

    # Print summary
    print_summary || exit_code=1

    exit $exit_code
}

main
