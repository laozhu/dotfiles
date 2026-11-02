#!/usr/bin/env bash
# Merge only the managed status line; preserve local Claude settings.
set -euo pipefail
settings="${1:?settings path required}"
template="${2:?template path required}"
command="${3:?ccline command required}"
mkdir -p "$(dirname "$settings")"
source_file="$template"
if [ -e "$settings" ] || [ -L "$settings" ]; then
  source_file="$settings"
fi
jq -e 'type == "object"' "$source_file" >/dev/null
temporary="$(mktemp "$(dirname "$settings")/.settings.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
jq --arg command "$command" '.statusLine = {type: "command", command: $command, padding: 0}' "$source_file" >"$temporary"
chmod 0600 "$temporary"
if [ -f "$settings" ] && cmp -s "$settings" "$temporary"; then exit 0; fi
# Keep one rolling backup; every ccline upgrade changes the command path.
if [ -e "$settings" ]; then
  cp -pL "$settings" "$settings.backup"
  chmod 0600 "$settings.backup"
fi
mv -f "$temporary" "$settings"
