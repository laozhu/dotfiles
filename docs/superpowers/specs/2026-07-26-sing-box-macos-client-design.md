# sing-box macOS 客户端配置设计

日期：2026-07-26

## 目标

为 Apple Silicon macOS 构建一套声明式 sing-box 客户端配置，满足以下要求：

- 使用 SFM 作为唯一的 sing-box 运行时；
- 通过 Network Extension 启用 IPv4/IPv6 双栈 TUN；
- GFWList 命中的流量通过代理，未命中的流量保持直连；
- 使用 FakeIP 和 DNS 劫持防止 DNS 污染；
- 支持两个服务器、两种协议组成的四个出站；
- 允许 SFM 自动选择或手动切换节点；
- 支持用户自定义拒绝、直连和代理规则；
- 使用 sops-nix 和 age 加密 Git 仓库中的服务器凭据；
- 所有 Mac 共用一套 nix-darwin 配置；
- 确保任何时候都不会启动多个 sing-box 实例。

## 约束

- 当前安装的稳定版核心是 sing-box 1.13.14。
- 只有 SFM 可以启动或停止 sing-box。
- Home Manager 不得创建 sing-box LaunchAgent 或 LaunchDaemon。
- sing-box CLI 仅用于校验配置。
- 不需要 Web Dashboard 或 Clash API。
- 仓库中已有与本任务无关的暂存和未暂存修改，实施时必须保留。
- 旧明文配置只作为迁移输入，不得整份照搬。
- 旧配置包含敏感值，不得在日志、测试输出或文档中显示。

## 仓库布局

仓库中将包含：

```text
.sops.yaml
secrets/
└── sing-box.yaml
home/.config/sing-box/
└── config.json
```

各文件职责如下：

- `.sops.yaml` 保存共享 age 公钥接收者及 SOPS 加密规则。
- `secrets/sing-box.yaml` 只保存由 SOPS 加密的秘密值。
- `home/.config/sing-box/config.json` 保存完整的非秘密配置结构、官方 JSON Schema 引用和具名秘密占位符。
- `~/.config/sing-box/config.json` 是经过校验并渲染完成的运行配置，权限为 `0600`。

仓库中的 `config.json` 是配置结构和规则的唯一真相来源。SOPS 文件只提供加密数据。SFM Local Profile 是派生的运行副本，不得成为独立的编辑来源。

## Nix 架构

### 单一 Darwin 配置

`flake.nix` 只暴露一个配置：

```text
darwinConfigurations.mac
```

删除重复的 `mac-laptop` 和 `mac-desktop` 输出。两台实体 Mac 使用同一套配置和同一份共享 age 私钥。

### 软件包和应用

Home Manager 从 nixpkgs 安装以下命令行软件包：

- `age`
- `sops`
- `sing-box`

nix-darwin 的 Homebrew cask 列表加入：

- `sfm`

必须声明 SFM，因为 Homebrew 激活配置使用了 `cleanup = "zap"`。

### 运行时所有权

SFM 负责：

- 唯一运行的 sing-box 实例；
- macOS Network Extension；
- TUN 生命周期；
- 日志和运行状态；
- 出站 selector 状态；
- 节点延迟测试和手动切换。

Home Manager 负责：

- 软件包；
- 加密秘密的供应；
- 配置渲染；
- 文件权限；
- 配置的静态和语义校验。

Home Manager 不得运行 `sing-box run`，不得创建自动启动服务，也不得重启 SFM。

## 秘密管理

### 加密模型

sops-nix 使用 age 作为加密后端。两台 Mac 共用同一个 age identity。

age 私钥存放在本机：

```text
~/Library/Application Support/sops/age/keys.txt
```

权限要求：

- 所在目录：`0700`
- 私钥文件：`0600`

私钥绝不能提交到 Git。新 Mac 必须通过密码管理器、加密移动存储或其他安全的带外渠道恢复私钥。

以下文件可以且应当提交：

- `.sops.yaml`，其中只包含 age 公钥接收者；
- `secrets/sing-box.yaml`，其中的值均已加密；
- 非秘密配置模板。

### 加密字段

迁移过程从 `/Users/rich/Downloads/config.json` 提取敏感值，但不得显示这些值。需要加密的字段包括：

- 美国和新加坡服务器地址，作为私有部署元数据处理；
- VLESS UUID；
- VLESS REALITY server name、public key 和 short ID；
- Hysteria2 密码；
- Hysteria2 Salamander 混淆密码；
- Hysteria2 TLS server name。

端口和带宽设置默认保留在模板中，除非进一步检查表明它们也应作为秘密处理。

### 渲染过程

仓库配置使用唯一且明确的字符串占位符。Home Manager 激活时，sops-nix 执行：

1. 读取 SOPS 密文；
2. 使用本地 age identity 解密；
3. 将 sops-nix placeholder 替换进配置；
4. 在 Nix Store 之外写入运行文件；
5. 设置权限为 `0600`；
6. 校验 JSON 语法和 sing-box 语义；
7. 仅在全部校验通过后，原子更新 `~/.config/sing-box/config.json`。

所有秘密均采用可以安全替换进 JSON 字符串的格式。渲染后必须重新解析生成文件，任何转义错误都应在替换现有运行配置之前使激活失败。

## 新 Mac 初始化

全新 Mac 的初始化流程：

```text
1. 克隆仓库。
2. 将共享 age 私钥恢复到 macOS 的标准 SOPS 路径。
3. 运行 ./bootstrap.sh。
4. 由 sops-nix 解密并渲染 sing-box 配置。
5. 将通过校验的运行配置导入 SFM。
```

`bootstrap.sh` 和 `rebuild.sh` 均使用 `darwinConfigurations.mac`。

脚本接口统一为：

```text
./bootstrap.sh
./rebuild.sh
./rebuild.sh --update
```

age 私钥缺失时，脚本必须提前失败并显示准确的恢复路径。不得自动生成替代密钥，因为新 identity 无法解密仓库中已有的 SOPS 文件。

## SFM Profile 同步

SFM 支持本地配置 Profile，但会将 Profile 内容保存为应用状态，并不会持续监视 `~/.config/sing-box/config.json`。

同步策略如下：

- 所有编辑都在仓库模板和加密 SOPS 文件中完成；
- SFM Profile 内容由渲染后的配置派生；
- 只有全部校验成功后才允许同步；
- `rebuild.sh` 不自动启动 SFM；
- 禁止直接在 SFM 编辑器中进行长期配置修改。

实施时必须对 SFM 官方文件导入流程进行端到端验证。如果 SFM 提供稳定的文件导入方式，则提供由用户主动执行的 `sfm-sync` 辅助命令。如果没有可靠的自动化接口，则文档明确要求在 SFM 中重新导入已经校验的文件。实施不得直接写入 SFM 的私有应用容器。

## 网络配置

### 入站

配置包含两个入站。

#### `tun-in`

- 类型：TUN
- 同时提供 IPv4 和 IPv6 地址
- 使用 system stack
- 生命周期由 SFM Network Extension 控制
- 不存在独立的 CLI TUN 实例

根据官方 SFM 功能矩阵完成测试后，尽量减少由 Apple Network Extension 管理或忽略的选项。

#### `mixed-in`

- 类型：mixed SOCKS/HTTP
- 监听地址：`127.0.0.1`
- 监听端口：`7777`
- 用途：终端诊断和单个应用显式代理

该入站绝不能监听局域网或公网地址。

### 实际出站

两个服务器提供四个实际出站：

- `sg-vless`：VLESS、REALITY、Vision、uTLS Chrome 指纹
- `sg-hy2`：Hysteria2、TLS、Salamander 混淆
- `us-vless`：VLESS、REALITY、Vision、uTLS Chrome 指纹
- `us-hy2`：Hysteria2、TLS、Salamander 混淆

旧配置中的带宽提示值：

- 新加坡 Hysteria2：上行 45 Mbps，下行 170 Mbps
- 美国 Hysteria2：上行 32 Mbps，下行 95 Mbps

除非当前 sing-box 指南或实际测试表明省略这些值更安全，否则实施时保留。

### Selector 层次

主 selector：

```text
proxy
├── auto
├── singapore
├── usa
├── sg-vless
├── sg-hy2
├── us-vless
└── us-hy2
```

行为：

- `proxy` 默认选择 `auto`；
- `auto` 对四个实际出站执行 URLTest；
- `singapore` 对两个新加坡协议执行 URLTest；
- `usa` 对两个美国协议执行 URLTest；
- 自动切换不打断已有连接；
- 用户手动切换时可以打断已有连接，使新选择立即生效；
- URLTest 初始周期为十分钟，减少电量和后台流量消耗；
- 没有测量证据时不增加单独的 TCP 或 UDP selector。

## DNS 设计

DNS 使用 FakeIP，防止受污染的解析结果控制代理目标。

### 行为

- TUN 劫持普通 DNS 流量。
- A 和 AAAA 查询通常返回 FakeIP。
- 同时启用 IPv4 和 IPv6 FakeIP 地址池。
- 解析和连接策略优先 IPv4，但允许 IPv6。
- FakeIP 映射写入 sing-box 缓存。
- 使用 inline hosts DNS 将代理服务器域名映射到固定 IP，避免启动递归和 DNS 污染。
- 本地、`.local`、反向解析、私有和链路本地域名使用本地解析。
- 直连目标使用中国大陆可用的加密 DNS。
- 代理目标保留域名并通过代理连接，不依赖可能受污染的本地解析结果。

最终配置使用 sing-box 1.13.14 支持的结构化 DNS server 格式，并尽量选择稳定版与最新官方 Schema 都接受的字段。

## 路由设计

### 规则集来源

GFWList 使用：

```text
https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs
```

它是远程二进制 sing-box rule-set，更新周期为 24 小时。通过一个已知可用的 bootstrap 代理出站下载。刷新失败时继续使用缓存规则。

### 优先级

路由规则按以下顺序求值：

1. 协议 sniff；
2. DNS 劫持；
3. 代理服务器端点、私有 IP 和局域网流量走 `direct`；
4. `custom-reject`；
5. `custom-direct`；
6. `custom-proxy`；
7. OpenAI 走 `proxy`；
8. Claude 走 `proxy`；
9. Google Meet 域名、官方媒体 IP 和必要 UDP 端口走 `proxy`；
10. MetaCubeX GFWList 走 `proxy`；
11. 未匹配流量走 `direct`。

### 自定义规则

主配置中包含三个 inline rule-set：

- `custom-reject`
- `custom-direct`
- `custom-proxy`

它们可以包含域名、域名后缀、关键字、CIDR、端口和进程规则。这样可以保留明确的用户覆盖规则，而不引入第二份配置来源。

### 保留的服务规则

只有以下服务策略具有充分证据：

- OpenAI 必须走 `proxy`。中国大陆不在支持访问地区中，新加坡和美国均受支持。
- Claude 必须走 `proxy`。Anthropic 使用 IP 推断位置并执行支持地区策略，两个代理地区均受支持。
- Google Meet 域名、官方媒体 IP 段和必要 UDP 端口必须走 `proxy`，以保证媒体连接。不固定到 Hysteria2，因为没有证据表明某一种代理协议普遍更优。

删除旧配置中的以下策略：

- Apple 直连，因为最终路由本来就是直连；
- OpenAI、Claude、Paid、Monoova 和 WorkOS 固定新加坡；
- WhatsApp、YouTube 和 Meet 仅使用 Hysteria2；
- 宽泛的 AWS 和 Cloudflare 代理规则；
- GitHub、Homebrew、Figma、Slack、Stripe、Atlassian、Logitech 和 Google Analytics 的显式代理规则。

这些服务由 GFWList 和默认直连行为处理。只有可复现的故障才能成为未来增加自定义规则的依据。

## Dashboard 和 API

不配置 Web Dashboard。

不配置 Clash API listener。

SFM 提供：

- 启动和停止控制；
- 日志；
- selector 分组；
- URLTest；
- 手动节点切换；
- 运行状态。

这样可以避免暴露不必要的本地 API，也无需使用 sing-box 1.14 alpha 的 API service。

## 单实例安全

单实例行为是硬性要求。

实施必须确保：

- SFM 是唯一运行时所有者；
- 脚本不启动 `sing-box run`；
- 不存在 sing-box LaunchAgent 或 LaunchDaemon；
- 只有一个活动的 sing-box Network Extension；
- 只有一个 TUN 所有者；
- 重复点击 SFM 启动不会创建第二个核心；
- 停止 SFM 后系统 DNS 和路由恢复；
- 配置 rebuild 不启动或重启 SFM。

预检和验收将检查进程、launchd 服务、监听端口、Network Extension 状态、TUN 接口和默认路由，同时不得打印秘密。

## 失败处理

配置生成是事务性的：

1. 验证 age identity；
2. 解密 SOPS 数据；
3. 渲染临时配置；
4. 解析 JSON；
5. 运行 `sing-box check`；
6. 只有全部成功后才原子发布。

发生失败时：

- 激活返回非零状态；
- 保留上一份有效运行配置；
- 不启动、停止或修改 SFM；
- 不保留残缺明文文件；
- 不打印秘密值。

远程规则集刷新失败时使用缓存。第一次启动需要至少一个实际代理出站可用，以完成首次 GFWList 下载。

## 验证计划

### 静态验证

- 运行 `nix flake check`；
- 构建 `darwinConfigurations.mac.system`；
- 对修改过的 Shell 脚本运行 `shellcheck`；
- 使用官方 sing-box JSON Schema 校验模板结构；
- 使用 `jq` 解析渲染后的配置；
- 使用 `sing-box check` 校验渲染后的配置；
- 扫描待提交和已提交文件，确认不存在 age 私钥或已知明文秘密。

如果最新在线 Schema 包含尚未正式发布的字段，则以本机稳定版 `sing-box check` 为最终依据。

### 端到端验证

1. 按用户真实流程将生成配置导入 SFM。
2. 启动 SFM，确认恰好只有一个 Network Extension 实例。
3. 确认不存在 CLI sing-box 进程或 launchd 服务。
4. 确认 TUN 接管 IPv4 和 IPv6。
5. 确认普通 A 和 AAAA 查询返回预期 FakeIP 地址池中的地址。
6. 确认局域网和 `.local` 访问正常。
7. 确认 GFWList 域名使用选定代理。
8. 确认未匹配域名保持直连。
9. 确认 OpenAI 和 Claude 使用 `proxy`。
10. 确认 Google Meet TCP 和 UDP 连通。
11. 分别测试四个实际出站。
12. 确认 `auto`、`singapore` 和 `usa` 的 URLTest 正常。
13. 通过 SFM 切换国家和协议，确认实际出口发生变化。
14. 停止 SFM，确认 DNS、路由和 TUN 状态恢复。
15. 重复启动、停止、导入和切换操作，确认不产生重复实例。

## 迁移与清理

旧文件 `/Users/rich/Downloads/config.json` 权限为 `0644`，包含完整明文凭据。

实施过程：

1. 在本地提取所需值，不显示它们；
2. 创建加密 SOPS 数据；
3. 使用共享 age identity 验证 SOPS 可以解密；
4. 校验并运行新配置；
5. 删除旧明文文件前单独请求用户明确许可。

旧 Clash API secret 视为已经暴露，不再复用。新设计没有 Clash API，因此不需要生成新的 API secret。

## 不在范围内

- 运行独立的 sing-box CLI 服务；
- Web Dashboard；
- Clash API；
- 第三方 GUI 或 TUI 客户端；
- 自动转换订阅；
- 没有实际需求的按应用路由；
- 自动删除旧明文配置；
- 分离 laptop 和 desktop 的 Darwin 配置。

## 验收标准

满足以下条件时设计目标完成：

- 两台 Mac 均构建同一个 `darwinConfigurations.mac`；
- 加密秘密可以安全提交，并能使用共享 age 私钥解密；
- 最终配置具备 Schema 辅助、是有效 JSON，并通过 sing-box 1.13.14 校验；
- SFM 通过声明式方式安装，并使用唯一的 Network Extension 实例运行配置；
- FakeIP、双栈、GFWList、自定义规则和服务例外均按设计工作；
- 四个节点均可选择，`auto` 可以自动选择；
- 未匹配流量保持直连；
- 停止 SFM 后系统网络状态恢复；
- 不存在重复 sing-box 运行时或持久化 CLI 服务。
