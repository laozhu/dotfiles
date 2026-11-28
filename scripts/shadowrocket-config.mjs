// Render the Shadowrocket node share links and check them with the public rules (.conf).
// Shadowrocket has no CLI validator, so this enforces the structure and safety
// contracts we rely on; the app still has to load the result.
import fs from "node:fs";
import { getPath } from "./render-sing-box-config.mjs";

const markerPattern = /__SOPS_[A-Z0-9_]+__/;
const sections = new Set(["General", "Proxy Group", "Rule"]);
const builtinPolicies = new Set(["DIRECT", "REJECT", "REJECT-DROP"]);
const ruleTypes = new Set([
  "DOMAIN",
  "DOMAIN-SUFFIX",
  "DOMAIN-KEYWORD",
  "IP-CIDR",
  "IP-CIDR6",
  "DST-PORT",
  "RULE-SET",
  "FINAL",
]);
const encryptedDns = /^(https|tls|quic|h3):\/\//;
const insecureFlags = /skip-cert-verify|allowinsecure|insecure=1|insecure=true/i;
// Share-link values are not percent-encoded, so secrets must not need encoding.
const plainValue = /^[A-Za-z0-9._~-]+$/;

// The map is shared with sing-box, so markers the links do not use are skipped.
export function renderNodes(conf, nodesTemplate, secretMap, secrets) {
  let nodes = nodesTemplate;
  for (const [marker, secretPath] of Object.entries(secretMap)) {
    const value = getPath(secrets, secretPath);
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`invalid secret value for: ${secretPath}`);
    }
    // The rules are published on GitHub, so they must not contain any secret.
    if (conf.includes(value)) throw new Error(`conf: contains the secret ${secretPath}`);
    nodes = nodes.split(marker).join(value);
  }
  checkShadowrocket(conf, nodes);
  return nodes;
}

function parseConf(text) {
  const parsed = { General: new Map(), "Proxy Group": new Map(), Rule: [] };
  let section = null;
  for (const [index, raw] of text.split("\n").entries()) {
    const line = raw.trim();
    const where = `conf line ${index + 1}`;
    if (line === "" || line.startsWith("#")) continue;
    const header = line.match(/^\[(.+)\]$/);
    if (header) {
      if (!sections.has(header[1])) throw new Error(`${where}: unsupported section [${header[1]}]`);
      section = header[1];
      continue;
    }
    if (section === null) throw new Error(`${where}: entry outside a section`);
    if (section === "Rule") {
      parsed.Rule.push({ where, fields: line.split(",").map((field) => field.trim()) });
      continue;
    }
    const separator = line.indexOf("=");
    if (separator < 1) throw new Error(`${where}: expected key = value`);
    const key = line.slice(0, separator).trim();
    if (parsed[section].has(key)) throw new Error(`${where}: duplicate ${key}`);
    parsed[section].set(key, { where, value: line.slice(separator + 1).trim() });
  }
  return parsed;
}

function parseGroup(name, { where, value }) {
  const [type, ...items] = value.split(",").map((item) => item.trim());
  const members = items.filter((item) => !item.includes("="));
  const options = Object.fromEntries(
    items
      .filter((item) => item.includes("="))
      .map((item) => {
        const separator = item.indexOf("=");
        return [item.slice(0, separator), item.slice(separator + 1)];
      }),
  );
  return { name, where, type, members, options };
}

export function parseNodes(text) {
  const nodes = [];
  for (const [index, raw] of text.split("\n").entries()) {
    const line = raw.trim();
    if (line === "") continue;
    const where = `node line ${index + 1}`;
    const url = new URL(line);
    const name = decodeURIComponent(url.hash.slice(1));
    const params = Object.fromEntries(url.searchParams);
    for (const value of [url.username, ...Object.values(params)]) {
      if (!plainValue.test(value)) throw new Error(`${where}: value needs URL encoding`);
    }
    nodes.push({ where, name, protocol: url.protocol.slice(0, -1), url, params });
  }
  return nodes;
}

function ensure(condition, message) {
  if (!condition) throw new Error(message);
}

function checkNode({ where, name, protocol, url, params }) {
  ensure(/^[a-z0-9-]+$/.test(name), `${where}: node name must be lowercase ASCII`);
  ensure(url.hostname !== "" && /^\d+$/.test(url.port), `${where}: missing host or port`);
  ensure(url.username !== "", `${where}: missing credential`);
  ensure(params.sni, `${where}: missing sni`);
  if (protocol === "vless") {
    ensure(params.security === "reality", `${where}: VLESS must use REALITY`);
    ensure(params.flow === "xtls-rprx-vision", `${where}: VLESS must use xtls-rprx-vision`);
    ensure(params.encryption === "none", `${where}: VLESS encryption must be none`);
    ensure(params.pbk && params.sid && params.fp, `${where}: missing REALITY pbk, sid or fp`);
  } else if (protocol === "hysteria2") {
    ensure(params.obfs === "salamander", `${where}: Hysteria2 must use salamander obfs`);
    ensure(params["obfs-password"], `${where}: missing obfs-password`);
  } else {
    throw new Error(`${where}: unsupported protocol ${protocol}`);
  }
}

export function checkShadowrocket(conf, nodesText) {
  for (const [label, text] of [
    ["conf", conf],
    ["nodes", nodesText],
  ]) {
    ensure(!markerPattern.test(text), `${label}: unresolved SOPS marker remains`);
    ensure(!insecureFlags.test(text), `${label}: certificate verification must stay on`);
  }

  const parsed = parseConf(conf);
  const general = parsed.General;
  ensure(general.get("ipv6")?.value === "false", "conf: ipv6 must be false like sing-box");
  const dns = general.get("dns-server")?.value ?? "";
  ensure(
    dns !== "" && dns.split(",").every((server) => encryptedDns.test(server.trim())),
    "conf: dns-server must use encrypted DNS",
  );

  const groups = [...parsed["Proxy Group"]].map(([name, entry]) => parseGroup(name, entry));
  const policies = new Set([...builtinPolicies, ...groups.map((group) => group.name)]);
  const nodes = parseNodes(nodesText);
  ensure(nodes.length > 0, "nodes: no share links");
  nodes.forEach(checkNode);
  const names = nodes.map((node) => node.name);
  ensure(new Set(names).size === names.length, "nodes: duplicate node name");

  for (const group of groups) {
    if (group.type === "select") {
      ensure(group.members.length > 0, `${group.where}: select needs members`);
      for (const member of group.members) {
        ensure(policies.has(member), `${group.where}: unknown member ${member}`);
      }
      const chosen = group.options["policy-select-name"];
      ensure(
        !chosen || group.members.includes(chosen),
        `${group.where}: unknown default ${chosen}`,
      );
    } else if (group.type === "url-test") {
      ensure(group.members.length === 0, `${group.where}: url-test selects nodes by regex only`);
      ensure(
        group.options.url?.startsWith("https://"),
        `${group.where}: url-test needs an https url`,
      );
      const filter = new RegExp(group.options["policy-regex-filter"] ?? "(?!)");
      ensure(
        names.some((name) => filter.test(name)),
        `${group.where}: filter matches no node`,
      );
    } else {
      throw new Error(`${group.where}: unsupported group type ${group.type}`);
    }
  }

  ensure(parsed.Rule.length > 0, "conf: no rules");
  for (const [index, { where, fields }] of parsed.Rule.entries()) {
    const [type] = fields;
    ensure(ruleTypes.has(type), `${where}: unsupported rule type ${type}`);
    const isFinal = type === "FINAL";
    ensure(isFinal === (index === parsed.Rule.length - 1), `${where}: FINAL must be the last rule`);
    const policy = isFinal ? fields[1] : fields[2];
    ensure(policies.has(policy), `${where}: unknown policy ${policy}`);
    if (type === "RULE-SET")
      ensure(fields[1].startsWith("https://"), `${where}: RULE-SET needs https`);
    if (type.startsWith("IP-CIDR"))
      ensure(fields.includes("no-resolve"), `${where}: IP rules need no-resolve`);
  }
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const [command, ...args] = process.argv.slice(2);
  if (command === "check" && args.length === 2) {
    checkShadowrocket(fs.readFileSync(args[0], "utf8"), fs.readFileSync(args[1], "utf8"));
  } else if (command === "render" && args.length === 4) {
    const [confPath, nodesTemplate, mapPath, output] = args;
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    const nodes = renderNodes(
      fs.readFileSync(confPath, "utf8"),
      fs.readFileSync(nodesTemplate, "utf8"),
      JSON.parse(fs.readFileSync(mapPath, "utf8")),
      JSON.parse(Buffer.concat(chunks).toString("utf8")),
    );
    fs.writeFileSync(output, nodes, { mode: 0o600 });
  } else {
    throw new Error(
      "usage: shadowrocket-config.mjs check CONF NODES | render CONF NODES_TEMPLATE MAP OUTPUT",
    );
  }
}
