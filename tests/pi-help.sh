#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pi_package="$(nix build --no-link --print-out-paths "$repo_dir#darwinConfigurations.mac.pkgs.pi")"
node --input-type=module - "$pi_package/bin/pi" <<'NODE'
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const binary = process.argv[2];
const root = mkdtempSync(join(tmpdir(), 'pi-help-test-'));
try {
  const agent = join(root, 'agent');
  const bin = join(root, 'bin');
  const log = join(root, 'npm.log');
  mkdirSync(agent);
  mkdirSync(bin);
  writeFileSync(join(agent, 'settings.json'), JSON.stringify({
    packages: ['npm:pi-web-access@0.29.0'],
  }));
  // A missing extension must not trigger installation just to display help.
  writeFileSync(join(bin, 'npm'), '#!/bin/sh\nprintf "%s %s\\n" "$PI_OFFLINE" "$*" >> "$PI_HELP_NPM_LOG"\nif [ "$1" = root ]; then printf "%s/global\\n" "$PI_CODING_AGENT_DIR"; exit 0; fi\nexit 71\n', { mode: 0o755 });
  for (const flag of ['--help', '-h']) {
    const result = spawnSync(binary, [flag], {
      cwd: root,
      env: { ...process.env, PI_OFFLINE: '0', PI_CODING_AGENT_DIR: agent,
        PI_HELP_NPM_LOG: log, PATH: `${bin}:${process.env.PATH}` },
      timeout: 5000, encoding: 'utf8',
    });
    assert.equal(result.error, undefined, `${flag} timed out`);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Usage:/);
    const commands = existsSync(log) ? readFileSync(log, 'utf8') : '';
    assert.doesNotMatch(commands, /\binstall\b/, `${flag} attempted to install an extension`);
  }
  writeFileSync(log, '');
  const install = spawnSync(binary, ['install', 'npm:pi-web-access@0.29.0'], {
    cwd: root,
    env: { ...process.env, PI_OFFLINE: '0', PI_CODING_AGENT_DIR: agent,
      PI_HELP_NPM_LOG: log, PATH: `${bin}:${process.env.PATH}` },
    timeout: 5000, encoding: 'utf8',
  });
  assert.equal(install.error, undefined);
  assert.match(readFileSync(log, 'utf8'), /^0 install /m,
    'Explicit package installation must retain normal network behavior');
} finally {
  rmSync(root, { recursive: true, force: true });
}
NODE
