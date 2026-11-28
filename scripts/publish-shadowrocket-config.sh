#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: publish-shadowrocket-config.sh STATE_DIR NODES_CANDIDATE CONF COREUTILS_BIN NODE CHECKER" >&2
  exit 64
fi

state_dir="$1"
candidate="$2"
conf="$3"
coreutils_bin="$4"
node_bin="$5"
checker="$6"
final_nodes="$state_dir/nodes.txt"

for utility in install mktemp rm cat chmod mv; do
  if [ ! -x "$coreutils_bin/$utility" ]; then
    echo "missing required coreutils binary: $utility" >&2
    exit 1
  fi
done
if [ ! -x "$node_bin" ] || [ ! -f "$checker" ] || [ ! -f "$conf" ]; then
  echo "missing validator or rules" >&2
  exit 1
fi
if [ ! -f "$candidate" ] || [ ! -r "$candidate" ]; then
  echo "candidate is not a readable regular file" >&2
  exit 1
fi
if [ -L "$state_dir" ] || { [ -e "$state_dir" ] && [ ! -d "$state_dir" ]; }; then
  echo "refusing non-directory state path" >&2
  exit 1
fi

"$coreutils_bin/install" -d -m 0700 "$state_dir"
if [ -L "$final_nodes" ] || { [ -e "$final_nodes" ] && [ ! -f "$final_nodes" ]; }; then
  echo "refusing non-regular nodes file" >&2
  exit 1
fi

umask 077
tmp="$("$coreutils_bin/mktemp" "$state_dir/.nodes.txt.XXXXXX")"
cleanup() {
  "$coreutils_bin/rm" -f "$tmp"
}
trap cleanup EXIT

"$coreutils_bin/cat" "$candidate" >"$tmp"
"$node_bin" "$checker" check "$conf" "$tmp"
"$coreutils_bin/chmod" 0600 "$tmp"
"$coreutils_bin/mv" -Tf -- "$tmp" "$final_nodes"
trap - EXIT
