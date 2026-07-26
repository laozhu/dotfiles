#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
template="$repo_dir/home/.config/sing-box/config.json"
secret_map="$repo_dir/home/.config/sing-box/secrets-map.json"
encrypted_secrets="$repo_dir/secrets/sing-box.yaml"

if [ "$#" -eq 1 ]; then
  jq -e . "$1" >/dev/null
  exec sing-box check -c "$1"
fi

sops decrypt --output-type json "$encrypted_secrets" \
  | node "$repo_dir/scripts/render-sing-box-config.mjs" "$template" "$secret_map" \
  | sing-box check -c /dev/stdin
