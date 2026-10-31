#!/usr/bin/env bash
# Some vendor installers leave a valid cask receipt without an installed app.
set -euo pipefail
if [ "$#" -lt 3 ]; then
  echo 'Usage: ensure-cask-app.sh BREW CASK APP_PATH [APP_PATH ...]' >&2
  exit 2
fi
brew_bin="$1"
cask="$2"
shift 2
app_exists() {
  local app
  for app in "$@"; do
    if [ -d "$app" ]; then return 0; fi
  done
  return 1
}
if app_exists "$@"; then exit 0; fi
echo "==> $cask has no installed application; rerunning its installer."
"$brew_bin" reinstall --cask "$cask"
if ! app_exists "$@"; then
  echo "$cask installer completed without creating the application: $*" >&2
  exit 1
fi
