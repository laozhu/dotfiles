#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  printf 'Usage: %s [--update|-u]\n' "${0##*/}" >&2
}

update_inputs=false
case "$#" in
  0)
    ;;
  1)
    case "$1" in
      -u | --update)
        update_inputs=true
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    ;;
  *)
    usage
    exit 2
    ;;
esac

source "$DIR/scripts/profile.sh"
PROFILE="$(dotfiles_profile)"
echo "==> Machine profile: $PROFILE (shared + $PROFILE)"
source "$DIR/scripts/nix-cache-env.sh"

"$DIR/scripts/check-sops-age-key.sh"

if [ "$update_inputs" = true ]; then
  # Updating without input names also contacts work-only providers on a home Mac.
  input_names="$(jq -er '.nodes[.root].inputs | keys[]' "$DIR/flake.lock")"
  update_targets=()
  while IFS= read -r input_name; do
    case "$PROFILE:$input_name" in
      home:atlassian-tap | home:nordpass-tap | home:temporal-tap) continue ;;
    esac
    update_targets+=("$input_name")
  done <<<"$input_names"
  if [ "${#update_targets[@]}" -eq 0 ]; then
    echo "No inputs selected for $PROFILE; refusing to update all inputs." >&2
    exit 2
  fi
  nix flake update --flake "$DIR" "${update_targets[@]}"
  bash "$DIR/scripts/update-macos-binaries.sh"
fi

# 使用即将安装的内核校验，避免旧版本拒绝升级后的配置格式。
target_sing_box="$(
  nix build --no-link --print-out-paths \
    "$DIR#darwinConfigurations.$PROFILE.pkgs.sing-box"
)"
PATH="$target_sing_box/bin:$PATH" "$DIR/scripts/check-sing-box-config.sh"

if [ "$PROFILE" = home ]; then
  homebrew_cask_source="$(
    DOTFILES_REBUILD_FLAKE="path:$DIR" nix eval \
      --raw \
      --impure \
      --expr \
      '(builtins.getFlake (builtins.getEnv "DOTFILES_REBUILD_FLAKE")).inputs.homebrew-cask.outPath'
  )"
  "$DIR/scripts/prefetch-uu-booster.sh" \
    "$homebrew_cask_source/Casks/u/uu-booster.rb"
fi

# 共享配置通过 Homebrew cask 安装或升级 Codex 官方 macOS 二进制。
sudo --preserve-env=NIX_CONFIG darwin-rebuild switch --flake "$DIR#$PROFILE"

# IDE 配置与插件属于当前用户，必须在系统应用安装完成后执行。
bash "$DIR/scripts/sync-editors.sh"

# rustup 工具链不在 flake.lock 中，随 --update 一起升级；激活已确保存在默认工具链。
if [ "$update_inputs" = true ]; then
  rustup update
fi

echo "==> Done. Open a new terminal to load updated PATH and shell settings."
