# Pi Agent 与 Claude 声明式配置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过 Home Manager 安全地复用 Claude 全局规则，并让 Pi 0.83 从声明式 settings 安装两个精确版本的第三方包，同时保留本地凭证、会话和运行时目录。

**Architecture:** `home/AGENTS.md` 继续作为共享规则真相源，Claude 通过独立的 `home/CLAUDE.md` 使用原生 `@AGENTS.md` 导入。Home Manager 只映射精确的 Pi settings、主题和本地扩展文件；Pi 自己在用户运行时目录中解析并安装精确 pin 的 npm 包。静态仓库测试验证声明和所有权边界，联网兼容性通过临时 HOME 中的一次真实 Pi 0.83 smoke test 验证。

**Tech Stack:** Nix Darwin、Home Manager、Bash、jq、Node.js、Pi 0.83、npm package sources

**Spec:** `docs/superpowers/specs/2026-09-13-pi-agent-home-manager-design.md`

## Global Constraints

- 不运行 `./rebuild.sh`，不激活新的 Darwin 或 Home Manager generation。
- 不修改或提交用户现有的未跟踪文件 `home/.claude/settings.json.bak`。
- 不加入 Pi Calm、`models.json`、`ffmpeg`、`yt-dlp` 或单独的 `unpdf` 包。
- 不接管 `.pi/agent`、`.pi/agent/themes`、`.pi/agent/extensions`、凭证、会话、缓存或 npm 运行时父目录。
- 保留 `home/.pi/agent/extensions/terminal-status-title.js` 中的 `ORCA_PANE_KEY` 防护，不修改该文件。
- 两个第三方包必须保持精确版本，不允许 `latest`、范围版本或无版本声明。

## File Structure

- Create: `home/CLAUDE.md` - Claude 专用兼容桥，只导入同目录的 `AGENTS.md`。
- Modify: `home.nix:3-8,124-146` - 新增 Claude wrapper 源，并分别映射 Claude wrapper 与共享规则。
- Modify: `home/.pi/agent/settings.json:1-14` - 声明两个精确版本的 Pi npm 包。
- Modify: `tests/pi-config.sh:1-84` - 覆盖 Home Manager 映射、Claude 安全边界、Pi 精确 pin 和运行时目录边界。

---

### Task 1: 用安全的 Claude wrapper 替代共享文件直链

**Files:**
- Create: `home/CLAUDE.md`
- Modify: `home.nix:3-8,141-145`
- Test: `tests/pi-config.sh:11-32`

**Interfaces:**
- `~/.claude/CLAUDE.md` 必须来自仓库的 `home/CLAUDE.md`。
- `~/.claude/AGENTS.md`、`~/.codex/AGENTS.md` 和 `~/.config/opencode/AGENTS.md` 必须继续共享 `home/AGENTS.md`。
- Claude wrapper 的有效指令必须只有 `@AGENTS.md`，并且不能与共享规则源使用同一个 Home Manager source。

- [ ] **Step 1: 先加入会失败的 Home Manager 映射测试**

在 `tests/pi-config.sh` 的 `managed_path` 列表中加入四个 agent context 路径：

```bash
  .claude/CLAUDE.md \
  .claude/AGENTS.md \
  .codex/AGENTS.md \
  .config/opencode/AGENTS.md; do
```

在 managed/unmanaged 路径检查之后加入 source 分离与 wrapper 内容检查：

```bash
managed_source() {
  nix eval --raw \
    "$repo_dir#darwinConfigurations.mac.config.home-manager.users.$primary_user.home.file.\"$1\".source"
}

claude_wrapper_source="$(managed_source .claude/CLAUDE.md)"
claude_agents_source="$(managed_source .claude/AGENTS.md)"

if [[ "$claude_wrapper_source" == "$claude_agents_source" ]]; then
  printf '%s\n' 'Claude wrapper must not point directly at shared AGENTS.md.' >&2
  exit 1
fi

diff -u \
  <(printf '%s\n' \
    '<!-- Claude Code compatibility bridge. Shared instructions are maintained in AGENTS.md. -->' \
    '' \
    '@AGENTS.md') \
  "$repo_dir/home/CLAUDE.md"

if cmp -s "$repo_dir/home/CLAUDE.md" "$repo_dir/home/AGENTS.md"; then
  printf '%s\n' 'Claude wrapper must remain separate from shared AGENTS.md.' >&2
  exit 1
fi
```

- [ ] **Step 2: 运行单项测试并确认它以预期原因失败**

Run:

```bash
bash tests/pi-config.sh
```

Expected: 非零退出，首先报告 Home Manager 尚未管理 `.claude/AGENTS.md`，或在后续检查中报告 Claude wrapper 与共享 AGENTS source 相同。不能出现 Nix 求值语法错误。

- [ ] **Step 3: 创建最小 Claude wrapper**

创建 `home/CLAUDE.md`，精确内容为：

```md
<!-- Claude Code compatibility bridge. Shared instructions are maintained in AGENTS.md. -->

@AGENTS.md
```

- [ ] **Step 4: 在 Home Manager 中分离 wrapper 与共享规则 source**

在 `home.nix` 的 `let` 中保留 `sharedAgentContext`，并增加：

```nix
  claudeContext = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/CLAUDE.md";
```

将 agent 配置映射改为：

```nix
    ".claude/settings.json".source      = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
    ".claude/CLAUDE.md".source          = claudeContext;
    ".claude/AGENTS.md".source          = sharedAgentContext;
    ".codex/AGENTS.md".source           = sharedAgentContext;
    ".config/opencode/AGENTS.md".source = sharedAgentContext;
```

- [ ] **Step 5: 运行 Claude 和现有 Pi 配置测试**

Run:

```bash
bash tests/pi-config.sh
```

Expected: `Pi configuration tests passed.`

- [ ] **Step 6: 检查本任务 diff 和用户文件边界**

Run:

```bash
git diff --check
git status --short
```

Expected: 只有 `home/CLAUDE.md`、`home.nix`、`tests/pi-config.sh` 和本计划文件属于本次工作；`home/.claude/settings.json.bak` 仍保持未跟踪且内容未变。

- [ ] **Step 7: 提交 Claude wrapper 变更**

```bash
git add home/CLAUDE.md home.nix tests/pi-config.sh
git commit -m "fix: isolate Claude agent instructions"
```

### Task 2: 声明并验证精确版本的 Pi packages

**Files:**
- Modify: `home/.pi/agent/settings.json:8-14`
- Modify: `tests/pi-config.sh:34-39`

**Interfaces:**
- `settings.json.packages` 必须严格等于 `npm:pi-web-access@0.29.0` 与 `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7`。
- Home Manager 仍只管理 settings 和两个精确资源文件，不管理 Pi 的 npm 下载目录或认证数据。
- Pi 0.83 必须能在隔离配置目录中安装两个 package、验证安装的精确版本，并在不调用 provider 的情况下加载两者的 extension resource；不得读取真实 HOME 中的凭证或会话。

- [ ] **Step 1: 用精确数组断言替换旧的无 packages 断言**

将 `tests/pi-config.sh` 中：

```bash
jq -e 'type == "object" and (has("packages") | not)' \
  "$repo_dir/home/.pi/agent/settings.json" >/dev/null
```

替换为：

```bash
pi_settings="$repo_dir/home/.pi/agent/settings.json"

jq -e '
  type == "object" and
  .packages == [
    "npm:pi-web-access@0.29.0",
    "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7"
  ] and
  (has("models") | not) and
  (has("npmCommand") | not)
' "$pi_settings" >/dev/null

if jq -er '.packages[]' "$pi_settings" |
  grep -Eqi 'pi-calm|compaction|@(latest|next)$'; then
  printf '%s\n' 'Pi settings contain a forbidden or floating package.' >&2
  exit 1
fi
```

在现有 unmanaged 路径列表中加入 npm 运行时目录：

```bash
  .pi/agent/npm \
```

- [ ] **Step 2: 运行单项测试并确认精确 pin 断言失败**

Run:

```bash
bash tests/pi-config.sh
```

Expected: 非零退出，原因是当前 `settings.json` 没有 `packages` 数组。Task 1 的 Claude 检查应继续通过。

- [ ] **Step 3: 在 Pi settings 中加入两个精确 package source**

在 `home/.pi/agent/settings.json` 的 `collapseChangelog` 后加入逗号和数组，最终尾部为：

```json
  "collapseChangelog": true,
  "packages": [
    "npm:pi-web-access@0.29.0",
    "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7"
  ]
}
```

不要增加 `npmCommand`、provider 配置、API key、browser cookie 配置或 `models`。

- [ ] **Step 4: 运行确定性的仓库级 Pi 测试**

Run:

```bash
bash tests/pi-config.sh
```

Expected: `Pi configuration tests passed.`

- [ ] **Step 5: 在临时 HOME 中执行一次真实 Pi 0.83 package smoke test**

此步骤允许 Pi 访问 npm，但所有安装结果均写入临时目录。它不加入 `tests/run.sh`，避免日常测试依赖网络。`pi list` 只列出 settings 中的 source，不安装 package，也不在 `--no-approve` 下加载 extension，因此不能作为本步骤的验证。

Run:

```bash
test "$(pi --version)" = "0.83.0"

pi_smoke_home="$(mktemp -d)"
trap 'rm -rf "$pi_smoke_home"' EXIT
mkdir -p "$pi_smoke_home/.pi/agent"
cp home/.pi/agent/settings.json "$pi_smoke_home/.pi/agent/settings.json"

# env -i prevents npm and Pi from inheriting real credential variables.
pi_env=(
  env -i
  PATH="$PATH"
  HOME="$pi_smoke_home"
  PI_CODING_AGENT_DIR="$pi_smoke_home/.pi/agent"
  PI_CODING_AGENT_SESSION_DIR="$pi_smoke_home/sessions"
  PI_TELEMETRY=0
  NPM_CONFIG_USERCONFIG="$pi_smoke_home/npmrc"
  NPM_CONFIG_CACHE="$pi_smoke_home/npm-cache"
)

"${pi_env[@]}" pi install npm:pi-web-access@0.29.0 --no-approve
"${pi_env[@]}" pi install npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7 --no-approve

jq -e '.packages == [
  "npm:pi-web-access@0.29.0",
  "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7"
]' "$pi_smoke_home/.pi/agent/settings.json" >/dev/null

web_manifest="$pi_smoke_home/.pi/agent/npm/node_modules/pi-web-access/package.json"
codex_fast_manifest="$pi_smoke_home/.pi/agent/npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode/package.json"
jq -e '.name == "pi-web-access" and .version == "0.29.0"' "$web_manifest" >/dev/null
jq -e '.name == "@ryan_nookpi/pi-extension-codex-fast-mode" and .version == "0.2.7"' "$codex_fast_manifest" >/dev/null

# Packages are already installed. Offline RPC startup loads extensions without
# provider calls; get_commands exposes resources registered by those extensions.
printf '%s\n' '{"id":"commands","type":"get_commands"}' |
  "${pi_env[@]}" PI_OFFLINE=1 pi --mode rpc --no-session --no-approve \
    >"$pi_smoke_home/rpc.jsonl"

! grep -Fq '"type":"extension_error"' "$pi_smoke_home/rpc.jsonl"
jq -e '
  (if type == "array" then .[] else . end)
  | select(.id == "commands" and .type == "response" and .success)
  | ([.data.commands[] | select(.name == "websearch" and .sourceInfo.source == "npm:pi-web-access@0.29.0")] | length == 1)
    and ([.data.commands[] | select(.name == "codex-fast" and .sourceInfo.source == "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7")] | length == 1)
' "$pi_smoke_home/rpc.jsonl" >/dev/null

# Pi may create an empty auth.json, but the isolated run must contain no auth
# entries and no saved session files.
test ! -e "$pi_smoke_home/.pi/agent/auth.json" ||
  jq -e 'type == "object" and keys == []' "$pi_smoke_home/.pi/agent/auth.json" >/dev/null
test ! -d "$pi_smoke_home/sessions" ||
  test -z "$(find "$pi_smoke_home/sessions" -type f -print -quit)"
```

Expected: 两个 `pi install` 命令退出 0；两个 package manifest 分别精确为 `pi-web-access@0.29.0` 和 `@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7`；离线 RPC 返回 `websearch` 与 `codex-fast` 两个 command，且 `sourceInfo.source` 分别为两个精确 npm source。不存在 extension error、认证条目或 session 文件。测试 shell 退出时由 `trap` 删除下载结果。

如果 npm 直连只因当前网络超时，保持同一个临时 HOME，并仅为失败的 `pi install` 命令重试一次：

```bash
proxy_pi_env=(
  "${pi_env[@]}"
  https_proxy=http://127.0.0.1:7897
  http_proxy=http://127.0.0.1:7897
  all_proxy=socks5://127.0.0.1:7897
)
"${proxy_pi_env[@]}" pi install npm:pi-web-access@0.29.0 --no-approve
# Or rerun the codex-fast command above if that was the command that timed out.
```

若错误属于 package API 不兼容、模块加载、资源注册或 manifest version 不匹配，不得用代理掩盖，必须停在本步骤诊断。

- [ ] **Step 6: 运行完整仓库测试和静态检查**

Run:

```bash
bash tests/run.sh
git diff --check
```

Expected: 输出 `All tests passed.`，且 `git diff --check` 无输出。不要运行 `rebuild.sh` 本体；`tests/run.sh` 中的 `tests/rebuild.sh` 只是脚本测试，不会激活系统。

- [ ] **Step 7: 审计最终 diff 和敏感数据边界**

Run:

```bash
git diff -- home.nix home/CLAUDE.md home/.pi/agent/settings.json tests/pi-config.sh
git status --short
git diff -- home/.pi/agent/extensions/terminal-status-title.js
```

Expected:

- package 数组只有两个精确 pin。
- 没有 `auth.json`、API key、Cookie、session、npm 下载目录或 `models.json`。
- terminal title 扩展没有 diff，现有 `ORCA_PANE_KEY` 防护仍在。
- `home/.claude/settings.json.bak` 仍未跟踪且未加入暂存区。

- [ ] **Step 8: 提交 Pi package 声明**

```bash
git add home/.pi/agent/settings.json tests/pi-config.sh
git commit -m "feat: manage Pi packages declaratively"
```

### Task 3: 提交后验证和交接

**Files:**
- Verify only: repository worktree and the two new commits

**Interfaces:**
- 本阶段不修改文件，不运行 rebuild，不合并其他分支。

- [ ] **Step 1: 从已提交状态重复核心验证**

Run:

```bash
bash tests/run.sh
git diff --check
git log -3 --oneline
git status --short
```

Expected: 完整测试通过；最近历史包含 Claude wrapper 与 Pi packages 两个提交；工作区只剩计划文件和用户原有的 `home/.claude/settings.json.bak`，除非执行者另行提交了计划文件。

- [ ] **Step 2: 向用户交接手动激活步骤**

报告已通过的静态测试与隔离 Pi 0.83 smoke test，并明确说明尚未执行 `./rebuild.sh`。提醒用户在方便时自行运行：

```bash
./rebuild.sh
```

Home Manager 激活后，Claude 会读取 wrapper 再导入共享规则；Pi 下次启动时会在真实用户目录中安装缺少的两个精确版本包。
