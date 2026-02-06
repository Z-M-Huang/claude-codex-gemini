import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

const TEST_DIR = path.join(import.meta.dirname, '..', 'test-workspace');
const INIT_SCRIPT = path.join(import.meta.dirname, '..', 'bin', 'init.ts');

beforeEach(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
  fs.mkdirSync(TEST_DIR, { recursive: true });
});

afterEach(() => {
  fs.rmSync(TEST_DIR, { recursive: true, force: true });
});

describe('multi-ai-pipeline init', () => {
  test('creates .multi-ai-pipeline directory with all required subdirs', () => {
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    expect(fs.existsSync(path.join(TEST_DIR, '.multi-ai-pipeline'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_DIR, '.multi-ai-pipeline', 'agents'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_DIR, '.multi-ai-pipeline', 'scripts'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_DIR, '.multi-ai-pipeline', 'docs'))).toBe(true);
    expect(fs.existsSync(path.join(TEST_DIR, '.multi-ai-pipeline', 'ORCHESTRATOR.md'))).toBe(true);
  });

  test('creates GEMINI.md when missing', () => {
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content = fs.readFileSync(path.join(TEST_DIR, 'GEMINI.md'), 'utf8');
    expect(content).toContain('multi-ai-pipeline section');
    expect(content).toContain('.multi-ai-pipeline/ORCHESTRATOR.md');
  });

  test('appends to existing GEMINI.md without duplicating', () => {
    const existingContent = '# My Project\n\nSome content here.';
    fs.writeFileSync(path.join(TEST_DIR, 'GEMINI.md'), existingContent);
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content = fs.readFileSync(path.join(TEST_DIR, 'GEMINI.md'), 'utf8');
    expect(content).toContain('My Project');
    expect(content).toContain('multi-ai-pipeline section');
    // Run again - should not duplicate
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content2 = fs.readFileSync(path.join(TEST_DIR, 'GEMINI.md'), 'utf8');
    const matches = content2.match(/multi-ai-pipeline section/g);
    expect(matches?.length).toBe(1);
  });

  test('creates .gitignore when missing', () => {
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content = fs.readFileSync(path.join(TEST_DIR, '.gitignore'), 'utf8');
    expect(content).toContain('.task/');
  });

  test('appends .task/ to existing .gitignore without duplicating', () => {
    fs.writeFileSync(path.join(TEST_DIR, '.gitignore'), 'node_modules/\n');
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content = fs.readFileSync(path.join(TEST_DIR, '.gitignore'), 'utf8');
    expect(content).toContain('node_modules/');
    expect(content).toContain('.task/');
    // Run again - should not duplicate
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const content2 = fs.readFileSync(path.join(TEST_DIR, '.gitignore'), 'utf8');
    const matches = content2.match(/\.task\//g);
    expect(matches?.length).toBe(1);
  });

  test('creates .task/state.json', () => {
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    const stateFile = path.join(TEST_DIR, '.task', 'state.json');
    expect(fs.existsSync(stateFile)).toBe(true);
    const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    expect(state.status).toBe('idle');
    expect(state.iterations).toBeDefined();
  });

  test('is idempotent - running twice succeeds', () => {
    execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR });
    expect(() => execSync(`bun ${INIT_SCRIPT}`, { cwd: TEST_DIR })).not.toThrow();
  });
});
