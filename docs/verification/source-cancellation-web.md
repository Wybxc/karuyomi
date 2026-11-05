# 正式 Web Source 图片获取中退出与恢复

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，Codex 内置浏览器通过正式 Flutter 主入口，在官方 Arknights Comics 1.6.2 的图片获取中返回详情，再正常继续阅读。修正测试传输后的 `run-MUmONL` gate 3 **通过该固定 Source、大 PNG 流暂停阶段的主动取消与恢复分项**：真实 HTTPS 响应尚未收完，浏览器断开经适配器 TCP reset 后约 12 ms 记录到 HTTPS aborted/close，距原 Source 约 10 秒期限尚有约 8 秒；同一 Worker 恢复首图和原取消页，最终取得完整遥测检查点与正常关停。旧轮等待超时、已收完小图及中间 popular 400 的失败保留在下文。

所有原报告的 `passed=false`、`productUiPassed=false` 原样保留：夹具没有自动赋予通过状态的逻辑，本分项结论来自关联事件、实际 UI 和最终检查点。`productionAccessVerified=false` 不变，不推广为生产 Access、Native、所有取消阶段或完整 P0 验收。

## 固定输入与观察范围

客户端固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6`，使用 reconnect-reader-validation worktree 中既有的 `apps/reader/build/web`，没有重建。host 输入来自固定 `b4f72f70804f12caef21bb51a17cb5adad6982d4`。各轮的正式 host、原 Worker、原 AOT、清单和共享材料均相同；未修改官方 Source 或原始 JAR。

| 输入             | 标识或 SHA-256                                                     |
| ---------------- | ------------------------------------------------------------------ |
| `main.dart.js`   | `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa` |
| 正式 `host.js`   | `dcb101ab53b5359fb7c1ad32e622b0f3db119a9b5b0a2b0aea75e495d219a598` |
| 原 `worker.js`   | `6a4774a2fd97464c0a986258ff8f89a3c064f494a33d34a25a5e903762145e3f` |
| manifest         | `6acb58ad69f33cf912bbf5535d27546ae8ceb5dc5ffd977e73acc337a337d13e` |
| materialVersion  | `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d` |
| buildId          | `ext-en.arknightscomics-ef114e43af44b3bda11182fc16202bb5`          |
| canonical bundle | `8969cab4db08462d60284f193a3680e0704b41303eb81c9deb7dea761fdfc98c` |
| gzip bundle      | `901f9d49a6b76ff0b8e292d9babf026013d598e041d8d07446315124e4fb0cb1` |

清单为 host ABI v3 / protocolVersion 2 / bridgeVersion 2，Source ID 为 `5973713386239249589`。五项 JS 桥和一项 WASM 均按清单摘要作为静态材料提供，未按扩展重复构建。夹具使用固定 Node 24.15.0、Codex 内置 Chromium 156、loopback origin、隔离 D1、受控 RS256 身份和两个显式域名政策：`arknights.global` 与 `webusstatic.yo-star.com`。各轮 principal 均为 `product-cancel-ark-owner`，namespace 为 `d04d5ffd64d80eddd66ab92112686e7c3d4b3477aa10cda592143a49456d7c07`。

产品 HTML 前置透传观察脚本，正式 Worker 后附控制信封、Java 终态和 HTTP 回调观察器；Blob 创建/撤销保留原返回值。观察器与独立控制页均不额外调用 Source，也不请求原图绕过 Source。网络 gate 在实际 HTTPS 响应转发 8192 B 后暂停一块正文；正常 TLS、Source 请求和图片处理链保持不变。45 秒自动放行或人工 release 仅用于清理，不能算作取消成功。以下时间均为报告中的服务端 UTC 记录，异步事件到达次序不等于所有调用的精确本地耗时。

## 旧轮 8932：提前 UI 取消成立，小图不证明上游半途取消

`run-7MZxdU` 的 gate 1 操作过迟，Source 10 秒超时先到；gate 2 混有超时和随后 UI 取消。只有 gate 3 用于提前 UI 取消分项：HTTP 请求 `e470c1d3-49c3-462f-ab4d-67ba100aa3f5` 对应图片请求 `reader-3-1-1`、generation `db724ec0-a078-490a-bb01-af0334bafeb4`。

该 HTTP 请求在 `00:55:32.529` 开始，`34.472` 暂停；`36.111` 浏览器 API 连接断开，`36.115` 正式 `cancelImage` 开始，`36.122` API adapter 取消处理完成。`36.190` HTTP read 返回 `AbortError`，`36.214` Java 返回 `InterruptedIOException`，观察到 `pendingReads=0`、`observedJavaHandles=0`。随后 acquire 返回 cancelled、cancel ACK 为 `{released:true}`，`36.347` 章节会话返回 `{closed:true}`。排队的下一页一并取消，没有为被取消请求发布图片 Blob，也未触发 1 秒强制回收。

但 workerd outbound 直到 `00:55:42.554` 才关闭，接近原 Source 10 秒期限。所选首 JPEG 仅 39602 B：held 时 `upstreamComplete=false`，真正关闭时已经 `upstreamComplete=true`。此时的 aborted/destroy/close 只证明停止下游消费，不能证明真实上游半途取消或及时停止下载。

正常“继续阅读”重开同一 DREAM 章，首图首次可见，UI 显示 `1 / 51` 和本地进度已保存；同一 Worker/generation 继续工作。最终正常退出阅读器、返回浏览并重新连接，事件 252 记录旧 Worker 终止。最终事件 1–258 连续，检查点 `sequence=acknowledgedSequence=258`、队列条目/字节均为 0、`persistenceFailure=null`，并有 Blob revoke 与章节关闭确认。

这轮服务由 Ctrl-C 退出 130，报告 `stoppedAt=null`，未取得正常 dispose ACK。后续进程与监听检查确认 PID 6938 及所属 workerd 已退出、8932 无监听；不能从退出码 130 推导异步清理和最终落盘成功。

## 旧轮 8933：直连适配器已关闭，上游仍等 Source 期限

`run-KI7HzW` 将 Node→API 换为 Miniflare 的 `unsafeDirectSockets` / `unsafeGetDirectURL()`，bootstrap 也走该直连路径，不走 `dispatchFetch` core 入口。Host、Origin、APP_ORIGIN 保持 `http://127.0.0.1:8933`，客户端断开时销毁 Node request、response 与上传流，并记录真实 close。outbound 仍由 Miniflare Node handler 接到 HTTPS 上游。该适配调整没有使本轮及时上游取消通过。

gate 1 的 HTTP 从 `01:16:33.273` 开始，`43.277` 才断开，Java 为 `SocketTimeoutException`，UI 动作与 10 秒期限竞态，不能计为提前 UI 取消。gate 2 才取得干净的提前 UI 取消，目标为 p1 的 `iqpgb75S.png`：

- 图片请求：`reader-2-1-2`；HTTP 请求：`0123166d-656b-450d-ba48-14b0dac13bf0`。
- 章节会话：`71bd2308-74ab-4c6f-8414-0d8da6e2d350`；generation：`04dcae35-115a-425a-9654-4ae744a8c299`。
- Worker：`2e0ce0ed-de91-4cbf-9c8c-614c56603237`；workerInstanceId：`27ec7731-f56f-48f3-a06b-541604b62ddc`。

| 时间（UTC）               | 实际观察                                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `01:17:36.210`            | HTTP 开始，Node 直连 request 打开。                                                                                      |
| `01:17:36.557`            | gate held：已读 18383 B、转发 8192 B、暂扣 10191 B；真实 HTTPS `complete=false`、`readableEnded=false`。                 |
| `01:17:38.676`            | 浏览器 API 连接断开。                                                                                                    |
| `01:17:38.683` / `38.690` | 直连 response / request 的真实 close；adapter 取消处理完成于 `38.690`。                                                  |
| `01:17:38.690`            | 正式 `cancelImage` 开始。                                                                                                |
| `01:17:38.871–38.896`     | HTTP read 返回 `AbortError`、HTTP close，Java 返回 `InterruptedIOException`；观察的 pendingReads / Java handles 均为 0。 |
| `01:17:38.911–38.973`     | acquire 返回 cancelled；cancel ACK 为 `{released:true}`；章节会话关闭 ACK 为 `{closed:true}`。                           |
| `01:17:46.218–46.220`     | workerd outbound 关闭，HTTPS destroy/aborted/close；`complete=false`、`readableEnded=false`，没有正常 EOF。              |

已经交付的 p0 由正式 release 撤销 Blob，排队 p2 取消，被取消 p1 没有发布 Blob。提前 UI 取消约在 HTTP 开始后 2.5 秒发生；真实上游关闭仍接近 HTTP 开始后 10 秒，相隔约 7.5 秒。**未完成响应最终被中断成立，及时传播上游取消未通过**。这些现象尚不足以将责任归于具体生产层或 Miniflare 机制，需另行受控定位。

当次暂停请求的 HTTP `Content-Length` 为 862662；后续同 path 正常获取与产品处理得到的 PNG 正文为 1182305 B。二者属于不同请求/表示的记录，不把准备材料中曾观察的 1182305 B 当作当次暂停响应的 Content-Length。

## 8932 / 8933 恢复、最终退出与服务清理的证据边界

新轮正常重开 DREAM 时使用同一 Worker/generation，首图首次可见。继续翻到第 2/3 页后，原被取消 p1 与相邻页正常显示，截图/AX 记录 `2 / 51`、本地进度已保存、最远第 3 页。恢复通过正式 UI 触发原 Source，没有额外调用 Source 补取结果。恢复证据为 `recovered.png` / `.ax.txt` 和 `recovered-cancelled-page.png` / `.ax.txt`，取消时 UI 为 `held-attempt2.ax.txt`。

最终正常返回详情与浏览前，恢复会话 `f6459b74-b975-48ec-99a9-8dcf08a33951` 的五张 Blob 在 `01:24:02.74–02.81` 全部撤销，观察到 `liveImageUrls=0`；`01:24:02.826` 取得 `closePageSession` ACK，是最后一个 browser event（sequence 238）。随后重连前 Codex 内置浏览器自动审批检查超时，原标签 86/87 失效，浏览器 inventory 为空。**未取得最终遥测检查点或显式 Worker terminate**；标签消失不能替代受观测的正常重连。报告 `observerHealth=[]`、`summary.checkpoints=[]`，不能称为 238/238 已确认或完整生命周期通过。

后续通过新的控制标签 88 点击正常 shutdown，取得 `{disposed:true,persisted:true}` ACK：`02:08:08.200` 开始，`08.248` 完成 Miniflare dispose，`08.251` 发送完 ACK，`08.252` 关闭服务并记录 `shutdown.phase=completed`、`stoppedAt`，剩余 API 请求为 0、错误为空，终端退出 0。进程/端口复核确认 PID 33174 消失、8933 释放。两轮清理均保留 AOT 发布进程 PID 19928、63388 及其任务，不修改构建输入、checkpoint 或 state。

两轮 `fixtureErrors` 均为空。旧轮有最终 browser checkpoint 和 Worker terminate，缺少正常服务 dispose ACK；新轮有正常服务 dispose ACK，缺少最终 browser checkpoint 和 Worker terminate。这些证据互不替代。Blob URL 与 Java handle 观察不等于 manager 私有字节/像素账本、transport 私有 session 表或浏览器/GPU 进程内存，未据此验收资源峰值归零、生产 Access、Native、所有 Source 或完整 P0。

## 独立机制比较：本地 close 不能替代远端取消

随后在固定 Node 24.15.0 / workerd `1.20261101.1` 上做最小 loopback HTTP 比较：origin 先发送 1024 B，再完全停止写入；请求期限为 30000 ms，取消观察窗口为 1000 ms。主 Worker 使用用户直连 socket，出站经显式辅助 Worker 和原生 external HTTP PROXY binding；辅助 Worker 明确启用 `enable_request_signal` 与 `request_signal_passthrough`。每次取消前确认 origin 尚未关闭，观察快照在该轮后续 cleanup 之前取得，窗口内未用 release 或 dispose 触发关闭。

| 客户端动作                                           | 1000 ms 内主 Worker abort / response cancel | 1000 ms 内 origin 提前关闭 |
| ---------------------------------------------------- | ------------------------------------------- | -------------------------- |
| request / response `destroy()`                       | 均未观察到；本地 socket 已记录 close        | 未观察到                   |
| `socket.end()`                                       | 均未观察到                                  | 未观察到                   |
| `socket.resetAndDestroy()` 后销毁 request / response | 均在约 1 ms 后观察到                        | 约 3 ms 后观察到，无 EOF   |

这组结果证明该测试传输上显式 TCP reset 与普通本地销毁的效果不同，不能把 adapter 的 `close` 直接当成 workerd 或真实上游收到取消。结果不证明所有 `destroy()` 都不发送关闭信号，也不直接定位前两轮所有延迟的原因。它是受控 HTTP 机制证据，不是正式 Source 图片、浏览器到生产边缘的 HTTP/2 / HTTP/3 或生产 Access 验收。最终报告确认 Miniflare、origin 和自有客户端 socket 已清理。

## 8934 前两次尝试：入口读取、popular 400

`run-xA4VNW` 的产品、AOT 与共享材料继续使用上表固定输入；夹具 preparation 摘要变为 `f1f101f7e7e4ac4eaa080f136b40655e40021a2aea76b8dbc388e728a64e566e`。Node→API 直连适配器在取消时先对该请求独有的 socket 调用 `resetAndDestroy()`，再销毁流；出站改为上节的显式辅助 Worker、两个 signal flag 与独立 native PROXY gateServer，取代隐式 Miniflare Node outbound wrapper。gate 仍只调节原响应时序，不手动调用 gate 取消来伪造产品传播。

本次只启动服务并打开产品入口，报告有 6 个 browser event、0 个 Source 网络请求，未 arm 图片、未进入阅读取消或恢复流程；milestones 和最终遥测检查点均为空，`passed=false` / `productUiPassed=false` 保持原值。该次运行没有提供真实 Source 及时取消证据，前两轮失败仍有效。

清理测试进程时调用夹具正常 shutdown 入口并收到 `{disposed:true,persisted:true}` ACK：`02:18:11.203` 开始，`11.207` 关闭 gateServer，`11.222` 完成 Miniflare dispose，`11.223` 刷完 ACK、关闭主服务并记录 `phase=completed` / `stoppedAt`；剩余 API 请求为 0，错误为空，终端退出 0。随后确认 PID 61169、workerd 61624 已消失，8934 及该轮随机端口释放，AOT 两条构建及动态子树保留。正常关停只补充夹具清理证据，不补作缺失的 Source、图片或浏览器生命周期验收。

第二次 `run-9rzZD1` 使用同一 preparation，经正式 UI 初始化原 Source 并调用 `popular`。HTTP 请求 `46c8d05d-bf57-4cee-8b61-d9ce918c99ef`、generation `ef073873-f466-4e76-ae50-4d4c9c2d2dba` 对应 `https://arknights.global/api/resource/comic/list`，bridge 外层为 200，帧内上游状态为 400，166 B 正文读至 END。原 Java 返回 `eu.kanade.tachiyomi.network.HttpException: HTTP error 400`，未打开漫画或章节，未 arm 图片，未进入取消门；`passed=false` / `productUiPassed=false`、milestones 为空保持原值。

这次正常重连记录到 `02:24:02.215` 的旧 Worker terminate（sequence 29），最终检查点 sequence / acknowledgedSequence 均为 35，队列条目/字节为 0、`persistenceFailure=null`、`liveImageUrls=0`。`02:24:09.808` 请求正常 shutdown，`09.811` 关闭 gateServer，`09.827` 完成 Miniflare dispose，`09.828` 刷完 ACK，`09.829` 完成服务关闭并落盘；剩余 API 请求为 0、错误为空。PID 68957 终端退出 0。这些是未进入阅读流程时的生命周期与夹具清理证据，不能代替图片退出/恢复验收。

## native PROXY 缺失 Host 的夹具修复与受控回归

第二次 8934 记录的 HTTPS 出站 header 名称没有 `host`。native PROXY 的 absolute-form 请求可以省略 Host；旧夹具把接收到的 raw header 数组直接交给 Node HTTPS client，而固定 Node 在数组分支不会自动补 Host。该行为可由 [Node 24.15.0 官方源码](https://github.com/nodejs/node/blob/v24.15.0/lib/_http_client.js#L349)核对，独立本地 HTTPS 负向对照也复现 400，且请求未到达 origin handler。这说明夹具的 Host 构造存在缺陷；尚不把它当成已修复真实外网 Source 的证据。

后续仅修改 ignored 夹具：在已登记的原 HTTPS 目标与 PROXY 请求精确匹配后，只在缺失 Host 时补入原目标 authority；已有 Host、重复头、method、pathname、query 与正文保留。未改原 Source、JAR、AOT 或正式产品 HTTP bridge，TLS 的证书链及主机名校验继续启用。新的 preparation 摘要为 `f0f5e7ccc4cb0cae8ff74d73cee58615030a7ebf14d579e34fc420f458af19f6`；下节真实 UI 复验使用这份准备输入。

`.local/source-cancel-be5/upstream-regression-result.json` 记录固定 Node 24.15.0 下 8 项回归均通过：

| 回归范围                                    | 实际证据                                                                                                              |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| raw 数组缺 Host 的负向对照                  | 400，origin handler 未到达。                                                                                          |
| 缺 Host / 已有 Host 两种 absolute-form 转发 | 仅补缺失 authority，已有 Host 不覆盖；重复头、query、26 B POST 正文和 40000 B 响应保留。                              |
| 未完成 HTTPS held 后取消、迟到 release      | 转发 8192 B 时 `complete=false`；取消约 4 ms 后真实 origin 提前关闭，未完成发送，迟到 release 不改变 cancelled 终态。 |
| 已收完小响应的负向对照                      | held 时 `complete=true`，不计远端半途取消。                                                                           |
| 正常 release / hold timeout                 | 两种路径均保留 40000 B 原正文；timeout 放行不计取消成功。                                                             |
| 未登记 URL                                  | 拒绝转发，HTTPS origin 请求数不增加。                                                                                 |

该回归只覆盖 Node HTTP 下游、夹具 gate 与受信本地 HTTPS 上游，没有 workerd、Flutter、真实 Source 或生产 Access。临时 CA 通过 `NODE_EXTRA_CA_CERTS` 加入信任，未禁用 TLS 校验。最终确认 proxy / origin 已关闭、active handles 为 0；这些机制结果不提升真实 Source 图片取消门的验收状态。

## 8934 修复后：真实大图主动取消、恢复与最终清理

`run-MUmONL` 经正常产品 UI 重新通过 popular、详情及 DREAM 51 页列表。gate 1 等待后未及时返回；gate 2 的 CUA 脚本因未声明变量中断，下一次工具调用才返回。两次 API 断开均在请求开始约 10 秒处，不能计主动 UI 取消。gate 3 在单次工具调用内完成 arm、开章、确认 held 和正式 Reader 返回，才用于本次主动取消结论。

gate 3 关联 HTTP 请求 `43bd42b5-1f10-4a6f-a8cc-8a000e494bf3`、图片请求 `reader-3-1-2`、generation `2c702b3a-b3e3-4d79-b21e-904ca6698ca1`、章节会话 `e5c1fab6-5018-40fd-80cf-aad73ccaa7b6`；目标仍为原 Source 的 p1 `iqpgb75S.png`，当次 Content-Length 为 1182305 B。

| 时间（UTC）           | 实际观察                                                                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `02:34:44.412`        | 浏览器 API 请求开始，随后直连用户 Worker 和真实 HTTPS。                                                                                                |
| `02:34:45.083`        | gate held：读 15368 B、转发 8192 B、暂扣 7176 B，HTTPS `complete=false` / `readableEnded=false`。                                                      |
| `02:34:46.472`        | 正式 Reader 返回导致浏览器连接断开，adapter 对该 socket 请求 TCP reset。                                                                               |
| `02:34:46.482–46.487` | workerd response 提前 close；真实 HTTPS aborted / response close 在 `46.484`，request close 在 `46.487`；均未 complete / readableEnded，没有正常 EOF。 |
| `02:34:46.687–46.714` | HTTP read `AbortError`、HTTP close 与 Java `InterruptedIOException`；`pendingReads=0`、`observedJavaHandles=0`。                                       |
| `02:34:46.776–46.851` | 当前 acquire 返回 cancelled、cancel ACK `{released:true}`，随后章节会话 ACK `{closed:true}`。                                                          |

真实 HTTPS response 在浏览器断开后约 12 ms 关闭，距 API 开始约 2.07 秒，早于原 Source 约 10 秒期限约 8 秒；该请求期间没有 gate release、45 秒自动放行或服务 shutdown。被取消 p1 没有发布图片 Blob，排队 p2 也取消；已交付 p0 正常 release / revoke。Java 合作退出后在同一 Worker / generation 正常重开 DREAM，没有用强制 Worker 回收替代本次取消。

恢复后的首图和原 p1 / p2 实际可见，截图 `recovered-first.png` 与 `recovered-cancelled-page.png` 及对应 AX 分别记录 `1 / 51`、`2 / 51`、本地进度已保存和最远第 3 页。恢复会话为 `b28912a8-0f7b-4341-b08e-388a94feb19f`。最终正常退出时，五张 Blob 均 revoke 至 0，五项 release ACK 完成，`02:36:19.475` 取得 session close ACK；返回浏览并重新连接后，`02:36:37.936` 记录旧 Worker terminate（sequence 302）。事件 1–308 连续，最终 checkpoint 为 308 / 308，队列条目/字节为 0、`persistenceFailure=null`、错误为空。

最后通过控制 UI 正常 shutdown：`02:37:03.385` 开始，`03.394` 关闭 gateServer，`03.408` 完成 Miniflare dispose，`03.411` 刷完 ACK、关闭主服务并记录 `phase=completed` / `stoppedAt`，剩余 API 请求为 0；终端退出 0。PID 84499、所属 workerd 与 8934 监听均已清理，AOT PID 19928 / 63388 及动态子树保留。该轮补齐本节限定的取消、恢复与最终清理分项；私有预算账本、进程/GPU 峰值、生产 Access、Native 和其它 Source / 取消阶段仍不在证明范围内。

## 证据与复验

ignored 材料在正式 main 的 `.local/source-cancel-be5/`。8932 / 8933 的两次阅读 UI 旧轮保留 `fixture-source/README.md`、冻结源码、`preparation.json`、静态清单、原报告及截图/AX；8934 的 `run-xA4VNW` / `run-9rzZD1` / `run-MUmONL` 也各冻结 16 个夹具文件到 `fixture-source/`，其中 preparation 摘要均与各自报告一致，不依赖后来重建的根目录准备记录。独立 socket 比较的源码与报告在 `.local/idle-cancel-socket-probe/`。详细机器输出不入库。

| 证据                                         | SHA-256                                                            |
| -------------------------------------------- | ------------------------------------------------------------------ |
| `run-7MZxdU/result.json`                     | `76c49c2210d82e6749aa4541a53021e16124c699466d5f41f879c0428d8f7a5c` |
| `run-7MZxdU/fixture-source/preparation.json` | `a9d1abc555e1eb2be64b553ce21d0f4d5e4ba8ef7d7a47f36b674e198b5d8f5e` |
| `run-KI7HzW/result.json`                     | `0b7d6c68a07a571f8ca557ebbf7dd5d386f57bde992708c63714ceff49f2a8f2` |
| `run-KI7HzW/fixture-source/preparation.json` | `b355e1852b0ab06e4c9ec5be903c2a9e7cec6f58342dcc55950b5224ca463d17` |
| `run-xA4VNW/result.json`                     | `6c7d6cebb86517bdb9015ac6976e2e0473cceb783a142ea541bb7a4bb89f5632` |
| `run-xA4VNW/fixture-source/preparation.json` | `f1f101f7e7e4ac4eaa080f136b40655e40021a2aea76b8dbc388e728a64e566e` |
| `run-9rzZD1/result.json`                     | `f08fb622931e83087ab4d00b2e8a4d1420040fc99042920bb704aafa4ceeaae1` |
| `run-9rzZD1/fixture-source/preparation.json` | `f1f101f7e7e4ac4eaa080f136b40655e40021a2aea76b8dbc388e728a64e566e` |
| `upstream-regression-result.json`            | `708d02cec2357b222569174947799f22b87093583528e61db01bbcb3be6255dc` |
| `run-MUmONL/result.json`                     | `53ab14bd0cda8ef46bce5dac1f4e7a595d9545ff7c7d86b6da60e8bb4f14a5b3` |
| `run-MUmONL/fixture-source/preparation.json` | `f0f5e7ccc4cb0cae8ff74d73cee58615030a7ebf14d579e34fc420f458af19f6` |
| `idle-cancel-socket-probe/result.json`       | `9e4f22936046e02f5d079574c09271f6d74f594eb4af0d98c5177a498aaac9b1` |

复验先按对应冻结 README 核对源码、输入摘要和 Node 版本；在新的独立夹具目录与空闲 loopback 端口工作，保持旧轮源码、报告及固定 Flutter 成品不变。三端严格检查与准备/启动入口为：

```sh
pnpm exec tsc -p <新夹具目录>/tsconfig.server.json
pnpm exec tsc -p <新夹具目录>/tsconfig.client.json
pnpm exec tsc -p <新夹具目录>/tsconfig.worker.json
node <新夹具目录>/prepare.ts
node <新夹具目录>/server.ts
```

按夹具配置设置新的端口、输入与报告目录。先核对控制页固定摘要、bootstrap 和授权，在正常产品 UI 进入 Arknights / `Prelude Suite: The Lone Walker` 详情，控制页 arm 实际 p1 pathname，再打开 DREAM。确认 held 后在 Source 期限前正常返回详情，按图片 requestId、HTTP requestId 与 generation 关联所有层的取消事件；两类 requestId 不能直接混用。必须同时核对 held 与实际关闭时的 `complete/readableEnded`、真实 HTTPS close 和耗时，排除超时与已收完小图。再次通过正常 UI 继续阅读，确认首图及原取消页可见、进度保存，再退出、返回浏览并重新连接。产品标签仍有效时取得最终遥测检查点，要求序号相等、队列为零、持久化失败为空，并单独核对 Worker terminate。最后通过控制页正常 shutdown 等待 ACK，核对报告完成阶段、进程和端口。任何浏览器操作或检查点中断都如实保留为缺口，不用后来服务正常退出补作浏览器层通过。
