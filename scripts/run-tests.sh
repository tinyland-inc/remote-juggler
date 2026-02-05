#!/usr/bin/env bash
# RemoteJuggler Test Runner
# Runs all unit tests and outputs results in JUnit XML format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_ROOT/test/unit"
BUILD_DIR="$PROJECT_ROOT/target/test"
HSM_DIR="$PROJECT_ROOT/pinentry"

# HSM compilation flags - include path for hsm.h
HSM_CCFLAGS="--ccflags=-I$HSM_DIR"

# Check if native HSM library is available
HSM_LIB="$HSM_DIR/libhsm_remotejuggler.so"
if [ -f "$HSM_LIB" ]; then
    HSM_NATIVE_FLAG="-sHSM_NATIVE_AVAILABLE=true"
    HSM_LDFLAGS="--ldflags=-L$HSM_DIR --ldflags=-lhsm_remotejuggler --ldflags=-Wl,-rpath,$HSM_DIR"
else
    HSM_NATIVE_FLAG="-sHSM_NATIVE_AVAILABLE=false"
    HSM_LDFLAGS=""
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
TOTAL_PASSED=0
TOTAL_FAILED=0
TEST_RESULTS=()

echo "=== RemoteJuggler Test Suite ==="
echo ""

# Ensure build directory exists
mkdir -p "$BUILD_DIR"

# Find all test files
TEST_FILES=$(find "$TEST_DIR" -name "*Tests.chpl" 2>/dev/null || true)

if [ -z "$TEST_FILES" ]; then
    echo -e "${YELLOW}No test files found in $TEST_DIR${NC}"
    exit 0
fi

# Compile and run each test
for test_file in $TEST_FILES; do
    test_name=$(basename "$test_file" .chpl)
    echo -e "${YELLOW}Running $test_name...${NC}"

    # Compile test
    # Include both src and src/remote_juggler directories for module resolution
    # Platform-specific linker flags for macOS
    # HSM flags for native library support
    COMPILE_FAILED=false
    if [ "$(uname -s)" = "Darwin" ]; then
        if ! chpl -o "$BUILD_DIR/$test_name" \
             "$test_file" \
             -M "$PROJECT_ROOT/src" \
             -M "$PROJECT_ROOT/src/remote_juggler" \
             --main-module "$test_name" \
             $HSM_NATIVE_FLAG \
             $HSM_CCFLAGS \
             $HSM_LDFLAGS \
             --ldflags="-framework Security -framework CoreFoundation" \
             2>&1; then
            COMPILE_FAILED=true
        fi
    else
        if ! chpl -o "$BUILD_DIR/$test_name" \
             "$test_file" \
             -M "$PROJECT_ROOT/src" \
             -M "$PROJECT_ROOT/src/remote_juggler" \
             --main-module "$test_name" \
             $HSM_NATIVE_FLAG \
             $HSM_CCFLAGS \
             $HSM_LDFLAGS \
             2>&1; then
            COMPILE_FAILED=true
        fi
    fi

    if [ "$COMPILE_FAILED" = true ]; then
        echo -e "${RED}COMPILE FAILED: $test_name${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        TEST_RESULTS+=("$test_name:compile_failed")
        continue
    fi

    # Run test
    if "$BUILD_DIR/$test_name" 2>&1; then
        echo -e "${GREEN}PASSED: $test_name${NC}"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
        TEST_RESULTS+=("$test_name:passed")
    else
        echo -e "${RED}FAILED: $test_name${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        TEST_RESULTS+=("$test_name:failed")
    fi
    echo ""
done

# Generate JUnit XML report
JUNIT_FILE="$PROJECT_ROOT/test-results.xml"
cat > "$JUNIT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="RemoteJuggler" tests="$((TOTAL_PASSED + TOTAL_FAILED))" failures="$TOTAL_FAILED">
  <testsuite name="unit" tests="$((TOTAL_PASSED + TOTAL_FAILED))" failures="$TOTAL_FAILED">
EOF

for result in "${TEST_RESULTS[@]}"; do
    name="${result%:*}"
    status="${result#*:}"

    if [ "$status" = "passed" ]; then
        echo "    <testcase name=\"$name\" classname=\"unit.$name\"/>" >> "$JUNIT_FILE"
    elif [ "$status" = "compile_failed" ]; then
        cat >> "$JUNIT_FILE" << EOF
    <testcase name="$name" classname="unit.$name">
      <failure message="Compilation failed">Test failed to compile</failure>
    </testcase>
EOF
    else
        cat >> "$JUNIT_FILE" << EOF
    <testcase name="$name" classname="unit.$name">
      <failure message="Test assertions failed">One or more test assertions failed</failure>
    </testcase>
EOF
    fi
done

cat >> "$JUNIT_FILE" << EOF
  </testsuite>
</testsuites>
EOF

# Summary
echo "=== Test Summary ==="
echo -e "${GREEN}Passed: $TOTAL_PASSED${NC}"
echo -e "${RED}Failed: $TOTAL_FAILED${NC}"
echo ""
echo "JUnit report: $JUNIT_FILE"

# Exit with appropriate code
if [ "$TOTAL_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
