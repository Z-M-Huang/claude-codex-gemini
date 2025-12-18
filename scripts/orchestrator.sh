#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Source state manager
source "$SCRIPT_DIR/state-manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Initialize state if needed
init_state

# Get max retries from config
get_max_retries() {
  if [[ -f "pipeline.config.json" ]]; then
    jq -r '.errorHandling.autoResolveAttempts // 3' pipeline.config.json
  else
    echo "3"
  fi
}

# Log error to file
log_error_to_file() {
  local stage="$1"
  local exit_code="$2"
  local message="$3"

  mkdir -p .task/errors
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local error_file=".task/errors/error-${timestamp}.json"

  cat > "$error_file" << EOF
{
  "id": "err-${timestamp}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stage": "$stage",
  "exit_code": $exit_code,
  "message": "$message",
  "task_id": "$(get_task_id)",
  "iteration": $(get_iteration)
}
EOF

  echo "$error_file"
}

# Run implementation phase
run_implementation() {
  log_info "Running implementation (Claude)..."
  local task_id
  task_id=$(get_task_id)

  if "$SCRIPT_DIR/run-claude.sh"; then
    log_success "Implementation completed"
    set_state "reviewing" "$task_id"
    return 0
  else
    local exit_code=$?
    log_error "Implementation failed with exit code $exit_code"
    log_error_to_file "implementing" "$exit_code" "Claude implementation failed"
    return 1
  fi
}

# Run review phase
run_review() {
  log_info "Running review (Codex)..."
  local task_id
  task_id=$(get_task_id)

  if "$SCRIPT_DIR/run-codex-review.sh"; then
    log_success "Review completed"

    # Check review result
    local status
    status=$(jq -r '.status' .task/review-result.json)

    case "$status" in
      approved)
        log_success "Review approved!"
        set_state "complete" "$task_id"
        ;;
      needs_changes)
        log_warn "Review requires changes"
        increment_iteration

        if [[ $(exceeded_review_limit) == "1" ]]; then
          log_error "Exceeded review loop limit"
          set_state "error" "$task_id"
          return 1
        fi

        set_state "fixing" "$task_id"
        ;;
      rejected)
        log_error "Review rejected"
        set_state "error" "$task_id"
        return 1
        ;;
    esac
    return 0
  else
    local exit_code=$?
    log_error "Review failed with exit code $exit_code"
    log_error_to_file "reviewing" "$exit_code" "Codex review failed"
    return 1
  fi
}

# Run fix phase (same as implementation but with review feedback)
run_fix() {
  log_info "Running fix iteration $(get_iteration)..."
  local task_id
  task_id=$(get_task_id)

  # run-claude.sh automatically picks up review-result.json for fixes
  if "$SCRIPT_DIR/run-claude.sh"; then
    log_success "Fix completed"
    set_state "reviewing" "$task_id"
    return 0
  else
    local exit_code=$?
    log_error "Fix failed with exit code $exit_code"
    log_error_to_file "fixing" "$exit_code" "Claude fix failed"
    return 1
  fi
}

# Track retry attempts (stored in state file)
get_error_retry_count() {
  jq -r '.error_retry_count // 0' .task/state.json
}

increment_error_retry() {
  jq '.error_retry_count = ((.error_retry_count // 0) + 1) | .updated_at = (now | todate)' \
    .task/state.json > .task/state.json.tmp
  mv .task/state.json.tmp .task/state.json
}

reset_error_retry() {
  jq 'del(.error_retry_count) | .updated_at = (now | todate)' \
    .task/state.json > .task/state.json.tmp
  mv .task/state.json.tmp .task/state.json
}

# Handle error state with auto-resolve retry loop
handle_error() {
  local task_id
  task_id=$(get_task_id)
  local retry_count
  retry_count=$(get_error_retry_count)
  local max_retries
  max_retries=$(get_max_retries)

  log_error "Pipeline in error state for task: $task_id"
  log_info "Auto-resolve attempt: $((retry_count + 1)) / $max_retries"

  if [[ $retry_count -lt $max_retries ]]; then
    increment_error_retry

    # Determine retry strategy based on attempt number
    case $retry_count in
      0)
        log_info "Strategy: Retry with same approach..."
        ;;
      1)
        log_info "Strategy: Clear intermediate files and retry..."
        rm -f .task/impl-result.json
        ;;
      2)
        log_info "Strategy: Full reset and retry..."
        rm -f .task/impl-result.json .task/review-result.json
        ;;
    esac

    # Reset to implementing state to retry
    set_state "implementing" "$task_id"
    log_info "Retrying implementation..."
  else
    # Exhausted retries - pause for user intervention
    log_error "Exhausted all $max_retries auto-resolve attempts"
    log_warn "Manual intervention required. Options:"
    log_warn "  1. Run: ./scripts/recover.sh"
    log_warn "  2. Check errors: ls -la .task/errors/"
    log_warn "  3. Reset: ./scripts/orchestrator.sh reset"

    # Reset retry counter for next time
    reset_error_retry

    exit 1
  fi
}

# Handle debate between Gemini and Codex
handle_debate() {
  local task_id
  task_id=$(get_task_id)

  log_info "Processing debate..."

  # Check if debate file exists
  if [[ ! -f .task/debate.json ]]; then
    log_warn "No debate file found, defaulting to accept review"
    set_state "fixing" "$task_id"
    return
  fi

  local debate_status
  debate_status=$(jq -r '.status // "open"' .task/debate.json)

  if [[ "$debate_status" == "resolved" ]]; then
    local decision
    decision=$(jq -r '.resolution.decision // "accept_review"' .task/debate.json)

    case "$decision" in
      accept_review)
        log_info "Debate resolved: accepting review, proceeding to fix"
        set_state "fixing" "$task_id"
        ;;
      override_partial)
        log_info "Debate resolved: partial override, filtering issues"
        # Filter out overridden issues from review-result.json
        local kept_issues
        kept_issues=$(jq -r '.challenged_issues // []' .task/debate.json)
        jq --argjson skip "$kept_issues" \
          '.issues = [.issues[] | select(.id as $id | $skip | index($id) | not)]' \
          .task/review-result.json > .task/review-result.json.tmp
        mv .task/review-result.json.tmp .task/review-result.json
        set_state "fixing" "$task_id"
        ;;
      override_full)
        log_info "Debate resolved: full override, marking complete"
        set_state "complete" "$task_id"
        ;;
      *)
        log_warn "Unknown debate decision: $decision, defaulting to fix"
        set_state "fixing" "$task_id"
        ;;
    esac

    # Clean up debate file
    rm -f .task/debate.json
  else
    # Debate still open - check round count
    local round
    round=$(jq -r '.round // 1' .task/debate.json)
    local max_rounds
    max_rounds=$(jq -r '.debate.maxRounds // 2' pipeline.config.json)

    if [[ $round -ge $max_rounds ]]; then
      log_warn "Debate reached max rounds ($max_rounds), defaulting to accept review"
      set_state "fixing" "$task_id"
      rm -f .task/debate.json
    else
      log_info "Debate round $round/$max_rounds - awaiting resolution"
      log_warn "To resolve, update .task/debate.json with resolution.decision"
      log_warn "Options: accept_review, override_partial, override_full"
      # In full implementation, would invoke Gemini to process debate
      # For now, pause and wait for manual resolution or timeout
      exit 0
    fi
  fi
}

# Complete task
complete_task() {
  local task_id
  task_id=$(get_task_id)

  log_success "Task $task_id completed successfully!"

  # Reset error retry counter on success
  reset_error_retry

  # Check autonomy mode for auto-commit
  local commit_approval
  commit_approval=$(jq -r '.autonomy.approvalPoints.commit // true' pipeline.config.json)

  if [[ "$commit_approval" == "false" ]]; then
    log_info "Auto-commit enabled, committing changes..."
    set_state "committing" "$task_id"
    # git add . && git commit -m "feat($task_id): implemented task"
    log_warn "Git commit skipped in MVP - implement when ready"
    set_state "idle" ""
  else
    log_info "Waiting for manual commit approval"
    set_state "idle" ""
  fi

  # Clean up review-result.json for next iteration
  rm -f .task/review-result.json
}

# Main orchestration loop
main_loop() {
  while true; do
    local status
    status=$(get_status)

    log_info "Current state: $status"

    case "$status" in
      idle)
        log_info "Pipeline idle. Waiting for task..."
        # In full implementation, would poll for new tasks
        # For MVP, exit and let user create task manually
        exit 0
        ;;
      planning|consulting)
        log_info "Planning/consulting handled by Gemini orchestrator"
        exit 0
        ;;
      implementing)
        if ! run_implementation; then
          set_state "error" "$(get_task_id)"
        fi
        ;;
      reviewing)
        if ! run_review; then
          set_state "error" "$(get_task_id)"
        fi
        ;;
      fixing)
        if ! run_fix; then
          set_state "error" "$(get_task_id)"
        fi
        ;;
      debating)
        handle_debate
        ;;
      complete)
        complete_task
        ;;
      committing)
        log_info "Committing..."
        set_state "idle" ""
        ;;
      error)
        handle_error
        ;;
      *)
        log_error "Unknown state: $status"
        exit 1
        ;;
    esac

    # Small delay to prevent tight loop
    sleep 1
  done
}

# Entry point
case "${1:-run}" in
  run)
    log_info "Starting orchestrator..."
    main_loop
    ;;
  status)
    echo "Current state: $(get_status)"
    echo "Task ID: $(get_task_id)"
    echo "Iteration: $(get_iteration)"
    ;;
  reset)
    log_warn "Resetting pipeline state..."
    set_state "idle" ""
    rm -f .task/impl-result.json .task/review-result.json .task/debate.json
    log_success "Pipeline reset to idle"
    ;;
  *)
    echo "Usage: $0 {run|status|reset}"
    exit 1
    ;;
esac
