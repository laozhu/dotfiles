#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
config="$fixture/orbstack/config/docker.json"
script="$repo_dir/scripts/sync-orbstack-docker.sh"
bash "$script" "$config" https://a.example https://b.example
jq -e '. == {"registry-mirrors": ["https://a.example", "https://b.example"]}' "$config" >/dev/null
test "$(stat -f %Lp "$config")" = 600
printf '{"features":{"buildkit":true},"registry-mirrors":["https://old.example"]}\n' >"$config"
bash "$script" "$config" https://a.example
jq -e '.features.buildkit == true and .["registry-mirrors"] == ["https://a.example"]' "$config" >/dev/null
printf 'invalid\n' >"$config"
if bash "$script" "$config" https://a.example 2>/dev/null; then exit 1; fi
test "$(cat "$config")" = invalid
test "$(find "$fixture/orbstack/config" -name '.docker.*' | wc -l | tr -d ' ')" = 0
