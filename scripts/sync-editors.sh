#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_dir="$repo_dir/home/ide"

# Prefer PATH, falling back to the cask CLI when no shell command is linked.
code_cli="$(command -v code || true)"
agy_cli="$(command -v antigravity-ide || true)"
code_cli="${code_cli:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
agy_cli="${agy_cli:-/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide}"
for cli in "$code_cli" "$agy_cli"; do
  if [ ! -x "$cli" ]; then
    printf 'IDE CLI not found: %s\n' "$cli" >&2
    exit 1
  fi
done

# Antigravity's Electron runtime can abort in its ESM loader, even when listing
# extensions. Run the same bundled CLI with the Node installed by Home Manager.
agy_resolved="$agy_cli"
while [ -L "$agy_resolved" ]; do
  agy_link="$(readlink "$agy_resolved")"
  case "$agy_link" in
    /*) agy_resolved="$agy_link" ;;
    *) agy_resolved="$(dirname "$agy_resolved")/$agy_link" ;;
  esac
done
agy_node_cli="$(dirname "$agy_resolved")/../out/cli.js"
if [ ! -f "$agy_node_cli" ]; then
  printf 'Antigravity CLI entry point not found: %s\n' "$agy_node_cli" >&2
  exit 1
fi
node_cli="$(command -v node)"

run_cli() {
  local cli="$1"
  shift
  if [ "$cli" = "$agy_cli" ]; then
    env -u ELECTRON_RUN_AS_NODE "$node_cli" "$agy_node_cli" "$@"
  else
    "$cli" "$@"
  fi
}

read_recommendations() {
  jq -r '
    if (.recommendations | type == "array" and all(.[]; type == "string"))
    then .recommendations[]
    else error("recommendations must be an array of extension IDs")
    end
  ' "$1"
}

# Parse before modifying settings so invalid manifests fail without side effects.
shared_extensions="$(read_recommendations "$config_dir/extensions.json")"
vscode_extensions="$(read_recommendations "$config_dir/vscode/extensions.json")"

for app in 'Code' 'Antigravity IDE'; do
  settings="$HOME/Library/Application Support/$app/User/settings.json"
  mkdir -p "$(dirname "$settings")"
  if cmp -s "$config_dir/settings.json" "$settings"; then
    continue
  fi
  if [ -e "$settings" ] || [ -L "$settings" ]; then
    backup="$(mktemp "$settings.backup.XXXXXX")"
    cp -p "$settings" "$backup"
    printf 'Backed up %s to %s\n' "$settings" "$backup"
  fi
  # Replace the file atomically, preserving any previous symlink's target.
  temporary="$(mktemp "$settings.tmp.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT
  cp "$config_dir/settings.json" "$temporary"
  mv -f "$temporary" "$settings"
  trap - EXIT
  printf 'Updated %s\n' "$settings"
done

status=0
install_extensions() {
  local cli="$1" extensions="$2" extension installed
  if ! installed="$(run_cli "$cli" --list-extensions)"; then
    printf 'Failed to list installed extensions with %s\n' "$cli" >&2
    status=1
    return
  fi
  while IFS= read -r extension || [ -n "$extension" ]; do
    [ -n "$extension" ] || continue
    if grep -Fxiq -- "$extension" <<< "$installed"; then
      printf 'Already installed: %s\n' "$extension"
      continue
    fi
    if ! run_cli "$cli" --install-extension "$extension"; then
      printf 'Failed to install %s with %s\n' "$extension" "$cli" >&2
      status=1
    fi
  done <<< "$extensions"
}

install_extensions "$code_cli" "$shared_extensions"$'\n'"$vscode_extensions"
install_extensions "$agy_cli" "$shared_extensions"
exit "$status"
