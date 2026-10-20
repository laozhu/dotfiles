# dotfiles

个人 Apple Silicon macOS 配置，使用 nix-darwin、Home Manager 和 Homebrew
统一管理系统设置、开发工具、应用与 dotfiles，使用 SOPS 加密保存秘密。

## Quick start

克隆仓库并进入目录。首次部署前，将已有的 SOPS age identity 恢复到
`~/Library/Application Support/sops/age/keys.txt`，目录权限设为 `0700`，
文件权限设为 `0600`。

```bash
./bootstrap.sh
```

脚本安装 Determinate Nix 和 Rosetta 2，创建 `~/.dotfiles` 链接，确认用户名并
应用配置。后续修改或更新依赖时运行：

```bash
./rebuild.sh          # 应用配置
./rebuild.sh --update # 更新依赖并应用配置
```

im-select 通过上游 `daipeihust/tap` 的 Homebrew formula 自动安装，tap 版本由
`flake.lock` 固定。运行 `rebuild.sh` 后可用 `im-select` 查询当前输入法。

Codex CLI 由 Homebrew `codex` cask 安装官方 Apple Silicon 预编译发布包，
不再由 `llm-agents.nix` 从源码编译。`bootstrap.sh` 首次安装，`rebuild.sh`
通过同一份 Homebrew 声明安装或升级；`--update` 同时更新锁定的 cask 定义。
`pnpm`、`uv`、`bws`、`herdr`、Kimi Code、Pi 和 sing-box 也使用官方 Apple Silicon
二进制发布包，Nix 只校验 SHA-256、解包和链接，不编译这些工具。
版本及校验值固定在 `macos-binaries.json`；`--update` 根据更新后的 flake 输入
通过 GitHub CLI 刷新这些记录，需要可用的 GitHub 连接（可先运行 `gh auth login`）。
缺少对应发布包或 SHA-256 时更新失败，不回退源码编译。普通 rebuild 与首次 bootstrap
使用已固定的版本，无需查询 GitHub API。其他 Nix 系统依赖仍可能编译。
单独运行 `pi --help` 或 `pi -h` 时禁用启动联网，避免因缺少扩展触发 npm 安装；
正常启动与扩展安装、更新继续使用原有网络行为。

SFM 配置需要手动导入，操作与恢复步骤见 [sing-box 文档](docs/sing-box.md)。
