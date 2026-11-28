# Shadowrocket

iPhone 上的 Shadowrocket 使用与 [sing-box](sing-box.md) 相同的节点和分流规则，全部扫码导入。
需要 Shadowrocket 2.2.53 或更高版本：VLESS REALITY 从 2.2.30、Hysteria2 从 2.2.35 开始支持，
2.2.53 修复了 REALITY Short ID 解析。旧版本会拒绝 `hysteria2://` 链接，或忽略 REALITY 参数而无法连接。

| 文件                                          | 内容                                             |
| --------------------------------------------- | ------------------------------------------------ |
| `home/.config/shadowrocket/shadowrocket.conf` | 分组、分流规则和 DNS；不含秘密，经局域网扫码导入 |
| `home/.config/shadowrocket/nodes.txt`         | 四个节点的分享链接模板（VLESS REALITY、HY2）     |
| `~/.local/state/shadowrocket/nodes.txt`       | 解密、校验后发布的分享链接，权限 `0600`          |

分享链接模板使用 sing-box 的 `secrets-map.json` 和 `secrets/sing-box.yaml`，不另存秘密。
节点不写进 `.conf`：Shadowrocket 没有公开 REALITY 和 salamander 的 `[Proxy]` 写法，
而 `vless://`、`hysteria2://` 分享链接是标准格式。url-test 分组按节点名
（`sg-hy2`、`us-vless` 等）匹配，导入后不要改名。
Shadowrocket 连接代理服务器本身不经过分流规则，节点主机名通过公网 DNS 解析，
因此 `.conf` 不需要服务器地址，也不使用 sing-box 那样的 hosts 映射。

## 生成与检查

rebuild 在切换系统前运行 `scripts/check-shadowrocket-config.sh`：解密、渲染分享链接，
并与 `.conf` 一起检查。系统激活时 sops-nix 渲染候选文件，
`scripts/publish-shadowrocket-config.sh` 检查通过后原子替换，失败时保留上一份。
检查已发布的链接：

```bash
bash scripts/check-shadowrocket-config.sh ~/.local/state/shadowrocket/nodes.txt
```

Shadowrocket 没有命令行校验工具，Mac 上也没有兼容其格式且带 CLI 的客户端。
`scripts/shadowrocket-config.mjs` 只检查本仓库依赖的结构和安全约束：`.conf` 不含任何秘密值、
分组与策略引用、规则类型、FINAL 位置、加密 DNS、IPv6 关闭、证书校验未关闭，
节点使用 REALITY vision 和 salamander，且秘密无需 URL 编码。
`tests/shadowrocket-config.sh` 还要求 sing-box 模板中的每条分流规则和节点参数
在 Shadowrocket 模板中都有对应项。能否连接仍需在 App 中验证。

## 扫码导入

两个通用脚本负责导入，不限于 Shadowrocket：

- `scripts/qr.sh [--lines] FILE|-`：用 qrtool 把文件或标准输入显示为终端二维码；
  `--lines` 让每个非空行单独成码，按回车翻页。只向终端输出，标题只显示链接 `#` 后的名称，
  退出时清屏。
- `scripts/serve-once.sh [--qr-prefix PREFIX] [--address IPV4] FILE`：用 miniserve 在局域网
  临时分享一个文件的副本，并把网址显示为二维码，按回车或 Ctrl-C 后停止。它只绑定第一个物理网卡
  （`en*`）上的私网 IPv4，不使用 SFM 的 TUN 地址；网址包含 128 位随机路径，根路径和目录列表
  返回 404。停止后列出请求过该文件的地址、状态码和客户端，用于判断设备是否连到了 Mac。
  下载走明文 HTTP，只用于不含凭据的文件，并只在可信的局域网使用。

导入步骤：

1. 在 Mac 上执行 rebuild，确认 `~/.local/state/shadowrocket/nodes.txt` 已更新。
2. 节点：执行下面的命令，在 Shadowrocket 首页左上角的扫码入口逐个扫描四个码：

   ```bash
   bash scripts/qr.sh --lines ~/.local/state/shadowrocket/nodes.txt
   ```

3. 规则：iPhone 与 Mac 连接同一个 Wi-Fi，执行下面的命令，用 iPhone 相机扫码，
   在 Shadowrocket 中添加并选用该配置，然后回到 Mac 按回车停止分享：

   ```bash
   bash scripts/serve-once.sh --qr-prefix shadowrocket://config/add/ \
     home/.config/shadowrocket/shadowrocket.conf
   ```

   首次运行时 macOS 防火墙可能询问是否允许 miniserve 接受传入连接，需要允许。
   iPhone 打开了“限制 IP 地址跟踪”或连接了其他 VPN 时，局域网访问也可能失败。

4. 连接后分别测试四个节点及 `🚀 proxy` 分组。

规则的远程网址只在分享期间有效，修改规则后需要重新执行第 3 步，不能在 App 里直接更新。
秘密或节点变化时，删除旧节点并重新执行第 2 步。扫码时不要开启屏幕共享或录屏。
Apple Silicon Mac 可从 Mac App Store 安装同一 Apple ID 已购买的 Shadowrocket，
用于在导入手机前手动测试。

## 与 sing-box 的差异

- AI 服务的 DNS 不单独走新加坡：命中代理规则的域名由代理出口解析，效果相近。
- 不使用 FakeIP；直连 DNS 使用阿里 DoH。
- 节点主机名使用公网 DNS 解析，而不是 hosts 映射。
- OpenAI、Claude 和 GFWList 使用 MetaCubeX 的 classical 文本列表，与 sing-box 的 `.srs`
  来自同一数据；OpenAI 列表含一条 DOMAIN-REGEX，Shadowrocket 是否支持尚未验证。
- 规则列表下载由 Shadowrocket 决定出口，不像 sing-box 固定走 us-hy2。
- HY2 的上下行带宽提示不在分享链接中。
- `shadowrocket://config/add/` 扫码添加配置来自社区手册，尚未实测；若无效，在 Shadowrocket 的
  配置页手动添加二维码对应的 `http://` 网址。
