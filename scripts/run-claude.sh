#!/bin/bash
set -e

# Load standards and task
STANDARDS=$(cat docs/standards.md)
TASK=$(cat .task/current-task.json)

# Check if this is a fix iteration (review feedback exists)
FEEDBACK=""
if [[ -f .task/review-result.json ]]; then
  FEEDBACK=$(cat .task/review-result.json)
fi

# Build prompt with context injection
PROMPT="## Project Standards

$STANDARDS

---

## Your Task

$TASK"

# Add review feedback if fixing
if [[ -n "$FEEDBACK" ]]; then
  PROMPT="$PROMPT

---

## Review Feedback to Address

$FEEDBACK"
fi

PROMPT="$PROMPT

Implement the task following the standards above. Write your output to .task/impl-result.json."

# Execute Claude
claude -p "$PROMPT" \
  --output-format json \
  --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
  --permission-mode acceptEdits

# Verify output file was created and is valid JSON
if [[ ! -f .task/impl-result.json ]]; then
  echo "ERROR: Claude did not create .task/impl-result.json" >&2
  exit 1
fi

if ! jq empty .task/impl-result.json 2>/dev/null; then
  echo "ERROR: .task/impl-result.json is not valid JSON" >&2
  exit 1
fi

echo "Implementation complete: .task/impl-result.json"
