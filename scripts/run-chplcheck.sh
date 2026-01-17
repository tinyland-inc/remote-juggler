#!/usr/bin/env bash
# RemoteJuggler chplcheck Linter
# Runs chplcheck on all Chapel source files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$PROJECT_ROOT/src"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== RemoteJuggler chplcheck Linter ==="
echo ""

# Check if chplcheck is available
if ! command -v chplcheck &> /dev/null; then
    echo -e "${YELLOW}Warning: chplcheck not found in PATH${NC}"
    echo "chplcheck is included with Chapel 2.0+"
    echo "Make sure Chapel is installed and CHPL_HOME/bin is in PATH"
    exit 0
fi

# Find all Chapel files
CHPL_FILES=$(find "$SRC_DIR" -name "*.chpl" -type f)

if [ -z "$CHPL_FILES" ]; then
    echo -e "${YELLOW}No Chapel files found in $SRC_DIR${NC}"
    exit 0
fi

# Count files
FILE_COUNT=$(echo "$CHPL_FILES" | wc -l | tr -d ' ')
echo "Checking $FILE_COUNT Chapel files..."
echo ""

# Track results
ERRORS=0
WARNINGS=0

# Run chplcheck on each file
for file in $CHPL_FILES; do
    relative_path="${file#$PROJECT_ROOT/}"

    # Run chplcheck and capture output
    output=$(chplcheck "$file" 2>&1 || true)

    if [ -n "$output" ]; then
        # Count errors and warnings in output
        file_errors=$(echo "$output" | grep -c "error:" || true)
        file_warnings=$(echo "$output" | grep -c "warning:" || true)

        if [ "$file_errors" -gt 0 ]; then
            echo -e "${RED}$relative_path: $file_errors error(s)${NC}"
            echo "$output" | grep "error:" | sed 's/^/  /'
            ERRORS=$((ERRORS + file_errors))
        fi

        if [ "$file_warnings" -gt 0 ]; then
            echo -e "${YELLOW}$relative_path: $file_warnings warning(s)${NC}"
            echo "$output" | grep "warning:" | sed 's/^/  /'
            WARNINGS=$((WARNINGS + file_warnings))
        fi
    else
        echo -e "${GREEN}✓${NC} $relative_path"
    fi
done

echo ""
echo "=== Summary ==="
echo -e "Files checked: $FILE_COUNT"
echo -e "Errors: ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

# Exit with error if any errors found
if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo -e "${RED}chplcheck found errors. Please fix them before committing.${NC}"
    exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}chplcheck found warnings. Consider fixing them.${NC}"
fi

echo ""
echo -e "${GREEN}chplcheck passed!${NC}"
exit 0
