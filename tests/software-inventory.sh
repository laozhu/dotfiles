#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
node --input-type=module - "$repo_dir" <<'JS'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = process.argv[2];
const script = path.join(root, 'scripts/software-inventory.mjs');
assert.ok(fs.existsSync(script), 'inventory script must exist');
const { inspectSoftware } = await import(pathToFileURL(script));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-inventory-'));
try {
  const bin = path.join(temp, 'bin'); const apps = path.join(temp, 'Applications');
  fs.mkdirSync(bin); fs.mkdirSync(apps);
  const options = { path: bin, home: temp, appDirs: [apps], brewPrefix: path.join(temp, 'brew') };
  const entry = { name: 'App', manager: 'Homebrew Cask', package: 'app', apps: ['Example.app'] };
  fs.mkdirSync(path.join(options.brewPrefix, 'Caskroom', 'app'), { recursive: true });
  assert.equal(inspectSoftware(entry, options).status, '未安装', 'receipt alone is insufficient');
  fs.mkdirSync(path.join(apps, 'Example.app'));
  assert.equal(inspectSoftware(entry, options).status, '已安装');
  const cli = { name: 'Tools', commands: ['first', 'second'] };
  assert.equal(inspectSoftware(cli, options).status, '未安装');
  const executable = name => { fs.writeFileSync(path.join(bin, name), '#!/bin/sh\nexit 99\n'); fs.chmodSync(path.join(bin, name), 0o755); };
  executable('first');
  assert.equal(inspectSoftware(cli, options).status, '部分安装');
  executable('second');
  assert.equal(inspectSoftware(cli, options).status, '已安装');
  assert.equal(inspectSoftware({ manager: 'Gradle', note: 'project' }, options).status, '项目管理');
  assert.equal(inspectSoftware({ id: 'gnumake', manager: 'Nix', commands: ['make'] }, { ...options, path: '/usr/bin' }).status, '未安装', 'Apple make is not the declared Nix tool');
  const bundled = path.join(apps, 'Example.app', 'cli'); fs.writeFileSync(bundled, '#!/bin/sh\nexit 99\n'); fs.chmodSync(bundled, 0o755);
  assert.equal(inspectSoftware({ commands: [bundled] }, options).status, '已安装');
  assert.equal(inspectSoftware({ id: 'openjdk', commands: ['java'] }, { ...options, path: '/usr/bin' }).status, '未安装');
  assert.equal(inspectSoftware({ id: 'python', commands: ['python3'] }, { ...options, path: '/usr/bin' }).status, '未安装');
  const run = args => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  const result = run(['--profile', 'home', '--json']); assert.equal(result.status, 0, result.stderr);
  const rows = JSON.parse(result.stdout);
  assert.ok(rows.some(r => r.id === 'steam')); assert.ok(rows.some(r => r.id === 'openjdk'));
  assert.ok(!rows.some(r => r.group === 'work'));
  assert.ok(!rows.some(r => ['git', 'bash', 'zsh', 'gnumake', 'gcc', 'curl', 'unzip'].includes(r.id)), 'base tools must be hidden from the inventory');
  assert.ok(rows.some(r => r.id === 'python'), 'explicit Homebrew replacements remain visible');
  assert.ok(!rows.some(r => /magnet|rabbitpro|dart|tencent-video/i.test(r.id)));
  assert.equal(rows.find(r => r.id === 'tencent-meeting').group, 'home');
  const work = JSON.parse(run(['--profile', 'work', '--json']).stdout);
  assert.ok(work.some(r => r.id === 'nordpass/tap/np')); assert.ok(!work.some(r => r.group === 'home'));
  assert.equal(run(['--profile', 'bad']).status, 2);
  assert.equal(run(['--group', 'shared']).stdout.includes('| 名称 |'), true);
  assert.equal(run(['--bad']).status, 2);
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
JS
