#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture"
source "$repo_dir/scripts/profile.sh"
if dotfiles_profile >/dev/null 2>&1; then
  echo 'missing profile must fail' >&2
  exit 1
fi
test "$(dotfiles_profile home)" = home
test "$(cat "$HOME/.config/dotfiles/profile")" = home
test "$(dotfiles_profile)" = home
if dotfiles_profile work >/dev/null 2>&1; then
  echo 'profile mismatch must fail' >&2
  exit 1
fi
test "$(dotfiles_profile)" = home
printf 'invalid\n' >"$HOME/.config/dotfiles/profile"
if dotfiles_profile >/dev/null 2>&1; then exit 1; fi
printf 'home\nwork\n' >"$HOME/.config/dotfiles/profile"
if dotfiles_profile >/dev/null 2>&1; then exit 1; fi
rm "$HOME/.config/dotfiles/profile"
if dotfiles_profile invalid >/dev/null 2>&1; then exit 1; fi
