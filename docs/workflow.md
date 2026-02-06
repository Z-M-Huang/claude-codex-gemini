# Pipeline Workflow

## Architecture Overview

The pipeline uses:
- **Gemini** - Sole orchestrator (reads GEMINI.md for instructions)
- **Claude Code** - Agent executor for requirements, planning, implementation
- **Codex** - Final gate reviewer for plans and code
- **3 TypeScript scripts** - Cross-platform executors (no external dependencies)
- **6 specialized agents** - Markdown files defining agent behavior
- **File-system-as-state** - Phase detection via `.task/` file existence

---

## Custom Agents

| Agent | Model | Purpose | Phase |
|-------|-------|---------|-------|
| requirements-gatherer | Opus | Gather and validate user requirements | Requirements |
| planner | Opus | Create detailed implementation plans | Planning |
| plan-reviewer | Sonnet/Opus | Review plans for completeness, security, feasibility | Plan Review |
| implementer | Sonnet | Implement plans with TDD approach | Implementation |
| code-reviewer | Sonnet/Opus | Review code for security, quality, tests | Code Review |
| codex-reviewer | Codex | Final gate reviews (documentation agent) | Plan/Code Review |

---

## Pipeline Phases

The pipeline has 6 phases. Gemini detects the current phase by checking which `.task/*.json` files exist:

```
Requirements → Planning → Plan Review → Implementation → Code Review → Complete
                              ↓                              ↓
                  (Sonnet → Opus → Codex)       (Sonnet → Opus → Codex)
```

### Phase Detection Logic

| File Missing | Phase | Action |
|--------------|-------|--------|
| `.task/user-story.json` | Requirements | Run requirements-gatherer (Opus) |
| `.task/plan-refined.json` | Planning | Run planner (Opus) |
| `.task/review-sonnet.json` (or status != approved) | Plan Review (Sonnet) | Run plan-reviewer (Sonnet) |
| `.task/review-opus.json` (or status != approved) | Plan Review (Opus) | Run plan-reviewer (Opus) |
| `.task/review-codex.json` (or status != approved) | Plan Review (Codex) | Run run-codex.ts --type plan |
| `.task/impl-result.json` | Implementation | Run implementer (Sonnet) |
| `.task/code-review-sonnet.json` (or status != approved) | Code Review (Sonnet) | Run code-reviewer (Sonnet) |
| `.task/code-review-opus.json` (or status != approved) | Code Review (Opus) | Run code-reviewer (Opus) |
| `.task/code-review-codex.json` (or status != approved) | Code Review (Codex) | Run run-codex.ts --type code |
| All files exist and approved | Complete | Report results, optionally commit |

---

## Sequential Review Chain

Reviews happen in sequence (NOT parallel) to maintain quality gates:

**Plan Review:** Sonnet → Opus → Codex
**Code Review:** Sonnet → Opus → Codex

Each reviewer must approve before proceeding to the next. If any reviewer returns `needs_changes`, Gemini invokes the planner/implementer to fix issues, then re-runs that specific reviewer (max 10 iterations per reviewer).

---

## Output Files

All pipeline state lives in `.task/`:

| File | Created By | Contains |
|------|-----------|----------|
| `state.json` | Gemini | Pipeline state, iteration counters |
| `user-story.json` | requirements-gatherer | User requirements, acceptance criteria |
| `plan-refined.json` | planner | Implementation plan |
| `review-sonnet.json` | plan-reviewer (Sonnet) | Sonnet's plan review |
| `review-opus.json` | plan-reviewer (Opus) | Opus's plan review |
| `review-codex.json` | Codex | Codex's plan review |
| `impl-result.json` | implementer | Implementation results |
| `code-review-sonnet.json` | code-reviewer (Sonnet) | Sonnet's code review |
| `code-review-opus.json` | code-reviewer (Opus) | Opus's code review |
| `code-review-codex.json` | Codex | Codex's code review |
| `.codex-session-plan` | run-codex.ts | Session marker for plan reviews |
| `.codex-session-code` | run-codex.ts | Session marker for code reviews |

---

## Review Status Values

All reviews (plan and code) support these statuses:

- **approved** - No blocking issues, proceed to next phase
- **needs_changes** - Issues found, must be fixed before approval
- **needs_clarification** - Ambiguous requirements, ask user for clarification
- **rejected** - Fundamental flaws (Codex only for plans = terminal)

---

## Scripts

All operations use these 3 TypeScript scripts (invoked via `bun`):

### 1. json-tool.ts

Cross-platform JSON utility for state management.

```
bun scripts/json-tool.ts get .task/state.json .status
bun scripts/json-tool.ts set .task/state.json status=implementing
bun scripts/json-tool.ts set .task/state.json +iterations.plan_review_sonnet
bun scripts/json-tool.ts valid .task/user-story.json
```

### 2. run-claude-code.ts

Spawns Claude CLI with agent instructions.

```
bun scripts/run-claude-code.ts \
  --agent-file agents/planner.md \
  --output .task/plan-refined.json \
  --model opus \
  --instructions "Create implementation plan"
```

**Features:**
- Automatically injects standards and state context
- Parses agent frontmatter for tool restrictions
- Platform-aware spawning (Windows/Unix)
- Validates output file exists and is valid JSON

### 3. run-codex.ts

Wraps Codex CLI for plan/code reviews.

```
bun scripts/run-codex.ts --type plan
bun scripts/run-codex.ts --type code --timeout 1800
```

**Features:**
- Type-scoped session management (plan vs code)
- Auto-retry on session expiry
- Output validation against schemas
- Platform detection and shell handling

---

## Example Flow

### Complete Pipeline Execution

```
1. User: "Add authentication to the API"

2. Gemini detects: No .task/user-story.json → Requirements phase
   Runs: bun scripts/run-claude-code.ts --agent-file agents/requirements-gatherer.md ...
   Creates: .task/user-story.json

3. Gemini detects: No .task/plan-refined.json → Planning phase
   Runs: bun scripts/run-claude-code.ts --agent-file agents/planner.md ...
   Creates: .task/plan-refined.json

4. Gemini detects: No .task/review-sonnet.json → Plan Review (Sonnet)
   Runs: bun scripts/run-claude-code.ts --agent-file agents/plan-reviewer.md --model sonnet ...
   Creates: .task/review-sonnet.json
   Status: approved

5. Gemini detects: No .task/review-opus.json → Plan Review (Opus)
   Runs: bun scripts/run-claude-code.ts --agent-file agents/plan-reviewer.md --model opus ...
   Creates: .task/review-opus.json
   Status: approved

6. Gemini detects: No .task/review-codex.json → Plan Review (Codex)
   Runs: bun scripts/run-codex.ts --type plan
   Creates: .task/review-codex.json
   Status: approved

7. Gemini detects: No .task/impl-result.json → Implementation phase
   Runs: bun scripts/run-claude-code.ts --agent-file agents/implementer.md ...
   Creates: .task/impl-result.json

8. Gemini detects: No .task/code-review-sonnet.json → Code Review (Sonnet)
   Runs: bun scripts/run-claude-code.ts --agent-file agents/code-reviewer.md --model sonnet ...
   Creates: .task/code-review-sonnet.json
   Status: approved

9. Gemini detects: No .task/code-review-opus.json → Code Review (Opus)
   Runs: bun scripts/run-claude-code.ts --agent-file agents/code-reviewer.md --model opus ...
   Creates: .task/code-review-opus.json
   Status: approved

10. Gemini detects: No .task/code-review-codex.json → Code Review (Codex)
    Runs: bun scripts/run-codex.ts --type code
    Creates: .task/code-review-codex.json
    Status: approved

11. Gemini detects: All files exist and approved → Complete phase
    Reports: "Authentication successfully added. All reviews passed."
```

---

## Iteration Tracking

To prevent infinite review loops, Gemini tracks iterations in `.task/state.json`:

```json
{
  "iterations": {
    "plan_review_sonnet": 2,
    "plan_review_opus": 1,
    "plan_review_codex": 3,
    "code_review_sonnet": 0,
    "code_review_opus": 0,
    "code_review_codex": 0
  }
}
```

**Max iterations per reviewer: 10**

If a reviewer hits 10 iterations, Gemini escalates to the user (likely indicates conflicting requirements).

---

## Stale File Handling

When a reviewer returns `needs_changes`, the planner/implementer fixes the issues, and the next review invocation **automatically overwrites** the previous review file. No manual deletion needed.

---

## Cross-Platform Support

All scripts work on:
- **Windows** - Uses `shell: true` for .cmd files, path.join() for all paths
- **macOS** - Uses `shell: false`, native process spawning
- **Linux** - Uses `shell: false`, native process spawning

No external dependencies required.

---

## Schema References

- Plan review schema: `docs/schemas/plan-review.schema.json`
- Code review schema: `docs/schemas/review-result.schema.json`

Both schemas are used by `run-codex.ts` via `--output-schema` flag to enforce structured output from Codex.
