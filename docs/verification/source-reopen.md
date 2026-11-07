# 独立 Web 文档 Source 重开诊断

2026-11-07，以主线 `bdc54de` 为基线增加默认关闭的运行时诊断，在正式 Flutter Web 与官方 Vite / Wrangler harness 复现新文档重开失败。当前只确认阻塞阶段，尚未找到根因或通过修复复验；不调整超时，不把缓存桥机制测试当作 TeaVM Source 运行证据。

## 输入与可复验入口

客户端使用本轮诊断候选；四包 AOT 仍固定于 `9b98d006dd12d5a62106abde846716d9cd6f7b26`，快照为 `/private/tmp/karuyomi-local-cuutruyen-aot-9b98d006-kNsNNZ/results/snapshot-four`，没有因增加宿主日志重编扩展、改共享材料或提升 `compiled_unverified` / `runtimeReady=false`。四包输入与来源见[跨源搜索复验](cross-source-search.md#2026-11-07含关闭修复的四包-web-复验)。实际只安装并执行 xkcd 英文 Source；作品与章节的精确身份见[书签记录](bookmarks.md#web-a-正式添加与只读-d1-核对)。

`VITE_KARUYOMI_RUNTIME_DIAGNOSTICS` 是 Vite 构建开关，默认关闭，仅值为 `1` 时启用。复验从仓库根目录使用固定工具链与已准备的四包快照：

```sh
VITE_KARUYOMI_RUNTIME_DIAGNOSTICS=1 \
EXTENSION_ASSETS_DIR=/private/tmp/karuyomi-local-cuutruyen-aot-9b98d006-kNsNNZ/results/snapshot-four \
pnpm acceptance:build

ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
pnpm acceptance:serve
```

使用命令打印的实际 URL 和 `acceptance-owner` 测试身份；端口不是固定配置。本轮先完成完整 acceptance 构建，再为日志转发重建 runtime-host、带四包快照的 API 与 acceptance 输出，复用前一步的 Flutter Web 输出。实际构建日志为 `.local/source-stage-build.log`、`.local/source-stage-assets-build.log`、`.local/source-relay-build.log`；这里只记录已执行的构建，不声明尚未运行的新 Java trace 或后续全库检查通过。

诊断由实际加载后的缓存 API 包装与 HTTP 传输阶段产生，经 Worker、当前代 manager 转发到页面 console。只记录白名单操作、阶段、requestId / generation、随机 handle、长度与计数；不输出 Source 请求参数、URL、请求头、Cookie、正文、缓存键或原异常堆栈。转发严格解析并核 generation，日志 sink 失败不改变 Source 调用结果；原控制响应、取消、队列与默认 deadline 保持原合同。

## 正式客户端复现

官方 HTTP harness 为 `http://127.0.0.1:51864`，隔离 D1，subject 为 `acceptance-owner`。主代理独占 Codex 内置浏览器，独立验收代理只用正常身份头执行正式业务 GET；未使用其它浏览器、直接业务写入、Native 或生产 Access。

A 从正式扩展管理安装 xkcd，打开英文 Source，首次热门成功。日志包含网络正文读完 `208440 B`、缓存 commit 完成，热门调用约 2.7 秒结束；随后正式详情 / 3320 章列表成功，收藏 `SINGLE` 并标记 `3319: Elevators`（原章节 URL `/3319/`）。这些成功只适用于 A 已观察的调用。

关闭 A 后，以同 origin 的全新文档 B 从正式书架打开该作品：

| 阶段         | 实际观察                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| 初始化与加载 | host init / load 均 settled，details `ui-1` 也 settled。                                                                       |
| 章节调用     | `ui-2` 的 `chapters` 于 `2026-11-06T23:21:51.940Z` 开始。                                                                      |
| 缓存入口     | 同一 requestId / generation 的 `cache-get` begin 与 resolved 均在上述时间出现，表明该 JavaScript Promise 已返回。              |
| 后续桥调用   | 到回收前未记录 `cache-read` 或 HTTP 阶段，也没有 chapters settled。                                                            |
| 终态         | `2026-11-06T23:22:21.901Z`，`control-1-11` / `ui-2` / `chapters` 返回 timeout，命中默认 30 秒活动调用 deadline 并回收 Worker。 |

该代 generation 为 `a4ee9cad-025b-4b57-9a66-5583ad01a3dc`。本次精确区分了 invoke 30 秒与 startup 60 秒；不能反向改写[较早书签复验](bookmarks.md#2026-11-07真实-web-标记与独立文档读取阻断)中未精确测量的历史结论。

`cache-get` 的日志没有记录返回值，所以不能声称缓存命中；Promise resolved 也不能证明 Java 异步 callback 已恢复、缓存内容已被消费或后续 Java 逻辑已完成。现有证据不将根因归为缓存数据库、网络、书架或 iframe；Java 后续阶段仍待定位。

## 独立 D1 核对与证据范围

独立验收在 `23:21:47.715Z` 保存添加后基准，在 B 确认超时后的 `23:24:31.566Z` 再读取一次。settings、library、manga、bookmarks、progress 与带 exact chapterKey 的 manga 共六路 GET 均为 200，前后完整响应逐字段相同：account revision 为 3、manga revision 为 2、global revision 为 1；唯一目标书签仍为 true。安装、元数据、收藏时间、分类、阅读默认、无 resume 与空进度均未变。

这只证明采样间没有额外已提交业务变化，不声称已捕获客户端全部请求，更不算 B 正式详情或第二端书签读回成功。原始状态快照为 `/private/tmp/karuyomi-source-reopen-diag-51864-{added,after-timeout}.json`；白名单阶段日志为 `/private/tmp/karuyomi-source-relay-{a,b}.json`，没有把 Source 参数或正文加入诊断。较早 50457 快照采样已晚于当次超时，不能作为前后比较，本节只采用 51864 的真实双阶段采样。

官方 Vitest Browser 另有纯缓存桥单项：旧 Worker 写入并停止后，新 Worker 首次读取完整已提交字节，测试通过，用时 215 ms。可复验入口为：

```sh
pnpm test:browser --run -t 'a new Worker reads committed cache bytes on its first operation after the old Worker stops'
```

该测试由官方 Browser preview 提供页面，按仓库要求使用 Codex 内置浏览器打开打印的地址。它没有执行 TeaVM / Java 或真实 xkcd，不能替代上述失败路径，也不能据此排除 Java 缓存适配问题。实际 Source 重开、第二文档书签读回与 Web↔Native 往返仍未通过。51864 验收服务本轮已关闭。

## 隔离 Java trace V1：缓存响应返回后仍超时

为继续定位 Java 侧，在独立目录固定 `9b98d006dd12d5a62106abde846716d9cd6f7b26`，仅应用临时 `trace.patch`；其记录 SHA-256 为 `a3badf8c631ee419a3bf3031abe79eb82497bce0e204ff0bc310b25028ca1d10`。候选构建为 `ext-all.xkcd-bf1e3c3c39982c1403e3a4f1ca0fb07d`，快照位于 `/private/tmp/karuyomi-cache-java-trace-9b98-QsujSS/results/snapshot`。独立核对 `prepared.json`、`summary.json` 与 patch 的阶段位置，复用已记录的产物身份，没有重算 bundle 哈希。原四包快照保持不变；此候选未部署、未写正式增量 checkpoint，仍为 `compiled_unverified` / `runtimeReady=false`。

新的官方 HTTP harness 为 `http://127.0.0.1:54450`，subject 为 `acceptance-owner`。主代理在 Codex 内置浏览器通过正式 UI 安装该精确候选；A 的热门、详情 / 3320 章、收藏和 `/3319/` 书签成功。关闭 A 后，新文档 B 从正式书架打开，章节调用仍于 `2026-11-06T23:37:40.120Z` 命中默认 30 秒超时，没有取得正式详情读回。

独立读取 `/private/tmp/karuyomi-java-cache-trace-b.json`，同一 generation `3f6b8b7d-438d-443e-baa7-24d0323c5418` 的 `chapters / ui-2` 实际经过：

- `23:37:10.132Z`：缓存桥 Promise resolved，Java `cache-callback-before` 后出现 `cache-command-text` 与 Gson 解析后的 `cache-command-return`。
- 随后进入有 `entry` 的分支，依次经过 metadata、headers、vary、body 和 entry tag 构造，未走缓存 miss 分支。
- `23:37:10.136Z`：Response 构造完成，出现 `cache-response`、`cache-return`、`cache-finally`；`23:37:10.137Z` 出现 `cache-callback-after`。
- 此后直到超时没有 `cache-read` 或 HTTP 阶段，也没有章节调用完成。

这些标记与 patch 的实际位置一致：该隔离候选已恢复 Java callback、完成 Gson 解析并构造返回缓存 Response，不能继续把它描述为仍等待 JavaScript cache-get Promise。它尚未读取缓存正文，也不能据此把阻塞定位到具体后续方法或宣称根因已确定。临时 trace 会改变字节码形状，本次没有修复原失败，也不能将候选的细分阶段直接当作原四包的同等证明。

独立六路正式 GET 在 `23:37:03.948Z` 保存添加后基准，超时后于 `23:39:00.051Z` 再读，均为 200 且前后逐字段完全相同：account / manga / global revision 仍为 3 / 2 / 1，exact `/3319/` 书签为 true，其它安装、资料、分类、阅读默认、空进度与无 resume 均未变。原始状态快照为 `/private/tmp/karuyomi-source-reopen-diag-54450-{added,after-timeout}.json`，只证明没有额外已提交业务变化。本节仅记录 V1，后续诊断结果单独验收，不提升 Source 重开或跨端书签门。

## 隔离 Java trace V2：A 经过 strategy，B 未到达

V2 保持同一固定 `9b98d006` 基线，临时 `trace-v2.patch` 增加 handshake / strategy 标记；`prepared-v2.json` 记录 patch SHA-256 为 `2d3448753e961ef68a2e3c197829cc7c6b723de5d318206945387b6a5f99294b`，候选为 `ext-all.xkcd-7c04a1abfd1291a40add4fbc42f27c56`。这仍是改变字节码形状的隔离 marker 候选，没有正式修复、部署或 runtimeReady 提升，原四包不变。

官方 HTTP harness `http://127.0.0.1:55538`、subject `acceptance-owner` 的 A 正式安装该候选，热门、详情、收藏和目标书签成功。独立核对 `/private/tmp/karuyomi-java-cache-trace-v2-{a,b}.json`：A 实际出现 `cache-strategy-track-enter`、`cache-strategy-network`、`cache-strategy-tracked`，各两次；故 strategy 标记并非完全未接线。

关闭 A 后，新文档 B 从书架重开，generation 为 `f351d640-f53d-4fba-9301-7347df8c9fc4`。`chapters / ui-2` 于 `23:46:07.544Z` 开始，随后完成 V1 的 callback、Gson、entry / metadata / headers / vary、Response 构造和 `cache-return` / `cache-finally`，至 `23:46:07.557Z` 已出现 `cache-callback-after`。B 未出现 handshake / strategy 标记，也没有后续 `cache-read` 或 HTTP 阶段，最终在 `2026-11-06T23:46:37.540Z` 命中默认 30 秒章节调用超时。A 的 strategy 正向记录和 B 的缺失只收窄后续定位范围，尚未证明日期解析是否进入或卡住，不能据此认定根因。

独立正式六路 GET 在 B 终态前的 `23:46:09.212Z` 保存基准，超时后于 `23:47:32.717Z` 再读，全部 200 且逐字段相同；account / manga / global revision 保持 3 / 2 / 1，目标书签仍为 true，无额外已提交业务修改。快照为 `/private/tmp/karuyomi-source-reopen-diag-55538-{added,after-timeout}.json`。本轮 B 正式详情、独立文档读回与跨端书签门仍未通过。
