import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec = promisify(execFile);

export function wslPath(value) {
  const normalized = value.replaceAll('\\', '/');
  const match = /^([a-zA-Z]):\/(.*)$/.exec(normalized);
  if (match) return `/mnt/${match[1].toLowerCase()}/${match[2]}`;
  if (normalized.startsWith('/')) return normalized;
  throw new Error('Windows watch route requires an absolute local path');
}

export function watchCommand({ root, home, state, env = process.env, platform = process.platform }, action) {
  if (!['start', 'status'].includes(action)) throw new Error('unsupported watch action');
  if (platform === 'win32') {
    const args = [...(env.YMIR_WSL_DISTRO ? ['-d', env.YMIR_WSL_DISTRO] : []), '--', 'env',
      `YMIR_HOME=${wslPath(home)}`, `BROKK_STATE_OVERRIDE=${wslPath(state)}`,
      `YMIR_ENGINE_PYTHON=${env.YMIR_WSL_PYTHON || '/usr/bin/python3'}`,
      'bash', `${wslPath(root)}/bin/pi/syn-watch.sh`, action];
    return { command: env.YMIR_WSL || 'wsl.exe', args };
  }
  return { command: env.YMIR_BASH || 'bash', args: [path.join(root, 'bin/pi/syn-watch.sh'), action] };
}

export async function gnaArm(context, options = {}, execute = exec) {
  const action = options.action || 'arm';
  if (!['arm', 'status', 'poll'].includes(action)) throw new Error('unknown Gna action');
  const threadId = options.threadId || context.env?.CODEX_THREAD_ID;
  if (!threadId || !/^[a-zA-Z0-9_-]+$/.test(threadId)) throw new Error('Gna requires the actual Codex threadId or inherited CODEX_THREAD_ID');
  const invoke = async (verb) => {
    const c = watchCommand(context, verb);
    try {
      const result = await execute(c.command, c.args, { env: context.env, cwd: context.root, timeout: 30000, maxBuffer: 262144, windowsHide: true });
      return result.stdout.trim();
    } catch (error) {
      throw new Error(`Gna ${verb} failed: ${String(error.stderr || error.message).slice(0, 1500)}`);
    }
  };
  if (action === 'arm') await invoke('start');
  const status = await invoke('status');
  const eventFile = path.join(context.state, '.arm.event');
  const pending = fs.existsSync(eventFile) ? fs.readFileSync(eventFile, 'utf8').trim() : '';
  const result = { threadId, action, watcher: status, pendingEvent: pending || null,
    delivery: 'native Codex thread heartbeat required; watcher status alone does not prove wake delivery' };
  // Poll is read-only: only the processing turn may acknowledge a handled event.
  // No CLI queue loop: queue --resume can exit 0 while warning that wake failed.
  return JSON.stringify(result);
}
