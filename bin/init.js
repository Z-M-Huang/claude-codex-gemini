#!/usr/bin/env node
import { spawn } from 'child_process';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const initScript = join(__dirname, 'init.ts');

const proc = spawn('bun', [initScript], {
  stdio: 'inherit',
  shell: process.platform === 'win32'
});

proc.on('error', (err) => {
  if (err.code === 'ENOENT') {
    console.error('Error: Bun is required but not installed.');
    console.error('Install Bun from: https://bun.sh');
    process.exit(1);
  }
  throw err;
});

proc.on('exit', (code) => {
  process.exit(code || 0);
});
