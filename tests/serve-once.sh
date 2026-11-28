#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
serve="$repo_dir/scripts/serve-once.sh"
serve_test_root="$(mktemp -d)"
trap 'rm -rf "$serve_test_root"' EXIT

tools="$(
  nix build --no-link --print-out-paths \
    "$repo_dir#darwinConfigurations.mac.pkgs.miniserve" \
    "$repo_dir#darwinConfigurations.mac.pkgs.qrtool"
)"
while IFS= read -r tool; do PATH="$tool/bin:$PATH"; done <<<"$tools"
export PATH

printf 'rules = 1\n' >"$serve_test_root/rules.conf"

status=0
bash "$serve" >/dev/null 2>&1 || status=$?
test "$status" = 2
status=0
bash "$serve" --unknown x "$serve_test_root/rules.conf" >/dev/null 2>&1 || status=$?
test "$status" = 2
if bash "$serve" "$serve_test_root/missing" >/dev/null 2>&1; then
  echo 'serve-once accepted a missing file' >&2
  exit 1
fi
# Without a terminal nobody can stop the server, so it must not start.
if bash "$serve" --address 127.0.0.1 "$serve_test_root/rules.conf" \
  >"$serve_test_root/out" 2>"$serve_test_root/err"; then
  echo 'serve-once ran without a terminal' >&2
  exit 1
fi
grep -Fq 'interactive terminal' "$serve_test_root/err"
if pgrep -f "miniserve .*$serve_test_root" >/dev/null; then
  echo 'serve-once left a server running' >&2
  exit 1
fi

# While the QR code is shown, only the random file URL serves the file; Enter stops it.
fetch_while_shown() {
  local args="" url_base=""
  for _ in $(seq 1 50); do
    args="$(pgrep -fl 'miniserve .*--interfaces 127.0.0.1' | head -n 1 || true)"
    [ -n "$args" ] && break
    sleep 0.1
  done
  local port prefix
  port="$(sed -E 's/.*--port ([0-9]+).*/\1/' <<<"$args")"
  prefix="$(sed -E 's/.*--route-prefix (\/[0-9a-f]+).*/\1/' <<<"$args")"
  url_base="http://127.0.0.1:$port"
  test "${#prefix}" = 33
  curl --silent --noproxy '*' "$url_base$prefix/rules.conf" >"$serve_test_root/fetched"
  local path
  for path in "$prefix/" / /rules.conf; do
    curl --silent --noproxy '*' -o /dev/null -w '%{http_code}\n' "$url_base$path"
  done >"$serve_test_root/denied"
  printf '%s\n' "$port" >"$serve_test_root/port"
  printf '\n'
  sleep 2
}
if script -q /dev/null true </dev/null >/dev/null 2>&1; then
  fetch_while_shown | TERM=xterm script -q "$serve_test_root/session" \
    bash "$serve" --address 127.0.0.1 --qr-prefix 'app://add/' "$serve_test_root/rules.conf" \
    >/dev/null 2>&1
  cmp "$serve_test_root/fetched" "$serve_test_root/rules.conf"
  test "$(sort -u "$serve_test_root/denied")" = 404
  grep -Fq '▄' "$serve_test_root/session"
  grep -Fq 'Stopped sharing rules.conf' "$serve_test_root/session"
  # The summary lists the download but not the server's own health check.
  grep -Eq '^  127\.0\.0\.1 200 curl/' "$serve_test_root/session"
  if grep -Fq serve-once-healthcheck "$serve_test_root/session"; then
    echo 'serve-once reported its own health check' >&2
    exit 1
  fi
  if curl --silent --noproxy '*' --max-time 2 -o /dev/null \
    "http://127.0.0.1:$(cat "$serve_test_root/port")/"; then
    echo 'serve-once kept serving after Enter' >&2
    exit 1
  fi
fi
