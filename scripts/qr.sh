#!/usr/bin/env bash
# Show a file (or stdin) as terminal QR codes. With --lines, each non-empty line becomes
# its own code, shown one at a time. Content may be secret: print only to a terminal
# and clear the screen on exit.
set -euo pipefail

usage() {
  printf 'Usage: %s [--lines] FILE|-\n' "${0##*/}" >&2
}

per_line=false
if [ "${1:-}" = --lines ]; then
  per_line=true
  shift
fi
if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi
if [ "$1" != - ] && [ ! -r "$1" ]; then
  printf 'cannot read: %s\n' "$1" >&2
  exit 1
fi
if [ ! -t 1 ]; then
  echo 'refusing to print QR codes outside an interactive terminal' >&2
  exit 1
fi
if ! command -v qrtool >/dev/null; then
  echo 'qrtool not found; run ./rebuild.sh first' >&2
  exit 1
fi

content="$(cat -- "$1")"
codes=()
if [ "$per_line" = true ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && codes+=("$line")
  done <<<"$content"
else
  codes=("$content")
fi
if [ "${#codes[@]}" -eq 0 ] || [ -z "${codes[0]}" ]; then
  echo 'nothing to encode' >&2
  exit 1
fi

# Escape codes instead of clear(1), which also discards typed-ahead input.
clear_screen() {
  printf '\033[H\033[2J\033[3J'
}
trap clear_screen EXIT
for index in "${!codes[@]}"; do
  code="${codes[$index]}"
  clear_screen
  # Name a share link by its #fragment; never echo the content itself.
  label=""
  case "$code" in *://*'#'*) label=" ${code##*#}" ;; esac
  printf '[%d/%d]%s\n\n' "$((index + 1))" "${#codes[@]}" "$label"
  qrtool encode -t unicode -- "$code" </dev/null
  printf '\nPress Enter to continue, Ctrl-C to stop.'
  read -r _ </dev/tty || break
done
