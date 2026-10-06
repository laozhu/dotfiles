#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
primary_user="$(nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.system.primaryUser")"

managed_files="$({
  nix eval --json \
    "$repo_dir#darwinConfigurations.mac.config.home-manager.users.$primary_user.home.file" \
    --apply 'files: builtins.attrNames files'
} | jq -r '.[]')"

for managed_path in \
  .pi/agent/themes/rose-pine-moon.json \
  .pi/agent/extensions/terminal-status-title.js \
  .pi/agent/settings.json \
  .claude/CLAUDE.md \
  .claude/AGENTS.md \
  .codex/AGENTS.md \
  .config/opencode/AGENTS.md; do
  if ! grep -Fxq "$managed_path" <<<"$managed_files"; then
    printf 'Home Manager does not manage %s\n' "$managed_path" >&2
    exit 1
  fi
done

managed_source() {
  nix eval --raw \
    "$repo_dir#darwinConfigurations.mac.config.home-manager.users.$primary_user.home.file.\"$1\".source"
}

claude_wrapper_source="$(managed_source .claude/CLAUDE.md)"
claude_agents_source="$(managed_source .claude/AGENTS.md)"

if [[ "$claude_wrapper_source" == "$claude_agents_source" ]]; then
  printf '%s\n' 'Claude wrapper must not point directly at shared AGENTS.md.' >&2
  exit 1
fi

diff -u \
  <(printf '%s\n' \
    '<!-- Claude Code compatibility bridge. Shared instructions are maintained in AGENTS.md. -->' \
    '' \
    '@AGENTS.md') \
  "$repo_dir/home/CLAUDE.md"

if cmp -s "$repo_dir/home/CLAUDE.md" "$repo_dir/home/AGENTS.md"; then
  printf '%s\n' 'Claude wrapper must remain separate from shared AGENTS.md.' >&2
  exit 1
fi

for local_path in \
  .pi/agent \
  .pi/agent/auth.json \
  .pi/agent/themes \
  .pi/agent/extensions \
  .pi/agent/models.json; do
  if grep -Fxq "$local_path" <<<"$managed_files"; then
    printf 'Home Manager must leave %s local\n' "$local_path" >&2
    exit 1
  fi
done

jq -e 'type == "object" and (has("packages") | not)' \
  "$repo_dir/home/.pi/agent/settings.json" >/dev/null
jq -e '.name == "rose-pine-moon" and (.colors | type == "object")' \
  "$repo_dir/home/.pi/agent/themes/rose-pine-moon.json" >/dev/null

git -C "$repo_dir" check-ignore --no-index -q home/.pi/agent/auth.json
git -C "$repo_dir" check-ignore --no-index -q home/.pi/agent/settings.json.backup

extension="$repo_dir/home/.pi/agent/extensions/terminal-status-title.js"
node --input-type=module - "$extension" <<'NODE'
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const extensionPath = process.argv[2];
const source = await readFile(extensionPath, "utf8");
const extensionModule = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
);

const handlers = new Map();
const pi = {
  getSessionName: () => "",
  on: (event, handler) => handlers.set(event, handler),
};
const titles = [];
const context = {
  cwd: "/tmp/workspace",
  hasUI: true,
  ui: { setTitle: (title) => titles.push(title) },
};

extensionModule.default(pi);
assert.deepEqual(
  [...handlers.keys()],
  ["session_start", "agent_start", "agent_settled", "session_shutdown"],
);

process.env.ORCA_PANE_KEY = "test-pane";
const orcaHandlers = new Map();
extensionModule.default({
  getSessionName: () => "",
  on: (event, handler) => orcaHandlers.set(event, handler),
});
assert.deepEqual([...orcaHandlers.keys()], []);
delete process.env.ORCA_PANE_KEY;

await handlers.get("session_start")({}, context);
await new Promise((resolve) => setTimeout(resolve, 0));
assert.equal(titles.at(-1), "○ | π | workspace");

await handlers.get("agent_start")({}, context);
assert.equal(titles.at(-1), "⠋ | π | workspace");

await handlers.get("agent_settled")({}, context);
assert.equal(titles.at(-1), "✓ | π | workspace");

await handlers.get("session_shutdown")({}, context);
NODE

printf '%s\n' 'Pi configuration tests passed.'
