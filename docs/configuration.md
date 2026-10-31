# 配置维护

以下命令均在仓库根目录执行。新 Mac 首次安装见 [Quick start](../README.md#quick-start)。

## 修改哪里

| 文件 | 用途 |
| --- | --- |
| `flake.nix` / `flake.lock` | 用户名、系统架构、依赖来源及锁定版本 |
| `configuration.nix` | macOS 设置、Homebrew 软件清单、包覆盖 |
| `home.nix` | 用户命令行工具、Shell、Git 和 dotfiles 映射 |
| `macos-binaries.json` / `macos-binaries.nix` | 官方 macOS 二进制的版本、下载地址、校验值及安装方式 |
| `home/ide/` | VS Code、Antigravity 的共享设置与插件清单 |
| `sing-box.nix` / `home/.config/sing-box/` | 代理配置渲染、校验与发布，详见 [SFM 指南](sing-box.md) |

大多数 dotfiles 通过 `~/.dotfiles` 链接到仓库，修改后应用可能立即读到变化；
新增文件映射、安装软件和系统设置需要 rebuild。
Claude 的 `home/.claude/settings.json` 只在本机配置不存在时复制，后续修改模板不会覆盖本机文件。

## 工具来源与更新

- 常规命令行工具由 Nix / Home Manager 管理；Claude Code、Antigravity CLI 来自 `llm-agents.nix`。
- `pnpm`、`uv`、`bws`、Herdr、Kimi Code、Pi 和 sing-box 使用官方 Apple Silicon 二进制，
  版本及 SHA-256 记录在 `macos-binaries.json`，Nix 负责校验、解包和链接。
- 桌面应用及 Codex CLI 由 Homebrew cask 管理；im-select 来自 `daipeihust/tap`。
  tap 的源码由 `flake.lock` 锁定，实际安装和升级还会受 Homebrew API、应用自动更新影响。

应用当前配置：

```bash
./rebuild.sh
```

更新依赖并应用配置：

```bash
./rebuild.sh --update
```

`--update` 先更新 `flake.lock`，再通过 GitHub CLI 查询对应版本的官方发布包并更新
`macos-binaries.json`，随后校验并应用配置。首次使用 `gh` 时先运行 `gh auth login`。
普通 rebuild 和 bootstrap 使用已有二进制记录，不查询这些发布包的 GitHub API。
缺少发布包或有效 SHA-256 时更新停止，不回退源码编译。

更新失败可能已经改动 `flake.lock`；二进制记录只有全部验证成功后才写入。
提交前检查两个文件，修复失败后再重试：

```bash
git diff -- flake.lock macos-binaries.json
```

Homebrew 激活时会更新、升级软件，并以 `cleanup = "zap"` 清理声明之外的包和 cask，
可能同时清理被移除应用的数据。移除软件声明前先确认本机数据是否需要保留。
Nix 的构建和回退不等于撤销 Homebrew 升级或 IDE 配置写入。

## IDE 配置与插件

bootstrap 和 rebuild 均在系统应用安装成功后，以当前用户执行 `scripts/sync-editors.sh`：

- 将 `home/ide/settings.json` 写入两个 IDE 的默认用户配置。
  内容不同时，先将原文件备份为旁边的 `settings.json.backup.*`；相同则跳过。
- 从 `home/ide/extensions.json` 的 `recommendations` 安装共享插件，
  VS Code 额外读取 `home/ide/vscode/extensions.json`。
- 已安装的插件跳过，其他插件不卸载，插件版本不锁定。
  查询失败会跳过该 IDE 的插件安装；安装失败会继续其余项，最后返回失败。

新增或删除推荐插件，直接编辑相应 JSON 清单。删除清单项不会自动卸载已装插件。
如需查看 Antigravity 已装插件，使用与同步脚本相同的 Node 入口，避开 Electron 启动问题：

```bash
node "/Applications/Antigravity IDE.app/Contents/Resources/app/out/cli.js" --list-extensions
```

仅同步 IDE：

```bash
bash scripts/sync-editors.sh
```

两个 IDE 及 Node、jq 必须已安装，插件下载需要网络；不处理命名 Profile。
Pi 的扩展清单在 `home/.pi/agent/settings.json`，不属于 IDE 同步步骤。
`pi --help` / `pi -h` 禁止启动联网，正常启动和显式安装扩展仍使用原有网络行为。

## 验证修改

```bash
bash tests/run.sh
nix build --dry-run --no-link .#darwinConfigurations.mac.system
```

需要实际验证 Nix 构建时执行：

```bash
nix build --no-link .#darwinConfigurations.mac.system
```

这些 Nix 命令不会激活系统，也不会执行 Homebrew 应用安装。
测试中的 bootstrap 使用临时目录和模拟安装命令，不能替代全新 macOS 上的安装验收。
官方选项和命令说明见 README 的 [参考资料](../README.md#参考资料)。
