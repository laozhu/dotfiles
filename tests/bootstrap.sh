#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bootstrap_test_root="$(mktemp -d)"
cleanup_bootstrap_tests() {
  rm -rf "$bootstrap_test_root"
}
trap cleanup_bootstrap_tests EXIT

bootstrap_fixture="$bootstrap_test_root/bootstrap.sh"
bootstrap_fixture_bin="$bootstrap_test_root/bin"
bootstrap_fixture_home="$bootstrap_test_root/user-home"
bootstrap_fixture_real="$(cd "$bootstrap_test_root" && pwd -P)"
bootstrap_home_repo="$bootstrap_test_root/home-repo"
bootstrap_log="$bootstrap_test_root/operations.log"
mkdir -p \
  "$bootstrap_fixture_bin" \
  "$bootstrap_fixture_home" \
  "$bootstrap_home_repo" \
  "$bootstrap_test_root/scripts"
ln -s "$bootstrap_home_repo" "$bootstrap_fixture_home/.dotfiles"
test "$(readlink "$bootstrap_fixture_home/.dotfiles")" = "$bootstrap_home_repo"
cp "$repo_dir/bootstrap.sh" "$bootstrap_fixture"
cp "$repo_dir/scripts/profile.sh" "$bootstrap_test_root/scripts/profile.sh"
cp "$repo_dir/scripts/nix-cache-env.sh" "$bootstrap_test_root/scripts/nix-cache-env.sh"
cp "$repo_dir/nix-caches.conf" "$bootstrap_test_root/nix-caches.conf"
cp "$repo_dir/scripts/init-pi-settings.sh" "$bootstrap_test_root/scripts/init-pi-settings.sh"
mkdir -p "$bootstrap_test_root/home/.pi/agent"
cp "$repo_dir/home/.pi/agent/settings.json" "$bootstrap_test_root/home/.pi/agent/settings.json"
mkdir -p "$bootstrap_fixture_home/.config/dotfiles"
printf 'home\n' >"$bootstrap_fixture_home/.config/dotfiles/profile"
printf '%s\n' '  user = "fixture-user";' >"$bootstrap_test_root/flake.nix"

cat >"$bootstrap_test_root/scripts/check-sops-age-key.sh" <<'SH'
#!/usr/bin/env bash
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf 'identity preflight %s\n' "$fixture_dir" >>"$BOOTSTRAP_TEST_LOG"
exit "${BOOTSTRAP_PREFLIGHT_STATUS:-0}"
SH
cat >"$bootstrap_test_root/scripts/sync-editors.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$PATH" in
  /etc/profiles/per-user/fixture-user/bin:/run/current-system/sw/bin:*) ;;
  *) echo 'editor sync cannot find newly installed tools' >&2; exit 42 ;;
esac
printf 'editor sync\n' >>"$BOOTSTRAP_TEST_LOG"
exit "${BOOTSTRAP_EDITOR_STATUS:-0}"
SH
cat >"$bootstrap_fixture_bin/whoami" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'fixture-user'
SH
cat >"$bootstrap_fixture_bin/scutil" <<'SH'
#!/usr/bin/env bash
if [ "$#" = 2 ] && [ "$1" = --get ] && [ "$2" = ComputerName ]; then
  printf '%s\n' 'Rich 的 MacBook Pro'
else
  echo 'unexpected scutil query' >&2
  exit 46
fi
SH
cat >"$bootstrap_fixture_bin/uname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${BOOTSTRAP_MACHINE_ARCH:-arm64}"
SH
cat >"$bootstrap_fixture_bin/pkgutil" <<'SH'
#!/usr/bin/env bash
printf 'pkgutil' >>"$BOOTSTRAP_TEST_LOG"
printf ' %s' "$@" >>"$BOOTSTRAP_TEST_LOG"
printf '\n' >>"$BOOTSTRAP_TEST_LOG"
exit "${BOOTSTRAP_ROSETTA_RECEIPT_STATUS:-1}"
SH
cat >"$bootstrap_fixture_bin/nix" <<'SH'
#!/usr/bin/env bash
case "${NIX_CONFIG:-}" in
  *https://cache.thalheim.io*) ;;
  *) echo 'Nix command did not inherit the binary cache configuration' >&2; exit 44 ;;
esac
printf 'nix' >>"$BOOTSTRAP_TEST_LOG"
printf ' %s' "$@" >>"$BOOTSTRAP_TEST_LOG"
printf '\n' >>"$BOOTSTRAP_TEST_LOG"
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--command' ]; then
    shift
    exec "$@"
  fi
  shift
done
SH
cat >"$bootstrap_fixture_bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo' >>"$BOOTSTRAP_TEST_LOG"
printf ' %s' "$@" >>"$BOOTSTRAP_TEST_LOG"
printf '\n' >>"$BOOTSTRAP_TEST_LOG"
if [ "$1" = scutil ]; then
  exit "${BOOTSTRAP_HOSTNAME_STATUS:-0}"
fi
if [ "$1" = "/usr/sbin/softwareupdate" ]; then
  exit "${BOOTSTRAP_ROSETTA_INSTALL_STATUS:-0}"
fi
exit "${BOOTSTRAP_DARWIN_STATUS:-0}"
SH
chmod 0755 \
  "$bootstrap_test_root/scripts/check-sops-age-key.sh" \
  "$bootstrap_fixture_bin/whoami" \
  "$bootstrap_fixture_bin/scutil" \
  "$bootstrap_fixture_bin/uname" \
  "$bootstrap_fixture_bin/pkgutil" \
  "$bootstrap_fixture_bin/nix" \
  "$bootstrap_fixture_bin/sudo"

export BOOTSTRAP_TEST_LOG="$bootstrap_log"
bootstrap_test_path="$bootstrap_fixture_bin:/usr/bin:/bin"
# First-run naming must stop on EOF or a failed system update, without saving
# a completion marker or proceeding with installation.
for naming_failure in eof scutil; do
  : >"$bootstrap_log"
  bootstrap_status=0
  if [ "$naming_failure" = eof ]; then
    HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
      bash "$bootstrap_fixture" </dev/null >/dev/null 2>&1 || bootstrap_status="$?"
    test ! -s "$bootstrap_log"
  else
    BOOTSTRAP_HOSTNAME_STATUS=45 HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
      bash "$bootstrap_fixture" <<<'rich-macbook' >/dev/null 2>&1 || bootstrap_status="$?"
    test "$(cat "$bootstrap_log")" = 'sudo scutil --set ComputerName rich-macbook'
  fi
  test "$bootstrap_status" -ne 0
  test ! -e "$bootstrap_fixture_home/.config/dotfiles/hostname"
done

# Return keeps the current names, including a display name that is not a DNS
# label. No system names should be rewritten when the user accepts it.
: >"$bootstrap_log"
HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" <<<'' >"$bootstrap_test_root/keep-name-output" 2>&1
grep -Fq 'Rich 的 MacBook Pro' "$bootstrap_test_root/keep-name-output"
pi_settings="$bootstrap_fixture_home/.pi/agent/settings.json"
test -f "$pi_settings" && test ! -L "$pi_settings"
cmp "$pi_settings" "$bootstrap_test_root/home/.pi/agent/settings.json"
printf '{"defaultModel":"local","deviceId":"local"}\n' >"$pi_settings"
cp "$pi_settings" "$bootstrap_test_root/local-pi.json"
test "$(cat "$bootstrap_fixture_home/.config/dotfiles/hostname")" = 'Rich 的 MacBook Pro'
if grep -q '^sudo scutil ' "$bootstrap_log"; then
  echo 'bootstrap rewrote machine names after an empty reply' >&2
  exit 1
fi
rm "$bootstrap_fixture_home/.config/dotfiles/hostname"

# Reject dotted, non-ASCII, overlong and hyphen-ended names, then accept
# a plain Bonjour label. Only the accepted value may reach scutil.
: >"$bootstrap_log"
long_machine_name="$(printf '%064d' 0)"
HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >"$bootstrap_test_root/naming-output" 2>&1 <<INPUT
rich-macbook.local
-rich
rich-
rich macbook
电脑
$long_machine_name
rich-macbook
INPUT
test "$(cat "$bootstrap_fixture_home/.config/dotfiles/hostname")" = rich-macbook
head -n 3 "$bootstrap_log" >"$bootstrap_test_root/naming-operations"
printf '%s\n' \
  'sudo scutil --set ComputerName rich-macbook' \
  'sudo scutil --set LocalHostName rich-macbook' \
  'sudo scutil --set HostName rich-macbook' >"$bootstrap_test_root/expected-naming"
cmp "$bootstrap_test_root/expected-naming" "$bootstrap_test_root/naming-operations"
test "$(grep -c '^sudo scutil ' "$bootstrap_log")" = 3

# Rerunning bootstrap must preserve local settings and the machine name.
: >"$bootstrap_log"
HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" </dev/null >/dev/null
test "$(readlink "$bootstrap_fixture_home/.dotfiles")" = \
  "$bootstrap_fixture_real"
cmp "$pi_settings" "$bootstrap_test_root/local-pi.json"

expected_bootstrap="$bootstrap_test_root/expected-operations"
printf '%s\n' \
  "pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto" \
  "sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license" \
  "nix shell nixpkgs#age nixpkgs#sops --command $bootstrap_fixture_real/scripts/check-sops-age-key.sh" \
  "identity preflight $bootstrap_fixture_real" \
  "sudo --preserve-env=NIX_CONFIG $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#home" \
  "editor sync" \
  >"$expected_bootstrap"
if ! cmp -s "$expected_bootstrap" "$bootstrap_log"; then
  echo "bootstrap skipped or misordered the identity preflight" >&2
  diff -u "$expected_bootstrap" "$bootstrap_log" >&2 || true
  exit 1
fi
if grep -Fq "$bootstrap_home_repo" "$bootstrap_log"; then
  echo "bootstrap used the divergent HOME checkout" >&2
  exit 1
fi

expected_bootstrap_without_rosetta="$bootstrap_test_root/expected-without-rosetta"
printf '%s\n' \
  "pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto" \
  "nix shell nixpkgs#age nixpkgs#sops --command $bootstrap_fixture_real/scripts/check-sops-age-key.sh" \
  "identity preflight $bootstrap_fixture_real" \
  "sudo --preserve-env=NIX_CONFIG $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#home" \
  "editor sync" \
  >"$expected_bootstrap_without_rosetta"

: >"$bootstrap_log"
BOOTSTRAP_ROSETTA_RECEIPT_STATUS=0 \
  HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >/dev/null
if ! cmp -s "$expected_bootstrap_without_rosetta" "$bootstrap_log"; then
  echo "bootstrap reinstalled an existing Rosetta receipt" >&2
  exit 1
fi

: >"$bootstrap_log"
BOOTSTRAP_MACHINE_ARCH=x86_64 \
  HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >/dev/null
intel_bootstrap="$bootstrap_test_root/expected-intel-bootstrap"
printf '%s\n' \
  "nix shell nixpkgs#age nixpkgs#sops --command $bootstrap_fixture_real/scripts/check-sops-age-key.sh" \
  "identity preflight $bootstrap_fixture_real" \
  "sudo --preserve-env=NIX_CONFIG $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#home" \
  "editor sync" \
  >"$intel_bootstrap"
if ! cmp -s "$intel_bootstrap" "$bootstrap_log"; then
  echo "bootstrap attempted to install Rosetta on an Intel Mac" >&2
  exit 1
fi

rosetta_failure_log="$bootstrap_test_root/expected-rosetta-failure"
printf '%s\n' \
  "pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto" \
  "sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license" \
  >"$rosetta_failure_log"
: >"$bootstrap_log"
if BOOTSTRAP_ROSETTA_INSTALL_STATUS=41 \
  HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >/dev/null; then
  echo "bootstrap continued after Rosetta installation failed" >&2
  exit 1
else
  bootstrap_status="$?"
fi
test "$bootstrap_status" = '41'
if ! cmp -s "$rosetta_failure_log" "$bootstrap_log"; then
  echo "bootstrap ran later operations after Rosetta installation failed" >&2
  exit 1
fi

failed_bootstrap="$bootstrap_test_root/expected-preflight-failure"
printf '%s\n' \
  "pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto" \
  "sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license" \
  "nix shell nixpkgs#age nixpkgs#sops --command $bootstrap_fixture_real/scripts/check-sops-age-key.sh" \
  "identity preflight $bootstrap_fixture_real" \
  >"$failed_bootstrap"
: >"$bootstrap_log"
if BOOTSTRAP_PREFLIGHT_STATUS=23 \
  HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >/dev/null; then
  echo "bootstrap continued after a failed identity preflight" >&2
  exit 1
else
  bootstrap_status="$?"
fi
test "$bootstrap_status" = '23'
if ! cmp -s "$failed_bootstrap" "$bootstrap_log"; then
  echo "bootstrap ran a switch after a failed identity preflight" >&2
  diff -u "$failed_bootstrap" "$bootstrap_log" >&2 || true
  exit 1
fi

# A failed switch must skip IDE sync; a failed sync must not report success.
for failure_stage in DARWIN EDITOR; do
  : >"$bootstrap_log"
  bootstrap_output="$bootstrap_test_root/failure-output"
  bootstrap_status=0
  env "BOOTSTRAP_${failure_stage}_STATUS=43" \
    HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
    bash "$bootstrap_fixture" >"$bootstrap_output" || bootstrap_status="$?"
  test "$bootstrap_status" = 43
  if grep -Fq '==> Done.' "$bootstrap_output"; then
    echo 'bootstrap reported success after a failure' >&2
    exit 1
  fi
  if [ "$failure_stage" = DARWIN ]; then
    head -n 5 "$expected_bootstrap" >"$bootstrap_test_root/expected-switch-failure"
    cmp "$bootstrap_test_root/expected-switch-failure" "$bootstrap_log"
  else
    cmp "$expected_bootstrap" "$bootstrap_log"
  fi
done

# Fresh bootstrap requires explicit selection and persists it before installing.
rm "$bootstrap_fixture_home/.config/dotfiles/profile"
: >"$bootstrap_log"
if HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" bash "$bootstrap_fixture" >/dev/null 2>&1; then exit 1; fi
test ! -s "$bootstrap_log"
HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" bash "$bootstrap_fixture" --profile work >/dev/null
test "$(cat "$bootstrap_fixture_home/.config/dotfiles/profile")" = work
grep -Fq "$bootstrap_fixture_real#work" "$bootstrap_log"
: >"$bootstrap_log"
if HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" bash "$bootstrap_fixture" --profile home >/dev/null 2>&1; then exit 1; fi
test ! -s "$bootstrap_log"

trap - EXIT
cleanup_bootstrap_tests
