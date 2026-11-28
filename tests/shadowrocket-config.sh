#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
checker="$repo_dir/scripts/shadowrocket-config.mjs"
node --check "$checker"

sr_test_root="$(mktemp -d)"
trap 'rm -rf "$sr_test_root"' EXIT

SR_TEST_ROOT="$sr_test_root" node --input-type=module - "$repo_dir" <<'NODE'
import assert from "node:assert/strict";
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const repo = process.argv[2];
const read = (file) => fs.readFileSync(`${repo}/${file}`, "utf8");
const { renderNodes, checkShadowrocket, parseNodes } = await import(
  pathToFileURL(`${repo}/scripts/shadowrocket-config.mjs`)
);
const confTemplate = read("home/.config/shadowrocket/shadowrocket.conf");
const nodesTemplate = read("home/.config/shadowrocket/nodes.txt");
const secretMap = JSON.parse(read("home/.config/sing-box/secrets-map.json"));
const singBox = JSON.parse(read("home/.config/sing-box/config.json"));

// Fake secrets shaped like the real ones: hostnames, IPv4 addresses and tokens.
const secrets = {};
for (const [index, secretPath] of Object.values(secretMap).entries()) {
  const keys = secretPath.split("/");
  let node = secrets;
  for (const key of keys.slice(0, -1)) node = node[key] ??= {};
  const leaf = keys.at(-1);
  node[leaf] = leaf === "server-ip" ? `192.0.2.${index}` :
    leaf === "server-hostname" ? `node${index}.example.com` : `token${index}`;
}
const conf = confTemplate;
const nodes = renderNodes(conf, nodesTemplate, secretMap, secrets);
const hostname = secrets["sing-box"].singapore["server-hostname"];

// The rules are published on GitHub, so they must stay free of secrets.
assert.doesNotMatch(conf, /__SOPS_/);
assert.throws(
  () => renderNodes(`${conf}# ${hostname}\n`, nodesTemplate, secretMap, secrets),
  /contains the secret sing-box\/singapore\/server-hostname/,
);

const rejects = (confText, nodesText, pattern) =>
  assert.throws(() => checkShadowrocket(confText, nodesText), pattern);
rejects(conf, nodes.replace("&type=tcp", "&type=tcp&allowInsecure=1"), /verification must stay on/);
rejects(conf.replace("ipv6 = false", "ipv6 = true"), nodes, /ipv6 must be false/);
rejects(conf.replace("https://dns.alidns.com/dns-query", "223.5.5.5"), nodes, /encrypted DNS/);
rejects(conf.replace("[Rule]", "[Proxy]\nx = vless,a,1\n[Rule]"), nodes, /unsupported section/);
rejects(conf.replace("[Rule]", "[Host]\na = 192.0.2.1\n[Rule]"), nodes, /unsupported section/);
rejects(conf.replace("DST-PORT,22,🚀 proxy", "DST-PORT,22,missing"), nodes, /unknown policy missing/);
rejects(conf.replace("FINAL,DIRECT", "FINAL,DIRECT\nDST-PORT,1,DIRECT"), nodes, /FINAL must be the last/);
rejects(conf.replace("IP-CIDR,10.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,10.0.0.0/8,DIRECT"), nodes, /no-resolve/);
rejects(conf.replace("^sg-(hy2|vless)$", "^jp-"), nodes, /filter matches no node/);
rejects(conf, nodes.replace("security=reality", "security=tls"), /must use REALITY/);
rejects(conf, nodes.replace("obfs=salamander", "obfs=none"), /salamander/);
rejects(conf, nodes.replace("#us-hy2", "#sg-hy2"), /duplicate node name/);
rejects(conf, `${nodes}ss://x@h:1?sni=a#ss\n`, /unsupported protocol/);
assert.throws(
  () => renderNodes(conf, nodesTemplate, secretMap,
    { ...secrets, "sing-box": { ...secrets["sing-box"], usa: {
      ...secrets["sing-box"].usa, vless: { ...secrets["sing-box"].usa.vless, uuid: "a+b" },
    } } }),
  /needs URL encoding/,
);
assert.throws(
  () => renderNodes(conf, nodesTemplate, { ...secretMap, __SOPS_EXTRA__: "x/y" }, secrets),
  /missing SOPS key path: x\/y/,
);

// Every sing-box route must have a Shadowrocket rule with the same policy.
const rules = new Set(confTemplate.split("\n").filter((line) => /^[A-Z0-9-]+,/.test(line)));
const sets = Object.fromEntries(singBox.route.rule_set.map((set) => [set.tag, set]));
const placeholder = "sing-box-placeholder.invalid";
for (const rule of singBox.route.rules) {
  if (rule.action === "sniff" || rule.action === "hijack-dns" || rule.ip_is_private) continue;
  // Shadowrocket never routes its own proxy server connections through the rules.
  if (rule.rule_set === "proxy-server") continue;
  const policy = rule.action === "reject" ? "REJECT" :
    rule.outbound === "direct" ? "DIRECT" : rule.outbound;
  if (rule.network) continue; // google-meet's UDP rule is covered by its plain rule below it
  if (rule.port) {
    for (const port of [].concat(rule.port)) {
      assert.ok(rules.has(`DST-PORT,${port},${policy}`), `port ${port}`);
    }
    continue;
  }
  const set = sets[rule.rule_set];
  assert.ok(set, `unknown sing-box rule set ${rule.rule_set}`);
  if (set.type === "remote") {
    const name = new URL(set.url).pathname.split("/").at(-1).replace(/\.srs$/, ".list");
    const url = `https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/classical/${name}`;
    assert.ok(rules.has(`RULE-SET,${url},${policy}`), `remote rule set ${set.tag}`);
    continue;
  }
  for (const entry of set.rules) {
    const values = (value) => (value === undefined ? [] : [].concat(value));
    for (const domain of values(entry.domain)) {
      if (domain !== placeholder) assert.ok(rules.has(`DOMAIN,${domain},${policy}`), `${set.tag} ${domain}`);
    }
    for (const suffix of values(entry.domain_suffix)) {
      assert.ok(rules.has(`DOMAIN-SUFFIX,${suffix},${policy}`), `${set.tag} ${suffix}`);
    }
    for (const cidr of values(entry.ip_cidr)) {
      const type = cidr.includes(":") ? "IP-CIDR6" : "IP-CIDR";
      assert.ok(rules.has(`${type},${cidr},${policy},no-resolve`), `${set.tag} ${cidr}`);
    }
  }
}
assert.ok(rules.has("FINAL,DIRECT") && singBox.route.final === "direct");

// Every sing-box node must have a share link with the same endpoint and secrets.
const links = new Map(parseNodes(nodesTemplate).map((node) => [node.name, node]));
const outbounds = singBox.outbounds.filter((o) => o.type === "vless" || o.type === "hysteria2");
assert.equal(links.size, outbounds.length);
for (const outbound of outbounds) {
  const link = links.get(outbound.tag.split(" ").at(-1));
  assert.ok(link, `missing share link for ${outbound.tag}`);
  assert.equal(link.protocol, outbound.type);
  assert.equal(link.url.hostname, outbound.server);
  assert.equal(link.url.port, String(outbound.server_port));
  assert.equal(link.params.sni, outbound.tls.server_name);
  if (outbound.type === "vless") {
    assert.equal(link.url.username, outbound.uuid);
    assert.equal(link.params.flow, outbound.flow);
    assert.equal(link.params.fp, outbound.tls.utls.fingerprint);
    assert.equal(link.params.pbk, outbound.tls.reality.public_key);
    assert.equal(link.params.sid, outbound.tls.reality.short_id);
  } else {
    assert.equal(link.url.username, outbound.password);
    assert.equal(link.params.obfs, outbound.obfs.type);
    assert.equal(link.params["obfs-password"], outbound.obfs.password);
  }
}

fs.writeFileSync(`${process.env.SR_TEST_ROOT}/nodes.txt`, nodes);
NODE

# Publishing checks the links against the rules and keeps them private.
coreutils_bin="$(
  nix eval --raw "$repo_dir#darwinConfigurations.mac.pkgs.coreutils"
)/bin"
conf="$repo_dir/home/.config/shadowrocket/shadowrocket.conf"
publish() {
  bash "$repo_dir/scripts/publish-shadowrocket-config.sh" "$1" "$2" "$3" \
    "$coreutils_bin" "$(command -v node)" "$checker"
}
state="$sr_test_root/state"
publish "$state" "$sr_test_root/nodes.txt" "$conf"
cmp "$state/nodes.txt" "$sr_test_root/nodes.txt"
test "$(stat -f %Lp "$state")" = 700
test "$(stat -f %Lp "$state/nodes.txt")" = 600
test "$(ls -A "$state")" = nodes.txt

sed 's/security=reality/security=tls/' "$sr_test_root/nodes.txt" >"$sr_test_root/bad.txt"
if publish "$state" "$sr_test_root/bad.txt" "$conf" 2>/dev/null; then
  echo 'published invalid Shadowrocket node links' >&2
  exit 1
fi
cmp "$state/nodes.txt" "$sr_test_root/nodes.txt"
test "$(ls -A "$state")" = nodes.txt

ln -s "$state" "$sr_test_root/state-link"
if publish "$sr_test_root/state-link" "$sr_test_root/nodes.txt" "$conf" 2>/dev/null; then
  echo 'published through a symlinked state directory' >&2
  exit 1
fi

# sops-nix renders only the links; the public rules are never rendered with secrets.
nix eval --json "$repo_dir#darwinConfigurations.mac.config.sops.templates" \
  --apply 't: builtins.mapAttrs (_: v: { inherit (v) path owner group mode; })
    (builtins.removeAttrs t [ "sing-box-candidate" ])' |
  jq -e '
    keys == ["shadowrocket-nodes-candidate"] and
    (.["shadowrocket-nodes-candidate"] |
      .path == "/run/secrets/rendered/shadowrocket-nodes-candidate" and
      .group == "staff" and .mode == "0400" and (.owner | length > 0))
  ' >/dev/null
