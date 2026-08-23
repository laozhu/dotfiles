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
bootstrap_fixture_home="$bootstrap_test_root/home"
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
printf '%s\n' '  user = "fixture-user";' >"$bootstrap_test_root/flake.nix"

cat >"$bootstrap_test_root/scripts/check-sops-age-key.sh" <<'SH'
#!/usr/bin/env bash
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf 'identity preflight %s\n' "$fixture_dir" >>"$BOOTSTRAP_TEST_LOG"
exit "${BOOTSTRAP_PREFLIGHT_STATUS:-0}"
SH
cat >"$bootstrap_fixture_bin/whoami" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'fixture-user'
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
if [ "$1" = "/usr/sbin/softwareupdate" ]; then
  exit "${BOOTSTRAP_ROSETTA_INSTALL_STATUS:-0}"
fi
SH
chmod 0755 \
  "$bootstrap_test_root/scripts/check-sops-age-key.sh" \
  "$bootstrap_fixture_bin/whoami" \
  "$bootstrap_fixture_bin/uname" \
  "$bootstrap_fixture_bin/pkgutil" \
  "$bootstrap_fixture_bin/nix" \
  "$bootstrap_fixture_bin/sudo"

export BOOTSTRAP_TEST_LOG="$bootstrap_log"
bootstrap_test_path="$bootstrap_fixture_bin:/usr/bin:/bin"
HOME="$bootstrap_fixture_home" PATH="$bootstrap_test_path" \
  bash "$bootstrap_fixture" >/dev/null
test "$(readlink "$bootstrap_fixture_home/.dotfiles")" = \
  "$bootstrap_fixture_real"

expected_bootstrap="$bootstrap_test_root/expected-operations"
printf '%s\n' \
  "pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto" \
  "sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license" \
  "nix shell nixpkgs#age nixpkgs#sops --command $bootstrap_fixture_real/scripts/check-sops-age-key.sh" \
  "identity preflight $bootstrap_fixture_real" \
  "sudo $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#mac" \
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
  "sudo $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#mac" \
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
  "sudo $bootstrap_fixture_bin/nix run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $bootstrap_fixture_real#mac" \
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

trap - EXIT
cleanup_bootstrap_tests

