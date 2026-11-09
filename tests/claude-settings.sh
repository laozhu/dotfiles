#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
settings="$fixture/claude/settings.json"
script="$repo_dir/scripts/sync-claude-settings.sh"
bash "$script" "$settings" "$repo_dir/home/.claude/settings.json" /test/bin/ccline
jq -e '.statusLine.command == "/test/bin/ccline" and .autoMemoryEnabled == false' "$settings" >/dev/null
jq -e '.permissions.allow == ["Bash(docker *)"]' "$settings" >/dev/null
jq -e '.subagentStatusLine == {type: "command", command: "/test/bin/ccline --subagent"}' "$settings" >/dev/null
printf '{"permissions":{"allow":["Read"]},"statusLine":{"command":"old"},"theme":"local"}\n' >"$settings"
cp "$settings" "$fixture/before.json"
bash "$script" "$settings" "$repo_dir/home/.claude/settings.json" /test/bin/ccline
jq -e '.theme == "local" and .permissions.allow == ["Read"] and .statusLine.command == "/test/bin/ccline"' "$settings" >/dev/null
jq -e '.subagentStatusLine.command == "/test/bin/ccline --subagent"' "$settings" >/dev/null
cmp "$fixture/before.json" "$settings.backup"
bash "$script" "$settings" "$repo_dir/home/.claude/settings.json" /test/bin/ccline
cmp "$fixture/before.json" "$settings.backup"
# A later command change replaces the single backup instead of adding another.
cp "$settings" "$fixture/second.json"
bash "$script" "$settings" "$repo_dir/home/.claude/settings.json" /test/bin/ccline-next
cmp "$fixture/second.json" "$settings.backup"
test "$(find "$fixture/claude" -name '*.backup*' | wc -l | tr -d ' ')" = 1
printf 'invalid\n' >"$settings"
if bash "$script" "$settings" "$repo_dir/home/.claude/settings.json" /test/bin/ccline 2>/dev/null; then exit 1; fi
test "$(cat "$settings")" = invalid
