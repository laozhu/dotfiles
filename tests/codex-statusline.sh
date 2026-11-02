#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
config="$fixture/codex/config.toml"
managed="$repo_dir/home/.codex/tui.toml"
script="$repo_dir/scripts/sync-codex-statusline.sh"

# Every managed item must be one Codex accepts; unknown ids are dropped with a warning.
# Ids taken from the Codex 0.166 binary; the public docs do not list them.
known='["project-name","current-dir","git-branch","model-with-reasoning",
  "context-used","context-remaining","five-hour-limit","weekly-limit","run-state"]'
yq -p toml -o json '.tui.status_line' "$managed" |
  jq -e --argjson known "$known" 'length > 0 and (. - $known | length == 0)' >/dev/null

# A missing config is created from the managed keys.
bash "$script" "$config" "$managed"
test "$(yq -p toml -o json -I0 '.tui' "$config")" = "$(yq -p toml -o json -I0 '.tui' "$managed")"

# Local settings, nested tui tables and quoted keys survive; managed keys win.
cat >"$config" <<'TOML'
model = "local"
[tui]
screen_reader_detection_done = true
status_line = ["old"]

[tui.model_availability_nux]
"gpt-6.1-sol" = 2

[projects."/a/b"]
trust_level = "trusted"
TOML
cp "$config" "$fixture/before.toml"
bash "$script" "$config" "$managed"
yq -p toml -o json "$config" | jq -e --argjson managed "$(yq -p toml -o json '.tui' "$managed")" '
  .model == "local" and .tui.screen_reader_detection_done == true and
  .tui.model_availability_nux["gpt-6.1-sol"] == 2 and
  .projects["/a/b"].trust_level == "trusted" and
  .tui.status_line == $managed.status_line and
  .tui.status_line_use_colors == $managed.status_line_use_colors' >/dev/null
cmp "$fixture/before.toml" "$config.backup"
test "$(stat -f %Lp "$config")" = 600

# An unchanged config is not rewritten, so the backup stays the original.
bash "$script" "$config" "$managed"
cmp "$fixture/before.toml" "$config.backup"

# Invalid TOML fails without touching the local file.
printf 'invalid = [\n' >"$config"
if bash "$script" "$config" "$managed" 2>/dev/null; then exit 1; fi
test "$(cat "$config")" = 'invalid = ['
