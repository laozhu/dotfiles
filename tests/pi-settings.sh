#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
script="$repo_dir/scripts/init-pi-settings.sh"
template="$fixture/repo/settings.json"
settings="$fixture/home/.pi/agent/settings.json"
mkdir -p "$(dirname "$template")"
printf '{"theme":"test","packages":[]}\n' >"$template"

# First deployment creates a private regular file from the template.
bash "$script" "$settings" "$template"
test -f "$settings" && test ! -L "$settings"
cmp "$settings" "$template"
test "$(node -p 'require("fs").statSync(process.argv[1]).mode & 511' "$settings")" = 384

# Existing runtime values survive subsequent activations and template updates.
printf '{"defaultModel":"local-model","deviceId":"local-device"}\n' >"$settings"
cp "$settings" "$fixture/local.json"
printf '{"theme":"updated-template"}\n' >"$template"
bash "$script" "$settings" "$template"
cmp "$settings" "$fixture/local.json"

# Materialize a legacy Home Manager symlink chain without editing its target.
legacy="$fixture/legacy"
mkdir -p "$legacy"
cp "$fixture/local.json" "$legacy/runtime.json"
ln -s "$legacy/runtime.json" "$legacy/hm-settings.json"
rm "$settings"
ln -s "$legacy/hm-settings.json" "$settings"
bash "$script" "$settings" "$template"
test ! -L "$settings"
cmp "$settings" "$fixture/local.json"
cmp "$legacy/runtime.json" "$fixture/local.json"
printf '{"deviceId":"changed-locally"}\n' >"$settings"
cmp "$legacy/runtime.json" "$fixture/local.json"

# A broken link must remain available for diagnosis rather than being overwritten.
rm "$settings"
ln -s "$fixture/missing.json" "$settings"
if bash "$script" "$settings" "$template" >"$fixture/broken.log" 2>&1; then
  echo 'Initialization overwrote a broken settings symlink' >&2
  exit 1
fi
test -L "$settings"
printf '%s\n' 'Pi settings initialization tests passed.'
