# sing-box macOS 客户端实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在两台 Apple Silicon Mac 上用一套 nix-darwin 配置部署 SFM、共享 SOPS/age secrets、经过校验的 sing-box TUN 配置以及 GFWList 自动分流。

**Architecture:** SFM 是唯一的 sing-box 运行时所有者。nix-darwin 使用 `sops-nix.darwinModules.sops` 将仓库模板和加密秘密渲染为候选配置，执行 JSON 与 sing-box 语义校验后，再原子发布到用户 state 目录；Home Manager 只管理 CLI 软件和 `~/.config/sing-box/config.json` 符号链接。仓库中的 JSON 模板与秘密映射是声明式输入，SFM Local Profile 是人工导入的派生副本。

**Tech Stack:** nix-darwin、Home Manager、sops-nix、SOPS、age、sing-box 1.13.14、SFM、Homebrew casks、Bash、Node.js、jq。

## Global Constraints

- 平台固定为 `aarch64-darwin`，两台 Mac 共用 `darwinConfigurations.mac`。
- 当前锁定 nixpkgs 的 sing-box 版本是 `1.13.14`，最终语义门禁是该版本的 `sing-box check`。
- JSON 顶层必须包含 `"$schema": "https://sing-box.sagernet.org/schema.json"`。
- 在线 Schema 可能先于稳定运行时提供 1.14 字段，不得写入 1.13.14 无法识别的字段。
- SFM 是唯一运行时所有者，不得创建 sing-box LaunchAgent、LaunchDaemon、CLI 常驻进程、Web Dashboard 或 Clash API。
- 不得在命令输出、测试日志、Git、Nix Store、Shell 参数或环境变量中暴露服务器秘密。
- age identity 固定存放于 `~/Library/Application Support/sops/age/keys.txt`，目录模式 `0700`，文件模式 `0600`，`generateKey = false`。
- Bitwarden 项目名称固定为 `dotfiles - sops age identity`，可选 item ID 环境变量名固定为 `BITWARDEN_SOPS_AGE_IDENTITY_ITEM_ID`。
- `home/.config/sing-box/config.json` 是配置结构唯一真相；`secrets/sing-box.yaml` 只保存 SOPS 密文。
- 旧配置 `/Users/rich/Downloads/config.json` 只作为迁移输入，删除前必须再次取得用户明确许可。
- 现有工作区包含用户已暂存且与本计划重叠的 `flake.nix`、`configuration.nix`、`home.nix` 和 `rebuild.sh` 改动。实施前必须由用户提交这些改动，或明确授权将它们与本功能一起提交；不得擅自重置、丢弃或混入功能提交。
- 所有源文件编辑使用 `apply_patch`；SOPS 加密输出和格式化工具生成的机械文件除外。

---

## 文件职责

- `flake.nix`: 声明 sops-nix input、Darwin 模块和唯一的 `darwinConfigurations.mac`。
- `configuration.nix`: 管理 GUI casks，保留 `bitwarden` 并加入 `sfm`。
- `home.nix`: 安装 `age`、`bitwarden-cli`、`sops`、`sing-box`，并创建最终配置链接。
- `sing-box.nix`: 声明 SOPS secrets、模板替换、候选配置和原子发布激活脚本。
- `.sops.yaml`: 保存通用 dotfiles age recipient 和 `secrets/*.yaml` 创建规则。
- `secrets/sing-box.yaml`: 保存从旧配置提取的加密服务器字段。
- `home/.config/sing-box/config.json`: 保存完整 sing-box 结构、规则、非秘密参数和具名秘密标记。
- `home/.config/sing-box/secrets-map.json`: 将每个模板标记映射到唯一的 SOPS key path。
- `scripts/check-sops-age-key.sh`: 检查 identity 路径、权限、recipient 和解密能力。
- `scripts/render-sing-box-config.mjs`: 仅通过 stdin 接收解密后的 JSON，在内存中完成测试渲染并输出到 stdout。
- `scripts/check-sing-box-config.sh`: 通过管道渲染和校验配置，不产生额外明文文件。
- `tests/sing-box-static.sh`: 检查模板标签、规则顺序、秘密覆盖、包和单实例约束。
- `bootstrap.sh`: 在首次 Darwin switch 前执行 identity 预检并固定使用 `#mac`。
- `rebuild.sh`: 支持 `--update`，执行预检，不再自动 `git add .`，固定使用 `#mac`。
- `docs/sing-box.md`: 中文恢复、修改、重建、SFM 导入、切换和排障手册。

---

### Task 1: 统一 Nix 拓扑、软件包和 GUI 所有权

**Files:**
- Modify: `flake.nix`
- Modify: `configuration.nix`
- Modify: `home.nix`

**Interfaces:**
- Consumes: 当前 `sharedModules`、Home Manager 和 nix-homebrew 配置。
- Produces: `inputs.sops-nix`、`darwinConfigurations.mac`、SFM cask、四个所需 CLI 包和最终配置链接。

- [ ] **Step 1: 运行失败的拓扑断言**

```bash
nix eval .#darwinConfigurations.mac.config.system.build.toplevel.drvPath
nix eval --json .#darwinConfigurations.mac.config.homebrew.casks \
  | jq -e '[.[].name] | index("bitwarden") and index("sfm")'
```

Expected: 第一条因为 `darwinConfigurations.mac` 尚不存在而失败；第二条的 cask 名称断言同样失败。

- [ ] **Step 2: 在 `flake.nix` 声明 sops-nix 并改为唯一配置**

加入 input：

```nix
sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

在 `outputs` 参数中接收 `sops-nix`，并将模块列表加入：

```nix
sops-nix.darwinModules.sops
```

`./sing-box.nix` 在 Task 4 创建该文件时再加入，避免当前任务引用不存在的模块。

删除 `mac-laptop` 和 `mac-desktop` 两个重复输出，只保留：

```nix
darwinConfigurations.mac = darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit user inputs; };
  modules = sharedModules;
};
```

- [ ] **Step 3: 声明 GUI casks**

在 `configuration.nix` 的 `homebrew.casks` 中保留：

```nix
"bitwarden"
```

并加入：

```nix
"sfm"
```

不得把 `bw` 或 sing-box CLI 放进 Homebrew `brews`。

- [ ] **Step 4: 声明 CLI 包与运行配置链接**

在 `home.nix` 的 `home.packages` 加入：

```nix
pkgs.age
pkgs.bitwarden-cli
pkgs.sops
pkgs.sing-box
```

在“统一文件映射”中加入：

```nix
".config/sing-box/config.json".source =
  config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/.local/state/sing-box/config.json";
```

不得把仓库模板直接链接到运行路径。

- [ ] **Step 5: 更新 lock 并重新运行拓扑断言**

Run:

```bash
nix flake lock --update-input sops-nix
nix eval .#darwinConfigurations.mac.config.system.build.toplevel.drvPath
nix eval --json .#darwinConfigurations.mac.config.homebrew.casks \
  | jq -e '[.[].name] | index("bitwarden") and index("sfm")'
nix eval --json .#darwinConfigurations.mac.config.home-manager.users.rich.home.packages \
  | jq -e 'length > 0'
```

Expected: 全部返回成功，cask 对象的名称同时包含 Bitwarden 和 SFM。

- [ ] **Step 6: 提交**

```bash
git add flake.nix flake.lock configuration.nix home.nix
git commit -m "feat: define sing-box macOS dependencies"
```

---

### Task 2: 创建共享 age identity 并迁移加密秘密

**Files:**
- Create: `.sops.yaml`
- Create: `secrets/sing-box.yaml`
- Read only: `/Users/rich/Downloads/config.json`

**Interfaces:**
- Consumes: 旧配置中四个实际出站及本机 `age-keygen`、`sops`。
- Produces: 通用 dotfiles age recipient 和以下 18 个 SOPS key path：
  - `sing-box/singapore/server-hostname`
  - `sing-box/singapore/server-ip`
  - `sing-box/singapore/vless/uuid`
  - `sing-box/singapore/vless/tls-server-name`
  - `sing-box/singapore/vless/reality-public-key`
  - `sing-box/singapore/vless/reality-short-id`
  - `sing-box/singapore/hysteria2/password`
  - `sing-box/singapore/hysteria2/obfs-password`
  - `sing-box/singapore/hysteria2/tls-server-name`
  - `sing-box/usa/server-hostname`
  - `sing-box/usa/server-ip`
  - `sing-box/usa/vless/uuid`
  - `sing-box/usa/vless/tls-server-name`
  - `sing-box/usa/vless/reality-public-key`
  - `sing-box/usa/vless/reality-short-id`
  - `sing-box/usa/hysteria2/password`
  - `sing-box/usa/hysteria2/obfs-password`
  - `sing-box/usa/hysteria2/tls-server-name`

- [ ] **Step 1: 验证当前失败状态**

Run:

```bash
test -f "$HOME/Library/Application Support/sops/age/keys.txt"
test -f .sops.yaml
test -f secrets/sing-box.yaml
```

Expected: 当前三项均失败。

- [ ] **Step 2: 初次生成 identity**

先确认 FileVault 已开启：

```bash
fdesetup status
```

Expected: 输出包含 `FileVault is On.`。

生成时不得覆盖已有文件：

```bash
age_key_dir="$HOME/Library/Application Support/sops/age"
age_key_file="$age_key_dir/keys.txt"
install -d -m 0700 "$age_key_dir"
umask 077
test ! -e "$age_key_file"
age-keygen -o "$age_key_file"
chmod 0600 "$age_key_file"
```

若文件已经存在，停止并验证现有 identity，不生成第二把。

- [ ] **Step 3: Bitwarden 人工备份检查点**

在 Bitwarden 创建安全笔记 `dotfiles - sops age identity`，开启主密码重新提示，并将 `keys.txt` 作为附件保存。附件上传完成后，从 Bitwarden 重新下载到一个受控临时位置，比较 SHA-256 后立即移除临时副本：

```bash
shasum -a 256 \
  "$HOME/Library/Application Support/sops/age/keys.txt" \
  "$bitwarden_downloaded_age_key"
```

Expected: 两个摘要相同。此步骤由用户在 Bitwarden 中完成并明确确认后才能继续。

- [ ] **Step 4: 创建 `.sops.yaml`**

Run:

```bash
age_recipient="$(
  age-keygen -y "$HOME/Library/Application Support/sops/age/keys.txt"
)"
printf '%s\n' "$age_recipient"
```

Expected: 只输出一个以 `age1` 开头的公钥。使用 `apply_patch` 创建 `.sops.yaml`。`keys` 中只写上一步输出的完整公钥并定义锚点 `dotfiles_age`；`creation_rules` 使用 `^secrets/.*\.yaml$`，其唯一 age key group 引用 `*dotfiles_age`。文件中不得出现说明性示例 recipient。

- [ ] **Step 5: 通过内存管道提取并加密旧秘密**

使用旧出站的精确 tag 构造嵌套 JSON，不把值传入命令参数：

```bash
age_recipient="$(
  age-keygen -y "$HOME/Library/Application Support/sops/age/keys.txt"
)"
mkdir -p secrets
jq '
  def ob($tag): first(.outbounds[] | select(.tag == $tag));
  (.dns.servers[] | select(.type == "hosts").predefined) as $hosts
  | if
      ob("🇸🇬 aws-singapore-vless").server != ob("🇸🇬 aws-singapore-hy2").server or
      ob("🇺🇸 racknerd-us-vless").server != ob("🇺🇸 racknerd-us-hy2").server
    then error("protocol endpoints differ within a region")
    else .
    end
  |
  {
    "sing-box": {
      singapore: {
        "server-hostname": ob("🇸🇬 aws-singapore-vless").server,
        "server-ip": $hosts[ob("🇸🇬 aws-singapore-vless").server],
        vless: {
          uuid: ob("🇸🇬 aws-singapore-vless").uuid,
          "tls-server-name": ob("🇸🇬 aws-singapore-vless").tls.server_name,
          "reality-public-key": ob("🇸🇬 aws-singapore-vless").tls.reality.public_key,
          "reality-short-id": ob("🇸🇬 aws-singapore-vless").tls.reality.short_id
        },
        hysteria2: {
          password: ob("🇸🇬 aws-singapore-hy2").password,
          "obfs-password": ob("🇸🇬 aws-singapore-hy2").obfs.password,
          "tls-server-name": ob("🇸🇬 aws-singapore-hy2").tls.server_name
        }
      },
      usa: {
        "server-hostname": ob("🇺🇸 racknerd-us-vless").server,
        "server-ip": $hosts[ob("🇺🇸 racknerd-us-vless").server],
        vless: {
          uuid: ob("🇺🇸 racknerd-us-vless").uuid,
          "tls-server-name": ob("🇺🇸 racknerd-us-vless").tls.server_name,
          "reality-public-key": ob("🇺🇸 racknerd-us-vless").tls.reality.public_key,
          "reality-short-id": ob("🇺🇸 racknerd-us-vless").tls.reality.short_id
        },
        hysteria2: {
          password: ob("🇺🇸 racknerd-us-hy2").password,
          "obfs-password": ob("🇺🇸 racknerd-us-hy2").obfs.password,
          "tls-server-name": ob("🇺🇸 racknerd-us-hy2").tls.server_name
        }
      }
    }
  }
' /Users/rich/Downloads/config.json \
  | sops encrypt \
      --age "$age_recipient" \
      --input-type json \
      --output-type yaml \
      --output secrets/sing-box.yaml \
      /dev/stdin
```

- [ ] **Step 6: 验证所有秘密适合 JSON 字符串模板替换**

在不输出值的条件下验证每个字符串都不含双引号、反斜杠、换行或控制字符：

```bash
sops decrypt --output-type json secrets/sing-box.yaml \
  | jq -e '
      [
        .. | strings
        | test("[\"\\\\\\u0000-\\u001f]")
      ]
      | any
      | not
    ' >/dev/null
```

Expected: 返回 0。若失败，停止并改用 JSON 转义后的 SOPS 值，不能继续做原始文本替换。

- [ ] **Step 7: 验证密文而不显示明文**

Run:

```bash
sops filestatus secrets/sing-box.yaml | jq -e '.encrypted == true'
sops decrypt --output-type json secrets/sing-box.yaml \
  | jq -e '
      .["sing-box"].singapore.vless.uuid != null and
      .["sing-box"].singapore["server-ip"] != null and
      .["sing-box"].singapore.hysteria2.password != null and
      .["sing-box"].usa.vless.uuid != null and
      .["sing-box"].usa["server-ip"] != null and
      .["sing-box"].usa.hysteria2.password != null
    ' >/dev/null
if rg -n 'AGE-SECRET-KEY-' . \
  --glob '!docs/superpowers/plans/*.md'; then
  exit 1
fi
```

Expected: 密文状态为 true，六个核心字段存在，仓库中没有 age 私钥或已知明文。

- [ ] **Step 8: 提交**

```bash
git add .sops.yaml secrets/sing-box.yaml
git commit -m "feat: encrypt sing-box server credentials"
```

---

### Task 3: 创建单一配置模板、秘密映射和无落盘校验器

**Files:**
- Create: `home/.config/sing-box/config.json`
- Create: `home/.config/sing-box/secrets-map.json`
- Create: `scripts/render-sing-box-config.mjs`
- Create: `scripts/check-sing-box-config.sh`
- Create: `tests/sing-box-static.sh`

**Interfaces:**
- Consumes: Task 2 的 18 个 SOPS key path。
- Produces:
  - `renderConfig(templateText: string, secretMap: object, secrets: object): string`
  - `scripts/check-sing-box-config.sh [rendered-config-path]`
  - 四个物理出站 `sg-vless`、`sg-hy2`、`us-vless`、`us-hy2`
  - 组出站 `auto`、`singapore`、`usa`、`proxy`

- [ ] **Step 1: 先创建失败的静态测试**

`tests/sing-box-static.sh` 必须使用 `set -euo pipefail`，并通过 jq 断言：

```bash
jq -e '
  .["$schema"] == "https://sing-box.sagernet.org/schema.json" and
  ([.inbounds[].tag] | sort == ["mixed-in", "tun-in"]) and
  ([.outbounds[].tag] | index("proxy") != null) and
  ([.outbounds[].tag] | index("auto") != null) and
  ([.outbounds[].tag] | index("singapore") != null) and
  ([.outbounds[].tag] | index("usa") != null) and
  ([.outbounds[].tag] | index("sg-vless") != null) and
  ([.outbounds[].tag] | index("sg-hy2") != null) and
  ([.outbounds[].tag] | index("us-vless") != null) and
  ([.outbounds[].tag] | index("us-hy2") != null) and
  .route.final == "direct" and
  .route.default_domain_resolver == "proxy-dns" and
  .route.auto_detect_interface == true and
  .experimental.cache_file.enabled == true
' home/.config/sing-box/config.json
```

还必须断言没有 `experimental.clash_api`、没有 Web Dashboard 字段、三个远程 rule-set 的 `download_detour` 均为通用 `proxy`，并确认 18 个 marker 到 SOPS key path 的映射对象与计划中的对象逐项完全一致，而不只是比较 path 集合。三个自定义 inline rule-set 必须各包含且仅包含一个初始哨兵规则，精确匹配保留域名 `sing-box-placeholder.invalid`。

模板标记计数也必须固定：两个 `*_SERVER_HOSTNAME__` 标记各出现四次，分别用于两个物理出站、`hosts-dns` 映射键和共享的 `proxy-server` inline rule-set；其余 16 个标记各出现一次。这样既能复用加密的服务器端点，又能防止无意重复。

Run:

```bash
bash tests/sing-box-static.sh
```

Expected: 因模板和映射文件不存在而失败。

- [ ] **Step 2: 创建 `secrets-map.json`**

使用 18 个唯一标记，例如：

```json
{
  "__SOPS_SG_SERVER_HOSTNAME__": "sing-box/singapore/server-hostname",
  "__SOPS_SG_SERVER_IP__": "sing-box/singapore/server-ip",
  "__SOPS_SG_VLESS_UUID__": "sing-box/singapore/vless/uuid",
  "__SOPS_SG_VLESS_TLS_SERVER_NAME__": "sing-box/singapore/vless/tls-server-name",
  "__SOPS_SG_VLESS_REALITY_PUBLIC_KEY__": "sing-box/singapore/vless/reality-public-key",
  "__SOPS_SG_VLESS_REALITY_SHORT_ID__": "sing-box/singapore/vless/reality-short-id",
  "__SOPS_SG_HY2_PASSWORD__": "sing-box/singapore/hysteria2/password",
  "__SOPS_SG_HY2_OBFS_PASSWORD__": "sing-box/singapore/hysteria2/obfs-password",
  "__SOPS_SG_HY2_TLS_SERVER_NAME__": "sing-box/singapore/hysteria2/tls-server-name",
  "__SOPS_US_SERVER_HOSTNAME__": "sing-box/usa/server-hostname",
  "__SOPS_US_SERVER_IP__": "sing-box/usa/server-ip",
  "__SOPS_US_VLESS_UUID__": "sing-box/usa/vless/uuid",
  "__SOPS_US_VLESS_TLS_SERVER_NAME__": "sing-box/usa/vless/tls-server-name",
  "__SOPS_US_VLESS_REALITY_PUBLIC_KEY__": "sing-box/usa/vless/reality-public-key",
  "__SOPS_US_VLESS_REALITY_SHORT_ID__": "sing-box/usa/vless/reality-short-id",
  "__SOPS_US_HY2_PASSWORD__": "sing-box/usa/hysteria2/password",
  "__SOPS_US_HY2_OBFS_PASSWORD__": "sing-box/usa/hysteria2/obfs-password",
  "__SOPS_US_HY2_TLS_SERVER_NAME__": "sing-box/usa/hysteria2/tls-server-name"
}
```

- [ ] **Step 3: 创建完整 JSON 模板**

模板必须包含以下结构和顺序：

1. `log`: `level = "info"`、`timestamp = true`。
2. `dns.servers`: 直连的 AliDNS DoH `223.5.5.5`、经 `proxy` 的 Cloudflare DoH `1.1.1.1`、把两个加密服务器域名映射到对应固定 IP 的 `hosts-dns`、FakeIP 双栈解析器；TLS server name 分别为 `dns.alidns.com` 和 `cloudflare-dns.com`，不得使用明文 UDP DNS。
3. FakeIP 地址段固定为 IPv4 `198.18.0.0/15` 和 IPv6 `fc00::/18`。
4. `dns.rules` 的顺序固定为：`proxy-server` 规则集使用 `hosts-dns`；GFW、OpenAI、Claude、Google Meet 使用代理 DoH；之后私网响应使用直连 DoH；最后 A/AAAA 进入 FakeIP。受保护域名必须排在 `ip_is_private` 响应过滤之前，避免为判断响应是否私网而先向直连 DNS 泄露查询。
5. `dns.strategy = "prefer_ipv4"`，同时保留 IPv6。
6. `tun-in`: `address = ["172.19.0.1/30", "fdfe:dcba:9876::1/126"]`、`auto_route = true`、`strict_route = true`、`stack = "mixed"`。
7. `mixed-in`: 只监听 `127.0.0.1:7777`。
8. `proxy`: selector 默认 `auto`，成员为 `auto`、`singapore`、`usa` 和四个物理节点，`interrupt_exist_connections = true`。
9. `auto`: URLTest 四个物理节点，URL 为 `https://www.gstatic.com/generate_204`，间隔 `10m`，容差 `50`，`interrupt_exist_connections = false`。
10. `singapore` 和 `usa`: 各自 URLTest 两种协议，间隔 `10m`，`interrupt_exist_connections = false`。
11. 两个 VLESS: `flow = "xtls-rprx-vision"`、REALITY、uTLS `chrome`，并显式设置 `domain_resolver = "hosts-dns"`。
12. 两个 Hysteria2: 保留旧配置的端口、上下行带宽和 Salamander obfs，并显式设置 `domain_resolver = "hosts-dns"`。
13. `direct` 出站。
14. `route.default_domain_resolver = "proxy-dns"`，避免 1.13.14 的缺失解析器错误，并让未被更具体 DNS 规则覆盖的域名继续使用防污染的代理 DoH；四个物理代理出站用自己的 `hosts-dns` 覆盖它，避免启动递归。`route.auto_detect_interface = true`，让 macOS TUN 出站绑定默认物理接口，防止重新进入 TUN。路由规则顺序严格为 sniff、DNS hijack、代理服务器目标直连、私网直连、`custom-reject`、`custom-direct`、`custom-proxy`、OpenAI、Claude、Google Meet UDP、Google Meet 通用、GFWList、final direct。
15. `custom-reject`、`custom-direct` 和 `custom-proxy` 是可编辑的 inline rule-set。sing-box 1.13.14 拒绝空的 inline rule-set，因此三个 `rules` 数组初始都包含一个精确匹配保留域名 `sing-box-placeholder.invalid` 的无害哨兵规则。用户以后向对应 `rules` 数组追加自定义规则，不要删除哨兵。
15.1. `proxy-server` 是包含两个加密服务器域名的 inline rule-set；DNS 规则引用它并交给 `hosts-dns` 返回加密保存的固定 IP，路由规则引用它并强制直连，避免启动递归和 DNS 污染。
16. Google Meet inline rule-set 包含 `meet.google.com`、`meetings.googleapis.com`、`stun.l.google.com`、`workspace.turns.goog`、`meet.turns.goog`，以及 `74.125.250.0/24`、`142.250.82.0/24`、`2001:4860:4864:5::/64`、`2001:4860:4864:6::/64`。UDP `3478` 和 `19302:19309` 在该服务规则中经 `proxy`。
17. 远程规则集只保留 GFWList、OpenAI 和 Claude，URL 分别为 MetaCubeX 的 `gfw.srs`、`openai.srs` 和 `anthropic.srs`，更新间隔均为 `24h`。
18. GFWList URL 固定为 `https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs`。
19. 使用 `experimental.cache_file.enabled = true`、`store_fakeip = true`，不包含 Clash API。

在线 Schema 已包含 1.14 的 `http_client`，但锁定运行时 1.13.14 不识别该顶层字段。三个远程 rule-set 在 1.13.14 中统一使用 `"download_detour": "proxy"`；升级运行时并完成兼容测试前不得提前加入 `http_clients`。

- [ ] **Step 4: 实现内存渲染器**

`scripts/render-sing-box-config.mjs` 必须：

```javascript
import fs from "node:fs";

function getPath(object, path) {
  return path.split("/").reduce((value, key) => {
    if (value === null || typeof value !== "object" || !(key in value)) {
      throw new Error(`missing SOPS key path: ${path}`);
    }
    return value[key];
  }, object);
}

export function renderConfig(templateText, secretMap, secrets) {
  let rendered = templateText;
  for (const [marker, path] of Object.entries(secretMap)) {
    const value = getPath(secrets, path);
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`invalid secret value for: ${path}`);
    }
    const occurrences = rendered.split(marker).length - 1;
    if (occurrences < 1) {
      throw new Error(`expected marker at least once: ${marker}`);
    }
    rendered = rendered.split(marker).join(value);
  }
  if (/__SOPS_[A-Z0-9_]+__/.test(rendered)) {
    throw new Error("unresolved SOPS marker remains");
  }
  JSON.parse(rendered);
  return rendered;
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const [templatePath, mapPath] = process.argv.slice(2);
  if (!templatePath || !mapPath) {
    throw new Error("usage: render-sing-box-config.mjs TEMPLATE MAP");
  }
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const secrets = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const output = renderConfig(
    fs.readFileSync(templatePath, "utf8"),
    JSON.parse(fs.readFileSync(mapPath, "utf8")),
    secrets,
  );
  process.stdout.write(output);
}
```

- [ ] **Step 5: 实现无额外明文文件的检查脚本**

`scripts/check-sing-box-config.sh` 使用：

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
template="$repo_dir/home/.config/sing-box/config.json"
secret_map="$repo_dir/home/.config/sing-box/secrets-map.json"
encrypted_secrets="$repo_dir/secrets/sing-box.yaml"

if [ "$#" -eq 1 ]; then
  jq -e . "$1" >/dev/null
  exec sing-box check -c "$1"
fi

sops decrypt --output-type json "$encrypted_secrets" \
  | node "$repo_dir/scripts/render-sing-box-config.mjs" "$template" "$secret_map" \
  | sing-box check -c /dev/stdin
```

该管道不得使用 `tee`，不得打印渲染后的 JSON。

- [ ] **Step 6: 运行测试**

Run:

```bash
bash tests/sing-box-static.sh
bash scripts/check-sing-box-config.sh
```

Expected: 静态断言通过，`sing-box check` 返回 0，输出中不含服务器地址、UUID、密码或密钥。

静态测试还必须导入 `renderConfig` 并传入会在替换后形成非法 JSON 的秘密值，断言渲染器拒绝该输入；这与缺失路径、缺失 marker、重复 marker 全量替换和残留 marker 测试一起构成负向覆盖。

- [ ] **Step 7: 提交**

```bash
git add \
  home/.config/sing-box/config.json \
  home/.config/sing-box/secrets-map.json \
  scripts/render-sing-box-config.mjs \
  scripts/check-sing-box-config.sh \
  tests/sing-box-static.sh
git commit -m "feat: add validated sing-box client template"
```

---

### Task 4: 用 sops-nix Darwin 模块事务性发布配置

**Files:**
- Create: `sing-box.nix`
- Create: `scripts/publish-sing-box-config.sh`
- Modify: `flake.nix`
- Modify: `tests/sing-box-static.sh`

**Interfaces:**
- Consumes: Task 3 的模板、映射和 18 个 SOPS key path。
- Produces:
  - `/run/secrets/rendered/sing-box-candidate.json`
  - `/Users/rich/.local/state/sing-box/config.json`
  - `~/.config/sing-box/config.json` 符号链接的有效目标。

- [ ] **Step 1: 增加失败的 Nix 断言**

在静态测试中加入：

```bash
nix eval --raw \
  .#darwinConfigurations.mac.config.sops.templates.sing-box-candidate.path \
  | grep -Fx '/run/secrets/rendered/sing-box-candidate.json'

nix eval --raw \
  .#darwinConfigurations.mac.config.sops.age.keyFile \
  | grep -Fx '/Users/rich/Library/Application Support/sops/age/keys.txt'
```

Expected: `sing-box.nix` 尚不存在时失败。

- [ ] **Step 2: 实现映射驱动的 sops-nix 模板**

先在 `flake.nix` 的共享模块列表加入：

```nix
./sing-box.nix
```

`sing-box.nix` 的核心定义：

```nix
{ config, lib, pkgs, user, ... }:

let
  templatePath = ./home/.config/sing-box/config.json;
  secretMap =
    builtins.fromJSON
      (builtins.readFile ./home/.config/sing-box/secrets-map.json);
  markers = builtins.attrNames secretMap;
  secretPaths = lib.unique (map (marker: secretMap.${marker}) markers);
  replacements =
    map (marker: config.sops.placeholder.${secretMap.${marker}}) markers;
  candidate = config.sops.templates."sing-box-candidate.json".path;
  stateDir = "/Users/${user}/.local/state/sing-box";
  finalConfig = "${stateDir}/config.json";
in
{
  sops = {
    defaultSopsFile = ./secrets/sing-box.yaml;
    defaultSopsFormat = "yaml";
    age = {
      keyFile = "/Users/${user}/Library/Application Support/sops/age/keys.txt";
      generateKey = false;
    };
    secrets = lib.genAttrs secretPaths (_: { });
    templates."sing-box-candidate.json" = {
      content = builtins.replaceStrings
        markers
        replacements
        (builtins.readFile templatePath);
      mode = "0400";
    };
  };
}
```

- [ ] **Step 3: 增加降权、校验后原子发布**

root 激活脚本不得在用户可控的 home 路径中执行 `install -d`、`chown`、`chmod`、`mktemp` 或 `mv`，否则目录符号链接可把这些操作重定向到任意 root 可写目标。新增 `scripts/publish-sing-box-config.sh`，由普通用户执行：

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: publish-sing-box-config.sh STATE_DIR FINAL_CONFIG COREUTILS_BIN" >&2
  exit 64
fi

state_dir="$1"
final_config="$2"
coreutils_bin="$3"

for utility in install mktemp rm cat chmod mv; do
  if [ ! -x "$coreutils_bin/$utility" ]; then
    echo "missing required coreutils binary: $utility" >&2
    exit 1
  fi
done

if [ "$final_config" != "$state_dir/config.json" ]; then
  echo "refusing unexpected final config path" >&2
  exit 1
fi
if [ -L "$state_dir" ]; then
  echo "refusing symlink state directory" >&2
  exit 1
fi
if [ -e "$state_dir" ] && [ ! -d "$state_dir" ]; then
  echo "refusing non-directory state path" >&2
  exit 1
fi

"$coreutils_bin/install" -d -m 0700 "$state_dir"

if [ -L "$final_config" ] ||
  { [ -e "$final_config" ] && [ ! -f "$final_config" ]; }; then
  echo "refusing non-regular final config" >&2
  exit 1
fi

umask 077
tmp="$("$coreutils_bin/mktemp" "$state_dir/.config.json.XXXXXX")"
cleanup() {
  "$coreutils_bin/rm" -f "$tmp"
}
trap cleanup EXIT

"$coreutils_bin/cat" >"$tmp"
"$coreutils_bin/chmod" 0600 "$tmp"
"$coreutils_bin/mv" -Tf -- "$tmp" "$final_config"
trap - EXIT
```

`sing-box.nix` 将该脚本作为普通 Nix Store 输入引用。在同一个模块中加入顺序晚于 sops-nix `mkAfter` 的 postActivation。root 只验证 `/run/secrets` 中的候选文件，随后通过标准输入把内容交给降权后的发布助手：

```nix
system.activationScripts.postActivation.text = lib.mkOrder 2000 ''
  echo "validating sing-box configuration..."
  state_dir=${lib.escapeShellArg stateDir}
  final_config=${lib.escapeShellArg finalConfig}
  candidate=${lib.escapeShellArg candidate}

  ${pkgs.jq}/bin/jq -e . "$candidate" >/dev/null
  ${pkgs.sing-box}/bin/sing-box check -c "$candidate"
  ${pkgs.coreutils}/bin/cat "$candidate" \
    | /usr/bin/sudo -u ${lib.escapeShellArg user} -- \
        ${pkgs.bash}/bin/bash ${./scripts/publish-sing-box-config.sh} \
          "$state_dir" "$final_config" ${pkgs.coreutils}/bin
'';
```

失败时必须保留上一份 `finalConfig`，不得触碰 SFM。静态测试必须用临时目录实际执行发布助手，并覆盖：正常首次发布、替换已有普通文件、状态目录符号链接、最终路径是目录、最终路径是符号链接。后三种攻击输入必须非零退出、保持链接目标或目录内容不变，且不遗留 `.config.json.*` 临时文件。

- [ ] **Step 4: 评估和构建**

Run:

```bash
bash tests/sing-box-static.sh
nix flake check
nix build .#darwinConfigurations.mac.system --dry-run
```

Expected: Nix 评估成功，不需要在构建阶段读取私钥，SOPS 密文可以进入 Store，但明文和 identity 不进入 Store。

- [ ] **Step 5: 提交**

```bash
git add \
  flake.nix \
  sing-box.nix \
  scripts/publish-sing-box-config.sh \
  tests/sing-box-static.sh
git commit -m "feat: render sing-box config with sops-nix"
```

---

### Task 5: 加固 bootstrap 和 rebuild

**Files:**
- Create: `scripts/check-sops-age-key.sh`
- Modify: `bootstrap.sh`
- Modify: `rebuild.sh`
- Modify: `tests/sing-box-static.sh`

**Interfaces:**
- Consumes: `.sops.yaml` recipient、标准 identity 路径、`secrets/sing-box.yaml`。
- Produces: 可复用的零明文 preflight，以及固定 `#mac` 的安全重建入口。

- [ ] **Step 1: 写失败的脚本测试**

静态测试必须断言：

```bash
grep -Fq 'darwinConfigurations.mac' flake.nix
grep -Fq '#mac' bootstrap.sh
grep -Fq '#mac' rebuild.sh
if grep -Fq 'git add .' rebuild.sh; then
  exit 1
fi
if rg -n 'sing-box[[:space:]]+run|launchctl.*sing-box' \
  bootstrap.sh rebuild.sh scripts sing-box.nix; then
  exit 1
fi
```

Expected: 当前 `rebuild.sh` 仍包含 `git add .`，测试失败。

- [ ] **Step 2: 实现 identity preflight**

`scripts/check-sops-age-key.sh` 必须执行：

1. 检查标准路径存在。
2. 用 `stat -f '%Lp'` 检查目录 `700` 和文件 `600`。
3. 用 `age-keygen -y` 推导 recipient。
4. 从 `.sops.yaml` 读取唯一的 `age1...` recipient 并精确比较。
5. 用 `sops decrypt secrets/sing-box.yaml >/dev/null` 验证解密。
6. 所有错误只打印路径、权限和 Bitwarden 项目名称，不打印 identity 或秘密。

缺失时的错误信息必须包含：

```text
Bitwarden item: dotfiles - sops age identity
Expected path: ~/Library/Application Support/sops/age/keys.txt
```

- [ ] **Step 3: 修改 bootstrap**

保留现有 Determinate Nix 安装和用户名个性化逻辑，在首次 switch 前执行：

```bash
"$NIX_BIN" shell nixpkgs#age nixpkgs#sops --command \
  "$DIR/scripts/check-sops-age-key.sh"
```

目标固定为：

```bash
switch --flake ~/.dotfiles#mac
```

bootstrap 不登录 Bitwarden、不生成 identity、不启动 SFM。

- [ ] **Step 4: 修改 rebuild**

恢复严格脚本头：

```bash
#!/usr/bin/env bash
set -euo pipefail
```

只接受无参数、`--update` 或 `-u`。执行顺序：

```text
解析参数
检查 identity
检查模板和秘密
可选 nix flake update
sudo darwin-rebuild switch --flake ~/.dotfiles#mac
```

删除目标参数、`mac-desktop` 默认值和 `git add .`。重建不启动、不停止、不重启 SFM。

- [ ] **Step 5: 运行脚本测试**

Run:

```bash
shellcheck bootstrap.sh rebuild.sh \
  scripts/check-sops-age-key.sh \
  scripts/check-sing-box-config.sh
bash tests/sing-box-static.sh
bash scripts/check-sops-age-key.sh
bash scripts/check-sing-box-config.sh
```

Expected: 全部通过，输出不包含任何秘密。

- [ ] **Step 6: 提交**

```bash
git add \
  bootstrap.sh \
  rebuild.sh \
  scripts/check-sops-age-key.sh \
  tests/sing-box-static.sh
git commit -m "feat: add safe sing-box rebuild preflight"
```

---

### Task 6: 激活配置并验证单实例边界

**Files:**
- Runtime: `/run/secrets/rendered/sing-box-candidate.json`
- Runtime: `/Users/rich/.local/state/sing-box/config.json`
- Runtime link: `/Users/rich/.config/sing-box/config.json`

**Interfaces:**
- Consumes: Tasks 1-5 的完整声明式配置。
- Produces: 当前 Mac 上通过校验、权限正确、尚未自动启动 SFM 的运行配置。

- [ ] **Step 1: 激活前记录基线**

Run:

```bash
pgrep -alf 'sing-box|SFM' || true
launchctl list | rg -i 'sing-box|sfm' || true
lsof -nP -iTCP:7777 -sTCP:LISTEN || true
lsof -nP -iTCP:9090 -sTCP:LISTEN || true
```

Expected: 不存在 CLI sing-box 常驻进程、第三方 launchd 服务或 9090 Dashboard 监听。

- [ ] **Step 2: 构建但不切换**

Run:

```bash
nix flake check
nix build .#darwinConfigurations.mac.system
```

Expected: 构建成功，期间不启动 SFM 或 sing-box。

- [ ] **Step 3: 执行一次系统切换**

Run:

```bash
./rebuild.sh
```

Expected: 需要 sudo，安装 SFM cask和 CLI 包，sops-nix 生成候选配置，postActivation 校验并发布最终配置；脚本不启动 SFM。

- [ ] **Step 4: 验证文件和内容边界**

Run:

```bash
test -L "$HOME/.config/sing-box/config.json"
test "$(readlink "$HOME/.config/sing-box/config.json")" \
  = "$HOME/.local/state/sing-box/config.json"
test "$(stat -f '%Lp' "$HOME/.local/state/sing-box")" = "700"
test "$(stat -f '%Lp' "$HOME/.local/state/sing-box/config.json")" = "600"
jq -e . "$HOME/.config/sing-box/config.json" >/dev/null
sing-box check -c "$HOME/.config/sing-box/config.json"
```

Expected: 全部通过，不打印配置正文。

- [ ] **Step 5: 验证失败保留上一版本**

先记录最终文件摘要，在一个独立临时副本中制造无效配置并执行检查，不修改仓库或运行文件：

```bash
before="$(
  shasum -a 256 "$HOME/.local/state/sing-box/config.json" | awk '{print $1}'
)"
if printf '{' | sing-box check -c /dev/stdin; then
  exit 1
fi
after="$(
  shasum -a 256 "$HOME/.local/state/sing-box/config.json" | awk '{print $1}'
)"
test "$before" = "$after"
```

Expected: 无效配置检查失败，已发布配置摘要不变。

- [ ] **Step 6: 再次检查没有额外实例**

Run:

```bash
pgrep -alf 'sing-box|SFM' || true
launchctl list | rg -i 'sing-box' || true
lsof -nP -iTCP:9090 -sTCP:LISTEN || true
```

Expected: rebuild 没有启动 sing-box 或 SFM，没有 Dashboard。

---

### Task 7: SFM 导入和网络端到端验收

**Files:**
- Modify: `docs/sing-box.md`
- SFM derived state: 只通过官方 UI 导入，不直接编辑应用容器。

**Interfaces:**
- Consumes: 已校验的 `~/.config/sing-box/config.json`。
- Produces: 一个 SFM Local Profile、一个 Network Extension 实例、可切换的四节点运行配置。

- [ ] **Step 1: 编写导入前操作手册**

`docs/sing-box.md` 必须说明：

```text
1. 执行 ./rebuild.sh。
2. 确认 scripts/check-sing-box-config.sh 通过。
3. 打开 SFM。
4. 从 ~/.config/sing-box/config.json 导入 Local Profile。
5. 不在 SFM 内长期编辑配置。
6. 配置改变后重新导入，rebuild 本身不重启 SFM。
```

- [ ] **Step 2: 首次打开 SFM 并由用户批准系统权限**

Run:

```bash
open -a SFM
```

用户在 macOS 系统界面批准 Network Extension 与 VPN 配置。不得通过脚本绕过批准。

- [ ] **Step 3: 通过官方 UI 导入配置**

在 SFM 中创建或替换唯一的 Local Profile，来源为：

```text
/Users/rich/.config/sing-box/config.json
```

如果 SFM 导入后保存内部副本，在手册中记录“每次仓库配置变化后重新导入”。不得写入 SFM 私有容器实现同步。

- [ ] **Step 4: 启动后验证恰好一个运行实例**

Run:

```bash
pgrep -alf 'sing-box|SFM'
launchctl list | rg -i 'sing-box|sfm'
ifconfig | rg -n '^utun'
lsof -nP -iTCP:7777 -sTCP:LISTEN
lsof -nP -iTCP:9090 -sTCP:LISTEN && exit 1 || true
```

Expected: 只有 SFM 管理的一个 Network Extension 核心，mixed 端口 7777 存在，9090 不存在。

- [ ] **Step 5: 验证 DNS、TUN 和规则**

逐项验证：

```text
IPv4 和 IPv6 默认流量进入 TUN
普通 A 和 AAAA 查询返回 FakeIP 地址段
局域网、localhost 和 .local 保持直连
GFWList 测试域名经 proxy
未匹配测试域名直连
OpenAI 与 Claude 经 proxy
Google Meet TCP 与 UDP 经 proxy
DNS 请求被劫持到 sing-box，系统 UDP DNS 不泄漏
```

使用 SFM 日志和出口 IP 检查，不在日志中展示服务器凭据。

- [ ] **Step 6: 验证节点选择**

依次在 SFM 中选择：

```text
auto
singapore
usa
sg-vless
sg-hy2
us-vless
us-hy2
```

每次通过外部出口 IP 和 SFM 日志确认选择生效。自动 URLTest 不打断既有连接；手动切换按模板设置处理现有连接。

- [ ] **Step 7: 停止和重复启动测试**

停止 SFM 后确认：

```text
mixed 端口 7777 消失
系统 DNS 和默认路由恢复
不存在残留 CLI sing-box
```

重复启动、停止、导入和切换两轮，确认不会产生第二个核心或第二个 TUN 所有者。

- [ ] **Step 8: 提交手册**

```bash
git add docs/sing-box.md
git commit -m "docs: add sing-box and SFM operations guide"
```

---

### Task 8: 最终验证、安全审计和旧文件处置

**Files:**
- Verify: all files changed by Tasks 1-7
- Optional delete after approval: `/Users/rich/Downloads/config.json`

**Interfaces:**
- Consumes: 完整实现和当前运行状态。
- Produces: 可复现的新机流程、无明文泄漏的 Git 差异和用户确认的最终状态。

- [ ] **Step 1: 全量静态验证**

Run:

```bash
git diff --check
shellcheck bootstrap.sh rebuild.sh scripts/*.sh
bash tests/sing-box-static.sh
bash scripts/check-sops-age-key.sh
bash scripts/check-sing-box-config.sh
nix flake check
nix build .#darwinConfigurations.mac.system
```

Expected: 全部通过。

- [ ] **Step 2: 审计 Git 内容**

Run:

```bash
git status --short
git diff --cached --stat
git grep -n 'AGE-SECRET-KEY-' -- . ':!docs/superpowers/plans/*' && exit 1 || true
git grep -nE '\"(uuid|password|public_key|short_id)\"[[:space:]]*:[[:space:]]*\"[^_]' \
  -- ':!secrets/sing-box.yaml' ':!docs/superpowers/plans/*' \
  && exit 1 || true
sops filestatus secrets/sing-box.yaml | jq -e '.encrypted == true'
```

Expected: 没有 age 私钥和已知明文凭据，SOPS 文件为密文。

- [ ] **Step 3: 验证新机恢复路径**

在不移动当前 identity 的情况下，用一个受控临时目录从 Bitwarden 附件恢复副本，检查模式、recipient 和解密能力，随后删除临时副本。不得修改当前有效 identity。

Expected: 恢复副本推导的 recipient 与 `.sops.yaml` 完全一致，能解密 `secrets/sing-box.yaml`。

- [ ] **Step 4: 请求旧明文文件处置许可**

向用户报告：

```text
/Users/rich/Downloads/config.json 仍为 0644 明文迁移输入。
新配置已验证且 Bitwarden 备份已验证。
是否允许将旧文件移到废纸篓？
```

只有用户明确允许后才使用可恢复的废纸篓操作。不得直接 `rm`。

- [ ] **Step 5: 最终提交与状态报告**

只提交属于本计划且已经审核的剩余文件：

```bash
git status --short
git diff --check
```

最终报告必须包含：

```text
最终配置路径
SFM 导入状态
四节点验证结果
GFWList、DNS、TUN 和服务规则结果
单实例检查结果
Bitwarden 备份验证结果
旧明文文件是否仍存在
未提交的用户原有改动
```
