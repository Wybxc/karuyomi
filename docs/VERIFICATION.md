# 实施验证记录

2026-11-07，同一隔离 HTTPS / D1 和测试身份下，正式 iOS 与 Android 模拟器通过章节书签往返：iOS 添加 → Android 新进程读回并移除 → iOS 新进程读回。独立六路 GET 确认两次读回无附带写入，写入仅改变目标书签和相应 revision；环境与剩余门见[书签记录](verification/bookmarks.md)。Web ↔ Native、生产 Access 与真机另验。

2026-11-07，固定 `5ba6fff` 的日期修复通过 JDK/真实生成 JavaScript 回归，以及无插桩原 xkcd 正式 Web 的两次新文档重开和书签往返。独立四阶段 D1 核对：重开只读，移除仅改变目标书签与相应 revision。历史超时、修复后立即失败及最终通过分别保留在[重开记录](verification/source-reopen.md)。本地候选未部署；同源混合平台、生产和真机门继续验收。

2026-11-07，修复书架无差异打开仍更新资料、推进共享 CAS 的问题，14 项定向回归及完整 Flutter 检查通过，见[阅读入口](verification/reading-entry.md)。正式 Native 书签驱动严格分析通过；后续模拟器实测和内置浏览器对本地 HTTPS 的信任门见[书签记录](verification/bookmarks.md)。

2026-11-07，全局设置的真实双 Web 与双 iOS 模拟器顺序往返、新文档/进程恢复分项通过；双 Web 旧 CAS 拒绝与明确重读通过。修复了 Dart 显式 false/0 与标准 ProtoJSON 省略默认值导致的确认误判，完整 Flutter 检查、格式与构建通过。实际范围、修前失败与其余平台/漫画覆盖/故障门见[设置记录](verification/reader-settings.md)，不计为完整 P1/P2 或生产验收。

2026-11-07，有界跨源搜索的正式协议、服务与 Flutter 页面已接入。完整工程检查与 Web 三包真实 Source 的前台交接、空结果/原错误隔离、CuuTruyen 分页、活动停止和详情/图片阅读分项通过；浏览器发现的前台关闭竞态已修复并推送。物理双 Worker 独立观测、更多 Source、Native 和生产仍待验，精确输入、独立 D1 核对及限制见[跨源搜索记录](verification/cross-source-search.md)。

2026-11-06，官方 `kotlinx-coroutines-core-jvm` 已接入正式源码，自有 Green Job 与四个同名覆盖已删除。正式工程及远端 CI、JVM/AOT 的真实挂起与取消/父子/启动语义、owner/lease 分项通过；固定新 AOT 经正式 Web 主入口完成 BH3 协程详情及 21 页阅读、Komiic 镜像设置/重开与筛选分页，见[协程验证](verification/coroutine-runtime.md)。HTTP await 已恢复 seed 上游可取消实现，响应所有权及 ACK 前清理的正式 JVM 202 项与完整工程检查通过；随后固定 `48c4526` 的正式 TeaVM / Node HTTP 取消子门通过，clab 后台重建两包及本机正式 harness 构建/静态装配/三路径 HTTP 200 通过；Node 最终 runner 使用显式退出，尚非自然 idle，IAB provider 不可用导致该次实际 Source/UI 未执行。两包保持 `compiled_unverified/runtimeReady=false`，无部署或正式 checkpoint 变更；产品取消、Native / 生产等剩余门继续按[计划](plan/coroutine-runtime.md)验收。

2026-11-07，默认仓库扩展管理的账户确认清单、准备/取消、有界缓存、手动更新、启停/卸载与精确关闭/显式重建已接入，独立集中检查、445 项 Vitest、22 + 63 + 470 项 Flutter/Dart 测试与完整构建通过，见[扩展管理验证](verification/extension-management.md)。初次构建为 0 扩展，彼时 IAB provider 不可用；随后当前候选的 Web 分项见下文，Native 和生产门继续按[计划](plan/extension-management.md)验收。

2026-11-07，额外仓库的账户登记、只读预览与刷新、同包明确换仓、完整来源回显、存储/设置隔离及按来源网络政策已接入，独立集中工程检查、465 项 Vitest、22 + 68 + 527 项 Dart/Flutter 与完整构建通过。随后真实 IAB 发现并修复网络登记 GET 缺身份头，完整 Flutter 回归重跑至 22 + 68 + 534 项全部通过；固定当前三包 AOT 已取回，官方 Vite 装配 64 个 Static Assets / 3 扩展。空外仓管理、max-age 再验证、双 Web 顺序收敛及默认 xkcd 安装/两页真实阅读分项通过，独立 D1 确认收藏与第 2 页进度。精确范围与限制见[额外仓库验证](verification/additional-repositories.md)；真实外仓代码、Native 与生产待验收，`0009` 尚未部署。

2026-11-07，源迁移正式合同、三 CAS D1 原子写、只读预览与书架/详情向导已接入，并通过独立集中工程检查、完整 Flutter 回归与客户端/API 构建，实际范围见[迁移验证](verification/source-migration.md)。真实 Source、独立客户端、Native 和生产迁移仍待验收；工程通过不覆盖这些层级。

2026-11-06，typed Source preferences 的 v6 控制合同、原 Preference 回调、构造前注入、D1 独立 CAS API、客户端秘密值与 Flutter 设置/重开路径已实现；集中工程检查、固定 Komiic AOT、正式 Web 设置/重开和新文档恢复分项通过；其它控件、Native 及生产门见[设置记录](verification/source-preferences.md)，正式决定见[设计](design/source-preferences.md)。历史 v4/v5 证据不自动覆盖 v6。

2026-11-06，typed Source 筛选的 Protobuf、原 Java Filter 子类保留、Flutter 编辑及空查询搜索/分页链路已接入；本次开发 host ABI 升为 v5。修复后的两包代表 AOT 与 CuuTruyen 真实 Web 动态标签、空 query、分页及重置草稿关闭后继续原查询分项通过。显式快照保留和活动取消的运行代次回收边界见[设计](design/source-filters.md)，工程结果、固定构建身份与其余真实 Source/平台待验门统一见[筛选记录](verification/source-filters.md)。历史 v4 生产与在线结果仍绑定原构建，不自动覆盖新 ABI。

2026-11-06，正式浏览页的当前包 Source 语言筛选已实现；仅投影已加载 `SourceInfo.lang`，切换包或 generation 重置，不改变已选 Source、不为筛选请求 Source 或写业务状态。设计见[包内语言筛选](design/source-language-filter.md)，正式组件结果与仍待完成的实际 Source/平台门维护在[验证记录](verification/source-language-filter.md)，不宣称全目录语言检索已实现。

2026-11-06，收藏源与快捷打开已接入生成全局设置、既有 Worker API + D1 和正式浏览入口。稳定 package/source 身份、完整全局 CAS、原请求重试与打开边界见[设计](design/source-favorites.md)；合同/API、共享 Dart 数据及其余工程检查的实际范围见[收藏源记录](verification/source-favorites.md)。独立客户端、真实 Source/索引更新、生产 Access 与目标设备继续验收，不能把本轮受控组件结果当成完整 P3 通过。

2026-11-06，书架直接续读、详情失败显式重试、续读位置只读重取及书架资料原请求重试已接入正式 Flutter 入口。稳定章节/位置/顺序恢复、未确认写隔离和迟到结果边界的受控组件记录见[续读与恢复](verification/reading-entry.md)，设计见[阅读入口](design/reading-entry.md)。实际 Source、独立客户端、生产 Access 和目标设备分别验收，不将本轮组件结果提升为完整 P1/P2 通过。

2026-11-06，自定义封面已接入生成业务协议、Worker API、D1 当前引用、私有 R2 及正式详情/书架 UI；上传使用独立二进制 multipart 与同一作品 mutation 的 CAS/ACK，清除沿 JSON mutation。共享数据回归已实测，结果与其余集中检查待补项统一见[自定义封面记录](verification/custom-covers.md)，对象宽限清理和身份边界见[设计](design/custom-covers.md)。独立客户端、实际 Native Cookie、生产私有 bucket 配置和部署尚未验收，不能据此认定完整 P1/P2 通过。

2026-11-06，章节范围已读/标未读已接入正式协议、D1 与详情 UI，包含读状态筛选、保留隐藏选择的多选/反序范围、串行精确确认和恢复。真实 Worker/D1、Dart 数据与正式组件结果及其实际范围见[章节状态记录](verification/chapter-read-state.md)；本轮还修复无 metadata 移出书架被正式合同拒绝的缺口，并通过独立真实 Worker/D1 回归。独立客户端、生产与设备门仍待验收。

2026-11-06，正式书架已接入多选、逐漫画批量添加/移出分类和移出书架；冻结确认清单与 CAS，首失败停止，未确认项精确重试，余项显式继续。工程与组件结果维护在[批量操作记录](verification/library-batch.md)；实际独立客户端、生产和设备门仍待验收。

2026-11-06，详情章节搜索、来源原序/反序和书签组合筛选已接入，保留重复条目、原始 Source DTO 及章节索引；4 项正式组件导航回归通过，含未返回详情状态时恢复服务端阅读顺序。集中检查与实际平台范围见[章节浏览记录](verification/chapter-browsing.md)。

2026-11-05，收藏与阅读进度已接入生成业务协议、Worker API 和 D1 权威状态，本地业务 SQLite 与对应 Web 资产已移除。真实 workerd/D1 的并发、幂等、身份、分页及原子失败测试见[服务端状态记录](verification/server-state.md)；本轮全格式、通用检查与 Flutter 三项目静态分析/测试通过（21/42/208 项）。Codex 内置浏览器已通过真实 xkcd 的独立会话收藏→阅读保存→重启续读，见[实际 Web 记录](verification/server-state.md#真实-web-独立会话闭环)；随后正式 iOS `app.main()` 与 Web 通过测试身份下的双向非默认页续读、真实图片及回看最远进度保持，三次官方集成测试通过，见[Web↔iOS 记录](verification/native-server-state.md)。随后正式 Android 入口补齐 Web↔Android、iOS↔Android 双向非默认页续读，六次 Native 官方集成测试各 1/1 通过，新 Web 实际显示 Android 已确认的第 2 页真实文字图，见[Android 配对记录](verification/android-server-state.md)。双 Web 正式入口随后通过远端位置/epoch 更新保持旧画面、停止旧视图写入、未先刷新时正常写路径冲突及明确重开恢复，见[双会话记录](verification/concurrent-server-state.md)。客户端与业务 API 已[部署生产并通过匿名检查](verification/server-state-production.md)；同时写竞争、实际自动前台重取、故障恢复、生产 Access 正向与真机仍待完成，历史本地数据库恢复不代表当前同步完成。

2026-11-05，分类协议、D1 API 与 Flutter 数据层通过[数据层验证](verification/category-state-data.md)，管理/排序/筛选/多关联 UI 已接入，真实双 Web 的目录、关联、旧编辑冲突与重载恢复分项通过，见[分类 UI 记录](verification/category-ui-sync.md)；Native 分类后续分项见下段，生产正向继续验收。未采用的 `runtime/image-codec` 候选与专属构建工具已删除，默认只维护 UI 直接解码。项目自有 JS 构建已进一步收敛为声明式 Vite 配置与官方 CLI，旧 builder、独立资产组装和不适合官方集成的探针已删除。Workers HTTP/状态、生成配置 harness 与内置浏览器新版 Browser 测试通过；完整构建、格式、Flutter 与通用集中检查通过，范围及限制见[Vite 记录](verification/vite-build-and-testing.md)。

2026-11-06，正式 `app.main()`、Native runtime、正常受信 HTTPS 与同一隔离 workerd/D1 下，双 iOS 以及 iOS↔Android 分类顺序五阶段已通过：创建关联、另一端改名/关联、新进程读回、删除保留收藏及新进程未分类读回，见[分类多端记录](verification/category-ui-sync.md)。Android 最后阶段曾因 DDS/容器初始化失败，保留失败后仅冷启动 AVD，原只读阶段才通过；初始化可靠性根因仍待修复。内置浏览器未信任此本地 CA，未绕过警告，因此 Web↔Native 分类、生产 Access、真机、并发故障与完整 P1/P2 均保持未验收。

2026-11-06，章节书签的 Protobuf 合同、D1 原子 mutation / 有界查询、共享 Dart 数据层以及正式详情与阅读入口已接入，工程与组件范围见[书签记录](verification/bookmarks.md)。该轮只验收工程与组件；后续实际 Web 独立文档和 Native 模拟器闭环见页首，生产另验。

2026-11-03，本地 macOS。Flutter 3.47.5 / Dart 3.13.4、pnpm 12.6.0；仓库固定 Node 24.15.0，本轮也使用 Node 26.5.0 执行检查。TeaVM 固定 0.16.0 JS backend，验证 JDK 为 Oracle GraalVM 25.0.4、Maven 3.9.11。下表区分代码/分项测试、独立机制探针与尚未完成的产品验收，不以测试总数作为能力证明。

当前图片交付已收敛为 Source 处理后的不透明编码资源，由 Flutter/UI 直接解码；工程回归、诊断性原 xkcd 阅读/恢复和默认关闭的计时采集入口见[UI 图片边界](verification/ui-image-boundary.md)。采集入口尚未取得正式性能数据，长图、真机与进程/GPU 门保持未通过。历史[编码页记录](verification/encoded-image-ownership.md)和[图片页控制记录](verification/image-page-controls.md)保留原输入与范围；其 host 编码页/tile 合同已退出当前产品路径。

2026-11-06，现有三项非敏感设置的协议、D1、API 与正式 Flutter UI 已接入：全局主题、四种阅读模式、AUTO/SINGLE/DOUBLE 页组及逐字段漫画覆盖。独立作用域 CAS、原子确认快照、幂等、继承和清空覆盖的后端分项通过；客户端/集中工程检查已通过；结果及仍待验收的实际跨端、生产和真机门分别维护在[设置记录](verification/reader-settings.md)。背景/亮度与可配置输入、适宽/适高及裁白随后已实现，分别见[外观记录](verification/reader-appearance.md)、[适配记录](verification/reader-fit.md)和[裁白记录](verification/reader-crop.md)；独立客户端与设备门分别维护。

## 工程与代码验证

GitHub 已确认 `Wybxc/karuyomi` 为公开仓库。gitleaks 8.30.1 对截至 `c1c9e7f` 的全部 Git 历史扫描，10 处命中经核对均为文件 SHA-256（8 处）和公开 Access AUD 标识（2 处），未发现实际凭据。当时的 Release 资产清单为 AOT、清单/构建记录与锁定的运行时构建材料；原始扫描报告留在忽略目录，不写入源码。

公开 Release 的浏览器下载门未通过：内置浏览器对下载入口与最终 CDN 的普通 GET/Range 均无法读取正文，响应缺少 CORS 许可；API 对照另遇匿名限流。用户已决定改为全客户端最新版 Static Assets 权威分发，取消扩展 Release 发布，证据见[公开 Release 下载门](verification/github-release-delivery.md)。现已删除 90 个扩展/索引 Release 及对应 tag，GitHub 仅保留锁定的 `teavm-runtime-release9-v1` 构建依赖；旧扩展发布工作流在 baseline 验证期间保持停用。历史两包快照通过线上下载检查；当前已部署 v4 三包并通过[匿名静态交付](verification/v4-production.md)，全量 baseline 尚未完成。

| 范围              | 已有证据                                                                                                                                                                | 复验入口与限制                                                                       |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 协议 / TypeScript | 生成版本一致性、严格类型检查，JS Worker 与 API 边界分项测试通过                                                                                                         | `pnpm check`；测试覆盖协议/ABI、hash/预算、串行与代次、取消/超时、登录响应及错误分层 |
| 运行时桥          | Codex 内置浏览器执行真实 Worker、WebCrypto、npm Zstd WASM、Canvas、IndexedDB、隔离与重启持久化均通过                                                                    | [桥验证](verification/worker-bridges.md)；不等同于 Source 在线或图片阅读验收         |
| Dart / Flutter    | source_runtime、reader_core 与 app 的静态分析、协议/布局/调度/浏览/阅读组件测试分项通过                                                                                 | `pnpm flutter:check`；测试 Provider/渲染夹具不等于真实 Source 或真机                 |
| 构建与静态入口    | 已完成本地 JS 宿主、Flutter Web release、同源资源组装及 Wrangler dry-run；公开 shell 与控制页可加载                                                                     | `pnpm build`、`pnpm dev`；dry-run 不部署，也不证明生产 Access                        |
| 静态分发 / D1     | 最新索引/清单/gzip、API 正文路由移除、D1 仅网络政策；本地真实 workerd 静态路由和政策继承已验证                                                                          | `pnpm test` 的官方 Workers/harness；历史静态探针已退役，受控夹具不是 Source 在线证明 |
| JWT / API         | 本地 RSA 密钥真实签名测试覆盖 issuer、AUD、本人邮箱/可选 subject、过期/伪造凭据、固定回跳、路径规范化与 API 不落入 SPA；静态正文绕过 Worker；动态请求按 D1 域名政策授权 | `pnpm exec vitest run apps/api/test`；测试签名不是 Cloudflare 签发的生产会话         |
| 阅读核心          | 单/双页、LTR/RTL、封面/横图独占、竖向/Webtoon、缩放/翻页、逻辑锚与布局恢复、取消/释放确认和迟到资源清理                                                                 | `pnpm flutter:check`；窗口预算为实现约束，估算解码像素不等于实测进程/GPU 峰值        |
| 设计溯源          | 初次导入摘要记录在[设计文档来源](verification/design-provenance.md)                                                                                                     | `docs/design/` 已解除冻结，摘要不用于声称当前文件仍是初始副本                        |

历史私有交付实现曾在本地与云端注册构建 `release9-mangadraft-product-e3505206005c25f69b92`：7 个私有产物，共 3,957,861 字节，云端查询状态为 verified。登记前逐文件校验长度/hash，构建与产物关联只在完整写入后可见。本地真实 workerd/D1/R2 加 RS256 测试签名探针已检查 manifest/list、全部 R2 SHA-256、HEAD/304/Range/416、缺 JWT/错误 AUD/错误 host 及整批冲突回滚，见 [API 探针](../apps/api/test/README.md) 与 [证据](verification/runtime-evidence.md#通过的分项与限制)。测试入口仅信任本次生成的公钥，产品没有鉴权绕过。

## 执行器与第三方库直接接入

2026-11-03，固定 Node 24.15.0 下完成 execa 迁移与 `tools/lib/` 删除。调用点直接使用 execa、json-stable-stringify、write-file-atomic、is-plain-obj、fflate/tar/yauzl、diff 和 get-stream；没有将通用包装换目录恢复。dependency-cruiser 检查 134 个模块、485 条依赖通过，禁止重新导入 `tools/lib/`。全库 `pnpm format`、`pnpm format:check` 与 `pnpm check` 通过，包含 256 项 TypeScript 测试、真实本地 D1 CLI、归档/补丁/静态分发及受控 origin 的 workerd HTTP v2 回归。

执行器回归真实运行 Unicode/元字符 argv、10 MiB 双流日志和过滤后的环境；checkpoint 校验失败保留旧内容，原子替换保留 0600 权限、末尾换行且无临时残留。41 项扩展发现/流水线/runner 回归包含 SIGINT/SIGTERM、正常退出仍有继承或独立 stdio 的后代，以及真实锁被删除后的失锁检测；后代停止后才允许锁释放和后续状态操作。Cloudflare 部署领域函数的 9 项无网络 CLI 回归覆盖合并输出正好 512 KiB UTF-8、两路总字节溢出、凭据脱敏、取消后独立恢复，以及正常退出和取消时 TERM-resistant 后代在函数返回前停止。这些测试没有重新执行线上权限探测或部署。

同期接入唯一 `.proto` 与 Buf，Protobuf-ES/Dart 官方生成模型用于正式 API、Source/Worker 与 Web/Native 控制边界；`pnpm generate:check` 检查生成文件全集和字节，9 项实际 TS↔Dart golden 覆盖 ProtoJSON/二进制、oneof、可选字段、精确 memo 数字文本及业务预算。`pnpm flutter:check` 的静态分析及 71 项测试通过；`pnpm build` 完成宿主、Native 材料、Flutter Web release、空扩展索引组装及 API Wrangler dry-run。Java DTO、HTTP body、图片和 Locale oracle 也通过。复验范围和命令见[协议计划](plan/cross-language-protocol.md)与[工具计划](plan/tooling-processes.md)。

2026-11-05 功能收尾时 host ABI 为 `karuyomi-source-host-v4`，protocolVersion 2 / HTTP bridgeVersion 2 不变。Access 阅读暂停/同身份恢复、namespace 执行互斥、后台 enqueue owner/drain 和 Android 异常退出文件清理已实现，先完成实现再集中回归，见[功能收尾记录](verification/p0-feature-completion.md)。新 Java 调用约定需要重建 AOT 与 Web/Native 材料；下述历史 Source、Native 与生产记录保留原提交/ABI，不自动计为 v4 通过。

随后固定 `1f599cd` 的三包 v4 原 Source 已重新 AOT，在内置 Chromium 156 通过元数据、原图片处理、2/3/3 张图片解码与释放；正式 Flutter xkcd 阅读完成、同 namespace 第二标签占用失败及关闭持有标签后重开也通过，见[v4 分项](verification/v4-source-runtime.md)。另以真实 TeaHost/BrowserCall AOT 和受控 Source/HTTP-v2 端点通过嵌套 enqueue、异常、取消及旧 owner 隔离，见[回调分项](verification/teavm-enqueue.md)。该次本地验证未部署，不提升流水线兼容标记，不替代生产 Access、Native 或真机验收。

随后固定 `13494a0` 的正式客户端/API 与这三包已部署，Worker version 为 `9a95d6e6-7578-4781-99aa-3d8bdae6b467`，snapshot revision 为 `702cc6bfb2974682bf1c83325458535a`。26 个匿名路径、三包完整性和旧资产 404 均通过，远端三包显式网络政策已核对，正式 checkpoint 已确认。完整身份与范围见[v4 生产记录](verification/v4-production.md)。当前 Access 会话失效，用户选择稍后登录；正向生产 bootstrap、Source 请求及阅读恢复待验收。`bootstrap.complete=false`，定时增量 CI 继续停用。

当前 v4 的正式 `lib/main.dart` 已重新构建为 iOS Simulator App 和 Android arm64 调试 APK，双端实际包内 manifest/host/worker 与当前材料逐字节一致，SQLite 映射和导出通过，见[Native 构建记录](verification/v4-native-main.md)。iOS 首次官方库下载失败保留，使用经固定摘要校验的标准缓存后成功；未修改第三方 hook。CUA 仍无法连接 Simulator，App 未安装/启动，不能认定当前 Native UI、Source、Access 或真机通过。

实际 TeaVM 回调门随后补齐产品 manager/Worker/driver 组合：64/65 pending 上限、真实约 30.05 秒 fatal drain、未发送的排队任务拒绝、上游连接关闭、namespace 释放及同 namespace 新 Worker/代次恢复均通过，见[组合记录](verification/teavm-enqueue.md#实际-callback-上限fatal-drain-与-manager-回收)。这是受控 Source/HTTP 端点，不代替官方 Source、生产 Access 或 Native。

P1 本地收藏书架随后接入正式 `main.dart`，支持详情收藏、搜索/排序、按当前索引重开原 Source 和继续阅读；真实 SQLite 文件关闭重开、已有进度增表保留、身份隔离及写入失败恢复通过，见[本地书架分项](verification/p1-local-library.md)。该实现只在当前设备保存，D1 云端状态与 outbox 未实现；组件 Source DTO/viewport 夹具不代替浏览器、Native UI 或生产验收。

2026-11-05，用户将多端同步提升为首要设计目标，Worker API + D1 为唯一业务权威，见[调整后的主线](plan/p2-sync.md)。上述本地书架/进度证据按原实现保留。该次计划调整本身没有实现 D1 业务表、同步 API 或跨端恢复；随后实现及当前实际三端证据见本文开头，不以历史本地恢复或计划声明提升验收状态。

此前控制身份为 host ABI `karuyomi-source-host-v3` / protocolVersion 2，HTTP bridgeVersion 仍为 2。浏览器探针入口已迁至单一 control 和正式生成 codec。固定 `6e08ec9` 后，原版 Arknights Comics 已重新 AOT，并在 Codex 内置浏览器通过初始化、真实 Source 元数据和首中末图片门，见 [v3 运行证据](verification/protocol-v3-runtime.md)。该历史记录不证明 v3 的生产部署或剩余运行门，当前直接维护 v4。生产 Access 正向 bootstrap 的历史证据见下文。下文 v2 图片和 v1 部署证据仍保持原身份；冻结 `022d828` 全量未改动，不能把其产物装配进当前客户端。

同日将正则供体类命名从补丁移入构建生成步骤，使用 `java-parser` token 位置保留原排版与字面量，再应用行为补丁；全部 13 份生成 Java 与拆分前逐字节一致，原输出摘要未改。回归覆盖刻意保留的上游类型转换、Lexer 引用与继承关系、字符串/文本块和注释不误改，以及源码/上下文/结果漂移拒绝。`toolchain/license.txt` 同时改名为 `android-sdk-license`，仅更新锁中的路径，41 字节内容与摘要不变。

## Android 普通文本布局分项

2026-11-04，项目 owned `TextPaint`/`Layout`/旧构造器 `StaticLayout`、真实 Canvas 字体指标与有界布局已接入，并补齐 TextInterceptor 使用的 HTML 字符串投影。Codex 内置浏览器 Chrome 156 通过 Canvas 五组机制门及同份 Java 101 项检查；独立固定 API 35/Robolectric 4.17 的 Android NATIVE oracle 同样通过 101 项，并断言真实 native shadows 和固定 instrumented SDK 身份。两端默认字体输出分别为 1000×140 与 1000×190，不声称高度或 PNG 像素等价。新增 CRLF 场景曾在 TeaVM 失败，修复后完整重跑通过；浏览器资源账本均归零。

这些机制证据覆盖 HTML plain-string、UTF-16 range、padding/spacing/行宽、普通文本绘字与预算。固定 `926b93d` 后原 xkcd 两页及 Flutter 可见文字已通过；固定 `5148c60` 的新文件/Bitmap 生命周期宿主重 AOT 后，两页也已通过。原 JAR 摘要保持一致；重复处理与内部自然回收、生产 Access 和 Native 应用分别验收。旧 host 的 Android Stub 失败证据保留。正式入口、原 Android plain 状态反向断言及未验范围见[文字布局记录](verification/text-layout-runtime.md)与[计划](plan/text-layout.md)。

## Cache 生命周期与有界正文分项

正式 Cache 桥直接使用 `idb@8.0.4`，正文为最多 64 KiB 的二进制块，metadata 与正文分开；snapshot pin 保留被替换/清空后仍在读取的完整 body，visible 与 staging/retired allocated 分别计费。Codex 内置浏览器通过真实 Worker/IndexedDB/Web Locks 门，覆盖死亡 owner、CAS/generation、事务 abort、读者 snapshot、六类 chunk 损坏与中途关闭。reader-close 原事务失败后独立按 owner/handle/directory/reader 清理，保留原错误，避免 Java 已释放的 reader 永久 pin 正文。具体矩阵与正式复验入口见[Cache 记录](verification/http-cache-runtime.md)。

共享 `CacheScenarios.java` 分别在官方 Maven 未适配 OkHttp 5.5.0 与真实 TeaVM 0.16 产品 Cache/BrowserCall/二进制 JSO 中执行，经受控 workerd origin 对照冷/热命中、304、no-cache/no-store、POST invalidation、Cookie Vary 和 evictAll 后打开 snapshot。请求/网络/命中/成功写入及正文摘要一致；原 JVM 断言实际 CodeSource，避免误用 seed 同名适配 JAR。CacheSink 的存储写失败只丢弃缓存副本，不吞网络读取异常。

独立的[共享 Java HTTP 故障门](verification/cache-http-failures.md)已在官方原 JVM 与 Codex 内置 Chromium 156 的实际 TeaVM 各通过四场景、50 项检查：精确读取 8192 B 后截断或取消、Cache 关闭后同目录重开、半成品不可见、旧完整条目保留及网络恢复。另观察到本地 HTTP/1 中继两次真实 RST 和四条原点响应关闭，正式 runner 退出 0；不推广为生产 HTTP/2、HTTP/3 或真实 Access 取消。

已有新 Cache 材料的 Arknights/CuuTruyen 在线图片分项见[Source 复验](verification/graphics-source-runtime.md#新-cache-材料复验)，仍未实测其冷/热 Cache 命中。固定 `b4f72f7` 的新 AOT 随后通过[原 xkcd 元数据 fresh Cache 复验](verification/source-network-cache.md)：cold HTTP 200 并提交 7187 B，warm 实际 store entry / 正文读取 / EOF / close，零上游请求；两次页列表摘要相同。原图片 cacheless 仍各自请求网络，无 304 结论。独立 origin 的原 Source 又通过 12 项实际 manager/Worker 重建门：dispose 终止旧 Worker，新 manager/Worker 在同四维 namespace 命中并读完 7187 B、EOF / reader-close，零网络、同 PageList 摘要，最终两 Worker 终止。这只验同一浏览器文档内的重建；浏览器进程、正式版本/身份切换、生产 Access、更广 Source / 取消仍待验收。随后双端模拟器也通过[原 xkcd Native Cache](verification/source-cache-native.md)：cold 完整提交 7187 B，warm 与正式 Native 容器重建后读取相同正文至 EOF、零网络，逐会话与最终 dispose 确认；不是 App 进程重启或其它 Source 结论。

真实 manager/加载器/产品 Worker 与受控 TS ABI 在内置 Chromium 156 通过[namespace 与组合存储 11 组](verification/runtime-storage-namespace.md)：实际构建替换和 manager 重建后 IDB 数据保留、四维隔离，以及同一真实派生键下 Cache/files 各 128 MiB allocated、完整分块读回与清理。没有修改 usage 伪造边界；不代表 Java/官方 Source、生产 Access、Native 或进程/物理磁盘资源门。

## 有界普通文件分项

`5148c60` 已将普通文件改为 typed idb inode/chunk、64 KiB 二进制 JSO、稀疏文件、配额与 Web Locks owner。数据、路径、长度及账本同事务，提交后才更新 cursor/ACK；rename/unlink 保留打开 inode，失败关闭可显式重试。真实浏览器机制、原 JVM 和实际 TeaVM 的共享 File/RandomAccessFile/Okio 场景分别通过；首次实际 TeaVM 门发现的 EOF/unsigned 差异由项目自有 JCL 适配修复，没有修改 vendor 或扩展 JAR。

固定预算、原始失败与最终输入身份见[文件证据](verification/file-storage-runtime.md)和[设计](design/runtime-file-storage.md)。普通 files namespace 的逻辑/allocated 预算已经实施；与独立 Cache 的既定分区及实际组合压力已通过上述受控 ABI 门；正式 Source、Native、产品切换和设备资源测量仍待验，见[存储计划](plan/runtime-storage.md)。

## 阅读连续性分项

2026-11-03，阅读路由已接 Source 原序/反序、漫画作用域章节键与上一章/下一章控制；不按编号排序或丢弃重复 URL。每次切章等旧 Reader 的 scheduler、图片 pin 与 provider 清理 ACK 后才挂载新叶；下一章 pages 迟到和新 provider 在下一帧挂载前退出均被关闭。`chapter_sequence_test.dart` 与 `chapter_reader_route_test.dart` 覆盖空/零/小数编号、重复章的快照键、跨漫画/Source 隔离及延迟清理/退出竞争；相关 26 项组件回归和 Flutter analyze 通过。完整 `pnpm flutter:check` 通过三个包的静态分析及 15/23/50 项测试，完整格式检查通过。此时尚无背景下一章准备、Drift 落盘、真实 Source 章节连续阅读或真机证据，不据此标记 P0/P1 通过。

2026-11-04，正式 Drift 产品接线与数据库静态资源已完成，完整格式检查、通用检查、TeaVM 回归及最终格式化后的三个 Flutter 包分析/测试通过。Codex 内置浏览器实际阅读原版 Arknights，完成连续切章、回看不降低最远进度、关标签页重开后恢复章节/当前页/最远页/章节顺序，以及重新阅读回首页。固定输入、命令和边界见[Web 产品进度记录](verification/reader-progress-web.md)；此处不是浏览器进程重启、Native 应用或生产 Access 动态请求门。

2026-11-04，固定新 host 的 Arknights DREAM 51 页、CuuTruyen Chương 142 的 23 页已在正式 Flutter Web 逐页显示并保存，末页显式完成，同路由下一章开头也通过，见[完整章记录](verification/full-chapter-web.md)。手动单双页被控件高度变化覆盖的缺口已先以正式 Widget 复现再修复；重连旧身份与迟到 API/图片清理污染新会话也已通过正式回归修复，见[重连记录](verification/runtime-reconnect.md)。该轮完整格式化、`pnpm flutter:check`（Reader 102 项）及 `pnpm check` 通过；固定 `be5c3ed` 的正式 Flutter Web release 已通过修复后末页实际复验：手动单页保持、51/51 保存及显式完成、返回详情继续阅读，详见同一完整章记录；没有重新逐页阅读 51 页。随后同一正式客户端以原 xkcd 通过 Web A→B→A：B 无 A 的继续阅读、返回 A 首次恢复第 2 页文字图，三个 Worker 的 namespace 依次 A/B/A，真实 304 后从原 Cache 读取 7187 B 至 EOF 并关闭。首轮记录器失败和新 origin 完整复验分别保留，详情见重连记录；版本更新、Native 身份与生产 Access 仍待验收。

## 新图形宿主与生产 Access 分项

2026-11-03 至 04，固定 `15a3900` 后六包本地 AOT 通过；Codex 内置浏览器在新材料下通过 Arknights 首中末直图，以及 CuuTruyen 23 个真实 DRM 页中的首中末 Bitmap/Canvas 重排。Little Tyrant 与 Philia Scans 初始化成功，但元数据请求均被各自站点 403 拒绝，图片未测。MangaDex 原包 61 个 Source 初始化成功，英文 Source 的列表链因 HTTP 超时失败，图片未测。xkcd 元数据及直图成功，但原 TextInterceptor 文字图片遇到 Android Stub，完整图片门失败。具体输入身份、必要数量和限制见[Source 记录](verification/graphics-source-runtime.md)。这些测试使用隔离 D1 和测试签名，仍不是生产 Source 或 Native 证据。

2026-11-04，用户在 Codex 内置浏览器完成真实 Cloudflare Access 登录，实际回跳 `https://karuyomi.wybxc.cc/api/bootstrap`；页面返回配置的本人邮箱、非空 subject、expiresAt 与 `stage=p0`。这一项证明当时生产正向登录及 bootstrap，未导出登录 Cookie/JWT。当时线上响应为旧部署 `protocolVersion=1`，不能代替当前 v4 / protocolVersion 2 的正向验收；Source 动态请求、会话过期/恢复与 Native 登录另验。历史匿名拦截及未登录状态的记录保留其当时范围。

## 历史部署与匿名边界

2026-11-03 已成功部署 `https://karuyomi.wybxc.cc`，Cloudflare Worker version 为 `0332ef7a-3d49-47c1-ac41-edbed49bd7fe`。云端 D1 的两次迁移均通过，e350 产物已 remote 注册。匿名检查得到 `/` 200、`/runtime/host.js` 200，`/runtime/host.html` 307 规范化到公开 `/runtime/host`；Safari 已实际渲染 Flutter 书架与三个导航页签。

Access 本人策略覆盖 `/api` 和 `/api/*`。匿名 `/api`、`/api/bootstrap` 与私有 `/api/extensions/artifacts/<hash>` 均返回 302 到 `wybxc.cloudflareaccess.com` 登录，保持 private/no-store。当时只验证了公开入口与匿名拦截。后续生产正向 bootstrap 已单独验收；私有产物交付属于已移除的历史架构，会话失效与恢复仍未验收。

## 自动化 TypeScript 迁移

16 个自有 Python 脚本及测试已全部迁为严格 TypeScript；CI 内嵌 Python 已移除，Python/venv/Ruff 不再是自有自动化依赖。Java oracle/编译器适配和平台构建配置保留原语言。依赖方向见 [TOOLING](TOOLING.md)：工具不反向导入 CLI，通用层不依赖领域，产品不导入工具；API 原有类型循环已提取到 `env.ts`，Native 资源由顶层组装。

固定 Node 24.15.0 下已通过全库 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 与 `pnpm build`。dependency-cruiser 覆盖 117 个模块、442 条依赖，无循环、越层或未解析导入；平台提供的 `cloudflare:workers` 按其环境解析。真实上游计划 CLI 发现 1,448 包，只生成忽略目录中的计划，未因此启动初次全量。CI 环境的流水线测试还实际验证了 SIGINT/SIGTERM 进程树停止后才释放 checkpoint 锁。

迁移提交 `8ad2362` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41606164124) 已全部通过。首次固定 checkout 真实代表构建中，Arknights Comics 原版 Gradle 编译通过，但分阶段宿主 javac 漏掉 HTTP v2 的 `HttpBodySource`，AOT 尚未进入 TeaVM。现已补齐 bootstrap 编译输入，新增真实 javac 依赖回归，并用实际 Maven classpath 编译正式桥四个类通过。该失败属于宿主编译输入，不是 Source 或原始 JAR；不能用上述检查通过替代完整 AOT 验收。

修复提交 `1bfc97f` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41610334065) 已全部通过。固定该提交的独立 clone 与三个上游 pin 后，Arknights Comics、MangaDraft 均完成原版 Gradle → TeaVM AOT → gzip 完整性检查，并在 Codex 内置浏览器 Chromium 156 通过正式 `verify-build.ts --serve`：实际下载/解压、Worker `hostInit/hostLoad`、IndexedDB 与清单 Source ID 一致，未发生 Source 网络请求。两包对应报告为 `browser_verified` / `runtimeReady=true`，在线兼容仍为 `not_tested`；其他未实测构建继续保持 `compiled_unverified`。

最终固定提交 `022d828` 的两包均重新构建，并对新清单与新字节重新通过同一内置浏览器 gate；不复用 `1bfc97f` 的验收报告。[该提交 CI](https://github.com/Wybxc/karuyomi/actions/runs/41614236181) 全部通过。

| `022d828` 代表构建     | 原始 JavaScript | 唯一 gzip | Source ID             |
| ---------------------- | --------------: | --------: | --------------------- |
| Arknights Comics 1.6.2 |     1,839,808 B | 592,989 B | `5973713386239249589` |
| MangaDraft 1.6.2       |     3,814,317 B | 800,371 B | `6866320578550428692` |

完整冻结计划发现 1,448 包；两包代表快照保留完整 catalog，尚未 finalize baseline。确认两包最新快照后，已从固定 `022d828` 独立 clone 启动本地剩余 1,446 包的单并发全量，首个新包已 built，supervisor 与实际 builder 均确认运行。它逐包保存交付结果，全部尝试结束后才产生完整候选；不自动部署或提前提交 checkpoint。计划、checkpoint、产物和原始报告均留在忽略目录，不能据此声称全量发布、在线阅读或真机验收已完成。

## CI 凭据权限

[Actions 权限验证](https://github.com/Wybxc/karuyomi/actions/runs/41605483397) 已成功使用仓库 secrets：更新预先建立的隔离 Worker `karuyomi-ci-permission-check`、上传一份唯一 Static Asset、创建 D1 并写入/读取标记，以及创建唯一随机子域名路由。最后删除临时路由和 D1，并将无公开地址的隔离 Worker 恢复为空白配置；生产应用和数据库未修改。

早期探测误用创建/删除 Worker，超出了正常部署所需的 Editor 权限。Cloudflare 当前 Editor 只能编辑已有 Worker，因此检查改为现有隔离 Worker；不要求给 CI 增加 Admin。该记录证明部署所需权限，不证明当前扩展快照已部署或生产 Access 登录通过。定时增量工作流在本地 baseline 完成前继续停用。

## 静态分发分项

当前 v4 三包生产快照及匿名交付见[生产记录](verification/v4-production.md)。以下 `022d828` 两包部署和政策保留其历史状态，不是当前生产目录。

固定 `022d828` 的两包代表快照已部署到 `https://karuyomi.wybxc.cc`，Worker version 为 `1d434d1b-7e30-4668-b458-350e486f3b3d`，快照 revision 为 `22378bbcb89d40f5a0397c5098310072`。生产 D1 `0002` 迁移已成功；公开 index/state 字节与本地候选一致，两个 gzip 的 MIME、无 HTTP Content-Encoding、immutable 缓存与编码/原文双 SHA 均通过实际匿名下载验证。前一 `1bfc97f` 的两个清单和 gzip 地址均已实际返回 404，确认当前快照只保留最新版本。六份共享材料的长度/摘要通过，未知扩展和 Native 内置资源路径返回 404，匿名 `/api/bootstrap` 仍跳转到原 Access 团队。bootstrap 尚不完整，不能启用初次全量 CI；当时只有匿名拦截证据，后续生产登录分项见上文。

注册 CLI 已改为只校验当前 index/manifest 与材料元数据，不读取 bundle 或重复计算摘要；原 `--artifacts` 参数已移除。锁定 Wrangler 的标准 pnpm 补丁修复 D1 `--file --json` 夹带上传进度的问题，仍保留严格 JSON 解析和 SQL 失败拒绝。本地真实文件写入/查询/错误 SQL、30 项政策回归与 13 项真实 workerd 门均通过；修复后的正式远端同步也通过：当时两包只继承 MangaDraft 原有 `www.mangadraft.com` 策略，Arknights 保持未授权。线上快照确认后，本地 checkpoint 已保存，首次全量标记仍为 false。

最新静态交付代码已覆盖：严格 TS/Dart 当前索引、gzip 编码/原文字节各一次传输摘要、有界解压与取消；资源组装只复制当前索引可达文件，拒绝混合 index/state、损坏 gzip 与显式缺失快照。流水线离线回归包含源码/依赖/host 指纹、同失败不重试、扫描失败保留成功、运行时不匹配排除、删除退役、首次本地初始化、checkpoint 锁、真实进程树信号取消，以及远端确认后才提交状态。

真实本地 workerd + D1 + Static Assets 门验证了公开索引/清单/gzip 不进入入口 Worker、gzip MIME 且无 HTTP Content-Encoding、匿名静态下载、缺失扩展 404、应用 shell 与控制页规范化、移除的 API 返回 404、RS256/AUD/host 拒绝、元数据事务回滚，以及部署后只继承既有包的明确域名政策。新包仍未授权，退役包政策删除。此次夹具是受控小脚本，尚未代替当前真实 TeaVM AOT 初始化或生产 Access 验收。正式入口见 [API 回归说明](../apps/api/test/README.md)。

## P0-A 真实构建与 Web 初始化

2026-11-03，TypeScript 迁移后的 6 份共享材料已通过实际 workerd 检查：摘要、长度、JavaScript/WASM MIME 和 public immutable 缓存头正确。逐包 AOT 输出唯一 gzip bundle；D1 仅注册网络授权元数据，静态材料按受信 host catalog 核对。原型不保兼容，旧桥副本与旧 raw 恢复路径已移除；旧固定宿主全量队列已停止，需以当前宿主身份重建。gzip 恢复回归覆盖编码/原文双摘要、长度上界、截断、尾随和拼接流。当时两包真实 AOT 与线上传输证据见上文；全量 baseline 和旧本地 bundle 缓存清理仍待验证，后续正式 Web 版本更新分项见[独立记录](verification/extension-version-web.md)。正式契约见[共享材料](RUNTIME-MATERIALS.md)与[发布说明](EXTENSIONS.md)。

同一 `1bfc97f` Arknights Comics 原版扩展已在 Codex 内置浏览器 Chromium 156 经产品 Worker、隔离 D1、真实 workerd 和 HTTP v2 完成在线元数据检查：热门 17 项，搜索首个标题返回同名 1 项，详情成功，章节 3 项，真实章节 pages 返回 51 页；latest 按 `supportsLatest=false` 明确跳过。网络使用显式 `arknights.global` 白名单及真实 RS256 测试身份，不是生产 Access。未请求图片字节，未修改 Source/JAR，也未据此判定图片、Cache/JVM 等价或完整阅读通过。

真实 Flutter + flutter_inappwebview 6.1.5 + iOS 26.4 Simulator 已在本地受信 HTTPS 通过内置运行时验证：控制页真实 307 从 `/runtime/host.html` 到 `/runtime/host`；document-start 内置 host 与 Blob Worker 完成 Arknights Comics 的 `hostInit` / `hostLoad`，返回 Source `5973713386239249589`，IndexedDB 可用，API 携带同源 HttpOnly cookie。服务器故意将远端 host.js、worker.js 和材料路径设为 503，这些路径请求数仍为 0。旧 cache/file 构建明确拒绝并提示升级扩展；同长度篡改 AOT 被 `integrity_error` 拦截，重建容器后正常恢复。实测同时修复 WK 返回 HTTP status `200.0` 的有限整数转换边界，并加入负例回归。临时入口、HTTPS 服务、证书与原始记录均留在 ignored `.local`，正式 app 代码、资源校验及 iOS CocoaPods 集成入库。

这项验证覆盖真实 Flutter 原生控制容器和本地 cookie 恢复，不是 Cloudflare Access 正向会话、物理 iPhone、图片通道或 Source 在线语义验收。

历史导入校验了 release9 研究交付；当前正式 Java 与桥已内化为项目源码，真正上游通过 submodule 和补丁追踪，依赖、原 JAR、ZIP 和大产物不入库。原 MangaDraft JAR SHA-256 为 `81d456c80449fc205e50332ff281c0b8ee20e584f7e5670ccd3f79abb71dfa86`，基线和产品构建前后保持一致。

| 项目                | 证据                                                        | 能证明的范围                                                                                                                         |
| ------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 冻结宿主基线        | [历史构建摘要](verification/runtime-evidence.md#构建与输入) | 未修改 release9 宿主真实编译；没有生成可安装产品清单                                                                                 |
| 产品宿主            | [产品构建摘要](verification/runtime-evidence.md#构建与输入) | 新 `hostInvoke` ABI、完整 DTO、显式引用覆盖层真实编译；bundle SHA `209ad02ba02eae99147502799c08e1aac0c1c7bc29906aa3d60e99174b1b9f22` |
| Chromium 156 初始化 | 同上摘要的浏览器初始化分项                                  | 清单/hash 检查后实际执行 `hostInit` / `hostLoad`，返回 MangaDraft ID `6866320578550428692`；缺章节引用经 Java 失败回调返回结构化错误 |
| DTO JVM oracle      | `tools/teavm/HostDtoTest.java`                              | 六项操作使用的完整漫画/章节/页面字段、长列表不截断、分页参数、顺序、memo、Long 精度及显式引用验证                                    |

`popular/latest/search/details/chapters/pages` 已实现 Java 调用边界。新增 Chromium 156 + 产品 JS + 真实 workerd/D1/R2/v1 HTTP bridge + RS256 测试签名的在线探针中，热门/最新/搜索请求均为 HTTP 200 并返回 20 项完整 DTO；原 JAR 字节码已确认：`j.getSearchManga` 将非 URL 查询原样交给 `r.i`，后者只构造过滤/分页参数，未将文本关键词加入 catalog 请求；观察到的不筛选行为来自冻结 Source 自身，不是 Host ABI 漏参，不能将返回列表判定为搜索匹配。详情/章节访问真实 `/manga/dragon-ball-kakumei` 后被源站 302 到 `/bot-verification`，最终返回 Human Verification；Java 明确返回 `source_error: Unable to find project script`，这是源站挑战而非 ABI 加载错误。探针没有伪造章节或 pages 引用，pages 尚未实测。当前仍未判定六项在线 Source 等价。控制 `ready` 始终为 `sourceReady: false`；真实初始化成功的 `open` 才返回 session。Source ID 与清单不符、hash/MIME/预算错误或登录 HTML 不得进入可用会话。远程脚本、非默认 filters/preferences 和产品图片调用仍明确不支持。

```sh
git submodule update --init --recursive
pnpm teavm:prepare --android
pnpm teavm:check
pnpm teavm:build --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

上述命令仅适用于 [f623a82 及此前源码](https://github.com/Wybxc/karuyomi/tree/f623a82)；本轮已删除独立 Source 探针，不作为当前复验命令。当时打开脚本输出的 localhost 页面运行正式 Source 集成回归。它使用真实 IndexedDB、产品 Worker 与 HTTP bridge、隔离 workerd/D1/Static Assets 和 RS256 测试签名；不修改产品鉴权入口。复验步骤见 [集成说明](../apps/api/test/source-metadata-probe.md)，实测状态见 [摘要](verification/runtime-evidence.md)。初始化通过不等于文件/HTTP Cache 重启、升级与取消语义已完成回归。

## P0-B 独立字节与错误探针

[字节机制摘要](verification/runtime-evidence.md) 记录 Chromium 156 上实际编译的 TeaVM JSO 探针：空字节、`00/ff`、全部 256 值、含 NUL/emoji 的 UTF-8、带偏移视图和 64 KiB 随机字节经 `Uint8Array → byte[] → Uint8Array` 显式复制后逐字节一致。它同时验证 64 KiB 限额、复制不别名、retained Java 引用清除、fiber 等待/IOException 恢复、模拟 supplier 取消后无遗留/迟到回调，以及主线程/Worker 双向转移后的发送方 ArrayBuffer 脱离。这里只保留复制与取消的关键门槛；桌面机制结果不外推为手机性能、零拷贝或总堆上限。

[Zstd 错误摘要](verification/runtime-evidence.md) 对照实际编译的原版和产品 `Bridge.zstd`。两者对真实 WASM 无效压缩流都返回 `Truncated Zstd frame`；显式注入 rejected host Promise 时，原版生成代码因局部变量名碰撞抛出 `TypeError` 并等待超时，产品实现改用 `failureReason` 后恢复 Java RuntimeException。历史原版对照保留在本地研究归档。

临时独立研究工程和脚本已移入本机被忽略的 `runtime/teavm/.local/research/`，保留原始本地资料，不进入源码仓库。上面的精简文档记录历史机制证据；正式产品与发布回归需要独立测试，不能依赖临时工程存在。

产品代码现已加入 [HTTP v2](HTTP-BRIDGE.md)：严格帧、Worker 按需响应、JS operation/generation handle、Java Okio Source 与有界上传 Sink。新增协议 38 项及 JS transport 9 项测试；完整 TypeScript 套件 192 项通过。Java 完整 javac 与 `tools/teavm/HttpBodyTest.java` 的 1,051 项断言通过，包括 64 MiB 分块读取与 8 MiB 上传上限（`pnpm teavm:check` 同时运行 DTO 与 body oracle）。真实 TeaVM 0.16 编译 JS 在 Node 的模拟六函数 supplier 下，验证 131,079 字节 GET/POST（00/ff、64 KiB 分块）、空 POST、pending-read 取消、超时、超请求块与 EOF 长度错共七例，handle 最终归零；这仍不是实际 HTTP、浏览器或 Access 验收。

当前构建、注册清单、Java、Worker 和 API 只维护 HTTP v2，旧 v1 传输分支已删除。Java 重新经过真实 TeaVM 编译后的 18 例模拟 supplier 回归，覆盖 GET/POST、空正文、取消/超时、受控重试及错误分类；这些仍是模拟环境证据。

`pnpm test:http-bridge` 已通过真实 workerd 与受控 HTTP origin 的 24 项检查：夹具真正发送 gzip（3,164 字节）与 Brotli（657 字节），解码后均为 131,089 字节且 SHA-256 一致；覆盖 200/206/403、HEAD、重复 Cookie、手动重定向、流式 POST、早响应仍验证上传 END，以及消费取消、请求取消和超时关闭 origin。分项实际验证 204/205/304 无正文与 304 表示元数据、显式 Range 的精确 19 字节返回、Unicode/重复 urlencoded 字段及跨 64 KiB 的 multipart 文件。表单由标准 Request/FormData codec 生成和解析；origin 在消费者已读到正确前缀后真实截断，bridge 返回 `upstream_body_error` 而非成功 END。入口通过固定 Undici 直连用户 Worker socket，origin 经明确启用 signal flag 的辅助 Worker 和原生 external HTTP proxy；没有修改生产入口。四个主动取消场景均使用 30 秒请求期限、1 秒取消窗口，本次本地取消及 origin 关闭用时约 12–22 毫秒；持续发送时使用普通 body cancel / AbortSignal，首块后 idle 的场景明确使用 TCP reset，不能把本地 destroy 当成远端已取消。该门已纳入 `pnpm check`，完整输出留在忽略目录 `.local/probes/http-bridge-v2.json`，合同见 [HTTP bridge](HTTP-BRIDGE.md)。提交 `7e57a74` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41760712045) 已全部通过，包括通用检查、Flutter、构建与本地 D1。它不涉及实际 Source、生产 Access 或 CacheInterceptor；原 Source/cache 同版对照和图片/移动内存链路仍需验收，P0-B 尚未通过。上面的部署版本属于旧版本历史记录，当前代码尚不能据此声称已部署或通过生产 Access 正向会话。

共享 CacheInterceptor 的截断/半途取消另有[实际 TeaVM 与原 JVM 对照](verification/cache-http-failures.md)，与上述模拟 supplier、独立 HTTP bridge 门分别计证据；生产网络取消仍未通过。

正式 `be5c3ed` Flutter Web 主入口已完成原版 Arknights 1.6.2 图片获取中退出与恢复的限定分项：真实未完成 HTTPS 响应转发 8192 B 后暂停，正式 Reader 返回触发取消，约 12 毫秒后上游 aborted/close，早于 Source 原 10 秒期限；Java 取消、章节关闭、首图及原取消页恢复可见与保存均确认。最终 Worker 终止、308/308 遥测检查点与正常服务关闭分别取得；旧轮的超时、400 和缺失检查点均保留，见[Source 图片取消证据](verification/source-cancellation-web.md)。这一门使用隔离 RS256、loopback HTTP/1 与真实 Source HTTPS，不是生产 Access、HTTP/2/3、Native、全部图片阶段或进程/GPU 峰值验收。

## Web 产品图片通道

2026-11-03，当时 host ABI `karuyomi-source-host-v2` 的原版 Arknights Comics 1.6.2 已完成实际 AOT，并在 Codex 内置浏览器 Chromium 156 通过正式 Worker 初始化门：IndexedDB 可用、清单 Source ID 一致。build 为 `ext-en.arknightscomics-4d57964aa8f40e8728f0fb701b2fa3de`，bundle SHA-256 为 `7f47a06dfb8002b9f0b70713d39588091ba909f4477eadb6288fb7382c9ee93f`。这不是已部署的 ABI v1 两包快照，也不能与仍运行的固定 v1 首次全量混装；它不代表后续 v3 控制协议已通过实际运行验收。

本地隔离 D1、签名测试 JWT 和真实 workerd 的 Source 门完成热门 17 项、标题搜索同名 1 项、详情、3 个章节及 DREAM 的 51 页列表；latest 依源声明跳过。网络政策显式限定 `arknights.global` 与元数据确认的 `webusstatic.yo-star.com`，未扩展生产政策。原 Page 对象由 Java 会话保存，图片经原 Source 的 `getImageUrl/getImage` 与 HTTP v2 进入产品图片 sink，没有读取原图 URL 绕过 Source。

| 实际章节页 | 已处理编码字节 | 浏览器解码尺寸 | 显示与释放                                     |
| ---------- | -------------- | -------------- | ---------------------------------------------- |
| 第 1 页    | 39,602 B，JPEG | 1200 × 1691    | decode、尺寸一致、重复释放及 Blob URL 撤销通过 |
| 第 26 页   | 719,916 B，PNG | 1200 × 1691    | 同上                                           |
| 第 51 页   | 718,931 B，PNG | 1200 × 1691    | 同上                                           |

实际 Flutter Web release 构建在同一边界经“浏览→扩展→Source→漫画详情→DREAM”进入 ReaderScreen，真实首图、单双页翻页、缩放/重置、连续阅读模式切换与放大层打开/关闭通过交互检查；模式切换保留逻辑页，连续下一页可前进至第 3 页。它是本地产品链路，不是 Cloudflare Access 正向会话、完整章逐页验收、下一章/进度持久化或手机性能。

正式回归还覆盖：保留原始/子类 Page、cacheless/progress 与本地 XOR 拦截器的 JVM 对照；双完成后才公开资源；单块 ACK；取消与迟到发布、解码预算 tombstone、Java 退出后解锁；资源公开后迟到 cancel/close 不撤销已返回 Blob；详情退出动画期间迟到 pages 不重开 Reader。真实 Flutter 退出还暴露了两端 mock 掩盖的应答漂移，现关闭会话统一为 `{closed:true}`，取消/释放为 `{released:true}`，公开 API→Worker 延迟确认与浏览器 Source 门均明确检查相应 ACK。原始日志与截图留在 ignored `.local/image-session-review/`，复验入口见 [Source 门](../apps/api/test/source-metadata-probe.md)。

`pnpm check`、`pnpm flutter:check` 与产品 Web/API dry-run 构建通过；Java 图片 oracle 对 seed 和正式 HttpSource 两套签名均通过。该历史输入的 Web 终端有 encoded/pixel/resource 总预算、头部预检与实际 decode；随后内部 Bitmap/ImageDecoder 的二进制与合计账本进展见下节。不能据此声称图片解密/重排、动画/超长图、进程/GPU 合计峰值、Native 受管文件或 P0 已通过。

## 长图 codec 机制（历史，候选已删除）

2026-11-05，未采用的候选源码、专属构建与测试工具已在 `e11b014` 删除。以下结果只记录历史机制，不表示当前仍维护或打包这套实现；当前由 Flutter/UI 直接解码。历史源码与构建说明见固定版本的 [codec README](https://github.com/Wybxc/karuyomi/blob/a2251a6/runtime/image-codec/README.md)。

2026-11-04，官方 Emscripten 5.0.7 macOS arm64 SDK 的 libspng 0.7.3 对 1080×20000 / 1080×40000 合成 RGBA8 非交错 PNG，Node 四项与内置 Chromium 五项通过；libjpeg-turbo 3.2.1 对 720×30000 / 720×60000 合成 baseline JPEG，Node 九项和浏览器六项通过。Node PNG 完整流对照原始 RGBA，JPEG 原尺寸与 1/2、1/4 完整流对照独立解码基准；Web 只核首/中/末区域且实际可见，不声称全流或缩放验收。

64 KiB 单块 ACK 背压、首块后协作取消与截尾拒绝分测通过，JPEG progressive 在解码前拒绝；协作终态 C 账本归零。观察到非共享 WASM heap 为 16 MiB，JPEG 最大计量 payload 为 1,959,276 B，不等同 RSS/GPU；强制 terminate 只证明 100 ms 窗无后续消息，没有测得 heap 回收。服务均已 exit=0、端口释放。官方 SDK 准备器及无大型下载的归档/HTTP/进程清理回归已接工程检查。详情、历史工具链偏差和复验命令见[长图 codec 证据](verification/long-image-codec.md)及固定版本的 [SDK 操作](https://github.com/Wybxc/karuyomi/blob/a2251a6/runtime/image-codec/README.md)。这些是独立机制，Source、随机区域/LOD、Flutter/Native 与真实设备峰值待验，正式 16 Mi 像素准入尚未调整。

正式源码也已在同一 macOS arm64 官方 SDK 下完成独立构建与 Node 19 项回归：四幅合成 PNG/JPEG 长图的完整流及首/中/末摘要一致，heap 均为 16 MiB，最大计量 payload 为 3,645,862 B，close 后分配数与 payload 均归零。两次使用独立构建缓存，第二次注入无效 CFLAGS/LDFLAGS/EMCC_CFLAGS/CMAKE_TOOLCHAIN_FILE，生成的四个 JS/WASM 文件字节相同；仅证明同主机/同 SDK 重建。新轮 80 ms 暂停只测同线程 pull，JPEG 缩放只核尺寸和字节数；新产物的独立 Worker、浏览器、共享材料、Source 与终端均待接入。正式命令、输入身份及覆盖范围见[正式 codec 验收](verification/long-image-codec.md#正式源码构建与-node-验收)。无大型 SDK 下载的 53 项运行库/构建器/工具链回归、完整 macOS 格式与通用 `pnpm check` 已通过。

随后当前源码增加有界 PNG encoder 和独立 codec Worker：真实 Node 门扩为 24 项，新增条带编码由 Sharp 全像素对照。正式 catalog/client/VerifiedLoader/Blob 模块与 WASM 已在 Codex 内置 Chromium 156 通过 11 项：四幅长图加最大高熵条带共 590 个基础 tile 的 PNG 字节/几何匹配独立 Node 实例，同一 Worker 内两个独立 WASM 实例；250 ms pull 暂停、逐块 ACK、首片/扣住首 ACK/start post 后取消、PNG/JPEG 截尾失效及错误后恢复通过。最大 DATA 为 64 KiB，观测最大活动 Worker 为 1，全部终态之后 terminate 再释放模块，最终为零；25 ms 无迟到消息只证明该观察窗，不证明物理 heap 或进程/GPU 归零。详细身份、C 计量、原始报告 SHA 和复验命令见[正式 Worker 证据](verification/long-image-codec.md)。Web Static Assets / Native host 内置材料接线及去重已有构建回归，Native 执行、Source/Protobuf/Reader、tile 缓存/LOD 与真机峰值仍未验，产品 16 Mi 像素门保持原状态。

## 内部 graphics 二进制与预算

2026-11-03，Bitmap、两套 ImageDecoder 和字体输入已将整图正文改为不超过 64 KiB 的 JSO 字节块，小 JSON 只传控制与 handle。尺寸查询先用锁定的 image-dimensions 解析至多 1 MiB 头部，不为 bounds 完整解码。账本分别覆盖可见 payload、surface、decoder/Frame、字体、临时副本和不可中断任务的工作预留；Source 持有的 Bitmap/decoder/Frame 不因普通调用结束被扫描删除，取消与迟到结果保留相应所有权直到任务真正退出。

新增流式 Java oracle 与原 DTO/HTTP/两套图片 oracle、16 个正式图形 Java 类 javac、113 项 runtime-host 测试及严格类型检查通过。Codex 内置浏览器 Chromium 156 的真实 Canvas 门通过；TeaVM 0.16.0 实际 Java→JSO→Canvas oracle 通过 131,079 字节分块往返、同步/异步 Java 异常、fiber bounds、Bitmap pixels/raw/PNG、region sample 别名与 Java Frame lease，显式释放后图形账本归零。独立 harness 初次遗漏正式构建器的 Android 重复类裁剪曾报 Stub，修正 harness 后复跑通过，未改扩展业务代码或原始 JAR。

预算合同、范围和复验入口见 [图片资源内部图形桥](IMAGE-RESOURCES.md#source-内部图形桥)。这是图形桥和受控 codec 的分项证据，尚需新 host 输入的真实 AOT、处理/解密源、移动环境及实际进程/GPU 峰值。Cache 与普通 File 的二进制正文、事务和各自预算已分阶段通过机制门，合计 namespace 预算及产品环境仍待汇合；图形账本不代表整个 Worker 的硬上限。Bitmap 自然回收和活 owner 的独立证据见[生命周期记录](verification/bitmap-lifetime-runtime.md)。

## F3 iOS 模拟器 HTTPS 机制

[实测摘要](verification/runtime-evidence.md) 记录 iOS 26.4 Simulator / Xcode SDK 27.2 在本地受信 HTTPS 下的机制验证：256 KiB、4 MiB、16 MiB 二进制，Worker 处理生成的 PNG，以及 16 MiB 下载启动后立即取消。正文走 `Worker → transferable ArrayBuffer → Blob URL → WKWebView.startDownload → WKDownloadDelegate → 受管临时文件`，只用小型控制消息；独立原生摘要、PNG 尺寸、发送方脱离、文件/Blob 释放与最终空资源目录检查通过。

iOS 临时独立工程与原始本地输出已归档到被忽略的研究目录，仓库只保留摘要。该次实测使用专用模拟器及临时受信 localhost 证书，没有跳过系统 TLS 校验。当时 `flutter_inappwebview` 未直接暴露所需 `startDownload` 受管文件链路，尚无产品薄扩展；这份历史机制证据不是 Flutter 产品图片桥，也不是物理 iPhone、生产 HTTPS/Access、任意阶段取消、首图性能或进程/GPU 峰值验收。

## Native 受管文件产品机制

2026-11-03 已接入正式 NativePlatformRuntime、资源所有权表、iOS WKDownload 文件桥与 Android 固定六槽 ArrayBuffer sink。iOS 26.4 Simulator / Xcode SDK 27.2 在正常受信 localhost HTTPS 下，实际 Flutter Headless 握手、唯一 token 绑定、307 控制页规范化、受控 Blob 下载、1,175 字节摘要、Flutter 256×128 解码及取消/释放/目录清理通过。Swift XCTest 11 项、Flutter 45 项、SourceRuntime 23 项和 Native opt-in/图片 manager 的 TypeScript 15 项通过；analyze 无问题，正式产品 iOS 模拟器构建成功。Android 嵌入脚本在该历史阶段仅通过 Node MessagePort 回归；后续实际 WebView 六槽、SQLite 进程重启及双端 readiness 差异见[Native 依赖与运行记录](verification/native-dependencies.md)。

完整合同、工具来源、期限/tombstone/配额和复验入口见 [Native 图片文件](NATIVE-IMAGE-FILES.md)。这证明产品容器与文件交接机制，尚非原版 Source→Native Reader、物理 iPhone、生产 Access、后台恢复或合计峰值验收。绑定与下载回调未确认停止时不会声称成功清理或归还预算。

固定 `a15c030` 的独立工作树进一步完成 iOS 原 Source 文件门：真实 CatalogController/ChapterPageProvider 从 17 项目录进入 3 章/51 页，首、中、末页经原 Source、HTTP v2、WKDownload 和 Flutter 文件解码均为 1200×1691，字节与上游流摘要逐项一致。release 删除文件并撤销所有权；获取中章节关闭、持图容器重建、binding 目录删除和新 generation 重开通过。身份核对与范围见 [原版 Source 分项证据](NATIVE-IMAGE-FILES.md#原版-source-到-native-文件的分项验收)。它仍使用测试身份与模拟器，未证明 Native ReaderScreen 完整交互、生产 Access、真机或峰值。

固定 `d76e8a4` 的新工作树已通过 iOS/Android 正式受管图片机制及真实进程重启的 SQLite 恢复，保留 `5e9e526` 的 iOS interactive 就绪失败及修正依据。iOS 进一步以相同材料的原 xkcd AOT 经正式 CatalogController/ChapterReaderRoute/ReaderScreen 显示两页，实际 frame 后保存末页与完成状态；terminate/launch 后重取原 Source 并恢复。输入是受控 Native 入口与合成 Flutter Pointer，同源受信 localhost HTTPS、隔离 RS256/D1 测试身份。它不证明生产 Access、真机触控、Android Source 或完整主入口日用流程；详细身份与限制见[Native 记录](verification/native-dependencies.md)。

固定 `8eef7b4`（`d76e8a4` 加 `6c2e09c`）的 Android 模拟器进一步通过原 xkcd 正式 ReaderScreen 两页、Source 文字图、显式完成和两次 force-stop 后 SQLite 恢复，最终 route/provider/WebView 退出也通过。修复文件 sink 与 controller 重复销毁 channel 的所有权错误，保留旧失败；最终截图等待正式“本地进度已保存”，与早期 pre-flush 截图分别留证。测试 CA 仅配置在独立 ignored debug App 的 exact localhost，系统 CA 保留，错误 CA/未配置域名均拒绝；不是生产 Access 或真机证据。完整输入、报告与限制见[Native 记录](verification/native-dependencies.md#android-独立-debug-app-的-tlssource-与退出复验)。

## Cache v3 的新材料复验

固定 `31555e8` 的三源新 AOT 已在内置 Chromium 156 通过正式 Source 元数据与图片链：xkcd 两页含原 TextInterceptor 文字图，Arknights 51 页首中末、CuuTruyen 23 页 DRM 引用首中末均解码、释放并关闭会话。输入与完整 EOF 范围见[三源记录](verification/cache-v3-sources.md)；不以此宣称 Cache 命中或取消通过。

同一 Cache 桥及官方 39 组 Worker/suite 字节在 iOS/Android 模拟器均通过 IndexedDB/Web Locks/Worker 机制和最终 dispose，见[移动引擎记录](verification/cache-v3-native.md)。这不替代 Native Java/Source、生产 Access 或真机门。

## Reader 帧调度修复后的复验

固定 `19b65f5`（`31555e8` 加 `5267181`）的正式 Flutter Web release 已在 Codex 内置 Chromium 156 经主入口完成原 xkcd 两章、显式读完与关标签页重开；首次恢复 3318 末页即显示原文字图，未翻页或诊断补帧。原黑屏失败不覆盖，详见[Web 修复后证据](verification/reader-frame-web.md)。同输入 Android / iOS 模拟器也通过正式 Reader 及真实进程重启，原文字图、已保存 / 已读完与最终清理均已核对，见[Native 修复后证据](verification/reader-frame-native.md)。iOS 早期黑截图仍作为视觉失败保留；终态截图等待实际路由过渡完成，并以 OS / Flutter 两种原图核对。以上不声明生产 Access、Source Cache、真机或浏览器进程恢复。

## 正式扩展版本更新与 Native 主入口准备

2026-11-04，固定 `be5c3ed` 的正式 Flutter Web 通过官方 Arknights 1.6.1 → 1.6.2 更新：旧版保存 DREAM 第 3 页，新版重新连接后首次继续阅读即显示同一原图和已保存页位；两版 PageList 均为 51 页且摘要一致，同 principal/namespace、不同 Worker/generation，章节会话与最终 Worker 清理确认。当前静态快照旧清单/正文返回 404；独立审查和完整 90/90 检查点见[版本记录](verification/extension-version-web.md)。新版四次 Cache entry 后仍以真实 200 重新写入正文，不能认定正文复用、304、零网络或本地旧 bundle 缓存清理。

同期正式 Native main 成品、62 份 Dart 和内置材料核对一致，正常 TLS、Secure/HttpOnly Cookie 与真实 RS256 Worker 的九项预验通过；当前 CUA 无法连接 Simulator，App 未安装/启动，UI 保持 `not_run` / `passed=false`。测试服务、模拟器和工具启动的 Xcode 已清理，见[Native 主入口记录](verification/native-main-entry.md)。

## UI 图片职责与分片选型

2026-11-04 当前原型已将 Source 图片交付统一为不透明编码资源；MIME、尺寸、EXIF、完整解码与分片决策移至 UI，Flutter 从实际显示所用 ImageStream 学习尺寸。旧 host 编码页/分片控制已移除，历史证据保持原输入；独立分片库仅候选，退出默认构建与 Web/Native 打包。工程检查、所有权边界与限制见[本轮记录](verification/ui-image-boundary.md)。候选算法尚无相对 Flutter 直接解码或平台区域解码的同条件真机性能依据，下一步先建立 UI 直接解码基线；不能用有界缓冲、WASM heap 或正确性证明性能优越。

阅读外观与输入预设沿用正式设置确认链路，协议与真实 D1、受控数据/组件以及实际平台证据分别记录，见[本轮设置记录](verification/reader-appearance.md)。

完整显示/适宽/适高与原图二维位置、视口锚沿同一正式设置和进度链路实现，协议、真实 D1、受控客户端及平台门分别见[适配记录](verification/reader-fit.md)。

同步裁白已接入同一正式设置链路，真实 PNG 的 Flutter 解码与默认 Reader 路径、资源所有权及独立平台限制见[裁白记录](verification/reader-crop.md)。

## 尚未通过的门槛

- Cloudflare 签发的真实 Access JWT 正向 Source 动态请求、登录回跳/cookie 失效与原生恢复。
- 更广 Source 的 Web/Native 冷热 Cache、真实 Source 截断 / 取消、版本更新后的 Cache 正文复用与普通文件、Native 版本/身份切换；xkcd Web 与双端 Native 元数据 fresh Cache 及实际容器重建后的复用已单独通过，但浏览器/App 进程重启未验；Cache 跨目录 namespace 39 组及受控 ABI 组合存储/manager 切换不能替代这些剩余产品门。Web 正式原 Source 的身份 A→B→A、304 后正文复用与上述版本更新续读分别保留其实际范围。
- 正式 Native 主入口人工操作、后台恢复与更多原 Source 的 Native 验收；原处理源重复/取消及更多真实解密源覆盖。
- 3–5 个未修改原版源完整章/下一章、物理设备触控、超长图、移动首图与合计峰值。
- 自定义封面的独立客户端双向读回、实际 Native Cookie/Access、进程重启、生产私有 bucket/部署与远端清理；实现及数据组件通过不能替代这些门。
- P1 完整书架/分类/设置和日用流程、P2 同步、P3 用户扩展/迁移、P4 覆盖与优化；已有本地进度分项不能替代完整 P1。

CI 已配置统一检查，远端运行结果需由对应提交确认。以上工程与探针证据不表示 P0 或后续阶段通过。
