#!/usr/bin/env bash
set -euo pipefail

download_page='https://adl.netease.com/d/g/uu/c/uumac?type=pc'

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  printf 'Usage: %s /path/to/uu-booster.rb\n' "${0##*/}" >&2
  exit 2
fi
cask_file="$1"

for command in brew curl sed shasum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

version="$(
  sed -n 's/^[[:space:]]*version "\([^"]*\)".*/\1/p' "$cask_file" |
    head -n 1
)"
expected_sha="$(
  sed -n 's/^[[:space:]]*sha256 "\([^"]*\)".*/\1/p' "$cask_file" |
    head -n 1
)"
declared_url="$(
  sed -n 's/^[[:space:]]*url "\([^"]*\)".*/\1/p' "$cask_file" |
    head -n 1
)"
expected_declared_url='https://uu.gdl.netease.com/UU-macOS-#{version}.dmg'

if [ "$declared_url" != "$expected_declared_url" ]; then
  printf 'Homebrew 的 UU Booster cask 已更改下载方式，跳过 403 兼容处理。\n'
  exit 0
fi
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+([.][0-9]+)+$' ||
  ! printf '%s\n' "$expected_sha" | grep -Eq '^[0-9a-f]{64}$'; then
  printf '无法从即将激活的 UU Booster cask 读取版本或 SHA-256。\n' >&2
  exit 1
fi

cask_url="https://uu.gdl.netease.com/UU-macOS-${version}.dmg"
url_sha="$(printf '%s' "$cask_url" | shasum -a 256)"
url_sha="${url_sha%% *}"
cache_root="$(brew --cache)"
cache_path="$cache_root/downloads/${url_sha}--UU-macOS-${version}.dmg"

if [ -f "$cache_path" ]; then
  cached_sha="$(shasum -a 256 "$cache_path")"
  cached_sha="${cached_sha%% *}"
  if [ "$cached_sha" = "$expected_sha" ]; then
    printf 'UU Booster is already present in Homebrew cache.\n'
    exit 0
  fi
fi

download_url="$(
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry=3 \
    --connect-timeout=15 \
    --proto '=https' \
    --proto-redir '=https' \
    "$download_page" |
    sed -n 's/.*var pc_link = "\([^"]*\)".*/\1/p'
)"

case "$download_url" in
  "https://uu.gdl.netease.com/UU-macOS-${version}.dmg?type=pc&key1="*"&key2="*)
    ;;
  *)
    printf '网易官网返回了无效的 UU 加速器下载地址。\n' >&2
    exit 1
    ;;
esac

if [ ! -d "$(dirname "$cache_path")" ]; then
  mkdir -p "$(dirname "$cache_path")"
fi
temporary_path="${cache_path}.incomplete.$$"
cleanup() {
  rm -f "$temporary_path"
}
trap cleanup EXIT

curl \
  --fail \
  --location \
  --show-error \
  --retry=3 \
  --connect-timeout=15 \
  --proto '=https' \
  --proto-redir '=https' \
  --output "$temporary_path" \
  "$download_url"

downloaded_sha="$(shasum -a 256 "$temporary_path")"
downloaded_sha="${downloaded_sha%% *}"
if [ "$downloaded_sha" != "$expected_sha" ]; then
  printf 'UU 加速器下载文件的 SHA-256 与 Homebrew cask 不一致。\n' >&2
  exit 1
fi

mv -f "$temporary_path" "$cache_path"
trap - EXIT
printf 'UU Booster has been added to Homebrew cache.\n'
