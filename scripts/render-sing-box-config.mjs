import fs from "node:fs";

function getPath(object, path) {
  return path.split("/").reduce((value, key) => {
    if (value === null || typeof value !== "object" || !(key in value)) {
      throw new Error(`missing SOPS key path: ${path}`);
    }
    return value[key];
  }, object);
}

export function renderConfig(templateText, secretMap, secrets) {
  let rendered = templateText;
  for (const [marker, path] of Object.entries(secretMap)) {
    const value = getPath(secrets, path);
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`invalid secret value for: ${path}`);
    }
    const occurrences = rendered.split(marker).length - 1;
    if (occurrences < 1) {
      throw new Error(`expected marker at least once: ${marker}`);
    }
    rendered = rendered.split(marker).join(value);
  }
  if (/__SOPS_[A-Z0-9_]+__/.test(rendered)) {
    throw new Error("unresolved SOPS marker remains");
  }
  JSON.parse(rendered);
  return rendered;
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const [templatePath, mapPath] = process.argv.slice(2);
  if (!templatePath || !mapPath) {
    throw new Error("usage: render-sing-box-config.mjs TEMPLATE MAP");
  }
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const secrets = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const output = renderConfig(
    fs.readFileSync(templatePath, "utf8"),
    JSON.parse(fs.readFileSync(mapPath, "utf8")),
    secrets,
  );
  process.stdout.write(output);
}
