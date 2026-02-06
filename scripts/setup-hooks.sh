#!/usr/bin/env bash
# RemoteJuggler Git Hooks Setup
# ==============================
#
# This script installs git hooks for RemoteJuggler development.
# Hooks are stored in ~/.githooks/remote-juggler/ (not tracked in repo)
#
# Usage: ./scripts/setup-hooks.sh
#
# What the hooks do:
# - pre-commit: Block .claude/CLAUDE files, run auto-formatters, run linters
# - commit-msg: Block Co-Authored-By, warn on non-conventional commits
# - pre-push: Run quick tests before push

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_DIR="$HOME/.githooks/remote-juggler"

echo "Setting up RemoteJuggler git hooks..."

# Create hooks directory
mkdir -p "$HOOKS_DIR"

# =============================================================================
# Pre-commit hook
# =============================================================================
cat > "$HOOKS_DIR/pre-commit" << 'HOOK_EOF'
#!/usr/bin/env bash
# RemoteJuggler Pre-Commit Hook
# Blocks .claude/CLAUDE files, runs formatters and linters

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Running pre-commit checks...${NC}"

# Block .claude and CLAUDE files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

for file in $STAGED_FILES; do
    if [[ "$file" == *"/.claude/"* ]] || [[ "$file" == ".claude/"* ]] || \
       [[ "$(basename "$file")" == "CLAUDE.md" ]] || \
       [[ "$(basename "$file")" == "CLAUDE.local.md" ]]; then
        echo -e "${RED}BLOCKED: Cannot commit Claude config file: $file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ No blocked files${NC}"

# Auto-format staged files
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Rust
RUST_FILES=$(echo "$STAGED_FILES" | grep '\.rs$' || true)
if [[ -n "$RUST_FILES" ]] && command -v cargo &>/dev/null && [[ -f "gtk-gui/Cargo.toml" ]]; then
    (cd gtk-gui && cargo fmt 2>/dev/null) || true
    for f in $RUST_FILES; do [[ -f "$f" ]] && git add "$f"; done
fi

# Go
GO_FILES=$(echo "$STAGED_FILES" | grep '\.go$' || true)
if [[ -n "$GO_FILES" ]] && command -v gofmt &>/dev/null; then
    for f in $GO_FILES; do [[ -f "$f" ]] && gofmt -w "$f" && git add "$f"; done
fi

# Python
PY_FILES=$(echo "$STAGED_FILES" | grep '\.py$' || true)
if [[ -n "$PY_FILES" ]] && command -v ruff &>/dev/null; then
    for f in $PY_FILES; do
        [[ -f "$f" ]] && ruff format "$f" 2>/dev/null && ruff check --fix "$f" 2>/dev/null && git add "$f"
    done
fi

# Nix
NIX_FILES=$(echo "$STAGED_FILES" | grep '\.nix$' || true)
if [[ -n "$NIX_FILES" ]] && command -v nixfmt &>/dev/null; then
    for f in $NIX_FILES; do [[ -f "$f" ]] && nixfmt "$f" 2>/dev/null && git add "$f"; done
fi

echo -e "${GREEN}✓ Auto-formatted files${NC}"

# Run linters
LINT_FAILED=0

if [[ -n "$RUST_FILES" ]] && command -v cargo &>/dev/null && [[ -f "gtk-gui/Cargo.toml" ]]; then
    if ! (cd gtk-gui && cargo clippy --quiet -- -D warnings 2>/dev/null); then
        LINT_FAILED=1
    fi
fi

if [[ -n "$GO_FILES" ]] && command -v go &>/dev/null && [[ -d "tray/linux" ]]; then
    if ! (cd tray/linux && go vet ./... 2>/dev/null); then
        LINT_FAILED=1
    fi
fi

if [[ $LINT_FAILED -eq 1 ]]; then
    echo -e "${RED}Commit blocked: lint errors${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Pre-commit checks passed${NC}"
HOOK_EOF

# =============================================================================
# Commit-msg hook
# =============================================================================
cat > "$HOOKS_DIR/commit-msg" << 'HOOK_EOF'
#!/usr/bin/env bash
# RemoteJuggler Commit-Msg Hook
# Blocks Co-Authored-By, warns on non-conventional commits

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

COMMIT_MSG=$(cat "$1")

# Block Co-Authored-By
if echo "$COMMIT_MSG" | grep -qi "co-authored-by"; then
    echo -e "${RED}BLOCKED: Co-Authored-By is not allowed${NC}"
    exit 1
fi

if echo "$COMMIT_MSG" | grep -qiE "(co-author|coauthor|paired.with)"; then
    echo -e "${RED}BLOCKED: Co-authoring indicators detected${NC}"
    exit 1
fi

# Warn on non-conventional format
FIRST_LINE=$(echo "$COMMIT_MSG" | head -n1)
if ! echo "$FIRST_LINE" | grep -qE "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?: .+"; then
    echo -e "${YELLOW}⚠ Warning: Not conventional commit format${NC}"
fi

echo -e "${GREEN}✓ Commit message OK${NC}"
HOOK_EOF

# =============================================================================
# Pre-push hook
# =============================================================================
cat > "$HOOKS_DIR/pre-push" << 'HOOK_EOF'
#!/usr/bin/env bash
# RemoteJuggler Pre-Push Hook
# Runs quick tests before push

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ "$ALLOW_PUSH_WITHOUT_TESTS" == "1" ]]; then
    echo -e "${YELLOW}⚠ Bypassing pre-push tests${NC}"
    exit 0
fi

echo -e "${YELLOW}Running pre-push checks...${NC}"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

TEST_FAILED=0

# Chapel tests
if command -v just &>/dev/null && [[ -f "justfile" ]]; then
    just test 2>/dev/null || TEST_FAILED=1
fi

# Rust tests
if [[ -f "gtk-gui/Cargo.toml" ]] && command -v cargo &>/dev/null; then
    (cd gtk-gui && cargo test --quiet 2>/dev/null) || TEST_FAILED=1
fi

# Go tests
if [[ -d "tray/linux" ]] && command -v go &>/dev/null; then
    (cd tray/linux && go test -short ./... 2>/dev/null) || TEST_FAILED=1
fi

if [[ $TEST_FAILED -eq 1 ]]; then
    echo -e "${RED}Push blocked: tests failed${NC}"
    echo "Bypass: ALLOW_PUSH_WITHOUT_TESTS=1 git push"
    exit 1
fi

echo -e "${GREEN}✓ Pre-push checks passed${NC}"
HOOK_EOF

# Make hooks executable
chmod +x "$HOOKS_DIR"/*

# Configure git to use hooks
git config core.hooksPath "$HOOKS_DIR"

echo ""
echo -e "${GREEN}Git hooks installed successfully!${NC}"
echo ""
echo "Hooks location: $HOOKS_DIR"
echo "Hooks installed:"
echo "  - pre-commit: Blocks .claude/CLAUDE files, runs formatters/linters"
echo "  - commit-msg: Blocks Co-Authored-By"
echo "  - pre-push: Runs tests before push"
echo ""
echo "To bypass hooks (not recommended):"
echo "  git commit --no-verify"
echo "  ALLOW_PUSH_WITHOUT_TESTS=1 git push"
