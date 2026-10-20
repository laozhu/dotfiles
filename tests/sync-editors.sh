#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
jq_cli="$(command -v jq)"
mkdir -p "$fixture/repo/scripts" "$fixture/bin" "$fixture/home"
cp "$repo_dir/scripts/sync-editors.sh" "$fixture/repo/scripts/"
mkdir -p "$fixture/repo/home"
cp -R "$repo_dir/home/ide" "$fixture/repo/home/"
# Real file operations, with marketplace calls replaced to avoid downloads.
cat > "$fixture/bin/code" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
editor="${0##*/}"
if [ "$editor" = cli.js ]; then editor=antigravity-ide; fi
printf '%s' "$editor" >> "$EDITOR_TEST_LOG"
printf ' %s' "$@" >> "$EDITOR_TEST_LOG"
printf '\n' >> "$EDITOR_TEST_LOG"
case "$1" in
  --list-extensions)
    if [ "${EDITOR_TEST_LIST_FAIL:-}" = "$editor" ]; then exit 24; fi
    cat "$EDITOR_TEST_STATE/$editor"
    ;;
  --install-extension)
    if [ "${EDITOR_TEST_FAIL:-}" = "$editor" ]; then exit 23; fi
    if grep -Fxiq -- "$2" "$EDITOR_TEST_STATE/$editor"; then
      echo 'attempted to reinstall an existing extension' >&2
      exit 25
    fi
    printf '%s\n' "$2" >> "$EDITOR_TEST_STATE/$editor"
    ;;
  *) exit 26 ;;
esac
CLI
# Simulate an Electron launcher that crashes, while its CLI works under Node.
agy_app="$fixture/Antigravity IDE.app/Contents/Resources/app"
mkdir -p "$agy_app/bin" "$agy_app/out"
cp "$fixture/bin/code" "$agy_app/out/cli.js"
cat > "$agy_app/bin/antigravity-ide" <<'CLI'
#!/usr/bin/env bash
echo 'Electron launcher must not be used' >&2
exit 134
CLI
ln -s "$agy_app/bin/antigravity-ide" "$fixture/bin/antigravity-ide"
cat > "$fixture/bin/node" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
test -z "${ELECTRON_RUN_AS_NODE:-}"
exec bash "$@"
CLI
ln -s "$jq_cli" "$fixture/bin/jq"
chmod +x "$fixture/bin/"*
export EDITOR_TEST_LOG="$fixture/calls"
export EDITOR_TEST_STATE="$fixture/installed"
mkdir -p "$EDITOR_TEST_STATE"
# Real extension IDs are case insensitive.
printf 'BRADLC.vscode-tailwindcss\n' > "$EDITOR_TEST_STATE/code"
printf 'bradlc.vscode-tailwindcss\n' > "$EDITOR_TEST_STATE/antigravity-ide"
export HOME="$fixture/home"
export PATH="$fixture/bin:/usr/bin:/bin"
code_settings="$HOME/Library/Application Support/Code/User/settings.json"
agy_settings="$HOME/Library/Application Support/Antigravity IDE/User/settings.json"
mkdir -p "$(dirname "$code_settings")"
printf '{"custom":true}\n' > "$code_settings"
cp "$code_settings" "$fixture/original"
ELECTRON_RUN_AS_NODE=1 bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null
cmp "$fixture/repo/home/ide/settings.json" "$code_settings"
cmp "$code_settings" "$agy_settings"
backups=("$code_settings".backup.*)
test "${#backups[@]}" = 1
cmp "$fixture/original" "${backups[0]}"
# Both editors must receive every shared plugin, and VS Code needs the theme.
while IFS= read -r extension; do
  grep -Fxiq -- "$extension" "$EDITOR_TEST_STATE/code"
  grep -Fxiq -- "$extension" "$EDITOR_TEST_STATE/antigravity-ide"
done < <(jq -r '.recommendations[]' "$fixture/repo/home/ide/extensions.json")
grep -Fxq 'code --install-extension enkia.tokyo-night' "$EDITOR_TEST_LOG"
: > "$EDITOR_TEST_LOG"
bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null
if grep -Fq -- '--install-extension' "$EDITOR_TEST_LOG"; then
  echo 'sync reinstalled existing extensions' >&2
  exit 1
fi
backups=("$code_settings".backup.*)
test "${#backups[@]}" = 1
# Replacing a symlink must preserve its old target and back up its contents.
cp "$fixture/original" "$fixture/target"
rm "$agy_settings"
ln -s "$fixture/target" "$agy_settings"
bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null
cmp "$fixture/original" "$fixture/target"
test ! -L "$agy_settings"
cmp "$code_settings" "$agy_settings"
# A failed marketplace install must fail the sync but still try the other IDE.
sed '/vscodevim.vim/d' "$EDITOR_TEST_STATE/code" > "$fixture/without-vim"
cp "$fixture/without-vim" "$EDITOR_TEST_STATE/code"
: > "$EDITOR_TEST_LOG"
if EDITOR_TEST_FAIL=code bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null 2>&1; then
  echo 'sync ignored extension installation failure' >&2
  exit 1
fi
grep -Fxq 'antigravity-ide --list-extensions' "$EDITOR_TEST_LOG"
# A failed listing must not be mistaken for an empty installed list.
: > "$EDITOR_TEST_LOG"
if EDITOR_TEST_LIST_FAIL=code bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null 2>&1; then
  echo 'sync ignored extension listing failure' >&2
  exit 1
fi
if grep -Fq 'code --install-extension ' "$EDITOR_TEST_LOG"; then
  echo 'sync installed extensions after a failed listing' >&2
  exit 1
fi
grep -Fxq 'antigravity-ide --list-extensions' "$EDITOR_TEST_LOG"

# Invalid recommendations must fail before changing settings or installing plugins.
printf '{"recommendations": "oxc.oxc-vscode"}\n' > "$fixture/repo/home/ide/extensions.json"
printf '{"keep":true}\n' > "$code_settings"
cp "$code_settings" "$fixture/keep"
: > "$EDITOR_TEST_LOG"
if bash "$fixture/repo/scripts/sync-editors.sh" > /dev/null 2>&1; then
  echo 'sync accepted invalid recommendations' >&2
  exit 1
fi
cmp "$fixture/keep" "$code_settings"
test ! -s "$EDITOR_TEST_LOG"
