# sing-box 性能审计

审计日期：2026-10-16。通过 SSH 读取两台服务器，并使用本机 sing-box 1.14.2
的单次 fetch 测试；节点连接绑定物理接口，避免流量被现有 SFM 再次代理。
首次审计只读；随后按用户要求完成客户端调整、SFM 导入验证，并进行服务端
调整前后的对照测速。唯一服务端修改为美国的通用 UDP 缓冲区系统上限，
具体记录见下文。没有由代理运行 rebuild，也没有重启在线服务。

## 服务端对比

| 项目 | 新加坡 Lightsail | 美国 RackNerd | 判断 |
| --- | --- | --- | --- |
| TCP 拥塞控制 / 默认队列 | BBR / fq | BBR / fq | 已对齐；不等于 HY2 使用 TCP BBR |
| HY2 版本 | 2.9.1 | 2.9.1 | 已对齐 |
| 服务文件描述符上限 | 524288 | 524288 | 已对齐 |
| 系统 UDP socket 收发缓冲区上限 | 各 16 MiB | 各 212992 字节，已提高至 16 MiB | 已补齐通用系统参数；不等于实际 socket 大小 |
| 运行中的 HY2 socket 收发缓冲区 | 各 16 MiB | 调整前后均为各 16 MiB | 原先运行时就已一致，不能把系统上限当作当前瓶颈 |
| UDP 接收缓冲区错误 | 0 | 累计 1491 | 美国曾发生内核接收缓冲区丢包；累计值不能证明当前仍在丢包 |
| HY2 QUIC 流 / 连接接收窗口 | 显式 26843545 / 67108864 字节 | 未显式配置 | 保留；没有证据表明默认窗口限制了当前速度 |
| HY2 服务端带宽配置 | 未显式配置 | up 100 / down 200 Mbps | 保留服务器专属配置 |
| HY2 监听端口 | UDP 443 | UDP 8443 | 保留，与客户端匹配 |
| VLESS / REALITY | TCP 443 / Apple | TCP 443 / Microsoft | 保留各自目标与 SNI |
| Xray | 原版 26.4.25 | 26.4.25 + REALITY 17 KiB 补丁 | 美国补丁解决已复现的证书记录过大问题；不为版本号一致升级新加坡 |
| HY2 证书到期日 | 2027-01-14 | 2026-12-12 | 均有效；新加坡此前已完成续期 |
| 证书续期任务 | root 每日任务，记录日志 | root 每日任务，无单独日志 | 日志能力有差异；没有修改美国任务 |
| 内存 / swap | 约 1 GB / 无 swap | 约 1 GB / 1 GB swap | 平台与运行策略差异，不为对齐而改动 |
| 网卡 MTU | 9001，AWS 网卡 | 1500 | 保留平台差异，不改网络路径参数 |

两台 Xray 都使用 Vision，未启用额外 multiplex，出口为 freedom / AsIs；
审计时负载很低，服务内存和网卡错误计数未显示资源瓶颈。

HY2 的 QUIC BBR 与 Linux TCP BBR 是不同层面的设置。当前客户端保留原有的
`up_mbps` / `down_mbps`，会参与 Brutal 带宽协商；新加坡服务端写了
`congestion.type: bbr` 不代表这些客户端请求会强制使用 BBR。
美国的服务端带宽上限和各地区的客户端带宽值均未修改。
参见 [HY2 拥塞控制与带宽协商](https://hysteria.network/docs/advanced/Full-Server-Config/#congestion-control-details)
和 [sing-box HY2 带宽字段](https://sing-box.sagernet.org/configuration/outbound/hysteria2/#up_mbps-down_mbps)。

### 已实施的通用系统调整及判断修正

美国的 `net.core.rmem_max`、`net.core.wmem_max` 已从 212992 提高到
16777216，并写入 `/etc/sysctl.d/100-hysteria2.conf`，采用
[Hysteria 官方性能建议](https://hysteria.network/docs/advanced/Performance/#linux)
的上限值。新加坡本来已配置相同上限，没有改动。

进一步检查 `ss -ulnmp` 发现，美国运行中 HY2 的 `rb`、`tb` 原本就都是
16777216，且服务具有 `CAP_NET_ADMIN`。quic-go 可以通过
[SO_RCVBUFFORCE](https://github.com/quic-go/quic-go/pull/3804) 绕过常规系统
上限。这修正了初次只依据 sysctl 数值推断的瓶颈：本次调整补齐系统默认策略，
没有扩大当前已经足够大的 socket，不能据此承诺当前连接提速。

无需为此重启服务。美国 HY2、Xray 的 PID 和配置文件 SHA-256 均在调整前后
核对一致；端口、TLS / REALITY、认证、地区带宽和 QUIC 窗口都未修改。
没有应用未经证实有收益的内核、核心版本或进程优先级改动。

备份及回滚脚本位于美国服务器
`/root/proxy-network-tuning-20261016-n05_3i2i/`。运行其中的 `rollback.sh`
可删除新增 sysctl 文件并恢复两个旧上限，不需要重启服务。
macOS rebuild 不会部署或撤销 Linux 服务器设置。

新加坡保留了一个指向不存在的 `/home/ubuntu/.acme.sh` 的旧 cron 任务，
有效的续期任务在 root 下。旧任务可另行清理，但不是此次客户端提速改动。

## 客户端调整

- 所有代理组和节点增加 emoji，并同步 selector、URLTest、DNS、路由、
  HTTP client 的出站引用；`direct` 和规则集标签保持原名。
- URLTest 从 10 分钟改为 3 分钟，三个组显式使用 50 ms 容差。候选中 HY2
  优先排列，全局组首先放美国 HY2；首次探测后的选择仍由实测延迟决定。
  自动选择变化时保留既有连接。参见 [URLTest](https://sing-box.sagernet.org/configuration/outbound/urltest/)。
- 启用 `store_dns`，复用重载前的 DNS 缓存；启用 `optimistic`，最多使用
  过期 5 分钟的记录并后台刷新。不会给首次访问的域名省去必要的查询。
  保留原有的 DNS 分流、IPv4 与 FakeIP 规则。参见
  [DNS 缓存](https://sing-box.sagernet.org/configuration/dns/#optimistic) 和
  [持久缓存](https://sing-box.sagernet.org/configuration/experimental/cache-file/#store_dns)。
- 远程规则集改用共享 HTTP client，继续固定经美国 HY2 下载，避免启动时
  依赖尚未完成探测的自动组，同时消除 `download_detour` 弃用提示。
  参见 [规则集 HTTP client](https://sing-box.sagernet.org/configuration/rule-set/#http_client)。

保留两台服务器各自的地址、端口、SNI、REALITY 参数、认证信息、HY2 带宽值
以及客户端 TUN stack / MTU，不引入额外监听、API 或后台核心。

本机 macOS 的 `kern.ipc.maxsockbuf` 为 8388608，`net.inet.udp.recvspace`
为 786896。前者是系统上限，后者是默认接收缓冲区，不等于运行中 QUIC
socket 的实际大小；不能据此直接断言存在瓶颈。没有调整 macOS sysctl，
也没有将 Linux 服务器参数套用到 Mac。

## 初步测试与客户端验收

本次调整前，同一 Cloudflare HTTPS 地址顺序下载 5,000,000 字节：

| 节点 | 总耗时 |
| --- | --- |
| 新加坡 HY2 | 2.196 秒 |
| 美国 HY2 | 1.446 秒 |

此前同日测试新加坡 VLESS 为 4.232 秒。以上是短请求样本，包含连接与 TLS
握手，测试时刻不同，也不是最大带宽或长期平均速度。URLTest 测的是 HTTP
请求延迟，不能据此断言下载吞吐量更高。

客户端已由用户 rebuild 并导入。已核对 SFM 出现新的 emoji 组名、四个节点
均有 URLTest 延迟，mixed 代理请求返回 HTTP 204。缓存与自动选路调整没有
改变线路、服务器算力或带宽额度，不承诺固定百分比的提速。

## 服务端调整前后对照测速

2026-10-16，Asia/Shanghai：调整前 13:46:55-13:49:33；调整后 13:50:36-13:53:27。

每个节点每阶段串行下载同一个 Cloudflare HTTPS 地址的 10,000,000 字节
三次，轮换节点测试顺序，并在每次下载前另外请求 Google 204 测量请求耗时。
单次下载 45 秒超时；吞吐量计入新连接、TLS 握手与完整下载时间。
每个请求使用独立的 sing-box 单次 fetch，绑定物理接口，没有切换 SFM 选路。
这里不是纯 TCP RTT、常驻连接峰值带宽或上传测试。

| 节点 | 调整前下载中位数 Mbps | 调整后下载中位数 Mbps | 完成次数：前 / 后 |
| --- | ---: | ---: | --- |
| 🇸🇬 sg-vless | 5.56 | 11.03 | 3/3 / 2/3 |
| 🇸🇬 sg-hy2 | 23.06 | 22.63 | 3/3 / 3/3 |
| 🇺🇸 us-vless | 9.82 | 2.76 | 2/3 / 3/3 |
| 🇺🇸 us-hy2 | 28.03 | 26.68 | 3/3 / 3/3 |

下载中位数只计算完成的请求，不能忽略超时再把这个数字当作稳定带宽。
美国 VLESS 调整前有一次超时，新加坡 VLESS 调整后有一次超时。
整个对照测试期间，两台服务器的 UDP `RcvbufErrors`、`SndbufErrors` 和
`InErrors` 增量均为 0。美国的累计 `RcvbufErrors` 保持 1491，不能用于证明
本次测试仍存在 UDP 缓冲区丢包。复核服务进程、配置校验值、HY2 监听 socket
缓冲区均未变化，SFM mixed 代理请求返回 HTTP 204。

| 节点 | 前三次下载 Mbps | 后三次下载 Mbps |
| --- | --- | --- |
| 🇸🇬 sg-vless | 5.562 / 14.81 / 5.212 | 11.945 / 45s 超时 / 10.111 |
| 🇸🇬 sg-hy2 | 32.239 / 23.062 / 19.524 | 22.626 / 24.51 / 22.225 |
| 🇺🇸 us-vless | 45s 超时 / 2.328 / 17.305 | 11.856 / 2.756 / 2.032 |
| 🇺🇸 us-hy2 | 16.809 / 34.773 / 28.031 | 24.204 / 26.68 / 27.011 |

| 节点 | 204 请求耗时中位数：前 ms | 后 ms |
| --- | ---: | ---: |
| 🇸🇬 sg-vless | 1734.3 | 1719.4 |
| 🇸🇬 sg-hy2 | 1242.8 | 1399.6 |
| 🇺🇸 us-vless | 1926.9 | 1913.1 |
| 🇺🇸 us-hy2 | 864.5 | 901.0 |

本次没有证实吞吐量提升。美国 HY2 的中位数从 28.03 变为 26.68 Mbps，
其波动范围在调整前就覆盖了调整后的结果。没有修改的新加坡也出现速度变化
和一次 VLESS 超时，因此不能把这些前后差异都归因于美国的系统参数。

美国 VLESS 的一次运行时 TCP 样本显示：RTT 约 144 ms，累计发送约 2.63 MB，
其中重传字节约 236 KB。它支持进一步关注 TCP 传输质量，但不是准确的链路
丢包率，也不能证明具体是运营商、网络过滤或服务器哪一侧造成。

结论：保留官方建议的通用系统上限；实际 HY2 socket 原本已足够大，
没有为没有证据的性能收益重启服务、替换核心或改动地区专属配置。
