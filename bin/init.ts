#!/usr/bin/env bun
import fs from 'fs';
import path from 'path';

const PACKAGE_ROOT = import.meta.dirname ? path.dirname(import.meta.dirname) : path.dirname(new URL(import.meta.url).pathname);
const TARGET_DIR = process.cwd();
const PIPELINE_DIR = '.multi-ai-pipeline';
const PIPELINE_MARKER = '<!-- multi-ai-pipeline section -->';

// State template (exact copy from .task.template/state.json)
const STATE_TEMPLATE = {
  pipeline_id: null,
  status: 'idle',
  iterations: {
    plan_review_sonnet: 0,
    plan_review_opus: 0,
    plan_review_codex: 0,
    code_review_sonnet: 0,
    code_review_opus: 0,
    code_review_codex: 0
  },
  started_at: null,
  updated_at: null
};

function copyDir(src: string, dest: string) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

try {
  // 1. Copy .multi-ai-pipeline/ (overwrite if exists - idempotent)
  const pipelineDir = path.join(TARGET_DIR, PIPELINE_DIR);
  copyDir(path.join(PACKAGE_ROOT, 'agents'), path.join(pipelineDir, 'agents'));
  copyDir(path.join(PACKAGE_ROOT, 'scripts'), path.join(pipelineDir, 'scripts'));
  copyDir(path.join(PACKAGE_ROOT, 'docs'), path.join(pipelineDir, 'docs'));
  fs.copyFileSync(path.join(PACKAGE_ROOT, 'ORCHESTRATOR.md'), path.join(pipelineDir, 'ORCHESTRATOR.md'));

  // 2. Handle GEMINI.md (create or append with duplicate detection)
  const geminiPath = path.join(TARGET_DIR, 'GEMINI.md');
  const geminiSection = `${PIPELINE_MARKER}\n## Multi-AI Pipeline\n\nFor pipeline orchestration, see [.multi-ai-pipeline/ORCHESTRATOR.md](.multi-ai-pipeline/ORCHESTRATOR.md).\nWhen user requests "run pipeline" or "use multi-ai", follow that file.\n`;
  if (fs.existsSync(geminiPath)) {
    const content = fs.readFileSync(geminiPath, 'utf8');
    if (!content.includes(PIPELINE_MARKER)) {
      fs.appendFileSync(geminiPath, '\n\n' + geminiSection);
    }
  } else {
    fs.writeFileSync(geminiPath, `# Project Context\n\n${geminiSection}`);
  }

  // 3. Handle .gitignore (create or append with duplicate detection)
  const gitignorePath = path.join(TARGET_DIR, '.gitignore');
  if (fs.existsSync(gitignorePath)) {
    const content = fs.readFileSync(gitignorePath, 'utf8');
    if (!content.includes('.task/') && !content.includes('.task\n')) {
      fs.appendFileSync(gitignorePath, '\n.task/\n');
    }
  } else {
    fs.writeFileSync(gitignorePath, '.task/\n');
  }

  // 4. Create .task/state.json
  const taskDir = path.join(TARGET_DIR, '.task');
  fs.mkdirSync(taskDir, { recursive: true });
  fs.writeFileSync(path.join(taskDir, 'state.json'), JSON.stringify(STATE_TEMPLATE, null, 2) + '\n');

  console.log('multi-ai-pipeline initialized successfully!');
  console.log('  .multi-ai-pipeline/ created');
  console.log('  GEMINI.md updated');
  console.log('  .gitignore updated');
  console.log('  .task/ created');
} catch (err: unknown) {
  if (err instanceof Error) {
    console.error('Error: ' + err.message);
  } else {
    console.error('Error: Unknown error occurred');
  }
  console.error('Check directory permissions and try again.');
  process.exit(1);
}
