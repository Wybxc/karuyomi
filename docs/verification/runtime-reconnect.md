# 重连与迟到控制响应

2026-11-04，正式 Dart 回归先在旧码复现两类问题：Catalog 的旧 bootstrap/index 在容器失效后仍将状态改回 ready；Transport 的旧 API 错误或旧图片清理错误，在新 open 成功后清空新会话或向新 generation 发事件。旧失败日志留在 ignored 目录，不以格式检查代替语义验证。

## 当前实现

- Catalog 显式重连立即撤销当前身份、选择和清单，并先提交绑定原身份的进度。失败草稿仍可重试，不改绑新身份。只有曾尝试加载 runtime 的重连才调用平台的可重开 rebuild；纯目录连接不销毁容器。
- Worker、WebView 与原生图片资源的清理由 PlatformRuntime 拥有；Catalog 通过显式依赖调用 rebuild，不调用永久 dispose。主动重建中的旧容器 runtimeLost 不自我取消当前重连，重建失败仍报告并允许下次重试。
- bootstrap、index、manifest 和 open 每次 await 后均核对 epoch，失效的结果不发布。传输层在请求前捕获 epoch；旧成功或异常不能向新会话发事件、清空新 session 或发布旧 API 结果。
- 有效的迟到图片仍交还原 acquireImage 所有者执行释放；旧 generation 清理失败保留原错误，不能破坏新 slot。dispose ACK 和正常控制交互保持有效，不自动重发任何副作用请求。

## 已运行的验证

旧码 Catalog 4 项、Transport 3 项回归明确失败。修后 source_runtime 完整 29 项及 Dart 分析通过；Reader 六个受影响测试文件 46 项与 Flutter 分析通过，包含身份更换前的旧进度保存、保存失败草稿、迟到 manifest、无已加载 runtime 时不重建、重建失败恢复及迟到图片所有权。正式入口为 `packages/source_runtime/test/transport_test.dart`、`apps/reader/test/browse/catalog_controller_test.dart` 与 `apps/reader/test/reader/reading_progress_controller_test.dart`。

上述结果是正式组件/传输与本地 SQLite 回归。随后正式 Web 主入口的 A→B→A 身份切换通过下述独立产品门；Native 身份切换、版本更新和生产 Access 过期恢复仍须另验，不能用模拟 transport 替代。分项产品验收继续按[P0](../plan/p0-runtime-and-reading.md)推进。

## Native 启动确认超时

2026-11-08，正式 Dart 运行容器的旧启动路径虽然设有 20 秒期限，超时后却在清理中继续等待 WebView 插件的 `run()` 确认，可能使启动、显式重建或关闭一直不返回。锁定的 iOS/Android 插件在确认前尚未把 WebView 标记为运行，提前调用 `dispose()` 不会释放该实例。

现在超时或关闭立即摘除旧代并结束前台等待，保留一个清理责任，直到迟到成功后调用一次 `dispose()`，或迟到失败结束等待；旧回调不能复活原代。清理期间显式重连立即报告暂时不能重连；一直未获确认或清理失败时可重启应用。等待期间不会继续创建新的 WebView。

`cd apps/reader && flutter test test/runtime/native_platform_runtime_test.dart` 的回归覆盖启动超时、迟到成功/失败、明确重连及关闭，使用受控的插件通道回调。它说明旧等待可被截断，不证明既有 Android 初始化故障由此引起；受信 HTTPS 下真实 Android/iOS 主入口重建、系统生命周期和真机仍须独立验收。

## 正式 Web 主入口的 A→B→A

2026-11-04，Codex 内置 Chromium 156 使用正式 Flutter `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 完成身份切换；`main.dart.js` SHA-256 为 `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa`。原 xkcd AOT 仍为 `b4f72f7` 的 `ext-all.xkcd-b33800f6d02ddab83b60b6d7ac85b49d`，JAR、清单、材料均未改，完整输入身份见[Source 网络 Cache](source-network-cache.md)。

全新同源 `http://127.0.0.1:8928` 提供正式产品与独立 A/B 控制页。两个隔离 workerd 各自固定匹配的 `ACCESS_SUBJECT`，通过真实产品 `jwtVerify` 校验局部 RS256 身份；启动实测匹配 A/A、B/B 为 200，交叉 A/B、B/A 为 403。操作者在正式 Catalog、Source、章节和重新连接 UI 完成操作，观察器不直接创建 manager 或调用 Source。

- A 读取原 `3318: Earth Sized Planets` 的首图和 TextInterceptor 文字第 2 页，保存第 2 页并退出。
- B 重连后没有 A 的继续阅读；正常读取同章第 1 页原图，退出后详情出现自己的继续阅读。
- 返回 A 后继续阅读首次恢复第 2 页，原文字图片真实可见；恢复过渡和随后稳定保存的截图分别保留。

独立报告确认三个不同 Worker、generation、workerInstanceId，真实 namespace 为 A/B/A。原 `/3318/` 按 requestId 关联的三轮均为 2 页，PageList SHA-256 同为 `cf4df2da1b455de6533e8a3563e764ef414857c49b3f574f27b702bed0665bd4`；额外打开的 3317 分开计数。A/B 各自 miss 1、commit 1，写入 7187 B；返回 A 实际 entry 1、miss 0、4 次读取共 7187 B、EOF 1、reader-close 1、正文写入 0。此时原请求带 If-None-Match，上游为 **304 / 0 B**：证明条件再验证后复用旧正文，**不证明零网络**，未调整原 freshness 或请求头。

正常退出和最终返回浏览后重连，三 Worker 均 terminate，实际章节会话关闭数为 2/1/2；第四次 bootstrap 仅用于清理，未创建第四个 Source Worker。最终检查点 `sequence=acknowledgedSequence=113`，事件连续，队列字节/条目均为 0，持久化失败为空；console、夹具及 Cache 观察错误均为 0。主代理随后关闭两临时标签，本地所属 server 已 Ctrl-C 停止且端口无监听；不据此声称图形账本或浏览器内存归零。

首轮 8924 的 UI 成功但 keepalive 遥测触及 [Fetch 64 KiB 合计限额](https://fetch.spec.whatwg.org/#http-network-or-cache-fetch)，返 A 观察不完整；原报告、console、截图均保留在固定 b4 树 `.local/network-cache-source/product-identity/first-round/`，不将该轮记为完整 Cache 门。新 8928 仅修 ignored 观测器：普通 fetch、消费响应正文、单请求有界队列，切换前确认快照与队列排空。

第二轮完整输入、启动命令与证据保留在该树 `.local/network-cache-source/product-identity-8928/`，归档位于 `evidence/`：

| 文件                                                    | SHA-256                                                            |
| ------------------------------------------------------- | ------------------------------------------------------------------ |
| `report-product-identity-observed.json`                 | `69f8bc8f7ee0170c776cf97c5b2498012cbad21dda4bff184ad8687a7c1a1973` |
| `evidence-sha256.json`（UI、console、六张截图逐项摘要） | `33990b94975ec5d1d0aa756afbb35988645c6ba4ca7454fbf2f0e82be74e0055` |
| `acceptance-human-and-observation.json`                 | `5c1d5965aa2f6ea029d2385fc2d1ad7dcf455bcde40d7c79b04b56ed1a787a86` |

原报告的 `passed=false` 保持不变；人工 UI 与独立数据核对另存 acceptance summary，不冒充自动 UI 测试。复验先对夹具三份 `tsconfig.{server,client,worker}.json` 运行 `pnpm exec tsc -p`，再按 `start-command.txt` 使用 Node 24、冻结 Flutter 目录及新 loopback origin 启动。临时 runner、D1、JSON 和截图不入源码库。

本门证明正式 Web 主入口的身份/进度隔离与恢复、同一原 Java Source 的条件 Cache 正文复用；不证明生产 Access 登录/过期/登出、Native 身份切换、浏览器或 App 进程重启、真实版本更新、其它 Source 兼容性或设备内存峰值。Cache 桥观察也不是精确 Java Cache counter。
