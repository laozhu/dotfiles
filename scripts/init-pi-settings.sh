#!/usr/bin/env bash
set -euo pipefail
settings="$1"
template="$2"

# Preserve regular local files byte-for-byte on every subsequent activation.
if [ -e "$settings" ] && [ ! -L "$settings" ]; then
  if [ ! -f "$settings" ]; then
    printf 'Pi settings is not a regular file: %s\n' "$settings" >&2
    exit 1
  fi
  exit 0
fi

source_file="$template"
if [ -L "$settings" ]; then
  if [ ! -f "$settings" ]; then
    printf 'Cannot migrate unreadable Pi settings symlink: %s\n' "$settings" >&2
    exit 1
  fi
  source_file="$settings"
fi

mkdir -p "$(dirname "$settings")"
temporary="$(mktemp "$settings.tmp.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
install -m 0600 "$source_file" "$temporary"
mv -f "$temporary" "$settings"
trap - EXIT
