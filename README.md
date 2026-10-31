# dotfiles

个人 Apple Silicon macOS 配置，使用 nix-darwin、Home Manager 和 Homebrew
统一管理系统设置、开发工具、应用与 dotfiles，使用 SOPS 加密保存秘密。

## Quick start

在新的 Apple Silicon Mac 上首次安装前，依次完成以下准备：

1. **创建管理员用户。** macOS 首次设置时，将账户短名称设为 `rich`，与当前配置一致，
   可减少安装时的确认步骤。若使用其他名称，bootstrap 会提示修改 `flake.nix`。
   在终端确认当前用户名：

   ```bash
   whoami
   ```

2. **准备网络。** 确保能访问 GitHub、Determinate Nix、Nix 缓存和各应用的下载站点。
   如果需要代理，先配置好可用的网络；bootstrap 安装的 SFM 需要后续手动导入和授权。

3. **安装 Command Line Tools。** 在终端执行，并在弹窗中确认安装，等待完成：

   ```bash
   xcode-select --install
   ```

   安装完成后检查工具路径和 Git：

   ```bash
   xcode-select -p
   git --version
   ```

4. **生成新机器的 SSH 密钥。** 使用 GitHub 账户邮箱作为备注，以下为当前配置使用的邮箱。
   按提示回车采用默认保存位置 `~/.ssh/id_ed25519`，并设置密钥口令。
   如果该位置已有密钥，不要覆盖，确认是否可以复用：

   ```bash
   mkdir -p "$HOME/.ssh"
   chmod 700 "$HOME/.ssh"
   ssh-keygen -t ed25519 -C "laozhu.me@gmail.com"
   ```

   启动 SSH agent 并添加私钥，将口令保存到 macOS 钥匙串：

   ```bash
   eval "$(ssh-agent -s)"
   /usr/bin/ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
   ```

5. **将 SSH 公钥加入 GitHub。** 复制新机器的公钥：

   ```bash
   pbcopy < "$HOME/.ssh/id_ed25519.pub"
   ```

   在浏览器登录 GitHub，进入 **Settings → SSH and GPG keys → New SSH key**
   （[直接打开](https://github.com/settings/ssh/new)）。填写能识别这台电脑的 Title，
   Key type 选择 **Authentication Key**，粘贴公钥并保存。
   只上传 `.pub` 公钥，私钥 `id_ed25519` 留在本机。

   验证连接：

   ```bash
   ssh -T git@github.com
   ```

   首次连接时，核对提示中的主机指纹与
   [GitHub 官方指纹](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
   一致，再输入 `yes`。出现 `Hi laozhu! You've successfully authenticated` 表示验证成功；
   GitHub 不提供 shell，因此此命令成功认证后仍会返回退出码 `1`。
   详细步骤见 [GitHub SSH 文档](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)。

6. **克隆仓库。** 使用 SSH：

   ```bash
   mkdir -p "$HOME/GitHub/laozhu"
   git clone git@github.com:laozhu/dotfiles.git "$HOME/GitHub/laozhu/dotfiles"
   cd "$HOME/GitHub/laozhu/dotfiles"
   ```

7. **恢复已有的 SOPS age 密钥。** 可以从已安装好的旧机器复制
   `~/Library/Application Support/sops/age/keys.txt`，通过 AirDrop、加密存储设备等
   安全方式传到新机；也可以从 Bitwarden 的 `dotfiles - sops age identity` 条目恢复。
   必须使用能解密本仓库的原有密钥，不要重新生成。

   在旧机器上，可用以下命令在 Finder 中定位密钥，再通过安全方式传输：

   ```bash
   open -R "$HOME/Library/Application Support/sops/age/keys.txt"
   ```

   假设新机收到的文件位于 `~/Downloads/keys.txt`，执行以下命令将其移到目标位置，
   并将目录权限设为 `0700`、文件权限设为 `0600`：

   ```bash
   mkdir -p "$HOME/Library/Application Support/sops/age"
   chmod 700 "$HOME/Library/Application Support/sops/age"
   mv "$HOME/Downloads/keys.txt" "$HOME/Library/Application Support/sops/age/keys.txt"
   chmod 600 "$HOME/Library/Application Support/sops/age/keys.txt"
   ```

   如果接收位置不同，请调整源文件路径。不要将密钥提交到 Git 或通过明文消息发送，
   并清理传输介质上的临时副本。密钥必须提前恢复，bootstrap 才能继续安装后续应用。

准备完成后，在仓库目录中以普通用户运行 bootstrap，不要在命令前加 `sudo`。
安装过程中按提示输入管理员密码；脚本会自动验证密钥、安装软件，并同步 IDE 配置与插件：

```bash
cd "$HOME/GitHub/laozhu/dotfiles"
./bootstrap.sh
```

安装完成后重新打开终端。以后应用配置：

```bash
./rebuild.sh
```

更新依赖并应用配置（首次使用 GitHub CLI 时先运行 `gh auth login`）：

```bash
./rebuild.sh --update
```

按 [sing-box 文档](docs/sing-box.md) 手动导入 SFM 配置。

## 文档

- [配置维护](docs/configuration.md)：工具来源、IDE 配置与插件清单维护。
- [sing-box](docs/sing-box.md)：SFM 导入与恢复。
