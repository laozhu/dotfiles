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

