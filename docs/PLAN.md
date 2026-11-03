# Karuyomi 实施计划

来源：[设计 Cloudflare 漫画阅读应用](codex://threads/01a19624-4303-7c91-b3fb-3bc110136ca9)。2026-11-03 将该聊天最终采用的设计迁入本仓库。

## 已确定的方向

- Flutter / Dart 负责 UI 与阅读核心；iOS、Android 原生优先，桌面使用 Flutter Web。
- TeaVM 0.16.0 JavaScript backend / release9 是冻结基线。Web 通过 JS interop 直连 Web Worker；原生通过系统 WebView 控制页连接同版 Worker。
- Dart `SourceRuntime`、版本化协议和公共 JS 宿主共享；图片使用可获取、取消、释放的独立资源通道。先验证 iOS，不以整图 Base64 或 JSON 代替图片桥。
- 单 hostname、单 Cloudflare Worker。公开 Flutter shell 与 `/runtime/`；全部后端、私有产物和个人数据位于 Access 保护的 `/api`、`/api/*`，Worker 再校验 JWT。
- 客户端共享运行时材料在 Web 作为静态资源交付，在 Native 随应用打包；每包 AOT 与共享材料分别管理。JAR、Maven、Android SDK 属于构建依赖，不下发客户端。
- 后端沿用 pnpm、TypeScript、Hono、Zod、jose、D1/Drizzle、私有 R2、SQLite Durable Objects。Pub 管 Dart 依赖；Java/Maven 工具链与依赖材料由正式锁文件校验。
- 首版只保留书架、浏览、在线阅读、基本进度、同步和源管理。更新、离线下载、历史统计、追踪、本地漫画、备份、应用内账号与隐私模块不预建。

## 当前实施状态

2026-11-03：工程已从脚手架进入 P0 实现。下列能力有源码、分项测试或机制探针；仍未汇合成可完整阅读的产品链路，P0 尚未通过。

- **P0-A 公共宿主。** release9 已校验导入并内化为项目 Java/桥/构建工具；真正上游通过 submodule 与兼容补丁追踪。原扩展 JAR 不修改；依赖、ZIP、构建副本与产物留在忽略的本地目录。固定 TeaVM 0.16.0 JS backend，按包输出带 hash/ABI/版本的私有清单。MangaDraft 历史原版基线与产品实现都已真实编译。
- **Java Source 边界。** `hostInvoke(sourceId, operation, argsJson)` 支持热门、最新、搜索、详情、章节、页面六项操作，返回完整列表与 DTO，显式传入漫画/章节引用；Source ID 和章节 Long 日期以字符串跨语言保存。JVM oracle 已覆盖长列表、元数据、顺序与引用校验；六项边界可用不代表全部在线语义已实测。原 JAR 字节码已确认 MangaDraft 普通文本搜索未把关键词加入 catalog 请求，这是原版行为，不是宿主漏参。非默认 filters/preferences 和远程脚本能力尚未开放。
- **Web / Dart 控制链。** JS 验证私有清单、脚本与资源后加载真实 TeaVM，管理串行调用、generation/build 隔离、取消/超时和销毁。真实 Chromium 已初始化 MangaDraft 并验证显式引用错误；经真实 workerd 桥和测试 JWT，热门/最新/搜索各返回完整列表，详情/章节遇到源站 Human Verification 挑战并明确失败，pages 未伪造。`ready.sourceReady: false` 只表示控制握手；成功 `open` 以真实 Source ID 与清单一致为条件。Dart 协议层、Web JS interop、原生受管 WebView 控制与可见登录代码已接入，原生真机与 Access 会话恢复仍待验收。
- **资料浏览与阅读核心。** Flutter 已接构建/Source 选择、热门/最新/搜索分页、详情与章节。独立 Dart 阅读核心及 `ReaderScreen` 已实现单/双页、RTL、竖向/Webtoon、缩放、稳定逻辑锚与有界资源窗口。产品 `acquireImage` 仍明确不支持，章节暂不可读，ReaderScreen 尚未接入实际 Source 导航；书架和进度持久化仍未实现。
- **API 与部署准备。** Worker 已实现 Access JWT 再校验、固定 origin/写请求边界、D1 构建注册、私有 R2 流式产物、Range/HEAD 与按构建网络白名单的临时 v1 桥。本地与云端均已注册真实 MangaDraft e350 产品构建。2026-11-03 已部署 `karuyomi.wybxc.cc`（Worker version `402471fe-f113-4272-89ae-ddbe064289b5`），云端 D1 迁移通过。Access 应用及本人策略覆盖 `/api`、`/api/*`；公开页面已渲染，匿名 API 已确认跳转 Access 登录。生产登录成功后的私有交付与 cookie 恢复仍待验收。
- **独立 P0-B / F3 探针。** TeaVM JSO 的有界双向字节复制、fiber 等待/取消和 Worker 所有权转移已在 Chromium 实测。iOS 模拟器已在本地受信 HTTPS 下验证 Worker → ArrayBuffer → Blob → WKDownload → 文件及取消/释放。两者都是独立机制证据，尚未接通产品 HTTP/Okio/图片通道；物理 iPhone、生产 HTTPS/Access 与进程/GPU 合计峰值未验证。

当前证据与正式回归入口见 [VERIFICATION.md](VERIFICATION.md) 和 [TeaVM 说明](../runtime/teavm/README.md)。独立机制研究只保留验证摘要，临时工程存于被忽略的本地归档，不作为产品源码或发布工具提交。`docs/design/` 的冻结设计副本继续保留，不随工程进展改写。

官方源码发现 1,448 包；[包体分析](AOT-SIZE.md)已确定首次方案：共享材料在 Web 静态 / Native 内置交付，每包 Release 使用确定性 gzip，保留 TeaVM `ADVANCED` 与现有服务。逐包输出只含私有 AOT，材料与压缩恢复契约已通过回归；发布输入已固定到 `8dc22e3`，首两份代表包已从本地发布到私有 Release，并生成未完成的 baseline 索引；现有项目代码已统一格式化并接入 prek；格式化后的 host 使用新输入指纹，固定提交后重新规划可恢复的全量队列，不覆盖已发布身份。MangaDraft 与 Arknights Comics 的此前构建通过真实浏览器初始化，在线兼容性未据此通过；新发布默认仍为 `compiled_unverified`。增量 CI 保留缺失初始基线的保护，首次全量不占用 CI。

## 后续顺序与验收

| 阶段 | 保留的范围与验收重点                                                                              | 当前剩余工作                                                                                                          |
| ---- | ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| P0-F | F1 Web DTO；F2 Access 与容器恢复；F3 优先 iOS 字节正确、有界内存、取消释放；F4 真实阅读           | Web 完整 DTO 联调；真实 Access/cookie 与原生恢复；将独立 WKDownload 机制接入已有 WebView 的薄插件扩展；图片与真机验收 |
| P0-R | 分页/长条、单双页、RTL、缩放、逻辑位置、旋转恢复、图片窗口与真机交互                              | 真实 Provider 与导航汇合、超长图降采样/分片、移动触控和实际内存/首图测量                                              |
| P0-A | 项目运行时与上游补丁；完整 DTO、显式引用、按包 AOT、哈希/ABI、私有交付、执行槽、文件与 HTTP Cache | 多源语义与同版对照、存储重启/取消/版本切换、正式私有交付及 Access 验收                                                |
| P0-B | 同版固定输入对照、无整段 JSON/Base64、流控、取消、缓存与异常语义                                  | 独立字节门已过；实现 v2 分帧和 Java/JS/Worker 两段二进制正文，再做缓冲/取消/语义回归                                  |
| P0-C | 3–5 原版源、请求头/图片处理、完整章与下一章、真实 Workers/Access、移动首图与合计峰值              | 当前尚未汇合；以真实 Source 图片资源串起资料、章节、阅读器和进度，不绕过插件处理                                      |
| P1   | 书架/详情/分类/阅读设置/进度/书签、重启恢复、网络错误与移动交互                                   | 完整日用流程与本地/服务端持久化；当前资料界面和阅读组件不等于这一阶段完成                                             |
| P2   | 幂等增量、revision、reset epoch、断网并发不倒退                                                   | 同步协议、业务表与多设备冲突/恢复验收                                                                                 |
| P3   | 手动安装/升级/回滚、筛选/preferences、迁移预览与保留原条目                                        | 当前构建注册只作工程入口；用户扩展管理、筛选和迁移流程仍待实现                                                        |
| P4   | 按源/版本/平台/出口记录兼容性、性能和可访问性                                                     | 持续覆盖、真实移动性能与可访问性验收，不以桌面或模拟器数字替代                                                        |

P0-F / P0-R / P0-A 可以独立推进，在 P0-C 合流；不重新比选 UI 框架或执行引擎。

## P0-B 下一步落点

1. **保留对照。** 当前产品 v1 桥仍为文本/Base64 基线；研究代码内化后按本项目维护，真实第三方上游通过 submodule 固定。[历史验证要点](verification/runtime-evidence.md) 保留 64 KiB 内显式复制、fiber 恢复及原版挂起/产品回调修复的对照结论。不假定零拷贝，也不把模拟 supplier 取消当作上游 HTTP 取消。
2. **定义并校验 v2 帧。** 在 `packages/contracts` 与相邻协议测试固定媒体类型/版本、`META → DATA* → END`、有界 `ERROR`、字节序与总长度；缺 END、截断、未知版本和超限必须失败。沿用完整设计的初始预算：META/DATA 各最多 64 KiB、每响应队列最多 4 块、请求正文最多 8 MiB、响应正文初始最多 64 MiB，之后依据移动实测调整。
3. **替换服务端正文路径。** 在 `apps/api/src/http-bridge.ts` 按版本区分基线与 v2，让 Worker 读取上游 `ReadableStream` 后逐块输出；保留域名白名单、逐跳重定向校验、重复 Cookie、压缩响应、HEAD/204/304/206 及 Access 边界。大正文不经过整段 `text()`、`arrayBuffer()` 或 JSON/Base64。
4. **实现 JS / Java 消费端。** 从 `packages/runtime-host/src/teavm-driver.ts` 接出按会话 `open → read(handle,maxBytes) → close/cancel` 的二进制传输，handle 绑定 requestId/generation；在产品 Java `Bridge` / `BrowserCall` 覆盖层包装 Okio Source / ResponseBody。消费速度决定读取速度，取消、关闭、超时和执行槽销毁都释放 reader/队列并终止上游；原 JAR 的业务请求保持不变，不新增云端 body-token 正文端点。
5. **与图片资源汇合。** 验证原插件请求头和图像处理后的字节，再接 Java 图片入口、JS 可取消/释放的资源 handle、Dart `PageProvider` 与受管原生临时文件。iOS 在已有 WebView 上补公开 `startDownload` 和专用 delegate 的薄插件扩展，覆盖 ID/代次、限额、取消与释放；不以原图 URL 或 JSON 整图替代。
6. **完成同版回归与测量。** 固定输入比较 v1 / v2 的逐字节摘要和原 Source 结果，覆盖空/二进制/UTF-8、表单/multipart、重定向、Range、Cookie/cache、压缩、半途取消与截断。再测慢消费者的队列上界、256 KiB 至 16 MiB 正文与图片处理链，区分桥缓冲、插件主动整段读取以及进程/GPU 合计峰值。达到这些门槛后才能判定 P0-B，并继续 P0-C。

## 完整设计副本

1. [主设计](design/mihon-web-design.md)：范围、部署、运行时、API/Access、数据与发布门槛。
2. [Flutter + TeaVM 接入](design/flutter-teavm-integration.md)：当前采用路线的实施依据。
3. [技术栈与阅读器](design/technology-stack-and-reader.md)：保留通用要求；其中 React/RN 选型已被 Flutter 替代。
4. [跨端框架评估](design/cross-platform-framework-evaluation.md)：历史决策记录。
5. [运行时历史评估](design/runtime-evaluation-history-2026-11-02.md)：历史研究证据。

副本仅将五份文档之间的绝对链接改为仓库内相对链接；研究材料的本机路径和历史状态原样保留。原文与副本 SHA-256 记录在[设计文档来源](verification/design-provenance.md)。当前工程状态以本页和仓库 README 为准；历史“未创建工程”描述对应原聊天当时状态。
