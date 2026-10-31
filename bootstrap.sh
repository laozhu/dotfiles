#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Validate selection before any installation or system changes.
source "$DIR/scripts/profile.sh"
case "$#" in
  0) PROFILE="$(dotfiles_profile)" ;;
  2)
    if [ "$1" != --profile ]; then
      echo 'Usage: bootstrap.sh [--profile home|work]' >&2
      exit 2
    fi
    PROFILE="$(dotfiles_profile "$2")"
    ;;
  *)
    echo 'Usage: bootstrap.sh [--profile home|work]' >&2
    exit 2
    ;;
esac
echo "==> Machine profile: $PROFILE (shared + $PROFILE)"
source "$DIR/scripts/nix-cache-env.sh"

echo "==> Configure the machine name (first run only)"
MACHINE_NAME_FILE="$HOME/.config/dotfiles/hostname"
if [ -f "$MACHINE_NAME_FILE" ]; then
  echo "    Machine name already configured, skipping"
else
  while true; do
    if ! read -r -p "    Computer name (e.g. rich-macbook, without .local): " MACHINE_NAME; then
      echo '    A computer name is required. Run bootstrap again in an interactive terminal.' >&2
      exit 1
    fi
    if [ "${#MACHINE_NAME}" -le 63 ] &&
      [[ "$MACHINE_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
      break
    fi
    echo '    Use 1-63 ASCII letters, digits or hyphens; start and end with a letter or digit.' >&2
  done
  sudo scutil --set ComputerName "$MACHINE_NAME"
  sudo scutil --set LocalHostName "$MACHINE_NAME"
  sudo scutil --set HostName "$MACHINE_NAME"
  mkdir -p "$(dirname "$MACHINE_NAME_FILE")"
  printf '%s\n' "$MACHINE_NAME" >"$MACHINE_NAME_FILE"
fi

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
# Resolve this as the real interactive user, outside sudo (which resets $USER
# to root).
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: install Rosetta 2 on Apple Silicon"
if [ "$(uname -m)" != "arm64" ]; then
  echo "    not an Apple Silicon Mac, skipping"
elif pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
  echo "    Rosetta 2 already installed, skipping"
else
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license
fi

# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
NIX_BIN="$(command -v nix)"

echo "==> Step 5: validate the SOPS age identity"
"$NIX_BIN" shell nixpkgs#age nixpkgs#sops --command \
  "$DIR/scripts/check-sops-age-key.sh"

echo "==> Step 6: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
# 共享配置安装固定的官方 macOS CLI 二进制；Codex 使用 Homebrew cask。
# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still pinned
# by this repo's flake.lock.
sudo --preserve-env=NIX_CONFIG "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$DIR#$PROFILE"
# If this still fails with "nix: command not found", open a new terminal
# (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Step 7: sync IDE settings and extensions"
# IDE 配置与插件属于当前用户，必须在系统应用安装完成后执行。
# 首次 switch 不会更新当前终端的 PATH，显式提供刚安装的 Node、jq 等工具。
PATH="/etc/profiles/per-user/$REAL_USER/bin:/run/current-system/sw/bin:$PATH" \
  bash "$DIR/scripts/sync-editors.sh"

echo "==> Done. Open a new terminal to load Python/Java PATH and shell settings. Use ./rebuild.sh for future changes."
