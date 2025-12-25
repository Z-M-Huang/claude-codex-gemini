# Pipeline Workflow

## Phase 1: Planning (Before Any Code)

### Gemini (Orchestrator)
1. Receive user request
2. Ask clarifying questions if ambiguous
3. Create initial plan in `.task/plan.json`
4. Set state to `plan_refining`
5. Delegate to Claude for plan refinement

### Claude (Plan Refiner)
1. Read `.task/plan.json`
2. Analyze feasibility and clarity
3. Refine requirements, add technical details
4. Identify potential challenges
5. Write refined plan to `.task/plan-refined.json`

### Codex (Plan Reviewer)
1. Read `.task/plan-refined.json`
2. Review for:
   - Completeness (are all requirements clear?)
   - Feasibility (can this be implemented as described?)
   - Potential issues (security, performance, complexity)
   - Over-engineering risks
3. Write review to `.task/plan-review.json`
4. If `needs_changes`: Claude refines again (loop)
5. If `approved`: Gemini proceeds to implementation

### Plan Review Loop
```
Gemini (draft) -> Claude (refine) -> Codex (review) ->
                       ^                   |
                       +--- needs changes -+
                                           |
                                     approved -> implement
```

---

## Internal Reviews (Cost Optimization)

Before calling Codex (expensive external API), run parallel internal reviews with 2 unified reviewers:

### Internal Review Agents

| Agent | Model | Focus |
|-------|-------|-------|
| `reviewer-sonnet` | Sonnet | Fast, practical: code + security + tests |
| `reviewer-opus` | Opus | Deep, thorough: architecture + vulnerabilities + test quality |

Each unified reviewer covers all three areas (code, security, tests) in a single pass, reducing complexity while maintaining comprehensive coverage.

### Internal Review Flow

```
Claude output -> Internal Reviews (2 parallel) -> All pass? -> Codex
                         |                            |
                         v                            v
                    Any fail? ---------> Claude fixes -> re-run internal
```

### Running Internal Reviews

```bash
# Run both unified reviewers in parallel
./scripts/run-internal-reviews.sh

# Check results
cat .task/internal-review-summary.json
```

### Output Files

- `.task/internal-review-sonnet.json`
- `.task/internal-review-opus.json`
- `.task/internal-review-summary.json` (aggregated)

---

## Phase 2: Implementation (After Plan Approved)

### Gemini (Orchestrator)
1. Create task in `.task/current-task.json` from approved plan
2. Set state to `implementing`
3. Invoke Claude for implementation
4. **Run internal reviews** (2 parallel unified subagents)
5. If internal reviews pass, invoke Codex for external code review
6. Handle review loop (max: reviewLoopLimit)
7. Optional: Debate with Codex on questionable issues
8. Commit on approval (based on autonomy mode)

### Claude (Coder)
1. Read `.task/current-task.json`
2. Read `docs/standards.md`
3. Implement following standards
4. Write output to `.task/impl-result.json`

### Codex (Code Reviewer)
1. Read `.task/impl-result.json`
2. Read `docs/standards.md`
3. Check against review checklist
4. Write output to `.task/review-result.json`

---

## Output Formats

### plan.json (Gemini initial plan)
```json
{
  "id": "plan-001",
  "title": "Feature title",
  "description": "What the user wants",
  "requirements": ["req 1", "req 2"],
  "created_at": "ISO8601",
  "created_by": "gemini"
}
```

### plan-refined.json (Claude refined plan)
```json
{
  "id": "plan-001",
  "title": "Feature title",
  "description": "What the user wants",
  "requirements": ["req 1", "req 2"],
  "technical_approach": "How to implement",
  "files_to_modify": ["path/to/file.ts"],
  "files_to_create": ["path/to/new.ts"],
  "dependencies": [],
  "estimated_complexity": "low|medium|high",
  "potential_challenges": ["challenge 1"],
  "refined_by": "claude",
  "refined_at": "ISO8601"
}
```

### plan-review.json (Codex plan review)
```json
{
  "status": "approved|needs_changes",
  "summary": "Overall assessment",
  "concerns": [
    {
      "severity": "error|warning|suggestion",
      "area": "requirements|approach|complexity|risks|feasibility",
      "message": "Description of concern",
      "suggestion": "How to address"
    }
  ],
  "reviewed_by": "codex",
  "reviewed_at": "ISO8601"
}
```

### impl-result.json (Claude implementation)
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

### review-result.json (Codex code review)
Schema enforced via --output-schema.
See docs/schemas/review-result.schema.json

---

## State Machine

### States
`idle`, `plan_drafting`, `plan_refining`, `plan_reviewing`, `implementing`, `reviewing`, `debating`, `fixing`, `complete`, `committing`, `error`, `needs_user_input`

### Full Flow
```
idle -> plan_drafting -> plan_refining -> plan_reviewing ->
                              ^                  |
                              +-- needs changes -+
                                                 |
                                           approved
                                                 |
                                                 v
        implementing -> reviewing -> complete -> committing -> idle
              ^              |
              +-- fixing <---+ (needs changes)
```

### State Transitions

| From | To | Trigger |
|------|----|---------|
| `idle` | `plan_drafting` | User submits requirement |
| `plan_drafting` | `plan_refining` | Gemini creates initial plan |
| `plan_refining` | `plan_reviewing` | Claude refines plan |
| `plan_reviewing` | `plan_refining` | Codex requests changes |
| `plan_reviewing` | (exit) | Codex approves, run `plan-to-task.sh` |
| (after plan-to-task.sh) | `implementing` | Plan converted to task |
| `implementing` | `reviewing` | Claude completes |
| `reviewing` | `complete` | Codex approves |
| `reviewing` | `debating` | Gemini challenges review |
| `reviewing` | `fixing` | Codex rejects |
| `debating` | `fixing` | Accept review |
| `debating` | `complete` | Override review |
| `fixing` | `reviewing` | Claude fixes |
| `complete` | `committing` | Auto-commit enabled |
| `complete` | `idle` | Manual commit mode |
| `committing` | `idle` | Commit done |
| `plan_refining` | `error` | Failure after retries |
| `plan_reviewing` | `error` | Failure after retries |
| `plan_refining` | `needs_user_input` | Claude needs clarification |
| `implementing` | `error` | Failure after retries |
| `implementing` | `needs_user_input` | Claude needs clarification |
| `reviewing` | `error` | Failure after retries |
| `error` | `idle` | User skips task |
| `error` | `plan_refining` | User retries (plan phase) |
| `error` | `implementing` | User retries (impl phase) |
| `needs_user_input` | (previous state) | User provides input |

---

## Orchestrator Safety Features

### Atomic Locking

The orchestrator uses PID-based locking to prevent concurrent execution:

- Lock file: `.task/.orchestrator.lock`
- Contains PID of running orchestrator
- Stale locks (dead PID) are automatically cleaned up
- Both `run` and `reset` commands require the lock

```bash
# If you see "Another orchestrator is running" but it's stale:
rm .task/.orchestrator.lock
```

### Dry-Run Validation

Validate setup before running:

```bash
./scripts/orchestrator.sh dry-run
```

Checks:
- `.task/` directory exists
- `state.json` valid (or will be created)
- `pipeline.config.json` valid
- Required scripts executable
- Required docs exist
- `.task` in `.gitignore`
- CLI tools available

### Phase-Aware Recovery

The recovery tool respects which phase failed:

- Errors in `plan_refining`/`plan_reviewing` → retry from `plan_refining`
- Errors in `implementing`/`reviewing`/`fixing` → retry from `implementing`

```bash
# Interactive recovery
./scripts/recover.sh

# Check previous state
cat .task/state.json | jq '.previous_state'
```

### Local Config Overrides

Create `pipeline.config.local.json` for local overrides (gitignored):

```json
{
  "autonomy": {
    "planReviewLoopLimit": 5,
    "codeReviewLoopLimit": 10
  }
}
```

---

## Codex Session Resume

Codex reviews use `resume --last` for subsequent reviews to save tokens, with an updated prompt that includes changes since last review.

### How It Works

- **First review** (new task): Full prompt with all context (standards, workflow, etc.)
- **Subsequent reviews**: Uses `resume --last` + shorter prompt with changes summary

### Session Tracking

Uses `.task/.codex-session-active` marker file:
- Created after first successful Codex call
- Cleared when entering `plan_drafting` (new task), after plan approval (plan-to-task.sh), or via reset

This ensures:
- Plan reviews: first is fresh, subsequent use resume
- Code reviews: first is fresh (marker cleared after plan approved), subsequent use resume

### Plan Reviews (Subsequent)

```
## IMPORTANT: This is a follow-up review

The plan has been UPDATED based on your previous feedback.
Please re-read and re-review the refined plan below.

[Updated plan content]
```

### Code Reviews (Subsequent)

```
## IMPORTANT: This is a follow-up review

The implementation has been UPDATED based on your previous feedback.

### Files Changed Since Last Review:
[List of changed files from git diff or impl-result.json]

Please re-review focusing on the changed files.
```

---

## Current Sprint Context

Add sprint-specific context here as needed. This section is referenced by the orchestrator when starting new features.
