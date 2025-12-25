#!/bin/bash
set -e

# Run Codex to review the refined plan
# Uses structured output for consistent review format
# Uses resume --last for subsequent reviews to save tokens

# Session marker file - tracks if Codex has been called for this task
SESSION_MARKER=".task/.codex-session-active"

# Read model from config
# Merge local config if it exists
if [[ -f pipeline.config.local.json ]]; then
  MODEL=$(jq -s '.[0] * .[1] | .models.reviewer.model' pipeline.config.json pipeline.config.local.json)
else
  MODEL=$(jq -r '.models.reviewer.model // "o3-mini"' pipeline.config.json)
fi

STANDARDS=$(cat docs/standards.md)
WORKFLOW=$(cat docs/workflow.md)
PLAN=$(cat .task/plan-refined.json)

# Determine if this is a subsequent review (resume session)
if [[ -f "$SESSION_MARKER" ]]; then
  IS_RESUME=true
  echo "[INFO] Resuming Codex session - will include changes summary"
else
  IS_RESUME=false
  echo "[INFO] Starting fresh Codex session (first review for this task)"
fi

# Build the prompt based on whether this is a resume or fresh start
if [[ "$IS_RESUME" == true ]]; then
  # For resume: shorter prompt focusing on what changed
  PROMPT="## IMPORTANT: This is a follow-up review

The plan has been UPDATED based on your previous feedback. Please re-read and re-review the refined plan below.

---

## Updated Refined Plan

$PLAN

---

## Your Task

Re-review this updated plan. Check if previous concerns were addressed:

1. **Completeness**: Are all requirements clearly defined?
2. **Feasibility**: Can this be implemented as described?
3. **Technical approach**: Is the approach sound and appropriate?
4. **Complexity**: Is the estimated complexity accurate?
5. **Risks**: Are potential challenges properly identified?
6. **Over-engineering**: Is the approach too complex for the problem?

Write your review to .task/plan-review.json using this format:
{
  \"status\": \"approved\" or \"needs_changes\",
  \"summary\": \"Overall assessment\",
  \"concerns\": [
    {
      \"severity\": \"error|warning|suggestion\",
      \"area\": \"requirements|approach|complexity|risks|feasibility\",
      \"message\": \"Description of concern\",
      \"suggestion\": \"How to address\"
    }
  ],
  \"reviewed_by\": \"codex\",
  \"reviewed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}

Decision rules:
- Any 'error' concern -> status: needs_changes
- 2+ 'warning' concerns -> status: needs_changes
- Only 'suggestion' concerns -> status: approved"

else
  # First review: full prompt with all context
  PROMPT="## Project Standards

$STANDARDS

---

## Workflow Documentation

$WORKFLOW

---

## Refined Plan to Review

$PLAN

---

## Your Task

Review this plan BEFORE implementation begins. Check for:

1. **Completeness**: Are all requirements clearly defined?
2. **Feasibility**: Can this be implemented as described?
3. **Technical approach**: Is the approach sound and appropriate?
4. **Complexity**: Is the estimated complexity accurate?
5. **Risks**: Are potential challenges properly identified?
6. **Over-engineering**: Is the approach too complex for the problem?

Write your review to .task/plan-review.json using this format:
{
  \"status\": \"approved\" or \"needs_changes\",
  \"summary\": \"Overall assessment\",
  \"concerns\": [
    {
      \"severity\": \"error|warning|suggestion\",
      \"area\": \"requirements|approach|complexity|risks|feasibility\",
      \"message\": \"Description of concern\",
      \"suggestion\": \"How to address\"
    }
  ],
  \"reviewed_by\": \"codex\",
  \"reviewed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}

Decision rules:
- Any 'error' concern -> status: needs_changes
- 2+ 'warning' concerns -> status: needs_changes
- Only 'suggestion' concerns -> status: approved"
fi

# Execute Codex with schema enforcement
if [[ "$IS_RESUME" == true ]]; then
  codex exec \
    --full-auto \
    --model "$MODEL" \
    --output-schema docs/schemas/plan-review.schema.json \
    -o .task/plan-review.json \
    resume --last \
    "$PROMPT"
else
  codex exec \
    --full-auto \
    --model "$MODEL" \
    --output-schema docs/schemas/plan-review.schema.json \
    -o .task/plan-review.json \
    "$PROMPT"
fi

# Verify output file was created and is valid JSON
if [[ ! -f .task/plan-review.json ]]; then
  echo "ERROR: Codex did not create .task/plan-review.json" >&2
  exit 1
fi

if ! jq empty .task/plan-review.json 2>/dev/null; then
  echo "ERROR: .task/plan-review.json is not valid JSON" >&2
  exit 1
fi

# Mark session as active only after successful validation
touch "$SESSION_MARKER"

echo "Plan review complete: .task/plan-review.json"
cat .task/plan-review.json | jq '{status, summary}'
