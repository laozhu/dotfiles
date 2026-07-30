# 本地开发与游戏应用声明式安装设计

## 目标

通过现有 nix-darwin 与 Home Manager 配置，在新 Mac 执行 `./rebuild.sh` 后安装本地容器开发、外设、游戏和密钥管理工具，同时继续维持“GUI 应用由 Homebrew Cask 管理，CLI 工具由 Nix 管理”的单一分工。

## 安装范围

在 `configuration.nix` 的 `homebrew.casks` 中加入：

- `orbstack`
- `logitech-g-hub`
- `steam`
- `uu-booster`
- `stablyai/orca/orca`

在 `home.nix` 的 `home.packages` 中加入：

- `pkgs.uv`
- `pkgs.bws`

在 `flake.nix` 中把 `github:stablyai/homebrew-orca` 声明为非 flake input，并通过 `nix-homebrew.taps` 将其锁定为 `stablyai/orca` tap。这样在 `nix-homebrew.mutableTaps = false` 时，新机器仍可声明式安装 Orca。

## 管理边界

- OrbStack 负责 Docker Engine、Docker CLI、Docker Compose 和 Buildx，不在 Nix 中重复安装 `docker-client`、`docker-compose` 或 `docker-buildx`。
- 使用完整 token `stablyai/orca/orca` 安装 AI Agent 编排应用 Orca，避免误装 Homebrew Core 中同名但已弃用的 Plotly Orca。
- Orca 应用保留其内置更新机制；flake input 负责固定和提供官方 tap，而不是固定 Orca 应用版本。
- `pkgs.bws` 只提供 Bitwarden Secrets Manager CLI。
- 本次不创建 Bitwarden machine account，不配置或注入 `BWS_ACCESS_TOKEN`，也不修改现有 SOPS secrets。
- 现有 `bitwarden` Cask 和 `pkgs.bitwarden-cli` 保持不变，分别继续提供 Password Manager 桌面应用和 `bw` CLI。
- 不安装或启动 Colima、Podman Desktop、Docker Desktop 等第二套容器运行时。

## 验证

在不触发完整系统重建和应用下载的静态验证阶段：

1. 格式化并解析 Nix 配置。
2. 通过 flake 检查或等价的离线求值确认 `pkgs.uv`、`pkgs.bws` 以及 darwin 配置可求值。
3. 确认四个官方 Cask 名称存在于当前 Homebrew Cask 源，并确认 `stablyai/orca/orca` 存在于锁定的官方 Orca tap。
4. 检查最终差异只包含本设计声明的包和相应文档。

用户执行 `./rebuild.sh` 后，可进一步验证：

```bash
uv --version
bws --version
docker version
docker compose version
docker buildx version
docker context show
```

OrbStack 首次启动可能要求用户完成 macOS 权限授权。`docker context show` 应输出 `orbstack`。

## 成功标准

- 新 Mac 可通过一次 rebuild 声明式安装所有七项新增工具。
- GUI 和 CLI 的包管理职责不重叠。
- 不引入第二套 Docker CLI 或容器运行时。
- 不把任何 Bitwarden Secrets Manager 访问令牌写入仓库、Nix store 或普通环境变量配置。
