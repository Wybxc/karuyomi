# 正式 Web 扩展版本更新与续读

2026-11-04，Codex 内置浏览器通过正式 Flutter 主入口完成官方 Arknights Comics **1.6.1 → 1.6.2** 更新、继续阅读与正常退出。客户端固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6`，`main.dart.js` SHA-256 为 `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa`。这是单浏览器文档、loopback origin 与受控 RS256 身份下的产品分项，未验生产 Access、Native 或浏览器进程重启。本轮临时 HTTP 夹具由系统 Node 26.5.0 启动；仓库检查恢复使用固定 Node 24.15.0，后续复验也应使用固定版本，不把该夹具环境记为 Node 24。

## 输入与实际操作

两版均从官方固定提交的原始 JAR 构建，未修改扩展业务代码；同一 hostFingerprint `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db`、共享材料 `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`、host ABI v3 / protocolVersion 2 / bridgeVersion 2。Source ID 均为 `5973713386239249589`。

| 版本  | 官方上游提交                               | buildId                                                   |
| ----- | ------------------------------------------ | --------------------------------------------------------- |
| 1.6.1 | `1dfd0bcf25b48cb5bd42d9191918a29072c67a61` | `ext-en.arknightscomics-9084a1447a6ffe60eb7337628dd7a5eb` |
| 1.6.2 | `efa93f5a3537856fe830450bbe33f69d21d28167` | `ext-en.arknightscomics-ef114e43af44b3bda11182fc16202bb5` |

操作者在正常浏览入口选择 1.6.1、Arknights Comics 与 `Prelude Suite: The Lone Walker`，打开 DREAM，切至单页并阅读到第 3 页；截图确认原图可见、`3 / 51`、本地进度已保存及最远第 3 页，随后返回详情和 Source 页。独立控制页只切换静态快照，不调用产品 manager 或 Source；切换前要求观察检查点已确认且队列排空。

在同一产品标签点击“重新连接”后，列表只显示 1.6.2。选择新版 Source、同一漫画，再点击“继续阅读”，首次进入即恢复第 3 页并显示原图，进度已保存。新版使用当前默认双页，第 3 页显示在右侧；本门证明逻辑锚恢复，不证明单页模式设置持久化。两次 PageList 都是 51 页，摘要同为 `40ba769e5bd456ad2455b912ab7f216e59d1883d86940af18700dca0c0e023b6`。

两个隔离 workerd 使用相同 principal `product-version-ark-owner`，并分别仅授权对应静态快照的当前构建。两版的 Worker、workerInstanceId、generation 均不同，namespace 同为 `830f974785247510694fbd258a94c8161be414efd85393174f0001b17682ce33`。旧 Worker 在重新连接时终止；新版正常退出阅读器、返回浏览并重新连接后也终止。两版各有一个章节会话关闭确认。最终事件 1–90 连续，检查点 `sequence=acknowledgedSequence=90`，队列条目/字节均为 0、持久化失败为空，fixture、Cache 观察和控制台错误均为空。

## 静态资源与 Cache 结论

新版索引、清单和 gzip 产物正常获取；切换后旧清单、旧 gzip 的实际请求均为 404。保留了本轮静态目录中的两份单构建索引原始文件，分别对应两次产品加载和 HTTP 请求记录。这证明夹具的当前快照切换，不代表生产部署或旧本地 bundle 缓存已经清理。

新版 Cache 观察为 4 次 entry、0 miss、0 readCalls/readBytes/readEof；四次 commit 共写入 32761 B。全部 18 次实际上游响应均为 200，图片继续通过原 Source 的正常请求链。因此只证明同 namespace 下旧条目可见、新版重新获取并写入正文；**没有证明版本更新后的 Cache 正文复用、304 或零网络**。原 xkcd 的同版正文复用与身份切换后 304 另见[Cache 记录](source-network-cache.md)和[重连记录](runtime-reconnect.md)。

## 证据与复验

正式临时夹具位于 main 的 ignored `.local/version-upgrade-ark-b4/.local/ark-version-upgrade/product-version-8929/`，本轮归档在 `product-ui-policy-fixed/`。原报告保持 `passed=false`，人工 UI 及独立数据审查另存，不改称自动 UI 测试。

| 证据                                                     | SHA-256                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------ |
| `report-final-observed.json`                             | `c153b970dad5a8f844424717966579a1b7ba80adb0ed8178dc014b36c67f314b` |
| `evidence-sha256.json`（截图、AX、静态索引与控制台摘要） | `efe8594043be6a2de770307ae3ef12269c2334d2c3118b0a2b0af8fbc447b17b` |
| `acceptance-human-and-observation.json`                  | `1e9148f650aeda24497a83ace18e09a2c5271f5af55acea7c27b73cf331ad501` |

在固定 clone `.local/version-upgrade-ark-b4/` 下，对 `.local/ark-version-upgrade/product-version-8929/tsconfig.{server,client,worker}.json` 分别运行 `pnpm exec tsc -p`。再以新的 loopback 端口运行 `SOURCE_PROBE_PORT=<端口> SOURCE_PROBE_READER_DIR=<冻结的 be5 Flutter build/web 绝对目录> SOURCE_PROBE_EVIDENCE=<新轮次 result.json 绝对路径> node .local/ark-version-upgrade/product-version-8929/server.ts`，先核实控制页列出的两个 registeredBuildId 和 bootstrap，再从产品 UI 复验上述步骤。原始输入、两版 JAR/清单摘要与服务源码摘要均在归档中。

更早的浏览器标签丢失轮次和授权夹具失败轮次均保留。后者先注册两版，再复制同一数据库，导致“每包仅保留当前版本”删除旧版授权，旧版目录请求在 bridge 返回 404、未访问上游。最终夹具先独立注册并复制每个版本的 D1，启动时断言每个后端恰好只有对应 buildId；正式 Worker 和官方 Source 未改。最终 UI 通过后，已关闭两个临时标签，停止所属服务并确认端口无监听；不据此宣称浏览器或 GPU 内存峰值通过。
