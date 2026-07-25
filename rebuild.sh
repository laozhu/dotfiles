#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# 确保软链接存在
ln -sfn "$DIR" ~/.dotfiles

# 核心修复：进入目录并将所有改动加入 Git 索引，确保 Flake 能读取到最新状态
cd ~/.dotfiles
git add .

TARGET=${1:-mac-laptop}
echo "正在重建 Nix 配置目标: $TARGET ..."

# 运行 darwin-rebuild
exec sudo darwin-rebuild switch --flake ~/.dotfiles#$TARGET
