#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config="$repo_dir/home/.config/sing-box/config.json"
secret_map="$repo_dir/home/.config/sing-box/secrets-map.json"
identity_preflight="$repo_dir/scripts/check-sops-age-key.sh"

if [ ! -f "$identity_preflight" ]; then
  echo "identity preflight script is missing" >&2
  exit 1
fi

preflight_test_root="$(mktemp -d)"
cleanup_preflight_tests() {
  rm -rf "$preflight_test_root"
}
trap cleanup_preflight_tests EXIT

missing_home="$preflight_test_root/missing-home"
mkdir -p "$missing_home"
missing_output="$preflight_test_root/missing-output"
if HOME="$missing_home" bash "$identity_preflight" \
  >"$missing_output" 2>&1; then
  echo "identity preflight accepted a missing identity" >&2
  exit 1
fi
grep -Fq 'Bitwarden item: dotfiles - sops age identity' "$missing_output"
grep -Fq \
  'Expected path: ~/Library/Application Support/sops/age/keys.txt' \
  "$missing_output"

fixture_home="$preflight_test_root/fixture-home"
fixture_key_dir="$fixture_home/Library/Application Support/sops/age"
fixture_key_file="$fixture_key_dir/keys.txt"
install -d -m 0700 "$fixture_key_dir"
(
  umask 077
  age-keygen -o "$fixture_key_file" >/dev/null 2>&1
)

directory_mode_output="$preflight_test_root/directory-mode-output"
chmod 0755 "$fixture_key_dir"
if HOME="$fixture_home" bash "$identity_preflight" \
  >"$directory_mode_output" 2>&1; then
  echo "identity preflight accepted an unsafe directory mode" >&2
  exit 1
fi
grep -Fq 'Expected permissions: 700' "$directory_mode_output"
grep -Fq 'Actual permissions: 755' "$directory_mode_output"

file_mode_output="$preflight_test_root/file-mode-output"
chmod 0700 "$fixture_key_dir"
chmod 0644 "$fixture_key_file"
if HOME="$fixture_home" bash "$identity_preflight" \
  >"$file_mode_output" 2>&1; then
  echo "identity preflight accepted an unsafe file mode" >&2
  exit 1
fi
grep -Fq 'Expected permissions: 600' "$file_mode_output"
grep -Fq 'Actual permissions: 644' "$file_mode_output"

mismatch_output="$preflight_test_root/mismatch-output"
chmod 0600 "$fixture_key_file"
if HOME="$fixture_home" bash "$identity_preflight" \
  >"$mismatch_output" 2>&1; then
  echo "identity preflight accepted a mismatched identity" >&2
  exit 1
fi
grep -Fq 'Identity does not match the repository recipient.' "$mismatch_output"
if rg -q 'AGE-SECRET-KEY-|age1[0-9a-z]+' "$mismatch_output"; then
  echo "identity preflight exposed key material on mismatch" >&2
  exit 1
fi

duplicate_repo="$preflight_test_root/duplicate-repo"
duplicate_preflight="$duplicate_repo/scripts/check-sops-age-key.sh"
duplicate_output="$preflight_test_root/duplicate-output"
fixture_recipient="$(
  age-keygen -y "$fixture_key_file" 2>/dev/null
)"
mkdir -p "$duplicate_repo/scripts" "$duplicate_repo/secrets"
cp "$identity_preflight" "$duplicate_preflight"
printf '%s\n' \
  "keys: $fixture_recipient" \
  "duplicate: $fixture_recipient" \
  >"$duplicate_repo/.sops.yaml"
: >"$duplicate_repo/secrets/sing-box.yaml"
if HOME="$fixture_home" bash "$duplicate_preflight" \
  >"$duplicate_output" 2>&1; then
  echo "identity preflight accepted duplicate repository recipients" >&2
  exit 1
fi
if ! grep -Fq 'Expected one repository recipient in:' "$duplicate_output"; then
  echo "identity preflight did not reject duplicate repository recipients" >&2
  exit 1
fi
if rg -q 'AGE-SECRET-KEY-|age1[0-9a-z]+' "$duplicate_output"; then
  echo "identity preflight exposed key material for duplicate recipients" >&2
  exit 1
fi

trap - EXIT
cleanup_preflight_tests

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
SH
chmod 0755 \
  "$bootstrap_test_root/scripts/check-sops-age-key.sh" \
  "$bootstrap_fixture_bin/whoami" \
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

failed_bootstrap="$bootstrap_test_root/expected-preflight-failure"
printf '%s\n' \
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

uu_test_root="$(mktemp -d)"
cleanup_uu_tests() {
  rm -rf "$uu_test_root"
}
trap cleanup_uu_tests EXIT

uu_prefetch="$repo_dir/scripts/prefetch-uu-booster.sh"
uu_test_bin="$uu_test_root/bin"
uu_test_cache_root="$uu_test_root/cache"
uu_test_cache="$uu_test_cache_root/downloads/cf06028bd51147d9ef0f42c622fd0dd7bea21924443c072454e4bdc37b3ba804--UU-macOS-2.8.14.dmg"
uu_test_dmg="$uu_test_root/signed.dmg"
uu_test_cask="$uu_test_root/uu-booster.rb"
uu_test_curl_log="$uu_test_root/curl.log"
mkdir -p "$uu_test_bin" "$uu_test_cache_root"
printf 'signed dmg fixture\n' >"$uu_test_dmg"
cat >"$uu_test_cask" <<'RUBY'
cask "uu-booster" do
  version "2.8.14"
  sha256 "eb030da6c6c30b0fc16952274fe661c5b4651f0371061379773cd6ca848bee3b"
  url "https://uu.gdl.netease.com/UU-macOS-#{version}.dmg"
end
RUBY

cat >"$uu_test_bin/brew" <<'SH'
#!/usr/bin/env bash
case "$*" in
  "--cache")
    printf '%s\n' "$UU_TEST_CACHE_ROOT"
    ;;
  *)
    exit 64
    ;;
esac
SH
cat >"$uu_test_bin/curl" <<'SH'
#!/usr/bin/env bash
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "$url" >>"$UU_TEST_CURL_LOG"
signed_url="${UU_TEST_SIGNED_URL:-https://uu.gdl.netease.com/UU-macOS-2.8.14.dmg?type=pc&key1=test-signature&key2=test-key}"
case "$url" in
  "https://adl.netease.com/d/g/uu/c/uumac?type=pc")
    printf 'var pc_link = "%s";\n' "$signed_url"
    ;;
  *)
    if [ "$url" = "$signed_url" ]; then
      cp "$UU_TEST_DMG" "$output"
    else
      exit 65
    fi
    ;;
esac
SH
chmod 0755 "$uu_test_bin/brew" "$uu_test_bin/curl"

export UU_TEST_CACHE_ROOT="$uu_test_cache_root"
export UU_TEST_CURL_LOG="$uu_test_curl_log"
export UU_TEST_DMG="$uu_test_dmg"
PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >/dev/null
if ! cmp -s "$uu_test_dmg" "$uu_test_cache"; then
  echo "UU Booster prefetch did not populate Homebrew's verified cache" >&2
  exit 1
fi

: >"$uu_test_curl_log"
PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >/dev/null
if [ -s "$uu_test_curl_log" ]; then
  echo "UU Booster prefetch accessed the network for a valid cache entry" >&2
  exit 1
fi

rm -f "$uu_test_cache"
foreign_output="$uu_test_root/foreign-output"
if UU_TEST_SIGNED_URL='https://downloads.example.test/UU-macOS-2.8.14.dmg?type=pc&key1=test&key2=test' \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$foreign_output" 2>&1; then
  echo "UU Booster prefetch accepted a non-NetEase download URL" >&2
  exit 1
fi
if [ -e "$uu_test_cache" ]; then
  echo "UU Booster prefetch cached a download from an untrusted host" >&2
  exit 1
fi

version_output="$uu_test_root/version-output"
if UU_TEST_SIGNED_URL='https://uu.gdl.netease.com/UU-macOS-9.9.9.dmg?type=pc&key1=test&key2=test' \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$version_output" 2>&1; then
  echo "UU Booster prefetch accepted a mismatched download version" >&2
  exit 1
fi

previous_cache="$uu_test_root/previous-cache"
bad_dmg="$uu_test_root/bad.dmg"
printf 'previous cache\n' >"$previous_cache"
printf 'bad download\n' >"$bad_dmg"
mkdir -p "$(dirname "$uu_test_cache")"
cp "$previous_cache" "$uu_test_cache"
checksum_output="$uu_test_root/checksum-output"
if UU_TEST_DMG="$bad_dmg" \
  PATH="$uu_test_bin:/usr/bin:/bin" \
  bash "$uu_prefetch" "$uu_test_cask" >"$checksum_output" 2>&1; then
  echo "UU Booster prefetch accepted a mismatched SHA-256" >&2
  exit 1
fi
if ! cmp -s "$previous_cache" "$uu_test_cache"; then
  echo "UU Booster prefetch overwrote the previous cache before verification" >&2
  exit 1
fi
if find "$(dirname "$uu_test_cache")" -name '*.incomplete.*' -print -quit |
  grep -q .; then
  echo "UU Booster prefetch left an incomplete download behind" >&2
  exit 1
fi

trap - EXIT
cleanup_uu_tests

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
mkdir -p \
  "$rebuild_fixture_bin" \
  "$rebuild_fixture_home" \
  "$rebuild_home_repo" \
  "$rebuild_cask_source/Casks/u" \
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
chmod 0755 \
  "$rebuild_test_root/scripts/check-sops-age-key.sh" \
  "$rebuild_test_root/scripts/check-sing-box-config.sh" \
  "$rebuild_test_root/scripts/prefetch-uu-booster.sh" \
  "$rebuild_fixture_bin/nix" \
  "$rebuild_fixture_bin/git" \
  "$rebuild_fixture_bin/sudo"

export REBUILD_TEST_LOG="$rebuild_log"
export REBUILD_CASK_SOURCE="$rebuild_cask_source"
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
  "config check $rebuild_fixture_real" \
  "nix eval --raw --impure --expr (builtins.getFlake (builtins.getEnv \"DOTFILES_REBUILD_FLAKE\")).inputs.homebrew-cask.outPath" \
  "UU prefetch $rebuild_fixture_real $rebuild_cask_source/Casks/u/uu-booster.rb" \
  "sudo darwin-rebuild switch --flake $rebuild_fixture_real#mac" \
  >"$expected_rebuild"
assert_rebuild_operations "$expected_rebuild"

expected_update_rebuild="$rebuild_test_root/expected-update-rebuild"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "config check $rebuild_fixture_real" \
  "nix flake update --flake $rebuild_fixture_real" \
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

identity_failure_log="$rebuild_test_root/expected-identity-failure"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  >"$identity_failure_log"
: >"$rebuild_log"
if REBUILD_IDENTITY_STATUS=31 \
  HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" -u >/dev/null; then
  echo "rebuild continued after a failed identity preflight" >&2
  exit 1
else
  rebuild_status="$?"
fi
test "$rebuild_status" = '31'
if ! cmp -s "$identity_failure_log" "$rebuild_log"; then
  echo "rebuild ran later operations after identity failure" >&2
  exit 1
fi

config_failure_log="$rebuild_test_root/expected-config-failure"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "config check $rebuild_fixture_real" \
  >"$config_failure_log"
: >"$rebuild_log"
if REBUILD_CONFIG_STATUS=32 \
  HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" -u >/dev/null; then
  echo "rebuild continued after a failed config check" >&2
  exit 1
else
  rebuild_status="$?"
fi
test "$rebuild_status" = '32'
if ! cmp -s "$config_failure_log" "$rebuild_log"; then
  echo "rebuild ran later operations after config failure" >&2
  exit 1
fi

uu_failure_log="$rebuild_test_root/expected-uu-failure"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "config check $rebuild_fixture_real" \
  "nix eval --raw --impure --expr (builtins.getFlake (builtins.getEnv \"DOTFILES_REBUILD_FLAKE\")).inputs.homebrew-cask.outPath" \
  "UU prefetch $rebuild_fixture_real $rebuild_cask_source/Casks/u/uu-booster.rb" \
  >"$uu_failure_log"
: >"$rebuild_log"
if REBUILD_UU_STATUS=34 \
  HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" >/dev/null; then
  echo "rebuild continued after a failed UU Booster prefetch" >&2
  exit 1
else
  rebuild_status="$?"
fi
test "$rebuild_status" = '34'
if ! cmp -s "$uu_failure_log" "$rebuild_log"; then
  echo "rebuild switched after a failed UU Booster prefetch" >&2
  exit 1
fi

update_failure_log="$rebuild_test_root/expected-update-failure"
printf '%s\n' \
  "identity preflight $rebuild_fixture_real" \
  "config check $rebuild_fixture_real" \
  "nix flake update --flake $rebuild_fixture_real" \
  >"$update_failure_log"
: >"$rebuild_log"
if REBUILD_NIX_STATUS=33 \
  HOME="$rebuild_fixture_home" PATH="$rebuild_test_path" \
  bash "$rebuild_fixture" -u >/dev/null; then
  echo "rebuild switched after a failed flake update" >&2
  exit 1
else
  rebuild_status="$?"
fi
test "$rebuild_status" = '33'
if ! cmp -s "$update_failure_log" "$rebuild_log"; then
  echo "rebuild ran a switch after update failure" >&2
  exit 1
fi

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

grep -Fq 'darwinConfigurations.mac' "$repo_dir/flake.nix"
if grep -Fq 'git add .' "$repo_dir/rebuild.sh"; then
  echo "rebuild must not stage repository changes" >&2
  exit 1
fi
grep -Fq '#mac' "$repo_dir/bootstrap.sh"
grep -Fq '#mac' "$repo_dir/rebuild.sh"
if rg -n 'sing-box[[:space:]]+run|launchctl.*sing-box' \
  "$repo_dir/bootstrap.sh" \
  "$repo_dir/rebuild.sh" \
  "$repo_dir/scripts" \
  "$repo_dir/sing-box.nix"; then
  echo "bootstrap and rebuild must not manage the sing-box runtime" >&2
  exit 1
fi

jq -e '
  .["$schema"] == "https://sing-box.sagernet.org/schema.json" and
  ([.inbounds[].tag] | sort == ["mixed-in", "tun-in"]) and
  ([.outbounds[].tag] | index("proxy") != null) and
  ([.outbounds[].tag] | index("auto") != null) and
  ([.outbounds[].tag] | index("singapore") != null) and
  ([.outbounds[].tag] | index("usa") != null) and
  ([.outbounds[].tag] | index("sg-vless") != null) and
  ([.outbounds[].tag] | index("sg-hy2") != null) and
  ([.outbounds[].tag] | index("us-vless") != null) and
  ([.outbounds[].tag] | index("us-hy2") != null) and
  .route.final == "direct" and
  .route.default_domain_resolver == "proxy-dns" and
  .route.auto_detect_interface == true and
  .experimental.cache_file.enabled == true
' "$config" >/dev/null

jq -e '
  .log == {"level": "info", "timestamp": true} and
  .dns.strategy == "prefer_ipv4" and
  ([.dns.servers[].tag] ==
    ["direct-dns", "proxy-dns", "hosts-dns", "fakeip-dns"]) and
  .dns.servers[0] == {
    "type": "https",
    "tag": "direct-dns",
    "server": "223.5.5.5",
    "server_port": 443,
    "tls": {
      "enabled": true,
      "server_name": "dns.alidns.com"
    }
  } and
  .dns.servers[1] == {
    "type": "https",
    "tag": "proxy-dns",
    "server": "1.1.1.1",
    "server_port": 443,
    "detour": "proxy",
    "tls": {
      "enabled": true,
      "server_name": "cloudflare-dns.com"
    }
  } and
  .dns.servers[2] == {
    "type": "hosts",
    "tag": "hosts-dns",
    "predefined": {
      "__SOPS_SG_SERVER_HOSTNAME__": "__SOPS_SG_SERVER_IP__",
      "__SOPS_US_SERVER_HOSTNAME__": "__SOPS_US_SERVER_IP__"
    }
  } and
  .dns.servers[3] == {
    "type": "fakeip",
    "tag": "fakeip-dns",
    "inet4_range": "198.18.0.0/15",
    "inet6_range": "fc00::/18"
  } and
  .dns.rules == [
    {
      "rule_set": "proxy-server",
      "server": "hosts-dns"
    },
    {
      "rule_set": ["gfwlist", "openai", "claude", "google-meet"],
      "server": "proxy-dns"
    },
    {
      "ip_is_private": true,
      "server": "direct-dns"
    },
    {
      "query_type": ["A", "AAAA"],
      "server": "fakeip-dns"
    }
  ]
' "$config" >/dev/null

jq -e '
  .inbounds == [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      "auto_route": true,
      "strict_route": true,
      "stack": "mixed"
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 7777
    }
  ] and
  .outbounds[0] == {
    "type": "selector",
    "tag": "proxy",
    "outbounds": [
      "auto",
      "singapore",
      "usa",
      "sg-vless",
      "sg-hy2",
      "us-vless",
      "us-hy2"
    ],
    "default": "auto",
    "interrupt_exist_connections": true
  } and
  .outbounds[1] == {
    "type": "urltest",
    "tag": "auto",
    "outbounds": ["sg-vless", "sg-hy2", "us-vless", "us-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "tolerance": 50,
    "interrupt_exist_connections": false
  } and
  .outbounds[2] == {
    "type": "urltest",
    "tag": "singapore",
    "outbounds": ["sg-vless", "sg-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "interrupt_exist_connections": false
  } and
  .outbounds[3] == {
    "type": "urltest",
    "tag": "usa",
    "outbounds": ["us-vless", "us-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "interrupt_exist_connections": false
  } and
  ([.outbounds[].tag] == [
    "proxy",
    "auto",
    "singapore",
    "usa",
    "sg-vless",
    "sg-hy2",
    "us-vless",
    "us-hy2",
    "direct"
  ])
' "$config" >/dev/null

jq -e '
  def vless_valid($tag; $server; $uuid; $name; $key; $short):
    first(.outbounds[] | select(.tag == $tag)) == {
      "type": "vless",
      "tag": $tag,
      "server": $server,
      "server_port": 443,
      "domain_resolver": "hosts-dns",
      "uuid": $uuid,
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": $name,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": $key,
          "short_id": $short
        }
      }
    };
  def hy2_valid($tag; $server; $port; $password; $obfs; $name; $up; $down):
    first(.outbounds[] | select(.tag == $tag)) == {
      "type": "hysteria2",
      "tag": $tag,
      "server": $server,
      "server_port": $port,
      "domain_resolver": "hosts-dns",
      "up_mbps": $up,
      "down_mbps": $down,
      "password": $password,
      "obfs": {
        "type": "salamander",
        "password": $obfs
      },
      "tls": {
        "enabled": true,
        "server_name": $name
      }
    };
  vless_valid(
    "sg-vless";
    "__SOPS_SG_SERVER_HOSTNAME__";
    "__SOPS_SG_VLESS_UUID__";
    "__SOPS_SG_VLESS_TLS_SERVER_NAME__";
    "__SOPS_SG_VLESS_REALITY_PUBLIC_KEY__";
    "__SOPS_SG_VLESS_REALITY_SHORT_ID__"
  ) and
  hy2_valid(
    "sg-hy2";
    "__SOPS_SG_SERVER_HOSTNAME__";
    443;
    "__SOPS_SG_HY2_PASSWORD__";
    "__SOPS_SG_HY2_OBFS_PASSWORD__";
    "__SOPS_SG_HY2_TLS_SERVER_NAME__";
    45;
    170
  ) and
  vless_valid(
    "us-vless";
    "__SOPS_US_SERVER_HOSTNAME__";
    "__SOPS_US_VLESS_UUID__";
    "__SOPS_US_VLESS_TLS_SERVER_NAME__";
    "__SOPS_US_VLESS_REALITY_PUBLIC_KEY__";
    "__SOPS_US_VLESS_REALITY_SHORT_ID__"
  ) and
  hy2_valid(
    "us-hy2";
    "__SOPS_US_SERVER_HOSTNAME__";
    8443;
    "__SOPS_US_HY2_PASSWORD__";
    "__SOPS_US_HY2_OBFS_PASSWORD__";
    "__SOPS_US_HY2_TLS_SERVER_NAME__";
    32;
    95
  ) and
  first(.outbounds[] | select(.tag == "direct")) == {
    "type": "direct",
    "tag": "direct",
    "domain_resolver": "direct-dns"
  }
' "$config" >/dev/null

jq -e '
  .route.rules == [
    {"action": "sniff"},
    {"protocol": "dns", "action": "hijack-dns"},
    {"rule_set": "proxy-server", "outbound": "direct"},
    {"ip_is_private": true, "outbound": "direct"},
    {"rule_set": "custom-reject", "action": "reject"},
    {"rule_set": "custom-direct", "outbound": "direct"},
    {"rule_set": "custom-proxy", "outbound": "proxy"},
    {"rule_set": "openai", "outbound": "proxy"},
    {"rule_set": "claude", "outbound": "proxy"},
    {
      "rule_set": "google-meet",
      "network": "udp",
      "port": 3478,
      "port_range": "19302:19309",
      "outbound": "proxy"
    },
    {"rule_set": "google-meet", "outbound": "proxy"},
    {"rule_set": "gfwlist", "outbound": "proxy"}
  ] and
  .route.rule_set[0] == {
    "type": "inline",
    "tag": "proxy-server",
    "rules": [
      {
        "domain": [
          "__SOPS_SG_SERVER_HOSTNAME__",
          "__SOPS_US_SERVER_HOSTNAME__"
        ]
      }
    ]
  } and
  .route.rule_set[1:4] == [
    {
      "type": "inline",
      "tag": "custom-reject",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    },
    {
      "type": "inline",
      "tag": "custom-direct",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    },
    {
      "type": "inline",
      "tag": "custom-proxy",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    }
  ] and
  .route.rule_set[4] == {
    "type": "inline",
    "tag": "google-meet",
    "rules": [
      {
        "domain": [
          "meet.google.com",
          "meetings.googleapis.com",
          "stun.l.google.com",
          "workspace.turns.goog",
          "meet.turns.goog"
        ],
        "ip_cidr": [
          "74.125.250.0/24",
          "142.250.82.0/24",
          "2001:4860:4864:5::/64",
          "2001:4860:4864:6::/64"
        ]
      }
    ]
  } and
  ([.route.rule_set[] | select(.type == "remote")] | length == 3) and
  ([.route.rule_set[] | select(.type == "remote") | .tag] ==
    ["gfwlist", "openai", "claude"]) and
  ([.route.rule_set[] | select(.type == "remote") | .download_detour] |
    all(. == "proxy")) and
  ([.route.rule_set[] | select(.type == "remote") | .update_interval] |
    all(. == "24h")) and
  ([.route.rule_set[] | select(.type == "remote") | .format] |
    all(. == "binary")) and
  first(.route.rule_set[] | select(.tag == "gfwlist")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs" and
  first(.route.rule_set[] | select(.tag == "openai")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs" and
  first(.route.rule_set[] | select(.tag == "claude")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/anthropic.srs"
' "$config" >/dev/null

jq -e '
  .experimental == {
    "cache_file": {
      "enabled": true,
      "store_fakeip": true
    }
  } and
  (.experimental | has("clash_api") | not) and
  (has("http_clients") | not) and
  ([.. | objects | keys[]] |
    any(
      . == "external_controller" or
      . == "external_ui" or
      . == "external_ui_download_url" or
      . == "secret"
    ) | not)
' "$config" >/dev/null

jq -e '
  . == {
    "__SOPS_SG_SERVER_HOSTNAME__": "sing-box/singapore/server-hostname",
    "__SOPS_SG_SERVER_IP__": "sing-box/singapore/server-ip",
    "__SOPS_SG_VLESS_UUID__": "sing-box/singapore/vless/uuid",
    "__SOPS_SG_VLESS_TLS_SERVER_NAME__":
      "sing-box/singapore/vless/tls-server-name",
    "__SOPS_SG_VLESS_REALITY_PUBLIC_KEY__":
      "sing-box/singapore/vless/reality-public-key",
    "__SOPS_SG_VLESS_REALITY_SHORT_ID__":
      "sing-box/singapore/vless/reality-short-id",
    "__SOPS_SG_HY2_PASSWORD__": "sing-box/singapore/hysteria2/password",
    "__SOPS_SG_HY2_OBFS_PASSWORD__":
      "sing-box/singapore/hysteria2/obfs-password",
    "__SOPS_SG_HY2_TLS_SERVER_NAME__":
      "sing-box/singapore/hysteria2/tls-server-name",
    "__SOPS_US_SERVER_HOSTNAME__": "sing-box/usa/server-hostname",
    "__SOPS_US_SERVER_IP__": "sing-box/usa/server-ip",
    "__SOPS_US_VLESS_UUID__": "sing-box/usa/vless/uuid",
    "__SOPS_US_VLESS_TLS_SERVER_NAME__":
      "sing-box/usa/vless/tls-server-name",
    "__SOPS_US_VLESS_REALITY_PUBLIC_KEY__":
      "sing-box/usa/vless/reality-public-key",
    "__SOPS_US_VLESS_REALITY_SHORT_ID__":
      "sing-box/usa/vless/reality-short-id",
    "__SOPS_US_HY2_PASSWORD__": "sing-box/usa/hysteria2/password",
    "__SOPS_US_HY2_OBFS_PASSWORD__":
      "sing-box/usa/hysteria2/obfs-password",
    "__SOPS_US_HY2_TLS_SERVER_NAME__":
      "sing-box/usa/hysteria2/tls-server-name"
  }
' "$secret_map" >/dev/null

map_markers="$(jq -c '[keys[]] | sort' "$secret_map")"
config_markers="$(
  {
    jq -r '.. | strings' "$config"
    jq -r '.. | objects | keys[]' "$config"
  } \
    | rg -o '__SOPS_[A-Z0-9_]+__' \
    | jq -Rsc 'split("\n")[:-1]'
)"
jq -en --argjson expected "$map_markers" --argjson actual "$config_markers" '
  ($actual | unique | sort) == $expected and
  ($expected | all(
    . as $marker |
    ([ $actual[] | select(. == $marker) ] | length) ==
      (if ($marker | endswith("_SERVER_HOSTNAME__")) then 4 else 1 end)
  ))
' >/dev/null

bash -n "$repo_dir/scripts/check-sing-box-config.sh"
node --check "$repo_dir/scripts/render-sing-box-config.mjs"

node --input-type=module - "$repo_dir/scripts/render-sing-box-config.mjs" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const rendererPath = process.argv[2];
const { renderConfig } = await import(pathToFileURL(rendererPath));

assert.equal(
  renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  '{"secret":"rendered"}',
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/missing" },
    { root: {} },
  ),
  /missing SOPS key path: root\/missing/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "" } },
  ),
  /invalid secret value for: root\/value/,
);
assert.equal(
  renderConfig(
    '{"a":"__SOPS_TEST__","b":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  '{"a":"rendered","b":"rendered"}',
);
assert.throws(
  () => renderConfig(
    '{"secret":"unchanged"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: "rendered" } },
  ),
  /expected marker at least once: __SOPS_TEST__/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_UNKNOWN__"}',
    {},
    {},
  ),
  /unresolved SOPS marker remains/,
);
assert.throws(
  () => renderConfig(
    '{"secret":"__SOPS_TEST__"}',
    { __SOPS_TEST__: "root/value" },
    { root: { value: '"' } },
  ),
  SyntaxError,
);
NODE

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.path" \
  | grep -Fx '/run/secrets/rendered/sing-box-candidate.json'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.age.keyFile" \
  | grep -Fx '/Users/rich/Library/Application Support/sops/age/keys.txt'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.owner" \
  | grep -Fx 'rich'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.group" \
  | grep -Fx 'staff'

nix eval --raw \
  "$repo_dir#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.mode" \
  | grep -Fx '0400'

publisher="$repo_dir/scripts/publish-sing-box-config.sh"
coreutils_bin="$(
  nix eval --raw "$repo_dir#darwinConfigurations.mac.pkgs.coreutils"
)/bin"
jq_bin="$(command -v jq)"
sing_box_bin="$(command -v sing-box)"

bash -n "$publisher"
test -x "$jq_bin"
test -x "$sing_box_bin"

publish_test_root="$(mktemp -d)"
cleanup_publish_tests() {
  rm -rf "$publish_test_root"
}
trap cleanup_publish_tests EXIT

assert_no_publish_temps() {
  if find "$publish_test_root" \
    -name '.config.json.*' \
    -print -quit \
    | grep -q .; then
    echo "publish helper left a temporary file behind" >&2
    exit 1
  fi
}

run_publisher() {
  bash \
    "$publisher" \
    "$1" \
    "$2" \
    "$3" \
    "$coreutils_bin" \
    "$jq_bin" \
    "$sing_box_bin"
}

valid_candidate="$publish_test_root/valid-candidate.json"
replacement_candidate="$publish_test_root/replacement-candidate.json"
printf '%s' '{}' >"$valid_candidate"
printf '%s' \
  '{"outbounds":[{"type":"direct","tag":"direct"}]}' \
  >"$replacement_candidate"

first_state="$publish_test_root/first/state"
first_final="$first_state/config.json"
run_publisher "$first_state" "$first_final" "$valid_candidate"
cmp -s "$valid_candidate" "$first_final"
test "$("$coreutils_bin/stat" -c '%a' "$first_state")" = '700'
test "$("$coreutils_bin/stat" -c '%a' "$first_final")" = '600'
assert_no_publish_temps

printf '%s' 'old regular config' >"$first_final"
run_publisher "$first_state" "$first_final" "$replacement_candidate"
cmp -s "$replacement_candidate" "$first_final"
test "$("$coreutils_bin/stat" -c '%a' "$first_final")" = '600'
assert_no_publish_temps

missing_state="$publish_test_root/missing-candidate"
"$coreutils_bin/install" -d "$missing_state"
printf '%s' 'missing candidate sentinel' >"$missing_state/config.json"
if run_publisher \
  "$missing_state" \
  "$missing_state/config.json" \
  "$publish_test_root/does-not-exist.json" \
  2>/dev/null; then
  echo "publish helper accepted a missing candidate" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$missing_state/config.json")" = \
  'missing candidate sentinel'
assert_no_publish_temps

unreadable_state="$publish_test_root/unreadable-candidate"
unreadable_candidate="$publish_test_root/unreadable-candidate.json"
"$coreutils_bin/install" -d "$unreadable_state"
printf '%s' 'unreadable candidate sentinel' \
  >"$unreadable_state/config.json"
printf '%s' '{}' >"$unreadable_candidate"
"$coreutils_bin/chmod" 000 "$unreadable_candidate"
if run_publisher \
  "$unreadable_state" \
  "$unreadable_state/config.json" \
  "$unreadable_candidate" \
  2>/dev/null; then
  echo "publish helper accepted an unreadable candidate" >&2
  exit 1
fi
"$coreutils_bin/chmod" 0600 "$unreadable_candidate"
test "$("$coreutils_bin/cat" "$unreadable_state/config.json")" = \
  'unreadable candidate sentinel'
assert_no_publish_temps

invalid_json_state="$publish_test_root/invalid-json"
invalid_json_candidate="$publish_test_root/invalid-json-candidate.json"
"$coreutils_bin/install" -d "$invalid_json_state"
printf '%s' 'invalid JSON sentinel' \
  >"$invalid_json_state/config.json"
printf '%s' 'not JSON' >"$invalid_json_candidate"
if run_publisher \
  "$invalid_json_state" \
  "$invalid_json_state/config.json" \
  "$invalid_json_candidate" \
  >/dev/null 2>&1; then
  echo "publish helper accepted invalid JSON" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$invalid_json_state/config.json")" = \
  'invalid JSON sentinel'
assert_no_publish_temps

invalid_sing_box_state="$publish_test_root/invalid-sing-box"
invalid_sing_box_candidate="$publish_test_root/invalid-sing-box-candidate.json"
"$coreutils_bin/install" -d "$invalid_sing_box_state"
printf '%s' 'invalid sing-box sentinel' \
  >"$invalid_sing_box_state/config.json"
printf '%s' \
  '{"outbounds":[{"type":"not-a-type","tag":"invalid"}]}' \
  >"$invalid_sing_box_candidate"
if run_publisher \
  "$invalid_sing_box_state" \
  "$invalid_sing_box_state/config.json" \
  "$invalid_sing_box_candidate" \
  >/dev/null 2>&1; then
  echo "publish helper accepted invalid sing-box semantics" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$invalid_sing_box_state/config.json")" = \
  'invalid sing-box sentinel'
assert_no_publish_temps

state_target="$publish_test_root/state-target"
state_link="$publish_test_root/state-link"
"$coreutils_bin/install" -d -m 0755 "$state_target"
printf '%s' 'state target sentinel' >"$state_target/sentinel"
ln -s "$state_target" "$state_link"
if run_publisher \
  "$state_link" \
  "$state_link/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted a symlink state directory" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$state_target/sentinel")" = \
  'state target sentinel'
test "$("$coreutils_bin/stat" -c '%a' "$state_target")" = '755'
test ! -e "$state_target/config.json"
assert_no_publish_temps

state_file="$publish_test_root/state-file"
printf '%s' 'state file sentinel' >"$state_file"
if run_publisher \
  "$state_file" \
  "$state_file/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted a non-directory state path" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$state_file")" = 'state file sentinel'
assert_no_publish_temps

unexpected_state="$publish_test_root/unexpected"
if run_publisher \
  "$unexpected_state" \
  "$unexpected_state/other.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper accepted an unexpected final path" >&2
  exit 1
fi
test ! -e "$unexpected_state"
assert_no_publish_temps

directory_state="$publish_test_root/final-directory"
"$coreutils_bin/install" -d "$directory_state/config.json"
printf '%s' 'directory sentinel' \
  >"$directory_state/config.json/sentinel"
if run_publisher \
  "$directory_state" \
  "$directory_state/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper replaced a final directory" >&2
  exit 1
fi
test "$("$coreutils_bin/cat" "$directory_state/config.json/sentinel")" = \
  'directory sentinel'
assert_no_publish_temps

symlink_state="$publish_test_root/final-symlink"
symlink_target="$publish_test_root/final-symlink-target"
"$coreutils_bin/install" -d "$symlink_state"
printf '%s' 'final symlink sentinel' >"$symlink_target"
ln -s "$symlink_target" "$symlink_state/config.json"
if run_publisher \
  "$symlink_state" \
  "$symlink_state/config.json" \
  "$valid_candidate" \
  2>/dev/null; then
  echo "publish helper replaced a final symlink" >&2
  exit 1
fi
test -L "$symlink_state/config.json"
test "$("$coreutils_bin/cat" "$symlink_target")" = \
  'final symlink sentinel'
assert_no_publish_temps

instrumented_bin="$publish_test_root/instrumented-coreutils"
"$coreutils_bin/install" -d "$instrumented_bin"
for utility in install mktemp rm cat chmod; do
  ln -s "$coreutils_bin/$utility" "$instrumented_bin/$utility"
done

cat >"$instrumented_bin/mv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$MV_PATH_LOG"
exec "$REAL_MV" "$@"
SH
cat >"$publish_test_root/jq-validator" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$JQ_PATH_LOG"
exec "$REAL_JQ" "$@"
SH
cat >"$publish_test_root/sing-box-validator" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$3" >"$SING_BOX_PATH_LOG"
exec "$REAL_SING_BOX" "$@"
SH
"$coreutils_bin/chmod" 0755 \
  "$instrumented_bin/mv" \
  "$publish_test_root/jq-validator" \
  "$publish_test_root/sing-box-validator"

instrumented_state="$publish_test_root/instrumented-state"
instrumented_final="$instrumented_state/config.json"
export MV_PATH_LOG="$publish_test_root/mv-path.log"
export JQ_PATH_LOG="$publish_test_root/jq-path.log"
export SING_BOX_PATH_LOG="$publish_test_root/sing-box-path.log"
export REAL_MV="$coreutils_bin/mv"
export REAL_JQ="$jq_bin"
export REAL_SING_BOX="$sing_box_bin"
bash \
  "$publisher" \
  "$instrumented_state" \
  "$instrumented_final" \
  "$valid_candidate" \
  "$instrumented_bin" \
  "$publish_test_root/jq-validator" \
  "$publish_test_root/sing-box-validator"
jq_validated_path="$("$coreutils_bin/cat" "$JQ_PATH_LOG")"
sing_box_validated_path="$("$coreutils_bin/cat" "$SING_BOX_PATH_LOG")"
mv_source_path="$("$coreutils_bin/cat" "$MV_PATH_LOG")"
test "$jq_validated_path" = "$sing_box_validated_path"
test "$jq_validated_path" = "$mv_source_path"
case "$mv_source_path" in
  "$instrumented_state"/.config.json.*) ;;
  *)
    echo "validators and mv did not receive the publication temp" >&2
    exit 1
    ;;
esac
cmp -s "$valid_candidate" "$instrumented_final"
assert_no_publish_temps

post_activation="$(
  nix eval --raw \
    "$repo_dir#darwinConfigurations.mac.config.system.activationScripts.postActivation.text"
)"
secrets_line="$(
  printf '%s\n' "$post_activation" \
    | grep -n -m1 'Setting up secrets' \
    | cut -d: -f1
)"
validation_line="$(
  printf '%s\n' "$post_activation" \
    | grep -n -m1 'validating sing-box configuration' \
    | cut -d: -f1
)"
test "$secrets_line" -lt "$validation_line"

before_downgrade="${post_activation%%/usr/bin/sudo -u *}"
if printf '%s\n' "$before_downgrade" \
  | grep -Eq '/bin/(install|chown|chmod|mktemp|mv|cat|jq|sing-box)([[:space:]]|$)'; then
  echo "root activation reads the candidate or mutates the user home" >&2
  exit 1
fi
publication_block="${post_activation#*validating sing-box configuration}"
if printf '%s\n' "$publication_block" | grep -Fq '|'; then
  echo "activation pipes candidate content across the user boundary" >&2
  exit 1
fi
printf '%s\n' "$post_activation" \
  | grep -F '/usr/bin/sudo -u rich --' >/dev/null
printf '%s\n' "$post_activation" \
  | grep -F -- '-publish-sing-box-config.sh' >/dev/null

trap - EXIT
cleanup_publish_tests

printf '%s\n' "sing-box static checks passed"
