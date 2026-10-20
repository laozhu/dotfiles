#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
nix eval --json "$repo_dir#darwinConfigurations.mac.pkgs" --apply '
  pkgs: map (name: {
    inherit name;
    binaryRelease = pkgs.${name}.binaryRelease or false;
  }) [ "pnpm" "bws" "herdr" "kimi-code" "pi" "sing-box" "uv" ]
' | jq -e 'all(.binaryRelease == true)' >/dev/null
# Codex must use the official macOS release cask, never a Rust source build.
nix eval --json "$repo_dir#darwinConfigurations.mac.config" --apply '
  config: {
    casks = map (cask: cask.name) config.homebrew.casks;
    brews = map (brew: brew.name) config.homebrew.brews;
    upgrade = config.homebrew.onActivation.upgrade;
    packages = builtins.concatLists (map
      (home: map (package: package.pname or package.name) home.home.packages)
      (builtins.attrValues config.home-manager.users));
  }
' | jq -e '
  (.casks | index("codex") != null) and
  (.brews | index("daipeihust/tap/im-select") != null) and
  .upgrade == true and
  ([.packages[] | select(test("^codex($|-)"))] | length == 0)
' >/dev/null
grep -Fq 'darwinConfigurations.mac' "$repo_dir/flake.nix"
nix eval --json \
  "$repo_dir#darwinConfigurations.mac.config.nix-homebrew.taps" |
  jq -e '
    keys == [
      "daipeihust/homebrew-tap",
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

