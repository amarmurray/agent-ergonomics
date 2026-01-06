#!/usr/bin/env bash
#
# run_cloud.sh - Submit a Codex Cloud task and optionally apply the diff
#
# Usage:
#   ./scripts/codex/run_cloud.sh --env ENV_ID [--attempts N] [--apply] [--wait] [--max-wait SECS] [--timeout SECS] [--poll SECS] "TASK PROMPT"
#
# Environment:
#   CODEX_CLOUD_ENV_ID            Default environment ID (if --env omitted)
#   CODEX_CLOUD_MAX_WAIT_SECS     Max wait time for --wait (default: 1800)
#   CODEX_CLOUD_SLEEP_MIN_SECS    Min wait interval (default: 20)
#   CODEX_CLOUD_SLEEP_MAX_SECS    Max wait interval (default: 60)
#   CODEX_CLOUD_APPLY_TIMEOUT_SECS  Per-apply attempt timeout (default: 300)
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_ID="${CODEX_CLOUD_ENV_ID:-}"
ATTEMPTS=1
APPLY=false
WAIT=false
MAX_WAIT_SECS="${CODEX_CLOUD_MAX_WAIT_SECS:-1800}"
SLEEP_MIN_SECS="${CODEX_CLOUD_SLEEP_MIN_SECS:-20}"
SLEEP_MAX_SECS="${CODEX_CLOUD_SLEEP_MAX_SECS:-60}"
APPLY_TIMEOUT_SECS="${CODEX_CLOUD_APPLY_TIMEOUT_SECS:-300}"
PROMPT=""

usage() {
    echo "Usage: $0 --env ENV_ID [--attempts N] [--apply] [--wait] [--max-wait SECS] [--timeout SECS] [--poll SECS] \"TASK PROMPT\""
    echo ""
    echo "Submit a Codex Cloud task and optionally apply the latest diff."
    echo ""
    echo "Options:"
    echo "  --env ENV_ID       Codex Cloud environment ID (required unless CODEX_CLOUD_ENV_ID set)"
    echo "  --attempts N       Number of attempts (1-4, default: 1)"
    echo "  --apply            Apply latest diff once the task is submitted"
    echo "  --wait             Poll apply until diff is ready (requires --apply)"
    echo "  --max-wait SECS    Max seconds to wait for diff (default: 1800)"
    echo "  --timeout SECS     Alias for --max-wait"
    echo "  --poll SECS        Initial polling interval for --wait"
    echo "  --help             Show this help message"
    echo ""
    echo "Environment:"
    echo "  CODEX_CLOUD_ENV_ID         Default env ID"
    echo "  CODEX_CLOUD_MAX_WAIT_SECS  Max wait time for --wait"
    echo "  CODEX_CLOUD_SLEEP_MIN_SECS Min polling interval"
    echo "  CODEX_CLOUD_SLEEP_MAX_SECS Max polling interval"
    echo "  CODEX_CLOUD_APPLY_TIMEOUT_SECS Per-apply timeout"
    echo ""
    echo "Notes:"
    echo "  codex apply exits non-zero on git apply failures; conflicts stop retries."
}

slugify() {
    local input="$1"
    local slug
    slug=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed -E 's/^-+//; s/-+$//')
    if [ -z "$slug" ]; then
        slug="task"
    fi
    printf '%s' "${slug:0:40}"
}

run_with_timeout() {
    local timeout_secs="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_secs" "$@"
    else
        perl -e 'alarm shift; exec @ARGV' "$timeout_secs" "$@"
    fi
}

extract_task_id() {
    local text="$1"
    local id=""
    local url=""

    id=$(printf '%s\n' "$text" | sed -nE 's/.*"task_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)
    if [ -z "$id" ]; then
        id=$(printf '%s\n' "$text" | sed -nE 's/.*[Tt]ask[[:space:]_-]*ID[[:space:]]*[:=][[:space:]]*([A-Za-z0-9_-]+).*/\1/p' | head -n1)
    fi
    if [ -z "$id" ]; then
        url=$(extract_task_url "$text")
        if [ -n "$url" ]; then
            id=$(printf '%s' "$url" | sed -nE 's#.*/task[/_-]?([A-Za-z0-9_-]+).*#\1#p')
            if [ -z "$id" ]; then
                id=$(printf '%s' "$url" | sed -nE 's#.*(task[_-][A-Za-z0-9_-]+).*#\1#p')
            fi
            if [ -z "$id" ]; then
                id=$(printf '%s' "$url" | sed -nE 's#.*/([0-9a-fA-F-]{36}).*#\1#p')
            fi
        fi
    fi
    if [ -z "$id" ]; then
        id=$(printf '%s\n' "$text" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n1 || true)
    fi
    if [ -z "$id" ]; then
        id=$(printf '%s\n' "$text" | grep -Eo 'task[_-][A-Za-z0-9_-]+' | head -n1 || true)
    fi
    printf '%s' "$id"
}

extract_task_url() {
    local text="$1"
    local url=""

    url=$(printf '%s\n' "$text" | grep -Eo 'https?://[^ ]*task[^ ]*' | head -n1 || true)
    printf '%s' "$url"
}

ensure_clean_git() {
    if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo -e "${RED}Error: Not inside a git repository${NC}"
        exit 1
    fi
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
        echo -e "${RED}Error: Working tree not clean${NC}"
        echo "Commit or stash changes before applying a cloud diff."
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENV_ID="$2"
            shift 2
            ;;
        --attempts)
            ATTEMPTS="$2"
            shift 2
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --wait)
            WAIT=true
            shift
            ;;
        --max-wait)
            MAX_WAIT_SECS="$2"
            shift 2
            ;;
        --timeout)
            MAX_WAIT_SECS="$2"
            shift 2
            ;;
        --poll)
            SLEEP_MIN_SECS="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [ -z "$PROMPT" ]; then
                PROMPT="$1"
            else
                PROMPT="$PROMPT $1"
            fi
            shift
            ;;
    esac
done

if [ -z "$PROMPT" ]; then
    echo -e "${RED}Error: Task prompt required${NC}"
    usage
    exit 1
fi

if [ -z "$ENV_ID" ]; then
    echo -e "${RED}Error: Env ID is required for Codex Cloud${NC}"
    echo "Provide --env ENV_ID or set CODEX_CLOUD_ENV_ID."
    echo "Run 'codex cloud' to list or select environments."
    exit 1
fi

case "$ATTEMPTS" in
    1|2|3|4) ;;
    *)
        echo -e "${RED}Error: --attempts must be between 1 and 4${NC}"
        exit 1
        ;;
esac

if [ "$WAIT" = true ] && [ "$APPLY" = false ]; then
    echo -e "${RED}Error: --wait requires --apply (apply is opt-in)${NC}"
    echo "Re-run with --apply to apply the cloud diff when ready."
    exit 1
fi

if [ "$SLEEP_MIN_SECS" -gt "$SLEEP_MAX_SECS" ]; then
    SLEEP_MIN_SECS="$SLEEP_MAX_SECS"
fi

if ! command -v codex >/dev/null 2>&1; then
    echo -e "${RED}Error: Codex CLI not found${NC}"
    echo "Install with:"
    echo "  npm install -g @openai/codex"
    echo "  # or"
    echo "  brew install codex"
    exit 1
fi

JOB_ID="cloud-$(date +%Y%m%d-%H%M%S)-$(slugify "$PROMPT")"
RUN_DIR="$REPO_ROOT/.agent/runs/$JOB_ID"
mkdir -p "$RUN_DIR"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo -e "${CYAN}=== Codex Cloud Submission ===${NC}"
echo "Job ID: $JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Env: $ENV_ID"
echo "Attempts: $ATTEMPTS"
echo "Apply: $APPLY"
echo "Wait: $WAIT"
echo ""

cat > "$RUN_DIR/meta.json" << EOF
{
  "job_id": "$JOB_ID",
  "mode": "cloud",
  "env_id": "$ENV_ID",
  "attempts": $ATTEMPTS,
  "apply": $APPLY,
  "wait": $WAIT,
  "max_wait_seconds": $MAX_WAIT_SECS,
  "prompt": "$PROMPT",
  "created_at": "$CREATED_AT"
}
EOF

SUBMIT_LOG="$RUN_DIR/cloud_exec.log"
echo -e "${GREEN}Submitting task to Codex Cloud...${NC}"

set +e
codex cloud exec --env "$ENV_ID" --attempts "$ATTEMPTS" "$PROMPT" 2>&1 | tee "$SUBMIT_LOG"
SUBMIT_EXIT=${PIPESTATUS[0]}
set -e

if [ $SUBMIT_EXIT -ne 0 ]; then
    echo -e "${RED}Submission failed (exit $SUBMIT_EXIT)${NC}"
    echo "See log: $SUBMIT_LOG"
    exit 1
fi

SUBMIT_OUTPUT="$(cat "$SUBMIT_LOG")"
TASK_URL="$(extract_task_url "$SUBMIT_OUTPUT")"
TASK_ID="$(extract_task_id "$SUBMIT_OUTPUT")"
if [ -z "$TASK_ID" ]; then
    echo -e "${RED}Error: Could not parse TASK_ID from output${NC}"
    echo ""
    echo "Captured output:"
    cat "$SUBMIT_LOG"
    echo ""
    echo "Please copy the TASK_ID manually and run:"
    echo "  codex apply <TASK_ID>"
    exit 1
fi

echo "$TASK_ID" > "$RUN_DIR/task_id.txt"
SUBMITTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$RUN_DIR/meta.json" << EOF
{
  "job_id": "$JOB_ID",
  "mode": "cloud",
  "env_id": "$ENV_ID",
  "attempts": $ATTEMPTS,
  "apply": $APPLY,
  "wait": $WAIT,
  "max_wait_seconds": $MAX_WAIT_SECS,
  "prompt": "$PROMPT",
  "created_at": "$CREATED_AT",
  "submitted_at": "$SUBMITTED_AT",
  "task_id": "$TASK_ID",
  "task_url": "$TASK_URL"
}
EOF

echo -e "${GREEN}Task submitted: ${TASK_ID}${NC}"
if [ -n "$TASK_URL" ]; then
    echo "Task URL: $TASK_URL"
fi
echo ""

if [ "$APPLY" = true ]; then
    ensure_clean_git

    echo -e "${CYAN}=== Applying Cloud Diff ===${NC}"
    echo "Task ID: $TASK_ID"
    echo "Apply timeout: ${APPLY_TIMEOUT_SECS}s"
    echo ""

    attempt=1
    WAIT_START=$(date +%s)
    SLEEP_SECS="$SLEEP_MIN_SECS"

    while true; do
        APPLY_LOG="$RUN_DIR/apply_attempt_${attempt}.log"
        echo -e "${GREEN}Apply attempt ${attempt}...${NC}"
        echo "Log: $APPLY_LOG"

        {
            echo "Attempt: $attempt"
            echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "Command: codex apply $TASK_ID"
            echo ""
        } > "$APPLY_LOG"

        set +e
        (cd "$REPO_ROOT" && run_with_timeout "$APPLY_TIMEOUT_SECS" codex apply "$TASK_ID") >> "$APPLY_LOG" 2>&1
        APPLY_EXIT=$?
        set -e

        if [ $APPLY_EXIT -eq 0 ]; then
            echo -e "${GREEN}codex apply succeeded${NC}"
            cat > "$RUN_DIR/meta.json" << EOF
{
  "job_id": "$JOB_ID",
  "mode": "cloud",
  "env_id": "$ENV_ID",
  "attempts": $ATTEMPTS,
  "apply": $APPLY,
  "wait": $WAIT,
  "max_wait_seconds": $MAX_WAIT_SECS,
  "prompt": "$PROMPT",
  "created_at": "$CREATED_AT",
  "submitted_at": "$SUBMITTED_AT",
  "task_id": "$TASK_ID",
  "task_url": "$TASK_URL",
  "applied_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "apply_status": "success",
  "apply_attempts": $attempt
}
EOF
            break
        fi

        if grep -qiE 'still running|not ready|pending|in progress|no diff turn found' "$APPLY_LOG"; then
            if [ "$WAIT" = false ]; then
                echo -e "${RED}Diff not ready yet${NC}"
                echo "Re-run with --wait to poll until the diff is ready."
                exit 1
            fi

            NOW=$(date +%s)
            ELAPSED=$((NOW - WAIT_START))
            if [ $ELAPSED -ge "$MAX_WAIT_SECS" ]; then
                echo -e "${RED}Max wait exceeded (${MAX_WAIT_SECS}s)${NC}"
                echo "Last apply log: $APPLY_LOG"
                exit 1
            fi

            if [ $((ELAPSED + SLEEP_SECS)) -gt "$MAX_WAIT_SECS" ]; then
                SLEEP_SECS=$((MAX_WAIT_SECS - ELAPSED))
            fi
            if [ $SLEEP_SECS -le 0 ]; then
                echo -e "${RED}Max wait exceeded (${MAX_WAIT_SECS}s)${NC}"
                echo "Last apply log: $APPLY_LOG"
                exit 1
            fi

            echo -e "${YELLOW}Diff not ready yet; retrying in ${SLEEP_SECS}s (elapsed ${ELAPSED}s)${NC}"
            sleep "$SLEEP_SECS"
            attempt=$((attempt + 1))
            if [ "$SLEEP_SECS" -lt "$SLEEP_MAX_SECS" ]; then
                SLEEP_SECS=$((SLEEP_SECS * 2))
                if [ "$SLEEP_SECS" -gt "$SLEEP_MAX_SECS" ]; then
                    SLEEP_SECS="$SLEEP_MAX_SECS"
                fi
            fi
            continue
        fi

        if grep -qiE 'conflict|merge conflict|patch failed|apply failed|cannot apply' "$APPLY_LOG"; then
            echo -e "${RED}Apply failed due to conflicts${NC}"
            echo "Resolve conflicts manually, then retry codex apply."
            exit 1
        fi

        echo -e "${RED}codex apply failed (exit $APPLY_EXIT)${NC}"
        echo "See log: $APPLY_LOG"
        exit 1
    done
fi

echo ""
echo -e "${CYAN}=== Cloud Run Complete ===${NC}"
echo "Run directory: $RUN_DIR"
echo "Task ID: $TASK_ID"
