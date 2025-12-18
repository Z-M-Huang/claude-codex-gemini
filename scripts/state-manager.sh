#!/bin/bash
# State manager using JSON files with atomic writes

STATE_FILE=".task/state.json"

# Initialize state if not exists
init_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    mkdir -p .task
    echo '{"status":"idle","current_task_id":null,"iteration":0}' > "$STATE_FILE"
  fi
}

# Get current state
get_state() {
  cat "$STATE_FILE"
}

# Get specific field
get_status() {
  jq -r '.status' "$STATE_FILE"
}

get_task_id() {
  jq -r '.current_task_id // empty' "$STATE_FILE"
}

get_iteration() {
  jq -r '.iteration' "$STATE_FILE"
}

# Update state atomically (write to tmp, then mv)
set_state() {
  local new_status="$1"
  local task_id="$2"

  jq --arg s "$new_status" --arg t "$task_id" \
    '.status = $s | .current_task_id = $t | .updated_at = (now | todate)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp"

  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Increment iteration (for review loops)
increment_iteration() {
  jq '.iteration += 1 | .updated_at = (now | todate)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Reset iteration (for new task)
reset_iteration() {
  jq '.iteration = 0 | .started_at = (now | todate) | .updated_at = (now | todate)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Check if stuck (no update for N seconds)
is_stuck() {
  local timeout_seconds="${1:-600}"
  local updated_at
  updated_at=$(jq -r '.updated_at // empty' "$STATE_FILE")

  if [[ -z "$updated_at" ]]; then
    echo "0"
    return
  fi

  local updated_epoch
  local now_epoch

  # Handle both GNU and BSD date
  if date --version >/dev/null 2>&1; then
    # GNU date
    updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "0")
  else
    # BSD date
    updated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null || echo "0")
  fi

  now_epoch=$(date +%s)
  local diff=$((now_epoch - updated_epoch))

  [[ $diff -gt $timeout_seconds ]] && echo "1" || echo "0"
}

# Get review loop limit from config
get_review_loop_limit() {
  local config_file="pipeline.config.json"
  if [[ -f "$config_file" ]]; then
    jq -r '.autonomy.reviewLoopLimit // 5' "$config_file"
  else
    echo "5"
  fi
}

# Check if we've exceeded review loop limit
exceeded_review_limit() {
  local iteration
  local limit
  iteration=$(get_iteration)
  limit=$(get_review_loop_limit)

  [[ $iteration -ge $limit ]] && echo "1" || echo "0"
}

# Source this file to use functions, or run directly for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    init)
      init_state
      echo "State initialized"
      ;;
    status)
      get_status
      ;;
    state)
      get_state
      ;;
    set)
      set_state "$2" "$3"
      echo "State updated"
      ;;
    *)
      echo "Usage: $0 {init|status|state|set <status> <task_id>}"
      exit 1
      ;;
  esac
fi
