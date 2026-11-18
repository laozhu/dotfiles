#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_dir="$repo_dir/home/ide"

# Prefer PATH, falling back to the cask CLI when no shell command is linked.
code_cli="$(command -v code || true)"
agy_cli="$(command -v antigravity-ide || true)"
cursor_cli="$(command -v cursor || true)"
code_cli="${code_cli:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
agy_cli="${agy_cli:-/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide}"
cursor_cli="${cursor_cli:-/Applications/Cursor.app/Contents/Resources/app/bin/cursor}"
for cli in "$code_cli" "$agy_cli" "$cursor_cli"; do
  if [ ! -x "$cli" ]; then
    printf 'IDE CLI not found: %s\n' "$cli" >&2
    exit 1
  fi
done

# Use each editor's bundled runtime. Running Antigravity under the system Node
# can hang during VSIX extraction (Node 26), even after a successful download.
# Cursor's runtime prints a Node url.parse() deprecation on every marketplace call
# and ignores NODE_OPTIONS; drop only those two lines and keep other stderr.
cli_noise='^\(node:[0-9]+\) \[DEP0169\] DeprecationWarning: |^\(Use `[^`]+ --trace-deprecation \.\.\.` to show where the warning was created\)$'
run_cli() {
  local cli="$1" rc=0
  shift
  { "$cli" "$@" 2>&1 1>&3 3>&- | { grep -Ev "$cli_noise" || true; } >&2; } 3>&1 || rc=$?
  return "$rc"
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
cursor_extensions="$(read_recommendations "$config_dir/cursor/extensions.json")"

# Cursor layers its own settings over the shared file; render them up front.
rendered_dir="$(mktemp -d)"
trap 'rm -rf "$rendered_dir"' EXIT
jq -s '.[0] * .[1]' "$config_dir/settings.json" "$config_dir/cursor/settings.json" \
  >"$rendered_dir/cursor.json"

for app in 'Code' 'Antigravity IDE' 'Cursor'; do
  settings="$HOME/Library/Application Support/$app/User/settings.json"
  desired="$config_dir/settings.json"
  if [ "$app" = Cursor ]; then
    desired="$rendered_dir/cursor.json"
  fi
  mkdir -p "$(dirname "$settings")"
  if cmp -s "$desired" "$settings"; then
    continue
  fi
  if [ -e "$settings" ] || [ -L "$settings" ]; then
    backup="$(mktemp "$settings.backup.XXXXXX")"
    cp -p "$settings" "$backup"
    printf 'Backed up %s to %s\n' "$settings" "$backup"
  fi
  # Replace the file atomically, preserving any previous symlink's target.
  temporary="$(mktemp "$settings.tmp.XXXXXX")"
  trap 'rm -f "$temporary"; rm -rf "$rendered_dir"' EXIT
  cp "$desired" "$temporary"
  mv -f "$temporary" "$settings"
  trap 'rm -rf "$rendered_dir"' EXIT
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
  # Only stdout contains extension IDs; Antigravity may emit harmless analytics
  # warnings on stderr. Reject unexpected stdout without mixing the streams.
  if [ -n "$installed" ] && printf '%s\n' "$installed" | grep -Evq '^[[:alnum:]_-]+\.[[:alnum:]_.-]+$'; then
    printf 'Invalid extension list from %s:\n%s\n' "$cli" "$installed" >&2
    status=1
    return
  fi
  while IFS= read -r extension || [ -n "$extension" ]; do
    [ -n "$extension" ] || continue
    if grep -Fxiq -- "$extension" <<<"$installed"; then
      printf 'Already installed: %s\n' "$extension"
      continue
    fi
    if ! run_cli "$cli" --install-extension "$extension"; then
      printf 'Failed to install %s with %s\n' "$extension" "$cli" >&2
      status=1
      continue
    fi
    # Extension packs install their members too; refresh to skip them below.
    installed="$(run_cli "$cli" --list-extensions)" || installed+=$'\n'"$extension"
  done <<<"$extensions"
}

install_extensions "$code_cli" "$shared_extensions"$'\n'"$vscode_extensions"
install_extensions "$agy_cli" "$shared_extensions"
install_extensions "$cursor_cli" "$shared_extensions"$'\n'"$cursor_extensions"
exit "$status"
