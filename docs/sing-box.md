# sing-box 与 SFM

SFM 负责运行代理、Network Extension 和 TUN；仓库负责生成、校验和发布配置。
不额外启动 `sing-box run`、LaunchAgent 或 LaunchDaemon，以免与 SFM 冲突。
新机安装前准备网络和密钥的步骤见 [Quick start](../README.md#quick-start)。

## 配置来源与版本

| 文件 | 用途 |
| --- | --- |
| `home/.config/sing-box/config.json` | 无凭据的配置模板，持久修改在这里完成 |
| `home/.config/sing-box/secrets-map.json` | 模板占位符与秘密字段的映射 |
| `secrets/sing-box.yaml` | SOPS 加密的秘密 |
| `~/.local/state/sing-box/config.json` | 解密并校验后发布的完整配置，权限 `0600` |
| `~/.config/sing-box/config.json` | 指向已发布配置的链接，供检查和导入使用 |

当前模板使用 sing-box 1.14 的 DNS 响应匹配、HTTP client 和缓存功能。
CLI 的固定版本见 `macos-binaries.json`；SFM 使用 Homebrew `sfm` cask，
两者的版本来源不同。CLI 校验通过不代表 SFM 内置核心一定兼容，升级时需分别确认版本，
并阅读 [官方迁移说明](https://sing-box.sagernet.org/migration/)。
跨越 SFM 1.14 的应用身份变更时，旧配置与设置不会自动继承，按
[官方数据迁移说明](https://sing-box.sagernet.org/migration/#migrate-the-macos-standalone-client-data)
处理。不要把以前版本的兼容性测试结论当作当前验收结果。

## 发布与导入

在仓库根目录执行：

```bash
./rebuild.sh
open -a SFM
```

rebuild 先用即将安装的 CLI 校验配置；系统激活时，sops-nix 解密并渲染候选文件，
发布脚本再次校验，成功后原子替换已发布配置。发布失败保留上一个有效文件，
但不代表整个系统或 Homebrew 变更都会回退。

SFM 的 Local Profile 是导入副本，不会自动读取仓库后续修改：

1. 在 SFM 中断开 VPN。
2. 选择“文件 → 从文件导入”，按 `Command-Shift-G` 输入 `~/.config/sing-box/config.json`。
3. 替换旧副本，保留一个容易辨认的配置，例如 `config`。
4. 连接；首次使用时按 macOS 提示批准网络扩展和 VPN 权限。

每次修改模板、规则或秘密并成功 rebuild 后，都要重新导入。
不要直接修改 SFM 的私有容器；应用内临时修改也不会同步回仓库。
Homebrew 安装或升级 SFM 可能中断代理连接，操作前保留可离线使用的安装包和配置。

## 当前分流

以下行为来自仓库模板，运行时以导入 SFM 的那份配置为准：

| 流量 | 去向 |
| --- | --- |
| 私网 IP、代理服务器自身、未匹配其他规则的流量 | 直连 |
| GitHub、Nix 缓存等 `custom-proxy` 目标，以及 GFWList、OpenAI、Google Meet | `🚀 proxy` 选择的出口 |
| Antigravity、Claude | `🇸🇬 singapore`，对应 DNS 也走新加坡 |
| 远程规则集下载 | 经 `rule-set-download` HTTP client 固定走 `🇺🇸 us-hy2` |

`🚀 proxy` 默认选择 `⚡ auto`，也可手动指定地区或节点。
三个自动组每 3 分钟探测，容差 50 ms；HY2 在候选中优先排列，探测后按延迟选择。
自动选择变化保留既有连接，手动切换全局 selector 会中断既有连接。
延迟测试不等于吞吐量测试，不能据此保证下载速度。

DNS 使用 IPv4 策略并拒绝 AAAA 查询；代理目标按规则使用代理 DNS，
其他请求先查询直连 DNS，部分 A 查询使用 FakeIP，并非所有域名都返回 FakeIP。
启用 DNS 持久缓存和最多 5 分钟的过期缓存后台刷新。
字段含义见 [DNS 配置](https://sing-box.sagernet.org/configuration/dns/) 和
[URLTest](https://sing-box.sagernet.org/configuration/outbound/urltest/)。

## 检查与恢复

检查仓库配置，或检查已经发布的文件：

```bash
bash scripts/check-sing-box-config.sh
bash scripts/check-sing-box-config.sh "$HOME/.config/sing-box/config.json"
```

前者会解密秘密并在管道中渲染，检查过程不主动打印完整配置。
核心版本不兼容时，先确认 `sing-box version`，不要直接删掉校验不认识的字段。

连接 SFM 后检查本机代理端口，并通过 HTTP 代理发起请求：

```bash
nc -G 1 -z 127.0.0.1 7777
curl --proxy http://127.0.0.1:7777 --connect-timeout 15 --max-time 30   -I https://github.com
```

模板只在 `127.0.0.1:7777` 提供 mixed 入站，没有开放局域网代理或 Clash API。
端口和 HTTP 请求正常只证明 mixed 代理可用；TUN 还要在 SFM 中确认连接状态，
并检查普通浏览器访问、DNS、IPv4/IPv6 默认路由是否符合预期。
断开后确认 `7777` 不再提供代理，网络与 DNS 恢复；升级后重复连接和断开测试。

- **校验失败**：修复仓库模板或秘密，重新 rebuild。秘密用 `sops secrets/sing-box.yaml` 编辑。
- **连接失败**：查看 SFM 错误，排除其他代理冲突，重新导入或重开应用，并检查系统授权。
- **单个节点失败**：测试同地区其他节点，并检查规则集下载依赖的美国 HY2 是否可用。
  全局 selector 的切换不会改变 Claude、Antigravity 和规则集下载各自固定的出口。
- **密钥检查失败**：运行 `bash scripts/check-sops-age-key.sh`，按提示恢复原有密钥或修正权限。
  脚本检查文件权限、仓库 recipient 匹配和解密能力，不会自动登录 Bitwarden 取回密钥。

完整配置、密钥和运行日志可能包含凭据，不要提交到 Git 或公开粘贴。
[2026-10-16 性能审计](sing-box-performance.md) 保留为历史记录，不能证明当前节点或服务端状态；
本仓库不部署、升级或回退服务端程序。
