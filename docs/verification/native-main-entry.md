# Native 正式主入口准备与阻断

2026-11-10，匹配冻结 v6 发布候选的 [iOS 真机目标构建](#v6-ios-arm64-发布构建)通过；[Android arm64 发布构建与离线模拟器冷启动](#v6-android-arm64-发布构建与离线模拟器冷启动)也通过。以下 v4 以前的记录保留历史输入。

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，对固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 的 Native 成品和本地 HTTPS 服务做独立预验。**正式 App UI 未运行，验收未通过**；本记录不替代既有受控 ReaderScreen 或 Source Cache 分项，也不代表生产 Access。

2026-11-05，当前 v4 正式入口的双端构建与包内材料核对另见[新记录](v4-native-main.md)。它未运行 UI，也未复用本记录的旧证书或成品；下文保留 be5 当时的输入与限制。

## 固定输入与已验证范围

构建入口是正式 `lib/main.dart`，AppID 为 `dev.karuyomi.karuyomi.nativemainbe5`，部署 origin 固定为 `https://localhost:9461`。未注入 runtime 或客户端身份。62 份 tracked Dart 的 Git blob、磁盘内容和输入摘要逐项一致；Runner.app 中的 manifest、host、worker 字节匹配共享材料 `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`。

服务使用隔离 D1、正常 TLS、本地测试 issuer 与真实产品 Worker 的 RS256 验签。九项 HTTP 预验通过，覆盖匿名 bootstrap 401、剥离客户端 Access assertion、可见登录跳转、Secure/HttpOnly Cookie 后的受信身份、受限回跳、mutation Origin/请求头校验、过期 401、非本人 403、显式失效和重新登录 B，以及独立于 API 认证的公开静态索引/原版 gzip。未发出 Source 网络请求。

本地 CA 的 DER 与已有模拟器 TrustStore 精确匹配；当轮有效期截至 `2026-11-04T04:17:53Z`。恢复时应重新核验有效期，不能复用过期证书或关闭 TLS 验证。

## UI 阻断与恢复入口

CUA 分别通过 Simulator 名称、完整应用路径和 bundle ID 连接，均返回应用不可用；可用 surface 未列出 Simulator。Xcode 的工具入口也未能完成连接。因此未安装、启动或操作 App，报告明确保留 `nativeUi=not_run`、`passed=false`。后续在可控制的 Simulator 或真机上，使用同一正式入口完成可见登录、选源、详情、真实图片阅读、退出/后台恢复和身份切换后，再记录产品通过。

可复用的成品、服务、输入摘要和启动记录位于 main 的 ignored `.local/native-main-be5/`，本轮证据在 `ui-run-20261103T2347/`。在 main 运行 `pnpm exec tsc -p .local/native-main-be5/tsconfig.json` 检查服务，再按输入记录运行 `node .local/native-main-be5/service.ts`，另开终端运行 `node .local/native-main-be5/preflight.ts`。正常 HTTP 预验只能证明服务边界，不能补作 App UI 证据；证书失效时先按准备步骤重建。

| 证据                 | SHA-256                                                            |
| -------------------- | ------------------------------------------------------------------ |
| `summary.json`       | `203f7a1f17b728bbe0baea7541f3c5fcacb0a8237e90caa58dcc2c113182135c` |
| `preflight.json`     | `e6d2904833b1fe8f4175192507ab85204753acad8a8cb36d4533679889c19708` |
| `service-input.json` | `7d7647bd59d5492fb6b4cc728eb0ac257d4a1305f6227d099beaada8610dec20` |

本轮服务、esbuild/workerd 子进程、单个 iOS 模拟器和工具尝试启动的 Xcode 均已正常停止；正式 AOT 队列未受影响。详细日志和临时工程不入源码库。

## v6 iOS arm64 发布构建

2026-11-10，从固定 `2c012db` 的独立 Git 归档构建正式 Flutter 主入口。锁定 Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4 和 Xcode 27.2。根目录先执行 `pnpm install --frozen-lockfile --offline`、`pnpm --filter @karuyomi/runtime-host build` 和 `pnpm build:native-assets`，在 `apps/reader` 执行：

```sh
flutter pub get --offline --enforce-lockfile
flutter build ios --release --no-codesign --no-pub --target=lib/main.dart \
  --dart-define=APP_ORIGIN=https://karuyomi.wybxc.cc
```

官方构建 exit 0。实际 `build/ios/iphoneos/Runner.app` 的 Runner 和 Dart AOT framework 均为 arm64、Mach-O 平台 iOS；应用 ID 为 `dev.karuyomi.karuyomi`，编译的 Dart AOT 包含指定 origin。成品中的 `host.js`、`worker.js`、`manifest.json` 与正式 Vite Native 输出逐字节一致；六份共享材料目录与冻结 v6 xkcd 验收输入相同，目录文件 SHA-256 为 `eec7701e311b37ac3c03005a128d98b8f54f65d8a873c549ccf860f8fbb765ae`。未混入后续七材料的 WebP 改动。原始日志、成品和核对输出保存在本机忽略目录 `.local/ios-device-release-2c012db.xwGgAa/`。

成品确认为未签名，检查时本机无有效签名身份。未安装、启动或访问生产；当前生产仍是 v4。真机验收需要有效签名、可达的匹配 v6 部署与用户 Access 登录，之后再记录真实阅读、跨端恢复及移动性能。

## v6 Android arm64 发布构建与离线模拟器冷启动

2026-11-10，复用隔离的固定 `2c012db` Git 归档和冻结 `c04d436` 的 v6 xkcd 六份匹配材料。使用 Flutter 3.47.5 / Dart 3.13.4、JDK 25.0.5+8 和正式 `lib/main.dart`，未设置 `APP_ORIGIN`。在固定源码树按锁文件准备依赖并用 `pnpm --filter @karuyomi/runtime-host build`、`pnpm build:native-assets` 生成 Native 资源后，在 `apps/reader` 执行：

```sh
flutter build apk --release --no-pub --target-platform=android-arm64 \
  --split-per-abi --target=lib/main.dart
```

- 官方产物 `app-arm64-v8a-release.apk` 为 23,210,038 字节，SHA-256 为 `19293db1112468b48276dc3558050546f032ed65916ea6ae05522b2ffc2a797e`。包名 `dev.karuyomi.karuyomi`、版本 `0.1.0`（versionCode `2001`）；APK 与系统安装记录均为 `arm64-v8a`，`libapp.so` 为 ELF64/AArch64，应用不可调试。
- `apksigner` 验证 APK Signature Scheme v2 通过，唯一证书为 `CN=Android Debug`，证书 SHA-256 为 `8cd31446c6584ffeb49a7dd7fccdfe2beac96a44c7559e6028abbe9f22b8187e`。这是当时 Gradle 配置生成的本机侧载候选，尚无发行签名。
- APK 内 `host.js`、`worker.js`、`manifest.json` 与固定 Native 构建逐字节一致；内置清单的材料版本为 `5d1260e5d20b2f2f05fd378a6e8b697338e5fdfd4feca2c5a8c361e756bb92e4`，引用的六份冻结材料均按实际文件核对。APK 没有 `libsqlite3.so`，`NativeAssetsManifest.json` 的映射为空；固定产品无 Drift/SQLite 业务依赖，业务状态由 Worker API + D1 确认。历史 APK 的 SQLite 证据属于旧实现。
- 专用 Pixel 7 / Android 16 API 36 ARM64 模拟器在飞行模式下通过 `adb install` 安装；设备上 `base.apk` 的 SHA-256 与本机 APK 相同。`adb shell am start -W -n dev.karuyomi.karuyomi/.MainActivity` 报告冷启动成功，正式 Activity 位于前台（PID `4184`），UI 树和截图显示空书架及书架、浏览、设置三个标签。

APK 保留在本机忽略目录 `.local/android-arm64-release-2c012db/artifacts/karuyomi-2c012db-arm64-v8a-release-local.apk`。`evidence/split/` 保留签名、ELF、实际安装摘要、启动日志及截图；可用 `node verify-apk.ts` 重核。专用模拟器和私有 ADB 已清理。本次只验证该 release 包能启动；未连接隔离或生产服务，未验证此 APK 的 Source 初始化、真实 xkcd 续读、生产 Access 或真机。

## Android 发行签名配置

2026-11-10，在包含 Native 登录及阅读恢复修复的[首发六材料归档](aot-current-pilot.md#首发六材料产品归档)副本中，只替换 Android app 的 Gradle 配置。使用固定 Flutter 3.47.5 / Dart 3.13.4、JDK 25.0.5+8 和 Android Build Tools 37.0.0，从 `apps/reader` 运行：

```sh
flutter build apk --release --target-platform=android-arm64 \
  --split-per-abi --target=lib/main.dart \
  --dart-define=APP_ORIGIN=https://karuyomi.wybxc.cc
```

- 无 `android/key.properties` 时，构建成功，`apksigner verify` 拒绝未签名 APK。提供本轮临时 PKCS#12 密钥库及发行配置后重建，`apksigner verify --verbose --print-certs` 确认 v2 签名通过，唯一签名证书的 SHA-256 与构建前从密钥库导出的证书一致。
- 两个 APK 内的 `host.js`、`worker.js` 和 `manifest.json` 均与首发归档逐字节一致，`pubspec.lock` 不变。首轮 `--no-pub` 复用了过时的集成测试插件注册表，未通过 Java 编译；上面的正常构建刷新注册表后，两次均成功。

日志、证书摘要和成品保存在本机忽略目录 `.local/prototype-android-signing.vZ5Qg7/`，临时密钥和签名配置已清理。两份 APK 均未安装；正式发行证书、签名真机和生产登录仍待验收。

## Native 本机服务地址恢复

2026-11-10，修复通用 Native 安装中手动选择的服务地址只留在当前进程的问题。正式设置使用 Flutter `shared_preferences` 2.5.6 记录本机选定的 HTTPS origin；启动先读取该偏好，没有可用值时使用构建的 `APP_ORIGIN`，Web 继续使用文档 origin。此偏好不保存业务状态或 Access 凭据。

正式 AppShell 组件回归从空配置进入设置、确认带端口的 HTTPS 地址、尝试无效 HTTP 地址，然后销毁并启动新的 AppShell。新实例选回之前的 HTTPS 地址，两个实例均未写业务 API。完整 `pnpm flutter:check` 通过（三项目 22、87、612 项），正式 Web/Worker 的 `pnpm build` 通过。

在固定 `2c012db` 的副本应用相同 Flutter 变更，用专用 iPhone 17 Pro / iOS 26.4 模拟器和空扩展目录的官方 Wrangler HTTPS / workerd / D1 验收实际系统偏好。两次 Flutter 集成验收均不传 `APP_ORIGIN`：PID 41163 在正式设置手动连接，写入本机 UserDefaults；PID 42525 启动自动连回同一测试身份，无手动连接。第二次 Flutter 启动覆盖安装并保留偏好。独立 HTTPS 书架、设置读回不变，三次独立 D1 核对均为账户 revision 0、无业务写或回执。原始日志在 `.local/native-ios-origin-2c012db/evidence/`。Android 真实系统偏好、签名真机及生产 Access 另验。

## Native 可见 Access 回跳

2026-11-10，在固定 `afcbd11` 的隔离 HTTPS、官方 Wrangler harness 和临时 D1 上复验可见登录。环回测试身份提供方走不同 HTTPS origin；用户界面中的真实按钮签发 Secure、HttpOnly Cookie，正式 Worker 校验夹具注入的 RS256 Access JWT。使用真实导航和 Cookie；未替换正式 bootstrap，也不向生产发请求。

Android 修复前可复现：IdP 签发 Cookie，Worker 收到有效 Cookie 后重定向，App 仍停在「登录」且未发 bootstrap。诊断轮观察到中间 `/api/auth/login` 的停止事件启动异步检查，随后 `/runtime/host.html` 的停止事件因检查未完成被跳过；canonical 页偶尔会在真正开始加载前再收到一次停止事件。偶发成功不代表流程可靠。

修复后 Web 和 Native 共用本次登录的 UUID 回跳；Native 只从已提交或已完成的主框架加载事件接受精确 URL。公开 `/auth/complete` 不加载应用脚本。登录页只发出完成信号，正式 Catalog 必须重新 bootstrap 确认身份。组件回归覆盖中间事件、错误 origin、过期 attempt、取消、重复回调与一律只消费一次的恢复状态；正式 Vite/Wrangler 测试核对轻量回跳正文和 no-store。

iPhone 17 Pro／iOS 26.4 用未插桩的正式 Flutter App 和外部 XCTest 操作可见登录：首次登录及同进程会话失效后从设置点「连接服务」再登录均各 1/1 通过，PID 同为 `60501`。设置页两次都显示测试账号；服务端每轮观察到匿名 bootstrap 401、挑战、IdP 文档、签 Cookie、带有效 Cookie 的正式登录 303 和回跳文档，随后仅一个有效 bootstrap 并读回设置。终止并启动原安装（PID `46548`）后，设置页不经可见登录再次显示同账号，审计只增加带有效 Cookie 的 bootstrap 和设置读取。D1 业务账号和变更回执始终为 0。

Android 用正式 Flutter 构建的调试 APK 启动正式 App，由系统 UIAutomator 点击可见 IdP 按钮。首次登录、新进程直接沿用 Cookie、失效后新进程明确需要登录、再点击并恢复同一账号四项均通过（PID 依次为 `3239`、`3632`、`3781`、`3936`）。阶段间覆盖安装保留同一 App 数据。两次可见登录各只触发一次带有效 Cookie 的 Native bootstrap，Cookie 有效时新进程不挑战，失效时不显示旧身份。独立 D1 查询确认业务表无新增行或回执。测试 CA 只用于独立的回环 WebView 与 Dart 网络信任，未关闭证书校验。

iOS 本机证据在忽略目录 `.local/native-cookie-access-afcbd11.ONsdHk/evidence/`，包括三轮 `xcresult` 和独立 audit JSON；Android 的验收及源文件比对在 `.local/native-android-access-afcbd11/evidence/`。iOS 首轮用 Flutter 测试驱动时外部点击未提交，改用未插桩 App；一次修复候选的本地材料装配错误也保留在原始记录，正式复验使用逐字节匹配的内置材料。本节只覆盖隔离设置页登录和身份确认；生产 Access、阅读中断后恢复、跨身份与真机门独立验收。

### Android 阅读中 Access 失效与原位恢复

2026-11-10，专用 Pixel 7 / Android 16 API 36 ARM64 模拟器通过同身份真实阅读恢复。使用 Flutter 3.47.5 / Dart 3.13.4 调试验收 APK，入口调用正式 `app.main`。固定 `2c012db` 六材料归档，应用 `98d78aa` 与 `016a5d0`，逐字节核对登录、服务地址和正式 Worker 源码。官方 Vite/Wrangler HTTPS harness 绑定隔离 D1；WebView 与 Dart 信任本轮回环证书。Static Assets 使用冻结 `c04d436` 的 v6 xkcd，材料版本 `5d1260e5d20b2f2f05fd378a6e8b697338e5fdfd4feca2c5a8c361e756bb92e4`。测试 IdP 发真实 Secure、HttpOnly Cookie，正式 Worker 校验测试签发的 Access JWT；图片通过正式 Source 链路请求和解码。

先从设置可见登录，安装 xkcd、收藏英文源作品并保存 `/3319/`（`3319: Elevators`）第 2/2 页。新进程从书架直接续读，后续都在 PID `5134` 的同一个 Reader 路由完成。让夹具 Cookie 失效后，Android 系统输入点击「刷新进度」，实际读请求收到 401。Reader 暂停新图片与章节请求，失效提示和可见登录覆盖期间，原来的页面会话、资源和已解码的 1000 × 209 画面都保留。Android 系统输入依次点击「重新登录并恢复本章」和 IdP 按钮。审计记录一次有效 Cookie 的正式 bootstrap，随后重新读取设置、作品和 Source；应用确认同一 `acceptance-owner`，释放原会话与资源，在同一路由用新会话解码同章、同清单、同页。

独立 D1 查询确认已保存、失效前、暂停、可见登录和恢复五个阶段的业务状态及回执完全相同（账户 revision 5、作品 revision 4、5 笔回执）。Android 系统返回退出时释放恢复后的会话，观察到恰好一笔进度写：仍是同章、同页和同一最远进度，仅 `current.viewportY` 从默认 0 变为约 0.394，账户 revision 6、作品 revision 5。驱动让阅读控件滚动至可点击范围，本轮不能单独归因这笔视口变化；无写入结论仅覆盖退出前的恢复阶段。

本机忽略目录 `.local/native-android-reader-access-2c012db/` 保留 `REPRODUCE.md`、Android 系统控件树和截图、分阶段审计与 D1 快照。可用仓库固定 Node 执行 `node .local/native-android-reader-access-2c012db/verify.ts` 独立重核。专用模拟器、ADB、隔离服务及临时私钥已清理。本项覆盖隔离 Android 模拟器中的同身份恢复；生产 Cloudflare Access、其他身份、未确认草稿和真机需分别验收。

2026-11-10，用带 `676f424` 和 `63c2cab` 阅读恢复修复的首发六材料源码，在另一台专用 Pixel 7 / Android 16 API 36 模拟器上重跑同一系统操作。正式入口和冻结 xkcd 的静态索引已逐字节核对。刷新进度收到 401 后保留原图，系统点击完成可见重登，读回同章第 2 页并重新解码；系统返回释放恢复后的资源。独立读取临时 D1 确认保存基线、401 前、暂停、登录、原位恢复、退出的业务数据完全相同（账户/作品 revision 4/3，四笔回执）；退出没有附带请求。保留旧轮次的同页写证据；本轮结论覆盖同一测试身份的读请求失效与退出。原始记录与独立核对脚本见 `.local/prototype-reader-recovery.mw5OJU/android-recovery/`。

### iOS 阅读中 Access 失效与待确认进度

2026-11-10，使用 iPhone 17 Pro / iOS 26.4 专用模拟器、未插桩 Flutter App 与外部 XCTest，独立验证首发六材料归档（`2c012db` + 服务地址与 Access 回跳修复）。官方 Vite/Wrangler HTTPS、临时 D1、回环测试 IdP 和冻结 v6 xkcd 与 Android 分项使用同一验证方式。正式界面登录、安装和收藏 xkcd 英文作品，打开 `3319: Elevators`、显示并保存第 2/2 页。驱动从外部使 Cookie 失效，App 留在前台，点击「读完本章」的真实 POST 收到 401；原图仍可见，账户/作品 revision 保持 5/4，D1 无新回执。

修复前，在同一 PID 点「重新登录并恢复本章」及可见 IdP 按钮后，App 恢复同章同页，但在重新读取作品前自动提交了 401 请求的原 UUID 和正文。用户没有点「重试保存」，D1 已将本章标记为读完。恢复期间另有一笔进度请求，最终 revision 7/6；这不是无写入恢复通过。

同一归档加入 `676f424` 的显式重试修复后，用新隔离 D1 复验。一次真实 401、可见重登和原位恢复都在 PID `72755`：失效期间保留第 2 页，回跳只触发一次有效 bootstrap，重新打开同章并显示第 2 页。重登后的作品读回没有业务 POST；基线、401 后和恢复后的账户、作品、章节与回执快照完全相同（revision 5/4，五笔回执，未读完）。点击「重试保存」后先读取作品，再用原 UUID、正文 SHA-256 和 CAS 4 发送一次，D1 收到对应回执，本章变为已读完。该中间版本随后还有一笔新 UUID、CAS 5 的同页视口写，最终 revision 7/6，页码、清单、epoch、最远页未改变。

最终修复在同章、同清单且原页仍存在时保留原视口锚点，避免图片重新解码或收起恢复控件被当作用户移动；清单改变仍走常规位置解析。用加入两次修复的同一六材料源码、专用 iOS 模拟器及新隔离 D1 复验：401 和原位恢复不改变业务状态；显式重试用原 UUID、正文及 CAS 只提交一次，账户/作品 revision 从 5/4 到 6/5，页位与最远进度均不变；控件收起后无新增 POST。主动翻到第 1 页才新增一条回执（7/6），第 2 页仍为最远进度，已读完成标记保留。42 项阅读器定向回归通过，包含恢复时清单变化、迟到解码和控件收起后再主动定位。复核可用固定 Node 执行 `node .local/ios-reader-access-v6.7gSLAq/placement.G2ta1m/verify.ts`，同目录保留实际补丁、`xcresult` 与分阶段审计。

回归测试另覆盖更换身份时不发送旧草稿、远端已重置时不重放旧写。本段实测使用同一身份和本地 IdP；生产 Access 和签名真机仍未验收。不同身份的隔离实测见下节。本机忽略目录 `.local/ios-reader-access-v6.7gSLAq/` 保留固定补丁、XCTest、原始 `xcresult`、分阶段审计和独立核对脚本。

### iOS 阅读中切换身份

2026-11-10，用带两次阅读恢复修复的首发六材料源码，在专用 iPhone 17 Pro / iOS 26.4 模拟器运行未插桩的正式 App。App、Reader Core、Source Runtime、正式 Worker 与归档一致，实际包内三项运行时资源也逐字节一致。复用冻结 v6 xkcd、隔离 D1、官方 Wrangler HTTPS 和外部 XCTest。回环测试 IdP 用同一测试邮件签发两个不同的 RS256 `sub`，正式 Worker 仍按签名身份鉴权。

1. A 登录、安装并收藏 xkcd，打开 `3319: Elevators`，显示并保存第 2/2 页。使 Cookie 失效后点击「读完本章」：实际 POST 收到 401，原图仍可见；账户/作品 revision 保持 5/4，本章未读完，D1 仍是 5 笔回执。
2. 保持同一 App 进程，通过 Reader 的可见登录切到 B。原 Reader 退出，B 看到空书架，无旧「重试保存」入口。独立审计确认 B 的 bootstrap 和书架读回，未出现原作品查询或 Source 中继请求，未重发 A 的章节 mutation，D1 业务快照与切换前完全一致。
3. B 从正式扩展管理明确安装 xkcd。D1 只新增 B 自己的一条全局设置回执，B 账户/设置 revision 均为 1，A 的账号、作品、进度、设置和回执逐项不变。终止并重启 App 后，B 仍能读回自己的扩展安装，书架保持空白，业务快照无变化。

首次 XCTest 已完成 B 登录，但等待空书架的静态标题超时；该标题未出现在当轮控件树中。驱动改用空状态专属的「去浏览」按钮，在原进程只读复验。设置接口审计未区分请求方法，唯一设置提交以 D1 revision 和回执为准。原始 `xcresult`、前后快照、进程核对及复验命令见本机忽略目录 `.local/prototype-ios-identity.vBZnAl/REPRODUCE.md`，可用固定 Node 执行同目录 `verify.ts`。测试服务、专用模拟器与 TLS 私钥已清理。本项仅覆盖 iOS 模拟器的本地签名身份切换，Android 对照见下节。

### Android 阅读中切换身份

2026-11-10，在专用 Pixel 7 / Android 16 API 36 arm64 模拟器，用与 iOS 对照一致的首发六材料源码、冻结 v6 xkcd、官方 Wrangler 回环 HTTPS 和新隔离 D1 复验。调试入口只为 Dart 加入测试 CA，再调用正式 `app.main()`；WebView 仅在回环域信任该 CA，两条网络路径都保留证书和主机名校验。APK 内的 `host.js`、`worker.js` 和 `manifest.json` 与首发归档逐字节一致。所有业务操作通过正式界面，由 Android 系统 UIAutomator 定位和点击；测试 IdP 签发不同 `sub` 的令牌，正式 Worker 验签。

1. A 安装并收藏真实 xkcd，打开 `3319: Elevators`，显示并保存第 2/2 页。Cookie 失效后点「读完本章」，唯一一次章节 POST 收到 401；截图确认第 2 页原图仍在，完成只显示为未确认草稿。独立 D1 快照确认本章未读完，账户/作品 revision 仍为 5/4，回执仍为五条。
2. 在同一 App PID `3856` 通过可见登录切到 B，原 Reader 退出，B 的空书架无旧「重试保存」入口。有效 Cookie 的 B bootstrap 后读回自己的书架；期间无业务 POST、原作品 GET 或 Source 中继请求，D1 业务快照不变。
3. B 的扩展列表显示零个安装，手动安装 xkcd 后只有一条由 B 发起的 `POST /api/settings/mutations`，请求 ID 与新 D1 回执一致。B 账户/设置 revision 为 1，A 的所有行不变，401 请求从未持久化。终止 App 后以 PID `5691` 冷启动，B 的 Cookie、空书架和安装记录可读回，全程无业务 POST，D1 快照不变。

控件树、截图、APK 资源核对、独立审计和复验步骤保留在本机忽略目录 `.local/prototype-android-identity.pEmIby/REPRODUCE.md`；用固定 Node 执行同目录 `verify.ts` 重核五阶段快照。专用服务、模拟器、私用 ADB 和临时 TLS 私钥已清理。本分项覆盖隔离模拟器的单向身份切换；生产 Access、更多 Source 下往返换身份和签名真机另验。
