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

## Phase 2: Implementation (After Plan Approved)

### Gemini (Orchestrator)
1. Create task in `.task/current-task.json` from approved plan
2. Set state to `implementing`
3. Invoke Claude for implementation
4. Invoke Codex for code review
5. Handle review loop (max: reviewLoopLimit)
6. Optional: Debate with Codex on questionable issues
7. Commit on approval (based on autonomy mode)

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

## Current Sprint Context

Add sprint-specific context here as needed. This section is referenced by the orchestrator when starting new features.
