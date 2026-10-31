#!/usr/bin/env bash
# Evaluate the pinned formulae with the actual Nix-managed Brew engine, without installing.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
setup_text="$(DOTFILES_TEST_FLAKE="path:$repo_dir" nix build --no-link --print-out-paths --impure --expr '
  let host = (builtins.getFlake (builtins.getEnv "DOTFILES_TEST_FLAKE")).darwinConfigurations.home;
  in host.pkgs.writeText "homebrew-setup-test" host.config.system.activationScripts.setup-homebrew.text
')"
setup_script="$(sed -nE '\|^/nix/store/[^ ]+-setup-homebrew$|p' "$setup_text")"
brew_code="$(sed -nE 's|^/bin/ln -shf "([^"]+)/Library/Homebrew".*|\1|p' "$setup_script")"
test -d "$brew_code/Library/Homebrew"
core="$(DOTFILES_TEST_FLAKE="path:$repo_dir" nix eval --raw --impure --expr \
  '(builtins.getFlake (builtins.getEnv "DOTFILES_TEST_FLAKE")).inputs.homebrew-core.outPath')"
mkdir -p "$fixture/bin" "$fixture/Library/Taps/homebrew" "$fixture/cache" "$fixture/logs"
cp "$brew_code/bin/brew" "$fixture/bin/brew"
ln -s "$brew_code/Library/Homebrew" "$fixture/Library/Homebrew"
ln -s "$core" "$fixture/Library/Taps/homebrew/homebrew-core"
# The isolated prefix uses nix-homebrew's patched Ruby, never the system Brew installation.
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_INSTALL_FROM_API=1 \
  HOMEBREW_CACHE="$fixture/cache" HOMEBREW_LOGS="$fixture/logs" \
  "$fixture/bin/brew" deps --tree openjdk gradle >"$fixture/dependencies" 2>"$fixture/errors" || {
  cat "$fixture/errors" >&2
  exit 1
}
grep -Fq harfbuzz "$fixture/dependencies"
