#!/usr/bin/env node
// Read-only inventory of declared software. No applications or secrets are opened.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const catalog = JSON.parse(fs.readFileSync(path.join(repo, "software.json"), "utf8"));

export function inspectSoftware(entry, options = {}) {
  const home = options.home ?? os.homedir();
  const brewPrefix = options.brewPrefix ?? "/opt/homebrew";
  const searchPath =
    options.path ??
    [
      `${brewPrefix}/opt/python/libexec/bin`,
      `${brewPrefix}/opt/openjdk/bin`,
      process.env.PATH ?? "",
      `${home}/.nix-profile/bin`,
      `/etc/profiles/per-user/${path.basename(home)}/bin`,
      "/run/current-system/sw/bin",
      `${brewPrefix}/bin`,
      "/usr/local/bin",
      `${home}/.local/bin`,
    ].join(path.delimiter);
  const appDirs = options.appDirs ?? ["/Applications", path.join(home, "Applications")];
  const evidence = [];
  let found = 0;
  const checks = [];
  const missing = [];
  if (entry.apps?.length) {
    const candidates = entry.apps.flatMap((app) => {
      if (app.startsWith("~/")) return [path.join(home, app.slice(2))];
      return path.isAbsolute(app) ? [app] : appDirs.map((dir) => path.join(dir, app));
    });
    const app = candidates.find((candidate) => fs.existsSync(candidate));
    checks.push(Boolean(app));
    if (app) {
      found++;
      evidence.push(app);
    } else missing.push("应用或字体文件");
  }
  for (const command of entry.commands ?? []) {
    const executable = searchPath
      .split(path.delimiter)
      .filter(Boolean)
      .map((dir) =>
        command.startsWith("~/")
          ? path.join(home, command.slice(2))
          : path.isAbsolute(command)
            ? command
            : path.join(dir, command),
      )
      .find((candidate) => {
        try {
          fs.accessSync(candidate, fs.constants.X_OK);
          if (!fs.statSync(candidate).isFile()) return false;
          if (
            ["Nix", "Home Manager", "llm-agents.nix"].includes(entry.manager) &&
            !fs.realpathSync(candidate).startsWith("/nix/store/")
          )
            return false;
          // macOS ships launcher stubs for Java and Rust, and a CLT Python.
          if (["openjdk", "python", "rustc", "cargo"].includes(entry.id)) {
            return (
              fs.realpathSync(candidate).startsWith(`${brewPrefix}/`) ||
              (["rustc", "cargo"].includes(entry.id) &&
                fs.realpathSync(candidate).startsWith("/nix/store/"))
            );
          }
          return true;
        } catch {
          return false;
        }
      });
    checks.push(Boolean(executable));
    if (executable) {
      found++;
      evidence.push(executable);
    } else missing.push(command);
  }
  let status = found === 0 ? "未安装" : found === checks.length ? "已安装" : "部分安装";
  if (entry.manager === "Gradle") status = "项目管理";
  if (entry.manager === "Manual" && !found) status = "需人工安装";
  const detail = [
    ...evidence,
    ...(missing.length ? [`缺少：${missing.join(", ")}`] : []),
    entry.note,
  ]
    .filter(Boolean)
    .join("; ");
  return { ...entry, status, detail };
}

function main(args) {
  let profile;
  let group;
  let json = false;
  while (args.length) {
    const arg = args.shift();
    if (arg === "--json") json = true;
    else if (arg === "--profile" && ["home", "work"].includes(args[0])) profile = args.shift();
    else if (arg === "--group" && ["shared", "home", "work"].includes(args[0]))
      group = args.shift();
    else if (arg === "--help" || arg === "-h") {
      console.log(
        "Usage: node scripts/software-inventory.mjs [--profile home|work] [--group shared|home|work] [--json]",
      );
      return;
    } else {
      console.error(`Invalid argument: ${arg}. Use --help.`);
      process.exitCode = 2;
      return;
    }
  }
  const rows = catalog
    .filter(
      (entry) =>
        entry.inventory !== false &&
        (!profile || ["shared", profile].includes(entry.group)) &&
        (!group || entry.group === group),
    )
    .map((entry) => inspectSoftware(entry));
  if (json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }
  console.log(
    "安装方式为声明来源；状态根据本机应用文件和命令路径检测，不表示已登录、已授权或服务可用。\n",
  );
  const cell = (value) =>
    String(value ?? "")
      .replaceAll("|", "\\|")
      .replaceAll("\n", " ");
  console.log("| 名称 | 分组 | 类型 | 安装方式 | 安装状态 | 检测依据 / 说明 |");
  console.log("| --- | --- | --- | --- | --- | --- |");
  for (const row of rows)
    console.log(
      `| ${[row.name, row.group, row.type, row.manager, row.status, row.detail].map(cell).join(" | ")} |`,
    );
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href)
  main(process.argv.slice(2));
