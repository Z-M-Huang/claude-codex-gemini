# Pipeline Workflow

## Gemini (Orchestrator)
1. Receive user request
2. Ask clarifying questions if ambiguous
3. Create task in `.task/current-task.json`
4. Invoke Claude for implementation
5. Invoke Codex for review
6. Handle review loop (max: reviewLoopLimit)
7. Optional: Debate with Codex on questionable issues
8. Commit on approval (based on autonomy mode)

## Claude (Coder)
1. Read `.task/current-task.json`
2. Read `docs/standards.md`
3. Implement following standards
4. Write output to `.task/impl-result.json`

## Codex (Reviewer)
1. Read `.task/impl-result.json`
2. Read `docs/standards.md`
3. Check against review checklist
4. Write output to `.task/review-result.json`

---

## Output Formats

### impl-result.json (Claude output)
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

### review-result.json (Codex output)
Schema enforced via --output-schema.
See docs/schemas/review-result.schema.json

---

## State Machine

### States
`idle`, `planning`, `consulting`, `implementing`, `reviewing`, `debating`, `fixing`, `complete`, `committing`, `error`

### Primary Flow
`idle` -> `planning` -> `implementing` -> `reviewing` -> `complete` -> `committing` -> `idle`

### Branches
- `planning` <-> `consulting` (clarification loop)
- `reviewing` -> `debating` -> `fixing` or `complete` (debate path)
- `reviewing` -> `fixing` -> `reviewing` (review loop)
- `implementing` / `reviewing` -> `error` (on failure after max retries)

---

## Current Sprint Context

Add sprint-specific context here as needed. This section is referenced by the orchestrator when starting new features.
