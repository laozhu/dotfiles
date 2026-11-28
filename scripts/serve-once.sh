#!/usr/bin/env bash
# Share one file on the local network until Enter: miniserve serves a private copy
# under a 128-bit random path on the LAN address only, and the URL is shown as a QR code.
# Plain HTTP: use it for files without credentials, on a trusted network.
set -euo pipefail

usage() {
  printf 'Usage: %s [--qr-prefix PREFIX] [--address IPV4] FILE\n' "${0##*/}" >&2
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
qr_prefix=""
address=""
while [ "$#" -gt 1 ]; do
  case "$1" in
    --qr-prefix) qr_prefix="$2" ;;
    --address) address="$2" ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift 2
done
if [ "$#" -ne 1 ] || [ "${1#-}" != "$1" ]; then
  usage
  exit 2
fi
file="$1"
if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  printf 'cannot read: %s\n' "$file" >&2
  exit 1
fi
if [ ! -t 1 ]; then
  echo 'refusing to share without an interactive terminal to stop it' >&2
  exit 1
fi
if ! command -v miniserve >/dev/null; then
  echo 'miniserve not found; run ./rebuild.sh first' >&2
  exit 1
fi

# The default route may be a VPN TUN, so use the first physical interface with a
# private IPv4 address that a phone on the same Wi-Fi can reach.
if [ -z "$address" ]; then
  for interface in en0 en1 en2 en3 en4 en5 en6 en7 en8 en9; do
    candidate="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
    case "$candidate" in
      10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].*)
        address="$candidate"
        break
        ;;
    esac
  done
fi
if [ -z "$address" ]; then
  echo 'no private LAN IPv4 address found; pass --address' >&2
  exit 1
fi

umask 077
share_dir="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$share_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

name="$(basename -- "$file")"
mkdir "$share_dir/files"
cp -- "$file" "$share_dir/files/$name"
token="$(openssl rand -hex 16)"
health_agent="serve-once-healthcheck"

# Pick a free ephemeral port; retry when another process got there first.
for _ in 1 2 3 4 5; do
  port=$((49152 + RANDOM % 16384))
  url="http://$address:$port/$token/$name"
  miniserve --verbose --interfaces "$address" --port "$port" --route-prefix "/$token" \
    --disable-indexing --no-symlinks "$share_dir/files" >"$share_dir/server.log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 30); do
    if curl --silent --fail --noproxy '*' --max-time 1 --user-agent "$health_agent" \
      -o /dev/null "$url"; then
      break 2
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=""
done
if [ -z "$server_pid" ]; then
  echo 'miniserve did not start' >&2
  cat "$share_dir/server.log" >&2
  exit 1
fi

printf '%s%s' "$qr_prefix" "$url" | bash "$repo_dir/scripts/qr.sh" -
# Stop before reading the log: miniserve writes its access log when it exits.
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
server_pid=""
printf 'Stopped sharing %s\n' "$name"

# Report who asked for the file, so a failed import shows whether the device got here.
requests="$(
  grep -F "\"GET /$token/" "$share_dir/server.log" | grep -Fv "\"$health_agent\"" |
    sed -E 's/.*\[INFO\] ([^ ]+) "GET [^"]*" ([0-9]+) [^"]*"[^"]*" "([^"]*)".*/  \1 \2 \3/' || true
)"
if [ -n "$requests" ]; then
  printf 'Requests (address, status, client):\n%s\n' "$requests"
else
  echo 'No device requested the file.'
fi
