#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export DSH_HOME="$fixture/dsh"
export DSH_PLUGIN_TEST_LOG="$fixture/install.log"
mkdir -p "$fixture/bin" "$DSH_HOME/profiles/tui"
printf 'local model selection\n' >"$DSH_HOME/profiles/tui/cordis.patch.yml"
printf 'local credentials\n' >"$DSH_HOME/.credentials.yaml"
cat >"$fixture/bin/dsh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DSH_PLUGIN_TEST_LOG"
if [ "${DSH_PLUGIN_TEST_FAIL:-0}" != 0 ]; then exit 42; fi
target="$DSH_HOME/profiles/$3"
package="${5%@*}"
version="${5##*@}"
mkdir -p "$target/node_modules/$package"
jq -n --arg p "$package" --arg v "$version" \
  '{dependencies:{($p):$v},dsh:{profile:{bundles:["@deepseek-ai/dsh-base",$p]}}}' >"$target/package.json"
jq -n --arg p "$package" --arg v "$version" \
  '{name:$p,version:$v}' >"$target/node_modules/$package/package.json"
SH
chmod +x "$fixture/bin/dsh"
export PATH="$fixture/bin:$PATH"
sync_plugin() {
  bash "$repo_dir/scripts/sync-dsh-plugin.sh" tui @deepseek-harness-tui/dsh-tui "$1"
}
sync_plugin 0.18.0
grep -Fxq 'plugin --profile tui add @deepseek-harness-tui/dsh-tui@0.18.0' "$DSH_PLUGIN_TEST_LOG"
sync_plugin 0.18.0
test "$(wc -l <"$DSH_PLUGIN_TEST_LOG" | tr -d ' ')" = 1
sync_plugin 0.19.0
test "$(wc -l <"$DSH_PLUGIN_TEST_LOG" | tr -d ' ')" = 2
# Missing installed files and a missing bundle registration both require repair.
rm "$DSH_HOME/profiles/tui/node_modules/@deepseek-harness-tui/dsh-tui/package.json"
sync_plugin 0.19.0
printf '{}\n' >"$DSH_HOME/profiles/tui/package.json"
sync_plugin 0.19.0
test "$(wc -l <"$DSH_PLUGIN_TEST_LOG" | tr -d ' ')" = 4
status=0
DSH_PLUGIN_TEST_FAIL=1 sync_plugin 0.20.0 || status="$?"
test "$status" = 42
test "$(cat "$DSH_HOME/profiles/tui/cordis.patch.yml")" = 'local model selection'
test "$(cat "$DSH_HOME/.credentials.yaml")" = 'local credentials'
