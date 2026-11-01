# 配置维护

以下命令均在仓库根目录执行。新 Mac 首次安装见 [Quick start](../README.md#quick-start)。

## 修改哪里

| 文件                                         | 用途                                                   |
| -------------------------------------------- | ------------------------------------------------------ |
| `flake.nix` / `flake.lock`                   | 用户名、系统架构、依赖来源及锁定版本                   |
| `configuration.nix`                          | macOS 设置、Homebrew 激活、包覆盖                      |
| `home.nix`                                   | 用户软件接入、Shell、Git 和 dotfiles 映射              |
| `macos-binaries.json` / `macos-binaries.nix` | 官方 macOS 二进制的版本、下载地址、校验值及安装方式    |
| `home/ide/`                                  | VS Code、Antigravity 的共享设置与插件清单              |
| `sing-box.nix` / `home/.config/sing-box/`    | 代理配置渲染、校验与发布，详见 [SFM 指南](sing-box.md) |

`software.json` / `software.nix` 维护 shared、home、work 的软件清单及安装来源；
`scripts/software-inventory.mjs` 使用同一清单检测安装状态。`inventory: false` 只隐藏基础工具的
表格行，不影响安装声明。分组选择与用法见 README。

大多数 dotfiles 通过 `~/.dotfiles` 链接到仓库，修改后应用可能立即读到变化；
新增文件映射、安装软件和系统设置需要 rebuild。
Claude 的 `home/.claude/settings.json` 只在本机配置不存在时复制，后续修改模板不会覆盖本机文件。
Pi 的 `home/.pi/agent/settings.json` 也是模板，但只由 bootstrap 在本机配置不存在时复制，
rebuild 和 Home Manager activation 均不创建或覆盖 Pi settings。已有普通文件始终保留；
bootstrap 遇到旧版软链接时会先将其完整内容转换成普通文件，再执行系统切换。
模板不包含设备标识、已读版本或默认 provider/model。更新模板里的主题或扩展版本后，
需要显式合并到本机配置。
若从旧版软链接配置升级，第一次 rebuild 前先运行一次迁移，避免旧链接随上一代配置被清理：

```bash
bash scripts/init-pi-settings.sh "$HOME/.pi/agent/settings.json" home/.pi/agent/settings.json
```

该命令将可读的旧链接转换为普通文件，保留完整内容；已有普通文件不变。

`configuration.nix` 在 home/work 两组中均将 AirDrop 设为对所有人可见，
并开启触摸板“轻点以点按”。这些设置由首次 bootstrap 和后续 rebuild 应用。

GitHub 多账号的目录切换、SSH key 和首次登录步骤见 [GitHub 目录身份](github-identities.md)。
本仓库为 `Developer/paid-inc`、`Developer/laozhu` 和 `Developer/beebat-dev` 部署父目录 `.envrc`。
工作目录使用默认 gh 配置并可加载本机 `~/.config/paid-inc/secrets.env`；个人目录使用 `gh-laozhu`。
direnv 同步设置账号 actor，并从对应 gh 登录读取 `GITHUB_TOKEN`。Zsh 启动时也从当前 gh
配置读取 token，读取过程忽略继承的 token，凭据不写入模板或日志。

## 工具来源与更新

- 常规命令行工具由 Nix / Home Manager 管理；Claude Code、Antigravity CLI 来自 `llm-agents.nix`。
- `pnpm`、`uv`、`bws`、Herdr、Kimi Code、Pi 和 sing-box 使用官方 Apple Silicon 二进制，
  版本及 SHA-256 记录在 `macos-binaries.json`，Nix 负责校验、解包和链接。
- 桌面应用及 Codex CLI 由 Homebrew cask 管理；im-select、mo、Atlassian CLI 和 NordPass CLI 使用上游 tap。
  Python、OpenJDK、Gradle 及工作机的 AWS、SAM、Temporal 和 Temporal Cloud CLI（`tcld`）使用 Homebrew formula。
  `tcld` 来自官方 `temporalio/brew` tap。
  Brew 与 tap 源码由 `flake.lock` 锁定，核心配方从锁定的 tap 读取，不从 API 加载核心配方。
  应用自动更新、在线安装器和未固定的下载地址仍可能影响实际安装结果。

应用当前配置：

```bash
./rebuild.sh
```

更新依赖并应用配置：

```bash
./rebuild.sh --update
```

`--update` 按本机分组更新 `flake.lock`：home 更新共享依赖，跳过 work 专用的 NordPass、Atlassian、Temporal tap；
work 更新全部依赖。随后通过 GitHub CLI 查询对应版本的官方发布包并更新
`macos-binaries.json`，随后校验并应用配置。首次使用 `gh` 时先运行 `gh auth login`。
普通 rebuild 和 bootstrap 使用已有二进制记录，不查询这些发布包的 GitHub API。
缺少发布包或有效 SHA-256 时更新停止，不回退源码编译。

更新失败可能已经改动 `flake.lock`；二进制记录只有全部验证成功后才写入。
提交前检查两个文件，修复失败后再重试：

```bash
git diff -- flake.lock macos-binaries.json
```

Brew 引擎（`brew-src`）与 taps 都由 `flake.lock` 固定，`--update` 会一起更新，
避免旧引擎无法解析新配方。激活时不运行 `brew update`，仍会安装、升级声明的软件，并以 `cleanup = "zap"` 清理声明之外的包和 cask，
可能同时清理被移除应用的数据。移除软件声明前先确认本机数据是否需要保留。
Nix 的构建和回退不等于撤销 Homebrew 升级或 IDE 配置写入。

G HUB 的安装器可能留下安装记录却没有应用。home 激活后会检查实际应用路径，缺失时自动重跑安装器；
该检查在 Brew bundle 成功返回后执行；重装命令失败，或返回后仍没有应用时会停止。
检查本身会跳过已有应用，但正常 Brew bundle 仍可能升级它。厂商安装器若不退出，检查也会等待，未设置超时。
G HUB 的详细日志由厂商安装器直接输出，目前没有进度条或日志精简功能；
下载失败时先按 [独立发布配置流程](sing-box.md#rebuild-被软件下载卡住时) 更新 SFM 的分流规则。

### 安装日志与终端环境

- **Python / Java**：Homebrew 阶段失败会阻止后续 Home Manager 激活。修复后重跑即可继续；
  成功后打开新终端，让 `python`、`python3`、`pip` 和 `JAVA_HOME` 加载新配置。
  子脚本不能修改已经打开的父终端环境。
- **Git tree has uncommitted changes / updating lock file**：`--update` 会改动版本记录，这些提示正常。
  审查改动后提交即可，不要让脚本自动提交或隐藏未提交修改。
- **Homebrew managed by Nix / Tier 3**：这是 Homebrew 对 Nix 管理方式的支持范围提示，不是安装失败。
- **running through sudo**：系统激活以 sudo 切换回当前用户安装 cask，
  Homebrew 因此提示服务域；不代表启动了 sing-box 服务。
- **Command Line Tools 更新**：通过系统设置的软件更新检查并安装 Apple 提供的更新，
  不删除现有 CLT，不由脚本绕过系统更新授权。
- **quarantine approval / 首次启动授权**：macOS 可能要求重新批准应用，保留系统校验。
  OrbStack 首次运行仍需完成初始化；SFM 升级可能重启应用，安装和后续下载时应确认代理已连接。
- **NordPass TLS 证书错误**：home 不更新该 work 专用源。work 需要代理正确转发其官方域名
  `downloads.npass.app`，且服务提供匹配的有效证书。模板已将 `npass.app` 加入代理 DNS 和路由；
  使用旧 SFM 导入副本时，需按 [SFM 文档](sing-box.md#发布与导入) 导入新配置。
  证书错误时停止并检查网络，不禁用证书校验。

## 二进制优先与缓存

优先使用官方 macOS 二进制、Nix 预编译缓存和 Homebrew bottles；缓存命中时，
使用 Nix 安装的工具不需要在本机编译源码。日志中的 `building` 也可能只是解包、链接或生成配置。

`nix-caches.conf` 声明 [sops-nix 上游](https://github.com/Mic92/sops-nix/blob/master/flake.nix)
提供的二进制缓存和签名公钥。bootstrap、rebuild 通过 `scripts/nix-cache-env.sh` 加载，
并将配置传给 sudo 下的 Nix 构建；CI 通过 Nix 安装 action 读取同一文件。
它补充 Nix 默认缓存，保留已有 `NIX_CONFIG`，不修改 Determinate 管理的 daemon 配置，不关闭签名校验。

普通用户构建若出现 `ignoring untrusted substituter` 或 `trusted-public-keys` 受限警告，
说明客户端提供的配置未被 daemon 接受。Determinate 安装后，在仓库根目录执行一次：

```bash
sudo install -m 644 nix-caches.conf /etc/nix/nix.dotfiles-caches.conf
if ! grep -Fxq '!include nix.dotfiles-caches.conf' /etc/nix/nix.custom.conf; then
  printf '\n!include nix.dotfiles-caches.conf\n' | sudo tee -a /etc/nix/nix.custom.conf >/dev/null
fi
sudo launchctl kickstart -k system/systems.determinate.nix-daemon
```

这保留已有系统配置，由 `nix.custom.conf` 加载缓存和签名公钥，不修改 Determinate
自动生成的 `nix.conf`，也不增加 `trusted-users`。系统配置已包含缓存和公钥时，
`scripts/nix-cache-env.sh` 不再重复传递受限的客户端设置。修改 `nix-caches.conf` 后需重新执行上述步骤。
重启 daemon 前应等待正在运行的 Nix 构建结束。

该缓存用于获取 `sops-install-secrets`，命中时可避免首次安装编译这段 Go 程序。
缓存可用性会随版本变化；缓存缺失不等于软件没有预编译版本，先检查代理、下载和上游缓存。
新增缓存前，先验证可访问性及签名公钥的上游来源；AI CLI 继续使用已经声明的官方二进制。

手动构建并使用项目缓存时，在仓库根目录执行：

```bash
bash -c 'source scripts/nix-cache-env.sh; nix build --no-link .#darwinConfigurations.home.system .#darwinConfigurations.work.system'
```

不能对整套配置设置 `max-jobs = 0`：配置生成、包装和官方二进制解包也需要执行少量本地构建。
格式化工具使用该限制是因为它们本身应直接从缓存获取。

## DeepSeek Harness

GUI 和 CLI 都属于 shared，home/work 两套配置均安装：

- 桌面应用由 Homebrew cask `deepseek-harness` 安装，使用官方 Apple Silicon 下载。
- `dsh` CLI 由已锁定的 `llm-agents.nix` 提供，不另外全局安装 npm CLI。
- CLI 的浏览器界面用 `dsh web` 启动；桌面应用在应用程序目录启动。
- 社区 TUI `@deepseek-harness-tui/dsh-tui` 的版本和 `tui` profile 声明在 `software.json`。
  Home Manager 在 bootstrap 和 rebuild 的系统激活阶段，以当前用户安装插件，之后用 `dsh tui` 启动。
  相同版本及 bundle 已安装时跳过下载；插件版本变化或安装文件缺失时重新安装。
- 同时安装时，保留 Nix 提供的 `dsh`，不必再用桌面应用的 Manage dsh Command 注册同名启动器。

首次构建 CLI 会获取 npm 依赖。实测当前网络直连 npm tarball 超时，显式代理可达，
因此 `registry.npmjs.org` 加入 custom-proxy；更新 SFM 配置后需重新导入，详见 [SFM 指南](sing-box.md)。
登录、API key、会话和用户 profile 保留在本机，不提交到模板中。
移除桌面 cask 前需备份 `~/.dsh`：该 cask 的 zap 清理包含这个目录，可能影响 CLI 数据。

TUI `0.18.0` 已在当前 CLI `0.2.1-rc.5` 下重新验证，交互界面和账号模型请求均成功。
首次启动按向导选择账号和模型；各 profile 的默认模型选择独立，不自动复制桌面版设置。
插件安装使用官方 `dsh plugin --profile tui add ...`，不会重置本机 profile patch、凭据或会话，
也不把可写 profile 变成受管软链接。首次安装需要网络和正常连接的 SFM；安装失败会使激活报错，
修复网络后再次运行 bootstrap/rebuild 即可重试。
更新 TUI 时修改 `software.json` 中的固定版本，并按
[插件项目说明](https://github.com/ccch1mneyyy/dsh-TUI/blob/main/docs/getting-started.en.md)
验证与宿主 CLI 的兼容性，不覆盖宿主版本检查。

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
nix build --dry-run --no-link .#darwinConfigurations.home.system .#darwinConfigurations.work.system
```

需要实际验证 Nix 构建时执行：

```bash
nix build --no-link .#darwinConfigurations.home.system .#darwinConfigurations.work.system
```

这些 Nix 命令不会激活系统，也不会执行 Homebrew 应用安装。
测试中的 bootstrap 使用临时目录和模拟安装命令，不能替代全新 macOS 上的安装验收。
`tests/homebrew-formulae.sh` 在临时前缀中使用实际锁定的 Brew 与 core tap 解析 Java 依赖，
覆盖 Nix 构建本身不会执行的配方兼容性检查，不安装 Homebrew 软件。
G HUB 补装测试用替身覆盖应用存在、缺失、安装失败及假成功；域名测试验证 sing-box 匹配和 DNS/路由引用。
这些测试不验证真实服务器连通性、厂商安装器退出行为、SFM 导入或系统授权。
官方选项和命令说明见 README 的 [参考资料](../README.md#参考资料)。
