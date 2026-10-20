# 配置维护

以下命令均在仓库根目录执行。

## 工具与依赖

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

## IDE 配置与插件

VS Code 与 Antigravity IDE 共用 `home/ide/settings.json`。每次 `rebuild.sh` 在系统配置
应用成功后，以当前用户身份更新两个 IDE 的全局 `settings.json` 并安装插件。
配置按仓库版本整体替换；内容不同时先在原文件旁保存 `settings.json.backup.*`，
相同则不重复备份。每个 IDE 先查询一次已装插件，跳过已有项，只安装缺失项；
已有的其他插件不会卸载。查询失败时跳过该 IDE 的插件安装并报错；
安装失败会继续尝试其余插件并最终报错。

共享插件清单保存在 `home/ide/extensions.json` 的 `recommendations` 数组，
来自 Antigravity IDE 已装的用户插件，不包含内置插件、不锁定版本。VS Code 额外通过 `home/ide/vscode/extensions.json`
安装 Tokyo Night（Antigravity IDE 已内置该主题）。以后新增插件后可手动刷新清单：

```bash
set -o pipefail
"/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide" \
  --list-extensions | LC_ALL=C sort -u | \
  jq -Rn '{recommendations: [inputs | select(length > 0)]}' > home/ide/extensions.json
```

清单使用 VS Code 标准的 `extensions.json` 结构；它本身只声明推荐插件，
全局安装由同步脚本读取 `recommendations` 后调用 IDE CLI 完成。

仅同步 IDE 而不重建系统时，可运行 `bash scripts/sync-editors.sh`。
两个 IDE 必须已安装，插件下载需要网络；配置写入默认用户目录，不处理命名 Profile。
Antigravity 的插件查询与安装使用 Home Manager 安装的 Node 运行其内置 `out/cli.js`，
绕开 Electron 运行时的偶发 V8 崩溃；应用文件保持原样。
