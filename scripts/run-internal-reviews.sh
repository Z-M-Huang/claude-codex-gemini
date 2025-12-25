#!/bin/bash
# Run internal reviews in parallel before escalating to Codex
# This reduces API costs by catching issues early with Claude subagents
# Uses 2 unified reviewers (sonnet + opus) covering code, security, and tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
  log_error "claude CLI not found. Please install Claude Code."
  exit 1
fi

# Clean up previous internal review results
rm -f .task/internal-review-*.json

log_info "Running 2 unified reviewers in parallel..."
log_info "  - reviewer-sonnet (fast, practical: code + security + tests)"
log_info "  - reviewer-opus (deep, thorough: architecture + vulnerabilities + test quality)"
echo ""

# Create temp directory for exit codes (Bash 3.2 + macOS/BSD compatible)
TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'internal-review')
trap "rm -rf $TEMP_DIR" EXIT

# Function to run a reviewer and capture exit code
run_reviewer() {
  local agent="$1"
  local exit_file="$TEMP_DIR/${agent}.exit"

  log_info "Starting $agent..."

  # Run claude task with the agent, capture exit code
  if claude task "$agent" --print > /dev/null 2>&1; then
    echo "0" > "$exit_file"
  else
    echo "1" > "$exit_file"
  fi
}

# Run both reviewers in background
run_reviewer "reviewer-sonnet" &
PID_SONNET=$!

run_reviewer "reviewer-opus" &
PID_OPUS=$!

# Wait for all background jobs (ignore exit codes here, check via temp files)
log_info "Waiting for reviewers to complete..."
wait || true

# Check exit codes from temp files
check_result() {
  local agent="$1"
  local exit_file="$TEMP_DIR/${agent}.exit"

  if [[ -f "$exit_file" ]] && [[ "$(cat "$exit_file")" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# Collect results
all_passed=true

if check_result "reviewer-sonnet"; then
  log_success "reviewer-sonnet: PASSED"
else
  log_error "reviewer-sonnet: FAILED"
  all_passed=false
fi

if check_result "reviewer-opus"; then
  log_success "reviewer-opus: PASSED"
else
  log_error "reviewer-opus: FAILED"
  all_passed=false
fi

echo ""

# Check that all required output files exist
REQUIRED_FILES=(
  ".task/internal-review-sonnet.json"
  ".task/internal-review-opus.json"
)

missing_files=()
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    missing_files+=("$file")
  fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
  log_error "Missing review output files:"
  for file in "${missing_files[@]}"; do
    log_error "  - $file"
  done
  all_passed=false
fi

# Aggregate results from output files
# Strict gating: only "approved" passes, anything else (needs_changes, unknown, invalid) fails
aggregate_status() {
  local issues=()
  local files_checked=0

  for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
      ((files_checked++)) || true

      # Check if file is valid JSON
      if ! jq empty "$file" 2>/dev/null; then
        local reviewer_name
        reviewer_name=$(basename "$file" .json)
        issues+=("$reviewer_name:invalid_json")
        continue
      fi

      local status
      status=$(jq -r '.status // "unknown"' "$file")

      # Only "approved" is a pass - everything else is a fail
      if [[ "$status" != "approved" ]]; then
        local reviewer
        reviewer=$(jq -r '.reviewer // "unknown"' "$file")
        if [[ "$status" == "needs_changes" ]]; then
          issues+=("$reviewer:needs_changes")
        else
          issues+=("$reviewer:invalid_status($status)")
        fi
      fi
    fi
  done

  # Fail if no files were checked
  if [[ $files_checked -eq 0 ]]; then
    echo "false"
    return
  fi

  # Fail if any reviewer had issues
  if [[ ${#issues[@]} -gt 0 ]]; then
    echo "false"
  else
    echo "true"
  fi
}

# Aggregate and write summary
log_info "Aggregating review results..."
final_status=$(aggregate_status)

# Override to false if any process failed or files missing
if [[ "$all_passed" == "false" ]]; then
  final_status="false"
fi

# Build issues array for summary
issues_json="[]"
for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    # Check if valid JSON first
    if ! jq empty "$file" 2>/dev/null; then
      file_reviewer=$(basename "$file" .json)
      issues_json=$(echo "$issues_json" | jq --arg r "$file_reviewer:invalid_json" '. + [$r]')
      continue
    fi

    file_status=$(jq -r '.status // "unknown"' "$file")
    # Only "approved" passes - flag everything else
    if [[ "$file_status" != "approved" ]]; then
      file_reviewer=$(jq -r '.reviewer // "unknown"' "$file")
      if [[ "$file_status" == "needs_changes" ]]; then
        issues_json=$(echo "$issues_json" | jq --arg r "$file_reviewer" '. + [$r]')
      else
        issues_json=$(echo "$issues_json" | jq --arg r "$file_reviewer:$file_status" '. + [$r]')
      fi
    fi
  fi
done

# Write summary
cat > .task/internal-review-summary.json << EOF
{
  "all_passed": $final_status,
  "reviewed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "files_missing": ${#missing_files[@]},
  "reviewers_with_issues": $issues_json,
  "recommendation": $(if [[ "$final_status" == "true" ]]; then echo '"proceed_to_codex"'; else echo '"fix_issues_first"'; fi)
}
EOF

echo ""
if [[ "$final_status" == "true" ]]; then
  log_success "All internal reviews PASSED"
  log_info "Ready for external Codex review"
  log_info "Run: ./scripts/run-codex-review.sh (for code) or ./scripts/run-codex-plan-review.sh (for plan)"
  exit 0
else
  log_warn "Internal reviews need attention"
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_error "${#missing_files[@]} output files missing - agents may not have Write permissions"
  fi
  log_info "Check individual review files in .task/internal-review-*.json"
  log_info "Fix issues and re-run: ./scripts/run-internal-reviews.sh"
  exit 1
fi
