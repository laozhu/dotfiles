#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
rebuild_test_root="$(mktemp -d)"
cleanup_rebuild_tests() {
  rm -rf "$rebuild_test_root"
}
trap cleanup_rebuild_tests EXIT

rebuild_fixture="$rebuild_test_root/rebuild.sh"
rebuild_fixture_bin="$rebuild_test_root/bin"
rebuild_fixture_home="$rebuild_test_root/home"
rebuild_fixture_real="$(cd "$rebuild_test_root" && pwd -P)"
rebuild_home_repo="$rebuild_test_root/home-repo"
rebuild_log="$rebuild_test_root/operations.log"
rebuild_cask_source="$rebuild_test_root/homebrew-cask"
rebuild_sing_box="$rebuild_test_root/target-sing-box"
mkdir -p \
  "$rebuild_fixture_bin" \
  "$rebuild_fixture_home" \
  "$rebuild_home_repo" \
  "$rebuild_cask_source/Casks/u" \
  "$rebuild_sing_box/bin" \
  "$rebuild_test_root/scripts"
ln -s "$rebuild_home_repo" "$rebuild_fixture_home/.dotfiles"
test "$(readlink "$rebuild_fixture_home/.dotfiles")" = "$rebuild_home_repo"
cp "$repo_dir/rebuild.sh" "$rebuild_fixture"

cat >"$rebuild_test_root/scripts/check-sops-age-key.sh" <<'SH'
#!/usr/bin/env bash
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf 'identity preflight %s\n' "$fixture_dir" >>"$REBUILD_TEST_LOG"
exit "${REBUILD_IDENTITY_STATUS:-0}"
SH
cat >"$rebuild_test_root/scripts/check-sing-box-config.sh" <<'SH'
#!/usr/bin/env bash
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ "$(command -v sing-box)" != "$REBUILD_SING_BOX/bin/sing-box" ]; then
  echo 'config check did not use the target sing-box' >&2
  exit 35
fi
printf 'config check %s\n' "$fixture_dir" >>"$REBUILD_TEST_LOG"
exit "${REBUILD_CONFIG_STATUS:-0}"
SH
cat >"$rebuild_test_root/scripts/prefetch-uu-booster.sh" <<'SH'
#!/usr/bin/env bash
fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
printf 'UU prefetch %s %s\n' "$fixture_dir" "$1" >>"$REBUILD_TEST_LOG"
exit "${REBUILD_UU_STATUS:-0}"
SH
cat >"$rebuild_fixture_bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix' >>"$REBUILD_TEST_LOG"
printf ' %s' "$@" >>"$REBUILD_TEST_LOG"
printf '\n' >>"$REBUILD_TEST_LOG"
if [ "$1" = "eval" ]; then
  printf '%s' "$REBUILD_CASK_SOURCE"
elif [ "$1" = "build" ]; then
  printf '%s' "$REBUILD_SING_BOX"
fi
exit "${REBUILD_NIX_STATUS:-0}"
SH
cat >"$rebuild_fixture_bin/git" <<'SH'
#!/usr/bin/env bash
printf 'git' >>"$REBUILD_TEST_LOG"
printf ' %s' "$@" >>"$REBUILD_TEST_LOG"
printf '\n' >>"$REBUILD_TEST_LOG"
SH
cat >"$rebuild_fixture_bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo' >>"$REBUILD_TEST_LOG"
printf ' %s' "$@" >>"$REBUILD_TEST_LOG"
printf '\n' >>"$REBUILD_TEST_LOG"
SH
cat >"$rebuild_sing_box/bin/sing-box" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod 0755 \
  "$rebuild_sing_box/bin/sing-box" \
  "$rebuild_test_root/scripts/check-sops-age-key.sh" \
  "$rebuild_test_root/scripts/check-sing-box-config.sh" \
  "$rebuild_test_root/scripts/prefetch-uu-booster.sh" \
  "$rebuild_fixture_bin/nix" \
  "$rebuild_fixture_bin/git" \
  "$rebuild_fixture_bin/sudo"

export REBUILD_TEST_LOG="$rebuild_log"
export REBUILD_CASK_SOURCE="$rebuild_cask_source"
export REBUILD_SING_BOX="$rebuild_sing_box"
rebuild_test_path="$rebuild_fixture_bin:/usr/bin:/bin"
invalid_rebuild_output="$rebuild_test_root/invalid-output"
: >"$rebuild_log"
if HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" unexpected >"$invalid_rebuild_output" 2>&1; then
  echo "rebuild accepted an unexpected argument" >&2
  exit 1
fi
grep -Fq 'Usage:' "$invalid_rebuild_output"
test ! -s "$rebuild_log"

assert_rebuild_operations() {
  expected_log="$1"
  shift
  : >"$rebuild_log"
  HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
    bash "$rebuild_fixture" "$@" >/dev/null
  if ! cmp -s "$expected_log" "$rebuild_log"; then
    echo "rebuild operations ran in the wrong order" >&2
    exit 1
  fi
}

expected_rebuild="$rebuild_test_root/expected-rebuild"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "nix build --no-link --print-out-paths $rebuild_fixture_real#darwinConfigurations.mac.pkgs.sing-box" \
  "config check $rebuild_fixture_real" \
  "nix eval --raw --impure --expr (builtins.getFlake (builtins.getEnv \"DOTFILES_REBUILD_FLAKE\")).inputs.homebrew-cask.outPath" \
  "UU prefetch $rebuild_fixture_real $rebuild_cask_source/Casks/u/uu-booster.rb" \
  "sudo darwin-rebuild switch --flake $rebuild_fixture_real#mac" \
  >"$expected_rebuild"
assert_rebuild_operations "$expected_rebuild"

expected_update_rebuild="$rebuild_test_root/expected-update-rebuild"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "nix flake update --flake $rebuild_fixture_real" \
  "nix build --no-link --print-out-paths $rebuild_fixture_real#darwinConfigurations.mac.pkgs.sing-box" \
  "config check $rebuild_fixture_real" \
  "nix eval --raw --impure --expr (builtins.getFlake (builtins.getEnv \"DOTFILES_REBUILD_FLAKE\")).inputs.homebrew-cask.outPath" \
  "UU prefetch $rebuild_fixture_real $rebuild_cask_source/Casks/u/uu-booster.rb" \
  "sudo darwin-rebuild switch --flake $rebuild_fixture_real#mac" \
  >"$expected_update_rebuild"
assert_rebuild_operations "$expected_update_rebuild" -u
assert_rebuild_operations "$expected_update_rebuild" --update
test "$(readlink "$rebuild_fixture_home/.dotfiles")" = "$rebuild_home_repo"
if grep -Fq "$rebuild_home_repo" "$rebuild_log"; then
  echo "rebuild used the divergent HOME checkout" >&2
  exit 1
fi

# 每个失败点都必须保留退出码，并停止后续操作。
assert_rebuild_failure() {
  local status_var="$1" status="$2" expected_log="$3" operation_count="$4"
  shift 4
  : >"$rebuild_log"
  local actual_status=0
  env "$status_var=$status" HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
    bash "$rebuild_fixture" "$@" >/dev/null || actual_status="$?"
  test "$actual_status" = "$status"
  head -n "$operation_count" "$expected_log" >"$rebuild_test_root/expected-failure"
  cmp "$rebuild_test_root/expected-failure" "$rebuild_log"
}

assert_rebuild_failure REBUILD_IDENTITY_STATUS 31 "$expected_update_rebuild" 1 -u
assert_rebuild_failure REBUILD_NIX_STATUS 33 "$expected_update_rebuild" 2 -u
assert_rebuild_failure REBUILD_NIX_STATUS 36 "$expected_rebuild" 2
assert_rebuild_failure REBUILD_CONFIG_STATUS 32 "$expected_update_rebuild" 4 -u
assert_rebuild_failure REBUILD_UU_STATUS 34 "$expected_rebuild" 5

multiple_rebuild_output="$rebuild_test_root/multiple-output"
: >"$rebuild_log"
if HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" -u --update >"$multiple_rebuild_output" 2>&1; then
  echo "rebuild accepted multiple arguments" >&2
  exit 1
fi
grep -Fq 'Usage:' "$multiple_rebuild_output"
test ! -s "$rebuild_log"

trap - EXIT
cleanup_rebuild_tests
