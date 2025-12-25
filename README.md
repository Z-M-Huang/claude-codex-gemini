# Multi-AI Orchestration Pipeline

A development pipeline that orchestrates multiple AI agents to plan, implement, review, and iterate on code changes.

- **Gemini CLI** - Orchestrator/Coordinator (does NOT write code)
- **Claude Code** - Plan Refiner + Implementation Coder
- **Codex CLI** - Plan Reviewer + Code Reviewer

> **Just want to run CC + Codex?** Check out [claude-codex](https://github.com/Z-M-Huang/claude-codex).

## How It Works

### Phase 1: Planning

```
User Request → Gemini (draft plan) → Claude (refine plan) → Codex (review plan)
                                           ↑                       ↓
                                           └──── needs changes ────┘
                                                                   ↓
                                                              approved
                                                                   ↓
                                                          plan-to-task.sh
```

### Phase 2: Implementation

```
Task → Claude (implement) → Internal Reviews (2 parallel) → Codex (review code) → commit
              ↑                      |                              ↓
              └──────────────────────+────── fix ←─── needs changes ┘
```

### Internal Reviews (Cost Optimization)

Before calling Codex, 2 unified Claude subagents review in parallel:
- **Sonnet**: `reviewer-sonnet` - Fast, practical (code + security + tests)
- **Opus**: `reviewer-opus` - Deep, thorough (architecture + vulnerabilities + test quality)

This catches ~90% of issues before external API calls, significantly reducing costs.

1. User describes a feature or task
2. Gemini creates an initial plan (`plan.json`)
3. Claude refines the plan with technical details (`plan-refined.json`)
4. Codex reviews the plan for completeness and feasibility
5. If plan needs changes, Claude refines again (loop until approved)
6. Once plan approved, Gemini converts it to a task
7. Claude implements following project standards
8. Codex reviews code against the checklist
9. If code needs changes, Claude fixes and Codex re-reviews
10. Loop until approved (max iterations configurable)
11. Commit on approval

## Prerequisites

- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed and authenticated
- [Claude Code](https://claude.ai/code) installed and authenticated
- [Codex CLI](https://github.com/openai/codex) installed and authenticated
- `jq` for JSON processing

## Quick Start

### Option A: Use as Template (New Projects)

1. **Clone/copy this repository:**

   ```bash
   git clone https://github.com/Z-M-Huang/claude-codex-gemini.git my-project
   cd my-project
   rm -rf .git
   git init
   ```

2. **Customize for your project:**

   ```bash
   # Edit standards to match your project
   vim docs/standards.md

   # Update workflow documentation
   vim docs/workflow.md

   # Configure models and autonomy level
   vim pipeline.config.json
   ```

3. **Initialize the pipeline:**

   ```bash
   ./scripts/state-manager.sh init

   # Tell git to ignore local changes to state files
   git update-index --skip-worktree .task/state.json .task/tasks.json
   ```

4. **Create your first plan:**

   ```bash
   # Create a plan file (or let Gemini create it)
   cat > .task/plan.json << 'EOF'
   {
     "id": "plan-001",
     "title": "Your feature title",
     "description": "What you want to build",
     "requirements": ["requirement 1", "requirement 2"],
     "created_at": "2025-12-18T00:00:00Z",
     "created_by": "gemini"
   }
   EOF
   ```

5. **Run the planning phase:**

   ```bash
   ./scripts/state-manager.sh set plan_refining plan-001
   ./scripts/orchestrator.sh
   # Wait for plan approval, then:
   ./scripts/plan-to-task.sh
   ```

6. **Run the implementation phase:**
   ```bash
   ./scripts/orchestrator.sh
   ```

### Option B: Adopt for Existing Projects

1. **Copy the pipeline files to your project:**

   ```bash
   # From the claude-codex-gemini directory
   cp -r scripts/ /path/to/your/project/
   cp -r docs/ /path/to/your/project/
   cp pipeline.config.json /path/to/your/project/
   cp GEMINI.md CLAUDE.md AGENTS.md /path/to/your/project/
   mkdir -p /path/to/your/project/.task
   ```

2. **Add to .gitignore:**

   ```bash
   echo ".task/" >> /path/to/your/project/.gitignore
   ```

3. **Customize docs/standards.md for your project:**

   Update the coding standards to match your existing conventions:

   - Naming conventions (files, classes, functions)
   - Code style rules
   - Testing requirements
   - Security requirements

4. **Update the agent config files:**

   Edit `GEMINI.md`, `CLAUDE.md`, and `AGENTS.md` to reference your project-specific context:

   ```markdown
   # In GEMINI.md, add project-specific imports

   @docs/your-project-docs.md
   @src/README.md
   ```

5. **Configure the pipeline:**

   Edit `pipeline.config.json`:

   ```json
   {
     "autonomy": {
       "mode": "semi-autonomous",
       "reviewLoopLimit": 5
     },
     "models": {
       "coder": { "model": "claude-opus-4.5" },
       "reviewer": { "model": "gpt-5.2" }
     }
   }
   ```

6. **Initialize and run:**
   ```bash
   cd /path/to/your/project
   ./scripts/state-manager.sh init
   ```

## After Cloning

The `.task/` folder contains initial state files that are tracked in git but should not have local changes committed. After cloning, run:

```bash
git update-index --skip-worktree .task/state.json .task/tasks.json
```

This tells git to ignore your local modifications to these files. The `.gitignore` already excludes new files in `.task/` (like `impl-result.json`, `review-result.json`, error logs).

**To check skip-worktree status:**

```bash
git ls-files -v .task/ | grep '^S'  # S = skip-worktree is set
```

**To undo (if you need to commit changes):**

```bash
git update-index --no-skip-worktree .task/state.json
```

## Project Structure

```
your-project/
├── pipeline.config.json      # Pipeline configuration
├── GEMINI.md                 # Gemini orchestrator instructions
├── CLAUDE.md                 # Claude coder/refiner instructions
├── AGENTS.md                 # Codex reviewer instructions
├── .claude/
│   └── agents/               # Internal review subagents
│       ├── reviewer-sonnet.md    # Fast unified review (code + security + tests)
│       └── reviewer-opus.md      # Deep unified review (architecture + vulnerabilities)
├── docs/
│   ├── standards.md          # Coding + review standards
│   ├── workflow.md           # Process documentation
│   └── schemas/
│       ├── review-result.schema.json   # Code review output schema
│       └── plan-review.schema.json     # Plan review output schema
├── scripts/
│   ├── orchestrator.sh       # Main pipeline loop
│   ├── run-claude.sh         # Claude implementation executor
│   ├── run-claude-plan.sh    # Claude plan refinement executor
│   ├── run-codex-review.sh   # Codex code review executor
│   ├── run-codex-plan-review.sh  # Codex plan review executor
│   ├── run-internal-reviews.sh   # Parallel internal reviews (2 unified agents)
│   ├── plan-to-task.sh       # Convert approved plan to task
│   ├── state-manager.sh      # State management
│   ├── error-handler.sh      # Error logging
│   └── recover.sh            # Recovery tool
└── .task/                    # Runtime state (gitignored)
    ├── state.json            # Pipeline state
    ├── tasks.json            # Task queue
    ├── plan.json             # Initial plan (Gemini creates)
    ├── plan-refined.json     # Refined plan (Claude creates)
    ├── plan-review.json      # Plan review (Codex creates)
    ├── current-task.json     # Active task
    ├── impl-result.json      # Implementation output
    ├── review-result.json    # Code review output
    └── internal-review-*.json  # Internal review outputs
```

## Usage

### Phase 1: Create and Approve a Plan

**Step 1: Create initial plan (Gemini does this)**

```bash
cat > .task/plan.json << 'EOF'
{
  "id": "plan-001",
  "title": "Add user authentication",
  "description": "Implement JWT-based authentication with login/logout",
  "requirements": [
    "POST /api/login endpoint",
    "POST /api/logout endpoint",
    "JWT token validation middleware",
    "Unit tests for auth functions"
  ],
  "created_at": "2025-12-18T00:00:00Z",
  "created_by": "gemini"
}
EOF
```

**Step 2: Refine and review the plan**

```bash
# Set state and run plan refinement (Claude)
./scripts/state-manager.sh set plan_refining plan-001
./scripts/orchestrator.sh

# This will automatically:
# 1. Claude refines plan -> plan-refined.json
# 2. Codex reviews plan -> plan-review.json
# 3. Loop until approved or limit reached
```

**Step 3: Convert approved plan to task**

```bash
# Check if plan was approved
cat .task/plan-review.json | jq '.status'

# If approved, convert to task
./scripts/plan-to-task.sh
```

### Phase 2: Implementation

```bash
# Run the implementation pipeline
./scripts/orchestrator.sh

# This will automatically:
# 1. Claude implements -> impl-result.json
# 2. Codex reviews code -> review-result.json
# 3. Loop until approved or limit reached
```

### Check Status

```bash
./scripts/orchestrator.sh status
```

### Dry Run (Validation)

Validate your pipeline setup without running it:

```bash
./scripts/orchestrator.sh dry-run
```

This checks:

- `.task/` directory and state file validity
- `pipeline.config.json` validity
- Required scripts present and executable
- Required docs (`standards.md`, `workflow.md`)
- `.task` in `.gitignore`
- CLI tools (`jq` required, `claude`/`codex`/`gemini` optional)

### Recovery

```bash
# Interactive recovery menu
./scripts/recover.sh

# Or reset directly
./scripts/orchestrator.sh reset
```

### Handling User Input Requests

If Claude needs clarification, the pipeline pauses with `needs_user_input` state:

```bash
# Check what questions need answering
cat .task/state.json | jq '.previous_state'  # See which phase
cat .task/plan-refined.json | jq '.questions'  # Plan phase questions
cat .task/impl-result.json | jq '.questions'   # Implementation questions

# After providing answers, resume:
./scripts/state-manager.sh set plan_refining plan-001  # or implementing task-001
./scripts/orchestrator.sh
```

## Configuration

### pipeline.config.json

| Setting                             | Description                                   | Default           |
| ----------------------------------- | --------------------------------------------- | ----------------- |
| `autonomy.mode`                     | `autonomous`, `semi-autonomous`, `supervised` | `semi-autonomous` |
| `autonomy.reviewLoopLimit`          | Max review iterations (legacy, fallback)      | `5`               |
| `autonomy.planReviewLoopLimit`      | Max plan review iterations                    | `3`               |
| `autonomy.codeReviewLoopLimit`      | Max code review iterations                    | `5`               |
| `autonomy.autoCommit`               | Auto-commit on approval                       | `false`           |
| `errorHandling.autoResolveAttempts` | Retries before pausing                        | `3`               |
| `models.coder.model`                | Claude model                                  | `claude-opus-4.5` |
| `models.reviewer.model`             | Codex model                                   | `gpt-5.2`         |
| `debate.enabled`                    | Allow Gemini to challenge reviews             | `true`            |
| `debate.maxRounds`                  | Max debate rounds                             | `2`               |

> **Note (MVP):** Branch strategy settings are defined in config but not yet implemented. Auto-commit is controlled by `autonomy.autoCommit`.

### Local Config Overrides

Create `pipeline.config.local.json` to override settings without modifying the tracked config:

```json
{
  "autonomy": {
    "planReviewLoopLimit": 5,
    "codeReviewLoopLimit": 10
  }
}
```

This file is gitignored and will be merged on top of `pipeline.config.json`.

### Autonomy Modes

| Mode              | Planning | Implementation | Review | Commit     |
| ----------------- | -------- | -------------- | ------ | ---------- |
| `autonomous`      | Auto     | Auto           | Auto   | Auto       |
| `semi-autonomous` | Auto     | Auto           | Auto   | **Manual** |
| `supervised`      | Manual   | Manual         | Manual | Manual     |

## Customization

### Adding Project-Specific Standards

Edit `docs/standards.md`:

```markdown
# Project Standards

## Coding Standards

- Use TypeScript strict mode
- All functions must have JSDoc comments
- No console.log in production code

## Review Checklist

### Must Check (severity: error)

- No hardcoded secrets
- All API endpoints have auth middleware
- Database queries use parameterized statements
```

### Modifying Review Schema

Edit `docs/schemas/review-result.schema.json` to add custom checklist items:

```json
{
  "checklist": {
    "properties": {
      "security": { "enum": ["PASS", "WARN", "FAIL"] },
      "performance": { "enum": ["PASS", "WARN", "FAIL"] },
      "your_custom_check": { "enum": ["PASS", "WARN", "FAIL"] }
    }
  }
}
```

## Troubleshooting

### Pipeline stuck in error state

```bash
./scripts/recover.sh
# Select option 1 to reset to idle
```

### Claude not creating output file

Check that Claude has the right permissions:

```bash
# Verify CLAUDE.md instructions mention the output file
grep "impl-result.json" CLAUDE.md
```

### Codex review failing

Verify the schema is valid:

```bash
jq empty docs/schemas/review-result.schema.json
```

### View error logs

```bash
ls -la .task/errors/
cat .task/errors/error-*.json | jq
```

## License

GPL-3.0 license
