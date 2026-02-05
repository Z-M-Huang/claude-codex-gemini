# V2 Migration Plan: claude-codex-gemini

## Executive Summary

This document defines the plan to modernize `claude-codex-gemini` by:

1. Replacing 10 bash scripts with **2 cross-platform TypeScript scripts** (`run-claude-code.ts`, `run-codex.ts`)
2. Moving all orchestration logic into **GEMINI.md** (the orchestrator brain)
3. Porting **6 specialized agent definitions** from upstream `claude-codex`
4. Adding a **requirements-gathering phase** with acceptance criteria tracking
5. Achieving **full Windows/macOS/Linux** cross-platform support
6. Replacing `jq` dependency with a bundled **`json-tool.ts`** utility

The core principle: **Gemini/Antigravity is the orchestrator, scripts are dumb executors.**

---

## Table of Contents

- [1. Architecture](#1-architecture)
- [2. What Gets Deleted](#2-what-gets-deleted)
- [3. What Gets Created](#3-what-gets-created)
- [4. What Gets Updated](#4-what-gets-updated)
- [5. Script Design: run-claude-code.ts](#5-script-design-run-claude-codets)
- [6. Script Design: run-codex.ts](#6-script-design-run-codexts)
- [7. Script Design: json-tool.ts](#7-script-design-json-toolts)
- [8. Agent Definitions](#8-agent-definitions)
- [9. GEMINI.md Redesign](#9-geminimd-redesign)
- [10. Pipeline Flow](#10-pipeline-flow)
- [11. State Management](#11-state-management)
- [12. Output File Formats](#12-output-file-formats)
- [13. Cross-Platform Strategy](#13-cross-platform-strategy)
- [14. Migration Steps](#14-migration-steps)
- [15. Testing Strategy](#15-testing-strategy)
- [16. Open Questions](#16-open-questions)

---

## 1. Architecture

### Current (V1) - Script-Heavy

```
Gemini CLI / Antigravity  (reads GEMINI.md)
  |
  +-- orchestrator.sh          (600+ lines, state machine, locking, config)
  +-- state-manager.sh         (state file CRUD)
  +-- run-claude.sh             (invoke Claude for implementation)
  +-- run-claude-plan.sh        (invoke Claude for plan refinement)
  +-- run-codex-review.sh       (invoke Codex for code review)
  +-- run-codex-plan-review.sh  (invoke Codex for plan review)
  +-- run-internal-reviews.sh   (parallel internal reviews)
  +-- plan-to-task.sh           (convert plan to task)
  +-- error-handler.sh          (error logging)
  +-- recover.sh                (recovery tool)
```

**Problems:** 10 bash scripts, no Windows support, `jq` dependency, orchestration logic split between GEMINI.md and scripts, complex state management in bash.

### Target (V2) - Gemini-Brained

```
Gemini CLI / Antigravity  (reads GEMINI.md - contains ALL orchestration logic)
  |
  +-- scripts/run-claude-code.ts   (dumb executor: invoke Claude with instructions)
  +-- scripts/run-codex.ts         (dumb executor: invoke Codex for review)
  +-- scripts/json-tool.ts         (utility: cross-platform JSON read/write)
```

**Key change:** GEMINI.md becomes the sole orchestration brain. It reads `.task/` state, decides what to do next, picks the right agent instructions, and calls one of 2 scripts. The scripts know nothing about pipeline phases.

### Why This Works

| Concern | V1 (scripts handle it) | V2 (Gemini handles it) |
|---------|------------------------|------------------------|
| "What phase are we in?" | `state-manager.sh`, `orchestrator.sh` | Gemini reads `.task/*.json` files |
| "What to do next?" | `orchestrator.sh` (600 lines of bash) | GEMINI.md instructions |
| "How to invoke Claude?" | `run-claude.sh`, `run-claude-plan.sh` | `run-claude-code.ts` with `--instructions` param |
| "How to invoke Codex?" | `run-codex-review.sh`, `run-codex-plan-review.sh` | `run-codex.ts` with `--type` param |
| "What went wrong?" | `error-handler.sh`, `recover.sh` | Gemini reads error output, retries |
| "How to convert plan to task?" | `plan-to-task.sh` | `json-tool.ts` or Gemini writes JSON directly |

Gemini CLI and Antigravity are already capable orchestrators. They can read files, write files, execute commands, and make decisions. The scripts should be thin wrappers around CLI invocations, not decision-makers.

---

## 2. What Gets Deleted

### Scripts (all 10)

| File | Reason for Deletion |
|------|---------------------|
| `scripts/orchestrator.sh` | Orchestration moves to GEMINI.md |
| `scripts/state-manager.sh` | State managed by Gemini via json-tool.ts |
| `scripts/run-claude.sh` | Replaced by `run-claude-code.ts` |
| `scripts/run-claude-plan.sh` | Replaced by `run-claude-code.ts --instructions "..."` |
| `scripts/run-codex-review.sh` | Replaced by `run-codex.ts` |
| `scripts/run-codex-plan-review.sh` | Replaced by `run-codex.ts --type plan` |
| `scripts/run-internal-reviews.sh` | Sequential reviews managed by GEMINI.md |
| `scripts/plan-to-task.sh` | Gemini writes JSON directly or uses json-tool.ts |
| `scripts/error-handler.sh` | Gemini handles errors in-context |
| `scripts/recover.sh` | Gemini reads state and recovers |

### Agent Files (replaced by ported versions)

| File | Reason for Deletion |
|------|---------------------|
| `.claude/agents/reviewer-sonnet.md` | Replaced by `agents/plan-reviewer.md` + `agents/code-reviewer.md` |
| `.claude/agents/reviewer-opus.md` | Same as above |

### Configuration

| File | Reason for Deletion |
|------|---------------------|
| `pipeline.config.json` | Settings move into GEMINI.md or are hardcoded defaults in scripts. The upstream removed this for the same reason: the config was never actually consumed by anything meaningful. |

---

## 3. What Gets Created

### Scripts

| File | Purpose |
|------|---------|
| `scripts/run-claude-code.ts` | Invoke Claude Code CLI with instructions + hardcoded context |
| `scripts/run-codex.ts` | Invoke Codex CLI for plan/code review with structured output |
| `scripts/json-tool.ts` | Cross-platform JSON get/set/merge/validate utility |

### Agent Definitions

| File | Purpose | Ported From |
|------|---------|-------------|
| `agents/requirements-gatherer.md` | Business analyst + PM hybrid for requirements elicitation | Upstream (new) |
| `agents/planner.md` | Architect + fullstack planning | Upstream (new, replaces plan logic in CLAUDE.md) |
| `agents/plan-reviewer.md` | Plan review: architecture + security + QA | Upstream (replaces reviewer-sonnet/opus for plans) |
| `agents/implementer.md` | Fullstack + TDD implementation | Upstream (new, replaces impl logic in CLAUDE.md) |
| `agents/code-reviewer.md` | Code review: security + performance + QA | Upstream (replaces reviewer-sonnet/opus for code) |
| `agents/codex-reviewer.md` | Thin wrapper doc for Codex CLI invocation | Upstream (new) |

### State Template

| File | Purpose |
|------|---------|
| `.task.template/state.json` | Clean initial state for pipeline reset |

---

## 4. What Gets Updated

| File | Changes |
|------|---------|
| `GEMINI.md` | Complete rewrite: contains full orchestration logic, phase detection, agent selection, script invocation, error handling, recovery |
| `CLAUDE.md` | Simplified: remove plan refiner/coder roles (now in separate agent files), keep as general project context |
| `AGENTS.md` | Simplified: remove inline review logic (now in agent files), keep as general Codex context |
| `docs/standards.md` | Port upstream's expanded version (OWASP details, reviewer focus areas table, resource/concurrency/API sections) |
| `docs/workflow.md` | Rewrite: reflect new 2-script architecture, sequential review chain, requirements phase |
| `docs/schemas/plan-review.schema.json` | Update: add `needs_clarification`, `rejected` statuses; add `requirements_coverage` field |
| `docs/schemas/review-result.schema.json` | Update: add `needs_clarification` status; add `acceptance_criteria_verification` field |
| `README.md` | Rewrite: new architecture, cross-platform setup, Bun requirement, remove bash examples |
| `.gitignore` | Add `node_modules/`, update `.task/` patterns |

---

## 5. Script Design: run-claude-code.ts

### Purpose

A dumb executor that invokes the Claude Code CLI with provided instructions. It knows nothing about pipeline phases. Gemini decides what instructions to pass.

### Interface

```
bun scripts/run-claude-code.ts \
  --instructions "You are a planner. Read .task/plan.json and write .task/plan-refined.json" \
  --output ".task/plan-refined.json" \
  [--agent-file "agents/planner.md"] \
  [--model "opus"] \
  [--timeout 600] \
  [--allowed-tools "Read,Write,Glob,Grep,Bash"]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--instructions` | Yes | The task instructions to pass to Claude Code |
| `--output` | No | Expected output file path (validated after execution) |
| `--agent-file` | No | Path to agent markdown file (prepended to instructions) |
| `--model` | No | Claude model to use (default: `sonnet`) |
| `--timeout` | No | Timeout in seconds (default: `600`) |
| `--allowed-tools` | No | Comma-separated tool list (default: `Read,Write,Edit,Glob,Grep,Bash`) |

### Hardcoded Behavior

The script automatically:

1. **Injects project context** - Prepends content from `docs/standards.md` to every invocation
2. **Injects state context** - Reads and summarizes relevant `.task/*.json` files based on what exists
3. **Validates output** - If `--output` specified, checks the file was created and contains valid JSON
4. **Outputs structured result** - Writes JSON to stdout with status and any errors

### Stdout Output

```json
{
  "event": "complete",
  "status": "success|failed|timeout",
  "output_file": ".task/plan-refined.json",
  "output_valid": true,
  "duration_ms": 45000,
  "error": null
}
```

### Implementation Notes

- Uses `child_process.spawn` to invoke `claude` CLI
- Platform-aware: uses `shell: true` on Windows, `shell: false` on Unix
- Claude CLI invocation: `claude --print --model <model> --allowedTools <tools> "<instructions>"`
  - The exact CLI flags depend on Claude Code's current interface; adapt as needed
- If `--agent-file` is provided, read the file content and prepend to `--instructions`
- Timeout kills the process with SIGKILL (or taskkill on Windows)
- All file reads use `path.join` for cross-platform paths

### Error Handling

| Error | Exit Code | Stdout Event |
|-------|-----------|--------------|
| Claude CLI not installed | 2 | `{"event": "error", "error": "not_installed"}` |
| Timeout | 3 | `{"event": "error", "error": "timeout"}` |
| Output file not created | 1 | `{"event": "error", "error": "no_output"}` |
| Output file invalid JSON | 1 | `{"event": "error", "error": "invalid_output"}` |
| Success | 0 | `{"event": "complete", "status": "success"}` |

---

## 6. Script Design: run-codex.ts

### Purpose

Invoke the Codex CLI for plan or code review with structured output validation. Ported from upstream's `codex-review.js` with adaptations.

### Interface

```
bun scripts/run-codex.ts \
  --type plan|code \
  [--changes-summary "Fixed SQL injection, added input validation"] \
  [--timeout 1200]
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--type` | Yes | `plan` or `code` — determines input/output files and schema |
| `--changes-summary` | No | Summary of changes since last review (for re-reviews) |
| `--timeout` | No | Timeout in seconds (default: `1200` = 20 minutes) |

### Hardcoded Behavior

The script automatically:

1. **Determines input file**:
   - `plan` → reads `.task/plan-refined.json`
   - `code` → reads `.task/impl-result.json`
2. **Selects output file**:
   - `plan` → writes to `.task/review-codex.json`
   - `code` → writes to `.task/code-review-codex.json`
3. **Selects schema**:
   - `plan` → `docs/schemas/plan-review.schema.json`
   - `code` → `docs/schemas/review-result.schema.json`
4. **Injects standards** from `docs/standards.md` into the prompt
5. **Manages session resume**:
   - Session marker: `.task/.codex-session-<type>`
   - First review: fresh prompt with full context
   - Subsequent reviews: `codex exec resume --last` with changes summary
   - Session expired: auto-removes marker and retries fresh
6. **Validates output**: Checks JSON validity, required fields (`status`, `summary`), valid status values

### Stdout Output

```json
{
  "event": "complete",
  "status": "approved|needs_changes|needs_clarification|rejected",
  "summary": "Review summary from Codex",
  "needs_clarification": false,
  "output_file": ".task/review-codex.json",
  "session_marker_created": true
}
```

### Error Handling

| Error | Exit Code | Description |
|-------|-----------|-------------|
| Codex not installed | 2 | `codex --version` fails |
| Auth required | 2 | Codex stderr contains "auth" |
| Timeout | 3 | Exceeds `--timeout` |
| Missing input file | 1 | `.task/plan-refined.json` or `.task/impl-result.json` not found |
| Invalid output | 1 | Output doesn't match schema |
| Session expired | auto-retry | Removes marker, retries fresh |

### Session Management

```
First plan review:  fresh → creates .task/.codex-session-plan
Second plan review: resume --last → reuses context, saves tokens
First code review:  fresh → creates .task/.codex-session-code (separate from plan)
Second code review: resume --last → reuses context
```

Session markers are **scoped by review type** to prevent a plan review session from contaminating code reviews.

---

## 7. Script Design: json-tool.ts

### Purpose

Cross-platform replacement for `jq`. Provides JSON read/write/merge/validate operations.

### Interface

```
bun scripts/json-tool.ts get <file> <path>           # Get value at JSON path
bun scripts/json-tool.ts set <file> <updates...>     # Update values
bun scripts/json-tool.ts valid <file>                 # Check if valid JSON
bun scripts/json-tool.ts merge <file1> <file2> ...   # Merge JSON files
```

### Operators for `set`

| Syntax | Example | Description |
|--------|---------|-------------|
| `field=value` | `status=approved` | Set string value |
| `field:=value` | `iteration:=3` | Set JSON value (number, bool, null) |
| `field@=now` | `reviewed_at@=now` | Set to current ISO timestamp |
| `+field` | `+iteration` | Increment numeric field |
| `-field` | `-old_key` | Delete field |

### Path Syntax

| Syntax | Example | Description |
|--------|---------|-------------|
| `.field` | `.status` | Top-level field |
| `.field.nested` | `.autonomy.mode` | Nested field |
| `.field // default` | `.status // idle` | Field with default if missing |

### Usage Examples

```bash
# Read pipeline state
bun scripts/json-tool.ts get .task/state.json .status

# Update state
bun scripts/json-tool.ts set .task/state.json status=implementing current_task_id=task-001 updated_at@=now

# Increment iteration
bun scripts/json-tool.ts set .task/state.json +iteration

# Check if file is valid JSON
bun scripts/json-tool.ts valid .task/plan-refined.json

# Merge base config with local overrides
bun scripts/json-tool.ts merge pipeline.config.json pipeline.config.local.json
```

### Implementation

Port directly from upstream `claude-codex` (`plugins/claude-codex/scripts/json-tool.ts`). The upstream version is already cross-platform and handles all edge cases. Minor adaptations:

- Remove any plugin-specific path assumptions
- Keep the `merge-get` subcommand (useful for config with local overrides)

---

## 8. Agent Definitions

### Agent File Structure

Each agent is a markdown file in `agents/` with frontmatter:

```markdown
---
name: agent-name
description: Short description of the agent's expertise
---

# Agent Title

Instructions for this agent...
```

The frontmatter is informational — Gemini reads it to decide which agent to use. The body is the actual instructions passed to `run-claude-code.ts` via `--agent-file`.

### Agent Inventory

#### 1. `agents/requirements-gatherer.md` (NEW)

**Source:** Port from upstream `requirements-gatherer.md`

**Purpose:** Elicit comprehensive requirements from the user through structured questioning, producing a `user-story.json` with acceptance criteria.

**Key adaptations for this repo:**
- Remove `AskUserQuestion` tool references (Gemini/Antigravity handles user interaction differently)
- Add note that Gemini will relay questions to the user and pass answers back
- Keep the RICE scoring, Given/When/Then acceptance criteria format
- Keep the `test_criteria` section for TDD validation

**Output:** `.task/user-story.json`

#### 2. `agents/planner.md` (NEW)

**Source:** Port from upstream `planner.md`

**Purpose:** Create comprehensive implementation plans through deep codebase research.

**Key adaptations:**
- Remove `LSP` tool references (may not be available in all contexts)
- Remove `disallowedTools` frontmatter (not used by Gemini)
- Keep the 3-phase process (Research → Design → Plan)
- Keep the `completion_promise` pattern
- Keep the `test_plan` section with commands and patterns

**Output:** `.task/plan-refined.json`

#### 3. `agents/plan-reviewer.md` (REPLACES reviewer-sonnet/opus for plan reviews)

**Source:** Port from upstream `plan-reviewer.md`

**Purpose:** Validate implementation plans for architecture, security, and quality.

**Key adaptations:**
- Remove model-specific output file naming (`review-sonnet.json` vs `review-opus.json`)
- Instead: Gemini tells the script where to write via `--output`
- Keep the `requirements_coverage` verification (critical for AC tracking)
- Keep the scoring system and severity definitions
- Add `needs_clarification` status (upstream addition)

**Output:** Gemini specifies via `--output` parameter (e.g., `.task/review-sonnet.json`, `.task/review-opus.json`)

#### 4. `agents/implementer.md` (REPLACES implementation logic in CLAUDE.md)

**Source:** Port from upstream `implementer.md`

**Purpose:** Implement the approved plan with clean, tested code.

**Key adaptations:**
- Remove `TaskCreate/TaskUpdate/TaskList` references (Claude Code-specific tools)
- Remove the "Phase 0: Create Progress Tasks" section
- Keep the "No User Interaction" rules (worker agent, no questions)
- Keep TDD cycle (red → green → refactor)
- Keep the deviations tracking in output
- Keep the "valid partial status" definitions (true blockers only)

**Output:** `.task/impl-result.json`

#### 5. `agents/code-reviewer.md` (REPLACES reviewer-sonnet/opus for code reviews)

**Source:** Port from upstream `code-reviewer.md`

**Purpose:** Validate implemented code for security, performance, and quality.

**Key adaptations:**
- Same model-specific output file adaptation as plan-reviewer
- Keep `acceptance_criteria_verification` section (critical)
- Keep OWASP checklist
- Keep the `git diff` step in code analysis
- Keep scoring and severity definitions

**Output:** Gemini specifies via `--output` parameter (e.g., `.task/code-review-sonnet.json`, `.task/code-review-opus.json`)

#### 6. `agents/codex-reviewer.md` (NEW - documentation only)

**Source:** Port from upstream `codex-reviewer.md`, simplified

**Purpose:** Document how Codex review works for reference. Not passed to Claude — it's a reference for GEMINI.md.

**Key adaptation:** This is primarily documentation for the Gemini orchestrator. The actual Codex invocation is handled by `run-codex.ts`. This file documents:
- What `run-codex.ts` does
- How to interpret results
- Session management behavior
- Error handling

---

## 9. GEMINI.md Redesign

### Design Principles

1. **Single source of orchestration truth** — all pipeline logic lives here
2. **No bash commands** — only `bun scripts/*.ts` invocations
3. **File-system-as-state** — phase determined by which `.task/*.json` files exist
4. **Agent selection via instructions** — Gemini picks the right agent file and passes it to the script

### Structure Outline

```markdown
# Pipeline Orchestrator

You coordinate a multi-AI development pipeline. You do NOT write code.

## Your Tools
- `bun scripts/run-claude-code.ts` — invoke Claude for any phase
- `bun scripts/run-codex.ts` — invoke Codex for reviews
- `bun scripts/json-tool.ts` — read/write JSON files

## Phase Detection
Read .task/ files to determine current phase:
- No .task/user-story.json → Phase: Requirements
- No .task/plan-refined.json → Phase: Planning
- No .task/review-sonnet.json → Phase: Plan Review (Sonnet)
- ... (full chain)

## Phase: Requirements Gathering
[How to invoke requirements-gatherer agent, handle user Q&A]

## Phase: Planning
[How to invoke planner agent]

## Phase: Plan Review (Sequential: Sonnet → Opus → Codex)
[How to invoke reviewers, handle needs_changes/needs_clarification]

## Phase: Implementation
[How to invoke implementer agent]

## Phase: Code Review (Sequential: Sonnet → Opus → Codex)
[Same pattern as plan review]

## Error Handling
[Read error output, retry logic, when to ask user]

## Recovery
[How to reset, clean up stale state]

@docs/standards.md
@docs/workflow.md
```

### Key Differences from V1 GEMINI.md

| V1 | V2 |
|----|----|
| `./scripts/orchestrator.sh` | Gemini reads `.task/` directly |
| `./scripts/state-manager.sh set plan_refining plan-001` | `bun scripts/json-tool.ts set .task/state.json status=plan_refining` |
| `./scripts/run-claude-plan.sh` | `bun scripts/run-claude-code.ts --agent-file agents/planner.md --output .task/plan-refined.json` |
| `./scripts/run-codex-review.sh` | `bun scripts/run-codex.ts --type code` |
| `./scripts/run-internal-reviews.sh` | Gemini runs Sonnet review, then Opus review sequentially |
| `cat .task/state.json \| jq` | `bun scripts/json-tool.ts get .task/state.json .status` |
| No requirements phase | Full requirements gathering with user-story.json |
| Parallel internal reviews | Sequential: Sonnet → Opus → Codex |

---

## 10. Pipeline Flow

### Full Pipeline (V2)

```
User Request → Gemini (orchestrator)
  |
  |-- Phase 1: Requirements Gathering
  |   run-claude-code.ts --agent-file agents/requirements-gatherer.md
  |   → .task/user-story.json
  |   (Gemini relays questions to user, passes answers back)
  |
  |-- Phase 2: Planning
  |   run-claude-code.ts --agent-file agents/planner.md --model opus
  |   → .task/plan-refined.json
  |
  |-- Phase 3: Plan Review (sequential)
  |   |-- Sonnet: run-claude-code.ts --agent-file agents/plan-reviewer.md --model sonnet
  |   |   → .task/review-sonnet.json
  |   |   needs_changes? → run-claude-code.ts --agent-file agents/planner.md (fix) → re-review
  |   |
  |   |-- Opus: run-claude-code.ts --agent-file agents/plan-reviewer.md --model opus
  |   |   → .task/review-opus.json
  |   |   needs_changes? → fix → re-review
  |   |
  |   |-- Codex: run-codex.ts --type plan
  |       → .task/review-codex.json
  |       rejected? → escalate to user
  |       needs_changes? → fix → re-review
  |
  |-- Phase 4: Implementation
  |   run-claude-code.ts --agent-file agents/implementer.md --model sonnet
  |   → .task/impl-result.json
  |
  |-- Phase 5: Code Review (sequential)
  |   |-- Sonnet: run-claude-code.ts --agent-file agents/code-reviewer.md --model sonnet
  |   |   → .task/code-review-sonnet.json
  |   |
  |   |-- Opus: run-claude-code.ts --agent-file agents/code-reviewer.md --model opus
  |   |   → .task/code-review-opus.json
  |   |
  |   |-- Codex: run-codex.ts --type code
  |       → .task/code-review-codex.json
  |
  |-- Phase 6: Complete
      Gemini reports results, optionally commits
```

### Review Loop (Same for Plan + Code)

```
Reviewer returns needs_changes:
  1. Gemini reads feedback from review file
  2. Gemini invokes fixer (planner for plan, implementer for code)
     with instructions: "Fix issues from <review-file>"
  3. Gemini re-invokes SAME reviewer
  4. Max 10 iterations per reviewer, then escalate to user

Reviewer returns needs_clarification:
  1. Gemini reads clarification_questions from review file
  2. If Gemini can answer from context: answer directly, re-run reviewer
  3. If not: ask user, pass answer, re-run reviewer

Reviewer returns rejected (Codex only):
  1. Plan rejected → terminal, ask user for direction
  2. Code rejected → create rework task, re-run full review chain
```

### Why Sequential (Not Parallel)

V1 ran internal reviews in parallel. V2 switches to sequential because:

1. **Cost efficiency** — if Sonnet catches 5 issues, Opus doesn't waste time finding those same 5
2. **Cascading fixes** — Sonnet fixes feed into Opus review, Opus fixes feed into Codex
3. **Simpler orchestration** — Gemini runs one command at a time, no parallel process management
4. **Better for Gemini CLI** — Gemini CLI doesn't have native subagent spawning; sequential is the natural pattern

---

## 11. State Management

### V1 State (Complex)

V1 used a `state.json` with status codes, iteration counters, PID locks, and error tracking. The `state-manager.sh` script handled transitions.

### V2 State (Implicit from Artifacts)

Phase is **determined by which `.task/` files exist**, not by explicit state tracking:

```
No user-story.json           → Phase: Requirements
No plan-refined.json         → Phase: Planning
No review-sonnet.json        → Phase: Plan Review (Sonnet)
review-sonnet.json exists    → Check status field
  needs_changes              → Phase: Fix Plan (Sonnet)
  needs_clarification        → Phase: Clarification (Sonnet)
  approved                   → Phase: Plan Review (Opus)
... (same pattern through the chain)
All reviews approved         → Phase: Complete
```

### Lightweight state.json (Optional)

A minimal `state.json` can still be useful for:
- **Iteration counter** — track fix iterations per reviewer
- **Timestamps** — when each phase started/completed
- **Metadata** — pipeline ID, user request summary

```json
{
  "pipeline_id": "pipe-20260205-143000",
  "status": "in_progress",
  "iterations": {
    "plan_review_sonnet": 0,
    "plan_review_opus": 0,
    "plan_review_codex": 0,
    "code_review_sonnet": 0,
    "code_review_opus": 0,
    "code_review_codex": 0
  },
  "started_at": "2026-02-05T14:30:00Z",
  "updated_at": "2026-02-05T15:00:00Z"
}
```

Gemini reads/writes this via `json-tool.ts`. No locking needed — only one orchestrator runs at a time (Gemini CLI is single-threaded).

---

## 12. Output File Formats

### `.task/user-story.json` (NEW)

```json
{
  "id": "story-YYYYMMDD-HHMMSS",
  "title": "Feature title",
  "description": "As a <user>, I want <feature> so that <benefit>",
  "requirements": {
    "functional": ["Core requirements"],
    "non_functional": ["Performance, security requirements"],
    "constraints": ["Technical constraints"]
  },
  "acceptance_criteria": [
    {
      "id": "AC1",
      "scenario": "Scenario name",
      "given": "Initial context",
      "when": "Action taken",
      "then": "Expected outcome"
    }
  ],
  "scope": {
    "in_scope": ["Included items"],
    "out_of_scope": ["Excluded items"],
    "assumptions": ["Documented assumptions"]
  },
  "test_criteria": {
    "commands": ["npm test"],
    "success_pattern": "passed",
    "failure_pattern": "FAILED|Error"
  },
  "approved_by": "user",
  "approved_at": "ISO8601"
}
```

### `.task/plan-refined.json` (UPDATED)

```json
{
  "id": "plan-YYYYMMDD-HHMMSS",
  "title": "Implementation plan title",
  "summary": "2-3 sentence overview",
  "technical_approach": {
    "pattern": "Architectural pattern",
    "rationale": "Why this approach",
    "alternatives_considered": [
      { "approach": "Alt 1", "rejected_because": "Reason" }
    ]
  },
  "steps": [
    {
      "id": 1,
      "phase": "setup|implementation|testing|cleanup",
      "file": "path/to/file.ts",
      "action": "create|modify|delete",
      "description": "What to do and why",
      "dependencies": [0],
      "tests": ["Related test cases"],
      "risks": ["Potential issues"]
    }
  ],
  "files_to_modify": ["path/to/file.ts"],
  "files_to_create": ["path/to/new-file.ts"],
  "test_plan": {
    "commands": ["npm test", "npm run lint"],
    "success_pattern": "passed",
    "failure_pattern": "FAILED|Error"
  },
  "risk_assessment": {
    "technical_risks": [
      { "risk": "Description", "severity": "high|medium|low", "mitigation": "Strategy" }
    ],
    "security_considerations": ["Security implications"]
  },
  "dependencies": {
    "external": ["npm packages"],
    "internal": ["Other modules"],
    "breaking_changes": ["Changes that affect other code"]
  }
}
```

### `.task/review-*.json` (Plan Reviews — UPDATED)

```json
{
  "status": "approved|needs_changes|needs_clarification|rejected",
  "summary": "Overall assessment",
  "needs_clarification": false,
  "clarification_questions": [],
  "requirements_coverage": {
    "mapping": [
      { "ac_id": "AC1", "steps": ["Step 3"] },
      { "ac_id": "AC2", "steps": ["Step 5", "Step 6"] }
    ],
    "missing": []
  },
  "findings": [
    {
      "id": "F1",
      "category": "requirements|security|architecture|quality|feasibility",
      "severity": "critical|high|medium|low|info",
      "title": "Short description",
      "description": "Detailed explanation",
      "recommendation": "How to fix"
    }
  ],
  "reviewed_at": "ISO8601"
}
```

### `.task/impl-result.json` (UPDATED)

```json
{
  "id": "impl-YYYYMMDD-HHMMSS",
  "plan_implemented": "plan-YYYYMMDD-HHMMSS",
  "status": "complete|partial|failed",
  "steps_completed": [1, 2, 3],
  "steps_remaining": [4, 5],
  "blocked_reason": "Only if status=partial",
  "files_modified": ["path/to/file.ts"],
  "files_created": ["path/to/new-file.ts"],
  "tests": {
    "written": 5,
    "passing": 5,
    "failing": 0
  },
  "deviations": [
    {
      "step": 2,
      "planned": "What was planned",
      "actual": "What was done",
      "reason": "Why"
    }
  ],
  "completed_at": "ISO8601"
}
```

### `.task/code-review-*.json` (Code Reviews — UPDATED)

```json
{
  "status": "approved|needs_changes|needs_clarification|rejected",
  "summary": "Overall assessment",
  "needs_clarification": false,
  "clarification_questions": [],
  "acceptance_criteria_verification": {
    "total": 3,
    "verified": 3,
    "missing": [],
    "details": [
      { "ac_id": "AC1", "status": "IMPLEMENTED", "evidence": "src/auth.ts:42", "notes": "" },
      { "ac_id": "AC2", "status": "NOT_IMPLEMENTED", "evidence": "", "notes": "Missing" }
    ]
  },
  "findings": [
    {
      "id": "F1",
      "category": "security|performance|quality|testing|compliance",
      "severity": "critical|high|medium|low|info",
      "title": "Short description",
      "file": "path/to/file.ts",
      "line": 42,
      "description": "Why this is an issue",
      "recommendation": "How to fix"
    }
  ],
  "reviewed_at": "ISO8601"
}
```

---

## 13. Cross-Platform Strategy

### Runtime: Bun

All scripts use Bun as the TypeScript runtime. Bun runs on Windows, macOS, and Linux.

**Why Bun over Node.js:**
- Native TypeScript execution (no build step)
- Faster startup for CLI tools
- Built-in file I/O APIs
- The upstream already standardized on Bun

**Prerequisite:** Users must install Bun. Add to README prerequisites.

### Path Handling

All scripts use `path.join()` and `path.resolve()` — never string concatenation with `/`.

```typescript
// Good
const statePath = path.join(TASK_DIR, 'state.json');

// Bad
const statePath = TASK_DIR + '/state.json';
```

### Process Spawning

```typescript
const isWindows = process.platform === 'win32';

if (isWindows) {
  // Windows: npm global commands are .cmd files requiring shell
  spawn(command, [], { shell: true });
} else {
  // Unix: shell: false is safer
  spawn(command, args, { shell: false });
}
```

### File Operations

- Use `fs.mkdirSync(dir, { recursive: true })` for directory creation
- Use `fs.existsSync()` instead of `test -f`
- Use `fs.writeFileSync()` instead of `echo >` or `cat <<EOF`

### GEMINI.md Platform Awareness

GEMINI.md instructions reference `bun scripts/*.ts` which works identically on all platforms:

```
# Works on all platforms:
bun scripts/run-claude-code.ts --agent-file agents/planner.md --output .task/plan-refined.json
```

No platform-specific instructions needed in GEMINI.md.

---

## 14. Migration Steps

### Phase 1: Create New Files

1. Create `scripts/json-tool.ts` (port from upstream)
2. Create `scripts/run-claude-code.ts` (new)
3. Create `scripts/run-codex.ts` (based on upstream `codex-review.js`)
4. Create all 6 agent files in `agents/` (port from upstream with adaptations)
5. Create `.task.template/state.json`

### Phase 2: Update Existing Files

6. Rewrite `GEMINI.md` with full orchestration logic
7. Simplify `CLAUDE.md` (remove plan/impl roles, keep project context)
8. Simplify `AGENTS.md` (remove inline review logic, keep Codex context)
9. Update `docs/standards.md` (port upstream's expanded version)
10. Rewrite `docs/workflow.md` (reflect new architecture)
11. Update `docs/schemas/plan-review.schema.json`
12. Update `docs/schemas/review-result.schema.json`
13. Update `README.md` (new architecture, cross-platform setup)
14. Update `.gitignore` (add `node_modules/`)

### Phase 3: Delete Old Files

15. Delete all 10 bash scripts from `scripts/`
16. Delete `.claude/agents/reviewer-sonnet.md`
17. Delete `.claude/agents/reviewer-opus.md`
18. Delete `pipeline.config.json`

### Phase 4: Validation

19. Run `bun scripts/json-tool.ts valid .task.template/state.json`
20. Test `run-claude-code.ts` with a simple instruction
21. Test `run-codex.ts --type plan` (dry-run)
22. Verify all agent files parse correctly
23. Review GEMINI.md for any remaining bash references

---

## 15. Testing Strategy

### Unit Tests for Scripts

Each script should have a corresponding test file:

| Script | Test File |
|--------|-----------|
| `scripts/json-tool.ts` | `scripts/json-tool.test.ts` |
| `scripts/run-codex.ts` | `scripts/run-codex.test.ts` |
| `scripts/run-claude-code.ts` | `scripts/run-claude-code.test.ts` |

### json-tool.ts Tests

Port from upstream `json-tool.ts` tests (if they exist). Test:
- `get` with nested paths, defaults, missing fields
- `set` with string, JSON, timestamp, increment, delete operators
- `valid` with valid and invalid JSON
- `merge` with overlapping keys, nested objects
- Edge cases: empty files, malformed JSON, missing files

### run-codex.ts Tests

Port from upstream `codex-review.test.js`. Test:
- Argument parsing
- Input validation (missing files, invalid type)
- Output validation (missing status, invalid status)
- Session marker management
- Platform-specific spawn behavior (mock)
- Timeout handling

### run-claude-code.ts Tests

Test:
- Argument parsing
- Agent file loading and prepending
- Context injection (standards.md, state files)
- Output validation
- Timeout handling
- Platform-specific behavior

### Integration Testing

Manual integration tests:
1. Run full pipeline with a trivial task (e.g., "add a comment to file X")
2. Verify each phase produces expected output files
3. Verify re-review loop works (mock a `needs_changes` response)
4. Test on Windows, macOS, and Linux

---

## 16. Open Questions

### Q1: How does Gemini/Antigravity invoke shell commands?

When Gemini reads GEMINI.md and sees `bun scripts/run-claude-code.ts ...`, does it:
- (a) Execute it via its built-in shell tool?
- (b) Need a specific extension/skill to run commands?
- (c) Depend on whether it's Gemini CLI vs Antigravity?

**Impact:** Determines if GEMINI.md needs special syntax for command invocation.

**Assumption:** Gemini CLI has a shell tool that can execute arbitrary commands, similar to Claude Code's Bash tool.

### Q2: Can Gemini read files directly?

If Gemini can read `.task/review-sonnet.json` directly (via a Read tool or file access), it doesn't need `json-tool.ts get` for phase detection. It could just read the files and parse the status.

**Impact:** Determines if json-tool.ts is mainly for scripts or also for GEMINI.md.

**Assumption:** Gemini can read files directly. json-tool.ts is mainly for the scripts and for set/merge operations.

### Q3: How does user interaction work in Antigravity?

When the requirements-gatherer needs to ask the user questions:
- In Gemini CLI: Gemini can prompt the user directly
- In Antigravity: Does the Manager View surface questions to the user?

**Impact:** Determines how requirements-gatherer relays questions.

### Q4: Bun availability on all platforms?

Bun supports Windows, macOS, and Linux, but is it commonly available in Antigravity's environment?

**Impact:** If Bun isn't guaranteed, we may need to support `node --loader ts-node` as a fallback, or compile TS to JS.

**Mitigation:** Add Bun installation to prerequisites. Consider a `npx tsx` fallback.

### Q5: Should we keep the `.claude/agents/` directory?

The upstream puts agents in `plugins/claude-codex/agents/`. This repo could use:
- `agents/` (at root — simpler)
- `.claude/agents/` (Claude Code convention)

**Recommendation:** Use `agents/` at root. This repo isn't a Claude Code plugin, and the agents are consumed by both Gemini (for selection) and Claude (for instructions).

### Q6: Maximum review iterations per reviewer?

V1 had configurable `planReviewLoopLimit` (3) and `codeReviewLoopLimit` (5). Upstream uses 10 per reviewer.

**Recommendation:** Hardcode 10 in GEMINI.md. If users want to customize, they can edit GEMINI.md directly.

---

## Appendix A: File Tree (V2 Target)

```
project-root/
├── agents/
│   ├── requirements-gatherer.md
│   ├── planner.md
│   ├── plan-reviewer.md
│   ├── implementer.md
│   ├── code-reviewer.md
│   └── codex-reviewer.md
├── docs/
│   ├── standards.md
│   ├── workflow.md
│   ├── PLAN-v2-migration.md       (this document)
│   └── schemas/
│       ├── plan-review.schema.json
│       └── review-result.schema.json
├── scripts/
│   ├── run-claude-code.ts
│   ├── run-codex.ts
│   ├── json-tool.ts
│   ├── run-codex.test.ts
│   ├── run-claude-code.test.ts
│   └── json-tool.test.ts
├── .task.template/
│   └── state.json
├── .task/                          (runtime, gitignored)
│   ├── state.json
│   ├── user-story.json
│   ├── plan-refined.json
│   ├── review-sonnet.json
│   ├── review-opus.json
│   ├── review-codex.json
│   ├── impl-result.json
│   ├── code-review-sonnet.json
│   ├── code-review-opus.json
│   ├── code-review-codex.json
│   └── .codex-session-*
├── GEMINI.md                       (orchestrator brain)
├── CLAUDE.md                       (project context for Claude)
├── AGENTS.md                       (Codex reviewer context)
├── README.md
├── LICENSE
└── .gitignore
```

## Appendix B: Upstream Reference

Upstream repo: https://github.com/Z-M-Huang/claude-codex (v1.3.1)

Key files referenced during this plan:
- `plugins/claude-codex/agents/*.md` — 6 agent definitions
- `plugins/claude-codex/scripts/codex-review.js` — cross-platform Codex invocation
- `plugins/claude-codex/scripts/json-tool.ts` — cross-platform JSON utility
- `plugins/claude-codex/hooks/guidance-hook.js` — phase detection logic (adapted for GEMINI.md)
- `plugins/claude-codex/hooks/review-validator.js` — AC verification logic (adapted for agent instructions)
- `plugins/claude-codex/docs/standards.md` — expanded review checklist
- `plugins/claude-codex/docs/workflow.md` — task-based workflow documentation
- `plugins/claude-codex/skills/multi-ai/SKILL.md` — orchestrator skill definition
