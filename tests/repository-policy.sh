#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
grep -Fq 'darwinConfigurations.mac' "$repo_dir/flake.nix"
nix eval --json \
  "$repo_dir#darwinConfigurations.mac.config.nix-homebrew.taps" |
  jq -e '
    keys == [
      "homebrew/homebrew-cask",
      "homebrew/homebrew-core",
      "stablyai/homebrew-orca"
    ]
  ' >/dev/null
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

