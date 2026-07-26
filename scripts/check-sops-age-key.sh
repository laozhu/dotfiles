#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
identity_dir="$HOME/Library/Application Support/sops/age"
identity_file="$identity_dir/keys.txt"
# Keep the tilde literal for the documented, user-facing recovery path.
# shellcheck disable=SC2088
identity_display='~/Library/Application Support/sops/age/keys.txt'
sops_config="$repo_dir/.sops.yaml"
encrypted_secrets="$repo_dir/secrets/sing-box.yaml"
bitwarden_item='dotfiles - sops age identity'

print_recovery_hint() {
  printf '%s\n' \
    "Bitwarden item: $bitwarden_item" \
    "Expected path: $identity_display" >&2
}

if [ ! -d "$identity_dir" ] || [ ! -f "$identity_file" ]; then
  print_recovery_hint
  exit 1
fi

if ! directory_mode="$(stat -f '%Lp' "$identity_dir" 2>/dev/null)"; then
  printf 'Could not read permissions for: %s\n' "$identity_dir" >&2
  exit 1
fi
if [ "$directory_mode" != '700' ]; then
  printf '%s\n' \
    "Path: $identity_dir" \
    'Expected permissions: 700' \
    "Actual permissions: $directory_mode" >&2
  exit 1
fi

if ! identity_mode="$(stat -f '%Lp' "$identity_file" 2>/dev/null)"; then
  printf 'Could not read permissions for: %s\n' "$identity_file" >&2
  exit 1
fi
if [ "$identity_mode" != '600' ]; then
  printf '%s\n' \
    "Path: $identity_file" \
    'Expected permissions: 600' \
    "Actual permissions: $identity_mode" >&2
  exit 1
fi

if [ ! -f "$sops_config" ]; then
  printf 'Expected path: %s\n' "$sops_config" >&2
  exit 1
fi
if [ ! -f "$encrypted_secrets" ]; then
  printf 'Expected path: %s\n' "$encrypted_secrets" >&2
  exit 1
fi

repository_recipients="$(
  awk '{
    for (field = 1; field <= NF; field++) {
      if ($field ~ /^age1[0-9a-z]+$/) {
        print $field
      }
    }
  }' "$sops_config" 2>/dev/null
)"
recipient_count="$(
  printf '%s\n' "$repository_recipients" \
    | awk '/^age1[0-9a-z]+$/ { count++ } END { print count + 0 }'
)"
if [ "$recipient_count" != '1' ]; then
  printf 'Expected one repository recipient in: %s\n' "$sops_config" >&2
  exit 1
fi

if ! identity_recipient="$(
  age-keygen -y "$identity_file" 2>/dev/null
)"; then
  printf 'Could not validate identity at: %s\n' "$identity_display" >&2
  exit 1
fi
if [ "$identity_recipient" != "$repository_recipients" ]; then
  printf '%s\n' \
    'Identity does not match the repository recipient.' \
    "Path: $identity_display" \
    "Bitwarden item: $bitwarden_item" >&2
  exit 1
fi

if ! sops decrypt "$encrypted_secrets" >/dev/null 2>&1; then
  printf '%s\n' \
    "Could not decrypt: $encrypted_secrets" \
    "Path: $identity_display" \
    "Bitwarden item: $bitwarden_item" >&2
  exit 1
fi
