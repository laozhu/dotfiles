# 软件安装列表

安装清单以 [software.json](../software.json) 为准。每台 Mac 安装 shared 和对应的 home only 或 work only。
本页列出配置要求，不记录随机器变化的安装状态。

Git、Bash/Zsh、GNU Make、GCC、curl、unzip 等基础工具保留现有 Nix 配置，按约定不列入本表。
Homebrew Python 是明确替换系统版本的工具，因此保留。RabbitPro 和 Bitdefender 列为人工安装项，
只检测安装状态，bootstrap/rebuild 不负责安装。

## Shared

两台 Mac 共用。

| 软件                                 | 类型      | 命令                   | 安装方式             |
| ------------------------------------ | --------- | ---------------------- | -------------------- |
| ChatGPT                              | GUI       | -                      | Homebrew Cask        |
| Claude                               | GUI       | -                      | Homebrew Cask        |
| Google Gemini                        | GUI       | -                      | Homebrew Cask        |
| Google Chrome                        | GUI       | -                      | Homebrew Cask        |
| Antigravity IDE                      | GUI + CLI | `antigravity-ide`      | Homebrew Cask        |
| VS Code                              | GUI + CLI | `code`                 | Homebrew Cask        |
| WezTerm                              | GUI + CLI | `wezterm`              | Homebrew Cask        |
| SFM                                  | GUI       | -                      | Homebrew Cask        |
| 豆包输入法                           | GUI       | -                      | Homebrew Cask        |
| ImageOptim                           | GUI       | -                      | Homebrew Cask        |
| Keka                                 | GUI       | -                      | Homebrew Cask        |
| Bitwarden                            | GUI       | -                      | Homebrew Cask        |
| 微信                                 | GUI       | -                      | Homebrew Cask        |
| 微信开发者工具                       | GUI + CLI | `cli`                  | Homebrew Cask        |
| OrbStack / Docker / Compose / buildx | GUI + CLI | `orb` / `docker`       | Homebrew Cask        |
| Orca                                 | GUI + CLI | `orca`                 | Homebrew Cask        |
| Codex CLI                            | CLI       | `codex`                | Homebrew Cask        |
| ngrok                                | CLI       | `ngrok`                | Homebrew Cask        |
| Python 3 / pip3                      | CLI       | `python3` / `pip3`     | Homebrew Formula     |
| OpenJDK                              | CLI       | `java` / `javac`       | Homebrew Formula     |
| Gradle                               | CLI       | `gradle`               | Homebrew Formula     |
| im-select                            | CLI       | `im-select`            | Homebrew Formula     |
| mo                                   | CLI       | `mo`                   | Homebrew Formula     |
| ripgrep                              | CLI       | `rg`                   | Nix                  |
| fd                                   | CLI       | `fd`                   | Nix                  |
| fzf                                  | CLI       | `fzf`                  | Nix                  |
| jq                                   | CLI       | `jq`                   | Nix                  |
| yq (Mike Farah)                      | CLI       | `yq`                   | Nix                  |
| Lazygit                              | CLI       | `lazygit`              | Nix                  |
| tig                                  | CLI       | `tig`                  | Nix                  |
| Neovim                               | CLI       | `nvim`                 | Nix                  |
| GitHub CLI                           | CLI       | `gh`                   | Nix                  |
| age                                  | CLI       | `age`                  | Nix                  |
| Bitwarden CLI                        | CLI       | `bw`                   | Nix                  |
| SOPS                                 | CLI       | `sops`                 | Nix                  |
| sing-box                             | CLI       | `sing-box`             | Nix                  |
| wget                                 | CLI       | `wget`                 | Nix                  |
| Node.js / npm / npx                  | CLI       | `node` / `npm` / `npx` | Nix                  |
| pnpm / pnpx                          | CLI       | `pnpm` / `pnpx`        | Nix                  |
| Bun                                  | CLI       | `bun`                  | Nix                  |
| uv / uvx                             | CLI       | `uv` / `uvx`           | Nix                  |
| Bitwarden Secrets Manager            | CLI       | `bws`                  | Nix                  |
| Rust                                 | CLI       | `rustc`                | Nix                  |
| Cargo                                | CLI       | `cargo`                | Nix                  |
| Caddy                                | CLI       | `caddy`                | Nix                  |
| FFmpeg / ffprobe                     | CLI       | `ffmpeg` / `ffprobe`   | Nix                  |
| Herdr                                | CLI       | `herdr`                | Nix                  |
| Kimi Code                            | CLI       | `kimi`                 | Nix                  |
| Pi                                   | CLI       | `pi`                   | Nix                  |
| Hack Nerd Font                       | Font      | -                      | Nix                  |
| Claude Code                          | CLI       | `claude`               | Nix / llm-agents.nix |
| Antigravity CLI                      | CLI       | `agy`                  | Nix / llm-agents.nix |
| Git LFS                              | CLI       | `git-lfs`              | Nix / Home Manager   |
| direnv                               | CLI       | `direnv`               | Nix / Home Manager   |
| Starship                             | CLI       | `starship`             | Nix / Home Manager   |
| Kotlin                               | CLI       | -                      | 项目 Gradle 插件     |

## Home only

仅家用电脑安装，RabbitPro 为人工项。

| 软件           | 类型 | 命令 | 安装方式      |
| -------------- | ---- | ---- | ------------- |
| Steam          | GUI  | -    | Homebrew Cask |
| UU 加速器      | GUI  | -    | Homebrew Cask |
| Logitech G HUB | GUI  | -    | Homebrew Cask |
| 腾讯会议       | GUI  | -    | Homebrew Cask |
| RabbitPro      | GUI  | -    | 人工安装      |

## Work only

仅工作电脑安装，Bitdefender 为人工项。

| 软件          | 类型          | 命令       | 安装方式                 |
| ------------- | ------------- | ---------- | ------------------------ |
| Slack         | GUI           | -          | Homebrew Cask            |
| NordPass      | GUI           | -          | Homebrew Cask            |
| Granola       | GUI           | -          | Homebrew Cask            |
| Loom          | GUI           | -          | Homebrew Cask            |
| Slack CLI     | CLI           | `slack`    | Homebrew Cask            |
| Atlassian CLI | CLI           | `acli`     | Homebrew Formula         |
| NordPass CLI  | CLI           | `np`       | Homebrew Formula         |
| AWS CLI       | CLI           | `aws`      | Homebrew Formula         |
| AWS SAM CLI   | CLI           | `sam`      | Homebrew Formula         |
| Temporal CLI  | CLI           | `temporal` | Homebrew Formula         |
| Bitdefender   | GUI / Service | -          | 公司安装包 / MDM（人工） |

## 安装说明

- **SFM / sing-box**：新机先手动安装 SFM 准备网络，后续由 Homebrew 管理。sing-box CLI
  仅用于配置校验，不启动独立服务；SFM 负责代理运行、Network Extension 和 TUN。
- **OrbStack**：提供 Docker、Compose 和 buildx，不重复安装 Docker Desktop、Podman 或另一套 Compose。
  首次启动时按提示完成初始化。
- **Python / Java**：Python 3 使用 Homebrew 版本并优先于系统 Python；OpenJDK 使用 Homebrew
  默认版本，Gradle 使用对应的 `JAVA_HOME`。Kotlin 由项目 Gradle 插件管理，不安装全局 `kotlinc`。
- **官方二进制**：pnpm、uv、bws、sing-box、Herdr、Kimi Code 和 Pi 由 Nix 管理固定版本的
  官方 macOS 二进制；版本和校验值见 [macos-binaries.json](../macos-binaries.json)。
- **RabbitPro**：用户自行安装到 `/Applications` 或 `~/Applications`，检查脚本会识别这两个位置。
- **Bitdefender**：需使用公司的安装包或 MDM，不通过通用 cask 猜测企业版本。
- **项目格式化工具**：Oxfmt、shfmt、nixfmt、StyLua 通过 `format.sh` 按需提供，不全局安装。

## 开发工具默认设置

两台 Mac 共用以下设置，由 Home Manager 管理：

| 工具   | 默认设置                                                                                    |
| ------ | ------------------------------------------------------------------------------------------- |
| PATH   | 加入 `~/.local/bin`、`~/.cargo/bin`，Homebrew 和 Nix 管理的工具保持优先                     |
| uv     | `python-preference = "system"`，优先使用已安装且满足项目要求的 Python，仍允许下载缺少的版本 |
| Gradle | `~/.gradle/gradle.properties` 启用 `org.gradle.caching=true`，复用构建产物                  |
| fzf    | 普通搜索和 `Ctrl-T` 使用 fd，包含隐藏文件，遵守 `.gitignore` 并排除 `.git`                  |

Gradle 不额外开启全局并行或配置缓存；项目可用 `--no-build-cache` 临时禁用构建缓存。

## 检查本机安装状态

在仓库根目录执行，输出软件名称、分组、类型、声明的安装方式、安装状态及检测依据：

```bash
node scripts/software-inventory.mjs --profile home
```

工作电脑使用 `--profile work`；不指定 profile 则显示全部分组。导出 Markdown 或 JSON：

```bash
node scripts/software-inventory.mjs --profile home > software-status.md
node scripts/software-inventory.mjs --profile home --json
```

脚本需要 Node.js，只读取应用文件和命令路径，不启动应用或读取凭证。
检测结果不代表应用已登录、系统权限已批准或服务可用。安装与分组选择见 [README](../README.md)。
