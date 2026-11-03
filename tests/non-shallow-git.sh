#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
node --input-type=module - "$repo_dir" <<'JS'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec = promisify(execFile);
const repo = process.argv[2];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-dumb-git-'));
let server;
try {
  const source = path.join(temp, 'source');
  const remote = path.join(temp, 'remote.git');
  await exec('git', ['init', '-b', 'main', source]);
  const content = `pinned source ${path.basename(temp)}\n`;
  fs.writeFileSync(path.join(source, 'README'), content);
  await exec('git', ['-C', source, 'add', 'README']);
  await exec('git', ['-C', source, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgSign=false', 'commit', '-m', 'Fixture']);
  const { stdout: revision } = await exec('git', ['-C', source, 'rev-parse', 'HEAD']);
  await exec('git', ['clone', '--bare', source, remote]);
  await exec('git', ['-C', remote, 'update-server-info']);
  // Serve static Git files, like NordPass: no smart HTTP or shallow capabilities.
  server = http.createServer((req, res) => {
    const file = path.join(temp, new URL(req.url, 'http://localhost').pathname);
    try {
      const data = fs.readFileSync(file);
      res.writeHead(200, { 'Content-Type': 'application/octet-stream' });
      res.end(data);
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const locked = {
    type: 'git', url: `http://127.0.0.1:${server.address().port}/remote.git`,
    ref: 'refs/heads/main', rev: revision.trim(), revCount: 1, shallow: false,
  };
  const args = `builtins.fromJSON ${JSON.stringify(JSON.stringify(locked))}`;
  const expr = `toString (import ${repo}/lib/non-shallow-git.nix (${args}))`;
  const { stdout } = await exec('nix', ['eval', '--raw', '--impure', '--expr', expr], {
    env: { ...process.env, XDG_CACHE_HOME: path.join(temp, 'empty-cache') }, timeout: 30000,
  });
  assert.equal(fs.readFileSync(path.join(stdout.trim(), 'README'), 'utf8'), content);
} finally {
  if (server) await new Promise(resolve => server.close(resolve));
  fs.rmSync(temp, { recursive: true, force: true });
}
JS
