#!/usr/bin/env bash
# Set the managed registry mirrors; OrbStack keeps writing the rest of docker.json.
set -euo pipefail
config="${1:?docker.json path required}"
shift
[ "$#" -gt 0 ] || {
  printf '%s\n' 'At least one mirror is required.' >&2
  exit 1
}
mkdir -p "$(dirname "$config")"
source_json='{}'
if [ -e "$config" ]; then source_json="$(cat "$config")"; fi
jq -e 'type == "object"' <<<"$source_json" >/dev/null
temporary="$(mktemp "$(dirname "$config")/.docker.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
jq '.["registry-mirrors"] = $ARGS.positional' --args "$@" <<<"$source_json" >"$temporary"
chmod 0600 "$temporary"
if [ -f "$config" ] && cmp -s "$config" "$temporary"; then exit 0; fi
mv -f "$temporary" "$config"
