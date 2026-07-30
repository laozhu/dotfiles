# Local Development Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 声明式安装 OrbStack、Logitech G Hub、Steam、网易 UU 加速器、Orca、uv 和 Bitwarden Secrets Manager CLI。

**Architecture:** macOS GUI 应用继续由 nix-darwin 的 Homebrew Cask 配置管理，CLI 工具继续由 Home Manager 的 `home.packages` 管理。Orca 的第三方 Homebrew tap 作为非 flake input 锁定，并通过 nix-homebrew 映射，以兼容 `mutableTaps = false`。

**Tech Stack:** Nix flakes、nix-darwin、nix-homebrew、Home Manager、Homebrew Cask

## Global Constraints

- OrbStack 负责 Docker Engine、Docker CLI、Docker Compose 和 Buildx。
- 不安装 `docker-client`、`docker-compose`、`docker-buildx`、Colima、Podman Desktop 或 Docker Desktop。
- `pkgs.bws` 只安装 CLI，不配置 `BWS_ACCESS_TOKEN`，不修改 `secrets.yaml`。
- Orca 必须使用完整 token `stablyai/orca/orca`，不能使用 Homebrew Core 中同名的 Plotly Orca。
- 所有新增 GUI 应用由 Cask 管理，所有新增 CLI 工具由 Nix 管理。

---

### Task 1: 锁定 Orca tap 并声明 GUI 应用

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `configuration.nix`

**Interfaces:**
- Consumes: 现有 `inputs.homebrew-core`、`inputs.homebrew-cask` 和 `nix-homebrew.taps`
- Produces: 锁定的 `inputs.orca-tap`、`stablyai/orca` tap 和五个新增 Cask 声明

- [ ] **Step 1: 记录变更前缺失状态**

Run:

```bash
rg -n 'orca-tap|stablyai/orca|orbstack|logitech-g-hub|steam|uu-booster' flake.nix configuration.nix
```

Expected: 没有匹配项，退出状态为 1。

- [ ] **Step 2: 在 flake 中锁定官方 Orca tap**

在 `inputs` 中加入：

```nix
orca-tap = {
  url = "github:stablyai/homebrew-orca";
  flake = false;
};
```

在 `nix-homebrew.taps` 中加入：

```nix
"stablyai/orca" = inputs.orca-tap;
```

- [ ] **Step 3: 更新 Orca tap 的 lock 节点**

Run:

```bash
nix flake update orca-tap
```

Expected: `flake.lock` 新增 `orca-tap` 节点，命令退出状态为 0。

- [ ] **Step 4: 声明 tap 和五个 Cask**

在 `configuration.nix` 的 `homebrew.taps` 中加入：

```nix
"stablyai/orca"
```

在 `homebrew.casks` 中加入：

```nix
"orbstack"
"logitech-g-hub"
"steam"
"uu-booster"
"stablyai/orca/orca"
```

- [ ] **Step 5: 验证 flake 和 Cask 声明**

Run:

```bash
nix flake metadata --offline
nix eval --offline --raw '.#darwinConfigurations.mac.config.homebrew.casks' --apply 'xs: builtins.concatStringsSep "\n" xs'
nix eval --offline --raw '.#darwinConfigurations.mac.config.homebrew.taps' --apply 'xs: builtins.concatStringsSep "\n" xs'
```

Expected:

- metadata 可离线解析。
- Cask 输出包含 `orbstack`、`logitech-g-hub`、`steam`、`uu-booster`、`stablyai/orca/orca`。
- tap 输出包含 `stablyai/orca`。

- [ ] **Step 6: 提交 GUI 与 tap 配置**

```bash
git add flake.nix flake.lock configuration.nix
git commit -m "feat: add local development desktop apps"
```

### Task 2: 声明 uv 和 bws CLI

**Files:**
- Modify: `home.nix`

**Interfaces:**
- Consumes: 当前锁定 nixpkgs 的 `pkgs.uv` 和 `pkgs.bws`
- Produces: 用户 profile 中的 `uv` 和 `bws` 可执行文件

- [ ] **Step 1: 验证锁定 nixpkgs 提供包**

Run:

```bash
nix eval --offline --json '.#darwinConfigurations.mac.pkgs' --apply 'p: { uv = p.uv.pname; bws = p.bws.pname; }'
```

Expected:

```json
{"bws":"bws","uv":"uv"}
```

- [ ] **Step 2: 加入 Home Manager 包列表**

在 `home.nix` 的运行时依赖区域加入：

```nix
pkgs.uv
pkgs.bws
```

- [ ] **Step 3: 验证 Home Manager 最终包集合**

Run:

```bash
nix eval --offline --json '.#darwinConfigurations.mac.config.home-manager.users.rich.home.packages' --apply 'xs: map (x: x.pname or x.name) xs' | jq -e 'index("uv") != null and index("bws") != null'
```

Expected: 输出 `true`，退出状态为 0。

- [ ] **Step 4: 提交 CLI 配置**

```bash
git add home.nix
git commit -m "feat: install uv and Bitwarden Secrets Manager CLI"
```

### Task 3: 验证完整配置

**Files:**
- Verify: `flake.nix`
- Verify: `flake.lock`
- Verify: `configuration.nix`
- Verify: `home.nix`

**Interfaces:**
- Consumes: Tasks 1 和 2 的声明式配置
- Produces: 可求值且无重复容器运行时的最终 darwin 配置

- [ ] **Step 1: 解析 Nix 文件**

Run:

```bash
nix-instantiate --parse flake.nix >/dev/null
nix-instantiate --parse configuration.nix >/dev/null
nix-instantiate --parse home.nix >/dev/null
```

Expected: 三条命令均退出状态为 0。

- [ ] **Step 2: 检查禁止的重复容器工具**

Run:

```bash
if rg -n 'pkgs\.(docker|docker-client|docker-compose|docker-buildx|colima|podman)|"(docker-desktop|podman-desktop)"' home.nix configuration.nix; then
  exit 1
fi
```

Expected: 没有匹配项，退出状态为 0。

- [ ] **Step 3: 求值完整 darwin system**

Run:

```bash
nix eval --offline --raw '.#darwinConfigurations.mac.system.drvPath'
```

Expected: 输出以 `/nix/store/` 开头并以 `.drv` 结尾的路径。

- [ ] **Step 4: 检查差异和工作树**

Run:

```bash
git diff --check
git status --short
git log -5 --oneline
```

Expected: `git diff --check` 通过；除了本计划文档外工作树干净。

- [ ] **Step 5: 用户侧安装与运行时验证**

用户运行：

```bash
./rebuild.sh
uv --version
bws --version
docker version
docker compose version
docker buildx version
docker context show
```

Expected:

- `uv` 和 `bws` 输出版本。
- 首次打开 OrbStack 并完成 macOS 授权后，Docker、Compose 和 Buildx 可用。
- `docker context show` 输出 `orbstack`。
