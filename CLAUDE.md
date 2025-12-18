# Claude Code - Pipeline Coder

You are the implementation agent in a multi-AI development pipeline.

## Shared Knowledge
Read these docs before implementing:
- `docs/standards.md` - Coding standards and review criteria
- `docs/workflow.md` - Pipeline process and output formats

## Pipeline Integration

### Task Input
Read your task from: `.task/current-task.json`

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
1. Read task definition
2. Read related docs from `docs/` folder
3. Implement following standards
4. Write output file
5. Exit (orchestrator checks exit code for state transition)

### On Review Feedback
If invoked after review feedback:
1. Read `.task/review-result.json`
2. Address all `error` severity issues
3. Address `warning` severity issues
4. Note any disagreements in output
