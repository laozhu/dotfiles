# dotfiles

个人 Apple Silicon macOS 配置，使用 nix-darwin、Home Manager 和 Homebrew
统一管理系统设置、开发工具、应用与 dotfiles，使用 SOPS 加密保存秘密。

## Quick start

在新的 Apple Silicon Mac 上，按以下顺序完成首次安装。

1. **创建管理员用户。** macOS 首次设置时，账户短名称建议使用 `rich`。
   使用其他名称也可以，bootstrap 会提示修改配置中的用户名。

2. **获取安装包和配置。** 在旧 Mac 下载官方 SFM `.pkg` 安装包，并准备好以下三个文件：

   | 文件 | 旧 Mac 上的位置 |
   | --- | --- |
   | SFM 安装包 | 刚下载的 `SFM-…-Universal.pkg` |
   | 代理配置 | `~/.local/state/sing-box/config.json` |
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

8. **运行 bootstrap。** 在新机终端执行，不要在命令前加 `sudo`：

   ```bash
   cd "$HOME/GitHub/laozhu/dotfiles"
   ./bootstrap.sh
   ```

   按提示输入管理员密码。脚本会安装 Nix、命令行工具和桌面应用，
   并同步 VS Code、Antigravity 的配置与插件。完成后重新打开终端。
   代理配置后续变更时，按 [SFM 文档](docs/sing-box.md) 重新导入。

## 日常维护

以下命令在仓库根目录执行。

应用当前配置：

```bash
./rebuild.sh
```

更新依赖并应用配置：

```bash
./rebuild.sh --update
```

更新需要可用的 GitHub 连接；首次使用 GitHub CLI 时先执行 `gh auth login`。

## 参考资料

项目指南：

- [配置维护](docs/configuration.md)：配置文件分工、依赖更新、IDE 同步与验证。
- [sing-box 与 SFM](docs/sing-box.md)：配置发布、导入、分流与故障恢复。

官方文档与上游说明：

| 主题 | 参考资料 |
| --- | --- |
| Nix 安装与使用 | [Determinate Nix](https://docs.determinate.systems/)、[Nix 手册](https://nix.dev/manual/nix/latest/) |
| macOS 与用户配置 | [nix-darwin 配置选项](https://nix-darwin.github.io/nix-darwin/manual/)、[Home Manager 手册](https://nix-community.github.io/home-manager/) |
| Homebrew 管理 | [Homebrew 命令手册](https://docs.brew.sh/Manpage)、[nix-homebrew](https://github.com/zhaofengli/nix-homebrew) |
| 秘密与密钥 | [SOPS](https://getsops.io/docs/)、[age](https://github.com/FiloSottile/age)、[sops-nix](https://github.com/Mic92/sops-nix) |
| 代理与客户端 | [SFM 下载与说明](https://sing-box.sagernet.org/clients/apple/)、[sing-box 配置](https://sing-box.sagernet.org/configuration/)、[版本迁移](https://sing-box.sagernet.org/migration/) |
| IDE 插件管理 | [VS Code 命令行](https://code.visualstudio.com/docs/configure/command-line) |
| AI 工具打包 | [llm-agents.nix](https://github.com/numtide/llm-agents.nix) |
| GitHub 认证 | [配置 SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) |
