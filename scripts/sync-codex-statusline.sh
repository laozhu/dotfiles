#!/usr/bin/env bash
# Merge only the managed [tui] keys; preserve local Codex settings.
set -euo pipefail
config="${1:?config path required}"
managed="${2:?managed tui.toml path required}"
mkdir -p "$(dirname "$config")"
source_file="$managed"
if [ -e "$config" ] || [ -L "$config" ]; then
  source_file="$config"
fi
temporary="$(mktemp "$(dirname "$config")/.config.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
MANAGED_TUI="$(yq -p toml -o json -I0 '.tui' "$managed")"
export MANAGED_TUI
# Fails on invalid local TOML, leaving the file untouched.
yq -p toml -o toml '.tui = ((.tui // {}) * env(MANAGED_TUI))' "$source_file" \
  >"$temporary" 2>/dev/null || {
  printf 'Cannot parse Codex config: %s\n' "$source_file" >&2
  exit 1
}
chmod 0600 "$temporary"
if [ -f "$config" ] && cmp -s "$config" "$temporary"; then exit 0; fi
# Keep one rolling backup next to the local file.
if [ -e "$config" ]; then
  cp -pL "$config" "$config.backup"
  chmod 0600 "$config.backup"
fi
mv -f "$temporary" "$config"
