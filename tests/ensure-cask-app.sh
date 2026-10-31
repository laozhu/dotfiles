#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export CASK_TEST_LOG="$fixture/operations" CASK_TEST_APP="$fixture/lghub.app"
cat >"$fixture/brew" <<'BREW'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASK_TEST_LOG"
case "${CASK_TEST_RESULT:-success}" in
  success) mkdir -p "$CASK_TEST_APP" ;;
  failure) exit 42 ;;
  receipt-only) exit 0 ;;
esac
BREW
chmod +x "$fixture/brew"
check() { bash "$repo_dir/scripts/ensure-cask-app.sh" "$fixture/brew" logitech-g-hub "$fixture/lghub.app" "$fixture/user/lghub.app"; }
# A receipt alone cannot count as installation: repair the missing application.
check
test -d "$fixture/lghub.app"
grep -Fxq 'reinstall --cask logitech-g-hub' "$fixture/operations"
: >"$fixture/operations"
check
test ! -s "$fixture/operations"
mkdir -p "$fixture/user"
mv "$fixture/lghub.app" "$fixture/user/lghub.app"
check
test ! -s "$fixture/operations"
rmdir "$fixture/user/lghub.app"
status=0
CASK_TEST_RESULT=failure check >/dev/null 2>&1 || status=$?
test "$status" = 42
if CASK_TEST_RESULT=receipt-only check >/dev/null 2>&1; then
  echo 'A successful installer without the app must fail validation.' >&2
  exit 1
fi
