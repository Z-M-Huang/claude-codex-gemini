# Multi-AI Development Pipeline V2

A cross-platform development pipeline orchestrating Gemini, Claude, and Codex for autonomous planning, implementation, and review.

## Installation

### Quick Start (Recommended)

In your existing project:

```sh
bunx claude-codex-gemini init
# or with npm
npx claude-codex-gemini init
```

This creates:
- `.multi-ai-pipeline/` - Pipeline orchestration files
- Updates `GEMINI.md` - Adds pipeline reference
- Updates `.gitignore` - Adds `.task/`
- Creates `.task/` - Pipeline state directory

### Manual Installation

Clone the repo and copy the necessary files manually:

```sh
git clone https://github.com/Z-M-Huang/claude-codex-gemini.git
```

## Architecture

- **Gemini** - Orchestrator (makes decisions, delegates work)
- **Claude Code** - Agent executor (requirements, planning, implementation)
- **Codex** - Final gate reviewer (independent quality assurance)
- **Bun + TypeScript** - Cross-platform, no external dependencies, works on Windows/macOS/Linux

## Quick Start

### Prerequisites

1. **Bun** - Runtime for TypeScript scripts
   Install from https://bun.sh (see site for platform-specific instructions)

2. **Claude CLI** - AI agent executor
   ```sh
   # Install from https://claude.com/claude-code
   npm install -g @anthropic-ai/claude-cli
   claude auth
   ```

3. **Codex CLI** - Final review gate
   ```sh
   # Install from https://codex.openai.com
   npm install -g @openai/codex-cli
   codex auth
   ```

4. **Gemini CLI** - Orchestrator
   ```sh
   # Available at https://ai.google.dev/gemini-api/docs/cli
   ```

### Usage

1. **Tell Gemini what you want:**
   ```
   "Add authentication to the API"
   ```

2. **Gemini orchestrates the pipeline:**
   - Requirements gathering (Opus)
   - Planning (Opus)
   - Sequential plan reviews (Sonnet → Opus → Codex)
   - Implementation (Sonnet)
   - Sequential code reviews (Sonnet → Opus → Codex)

3. **Review results:**
   All outputs are in `.task/` directory as JSON files.

## Pipeline Phases

The pipeline auto-detects the current phase by checking which `.task/*.json` files exist:

```
Requirements → Planning → Plan Review → Implementation → Code Review → Complete
                             ↓                              ↓
                 (Sonnet → Opus → Codex)       (Sonnet → Opus → Codex)
```

### Phase Detection

| File Missing | Phase | Agent |
|--------------|-------|-------|
| `user-story.json` | Requirements | requirements-gatherer (Opus) |
| `plan-refined.json` | Planning | planner (Opus) |
| `review-sonnet.json` | Plan Review (Sonnet) | plan-reviewer (Sonnet) |
| `review-opus.json` | Plan Review (Opus) | plan-reviewer (Opus) |
| `review-codex.json` | Plan Review (Codex) | codex-reviewer |
| `impl-result.json` | Implementation | implementer (Sonnet) |
| `code-review-sonnet.json` | Code Review (Sonnet) | code-reviewer (Sonnet) |
| `code-review-opus.json` | Code Review (Opus) | code-reviewer (Opus) |
| `code-review-codex.json` | Code Review (Codex) | codex-reviewer |

## Cross-Platform Scripts

All operations use these 3 TypeScript scripts (Windows/macOS/Linux):

### 1. json-tool.ts

Cross-platform JSON operations for state management:
```sh
bun scripts/json-tool.ts get .task/state.json .status
bun scripts/json-tool.ts set .task/state.json status=implementing
bun scripts/json-tool.ts set .task/state.json +iterations.plan_review_sonnet
```

### 2. run-claude-code.ts

Spawns Claude CLI with agent context:
```sh
bun scripts/run-claude-code.ts \
  --agent-file agents/planner.md \
  --output .task/plan-refined.json \
  --model opus \
  --instructions "Create implementation plan"
```

Features:
- Automatic standards injection
- Platform-aware spawning (shell: true on Windows, false on Unix)
- Output validation

### 3. run-codex.ts

Wraps Codex CLI for reviews:
```sh
bun scripts/run-codex.ts --type plan
bun scripts/run-codex.ts --type code --timeout 1800
```

Features:
- Type-scoped session management (`.codex-session-plan`, `.codex-session-code`)
- Auto-retry on session expiry
- Schema validation

## Review Chain

Reviews happen sequentially (NOT parallel) for quality gates:

**Plan Review:** Sonnet → Opus → Codex
**Code Review:** Sonnet → Opus → Codex

Each reviewer must approve before proceeding. If `needs_changes`, Gemini fixes and re-reviews (max 10 iterations per reviewer).

### Review Statuses

- **approved** - No blocking issues, proceed
- **needs_changes** - Issues found, must fix
- **needs_clarification** - Ask user for clarification
- **rejected** - Fundamental flaws (Codex only, terminal for plans)

## Custom Agents

6 specialized agents in `agents/` directory:

| Agent | Model | Purpose |
|-------|-------|---------|
| requirements-gatherer | Opus | Gather user requirements |
| planner | Opus | Create implementation plans |
| plan-reviewer | Sonnet/Opus | Review plans |
| implementer | Sonnet | Implement plans |
| code-reviewer | Sonnet/Opus | Review code |
| codex-reviewer | Codex | Final gate reviews |

## State Management

All pipeline state lives in `.task/`:

```
.task/
├── state.json                   # Pipeline state, iteration counters
├── user-story.json             # Requirements
├── plan-refined.json           # Implementation plan
├── review-sonnet.json          # Sonnet's plan review
├── review-opus.json            # Opus's plan review
├── review-codex.json           # Codex's plan review
├── impl-result.json            # Implementation results
├── code-review-sonnet.json     # Sonnet's code review
├── code-review-opus.json       # Opus's code review
├── code-review-codex.json      # Codex's code review
├── .codex-session-plan         # Codex plan review session marker
└── .codex-session-code         # Codex code review session marker
```

## Iteration Tracking

Gemini tracks iterations in `.task/state.json` to prevent infinite loops:

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

**Max iterations: 10 per reviewer**

If a reviewer hits 10 iterations, Gemini escalates to user (likely conflicting requirements).

## Documentation

- **GEMINI.md** - Orchestrator instructions (Gemini reads this)
- **CLAUDE.md** - Agent context (Claude reads this)
- **AGENTS.md** - Final gate reviewer context (Codex reads this)
- **docs/standards.md** - Review criteria (OWASP, error handling, quality)
- **docs/workflow.md** - Detailed V2 architecture
- **agents/\*.md** - Agent behavior definitions

## Session Management

Codex sessions are automatically managed per review type:

- `.task/.codex-session-plan` - Plan review sessions
- `.task/.codex-session-code` - Code review sessions

Benefits:
- First review: Fresh Codex session
- Subsequent reviews: Automatic resume with context
- Session expired: Auto-retry without resume
- Type-scoped: Plan sessions don't affect code sessions

## Differences from V1

- **No bash scripts** - All TypeScript, cross-platform
- **No external JSON tools** - json-tool.ts handles all JSON operations natively
- **Sequential reviews** - Quality gates instead of parallel (Sonnet → Opus → Codex)
- **File-system-as-state** - Phase detection via file existence
- **Type-scoped sessions** - Separate Codex sessions for plan vs code reviews
- **Unified agent files** - All agent behavior in `agents/` directory
- **Needs clarification** - Reviewers can pause to ask user questions

## Contributing

This project follows the V2 architecture. When contributing:

1. Use path.join() for all file paths (never string concat with '/')
2. Test on Windows, macOS, and Linux
3. Follow docs/standards.md for code quality
4. Ensure scripts work with Bun runtime

## License

GPL-3.0 — see [LICENSE](./LICENSE) for details.

## Links

- **Upstream Project**: [claude-codex](https://github.com/Z-M-Huang/claude-codex) - Codex CLI wrapper plugin
- **Claude CLI**: https://claude.com/claude-code
- **Codex CLI**: https://codex.openai.com
- **Bun Runtime**: https://bun.sh
