# dotfiles

个人 Apple Silicon macOS 配置，使用 nix-darwin、Home Manager 和 Homebrew
统一管理系统设置、开发工具、应用与 dotfiles，使用 SOPS 加密保存秘密。

## Quick start

在新的 Apple Silicon Mac 上，按以下顺序完成首次安装。

1. **创建管理员用户。** macOS 首次设置时，账户短名称建议使用 `rich`。
   使用其他名称也可以，bootstrap 会提示修改配置中的用户名。

2. **获取安装包和配置。** 在旧 Mac 下载官方 SFM `.pkg` 安装包，并准备好以下三个文件：

   | 文件              | 旧 Mac 上的位置                                   |
   | ----------------- | ------------------------------------------------- |
   | SFM 安装包        | 刚下载的 `SFM-…-Universal.pkg`                    |
   | 代理配置          | `~/.local/state/sing-box/config.json`             |
   | SOPS age 解密密钥 | `~/Library/Application Support/sops/age/keys.txt` |

   在旧 Mac 的终端中定位配置和密钥：

   ```bash
   open -R "$HOME/.local/state/sing-box/config.json"
   open -R "$HOME/Library/Application Support/sops/age/keys.txt"
   ```

   通过 AirDrop、加密存储设备等安全方式，将三个文件一次传到新 Mac。
   以下步骤假设它们保存在新机的 `~/Downloads`，位置不同时调整对应路径。
   使用原有 age 密钥，不要重新生成。代理配置和密钥都包含秘密，
   不要提交到 Git 或通过明文消息发送，全部使用完后清理传输用的临时副本。

3. **准备网络。** 打开收到的 `.pkg` 安装 SFM。在 SFM 中选择“文件 → 从文件导入”，
   导入 `~/Downloads/config.json`，
   按提示批准网络扩展和 VPN 权限，然后连接。用浏览器确认能打开 GitHub，再继续。
   后续安装期间保持 SFM 连接。

4. **安装 Command Line Tools。** 打开新机终端执行，在弹窗中确认安装并等待完成：

   ```bash
   xcode-select --install
   ```

   完成后检查：

   ```bash
   xcode-select -p
   git --version
   ```

5. **配置 GitHub SSH。** 将下面的示例邮箱替换为你的 GitHub 邮箱，再生成密钥。
   按提示回车使用默认路径并设置口令。如果已有密钥，不要覆盖。

   ```bash
   mkdir -p "$HOME/.ssh"
   chmod 700 "$HOME/.ssh"
   ssh-keygen -t ed25519 -C "your_email@example.com"
   eval "$(ssh-agent -s)"
   /usr/bin/ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
   pbcopy < "$HOME/.ssh/id_ed25519.pub"
   ```

   登录 GitHub，进入 **Settings → SSH and GPG keys → New SSH key**
   （[直接打开](https://github.com/settings/ssh/new)）。填写电脑名称，
   选择 **Authentication Key**，粘贴刚复制的公钥并保存。然后验证连接：

   ```bash
   ssh -T git@github.com
   ```

   首次连接时，核对 [GitHub 官方主机指纹](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
   后输入 `yes`。看到 `You've successfully authenticated` 即可继续；退出码 `1` 是正常的。

6. **克隆仓库。** 使用 SSH 下载到新机：

   ```bash
   mkdir -p "$HOME/GitHub/laozhu"
   git clone git@github.com:laozhu/dotfiles.git "$HOME/GitHub/laozhu/dotfiles"
   ```

7. **恢复解密密钥。** 将准备好的 `keys.txt` 移到目标位置，并设置权限：

   ```bash
   mkdir -p "$HOME/Library/Application Support/sops/age"
   chmod 700 "$HOME/Library/Application Support/sops/age"
   mv "$HOME/Downloads/keys.txt" "$HOME/Library/Application Support/sops/age/keys.txt"
   chmod 600 "$HOME/Library/Application Support/sops/age/keys.txt"
   ```

8. **选择电脑用途并运行 bootstrap。** 在新机终端进入仓库，不要在命令前加 `sudo`：

   ```bash
   cd "$HOME/GitHub/laozhu/dotfiles"
   ```

   根据电脑用途，选择下面一条命令。

   **家用电脑**：安装 shared 和 home only 软件。

   ```bash
   ./bootstrap.sh --profile home
   ```

   **工作电脑**：安装 shared 和 work only 软件。

   ```bash
   ./bootstrap.sh --profile work
   ```

   各组软件见 [软件安装列表](docs/software.md)。首次运行会显示当前电脑名称，直接回车则保留现有设置。
   如需改名，输入例如 `rich-macbook`，使用 1-63 个英文字母、数字或连字符，首尾须为字母或数字，不加 `.local`。
   输入新名称后，脚本会将 `ComputerName`、`LocalHostName`、`HostName` 设为该名称；macOS 自动提供 `rich-macbook.local` 局域网地址。
   确认沿用或改名成功后记录在本机 `~/.config/dotfiles/hostname`，重跑时跳过；如需重新设置，可删除此标记后重跑。
   按提示输入管理员密码，
   脚本会安装 Nix、命令行工具和桌面应用，并同步 VS Code、Antigravity 的配置与插件。
   完成后重新打开终端。

   分组保存在本机的 `~/.config/dotfiles/profile`，不提交到仓库。
   安装中断后，重新运行 `./bootstrap.sh` 会沿用已选分组；首次运行必须指定 `--profile`。
   已有分组时，指定另一个分组会停止。日常更新使用下方的 `rebuild.sh`，自动读取本机分组。
   代理配置后续变更时，按 [SFM 文档](docs/sing-box.md) 重新导入。

## 软件分组与安装检查

`software.json` 是软件名称、类型、安装来源和分组的统一清单，Nix 与检查脚本共用：

- `shared`：两台 Mac 共用的应用和开发工具，包括 OrbStack、Python、OpenJDK、Gradle。
- `home`：Steam、UU 加速器、Logitech G HUB、腾讯会议，以及人工安装的 RabbitPro。
- `work`：Slack、NordPass / np、Granola、Loom、Atlassian / Slack CLI、AWS / SAM、Temporal。

Kotlin 由各项目的 Gradle 插件管理，不安装全局编译器。Bitdefender 列为 work 的人工项，
需使用公司的安装包或 MDM；RabbitPro 列为 home 的人工项。这两个软件只检测安装状态，不由 bootstrap/rebuild 安装。
Homebrew Python 优先于系统 Python，
OpenJDK 使用 Homebrew 默认版本，Gradle 使用对应的 `JAVA_HOME`。

查看本机标记及安装状态（需要 Node.js，bootstrap 会安装）：

```bash
cat "$HOME/.config/dotfiles/profile"
node scripts/software-inventory.mjs --profile home
```

工作电脑改为 `--profile work`；不传参数会列出所有分组。也可以只列 shared 或导出 JSON：

```bash
node scripts/software-inventory.mjs --group shared
node scripts/software-inventory.mjs --profile home --json
```

默认输出 Markdown 表格，可重定向为文件。Git、Bash/Zsh、GNU Make、GCC、curl、unzip 等
基础工具保留现有 Nix 配置，但不列入软件表格；明确替换系统版本的 Homebrew Python 仍显示。
检查只读取应用文件和可执行路径，不启动应用、
不读取凭证，也不代表应用已登录、系统权限已批准或服务可正常运行。安装方式表示配置声明的来源。
OrbStack 首次启动后会准备 Docker、Compose 和 buildx，仍需按提示完成初始化。
sing-box CLI 仅用于配置校验，不启动独立服务；代理运行和 TUN 由 SFM 负责。

已有机器首次使用分组时，在运行 rebuild 前保存一次标记：

```bash
mkdir -p "$HOME/.config/dotfiles"
printf 'home\n' > "$HOME/.config/dotfiles/profile"
```

工作机写入 `work`。不要随意修改已有标记：Homebrew 的 `cleanup = "zap"` 会移除当前分组外的软件，
可能同时清理应用数据。日常 rebuild 自动读取标记；缺少或无效时停止。

## 日常维护

以下命令在仓库根目录执行。

格式化源码，或只检查格式（不改文件）：

```bash
./format.sh
./format.sh --check
```

脚本通过 Nix 临时提供项目锁定版本的 Oxfmt、shfmt、nixfmt 和 StyLua，无需全局安装。
工具二进制缓存在 `/nix/store`，不加入日常 Shell 的 PATH；没有预编译缓存时会报错，不在本机编译。
格式化跳过 SOPS 密文、锁文件和生成的版本记录。
CI 分别执行 `format:check` 和 `test`；本地运行测试使用 `bash tests/run.sh`。

应用当前配置：

```bash
./rebuild.sh
```

更新依赖并应用配置：

```bash
./rebuild.sh --update
```

`--update` 按本机分组选择依赖；home 会跳过 NordPass、Atlassian 等 work 专用源。
更新需要可用的 GitHub 连接；首次使用 GitHub CLI 时先执行 `gh auth login`。
安装优先使用官方二进制和预编译缓存；bootstrap、rebuild 与 CI 共用 `nix-caches.conf`，
其中的 sops-nix 上游缓存可减少首次安装的源码编译。详见 [配置维护](docs/configuration.md#二进制优先与缓存)。
若软件下载失败，导致新代理规则也无法发布，见 [独立生成代理配置](docs/sing-box.md#rebuild-被软件下载卡住时)。

## 参考资料

项目指南：

- [软件安装列表](docs/software.md)：shared、home only、work only 分组、安装方式与本机状态检查。
- [配置维护](docs/configuration.md)：配置文件分工、依赖更新、IDE 同步与验证。
- [sing-box 与 SFM](docs/sing-box.md)：配置发布、导入、分流与故障恢复。

官方文档与上游说明：

| 主题             | 参考资料                                                                                                                                                                            |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nix 安装与使用   | [Determinate Nix](https://docs.determinate.systems/)、[Nix 手册](https://nix.dev/manual/nix/latest/)                                                                                |
| macOS 与用户配置 | [nix-darwin 配置选项](https://nix-darwin.github.io/nix-darwin/manual/)、[Home Manager 手册](https://nix-community.github.io/home-manager/)                                          |
| Homebrew 管理    | [Homebrew 命令手册](https://docs.brew.sh/Manpage)、[nix-homebrew](https://github.com/zhaofengli/nix-homebrew)                                                                       |
| 秘密与密钥       | [SOPS](https://getsops.io/docs/)、[age](https://github.com/FiloSottile/age)、[sops-nix](https://github.com/Mic92/sops-nix)                                                          |
| 代理与客户端     | [SFM 下载与说明](https://sing-box.sagernet.org/clients/apple/)、[sing-box 配置](https://sing-box.sagernet.org/configuration/)、[版本迁移](https://sing-box.sagernet.org/migration/) |
| IDE 插件管理     | [VS Code 命令行](https://code.visualstudio.com/docs/configure/command-line)                                                                                                         |
| AI 工具打包      | [llm-agents.nix](https://github.com/numtide/llm-agents.nix)                                                                                                                         |
| GitHub 认证      | [配置 SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)                                                                                                 |

配置学习参考：[kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles/)。
本项目的许多配置思路学习自该仓库，感谢作者的分享。
