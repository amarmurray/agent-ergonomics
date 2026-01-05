#!/usr/bin/env bash
#
# apply.sh - Apply agent-ergonomics kit to a target repository
#
# Usage:
#   ./scripts/apply.sh /path/to/target/repo
#   ./scripts/apply.sh /path/to/target/repo --force
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
TEMPLATES_DIR="$KIT_ROOT/templates"

# Parse arguments
FORCE=false
TARGET_DIR=""

for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <target-directory> [--force]"
            echo ""
            echo "Apply agent-ergonomics kit to a target repository."
            echo ""
            echo "Options:"
            echo "  --force    Overwrite existing files"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            if [ -z "$TARGET_DIR" ]; then
                TARGET_DIR="$arg"
            fi
            ;;
    esac
done

if [ -z "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Target directory required${NC}"
    echo "Usage: $0 <target-directory> [--force]"
    exit 1
fi

# Convert to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
    echo -e "${RED}Error: Target directory does not exist: $TARGET_DIR${NC}"
    exit 1
}

echo "Applying agent-ergonomics kit to: $TARGET_DIR"
echo ""

# Track what we do
CREATED=()
SKIPPED=()
UPDATED=()

# Function to safely copy a file
safe_copy() {
    local src="$1"
    local dst="$2"
    local rel_dst="${dst#$TARGET_DIR/}"

    if [ -f "$dst" ]; then
        if [ "$FORCE" = true ]; then
            cp "$src" "$dst"
            UPDATED+=("$rel_dst")
            echo -e "${YELLOW}Updated:${NC} $rel_dst"
        else
            SKIPPED+=("$rel_dst")
            echo -e "${YELLOW}Skipped:${NC} $rel_dst (exists, use --force to overwrite)"
        fi
    else
        # Ensure parent directory exists
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        CREATED+=("$rel_dst")
        echo -e "${GREEN}Created:${NC} $rel_dst"
    fi
}

# Function to copy directory recursively
safe_copy_dir() {
    local src_dir="$1"
    local dst_dir="$2"

    find "$src_dir" -type f | while read -r src_file; do
        local rel_path="${src_file#$src_dir/}"
        local dst_file="$dst_dir/$rel_path"
        safe_copy "$src_file" "$dst_file"
    done
}

echo "=== Installing core files ==="
echo ""

# Install AGENTS.md
safe_copy "$TEMPLATES_DIR/AGENTS.md" "$TARGET_DIR/AGENTS.md"

# Install CLAUDE.md shim
safe_copy "$TEMPLATES_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"

echo ""
echo "=== Installing .agent/ directory ==="
echo ""

# Install .agent/ directory
safe_copy_dir "$TEMPLATES_DIR/.agent" "$TARGET_DIR/.agent"

echo ""
echo "=== Installing scripts ==="
echo ""

# Create scripts directories in target
mkdir -p "$TARGET_DIR/scripts/agent"
mkdir -p "$TARGET_DIR/scripts/codex"
mkdir -p "$TARGET_DIR/scripts/mcp"
mkdir -p "$TARGET_DIR/scripts/docs"

# Copy agent scripts
for script in bootstrap.sh verify.sh; do
    if [ -f "$KIT_ROOT/scripts/agent/$script" ]; then
        safe_copy "$KIT_ROOT/scripts/agent/$script" "$TARGET_DIR/scripts/agent/$script"
        chmod +x "$TARGET_DIR/scripts/agent/$script" 2>/dev/null || true
    fi
done

# Copy codex scripts
for script in run.sh run_cli.sh run_mcp.sh status.sh cancel.sh watchdog.sh enqueue.sh worker.sh worker_status.sh diagnose.sh; do
    if [ -f "$KIT_ROOT/scripts/codex/$script" ]; then
        safe_copy "$KIT_ROOT/scripts/codex/$script" "$TARGET_DIR/scripts/codex/$script"
        chmod +x "$TARGET_DIR/scripts/codex/$script" 2>/dev/null || true
    fi
done

# Copy mcp scripts
for script in install.sh; do
    if [ -f "$KIT_ROOT/scripts/mcp/$script" ]; then
        safe_copy "$KIT_ROOT/scripts/mcp/$script" "$TARGET_DIR/scripts/mcp/$script"
        chmod +x "$TARGET_DIR/scripts/mcp/$script" 2>/dev/null || true
    fi
done

# Copy docs scripts
for script in list.sh; do
    if [ -f "$KIT_ROOT/scripts/docs/$script" ]; then
        safe_copy "$KIT_ROOT/scripts/docs/$script" "$TARGET_DIR/scripts/docs/$script"
        chmod +x "$TARGET_DIR/scripts/docs/$script" 2>/dev/null || true
    fi
done

echo ""
echo "=== Installing docs ==="
echo ""

# Create docs directory in target if it doesn't exist
mkdir -p "$TARGET_DIR/docs"

# Copy documentation
for doc in agent_setup.md codex_cli.md codex_config_recommended.md codex_postmortem.md; do
    if [ -f "$KIT_ROOT/docs/$doc" ]; then
        safe_copy "$KIT_ROOT/docs/$doc" "$TARGET_DIR/docs/$doc"
    fi
done

# Create queue directory
mkdir -p "$TARGET_DIR/.agent/queue"
touch "$TARGET_DIR/.agent/queue/.gitkeep"

# Create runs directory
mkdir -p "$TARGET_DIR/.agent/runs"
touch "$TARGET_DIR/.agent/runs/.gitkeep"

echo ""
echo "=== Summary ==="
echo ""
echo -e "${GREEN}Created:${NC} ${#CREATED[@]} files"
echo -e "${YELLOW}Updated:${NC} ${#UPDATED[@]} files"
echo -e "${YELLOW}Skipped:${NC} ${#SKIPPED[@]} files (use --force to overwrite)"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Review and customize AGENTS.md with your repo's actual commands"
echo "2. Run: ./scripts/agent/bootstrap.sh"
echo "3. Run: ./scripts/mcp/install.sh (optional, for MCP users)"
echo "4. Run: ./scripts/codex/diagnose.sh (to verify Codex setup)"
echo ""
echo -e "${GREEN}Done!${NC}"
