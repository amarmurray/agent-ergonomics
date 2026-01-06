#!/usr/bin/env bash
#
# verify.sh - Verify target repo conforms to agent-ergonomics standards
#
# Usage:
#   ./scripts/verify.sh /path/to/target/repo
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
TARGET_DIR="${1:-$(pwd)}"

# Convert to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo -e "${RED}Error: Target directory does not exist: $TARGET_DIR${NC}"
    exit 1
}

echo "Verifying agent-ergonomics compliance in: $TARGET_DIR"
echo ""

ERRORS=0
WARNINGS=0

check_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

check_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((ERRORS++))
}

check_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

check_file() {
    local path="$1"
    local label="$2"

    if [ -f "$path" ]; then
        check_pass "$label exists"
    else
        check_fail "$label not found"
    fi
}

check_dir() {
    local path="$1"
    local label="$2"

    if [ -d "$path" ]; then
        check_pass "$label exists"
    else
        check_fail "$label not found"
    fi
}

check_script() {
    local path="$1"
    local label="$2"

    if [ -f "$path" ]; then
        if [ -x "$path" ]; then
            check_pass "$label exists and is executable"
        else
            check_warn "$label exists but is not executable"
        fi
    else
        check_fail "$label not found"
    fi
}

print_summary() {
    echo ""
    echo "=== Summary ==="
    echo ""

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}All checks passed!${NC}"
        exit 0
    elif [ $ERRORS -eq 0 ]; then
        echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
        exit 0
    else
        echo -e "${RED}Failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
        echo ""
        if [ "${MODE:-target}" = "kit" ]; then
            echo "To fix:"
            echo "  - Ensure kit templates, scripts, and CI workflow are present"
        else
            echo "To fix:"
            echo "  1. Run: ./scripts/apply.sh $TARGET_DIR --force"
            echo "  2. Or manually create missing files"
        fi
        exit 1
    fi
}

is_kit_repo() {
    if [ -d "$TARGET_DIR/templates/.agent" ] && [ -f "$TARGET_DIR/templates/CLAUDE.md" ] && [ ! -f "$TARGET_DIR/CLAUDE.md" ]; then
        return 0
    fi
    return 1
}

verify_kit() {
    echo "=== Kit Templates ==="
    echo ""

    check_file "$TARGET_DIR/templates/CLAUDE.md" "templates/CLAUDE.md"
    check_file "$TARGET_DIR/templates/AGENTS.md" "templates/AGENTS.md"
    check_dir "$TARGET_DIR/templates/.agent" "templates/.agent"

    KIT_AGENT_FILES=(
        "templates/.agent/skills.md"
        "templates/.agent/sandbox.md"
        "templates/.agent/auth.md"
        "templates/.agent/mcp.md"
        "templates/.agent/codex.md"
        "templates/.agent/inference_speed.md"
    )

    for file in "${KIT_AGENT_FILES[@]}"; do
        check_file "$TARGET_DIR/$file" "$file"
    done

    echo ""
    echo "=== Kit Scripts ==="
    echo ""

    KIT_SCRIPTS=(
        "scripts/codex/run.sh"
        "scripts/codex/run_cloud.sh"
        "scripts/codex/diagnose.sh"
    )

    for script in "${KIT_SCRIPTS[@]}"; do
        check_script "$TARGET_DIR/$script" "$script"
    done

    echo ""
    echo "=== Kit CI ==="
    echo ""

    check_file "$TARGET_DIR/.github/workflows/kit-ci.yml" ".github/workflows/kit-ci.yml"
}

# Expected CLAUDE.md shim content (exact match required)
EXPECTED_SHIM='# Claude Code entrypoint
@AGENTS.md
@.agent/skills.md
@.agent/sandbox.md
@.agent/auth.md
@.agent/mcp.md
@.agent/codex.md
@.agent/inference_speed.md'

MODE="target"
if is_kit_repo; then
    MODE="kit"
    verify_kit
    print_summary
fi

echo "=== Core Files ==="
echo ""

# Check CLAUDE.md exists and matches shim exactly
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    ACTUAL_SHIM=$(cat "$TARGET_DIR/CLAUDE.md")
    if [ "$ACTUAL_SHIM" = "$EXPECTED_SHIM" ]; then
        check_pass "CLAUDE.md exists and matches shim template"
    else
        check_fail "CLAUDE.md exists but does not match shim template"
        echo "    Expected content:"
        echo "$EXPECTED_SHIM" | sed 's/^/      /'
        echo "    Actual content:"
        echo "$ACTUAL_SHIM" | sed 's/^/      /'
    fi
else
    check_fail "CLAUDE.md not found"
fi

# Check AGENTS.md exists
if [ -f "$TARGET_DIR/AGENTS.md" ]; then
    check_pass "AGENTS.md exists"
else
    check_fail "AGENTS.md not found"
fi

echo ""
echo "=== .agent/ Directory ==="
echo ""

# Check .agent/ directory and files
AGENT_FILES=(
    ".agent/skills.md"
    ".agent/sandbox.md"
    ".agent/auth.md"
    ".agent/mcp.md"
    ".agent/codex.md"
    ".agent/inference_speed.md"
)

for file in "${AGENT_FILES[@]}"; do
    if [ -f "$TARGET_DIR/$file" ]; then
        check_pass "$file exists"
    else
        check_fail "$file not found"
    fi
done

# Check MCP server definitions directory
if [ -d "$TARGET_DIR/.agent/mcp/servers" ]; then
    count=$(find "$TARGET_DIR/.agent/mcp/servers" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        check_pass ".agent/mcp/servers/ has $count server definition(s)"
    else
        check_warn ".agent/mcp/servers/ exists but has no .md files"
    fi
else
    check_warn ".agent/mcp/servers/ directory not found"
fi

echo ""
echo "=== Scripts ==="
echo ""

# Check essential scripts
ESSENTIAL_SCRIPTS=(
    "scripts/agent/bootstrap.sh"
    "scripts/agent/verify.sh"
    "scripts/codex/run.sh"
    "scripts/codex/diagnose.sh"
    "scripts/mcp/install.sh"
)

for script in "${ESSENTIAL_SCRIPTS[@]}"; do
    if [ -f "$TARGET_DIR/$script" ]; then
        if [ -x "$TARGET_DIR/$script" ]; then
            check_pass "$script exists and is executable"
        else
            check_warn "$script exists but is not executable"
        fi
    else
        check_warn "$script not found"
    fi
done

echo ""
echo "=== Documentation ==="
echo ""

# Check docs directory
if [ -d "$TARGET_DIR/docs" ]; then
    check_pass "docs/ directory exists"
else
    check_warn "docs/ directory not found"
fi

echo ""
print_summary
