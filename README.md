# dotfiles

个人 Apple Silicon macOS 配置，使用 nix-darwin、Home Manager 和 Homebrew
统一管理系统设置、开发工具、应用与 dotfiles，使用 SOPS 加密保存秘密。

## Quick start

克隆仓库并进入目录。

首次部署前，将已有的 SOPS age identity 恢复到
`~/Library/Application Support/sops/age/keys.txt`，目录权限设为 `0700`，
文件权限设为 `0600`，然后运行：

```bash
./bootstrap.sh
```

应用配置：

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
