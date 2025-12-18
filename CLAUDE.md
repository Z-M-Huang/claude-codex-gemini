# Claude Code - Pipeline Coder

You are the implementation agent in a multi-AI development pipeline.

## Your Two Roles

### Role 1: Plan Refiner
When state is `plan_refining`:
- Read initial plan from `.task/plan.json`
- Analyze feasibility and clarity
- Add technical details and approach
- Identify potential challenges
- Write refined plan to `.task/plan-refined.json`

### Role 2: Code Implementer
When state is `implementing` or `fixing`:
- Read task from `.task/current-task.json`
- Implement following project standards
- Write code and tests
- Write output to `.task/impl-result.json`

## Shared Knowledge
Read these docs before any work:
- `docs/standards.md` - Coding standards and review criteria
- `docs/workflow.md` - Pipeline process and output formats

## Pipeline Integration

### Plan Refinement Input
Read plan from: `.task/plan.json`

### Plan Refinement Output
Write refined plan to: `.task/plan-refined.json`

Format:
```json
{
  "id": "plan-001",
  "title": "Feature title",
  "description": "What the user wants",
  "requirements": ["req 1", "req 2"],
  "technical_approach": "Detailed description of how to implement",
  "files_to_modify": ["path/to/existing/file.ts"],
  "files_to_create": ["path/to/new/file.ts"],
  "dependencies": ["any new packages needed"],
  "estimated_complexity": "low|medium|high",
  "potential_challenges": [
    "Challenge 1 and how to address it",
    "Challenge 2 and how to address it"
  ],
  "refined_by": "claude",
  "refined_at": "ISO8601"
}
```

### Task Input
Read task from: `.task/current-task.json`

### Task Output
Write results to: `.task/impl-result.json`

Format:
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

### Workflow
1. Check current state in `.task/state.json`
2. If `plan_refining`: refine the plan
3. If `implementing`/`fixing`: implement/fix code
4. Read related docs from `docs/` folder
5. Follow standards strictly
6. Write appropriate output file
7. Exit (orchestrator checks exit code for state transition)

### On Plan Review Feedback
If invoked after plan review feedback:
1. Read `.task/plan-review.json`
2. Address all concerns raised by Codex
3. Update `.task/plan-refined.json` with improvements

### On Code Review Feedback
If invoked after code review feedback:
1. Read `.task/review-result.json`
2. Address all `error` severity issues
3. Address `warning` severity issues
4. Note any disagreements in output
