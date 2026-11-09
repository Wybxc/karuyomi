# 自定义封面验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。自定义封面已接入 Protobuf、Worker API、D1 当前引用、私有 R2、共享 Dart 数据层及正式详情/书架入口；当前状态为**已实现，独立 Web 客户端往返通过；Native、故障与生产仍待验**。合同、上传/清除、对象清理与生命周期设计见[设计](../design/custom-covers.md)。

## 已实测的数据层

`flutter test test/data/ --reporter expanded` 首轮 **102/102 通过**，包含七项新增封面数据回归；原有设置、书架、分类、书签、阅读进度和共享队列回归一起通过。真实终端日志保留在临时文件 `/private/tmp/karuyomi-cover-data-regression.log`，没有把日志复制入库。

新增回归使用正式生成模型、共享 `BusinessStateClient` 和数据组件 supplier，验证：

- 上传和清除共用漫画 CAS；书架取得独立封面描述，源 thumbnail 快照不被改写；刷新源元数据与取消收藏保留封面，清除走无 cover 的 JSON mutation，旧 asset 不再从 supplier 读取。
- 丢失上传 ACK 后，不可变字节、asset UUID、mutation UUID、正文及 CAS 保持不变；同一 client 下重建 repository 和读取状态保留未确认操作，明确重试只确认一次；新编辑和其它漫画写操作不能擅自替换原命令，正常后续进度写入按同一漫画队列运行。
- 远端 CAS 冲突要求读取最新状态后作出新决定；旧成功 ACK 不能复活远端已清除的封面；关闭会话拒绝迟到 ACK，另一 subject 不能取得旧封面；描述和上传字节预算在传输前校验。

自有数据链路、共享 supplier、新 fake 和封面测试的定向严格 Dart 分析无问题；七个负责文件的格式检查及补丁检查通过。以上是数据组件证据，不是实际 multipart HTTP、R2/D1 事务、文件选择 UI、Native Cookie 或生产 Access 证据。

```sh
cd apps/reader
flutter test test/data/ --reporter expanded
```

## 服务端、界面与集中工程

- 合同 11 项、真实 state workerd 32 项、真实 cover workerd 4 项，合计 47 项通过。封面组合验证鉴权身份与当前引用、另一调用方读回、Source 更新保留封面、CAS 单一胜者、set/clear 的旧 ACK 不复活、D1 事务回滚、失败候选及宽限期清理、非法/超限/multipart 重复字段和 JSON 上传捷径拒绝。
- 官方 Vite 构建与 Wrangler harness 2 项通过，实际核对 `COVERS` 的 put/get/delete 和 `cover_assets` migration。正式本地 `db:migrate:local` 应用 0007 后，真实 `pnpm covers:cleanup` exit 0，输出 local/scanned=0/deleted=0/truncated=false；即使空桶，helper 也先查询当前表，缺 migration 会失败。
- 封面 UI 4 项通过：规范化的方向、像素头预算与缩小；480×800 正式详情选择/替换/清除并更新书架；丢 ACK 的原 UUID/正文/字节重试、重开时 GET 503 后仍可重试原操作、CAS 冲突后只读刷新；身份变化后拒绝迟到 picker。相关 browse/library/covers 组合 80 项通过。文件选择由官方平台接口 supplier 驱动，不作为真实系统选择器操作证据。
- 独立 HTTP 传输 7 项通过：实际 `http` multipart 封装的字节与同源身份、下载完整性和不可变结果、错误格式/长度/digest/redirect、声明和流式限额、等待 Cookie 时关闭、超时迟到结果，以及非法输入不发请求。使用成熟库的受控 HTTP supplier，不代表 Native Cookie 或浏览器网络验收。
- `pnpm format`、完整 `pnpm format:check`、`pnpm check` 全通过，覆盖所有自有语言、生成一致性、依赖层级、严格类型、389 项 Vitest、10 项正式 TS/Dart 双向 ProtoJSON golden 和全部工具回归。golden 包含封面描述、设置及清除的 message presence。最终合同复核统一共享 UUIDv4 校验为小写；TS、Dart 数据和 HTTP 边界均拒绝大写，避免服务端接受客户端无法读回的身份。
- `pnpm flutter:check` 全通过：reader_core 22、source_runtime 42、客户端 375 项，三个项目静态分析无问题。`pnpm build` 完成 Web/Native runtime 资源、Flutter Web 与 Worker/Static Assets 正式构建。

```sh
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts apps/api/test/cover-worker.test.ts
pnpm --filter @karuyomi/api db:migrate:local
pnpm covers:cleanup
cd apps/reader
flutter test test/covers/ test/runtime/cover_transport_test.dart
```

提交 `cc59335` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/42116194785) 全部通过，包含 `pnpm check`、`pnpm flutter:check`、`pnpm build` 与本地 D1 migration。

临时日志保留在忽略的 `.local/cover-*.log`。全库可复验入口为 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build`。官方生成的 Worker runtime 类型保持生成器输出，其余自有文件补丁检查通过。

## 原生构建

正式 `lib/main.dart` 的 iOS simulator debug 与 Android ARM64 debug 均 exit 0。iOS 使用 Xcode 27.2 / Simulator SDK 27.2，产物为 arm64+x86_64 universal `Runner.app`；Android 使用已有 SDK/NDK 与固定 JDK/Gradle，APK 为 93,144,545 字节。两端生成的插件注册均包含 file_selector，未修改正式产品源码、Podfile.lock 或 TLS 策略。

iOS Xcode 构建 26.7 秒。Android 首轮 Maven Central 的 Kotlin 2.1.20 TLS 握手中断，保留该失败后由同一 Flutter 官方进程自动重试成功，没有另开竞争构建或跳过证书校验。日志位于 `.local/cover-native/ios-build.log` 与 `.local/cover-native/android-build.log`；构建后无本轮 Flutter、Xcode、Gradle 或 Kotlin daemon 遗留。

本轮没有启动 Native App 或模拟器，构建通过不表示真实选择器、Cookie、Access 或 Native UI 已验收。

## 独立 Web 客户端往返

2026-11-07，固定 `d2a21aa` Flutter Web 与官方 Wrangler `createTestHarness`，使用同一 loopback HTTP origin、受验签测试身份 `acceptance-owner`、隔离 D1 和本地 R2 `COVERS`。Flutter `main.dart.js` SHA-256 为 `178c4b43bfe620ef8df51078db0e87a8bb53c8c05d9e555f2ed221d42063794c`。静态索引仅含 xkcd 1.6.1，buildId `ext-all.xkcd-dd84d305506e2bdc34ac62988aef645f`，允许 `xkcd.com` 与 `imgs.xkcd.com`。使用正式浏览、书架与详情和真实英文 xkcd（Source ID `1538249443376436084`，作品 `SINGLE`），未注入图片或业务响应。

| 独立文档     | 正式界面与只读证据                                                                                                                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 上传       | 通过真实浏览器文件选择器选择自行生成的 192 × 256 橙色 PNG，预览后保存。详情与编辑器显示已确认橙图，书架 API 返回 account / manga revision `3 / 2` 和 2,423 B 的 JPEG 描述。                                         |
| B 读回、替换 | 关闭 A 后新文档书架直接显示橙图。B 从书架打开详情、用文件选择器选择同尺寸青色 PNG 并保存。详情与编辑器显示青图，独立书架 GET 为 `4 / 3`；橙图 asset 路径 404，青图 200，实际 2,391 B JPEG 的 SHA-256 与新描述一致。 |
| C 读回、清除 | 新文档书架显示青图。C 从详情清除并保存，编辑器回到无自定义封面的“选择图片”。独立书架 GET 为 `5 / 4`，作品和书架均无封面引用，两份旧 asset 路径都是 404。                                                            |
| D 新文档     | 启动后仍显示同一收藏，封面回到 xkcd 默认占位。逐字段对比书架三份快照，除封面引用与 revision 外完全相同；书签和进度仍为空。                                                                                          |

复验使用与当前 host ABI 匹配的真实 xkcd 静态快照，按[官方 Web 验收入口](aot-current-pilot.md#绑定摘要后的正式三包和同站-web-更新)构建并启动服务；本分项不设 `ACCEPTANCE_NEXT_CONFIG`，只提供上述两个精确 Source hosts。通过界面上传两份无敏感数据、易区分的测试图片，独立 GET `/api/library`、`/api/state/manga/:mangaKey` 及 `/api/covers/:assetId` 时使用 `X-App-Request: 1` 和 `X-App-Subject: acceptance-owner`。确认当前正文摘要、旧路径状态和清除前后无关字段。原始图片和 API 样本留在 `/private/tmp/karuyomi-cover-58652.OkXKyy/`；四份文档已关闭，harness 正常退出，原端口无监听。404 仅证明应用拒绝读旧引用，不代表底层旧对象已物理删除。

## Android 模拟器系统选择器与新进程读回

2026-11-10，固定产品 `426536d`、冻结 `c04d436` 的真实 xkcd v6 1.6.1、Android API 36 专用模拟器。同一官方 Wrangler HTTPS / workerd / D1、隔离私有 `COVERS` 和测试身份，系统 WebView 与 Flutter HTTP 客户端正常校验证书。正式详情和书架使用真实英文 xkcd，另有一部由正式 API 创建的对照收藏。

四个独立 Flutter 进程均 1/1 通过。第一次上传橙色 PNG，第二次新进程读回橙图并替换为青色 PNG；两次均从 Android 系统 DocumentsUI 的 `ACTION_OPEN_DOCUMENT` 列表实际选择文件。正式预览、确认后封面、详情和书架解码为预期颜色。第三次新进程读回青图并清除，第四次启动仍无封面引用，显示原占位，未附带写入。

独立 HTTPS 与只读 D1/R2 审计核对：账户／作品 revision `3/1 → 4/2 → 5/3 → 6/4 → 6/4`，三个写阶段各有一条唯一回执。两份实际返回的 JPEG 均为 192 × 256，正文大小和 SHA-256 与当前 D1 引用及 R2 内容一致。替换后橙图路径 404，清除后两份旧路径均 404；旧对象仍按宽限期留在 R2。对照收藏、作品资料、设置、书签和阅读进度保持不变。复验步骤、系统选择器证据及独立摘要位于本机忽略目录 `.local/native-android-cover-426536d/` 的 `REPRODUCE.md` 和 `evidence/verified.json`。

## iOS 模拟器系统选择器与新进程读回

2026-11-10，固定同一正式产品 `426536d`、冻结 `c04d436` 的真实 xkcd v6 1.6.1。iPhone 17 Pro / iOS 26.4 专用模拟器通过正常 TLS 访问独立官方 Wrangler HTTPS / workerd / D1、隔离私有 `COVERS` 和测试身份。正式 Flutter 主入口与原文件选择插件不修改；独立 XCUITest 操作实际 iOS Files 选择器，从仅含两份合成 PNG 的测试文件夹依次选择橙色和青色文件，并确认选择器关闭。

上传、替换、清除和重启读回四个 Flutter 进程各 1/1。正式详情预览、确认后的封面与书架显示预期颜色；替换与清除分别从新进程读到上一份已确认封面。第四次启动仍保留同一收藏，恢复原占位。独立 D1/R2 核对三条新成功回执，账户／作品 revision 为 `3/1 → 4/2 → 5/3 → 6/4 → 6/4`；两份 192 × 256 JPEG 的 HTTP 大小与摘要均匹配当时的 D1 引用和 R2 对象。替换后旧橙图路径 404，清除后两份旧路径均 404，两个对象仍在宽限期。对照收藏、设置、进度和书签不变。

首轮选择器定位及 Flutter 等待超时保留；测试驱动改为预编译后及时启动并点实际文件单元格的缩略图，正式产品未改。原始 Flutter 日志、XCUITest 结果与各阶段快照保存在本机忽略目录 `.local/native-ios-cover-426536d/`。

## 剩余平台、故障与生产门

Web 与 iOS、Android 模拟器分别通过独立文档／进程的顺序保存和读回。混合平台同库、并发旧 CAS、响应丢失后原请求恢复、服务端重启、生产 Cookie／Access 与真机仍须验收。

已通过当前账户的 Wrangler 创建配置匹配的 `karuyomi-covers` bucket，`wrangler r2 bucket dev-url get karuyomi-covers` 确认公开 r2.dev 访问关闭；创建记录在忽略的 `.local/cover-bucket-create.log`，隐私检查在 `.local/cover-bucket-privacy.log`。这只证明资源已准备，尚未部署新 Worker 绑定或应用生产 D1 schema。部署后仍需分别记录已登录上传/读取、匿名拒绝、不同 subject 隔离、旧 asset 撤销和宽限期后显式清理。远端对象不即时删除是当前设计，不能将暂存旧对象误记为当前 API 可公开读取。

完整 P1/P2、生产 Access 和真机门仍未通过；下一步按 [P1](../plan/p1-library-and-progress.md) 与 [P2](../plan/p2-sync.md) 的剩余日用流程、错误恢复及实际跨端缺口推进。
