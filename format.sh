#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
mode="${1:---write}"
if [ "$#" -gt 1 ] || { [ "$mode" != --write ] && [ "$mode" != --check ]; }; then
  echo "Usage: ${0##*/} [--check|--write]" >&2
  exit 2
fi

# Use the same locked formatter versions locally and in CI, without installing them globally.
if [ "${DOTFILES_FORMAT_TOOLS:-}" != 1 ]; then
  exec nix shell --max-jobs 0 --inputs-from "$repo_dir" \
    nixpkgs#oxfmt nixpkgs#shfmt nixpkgs#nixfmt nixpkgs#stylua \
    --command env DOTFILES_FORMAT_TOOLS=1 bash "$repo_dir/format.sh" "$mode"
fi

cd "$repo_dir"
shell_files=()
oxfmt_files=()
nix_files=()
lua_files=()

# Include new, non-ignored files, but never follow links or rewrite generated files.
while IFS= read -r -d '' file; do
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  case "$file" in
    secrets/* | flake.lock | */lazy-lock.json | macos-binaries.json | CHANGELOG.md | */CHANGELOG.md) continue ;;
    *.sh) shell_files+=("$file") ;;
    *.yaml | *.yml | *.json | *.jsonc | *.md | *.toml | *.js | *.mjs | *.cjs | *.jsx | *.ts | *.tsx)
      oxfmt_files+=("$file")
      ;;
    *.nix) nix_files+=("$file") ;;
    *.lua) lua_files+=("$file") ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)

shfmt_options=(-w -i 2 -ci)
nixfmt_options=()
stylua_options=(--indent-type Spaces --indent-width 2)
if [ "$mode" = --check ]; then
  shfmt_options=(-d -i 2 -ci)
  nixfmt_options=(--check)
  stylua_options+=(--check)
fi

status=0
if [ "${#shell_files[@]}" -gt 0 ]; then
  shfmt "${shfmt_options[@]}" "${shell_files[@]}" || status=1
fi
if [ "${#oxfmt_files[@]}" -gt 0 ]; then
  oxfmt "$mode" "${oxfmt_files[@]}" || status=1
fi
if [ "${#nix_files[@]}" -gt 0 ]; then
  nixfmt "${nixfmt_options[@]}" "${nix_files[@]}" || status=1
fi
if [ "${#lua_files[@]}" -gt 0 ]; then
  stylua "${stylua_options[@]}" "${lua_files[@]}" || status=1
fi
exit "$status"
