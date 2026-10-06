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

SFM 配置需要手动导入，操作与恢复步骤见 [sing-box 文档](docs/sing-box.md)。
