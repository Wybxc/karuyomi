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

## 历史部署与匿名边界

2026-11-03 已成功部署 `https://karuyomi.wybxc.cc`，Cloudflare Worker version 为 `0332ef7a-3d49-47c1-ac41-edbed49bd7fe`。云端 D1 的两次迁移均通过，e350 产物已 remote 注册。匿名检查得到 `/` 200、`/runtime/host.js` 200，`/runtime/host.html` 307 规范化到公开 `/runtime/host`；Safari 已实际渲染 Flutter 书架与三个导航页签。

Access 本人策略覆盖 `/api` 和 `/api/*`。匿名 `/api`、`/api/bootstrap` 与私有 `/api/extensions/artifacts/<hash>` 均返回 302 到 `wybxc.cloudflareaccess.com` 登录，保持 private/no-store。这里验证的是公开入口与匿名拦截；尚未取得生产 Access 登录成功后的正向 bootstrap/私有产物交付，也未完成登录/cookie 失效与恢复验收。

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

固定 `022d828` 的两包代表快照已部署到 `https://karuyomi.wybxc.cc`，Worker version 为 `1d434d1b-7e30-4668-b458-350e486f3b3d`，快照 revision 为 `22378bbcb89d40f5a0397c5098310072`。生产 D1 `0002` 迁移已成功；公开 index/state 字节与本地候选一致，两个 gzip 的 MIME、无 HTTP Content-Encoding、immutable 缓存与编码/原文双 SHA 均通过实际匿名下载验证。前一 `1bfc97f` 的两个清单和 gzip 地址均已实际返回 404，确认当前快照只保留最新版本。六份共享材料的长度/摘要通过，未知扩展和 Native 内置资源路径返回 404，匿名 `/api/bootstrap` 仍跳转到原 Access 团队。bootstrap 尚不完整，不能启用初次全量 CI 或据此声称生产登录通过。

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

## F3 iOS 模拟器 HTTPS 机制

[实测摘要](verification/runtime-evidence.md) 记录 iOS 26.4 Simulator / Xcode SDK 27.2 在本地受信 HTTPS 下的机制验证：256 KiB、4 MiB、16 MiB 二进制，Worker 处理生成的 PNG，以及 16 MiB 下载启动后立即取消。正文走 `Worker → transferable ArrayBuffer → Blob URL → WKWebView.startDownload → WKDownloadDelegate → 受管临时文件`，只用小型控制消息；独立原生摘要、PNG 尺寸、发送方脱离、文件/Blob 释放与最终空资源目录检查通过。

iOS 临时独立工程与原始本地输出已归档到被忽略的研究目录，仓库只保留摘要。该次实测使用专用模拟器及临时受信 localhost 证书，没有跳过系统 TLS 校验。当前 `flutter_inappwebview` 未直接暴露所需 `startDownload` 受管文件链路，产品薄插件扩展尚未实现；这份机制证据不是 Flutter 产品图片桥，也不是物理 iPhone、生产 HTTPS/Access、任意阶段取消、首图性能或进程/GPU 峰值验收。

## 尚未通过的门槛

- Cloudflare 签发的真实 Access JWT 正向 Source 动态请求、登录回跳/cookie 失效与原生恢复。
- v2 二进制网络/Okio 流控、真实上游取消、文件与 HTTP Cache 同版回归。
- Java 图片处理到 Dart Provider / Web 资源 / 原生文件的产品通道，以及真实图片进入 ReaderScreen。
- 3–5 个未修改原版源完整章/下一章、物理设备触控、超长图、移动首图与合计峰值。
- P1 书架/进度等持久化、P2 同步、P3 用户扩展/迁移、P4 覆盖与优化。

CI 已配置统一检查，远端运行结果需由对应提交确认。以上工程与探针证据不表示 P0 或后续阶段通过。
