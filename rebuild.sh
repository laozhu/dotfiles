cd ~/.dotfiles

# 解析参数
UPDATE_ALL=false
TARGET=""

for arg in "$@"; do
  if [ "$arg" == "--update" ] || [ "$arg" == "-u" ]; then
    UPDATE_ALL=true
  else
    TARGET="$arg"
  fi
done

TARGET=${TARGET:-mac-desktop}

if [ "$UPDATE_ALL" = true ]; then
  echo "🚀 正在更新所有 Flake Inputs (nixpkgs, llm-agents, homebrew)..."
  nix flake update
fi

git add .

echo "🛠️ 正在重建 Nix 配置目标: $TARGET ..."
exec sudo darwin-rebuild switch --flake ~/.dotfiles#$TARGET
