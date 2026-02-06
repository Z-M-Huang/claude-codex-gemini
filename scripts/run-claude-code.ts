#!/usr/bin/env bun
/**
 * Claude Code CLI Executor Script
 *
 * Spawns Claude CLI with agent files, standards context, and task state.
 * Handles cross-platform execution, timeout, and output validation.
 *
 * Usage:
 *   bun run-claude-code.ts --instructions "Task description"
 *   bun run-claude-code.ts --agent-file agents/planner.md --output .task/plan-refined.json
 *   bun run-claude-code.ts --agent-file agents/implementer.md --model sonnet --timeout 1200
 *
 * Exit codes:
 *   0 - Success
 *   1 - Output validation error
 *   2 - Claude CLI not installed
 *   3 - Timeout
 */

import { spawn, execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ================== CONFIGURATION ==================

const SCRIPT_DIR = import.meta.dirname;
const PACKAGE_ROOT = path.dirname(SCRIPT_DIR);
const TASK_DIR = '.task';
const DEFAULT_MODEL = 'sonnet';
const DEFAULT_TIMEOUT = 600; // seconds
const DEFAULT_TOOLS = 'Read,Write,Edit,Glob,Grep,Bash';

// ================== ARGUMENT PARSING ==================

interface Args {
  instructions: string | null;
  output: string | null;
  agentFile: string | null;
  model: string;
  timeout: number;
  allowedTools: string;
}

function parseArgs(): Args {
  const args = process.argv.slice(2);
  const result: Args = {
    instructions: null,
    output: null,
    agentFile: null,
    model: DEFAULT_MODEL,
    timeout: DEFAULT_TIMEOUT,
    allowedTools: DEFAULT_TOOLS
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--instructions' && args[i + 1]) {
      result.instructions = args[i + 1];
      i++;
    } else if (args[i] === '--output' && args[i + 1]) {
      result.output = args[i + 1];
      i++;
    } else if (args[i] === '--agent-file' && args[i + 1]) {
      result.agentFile = args[i + 1];
      i++;
    } else if (args[i] === '--model' && args[i + 1]) {
      result.model = args[i + 1];
      i++;
    } else if (args[i] === '--timeout' && args[i + 1]) {
      const parsed = parseInt(args[i + 1], 10);
      result.timeout = isNaN(parsed) ? DEFAULT_TIMEOUT : parsed;
      i++;
    } else if (args[i] === '--allowed-tools' && args[i + 1]) {
      result.allowedTools = args[i + 1];
      i++;
    }
  }

  return result;
}

// ================== FILE HELPERS ==================

function fileExists(filePath: string): boolean {
  try {
    return fs.existsSync(filePath);
  } catch {
    return false;
  }
}

function readFile(filePath: string): string | null {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

function isValidJson(content: string): boolean {
  try {
    JSON.parse(content);
    return true;
  } catch {
    return false;
  }
}

// ================== SHELL ESCAPING ==================

function escapeWinArg(arg: string): string {
  // If arg contains spaces or special chars, wrap in double quotes
  // Escape any existing double quotes
  if (/[\s"&|<>^]/.test(arg)) {
    return `"${arg.replace(/"/g, '\\"')}"`;
  }
  return arg;
}

// ================== FRONTMATTER PARSING ==================

function parseFrontmatter(content: string): { tools?: string } {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};

  const frontmatter = match[1];
  const toolsMatch = frontmatter.match(/^tools:\s*(.+)$/m);
  if (!toolsMatch) return {};

  return { tools: toolsMatch[1].trim() };
}

// ================== CONTEXT BUILDING ==================

function buildInstructions(args: Args): string {
  let instructions = '';

  // 1. Prepend agent file content if provided
  if (args.agentFile && fileExists(args.agentFile)) {
    const agentContent = readFile(args.agentFile);
    if (agentContent) {
      instructions += agentContent + '\n\n---\n\n';

      // Parse frontmatter to extract tools for default allowed-tools (if not explicitly provided)
      const frontmatter = parseFrontmatter(agentContent);
      if (frontmatter.tools && args.allowedTools === DEFAULT_TOOLS) {
        // User didn't explicitly specify --allowed-tools, so use agent's tools from frontmatter
        args.allowedTools = frontmatter.tools;
      }
    }
  }

  // 2. Append standards context
  const standardsPath = path.join(PACKAGE_ROOT, 'docs', 'standards.md');
  if (fileExists(standardsPath)) {
    const standards = readFile(standardsPath);
    if (standards) {
      instructions += '# Project Standards\n\n';
      instructions += standards + '\n\n---\n\n';
    }
  }

  // 3. Append task state context
  instructions += '# Current Task State\n\n';
  if (fileExists(TASK_DIR)) {
    const taskFiles = ['state.json', 'user-story.json', 'plan-refined.json', 'impl-result.json'];
    for (const file of taskFiles) {
      const filePath = path.join(TASK_DIR, file);
      if (fileExists(filePath)) {
        instructions += `- ${file} exists\n`;
      }
    }
  } else {
    instructions += '- .task directory not found\n';
  }
  instructions += '\n---\n\n';

  // 4. Inject output path if specified
  if (args.output) {
    instructions += '# Output Requirement\n\n';
    instructions += `You MUST write your output to: ${args.output}\n`;
    instructions += 'The file must be valid JSON.\n\n---\n\n';
  }

  // 5. Append user instructions
  if (args.instructions) {
    instructions += '# Task Instructions\n\n';
    instructions += args.instructions + '\n';
  }

  return instructions;
}

// ================== CLAUDE CLI ==================

function isClaudeInstalled(): boolean {
  try {
    execSync('claude --version', { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

interface RunResult {
  success: boolean;
  error?: string;
  duration_ms: number;
}

function runClaude(instructions: string, args: Args): Promise<RunResult> {
  return new Promise((resolve) => {
    const startTime = Date.now();
    let timedOut = false;

    const isWindows = os.platform() === 'win32';
    const timeoutMs = args.timeout * 1000;

    // Build Claude command args
    const cmdArgs = [
      '--print',
      '--model', args.model,
      '--allowedTools', args.allowedTools
    ];

    let proc;

    if (isWindows) {
      // On Windows, claude.cmd requires shell: true
      // Escape all arguments to prevent shell injection
      const escapedArgs = cmdArgs.map(escapeWinArg);
      const command = `claude ${escapedArgs.join(' ')}`;
      proc = spawn(command, [], {
        stdio: ['pipe', 'inherit', 'inherit'],
        shell: true
      });
    } else {
      // On Unix, shell: false is safer
      proc = spawn('claude', cmdArgs, {
        stdio: ['pipe', 'inherit', 'inherit'],
        shell: false
      });
    }

    // Pass instructions via stdin to avoid shell injection risks
    proc.stdin.write(instructions);
    proc.stdin.end();

    // Set timeout
    const timeoutId = setTimeout(() => {
      timedOut = true;
      proc.kill('SIGKILL');
    }, timeoutMs);

    proc.on('close', (code) => {
      clearTimeout(timeoutId);
      const duration = Date.now() - startTime;

      if (timedOut) {
        resolve({ success: false, error: 'timeout', duration_ms: duration });
      } else if (code === 0) {
        resolve({ success: true, duration_ms: duration });
      } else {
        resolve({ success: false, error: `claude exited with code ${code}`, duration_ms: duration });
      }
    });

    proc.on('error', (err: NodeJS.ErrnoException) => {
      clearTimeout(timeoutId);
      const duration = Date.now() - startTime;

      if (err.code === 'ENOENT') {
        resolve({ success: false, error: 'not_installed', duration_ms: duration });
      } else {
        resolve({ success: false, error: err.message, duration_ms: duration });
      }
    });
  });
}

// ================== OUTPUT VALIDATION ==================

function validateOutput(outputPath: string): { valid: boolean; error?: string } {
  if (!fileExists(outputPath)) {
    return { valid: false, error: 'Output file not created' };
  }

  const content = readFile(outputPath);
  if (!content) {
    return { valid: false, error: 'Output file is empty or unreadable' };
  }

  if (!isValidJson(content)) {
    return { valid: false, error: 'Output file is not valid JSON' };
  }

  return { valid: true };
}

// ================== MAIN ==================

async function main(): Promise<void> {
  const args = parseArgs();

  // Validate required args
  if (!args.instructions) {
    console.log(JSON.stringify({
      event: 'error',
      error: 'Missing required --instructions argument'
    }));
    process.exit(1);
  }

  // Check Claude CLI
  if (!isClaudeInstalled()) {
    console.log(JSON.stringify({
      event: 'error',
      error: 'Claude CLI not installed. Install from: https://claude.com/claude-code',
      phase: 'cli_check'
    }));
    process.exit(2);
  }

  // Build full instructions with context
  const fullInstructions = buildInstructions(args);

  console.log(JSON.stringify({
    event: 'start',
    model: args.model,
    allowedTools: args.allowedTools,
    timeout_s: args.timeout,
    has_agent_file: !!args.agentFile,
    has_output: !!args.output,
    timestamp: new Date().toISOString()
  }));

  // Run Claude
  console.log(JSON.stringify({
    event: 'invoking_claude',
    model: args.model
  }));

  const result = await runClaude(fullInstructions, args);

  if (!result.success) {
    let exitCode = 1;
    if (result.error === 'not_installed') {
      exitCode = 2;
    } else if (result.error === 'timeout') {
      exitCode = 3;
    }

    console.log(JSON.stringify({
      event: 'error',
      phase: 'execution',
      error: result.error,
      duration_ms: result.duration_ms
    }));
    process.exit(exitCode);
  }

  // Validate output if --output was specified
  let outputValid = true;
  if (args.output) {
    const validation = validateOutput(args.output);
    outputValid = validation.valid;

    if (!validation.valid) {
      console.log(JSON.stringify({
        event: 'error',
        phase: 'output_validation',
        error: validation.error,
        output_file: args.output,
        duration_ms: result.duration_ms
      }));
      process.exit(1);
    }
  }

  console.log(JSON.stringify({
    event: 'complete',
    status: 'success',
    output_file: args.output || null,
    output_valid: outputValid,
    duration_ms: result.duration_ms
  }));

  process.exit(0);
}

main().catch((err) => {
  console.log(JSON.stringify({
    event: 'error',
    phase: 'unexpected_error',
    error: err.message
  }));
  process.exit(1);
});
