# sing-box 与 SFM 操作手册

本机只允许 SFM 拥有 sing-box 运行时、Network Extension 和 TUN。nix-darwin
负责解密、渲染、校验和发布配置，Home Manager 只负责命令行工具与最终配置
链接。不要创建 sing-box LaunchAgent、LaunchDaemon 或 CLI 常驻进程，也不要用
`sing-box run` 启动服务。

## 配置来源与边界

- 仓库中的 `home/.config/sing-box/config.json` 是配置结构和规则的唯一真相来源。
- `secrets/sing-box.yaml` 只保存 SOPS 密文，不应复制到 SFM 或文档中。
- `~/.config/sing-box/config.json` 最终解析到
  `~/.local/state/sing-box/config.json`，后者是通过校验的运行配置。
- SFM 的 `sing-box` Local Profile 是导入后的派生副本。不要在 SFM 编辑器中长期
  修改它，也不要直接读写 SFM 的私有应用容器。
- SFM 不持续监视源文件。仓库配置变化后，即使 `./rebuild.sh` 成功，也必须在
  SFM 中重新导入。`rebuild.sh` 不会启动、停止或重启 SFM。
- 当前配置只提供本机 `127.0.0.1:7777` mixed 入站。没有 Web Dashboard、
  Clash API 或 `9090` 监听端口。SFM 自带的“仪表”页面不是网络 Dashboard
  服务，不应为它启用 Clash API。

## 首次部署与导入

在仓库根目录运行：

```bash
./rebuild.sh
bash scripts/check-sing-box-config.sh
```

两条命令都成功后，先确认没有已经运行的其他核心，也没有端口冲突：

```bash
pgrep -alf 'sing-box|SFM'
launchctl list | rg -i 'sing-box|sfm'
lsof -nP -iTCP:7777 -sTCP:LISTEN
lsof -nP -iTCP:9090 -sTCP:LISTEN
netstat -anv -p tcp | rg '[.:](7777|9090).*LISTEN'
```

检查 `pgrep` 结果时忽略命令行中恰好包含搜索词的短暂检查进程。导入前应没有
独立的 sing-box 核心、没有 `7777` 或 `9090` 监听。若另一个代理客户端正在
接管系统 VPN 或 TUN，先在其官方界面中断开并退出。

只通过 macOS 正常方式打开 SFM：

```bash
open -a SFM
```

首次使用时，在 macOS 系统界面批准 SFM 的 Network Extension 和 VPN 配置。
审批必须由用户完成，不得用脚本绕过。

在 SFM 1.13.14 的官方界面中导入：

1. 保持 VPN 处于“已断开”状态。
2. 选择菜单“文件” -> “从文件导入”。
3. 在文件选择器中按 `Command-Shift-G`，输入
   `/Users/rich/.config/sing-box/config.json`，再选择“打开”。
4. 确认导入后显示名称为 `sing-box`，类型为 Local Profile，并选中它作为当前配置。
5. 在“配置”页面确认只有一个 `sing-box` 本地配置。不要保留同一来源的重复
   Profile，也不要创建 Remote Profile。

导入只复制已经通过校验的配置，不会把仓库模板或 SOPS 密文交给 SFM。

## 配置变更后重新导入

每次修改模板、规则或加密秘密后：

1. 在仓库根目录运行 `./rebuild.sh`。
2. 运行 `bash scripts/check-sing-box-config.sh`，确认新配置通过当前锁定版本的
   sing-box 语义校验。
3. 在 SFM 中先“断开连接”。`rebuild.sh` 本身不会改变现有连接。
4. 在“配置”页面删除或替换旧的 `sing-box`，再使用“文件” ->
   “从文件导入”导入 `/Users/rich/.config/sing-box/config.json`。
5. 确认最终仍只有一个名为 `sing-box` 的 Local Profile，再重新连接并完成下文
   的运行验收。

不要把 SFM 内的临时编辑导出后覆盖仓库文件。需要持久化的修改必须回到仓库
模板或 SOPS 密文，经 rebuild、校验和重新导入后生效。

## 连接后的单实例验收

在 SFM 中选中 `sing-box` 后点击“启动”或“连接”。等待状态稳定为已连接，再
执行：

```bash
pgrep -alf 'sing-box|SFM'
launchctl list | rg -i 'sing-box|sfm'
ifconfig | rg -n '^utun'
lsof -nP -iTCP:7777 -sTCP:LISTEN
lsof -nP -iTCP:9090 -sTCP:LISTEN
```

验收结果应同时满足：

- 只有 SFM 前端及其 Network Extension 管理的一个核心，没有独立
  `sing-box run` 进程。
- `127.0.0.1:7777` 恰好有一个监听者。macOS Network Extension 的监听者可能
  不出现在普通用户执行的 `lsof` 中，此时必须用 `netstat` 和
  `nc -G 1 -z 127.0.0.1 7777` 交叉确认，不能把单独的空 `lsof` 结果误判为
  未启动。
- `9090` 没有监听者。
- SFM 显示 VPN 已连接，IPv4 与 IPv6 默认流量由 SFM 的 TUN 路由接管。

macOS 在 SFM 启动前可能已经存在多个 `utun` 接口。不能仅凭“看到 utun”
判定成功。连接前后都记录接口和默认路由，用新增或发生变化的接口、路由、
SFM VPN 状态和 `7777` 监听共同识别 SFM 接管的 TUN。

若发现第二个核心、第二个 `7777` 监听者或其他代理客户端仍连接，立即在 SFM
中断开，不要直接 `kill` Network Extension。先从各应用的官方界面停止冲突
服务，再重新进行导入前检查。

## DNS、TUN 与分流验收

使用 SFM 的“日志”“连接”和出口 IP 检查逐项验证，但不要复制包含服务器地址、
认证字段或其他凭据的完整日志：

- IPv4 和 IPv6 默认流量都进入 SFM TUN。
- DNS 结果必须符合分流规则，不能假定所有域名都返回 FakeIP。当前实测
  `example.com` 返回真实地址，而 `example.net`、`neverssl.com` 和 `invalid`
  返回配置声明范围内的 FakeIP。
- `localhost`、`.local` 与局域网目标保持直连并仍可访问。
- 选定的 GFWList 测试域名走 `proxy`。
- 选定的未匹配测试域名走 `direct`。
- OpenAI 与 Claude 走 `proxy`。
- Google Meet 的 TCP 与 UDP 流量都走 `proxy`。
- DNS 请求被 `tun-in` 劫持到 sing-box，没有绕过 TUN 的系统 UDP DNS 泄漏。

国内直连域名由 `direct` 出站显式使用 `direct-dns`（AliDNS）完成实际拨号
解析；GFWList、OpenAI、Claude 和 Google Meet 等代理目标使用经 `proxy`
连接的 Cloudflare DoH。不要删除 `direct.domain_resolver`，否则 FakeIP 还原
后的国内域名会继承全局代理 DNS，可能获得不适合国内直连的候选地址并表现为
TLS 建连缓慢。

选择测试域名时避免账号、工作资源和私有服务。出口 IP 只用于核对线路，不要
把完整结果写入仓库、工单或公开日志。

## 节点选择

配置的主 selector 名为 `proxy`。在 SFM 的出站或组选择界面依次选择并验证：

```text
auto
singapore
usa
sg-vless
sg-hy2
us-vless
us-hy2
```

每次选择后，用 SFM 日志中的非敏感 tag 和外部出口 IP 共同确认切换生效。
`auto`、`singapore` 和 `usa` 是 URLTest 组，自动探测不会中断既有连接。手动
切换 `proxy` selector 会按模板设置中断既有连接，新连接应立即走所选节点。

如果某个物理节点失败，先切回 `auto` 保持可用性，再查看 SFM 的非敏感错误
类型和延迟结果。不要把 UUID、密码、REALITY 参数、服务器名称或服务器地址
粘贴到终端、文档或 issue。

### 已知问题

- 2026-07-28 本机端到端验收中，`us-vless` 不可用，切换后没有建立经该物理
  节点传输的流量。当前不推测根因，留作后续排查。
- 同轮验收中，`auto`、`singapore`、`usa`、`sg-vless`、`sg-hy2` 和
  `us-hy2` 均已通过。
- 本轮验收结束时已切回 `auto` 并保持 Connected。断开后的 DNS、路由和监听
  恢复检查，以及第二轮重复启停和重新导入均未执行，因为 Codex 协作连接依赖
  当前 SFM 网络，断开可能中断任务。这两项状态为 deferred/not tested，不能
  视为通过。

## 停止、重复启动与恢复

正常停止必须在 SFM 中点击“停止”或“断开连接”。停止后确认：

```bash
lsof -nP -iTCP:7777 -sTCP:LISTEN
lsof -nP -iTCP:9090 -sTCP:LISTEN
netstat -anv -p tcp | rg '[.:](7777|9090).*LISTEN'
pgrep -alf 'sing-box|SFM'
```

预期 `7777` 和 `9090` 都没有监听，系统 DNS 与 IPv4/IPv6 默认路由恢复到连接
前状态，且没有残留的 CLI sing-box 核心。SFM 前端仍打开并不代表核心仍在
运行。

首次验收或 SFM 升级后，完整重复两轮“导入 -> 连接 -> 节点切换 -> 断开”。
每轮都检查只有一个 Local Profile、一个运行核心和一个 TUN 所有者。已有的
系统 `utun` 数量不能替代前后差异和路由检查。

故障恢复顺序：

1. 在 SFM 官方界面断开，等待 VPN 状态变为已断开。
2. 确认 `7777` 消失、路由和 DNS 恢复，并停止其他代理客户端。
3. 重新运行 `bash scripts/check-sing-box-config.sh`。
4. 校验失败时保留上一个已发布配置，修复仓库输入后再次 `./rebuild.sh`。
5. 校验通过但 SFM 状态异常时，退出并重新打开 SFM，再重新导入唯一的
   `sing-box` Local Profile。不要编辑应用容器或用 CLI 启停核心。
6. 若 Network Extension 权限被撤销，按 SFM 和 macOS 的官方提示重新授权，
   然后从断开状态重新验收。

## age identity 与 Bitwarden 恢复

共享 age identity 的唯一标准位置是：

```text
~/Library/Application Support/sops/age/keys.txt
```

目录权限必须是 `0700`，文件权限必须是 `0600`。Bitwarden 中的备份项目名称
固定为 `dotfiles - sops age identity`；可选 item ID 环境变量名称固定为
`BITWARDEN_SOPS_AGE_IDENTITY_ITEM_ID`。

新 Mac 上应通过 Bitwarden 官方应用、Web Vault 或已安装的官方 CLI，把完整
`keys.txt` 直接恢复到标准位置，然后运行：

```bash
bash scripts/check-sops-age-key.sh
```

该检查验证权限、仓库 recipient 匹配和 SOPS 解密能力，不输出私钥或解密后的
秘密。恢复失败时不要生成新 identity，也不要把私钥放入仓库、Nix Store、
命令参数、环境变量、聊天、截图、普通云盘或长期保留的 Downloads 文件。
FileVault 必须保持开启。
