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
cat >"$fixture/bin/code" <<'CLI'
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
    if [ "${EDITOR_TEST_LIST_DIAGNOSTIC:-}" = "$editor" ]; then
      echo '[createInstance] extensionManagementService depends on antigravityAnalytics which is NOT registered.' >&2
    fi
    cat "$EDITOR_TEST_STATE/$editor"
    ;;
  --install-extension)
    if [ "${EDITOR_TEST_FAIL:-}" = "$editor" ]; then exit 23; fi
    # Mimic Cursor's runtime deprecation noise on marketplace calls.
    echo "(node:123) [DEP0169] DeprecationWarning: \`url.parse()\` behavior is not standardized." >&2
    echo '(Use `Cursor --trace-deprecation ...` to show where the warning was created)' >&2
    if grep -Fxiq -- "$2" "$EDITOR_TEST_STATE/$editor"; then
      echo 'attempted to reinstall an existing extension' >&2
      exit 25
    fi
    printf '%s\n' "$2" >> "$EDITOR_TEST_STATE/$editor"
    # ms-toolsai.jupyter is an extension pack that installs its members too.
    if [ "$2" = ms-toolsai.jupyter ]; then
      printf 'ms-toolsai.jupyter-keymap\nms-toolsai.jupyter-renderers\n' >> "$EDITOR_TEST_STATE/$editor"
    fi
    ;;
  *) exit 26 ;;
esac
CLI
# Exercise the official launcher path rather than substituting system Node.
cp "$fixture/bin/code" "$fixture/bin/antigravity-ide"
cp "$fixture/bin/code" "$fixture/bin/cursor"
ln -s "$jq_cli" "$fixture/bin/jq"
chmod +x "$fixture/bin/"*
export EDITOR_TEST_LOG="$fixture/calls"
export EDITOR_TEST_STATE="$fixture/installed"
mkdir -p "$EDITOR_TEST_STATE"
# Real extension IDs are case insensitive.
printf 'BRADLC.vscode-tailwindcss\n' >"$EDITOR_TEST_STATE/code"
printf 'bradlc.vscode-tailwindcss\n' >"$EDITOR_TEST_STATE/antigravity-ide"
printf 'anysphere.remote-ssh\n' >"$EDITOR_TEST_STATE/cursor"
export HOME="$fixture/home"
export PATH="$fixture/bin:/usr/bin:/bin"
code_settings="$HOME/Library/Application Support/Code/User/settings.json"
agy_settings="$HOME/Library/Application Support/Antigravity IDE/User/settings.json"
cursor_settings="$HOME/Library/Application Support/Cursor/User/settings.json"
mkdir -p "$(dirname "$code_settings")"
printf '{"custom":true}\n' >"$code_settings"
cp "$code_settings" "$fixture/original"
ELECTRON_RUN_AS_NODE=1 bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null 2>"$fixture/first.err"
if grep -Eq 'DEP0169|trace-deprecation' "$fixture/first.err"; then
  echo 'sync did not filter runtime deprecation warnings' >&2
  exit 1
fi
# Pack members installed alongside ms-toolsai.jupyter must not be requested again.
if grep -Eq ' --install-extension ms-toolsai\.jupyter-(keymap|renderers)$' "$EDITOR_TEST_LOG"; then
  echo 'sync reinstalled extension pack members' >&2
  exit 1
fi
cmp "$fixture/repo/home/ide/settings.json" "$code_settings"
cmp "$code_settings" "$agy_settings"
backups=("$code_settings".backup.*)
test "${#backups[@]}" = 1
cmp "$fixture/original" "${backups[0]}"
# Cursor gets the shared settings plus its own overrides.
jq -e --slurpfile shared "$fixture/repo/home/ide/settings.json" \
  --slurpfile cursor "$fixture/repo/home/ide/cursor/settings.json" \
  '. == ($shared[0] * $cursor[0])' "$cursor_settings" >/dev/null
jq -e '."workbench.colorTheme" == "Tokyo Night" and
  ."cursor.composer.queueMessageDefaultBehavior" == "steer"' "$cursor_settings" >/dev/null
# Both editors must receive every shared plugin, and VS Code needs the theme.
while IFS= read -r extension; do
  grep -Fxiq -- "$extension" "$EDITOR_TEST_STATE/code"
  grep -Fxiq -- "$extension" "$EDITOR_TEST_STATE/antigravity-ide"
  grep -Fxiq -- "$extension" "$EDITOR_TEST_STATE/cursor"
done < <(jq -r '.recommendations[]' "$fixture/repo/home/ide/extensions.json")
grep -Fxq 'code --install-extension enkia.tokyo-night' "$EDITOR_TEST_LOG"
grep -Fxq 'cursor --install-extension enkia.tokyo-night' "$EDITOR_TEST_LOG"
: >"$EDITOR_TEST_LOG"
bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null
if grep -Fq -- '--install-extension' "$EDITOR_TEST_LOG"; then
  echo 'sync reinstalled existing extensions' >&2
  exit 1
fi
backups=("$code_settings".backup.*)
test "${#backups[@]}" = 1
test -z "$(find "$(dirname "$cursor_settings")" -name 'settings.json.backup.*')"
# Replacing a symlink must preserve its old target and back up its contents.
cp "$fixture/original" "$fixture/target"
rm "$agy_settings"
ln -s "$fixture/target" "$agy_settings"
bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null
cmp "$fixture/original" "$fixture/target"
test ! -L "$agy_settings"
cmp "$code_settings" "$agy_settings"
# A failed marketplace install must fail the sync but still try the other IDE.
sed '/vscodevim.vim/d' "$EDITOR_TEST_STATE/code" >"$fixture/without-vim"
cp "$fixture/without-vim" "$EDITOR_TEST_STATE/code"
: >"$EDITOR_TEST_LOG"
if EDITOR_TEST_FAIL=code bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null 2>&1; then
  echo 'sync ignored extension installation failure' >&2
  exit 1
fi
grep -Fxq 'antigravity-ide --list-extensions' "$EDITOR_TEST_LOG"
# A failed listing must not be mistaken for an empty installed list.
: >"$EDITOR_TEST_LOG"
if EDITOR_TEST_LIST_FAIL=code bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null 2>&1; then
  echo 'sync ignored extension listing failure' >&2
  exit 1
fi
if grep -Fq 'code --install-extension ' "$EDITOR_TEST_LOG"; then
  echo 'sync installed extensions after a failed listing' >&2
  exit 1
fi
grep -Fxq 'antigravity-ide --list-extensions' "$EDITOR_TEST_LOG"

# Harmless stderr warnings must not contaminate the installed-extension list.
: >"$EDITOR_TEST_LOG"
EDITOR_TEST_LIST_DIAGNOSTIC=antigravity-ide bash "$fixture/repo/scripts/sync-editors.sh" >"$fixture/diagnostic.log" 2>&1
grep -q 'antigravityAnalytics' "$fixture/diagnostic.log"
if grep -Fq 'antigravity-ide --install-extension ' "$EDITOR_TEST_LOG"; then
  echo 'sync reinstalled extensions after a harmless stderr warning' >&2
  exit 1
fi

# Invalid recommendations must fail before changing settings or installing plugins.
printf '{"recommendations": "oxc.oxc-vscode"}\n' >"$fixture/repo/home/ide/extensions.json"
printf '{"keep":true}\n' >"$code_settings"
cp "$code_settings" "$fixture/keep"
: >"$EDITOR_TEST_LOG"
if bash "$fixture/repo/scripts/sync-editors.sh" >/dev/null 2>&1; then
  echo 'sync accepted invalid recommendations' >&2
  exit 1
fi
cmp "$fixture/keep" "$code_settings"
test ! -s "$EDITOR_TEST_LOG"
