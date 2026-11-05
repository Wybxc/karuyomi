# 自定义封面验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。自定义封面已接入 Protobuf、Worker API、D1 当前引用、私有 R2、共享 Dart 数据层及正式详情/书架入口；状态为**已实现，待独立客户端验收**。合同、上传/清除、对象清理与生命周期设计见[设计](../design/custom-covers.md)。

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

临时日志保留在忽略的 `.local/cover-*.log`。全库可复验入口为 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build`。官方生成的 Worker runtime 类型保持生成器输出，其余自有文件补丁检查通过。

## 原生构建

正式 `lib/main.dart` 的 iOS simulator debug 与 Android ARM64 debug 均 exit 0。iOS 使用 Xcode 27.2 / Simulator SDK 27.2，产物为 arm64+x86_64 universal `Runner.app`；Android 使用已有 SDK/NDK 与固定 JDK/Gradle，APK 为 93,144,545 字节。两端生成的插件注册均包含 file_selector，未修改正式产品源码、Podfile.lock 或 TLS 策略。

iOS Xcode 构建 26.7 秒。Android 首轮 Maven Central 的 Kotlin 2.1.20 TLS 握手中断，保留该失败后由同一 Flutter 官方进程自动重试成功，没有另开竞争构建或跳过证书校验。日志位于 `.local/cover-native/ios-build.log` 与 `.local/cover-native/android-build.log`；构建后无本轮 Flutter、Xcode、Gradle 或 Kotlin daemon 遗留。

本轮没有启动 Native App 或模拟器，构建通过不表示真实选择器、Cookie、Access 或 Native UI 已验收。

## 独立客户端与生产门

需要两个独立客户端经同一真实 D1/R2 验证封面替换、另一端刷新、反向替换、清除、并发旧 CAS、响应丢失后的原请求恢复及新进程读回。Web 文件选择与同源凭据、iOS/Android 的真实 Cookie 接线及 Access 恢复分别验收，不能用同一进程多个 repository 或测试 supplier 代替。

已通过当前账户的 Wrangler 创建配置匹配的 `karuyomi-covers` bucket，`wrangler r2 bucket dev-url get karuyomi-covers` 确认公开 r2.dev 访问关闭；创建记录在忽略的 `.local/cover-bucket-create.log`，隐私检查在 `.local/cover-bucket-privacy.log`。这只证明资源已准备，尚未部署新 Worker 绑定或应用生产 D1 schema。部署后仍需分别记录已登录上传/读取、匿名拒绝、不同 subject 隔离、旧 asset 撤销和宽限期后显式清理。远端对象不即时删除是当前设计，不能将暂存旧对象误记为当前 API 可公开读取。

完整 P1/P2、生产 Access 和真机门仍未通过；下一步按 [P1](../plan/p1-library-and-progress.md) 与 [P2](../plan/p2-sync.md) 的剩余日用流程、错误恢复及实际跨端缺口推进。
