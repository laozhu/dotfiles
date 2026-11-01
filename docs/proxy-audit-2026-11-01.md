# custom-proxy 直连测评：2026-11-01

本次检查仓库当时剩余的 17 条 domain_suffix，覆盖 35 个主机及代表性业务路径。
结论只适用于测试时的网络，不代表所有子域名、IPv6、完整登录或支付流程均可用。

## 方法与判读

- SFM 保持连接；系统 DNS 指向 TUN，因此不把系统解析当作运营商 DNS。
- 向 DHCP 提供的局域网路由器查询 A 记录，确认路由器经 en0 可达。
- 对照经显式代理访问的 Cloudflare DNS-over-HTTPS 结果。
- HTTPS 使用 `curl --interface en0 --noproxy '*' --resolve`，固定被测 IP，保留 TLS 证书校验。
  en0 的 scoped 路由经物理网关，不使用 TUN 默认路由。
- 比较本地和可信 DNS 的 IP；异常主机逐 IP 复测。候选移除项补测两轮，
  下载使用 Range 读取样本，重定向逐跳使用局域网 DNS 解析并固定地址。
- 401 是 API 未认证响应；403/404/405 表示收到 HTTPS 服务响应，不等于网络封锁，
  但单独一个根路径响应也不能证明真实业务可用。CDN 地址不同本身不是污染证据。
- curl 连接超时只能证明该次连接未成功，不能区分封锁、丢包或远端故障，
  也不足以判断是目标 IP 还是域名/SNI 被封锁。

## 策略更正

用户确认：即使网络直连可达，服务也可能限制大陆 IP。本轮曾移除的 8 条规则已全部恢复，
下表的连通性结果保留作诊断证据，不再作为移除依据。此前移除的 cache.thalheim.io、
open-vsx.org、openvsx.eclipsecontent.org 不属于本轮恢复范围。

## 逐条结论

| 原规则 | 测试证据 | 判定 | 处理 |
| --- | --- | --- | --- |
| github.com | 主站、api 两轮均 200；codeload 返回 200 并传输数据，但归档未在 9 秒内完成 | 主站/API 可直连，无 DNS 污染证据；完整大文件下载未验证 | 保留，考虑大陆 IP 下的服务可用性 |
| npass.app | 根域名无 A；实际 downloads.npass.app/mac/arm/NordPass.dmg 读取样本 206，另两轮 HEAD 200 | 已测下载可直连 | 保留，考虑大陆 IP 下的服务可用性 |
| logi.com | 官方 lghub_installer.zip 返回 302，逐跳直连 download.logitech.com.cn 返回 206；另两轮 302 | 已测下载链可直连 | 保留，考虑大陆 IP 下的服务可用性 |
| logitechg.com | updates.ghub.logitechg.com 多轮 HTTPS 403，未验证实际更新清单 | 可建立连接，业务路径证据不足 | 保留 |
| githubusercontent.com | 本地与可信 DNS 都返回 185.199.108-111.133；raw、objects、release-assets 各有不同 IP 的超时与成功；raw 实际文件出现传输超时 | 无明显 DNS 污染；连接/传输不稳定，不能认定固定 IP 或域名被封锁 | 保留 |
| githubassets.com | github.githubassets.com 多 IP 复测，部分 404、部分连接超时；代理 404 | 无明显 DNS 污染；直连不稳定 | 保留 |
| cache.nixos.org | 首轮本地 IP 146.75.113.91 与可信 IP 均 200；实际 nix-cache-info 及随后两轮本地 IP 连接超时；代理 200 | CDN DNS 差异不足以认定污染；本地所选节点不稳定 | 保留 |
| cloudfront.net | 根域名无 A；已知 dr2v7l5emb758 子域本地与可信 IP 均返回 403，缺少有效对象路径 | 该分发可建立 HTTPS，不能外推所有 CloudFront 分发可用 | 保留 |
| slack-edge.com | 根域名无 A；emoji 子域经重定向返回 404；a 子域 403 | 已测节点可连接，但缺少有效资源与完整 Slack 验证 | 保留 |
| slack-imgs.com | 多个 CDN 节点首轮 200，后续节点连接超时；代理 200；files 子域无 A | 无明显 DNS 污染；直连不稳定 | 保留 |
| s3.ap-southeast-2.amazonaws.com | 路由器返回 108.160.166.253 且连接超时；可信 DNS 返回多个 3.5.* / 52.95.* 地址，逐个均收到 HTTPS 405；代理 405 | 本地 DNS 响应明显异常，高度疑似污染；可信 IP 可连接，未发现整体 AWS IP 封锁证据 | 保留代理 DNS 和路由 |
| hcaptcha.com | 根域名重测 302，js.hcaptcha.com/1/api.js GET 200，API 302；脚本两轮 HEAD 405 | 已测服务可直连，HEAD 方法限制不影响 GET | 保留，考虑大陆 IP 下的服务可用性 |
| challenges.cloudflare.com | turnstile/v0/api.js 逐跳直连 302 → 200，另两轮 302 | 已测脚本可直连 | 保留，考虑大陆 IP 下的服务可用性 |
| turnstile.com | 本地与可信 DNS 同为 209.17.116.165，多轮 200 | 已测站点可直连；不要把它当作 challenges.cloudflare.com 的替代域名 | 保留，考虑大陆 IP 下的服务可用性 |
| stripe.com | js.stripe.com/v3/ 读取样本 206、两轮 HEAD 200；api.stripe.com/v1/charges 多轮正常 401；checkout 301/302 | 已测页面、脚本和 API 可直连；未执行支付交易 | 保留，考虑大陆 IP 下的服务可用性 |
| monoova.com | 首页逐跳直连；API 与可信 IP 均正常 401，另两轮相同；TLS 验证通过 | 已测页面/API 可直连；未执行认证后的交易 | 保留，考虑大陆 IP 下的服务可用性 |
| auth0.com | 主站 200/206；cdn.auth0.com 一个本地节点 54.192.250.35 重复超时，可信节点 99.86.9.143 返回 200；换本地节点后脚本可下载；代理 200 | 不是整个域名被封锁；部分 CDN 节点不稳定，不能证明 DNS 污染 | 保留 |

本轮 17 条全部保留。本次没有足够证据将任何目标确认为“整个域名或全部 IP 被封锁”。

## 生效与回退

这里只修改仓库模板，没有改动运行中的 SFM。rebuild 发布后需重新导入 SFM。
这批服务保持 custom-proxy 显式代理，实际出口以导入配置的匹配结果为准。
如后续在实际应用中发现验证码、登录或下载失败，记录具体失败主机和路径后再补充窄规则。
