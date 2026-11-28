#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
checker="$repo_dir/scripts/shadowrocket-config.mjs"
conf="$repo_dir/home/.config/shadowrocket/shadowrocket.conf"

# With a path, check published share links; otherwise render them from the repo.
if [ "$#" -eq 1 ]; then
  exec node "$checker" check "$conf" "$1"
fi

umask 077
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
sops decrypt --output-type json "$repo_dir/secrets/sing-box.yaml" |
  node "$checker" render "$conf" \
    "$repo_dir/home/.config/shadowrocket/nodes.txt" \
    "$repo_dir/home/.config/sing-box/secrets-map.json" \
    "$render_dir/nodes.txt"
