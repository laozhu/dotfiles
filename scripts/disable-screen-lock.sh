#!/usr/bin/env bash
# Work GUI agents (Computer Use) need an unlocked session. macOS keeps a single
# screen lock setting for AC and battery, and sysadminctl needs the login password,
# so prompt only while the lock is still on and a terminal can answer.
set -euo pipefail

screen_lock_off() {
  sysadminctl -screenLock status 2>&1 | grep -Fq 'screenLock is off'
}

if screen_lock_off; then
  exit 0
fi

if [ ! -t 0 ]; then
  echo 'warning: screen lock is still on; run scripts/disable-screen-lock.sh in a terminal' >&2
  exit 0
fi

echo '==> Turning off the screen lock for GUI agents (enter your login password)'
sysadminctl -screenLock off -password - || true

if ! screen_lock_off; then
  echo 'warning: screen lock is still on; run scripts/disable-screen-lock.sh again' >&2
fi
