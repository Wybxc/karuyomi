# 实施验证记录

2026-11-03，本地 macOS。Flutter 3.47.5 / Dart 3.13.4、pnpm 12.6.0；仓库固定 Node 24.15.0，本轮也使用 Node 26.5.0 执行检查。TeaVM 固定 0.16.0 JS backend，验证 JDK 为 Oracle GraalVM 25.0.4、Maven 3.9.11。下表区分代码/分项测试、独立机制探针与尚未完成的产品验收，不以测试总数作为能力证明。

## 工程与代码验证

| 范围              | 已有证据                                                                                                                                                               | 复验入口与限制                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 协议 / TypeScript | 生成版本一致性、严格类型检查，JS Worker 与 API 边界分项测试通过                                                                                                        | `pnpm check`；测试覆盖协议/ABI、hash/预算、串行与代次、取消/超时、登录响应及错误分层    |
| Dart / Flutter    | source_runtime、reader_core 与 app 的静态分析、协议/布局/调度/浏览/阅读组件测试分项通过                                                                                | `pnpm flutter:check`；测试 Provider/渲染夹具不等于真实 Source 或真机                    |
| 构建与静态入口    | 已完成本地 JS 宿主、Flutter Web release、同源资源组装及 Wrangler dry-run；公开 shell 与控制页可加载                                                                    | `pnpm build`、`pnpm dev`；dry-run 不部署，也不证明生产 Access                           |
| D1 / R2           | 迁移已加入构建/产物/关联/网络域名注册表；真实 MangaDraft 产品包已注册本地 D1/R2                                                                                        | `pnpm db:migrate:local`；`scripts/register-build.py` 默认仅输出计划，`--local` 才写本地 |
| JWT / API         | 本地 RSA 密钥真实签名测试覆盖 issuer、AUD、本人邮箱/可选 subject、过期/伪造凭据、固定回跳、路径规范化与 API 不落入 SPA；私有交付校验已注册关联、MIME/长度和 Range/HEAD | `pnpm exec vitest run apps/api/test`；测试签名不是 Cloudflare 签发的生产会话            |
| 阅读核心          | 单/双页、LTR/RTL、封面/横图独占、竖向/Webtoon、缩放/翻页、逻辑锚与布局恢复、取消/释放确认和迟到资源清理                                                                | `pnpm flutter:check`；窗口预算为实现约束，估算解码像素不等于实测进程/GPU 峰值           |
| 冻结设计溯源      | 五份设计副本保留，摘要记录在[设计文档来源](verification/design-provenance.md)                                                                                          | `docs/design/` 未随工程状态改写                                                         |

本地与云端已注册构建 `release9-mangadraft-product-e3505206005c25f69b92`：7 个私有产物，共 3,957,861 字节，云端查询状态为 verified。登记前逐文件校验长度/hash，构建与产物关联只在完整写入后可见。本地真实 workerd/D1/R2 加 RS256 测试签名探针已检查 manifest/list、全部 R2 SHA-256、HEAD/304/Range/416、缺 JWT/错误 AUD/错误 host 及整批冲突回滚，见 [API 探针](../apps/api/test/README.md) 与 [证据](verification/runtime-evidence.md#通过的分项与限制)。测试入口仅信任本次生成的公钥，产品没有鉴权绕过。

## 正式部署与匿名边界

2026-11-03 已成功部署 `https://karuyomi.wybxc.cc`，Cloudflare Worker version 为 `402471fe-f113-4272-89ae-ddbe064289b5`。云端 D1 的两次迁移均通过，e350 产物已 remote 注册。匿名检查得到 `/` 200、`/runtime/host.js` 200，`/runtime/host.html` 307 规范化到公开 `/runtime/host`；Safari 已实际渲染 Flutter 书架与三个导航页签。

Access 本人策略覆盖 `/api` 和 `/api/*`。匿名 `/api`、`/api/bootstrap` 与私有 `/api/extensions/artifacts/<hash>` 均返回 302 到 `wybxc.cloudflareaccess.com` 登录，保持 private/no-store。这里验证的是公开入口与匿名拦截；尚未取得生产 Access 登录成功后的正向 bootstrap/私有产物交付，也未完成登录/cookie 失效与恢复验收。

## P0-A 真实构建与 Web 初始化

2026-11-03 新共享材料链路已通过实际 workerd 检查：当前 6 份材料与旧 e350 的 2 份兼容桥均返回正确摘要、长度、JavaScript/WASM MIME 和 public immutable 缓存头。逐包 AOT 输出只保留私有 bundle；注册仅关联私有产物，静态材料按受信 host catalog 核对。gzip 恢复回归覆盖编码/原文双摘要、长度上界、截断、尾随/拼接流和旧 raw 兼容；本地真实两包字节 roundtrip 通过。正式契约见[共享材料](RUNTIME-MATERIALS.md)与[发布说明](EXTENSIONS.md)。

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
node apps/api/test/source-metadata-probe.mjs PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

打开脚本输出的 localhost 页面并运行正式 Source 集成回归。它使用真实 IndexedDB、产品 Worker 与 HTTP bridge、隔离 workerd/D1/R2 和 RS256 测试签名；不修改产品鉴权入口。复验步骤见 [集成说明](../apps/api/test/source-metadata-probe.md)，实测状态见 [摘要](verification/runtime-evidence.md)。初始化通过不等于文件/HTTP Cache 重启、升级与取消语义已完成回归。

## P0-B 独立字节与错误探针

[字节机制摘要](verification/runtime-evidence.md) 记录 Chromium 156 上实际编译的 TeaVM JSO 探针：空字节、`00/ff`、全部 256 值、含 NUL/emoji 的 UTF-8、带偏移视图和 64 KiB 随机字节经 `Uint8Array → byte[] → Uint8Array` 显式复制后逐字节一致。它同时验证 64 KiB 限额、复制不别名、retained Java 引用清除、fiber 等待/IOException 恢复、模拟 supplier 取消后无遗留/迟到回调，以及主线程/Worker 双向转移后的发送方 ArrayBuffer 脱离。这里只保留复制与取消的关键门槛；桌面机制结果不外推为手机性能、零拷贝或总堆上限。

[Zstd 错误摘要](verification/runtime-evidence.md) 对照实际编译的原版和产品 `Bridge.zstd`。两者对真实 WASM 无效压缩流都返回 `Truncated Zstd frame`；显式注入 rejected host Promise 时，原版生成代码因局部变量名碰撞抛出 `TypeError` 并等待超时，产品实现改用 `failureReason` 后恢复 Java RuntimeException。历史原版对照保留在本地研究归档。

临时独立研究工程和脚本已移入本机被忽略的 `runtime/teavm/.local/research/`，保留原始本地资料，不进入源码仓库。上面的精简文档记录历史机制证据；正式产品与发布回归需要独立测试，不能依赖临时工程存在。

这些探针尚未接入 HTTP v2 分帧、真实网络 reader、Okio ResponseBody 或图片通道。当前 P0-A `/api/bridge/http` 仍为有界文本/Base64 基线；不作为 P0-B 完成标准。下一步实现落点见 [计划](PLAN.md#p0-b-下一步落点)。

## F3 iOS 模拟器 HTTPS 机制

[实测摘要](verification/runtime-evidence.md) 记录 iOS 26.4 Simulator / Xcode SDK 27.2 在本地受信 HTTPS 下的机制验证：256 KiB、4 MiB、16 MiB 二进制，Worker 处理生成的 PNG，以及 16 MiB 下载启动后立即取消。正文走 `Worker → transferable ArrayBuffer → Blob URL → WKWebView.startDownload → WKDownloadDelegate → 受管临时文件`，只用小型控制消息；独立原生摘要、PNG 尺寸、发送方脱离、文件/Blob 释放与最终空资源目录检查通过。

iOS 临时独立工程与原始本地输出已归档到被忽略的研究目录，仓库只保留摘要。该次实测使用专用模拟器及临时受信 localhost 证书，没有跳过系统 TLS 校验。当前 `flutter_inappwebview` 未直接暴露所需 `startDownload` 受管文件链路，产品薄插件扩展尚未实现；这份机制证据不是 Flutter 产品图片桥，也不是物理 iPhone、生产 HTTPS/Access、任意阶段取消、首图性能或进程/GPU 峰值验收。

## 尚未通过的门槛

- Cloudflare 签发的真实 Access JWT 正向私有交付、登录回跳/cookie 失效与原生恢复。
- v2 二进制网络/Okio 流控、真实上游取消、文件与 HTTP Cache 同版回归。
- Java 图片处理到 Dart Provider / Web 资源 / 原生文件的产品通道，以及真实图片进入 ReaderScreen。
- 3–5 个未修改原版源完整章/下一章、物理设备触控、超长图、移动首图与合计峰值。
- P1 书架/进度等持久化、P2 同步、P3 用户扩展/迁移、P4 覆盖与优化。

CI 已配置统一检查，远端运行结果需由对应提交确认。以上工程与探针证据不表示 P0 或后续阶段通过。
