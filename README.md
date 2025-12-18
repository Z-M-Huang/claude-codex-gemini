# Multi-AI Orchestration Pipeline

A development pipeline that orchestrates multiple AI agents to implement, review, and iterate on code changes.

- **Gemini CLI** - Orchestrator/Coordinator
- **Claude Code** - Implementation/Coder
- **Codex CLI** - Code Reviewer

## How It Works

```
User Request → Gemini (plan) → Claude (implement) → Codex (review) →
                                      ↑                    ↓
                                      └──── fix ←─── needs changes?
                                                           ↓
                                                      approved → commit
```

1. User describes a feature or task
2. Gemini creates a structured task definition
3. Claude implements following project standards
4. Codex reviews against the checklist
5. If changes needed, Claude fixes and Codex re-reviews
6. Loop until approved (max iterations configurable)
7. Commit on approval

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
   git update-index --skip-worktree .task/state.json .task/tasks.json .task/current-task.json.example
   ```

4. **Create your first task:**
   ```bash
   cp .task/current-task.json.example .task/current-task.json
   # Edit the task with your requirements
   vim .task/current-task.json
   ```

5. **Run the pipeline:**
   ```bash
   ./scripts/state-manager.sh set implementing your-task-id
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
git update-index --skip-worktree .task/state.json .task/tasks.json .task/current-task.json.example
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
├── CLAUDE.md                 # Claude coder instructions
├── AGENTS.md                 # Codex reviewer instructions
├── docs/
│   ├── standards.md          # Coding + review standards
│   ├── workflow.md           # Process documentation
│   └── schemas/
│       └── review-result.schema.json
├── scripts/
│   ├── orchestrator.sh       # Main pipeline loop
│   ├── run-claude.sh         # Claude executor
│   ├── run-codex-review.sh   # Codex executor
│   ├── state-manager.sh      # State management
│   ├── error-handler.sh      # Error logging
│   └── recover.sh            # Recovery tool
└── .task/                    # Runtime state (gitignored)
    ├── state.json            # Pipeline state
    ├── tasks.json            # Task queue
    ├── current-task.json     # Active task
    ├── impl-result.json      # Claude output
    └── review-result.json    # Codex output
```

## Usage

### Create a Task

```bash
cat > .task/current-task.json << 'EOF'
{
  "id": "feature-001",
  "type": "feature",
  "title": "Add user authentication",
  "description": "Implement JWT-based authentication with login/logout",
  "requirements": [
    "POST /api/login endpoint",
    "POST /api/logout endpoint",
    "JWT token validation middleware",
    "Unit tests for auth functions"
  ],
  "context": {
    "related_files": ["src/routes/", "src/middleware/"]
  },
  "created_at": "2025-12-18T00:00:00Z",
  "created_by": "gemini"
}
EOF
```

### Run the Pipeline

```bash
# Set state and run
./scripts/state-manager.sh set implementing feature-001
./scripts/orchestrator.sh
```

### Check Status

```bash
./scripts/orchestrator.sh status
```

### Recovery

```bash
# Interactive recovery menu
./scripts/recover.sh

# Or reset directly
./scripts/orchestrator.sh reset
```

## Configuration

### pipeline.config.json

| Setting | Description | Default |
|---------|-------------|---------|
| `autonomy.mode` | `autonomous`, `semi-autonomous`, `supervised` | `semi-autonomous` |
| `autonomy.reviewLoopLimit` | Max review iterations | `5` |
| `errorHandling.autoResolveAttempts` | Retries before pausing | `3` |
| `models.coder.model` | Claude model | `claude-opus-4.5` |
| `models.reviewer.model` | Codex model | `gpt-5.2` |
| `debate.enabled` | Allow Gemini to challenge reviews | `true` |
| `debate.maxRounds` | Max debate rounds | `2` |

### Autonomy Modes

| Mode | Planning | Implementation | Review | Commit |
|------|----------|----------------|--------|--------|
| `autonomous` | Auto | Auto | Auto | Auto |
| `semi-autonomous` | Auto | Auto | Auto | **Manual** |
| `supervised` | Manual | Manual | Manual | Manual |

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

MIT
