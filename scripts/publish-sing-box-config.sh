#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: publish-sing-box-config.sh STATE_DIR FINAL_CONFIG CANDIDATE COREUTILS_BIN JQ SING_BOX" >&2
  exit 64
fi

state_dir="$1"
final_config="$2"
candidate="$3"
coreutils_bin="$4"
jq_bin="$5"
sing_box_bin="$6"

for utility in install mktemp rm cat chmod mv; do
  if [ ! -x "$coreutils_bin/$utility" ]; then
    echo "missing required coreutils binary: $utility" >&2
    exit 1
  fi
done
if [ ! -x "$jq_bin" ] || [ ! -x "$sing_box_bin" ]; then
  echo "missing validator binary" >&2
  exit 1
fi
if [ ! -f "$candidate" ] || [ ! -r "$candidate" ]; then
  echo "candidate is not a readable regular file" >&2
  exit 1
fi

if [ "$final_config" != "$state_dir/config.json" ]; then
  echo "refusing unexpected final config path" >&2
  exit 1
fi
if [ -L "$state_dir" ]; then
  echo "refusing symlink state directory" >&2
  exit 1
fi
if [ -e "$state_dir" ] && [ ! -d "$state_dir" ]; then
  echo "refusing non-directory state path" >&2
  exit 1
fi

"$coreutils_bin/install" -d -m 0700 "$state_dir"

if [ -L "$final_config" ] ||
  { [ -e "$final_config" ] && [ ! -f "$final_config" ]; }; then
  echo "refusing non-regular final config" >&2
  exit 1
fi

umask 077
tmp="$("$coreutils_bin/mktemp" "$state_dir/.config.json.XXXXXX")"
cleanup() {
  "$coreutils_bin/rm" -f "$tmp"
}
trap cleanup EXIT

"$coreutils_bin/cat" "$candidate" >"$tmp"
"$jq_bin" -e . "$tmp" >/dev/null
"$sing_box_bin" check -c "$tmp"
"$coreutils_bin/chmod" 0600 "$tmp"
"$coreutils_bin/mv" -Tf -- "$tmp" "$final_config"
trap - EXIT
