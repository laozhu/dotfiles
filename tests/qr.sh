#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
qr="$repo_dir/scripts/qr.sh"
qr_test_root="$(mktemp -d)"
trap 'rm -rf "$qr_test_root"' EXIT

qrtool_bin="$(
  nix build --no-link --print-out-paths "$repo_dir#darwinConfigurations.mac.pkgs.qrtool"
)/bin"
export PATH="$qrtool_bin:$PATH"

secret='00000000-0000-4000-8000-000000000000'
vless="vless://$secret@node.example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=$(printf 'k%.0s' {1..43})&sid=0123456789abcdef&type=tcp#sg-vless"
hy2="hysteria2://$(printf 'p%.0s' {1..64})@node.example.com:443?sni=hy2.example.com&obfs=salamander&obfs-password=$(printf 'o%.0s' {1..64})#sg-hy2"
printf '%s\n\n%s\n' "$vless" "$hy2" >"$qr_test_root/links.txt"

# Codes of the longest real payloads must decode back to the exact text.
for payload in "$vless" "$hy2" \
  'shadowrocket://config/add/http://192.168.100.200:65535/0123456789abcdef0123456789abcdef/shadowrocket.conf'; do
  qrtool encode -t png -- "$payload" >"$qr_test_root/code.png"
  test "$(qrtool decode "$qr_test_root/code.png")" = "$payload"
done

status=0
bash "$qr" >/dev/null 2>&1 || status=$?
test "$status" = 2
status=0
bash "$qr" --lines a b >/dev/null 2>&1 || status=$?
test "$status" = 2

# Content may be secret, so it is never written to a pipe or file.
if bash "$qr" --lines "$qr_test_root/links.txt" >"$qr_test_root/out" 2>"$qr_test_root/err"; then
  echo 'qr.sh printed outside a terminal' >&2
  exit 1
fi
test ! -s "$qr_test_root/out"
grep -Fq 'interactive terminal' "$qr_test_root/err"
if bash "$qr" "$qr_test_root/missing" >/dev/null 2>&1; then
  echo 'qr.sh accepted a missing file' >&2
  exit 1
fi

# In a terminal, each line is its own code, labelled by name only. macOS script(1)
# sends EOF ahead of piped input that is already buffered, so keys arrive paced.
keys() {
  sleep 1
  printf '\n\n'
  sleep 2
}
if script -q /dev/null true </dev/null >/dev/null 2>&1; then
  keys | TERM=xterm script -q "$qr_test_root/session" \
    bash "$qr" --lines "$qr_test_root/links.txt" >/dev/null 2>&1
  grep -Fq '[1/2] sg-vless' "$qr_test_root/session"
  grep -Fq '[2/2] sg-hy2' "$qr_test_root/session"
  grep -Fq '▄' "$qr_test_root/session"
  if grep -Fq "$secret" "$qr_test_root/session"; then
    echo 'qr.sh echoed the encoded content' >&2
    exit 1
  fi

  keys | TERM=xterm QR="$qr" script -q "$qr_test_root/stdin-session" \
    bash -c 'printf "single file\n" | bash "$QR" -' >/dev/null 2>&1
  grep -Fq '[1/1]' "$qr_test_root/stdin-session"
fi
