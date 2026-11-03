// exec.js — execFile wrapper for kanban-tasks CLI invocations.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);

export const DEFAULTS = {
  timeoutMs: 15000,
  maxBuffer: 1024 * 1024,
};

export async function runCli(args, opts = {}, _execFile = execFileP) {
  const { cliPath, timeoutMs = DEFAULTS.timeoutMs } = opts;
  if (!cliPath) throw new Error('cliPath required in runCli opts');
  try {
    const { stdout, stderr } = await _execFile(cliPath, args, {
      timeout: timeoutMs,
      encoding: 'utf-8',
      maxBuffer: DEFAULTS.maxBuffer,
    });
    return { ok: true, stdout: (stdout || '').trim(), stderr: (stderr || '').trim() };
  } catch (err) {
    return {
      ok: false,
      stdout: (err.stdout || '').toString().trim(),
      stderr: (err.stderr || '').toString().trim(),
      code: err.code,
      signal: err.signal,
      message: err.message,
    };
  }
}
