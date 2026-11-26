#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
lock_test_root="$(mktemp -d)"
trap 'rm -rf "$lock_test_root"' EXIT
mkdir -p "$lock_test_root/bin"
lock_log="$lock_test_root/calls.log"

# The fake reports "off" once the state file says so, and records every call.
cat >"$lock_test_root/bin/sysadminctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOCK_TEST_LOG"
case "$2" in
  status)
    if [ "$(cat "$LOCK_TEST_STATE")" = off ]; then
      echo 'sysadminctl[1] screenLock is off' >&2
    else
      echo 'sysadminctl[1] screenLock delay is 300 seconds' >&2
    fi
    ;;
  off) printf 'off\n' >"$LOCK_TEST_STATE" ;;
esac
SH
chmod +x "$lock_test_root/bin/sysadminctl"
export LOCK_TEST_LOG="$lock_log" LOCK_TEST_STATE="$lock_test_root/state"
run_lock_script() {
  : >"$lock_log"
  PATH="$lock_test_root/bin:/usr/bin:/bin" bash "$repo_dir/scripts/disable-screen-lock.sh" "$@"
}

# Already off: never prompts for the password.
printf 'off\n' >"$LOCK_TEST_STATE"
run_lock_script </dev/null
test "$(cat "$lock_log")" = '-screenLock status'

# Still on without a terminal: warns and leaves the setting alone.
printf 'on\n' >"$LOCK_TEST_STATE"
warning="$(run_lock_script </dev/null 2>&1)"
test "$(cat "$lock_log")" = '-screenLock status'
case "$warning" in *'screen lock is still on'*) ;; *) exit 1 ;; esac

# Still on with a terminal: turns it off, then rechecks.
if script -q /dev/null true </dev/null >/dev/null 2>&1; then
  : >"$lock_log"
  PATH="$lock_test_root/bin:/usr/bin:/bin" script -q /dev/null \
    bash "$repo_dir/scripts/disable-screen-lock.sh" >/dev/null 2>&1
  test "$(cat "$lock_log")" = "$(printf '%s\n' '-screenLock status' '-screenLock off -password -' '-screenLock status')"
  test "$(cat "$LOCK_TEST_STATE")" = off
fi
