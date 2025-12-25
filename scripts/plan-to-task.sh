#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

source "$SCRIPT_DIR/state-manager.sh"

# Initialize state if needed
init_state

# Check that plan was approved
if [[ ! -f .task/plan-review.json ]]; then
  echo "ERROR: No plan review found. Run plan review first." >&2
  exit 1
fi

PLAN_STATUS=$(jq -r '.status' .task/plan-review.json)
if [[ "$PLAN_STATUS" != "approved" ]]; then
  echo "ERROR: Plan not approved. Status: $PLAN_STATUS" >&2
  echo "Address the review concerns and get approval first." >&2
  exit 1
fi

if [[ ! -f .task/plan-refined.json ]]; then
  echo "ERROR: No refined plan found." >&2
  exit 1
fi

# Convert plan to task using jq for safe JSON generation
echo "Converting approved plan to implementation task..."

PLAN_ID=$(jq -r '.id' .task/plan-refined.json)
TASK_ID="${PLAN_ID/plan-/task-}"

# Build task JSON safely using jq
jq -n \
  --arg id "$TASK_ID" \
  --arg plan_id "$PLAN_ID" \
  --arg title "$(jq -r '.title' .task/plan-refined.json)" \
  --arg description "$(jq -r '.description' .task/plan-refined.json)" \
  --arg technical_approach "$(jq -r '.technical_approach' .task/plan-refined.json)" \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson requirements "$(jq -c '.requirements' .task/plan-refined.json)" \
  --argjson files_to_modify "$(jq -c '.files_to_modify // []' .task/plan-refined.json)" \
  --argjson files_to_create "$(jq -c '.files_to_create // []' .task/plan-refined.json)" \
  '{
    id: $id,
    type: "feature",
    title: $title,
    description: $description,
    requirements: $requirements,
    technical_approach: $technical_approach,
    constraints: [],
    context: {
      related_files: $files_to_modify,
      files_to_create: $files_to_create
    },
    plan_id: $plan_id,
    created_at: $created_at,
    created_by: "gemini"
  }' > .task/current-task.json

# Validate JSON
if ! jq empty .task/current-task.json 2>/dev/null; then
  echo "ERROR: Generated task JSON is invalid" >&2
  exit 1
fi

# Clear Codex session marker so first code review starts fresh
rm -f .task/.codex-session-active

# Update state
set_state "implementing" "$TASK_ID"
reset_iteration

echo "Task created: .task/current-task.json"
echo "Task ID: $TASK_ID"
echo "State set to: implementing"
echo ""
echo "Ready to run: ./scripts/orchestrator.sh"
