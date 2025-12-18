#!/bin/bash
# Error handler for pipeline failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

source "$SCRIPT_DIR/state-manager.sh"

# Log error with full context
log_error() {
  local stage="$1"
  local exit_code="$2"
  local message="${3:-Unknown error}"

  mkdir -p .task/errors
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local error_file=".task/errors/error-${timestamp}.json"

  # Capture context
  local state_snapshot
  state_snapshot=$(cat .task/state.json 2>/dev/null || echo '{}')

  local task_snapshot
  task_snapshot=$(cat .task/current-task.json 2>/dev/null || echo '{}')

  cat > "$error_file" << EOF
{
  "id": "err-${timestamp}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "severity": "error",
  "stage": "$stage",
  "agent": "$(echo "$stage" | sed 's/implementing/claude/;s/reviewing/codex/;s/fixing/claude/')",
  "task_id": "$(get_task_id)",
  "error": {
    "type": "ExecutionError",
    "message": "$message",
    "exit_code": $exit_code
  },
  "context": {
    "current_state": $state_snapshot,
    "task_definition": $task_snapshot,
    "iteration": $(get_iteration)
  },
  "resolution": {
    "auto_attempts": [],
    "status": "waiting_for_user",
    "suggested_fixes": [
      "Check agent logs for details",
      "Run ./scripts/recover.sh to reset state",
      "Review .task/errors/ for error history"
    ]
  }
}
EOF

  echo "Error logged to: $error_file"
  echo "$error_file"
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  stage="${1:-unknown}"
  exit_code="${2:-1}"
  message="${3:-Unspecified error}"

  log_error "$stage" "$exit_code" "$message"
fi
