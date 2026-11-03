# 实施验证记录

2026-11-03，本地 macOS。Flutter 3.47.5 / Dart 3.13.4、pnpm 12.6.0；仓库固定 Node 24.15.0，本轮也使用 Node 26.5.0 执行检查。TeaVM 固定 0.16.0 JS backend，验证 JDK 为 Oracle GraalVM 25.0.4、Maven 3.9.11。下表区分代码/分项测试、独立机制探针与尚未完成的产品验收，不以测试总数作为能力证明。

## 工程与代码验证

GitHub 已确认 `Wybxc/karuyomi` 为公开仓库。gitleaks 8.30.1 对截至 `c1c9e7f` 的全部 Git 历史扫描，10 处命中经核对均为文件 SHA-256（8 处）和公开 Access AUD 标识（2 处），未发现实际凭据。当时的 Release 资产清单为 AOT、清单/构建记录与锁定的运行时构建材料；原始扫描报告留在忽略目录，不写入源码。

公开 Release 的浏览器下载门未通过：内置浏览器对下载入口与最终 CDN 的普通 GET/Range 均无法读取正文，响应缺少 CORS 许可；API 对照另遇匿名限流。用户已决定改为全客户端最新版 Static Assets 权威分发，取消扩展 Release 发布，证据见[公开 Release 下载门](verification/github-release-delivery.md)。现已删除 90 个扩展/索引 Release 及对应 tag，GitHub 仅保留锁定的 `teavm-runtime-release9-v1` 构建依赖；旧扩展发布工作流在 baseline 验证期间保持停用。当前两包代表快照已完成真实 AOT、内置浏览器初始化和线上下载检查，全量 baseline 尚未完成。

| 范围              | 已有证据                                                                                                                                                                | 复验入口与限制                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 协议 / TypeScript | 生成版本一致性、严格类型检查，JS Worker 与 API 边界分项测试通过                                                                                                         | `pnpm check`；测试覆盖协议/ABI、hash/预算、串行与代次、取消/超时、登录响应及错误分层   |
| 运行时桥          | Codex 内置浏览器执行真实 Worker、WebCrypto、npm Zstd WASM、Canvas、IndexedDB、隔离与重启持久化均通过                                                                    | [桥验证](verification/worker-bridges.md)；不等同于 Source 在线或图片阅读验收           |
| Dart / Flutter    | source_runtime、reader_core 与 app 的静态分析、协议/布局/调度/浏览/阅读组件测试分项通过                                                                                 | `pnpm flutter:check`；测试 Provider/渲染夹具不等于真实 Source 或真机                   |
| 构建与静态入口    | 已完成本地 JS 宿主、Flutter Web release、同源资源组装及 Wrangler dry-run；公开 shell 与控制页可加载                                                                     | `pnpm build`、`pnpm dev`；dry-run 不部署，也不证明生产 Access                          |
| 静态分发 / D1     | 最新索引/清单/gzip、API 正文路由移除、D1 仅网络政策；本地真实 workerd 静态路由和政策继承已验证                                                                          | `node apps/api/test/workerd-probe.ts MANIFEST ARTIFACTS`；受控夹具不是 Source 在线证明 |
| JWT / API         | 本地 RSA 密钥真实签名测试覆盖 issuer、AUD、本人邮箱/可选 subject、过期/伪造凭据、固定回跳、路径规范化与 API 不落入 SPA；静态正文绕过 Worker；动态请求按 D1 域名政策授权 | `pnpm exec vitest run apps/api/test`；测试签名不是 Cloudflare 签发的生产会话           |
| 阅读核心          | 单/双页、LTR/RTL、封面/横图独占、竖向/Webtoon、缩放/翻页、逻辑锚与布局恢复、取消/释放确认和迟到资源清理                                                                 | `pnpm flutter:check`；窗口预算为实现约束，估算解码像素不等于实测进程/GPU 峰值          |
| 设计溯源          | 初次导入摘要记录在[设计文档来源](verification/design-provenance.md)                                                                                                     | `docs/design/` 已解除冻结，摘要不用于声称当前文件仍是初始副本                          |

历史私有交付实现曾在本地与云端注册构建 `release9-mangadraft-product-e3505206005c25f69b92`：7 个私有产物，共 3,957,861 字节，云端查询状态为 verified。登记前逐文件校验长度/hash，构建与产物关联只在完整写入后可见。本地真实 workerd/D1/R2 加 RS256 测试签名探针已检查 manifest/list、全部 R2 SHA-256、HEAD/304/Range/416、缺 JWT/错误 AUD/错误 host 及整批冲突回滚，见 [API 探针](../apps/api/test/README.md) 与 [证据](verification/runtime-evidence.md#通过的分项与限制)。测试入口仅信任本次生成的公钥，产品没有鉴权绕过。

## 执行器与第三方库直接接入

2026-11-03，固定 Node 24.15.0 下完成 execa 迁移与 `tools/lib/` 删除。调用点直接使用 execa、json-stable-stringify、write-file-atomic、is-plain-obj、fflate/tar/yauzl、diff 和 get-stream；没有将通用包装换目录恢复。dependency-cruiser 检查 134 个模块、485 条依赖通过，禁止重新导入 `tools/lib/`。全库 `pnpm format`、`pnpm format:check` 与 `pnpm check` 通过，包含 256 项 TypeScript 测试、真实本地 D1 CLI、归档/补丁/静态分发及受控 origin 的 workerd HTTP v2 回归。

执行器回归真实运行 Unicode/元字符 argv、10 MiB 双流日志和过滤后的环境；checkpoint 校验失败保留旧内容，原子替换保留 0600 权限、末尾换行且无临时残留。41 项扩展发现/流水线/runner 回归包含 SIGINT/SIGTERM、正常退出仍有继承或独立 stdio 的后代，以及真实锁被删除后的失锁检测；后代停止后才允许锁释放和后续状态操作。Cloudflare 部署领域函数的 9 项无网络 CLI 回归覆盖合并输出正好 512 KiB UTF-8、两路总字节溢出、凭据脱敏、取消后独立恢复，以及正常退出和取消时 TERM-resistant 后代在函数返回前停止。这些测试没有重新执行线上权限探测或部署。

同期接入唯一 `.proto` 与 Buf，Protobuf-ES/Dart 官方生成模型用于正式 API、Source/Worker 与 Web/Native 控制边界；`pnpm generate:check` 检查生成文件全集和字节，9 项实际 TS↔Dart golden 覆盖 ProtoJSON/二进制、oneof、可选字段、精确 memo 数字文本及业务预算。`pnpm flutter:check` 的静态分析及 71 项测试通过；`pnpm build` 完成宿主、Native 材料、Flutter Web release、空扩展索引组装及 API Wrangler dry-run。Java DTO、HTTP body、图片和 Locale oracle 也通过。复验范围和命令见[协议计划](plan/cross-language-protocol.md)与[工具计划](plan/tooling-processes.md)。

当前控制身份为 host ABI `karuyomi-source-host-v3` / protocolVersion 2，HTTP bridgeVersion 仍为 2。浏览器探针入口已迁至单一 control 和正式生成 codec。固定 `6e08ec9` 后，原版 Arknights Comics 已重新 AOT，并在 Codex 内置浏览器通过初始化、真实 Source 元数据和首中末图片门，见 [v3 运行证据](verification/protocol-v3-runtime.md)。Native Reader 界面、运行中取消与当前 v3 部署仍须分项验收。生产 Access 正向 bootstrap 的单独证据见下文。下文 v2 图片和 v1 部署证据仍保持原身份；冻结 `022d828` 全量未改动，不能把其产物装配进当前客户端。

同日将正则供体类命名从补丁移入构建生成步骤，使用 `java-parser` token 位置保留原排版与字面量，再应用行为补丁；全部 13 份生成 Java 与拆分前逐字节一致，原输出摘要未改。回归覆盖刻意保留的上游类型转换、Lexer 引用与继承关系、字符串/文本块和注释不误改，以及源码/上下文/结果漂移拒绝。`toolchain/license.txt` 同时改名为 `android-sdk-license`，仅更新锁中的路径，41 字节内容与摘要不变。

## Android 普通文本布局分项

2026-11-04，项目 owned `TextPaint`/`Layout`/旧构造器 `StaticLayout`、真实 Canvas 字体指标与有界布局已接入，并补齐 TextInterceptor 使用的 HTML 字符串投影。Codex 内置浏览器 Chrome 156 通过 Canvas 五组机制门及同份 Java 101 项检查；独立固定 API 35/Robolectric 4.17 的 Android NATIVE oracle 同样通过 101 项，并断言真实 native shadows 和固定 instrumented SDK 身份。两端默认字体输出分别为 1000×140 与 1000×190，不声称高度或 PNG 像素等价。新增 CRLF 场景曾在 TeaVM 失败，修复后完整重跑通过；浏览器资源账本均归零。

这些证据覆盖 HTML plain-string、UTF-16 range、padding/spacing/行宽、普通文本绘字与预算机制，不能替代新 host 下原 xkcd TextInterceptor 第二页、生产 Access 或 Native 应用验收。旧 host 的 Android Stub 失败证据保留。正式入口、原 Android plain 状态反向断言及未验范围见[文字布局记录](verification/text-layout-runtime.md)与[计划](plan/text-layout.md)。

## Cache 生命周期与有界正文分项

2026-11-03 至 04，正式 Cache 桥使用 `idb@8.0.4` 将正文拆成最多 64 KiB 的二进制块，metadata 与正文分开，snapshot pin 保留被替换/清空后仍在读取的完整 body；可见预算和计入 staging/retired 的 allocated 预算分别限制。Codex 内置浏览器 Chromium 156 通过十七组真实 Worker/IndexedDB/Web Locks 门，覆盖 editor 死亡 owner 回收、handle/CAS/generation 隔离、put abort、close/delete 与在途 begin、分块 snapshot/EOF、metadata 不读 chunks、块与目录预算、预算不足时原子回滚，以及 close/delete 原事务失败后按 owner/handle 清理。机制与故障门不代表完整 Source 或峰值验收。

共享 `CacheScenarios.java` 分别在官方 Maven 未适配 OkHttp 5.5.0 与真实 TeaVM 0.16 产品 Cache/BrowserCall/二进制 JSO 中执行。131079 字节冷/热命中、304 合并、no-store、Cookie Vary 和打开 snapshot 跨 evictAll 的正文摘要一致，均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`；计数均为 11 次请求、8 次网络、4 次命中、5 次成功写入。原 JVM 断言 Cache/OkHttpClient CodeSource，避免 seed 同名适配 JAR 将请求送入 BrowserCall。Java CacheSink 的 19 项 JVM 边界检查同时通过，存储写失败仅丢弃缓存副本，不吞网络读取异常。

上述 TeaVM 网络使用受控 workerd origin，尚未验收新 Cache 下的真实 Source、生产 Access、reader 死亡/损坏正文/中途取消或 Native；普通文件与跨目录 namespace 总预算仍待实施。复验与边界见[Cache 记录](verification/http-cache-runtime.md)和[存储计划](plan/runtime-storage.md)。原 JVM oracle JAR SHA-256 为 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52`。

## 阅读连续性分项

2026-11-03，阅读路由已接 Source 原序/反序、漫画作用域章节键与上一章/下一章控制；不按编号排序或丢弃重复 URL。每次切章等旧 Reader 的 scheduler、图片 pin 与 provider 清理 ACK 后才挂载新叶；下一章 pages 迟到和新 provider 在下一帧挂载前退出均被关闭。`chapter_sequence_test.dart` 与 `chapter_reader_route_test.dart` 覆盖空/零/小数编号、重复章的快照键、跨漫画/Source 隔离及延迟清理/退出竞争；相关 26 项组件回归和 Flutter analyze 通过。完整 `pnpm flutter:check` 通过三个包的静态分析及 15/23/50 项测试，完整格式检查通过。此时尚无背景下一章准备、Drift 落盘、真实 Source 章节连续阅读或真机证据，不据此标记 P0/P1 通过。

## 新图形宿主与生产 Access 分项

2026-11-03 至 04，固定 `15a3900` 后六包本地 AOT 通过；Codex 内置浏览器在新材料下通过 Arknights 首中末直图，以及 CuuTruyen 23 个真实 DRM 页中的首中末 Bitmap/Canvas 重排。Little Tyrant 与 Philia Scans 初始化成功，但元数据请求均被各自站点 403 拒绝，图片未测。MangaDex 原包 61 个 Source 初始化成功，英文 Source 的列表链因 HTTP 超时失败，图片未测。xkcd 元数据及直图成功，但原 TextInterceptor 文字图片遇到 Android Stub，完整图片门失败。具体输入身份、必要数量和限制见[Source 记录](verification/graphics-source-runtime.md)。这些测试使用隔离 D1 和测试签名，仍不是生产 Source 或 Native 证据。

2026-11-04，用户在 Codex 内置浏览器完成真实 Cloudflare Access 登录，实际回跳 `https://karuyomi.wybxc.cc/api/bootstrap`；页面返回配置的本人邮箱、非空 subject、expiresAt 与 `stage=p0`。这一项证明生产正向登录及 bootstrap，未导出登录 Cookie/JWT。线上响应仍为旧部署 `protocolVersion=1`，不能据此认定当前 v3 已部署；Source 动态请求、会话过期/恢复与 Native 登录另验。历史匿名拦截及未登录状态的记录保留其当时范围。

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

## 当前静态分发分项

固定 `022d828` 的两包代表快照已部署到 `https://karuyomi.wybxc.cc`，Worker version 为 `1d434d1b-7e30-4668-b458-350e486f3b3d`，快照 revision 为 `22378bbcb89d40f5a0397c5098310072`。生产 D1 `0002` 迁移已成功；公开 index/state 字节与本地候选一致，两个 gzip 的 MIME、无 HTTP Content-Encoding、immutable 缓存与编码/原文双 SHA 均通过实际匿名下载验证。前一 `1bfc97f` 的两个清单和 gzip 地址均已实际返回 404，确认当前快照只保留最新版本。六份共享材料的长度/摘要通过，未知扩展和 Native 内置资源路径返回 404，匿名 `/api/bootstrap` 仍跳转到原 Access 团队。bootstrap 尚不完整，不能启用初次全量 CI；当时只有匿名拦截证据，后续生产登录分项见上文。

注册 CLI 已改为只校验当前 index/manifest 与材料元数据，不读取 bundle 或重复计算摘要；原 `--artifacts` 参数已移除。锁定 Wrangler 的标准 pnpm 补丁修复 D1 `--file --json` 夹带上传进度的问题，仍保留严格 JSON 解析和 SQL 失败拒绝。本地真实文件写入/查询/错误 SQL、30 项政策回归与 13 项真实 workerd 门均通过；修复后的正式远端同步也通过：当前两包只继承 MangaDraft 原有 `www.mangadraft.com` 策略，Arknights 保持未授权。线上快照确认后，本地 checkpoint 已保存，首次全量标记仍为 false。

最新静态交付代码已覆盖：严格 TS/Dart 当前索引、gzip 编码/原文字节各一次传输摘要、有界解压与取消；资源组装只复制当前索引可达文件，拒绝混合 index/state、损坏 gzip 与显式缺失快照。流水线离线回归包含源码/依赖/host 指纹、同失败不重试、扫描失败保留成功、运行时不匹配排除、删除退役、首次本地初始化、checkpoint 锁、真实进程树信号取消，以及远端确认后才提交状态。

真实本地 workerd + D1 + Static Assets 门验证了公开索引/清单/gzip 不进入入口 Worker、gzip MIME 且无 HTTP Content-Encoding、匿名静态下载、缺失扩展 404、应用 shell 与控制页规范化、移除的 API 返回 404、RS256/AUD/host 拒绝、元数据事务回滚，以及部署后只继承既有包的明确域名政策。新包仍未授权，退役包政策删除。此次夹具是受控小脚本，尚未代替当前真实 TeaVM AOT 初始化或生产 Access 验收。正式入口见 [API 回归说明](../apps/api/test/README.md)。

## P0-A 真实构建与 Web 初始化

2026-11-03，TypeScript 迁移后的当前 6 份共享材料已通过实际 workerd 检查：摘要、长度、JavaScript/WASM MIME 和 public immutable 缓存头正确。当前逐包 AOT 输出唯一 gzip bundle；D1 仅注册网络授权元数据，静态材料按受信 host catalog 核对。原型不保兼容，旧桥副本与旧 raw 恢复路径已移除；旧固定宿主全量队列已停止，需以当前宿主身份重建。gzip 恢复回归覆盖编码/原文双摘要、长度上界、截断、尾随和拼接流。当前两包真实 AOT 与线上传输证据见上文；全量恢复、客户端实际更新和旧缓存清理仍待验证。正式契约见[共享材料](RUNTIME-MATERIALS.md)与[发布说明](EXTENSIONS.md)。

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

打开脚本输出的 localhost 页面并运行正式 Source 集成回归。它使用真实 IndexedDB、产品 Worker 与 HTTP bridge、隔离 workerd/D1/Static Assets 和 RS256 测试签名；不修改产品鉴权入口。复验步骤见 [集成说明](../apps/api/test/source-metadata-probe.md)，实测状态见 [摘要](verification/runtime-evidence.md)。初始化通过不等于文件/HTTP Cache 重启、升级与取消语义已完成回归。

## P0-B 独立字节与错误探针

[字节机制摘要](verification/runtime-evidence.md) 记录 Chromium 156 上实际编译的 TeaVM JSO 探针：空字节、`00/ff`、全部 256 值、含 NUL/emoji 的 UTF-8、带偏移视图和 64 KiB 随机字节经 `Uint8Array → byte[] → Uint8Array` 显式复制后逐字节一致。它同时验证 64 KiB 限额、复制不别名、retained Java 引用清除、fiber 等待/IOException 恢复、模拟 supplier 取消后无遗留/迟到回调，以及主线程/Worker 双向转移后的发送方 ArrayBuffer 脱离。这里只保留复制与取消的关键门槛；桌面机制结果不外推为手机性能、零拷贝或总堆上限。

[Zstd 错误摘要](verification/runtime-evidence.md) 对照实际编译的原版和产品 `Bridge.zstd`。两者对真实 WASM 无效压缩流都返回 `Truncated Zstd frame`；显式注入 rejected host Promise 时，原版生成代码因局部变量名碰撞抛出 `TypeError` 并等待超时，产品实现改用 `failureReason` 后恢复 Java RuntimeException。历史原版对照保留在本地研究归档。

临时独立研究工程和脚本已移入本机被忽略的 `runtime/teavm/.local/research/`，保留原始本地资料，不进入源码仓库。上面的精简文档记录历史机制证据；正式产品与发布回归需要独立测试，不能依赖临时工程存在。

产品代码现已加入 [HTTP v2](HTTP-BRIDGE.md)：严格帧、Worker 按需响应、JS operation/generation handle、Java Okio Source 与有界上传 Sink。新增协议 38 项及 JS transport 9 项测试；完整 TypeScript 套件 192 项通过。Java 完整 javac 与 `tools/teavm/HttpBodyTest.java` 的 1,051 项断言通过，包括 64 MiB 分块读取与 8 MiB 上传上限（`pnpm teavm:check` 同时运行 DTO 与 body oracle）。真实 TeaVM 0.16 编译 JS 在 Node 的模拟六函数 supplier 下，验证 131,079 字节 GET/POST（00/ff、64 KiB 分块）、空 POST、pending-read 取消、超时、超请求块与 EOF 长度错共七例，handle 最终归零；这仍不是实际 HTTP、浏览器或 Access 验收。

当前构建、注册清单、Java、Worker 和 API 只维护 HTTP v2，旧 v1 传输分支已删除。Java 重新经过真实 TeaVM 编译后的 18 例模拟 supplier 回归，覆盖 GET/POST、空正文、取消/超时、受控重试及错误分类；这些仍是模拟环境证据。

`pnpm test:http-bridge` 已通过真实 workerd 与受控 HTTP origin 的 15 项检查：夹具真正发送 gzip（3,164 字节）与 Brotli（657 字节），解码后均为 131,089 字节且 SHA-256 一致；覆盖 200/206/403、HEAD、重复 Cookie、手动重定向、流式 POST、早响应仍验证上传 END，以及消费取消、请求取消和超时关闭 origin。该门已纳入 `pnpm check`，完整输出留在忽略目录 `.local/probes/http-bridge-v2.json`。它不涉及实际 Source、生产 Access 或 CacheInterceptor；原 Source/cache 同版对照和图片/移动内存链路仍需验收，P0-B 尚未通过。上面的部署版本属于旧版本历史记录，当前代码尚不能据此声称已部署或通过生产 Access 正向会话。

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

`pnpm check`、`pnpm flutter:check` 与产品 Web/API dry-run 构建通过；Java 图片 oracle 对 seed 和正式 HttpSource 两套签名均通过。Web 终端有 encoded/pixel/resource 总预算、头部预检与实际 decode，但内部 Bitmap/ImageDecoder 仍有整图 Base64/readAllBytes 和未协调的总 raster 预算。不能据此声称图片解密/重排、动画/超长图、进程/GPU 合计峰值、Native 受管文件或 P0 已通过。

## 内部 graphics 二进制与预算

2026-11-03，Bitmap、两套 ImageDecoder 和字体输入已将整图正文改为不超过 64 KiB 的 JSO 字节块，小 JSON 只传控制与 handle。尺寸查询先用锁定的 image-dimensions 解析至多 1 MiB 头部，不为 bounds 完整解码。账本分别覆盖可见 payload、surface、decoder/Frame、字体、临时副本和不可中断任务的工作预留；Source 持有的 Bitmap/decoder/Frame 不因普通调用结束被扫描删除，取消与迟到结果保留相应所有权直到任务真正退出。

新增流式 Java oracle 与原 DTO/HTTP/两套图片 oracle、16 个正式图形 Java 类 javac、113 项 runtime-host 测试及严格类型检查通过。Codex 内置浏览器 Chromium 156 的真实 Canvas 门通过；TeaVM 0.16.0 实际 Java→JSO→Canvas oracle 通过 131,079 字节分块往返、同步/异步 Java 异常、fiber bounds、Bitmap pixels/raw/PNG、region sample 别名与 Java Frame lease，显式释放后图形账本归零。独立 harness 初次遗漏正式构建器的 Android 重复类裁剪曾报 Stub，修正 harness 后复跑通过，未改扩展业务代码或原始 JAR。

预算合同、范围和复验入口见 [图片资源内部图形桥](IMAGE-RESOURCES.md#source-内部图形桥)。这是图形桥和受控 codec 的分项证据，尚需新 host 输入的真实 AOT、处理/解密源、移动环境及实际进程/GPU 峰值。Cache/File 的 Base64、整条目复制和存储预算仍属于独立未完成阶段；图形账本不代表整个 Worker 的硬上限。

## F3 iOS 模拟器 HTTPS 机制

[实测摘要](verification/runtime-evidence.md) 记录 iOS 26.4 Simulator / Xcode SDK 27.2 在本地受信 HTTPS 下的机制验证：256 KiB、4 MiB、16 MiB 二进制，Worker 处理生成的 PNG，以及 16 MiB 下载启动后立即取消。正文走 `Worker → transferable ArrayBuffer → Blob URL → WKWebView.startDownload → WKDownloadDelegate → 受管临时文件`，只用小型控制消息；独立原生摘要、PNG 尺寸、发送方脱离、文件/Blob 释放与最终空资源目录检查通过。

iOS 临时独立工程与原始本地输出已归档到被忽略的研究目录，仓库只保留摘要。该次实测使用专用模拟器及临时受信 localhost 证书，没有跳过系统 TLS 校验。当时 `flutter_inappwebview` 未直接暴露所需 `startDownload` 受管文件链路，尚无产品薄扩展；这份历史机制证据不是 Flutter 产品图片桥，也不是物理 iPhone、生产 HTTPS/Access、任意阶段取消、首图性能或进程/GPU 峰值验收。

## Native 受管文件产品机制

2026-11-03 已接入正式 NativePlatformRuntime、资源所有权表、iOS WKDownload 文件桥与 Android 固定六槽 ArrayBuffer sink。iOS 26.4 Simulator / Xcode SDK 27.2 在正常受信 localhost HTTPS 下，实际 Flutter Headless 握手、唯一 token 绑定、307 控制页规范化、受控 Blob 下载、1,175 字节摘要、Flutter 256×128 解码及取消/释放/目录清理通过。Swift XCTest 11 项、Flutter 45 项、SourceRuntime 23 项和 Native opt-in/图片 manager 的 TypeScript 15 项通过；analyze 无问题，正式产品 iOS 模拟器构建成功。Android 嵌入脚本的真实 Node MessagePort 背压/复用/迟到 ACK 回归通过，尚未在 Android WebView 运行。

完整合同、工具来源、期限/tombstone/配额和复验入口见 [Native 图片文件](NATIVE-IMAGE-FILES.md)。这证明产品容器与文件交接机制，尚非原版 Source→Native Reader、物理 iPhone、生产 Access、后台恢复或合计峰值验收。绑定与下载回调未确认停止时不会声称成功清理或归还预算。

固定 `a15c030` 的独立工作树进一步完成 iOS 原 Source 文件门：真实 CatalogController/ChapterPageProvider 从 17 项目录进入 3 章/51 页，首、中、末页经原 Source、HTTP v2、WKDownload 和 Flutter 文件解码均为 1200×1691，字节与上游流摘要逐项一致。release 删除文件并撤销所有权；获取中章节关闭、持图容器重建、binding 目录删除和新 generation 重开通过。身份核对与范围见 [原版 Source 分项证据](NATIVE-IMAGE-FILES.md#原版-source-到-native-文件的分项验收)。它仍使用测试身份与模拟器，未证明 Native ReaderScreen 完整交互、生产 Access、真机或峰值。

## 尚未通过的门槛

- Cloudflare 签发的真实 Access JWT 正向 Source 动态请求、登录回跳/cookie 失效与原生恢复。
- v2 二进制网络/Okio 流控、真实上游取消、文件与 HTTP Cache 同版回归。
- Native ReaderScreen 交互、Android 实际 WebView 和后台恢复；新 graphics 材料的实际 AOT/处理源及更多真实解密源覆盖。
- 3–5 个未修改原版源完整章/下一章、物理设备触控、超长图、移动首图与合计峰值。
- P1 书架/进度等持久化、P2 同步、P3 用户扩展/迁移、P4 覆盖与优化。

CI 已配置统一检查，远端运行结果需由对应提交确认。以上工程与探针证据不表示 P0 或后续阶段通过。
