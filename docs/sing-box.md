# sing-box 与 SFM

SFM 独占 sing-box 运行时、Network Extension 和 TUN。nix-darwin 负责解密、
渲染、校验和发布配置，Home Manager 提供命令行工具与配置链接。
不要创建额外的 LaunchAgent、LaunchDaemon 或 `sing-box run` 进程。

## 版本与配置来源

当前模板要求 **sing-box / SFM 1.14 或更新版本**。DNS 使用 `evaluate` 和
`match_response` 判断直连 DNS 响应是否为私网地址。`rebuild.sh` 使用即将安装的
Nix 内核预检配置。

升级 SFM 前备份应用、配置和数据库，按
[官方迁移说明](https://sing-box.sagernet.org/migration/#migrate-the-macos-standalone-client-data)
迁移数据。Homebrew 升级 SFM 可能中断连接，应提前准备离线恢复材料。
系统扩展与 VPN 授权在 macOS 界面完成。

- 模板：`home/.config/sing-box/config.json`，持久修改应在这里完成。
- 秘密：`secrets/sing-box.yaml`，只保存 SOPS 密文。
- 已发布配置：`~/.local/state/sing-box/config.json`，通过
  `~/.config/sing-box/config.json` 链接访问。
- SFM 的 `sing-box` Local Profile 是导入副本，配置变化后必须重新导入。
  不要编辑应用私有容器或把 SFM 的临时修改覆盖回仓库。

## 部署与重新导入

在仓库根目录运行：

```bash
./rebuild.sh
bash scripts/check-sing-box-config.sh
open -a SFM
```

`rebuild.sh` 不负责启停 SFM。首次部署前，断开其他代理客户端，确认没有独立
sing-box 核心或端口冲突。

1. 在 SFM 中断开 VPN。
2. 选择“文件” -> “从文件导入”，按 `Command-Shift-G` 输入
   `/Users/rich/.config/sing-box/config.json`。
3. 删除或替换旧副本，只保留一个名为 `sing-box` 的 Local Profile。
4. 连接并检查下面的运行状态。首次使用时按 macOS 提示授权。

每次修改模板、规则或秘密后，重复以上步骤。

## 运行检查

```bash
pgrep -alf 'sing-box|SFM'
launchctl list | rg -i 'sing-box|sfm'
lsof -nP -iTCP:7777 -sTCP:LISTEN
lsof -nP -iTCP:9090 -sTCP:LISTEN
netstat -anv -p tcp | rg '[.:](7777|9090).*LISTEN'
```

- 只有 SFM 管理的一个核心，`127.0.0.1:7777` 有一个 mixed 入站监听。
- 没有 `9090` 监听、Clash API 或 Web Dashboard。
- Network Extension 的监听可能不出现在普通用户的 `lsof` 中，可用 `netstat`
  和 `nc -G 1 -z 127.0.0.1 7777` 确认。
- SFM 显示已连接，IPv4/IPv6 默认路由与 DNS 由 TUN 接管。比较连接前后的
  路由与接口，不能只凭存在 `utun` 判断。

通过 SFM 日志、连接记录与出口 IP 检查分流：

- `localhost`、`.local`、局域网及未匹配目标直连。
- GFWList、GitHub、OpenAI、Claude 和 Google Meet（TCP/UDP）走 `proxy`。
- DNS 请求由 TUN 劫持，结果符合规则；并非所有域名都返回 FakeIP。

`direct.domain_resolver` 使用 AliDNS，避免国内直连目标继承代理 DNS。
远程规则集通过 `sg-vless` 下载，避免首次启动依赖尚未完成探测的 `auto`。
GitHub 的主站、Raw 和静态资源域名使用内联规则，避免依赖远程规则集缓存。

`proxy` 可选择 `auto`、`singapore`、`usa`、`sg-vless`、`sg-hy2`、`us-vless`
和 `us-hy2`。手动切换会中断既有连接，URLTest 自动探测不会。
节点失败时先切回 `auto`，再检查错误与延迟。不要公开完整日志、出口 IP 或凭据。

历史验收（2026-07-28）：`us-vless` 未通过，其余节点与组通过；断开恢复及
重复启停未测试。升级后应重新验收，不能沿用历史结果。

## 停止与恢复

在 SFM 界面断开后，确认 `7777`、`9090` 没有监听，DNS 与 IPv4/IPv6 默认路由
恢复到连接前状态，没有残留 CLI 核心。SFM 前端仍打开不代表核心仍运行。
首次部署或升级后，重复两轮“导入 -> 连接 -> 切换节点 -> 断开”检查。

故障时先在 SFM 界面断开，排除其他代理冲突，再运行配置检查。
校验失败则修复仓库输入并重新 rebuild；发布脚本会保留上一个有效配置。
校验通过但运行异常则退出并重开 SFM，重新导入；权限缺失时按官方提示授权。

## age identity 恢复

标准位置为 `~/Library/Application Support/sops/age/keys.txt`，目录权限 `0700`，
文件权限 `0600`。Bitwarden 备份项目为 `dotfiles - sops age identity`，可选
item ID 环境变量为 `BITWARDEN_SOPS_AGE_IDENTITY_ITEM_ID`。

新 Mac 上通过 Bitwarden 官方客户端恢复完整文件到标准位置，然后运行：

```bash
bash scripts/check-sops-age-key.sh
```

检查验证权限、recipient 匹配与 SOPS 解密，不输出秘密。恢复失败时不要生成新
identity。私钥不得放入仓库、Nix Store、命令参数、环境变量或公开材料。
保持 FileVault 开启。
