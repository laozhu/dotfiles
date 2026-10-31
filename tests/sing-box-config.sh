#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config="$repo_dir/home/.config/sing-box/config.json"

# Group, route and downloader references must survive display-name changes.
jq -e '
  [.outbounds[].tag] as $tags |
  ($tags | length) == ($tags | unique | length) and
  ([.outbounds[] | select(.type == "selector" or .type == "urltest") |
    .outbounds[]] | all(. as $tag | $tags | index($tag) != null)) and
  ([.. | objects | (.outbound? // empty), (.detour? // empty)] |
    all(. as $tag | $tags | index($tag) != null)) and
  ([.outbounds[] | select(.type == "selector") |
    . as $group | .outbounds | index($group.default) != null] | all)
' "$config" >/dev/null

# Check safety boundaries and routing contracts, not a snapshot of every setting.
jq -e '
  .route.final == "direct" and
  (.inbounds | length == 2) and
  ([.inbounds[] | select(.type == "tun" and .auto_route == true)] | length == 1) and
  ([.inbounds[] | select(.type == "mixed" and .listen == "127.0.0.1" and
    .listen_port == 7777)] | length == 1) and
  (.experimental | has("clash_api") | not) and
  ([.. | objects | keys[]] | any(. == "external_controller" or . == "external_ui") | not)
' "$config" >/dev/null

# Fixed regional routes must remain independent of the global selector.
jq -e '
  . as $config |
  ["claude", "antigravity.google"] | all(
    . as $tag |
    ([$config.route.rules[] | select(.rule_set == $tag) | .outbound] == ["🇸🇬 singapore"]) and
    ([$config.dns.rules[] | select(.rule_set == $tag) | .server] == ["singapore-dns"])
  )
' "$config" >/dev/null

# DNS and rule-set references must resolve, including the shared download client.
jq -e '
  [.dns.servers[].tag] as $dns |
  [.route.rule_set[].tag] as $rules |
  [.http_clients[].tag] as $clients |
  ($dns | length == (unique | length)) and
  ($rules | length == (unique | length)) and
  ([.dns.final, .route.default_domain_resolver,
    (.outbounds[] | .domain_resolver? // empty),
    (.dns.rules[] | .server? // empty)] |
    all(. as $tag | $dns | index($tag) != null)) and
  ([.route.rules[], .dns.rules[] | .rule_set? // empty |
    if type == "array" then .[] else . end] |
    all(. as $tag | $rules | index($tag) != null)) and
  ([.route.default_http_client, (.route.rule_set[] | .http_client? // empty)] |
    all(. as $tag | $clients | index($tag) != null)) and
  (first(.http_clients[] | select(.tag == "rule-set-download")).detour == "🇺🇸 us-hy2")
' "$config" >/dev/null

config_test_root="$(mktemp -d)"
trap 'rm -rf "$config_test_root"' EXIT

# Render the actual template with synthetic secrets, then use the real core to
# validate it. This exercises schema changes without needing the user's age key.
node --input-type=module - "$repo_dir" "$config_test_root/rendered.json" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [repo, output] = process.argv.slice(2);
const { renderConfig } = await import(pathToFileURL(`${repo}/scripts/render-sing-box-config.mjs`));
const template = readFileSync(`${repo}/home/.config/sing-box/config.json`, "utf8");
const map = JSON.parse(readFileSync(`${repo}/home/.config/sing-box/secrets-map.json`, "utf8"));
const markers = [...new Set(template.match(/__SOPS_[A-Z0-9_]+__/g))].sort();
assert.deepEqual(markers, Object.keys(map).sort(), "Secret map and template markers must agree");
const server = {
  vless: {
    uuid: "00000000-0000-4000-8000-000000000001",
    "tls-server-name": "example.invalid",
    "reality-public-key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "reality-short-id": "0123456789abcdef",
  },
  hysteria2: {
    password: "test-only-password",
    "obfs-password": "test-only-obfs-password",
    "tls-server-name": "example.invalid",
  },
};
const secrets = { "sing-box": {
  singapore: { ...server, "server-hostname": "sg.example.invalid", "server-ip": "192.0.2.1" },
  usa: { ...server, "server-hostname": "us.example.invalid", "server-ip": "192.0.2.2" },
} };
writeFileSync(output, renderConfig(template, map, secrets));
NODE
sing-box check -c "$config_test_root/rendered.json"

# Exercise sing-box domain matching, including exact API hosts and suffix boundaries.
rule_fixture="$config_test_root/antigravity.json"
jq -e '
  [.route.rule_set[] | select(.tag == "antigravity.google")] | length == 1
' "$config" >/dev/null
jq '{version: 3, rules: first(.route.rule_set[] |
  select(.tag == "antigravity.google")).rules}' "$config" >"$rule_fixture"
for domain in \
  antigravity.google www.antigravity.google antigravity.google.com \
  aicode.googleapis.com cloudcode-pa.googleapis.com daily-cloudcode-pa.googleapis.com \
  accounts.google.com oauth2.googleapis.com www.googleapis.com \
  antigravity-unleash.goog play.googleapis.com \
  antigravity-cli-auto-updater-974169037036.us-central1.run.app storage.googleapis.com; do
  result="$(sing-box rule-set match "$rule_fixture" "$domain" 2>&1)"
  if [ -z "$result" ]; then
    printf 'Antigravity rule did not match %s\n' "$domain" >&2
    exit 1
  fi
done
for domain in example.com other.googleapis.com notantigravity.google antigravity.google.evil.example; do
  result="$(sing-box rule-set match "$rule_fixture" "$domain" 2>&1)"
  if [ -n "$result" ]; then
    printf 'Antigravity rule unexpectedly matched %s\n' "$domain" >&2
    exit 1
  fi
done
