# Native 数据库与 WebView 依赖验证

2026-11-04。本记录区分正式平台打包、Dart 回归与实际设备传输；打包成功不代表 Native Source、图片或应用重启恢复已验收。

## 固定输入的 iOS 模拟器打包

独立工作树 `drift-native-validation/karuyomi` 固定提交 `7edf1237b254360ec791207f4a89cb405ff27cfd`，Flutter 3.47.5 / Dart 3.13.4、Xcode 27.2。数据依赖为 Drift 2.35.3、drift_flutter 0.3.1、sqlite3 3.5.2；WebView 为 flutter_inappwebview 6.1.5 / iOS 1.1.2。

```sh
cd apps/reader
env -u GH_TOKEN -u GITHUB_TOKEN -u CLOUDFLARE_API_TOKEN \
  PUB_CACHE=/Users/wybxc/karuyomi/.pub-cache \
  FLUTTER_ROOT=/tmp/karuyomi-flutter-sdk \
  /tmp/karuyomi-flutter-sdk/bin/flutter build ios \
  --simulator --debug --no-codesign --no-pub
```

前两次执行因官方 sqlite3 hook 的 GitHub 下载连接失败或超时而失败。随后用正常 TLS 的 `curl --fail --location` 预热同一[官方发布文件](https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/libsqlite3.arm64.ios_sim.dylib)，保留未修改的 hook 自行验证其包内固定 SHA-256。下载 1,714,976 B，SHA-256 为 `1ce8ac8ebbb3f61fd6282c45a4da15b9c6c6ec169eff40a918520357a502510b`；没有修改 pub-cache 源码或绕过校验。

第三次正式构建成功，产物为 `apps/reader/build/ios/iphonesimulator/Runner.app`：

- 实际包含 `Frameworks/sqlite3.framework/sqlite3`，Mach-O 同时包含 arm64 与 x86_64。
- `nm -gU` 确认 `_sqlite3_open_v2`、`_sqlite3_prepare_v2`、`_sqlite3_close_v2`。
- `App.framework/flutter_assets/NativeAssetsManifest.json` 中 ios_arm64 / ios_x64 的 sqlite3 asset 均映射到该 framework；objective_c framework 也实际存在。
- 官方 hook 输出成功；`Podfile.lock` 无变化，SHA-256 为 `a02a5ff09ead04f33a93d431a0a026ec6691d90cee9aaab866eaac44c839fb50`。Drift / sqlite3 通过 Dart native-assets 打包，无需新增 sqlite3 CocoaPod。

日志保留在该工作树忽略的 `.local/native-data/ios-simulator-{build,retry,cached-build}.log`。尚未安装运行此包，也未验证应用关闭重启后的数据库读取。

## Android 阻断与正式依赖升级

同一固定提交使用项目配置 AGP 9.1.0、Gradle 9.3.1、Kotlin 插件 2.4.0 与 JDK 25.0.5+8 执行 `flutter build apk --debug --no-pub`。官方 Gradle wrapper 与 NDK 正常准备后，构建在 `flutter_inappwebview_android` 1.1.3 的 `android/build.gradle:44` 失败：它调用了 AGP 9 已移除的 `getDefaultProguardFile('proguard-android.txt')`。此时尚未产出 APK，不能归因为 Drift 或宣称 Android 打包通过。日志在 `.local/native-data/android-debug-cached-build.log`。

官方稳定版仍为 flutter_inappwebview 6.1.5，但已发布的 [6.2.0-beta.3](https://pub.dev/packages/flutter_inappwebview/versions/6.2.0-beta.3/changelog) 搭配 [Android 1.2.0-beta.3](https://pub.dev/packages/flutter_inappwebview_android/versions/1.2.0-beta.3/changelog) 明确包含 [AGP 9 修复 #2765](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2765)。当前项目精确升级到该官方版本并通过 pub 锁定各联邦实现，没有手改缓存、使用 dependency override 或降低 AGP。

该版本要求 Flutter ≥3.32 / Dart ^3.8，当前固定 SDK 满足。项目保留模板的 `android.builtInKotlin=false` / `android.newDsl=false`；这是 [Flutter 官方记录的 AGP 9 过渡支持](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)，不是为了忽略插件错误增加的开关。

升级后的实际回归：

```sh
cd apps/reader
flutter analyze --fatal-infos lib/runtime test/runtime
flutter test test/runtime
```

分析无问题，23 项测试通过，包括 Android 二进制 block / transfer 标识、匹配 ACK、持久 port、旧 transfer 消息与取消，以及 Native 文件预算、迟到结果和释放失败。这里的 port 场景运行在 Node，不代替 Android WebView。旧 `7edf123` 的打包结果不能自动转移到新依赖身份；升级后的固定输入验证如下。

## 官方 beta 的双端实际打包

独立工作树 `native-progress-validation/karuyomi` 固定 `926b93d78a7360d849813b2d03dd650cd5c34172`，使用锁定的官方 beta 及 Flutter 3.47.5 / Dart 3.13.4。全部命令移除 `GH_TOKEN`、`GITHUB_TOKEN`、`CLOUDFLARE_API_TOKEN`，未修改插件缓存或跳过官方构建步骤。

- iOS：同上 `flutter build ios --simulator --debug --no-codesign --no-pub` 成功。实际 SQLite framework 包含 arm64 / x86_64 及 `sqlite3_open_v2`、`sqlite3_prepare_v2`、`sqlite3_close_v2` 符号。
- Android：JDK 25.0.5+8、项目既定 AGP 9.1.0 / Gradle 9.3.1，`flutter build apk --debug --no-pub` 成功。APK 实际包含三种 Android ABI 的 `libsqlite3.so` 及 `NativeAssetsManifest.json`，SHA-256 为 `b42e7d19a43ec76bee3fa5cb1679850d5dcb8e15014ec2602ffa302e80b05010`。官方 beta 解决了此前 AGP 9 构建阻断。
- 依赖准备仅复用已按 sqlite3 3.5.2 包内固定 SHA-256 验证的官方 native-assets 下载文件；仍由未修改的 hook 验收，没有复制编译 hook 或手改 pub-cache。
- Flutter 官方流程将本次 iOS 插件切换到 Swift Package Manager。`Podfile.lock` 仅剩 Flutter；`project.pbxproj` 移除无用的 Pods framework 嵌入阶段，保留 `NativeImageFiles.swift` 正式编译引用。两份 workspace `Package.resolved` 固定官方 `swift-collections` 1.7.5 / `f96b909e1a9e469620bc5037c1e24e00153f376f`。只回收这些构建输入，SPM checkout 与生成缓存不入库。

正式主入口包备份与完整日志保留在该树 `.local/native-data/official-ios/Runner.app`、`official-android-app-debug.apk`、`ios-simulator-build.log`、`android-debug-build.log`。下述运行使用忽略目录内的机制夹具，不能把其结果当成正式 ReaderScreen 或 Source 阅读验收。

## iOS 实际受管文件与 SQLite 进程重启

同一固定树的 `.local/native-image-validation/main.dart` 调用正式 `NativePlatformRuntime`、`IosImageFileStore`、`NativeImageControl`，在 iPhone 17 Pro / iOS 26.4 模拟器运行。内置材料为 `6ce41048c205ea29dc6ba076faa2eb63398bd745f9ad864787c21391e9acee37`，正常 HTTPS 控制页为 `https://karuyomi.wybxc.cc/runtime/host`。

```sh
cd apps/reader
flutter run --debug --no-resident --no-pub \
  -d 516C79A4-FE42-46C2-8500-BDE77CBBA069 \
  --target .local/native-image-validation/main.dart
```

实际通过：正式容器握手；两轮各六张并发、每张 233,144 B 的同源受控 PNG Blob 经 WKDownload 到受管文件；文件摘要一致、Flutter 实际解码、六资源配额、generation 绑定、发布后迟到取消、幂等释放、文件删除与 owner clear。PNG 摘要为 `b5b30238a6a750d723ee80d3af098b20d562bda00d2972d6d53717dc9afdb896`。另验证已取消的 acquisition 不发布资源；这不是 WKDownload 正文中段取消的证明。

夹具随后通过正式 `ReadingProgressController` / `ProgressRepository` / `ReaderDatabase.open()` 保存合成章节，确认真实 persistent 模式并关闭数据库。使用 `xcrun simctl terminate` 后 `launch` 真正重启进程，成功恢复当前页及 `.25` offset、最远页及 `.75` offset、反序；不同 subject 无该进度，reset 原子增加 epoch 并回首页、清最远，旧 epoch 写入不能覆盖 reset。

报告为该树 `.local/native-data/ios-image-report.json`、`ios-progress-report.json`；原报告也保留在应用 Application Support。此结果仅覆盖正式 Native 文件/SQLite 机制，输入是受控 Blob 与合成章节，未调用 Source AOT、正式 ReaderScreen 或真机；不宣称 Source 图片处理、真机峰值内存或 Native 阅读全链已通过。

## Android 实际桥就绪阻断与修正

官方 Android Emulator 37.2.13 / Google APIs ARM64 API 36 r7、Android WebView `133.0.6943.137` 上，926 固定树的正式 `NativePlatformRuntime.ready` 超时，尚未进入六 slot 图片验证。

真实对照区分出原因：直达 `/runtime/host` 时，`onLoadStop` 中立即 `callAsyncJavaScript` 成功；经 `.html` 的 307 时，会先得到一次 URL 已显示 `/runtime/host` 的回调，立即调用却报 `callHandler is not a function` 且不返回，随后第二次加载完成回调桥才就绪。有无内置脚本、显式 bridge origin 设置均相同。原宿主在第一次回调设置 `handshaking`，导致后续就绪回调被忽略。

修正直接加载规范路径，先用官方同步 `evaluateJavascript` 的 boolean 返回检查文档、插件桥与内置材料身份；未就绪不占握手，异步检查后重验 generation，仍受原整体超时预算。不增加固定 sleep 或修改插件。四项正式平台接口回归覆盖未就绪后再就绪、并发回调、重建后的迟到 readiness、拒绝非 boolean 返回；后续固定提交的真实双端结果见下节。

失败及对照报告保留为该固定树 `.local/native-data/android-image-report.json`、`android-plugin-diagnostic-v2.json`；不能用后来的对照成功覆盖首次生产路径失败。

## iOS 单次加载回调与文档状态

固定 `5e9e526` 的独立 `native-canonical-validation` 工作树已通过 Android 正式握手、两轮各六张并发受管图片、解码/取消/释放及真实 force-stop/relaunch 的 SQLite 恢复。Flutter CLI 末端 DDS 连接被拒绝并退出 2；应用实际已生成完整 passed 报告，分别记录这两个结果，不把 CLI 退出码改称成功。

同提交在 iOS 却真实触发 20 秒 readiness 超时：唯一 `onLoadStop` 的同步检查中，文档状态为 `interactive`，来源、规范路径、插件 `callHandler`、内置材料及 runtime 引用全部正确；紧接官方 native `callAsyncJavaScript` 返回 42，随后文档才进入 `complete`，没有第二次 `onLoadStop`。因此不能要求该回调时文档已经 complete。

当前条件显式接受 `interactive` 或 `complete`，继续检查插件、来源/路径、材料身份及 generation；不以定时等待或固定 sleep 代替真实就绪。忽略目录中的单条件诊断复制通过了完整 iOS 受管图片机制；该草稿与随后的正式验证分别记录。失败、分条件诊断和草稿报告分别保留在 `.local/native-data/`，不会覆盖首次失败。

## 正式 readiness 修复的双端复验

2026-11-04，独立 `native-ready-validation/karuyomi` 固定 `d76e8a48f6898c06dd7413c430747d60e5cba34d`。按锁安装真实依赖，构建 protocol、runtime-host 并运行正式 `assemble-native-assets.ts`；内置材料为 `80c9e303184623dea1b56acdd1c02cac0db522b83fe01f5f68285d7145f395c7`。设备保持原 iOS 26.4 模拟器及 Android API 36 / WebView 133，仍使用正常 HTTPS 与官方 beta。

两端均实际通过正式 `NativePlatformRuntime.ready`，以及两轮各六张并发的受控 PNG 文件传输：

| 平台    | 每张编码字节 | SHA-256                                                            | 实际平台路径                                 |
| ------- | -----------: | ------------------------------------------------------------------ | -------------------------------------------- |
| iOS     |    233,144 B | `b5b30238a6a750d723ee80d3af098b20d562bda00d2972d6d53717dc9afdb896` | 同一 WKWebView 的 WKDownload → 受管文件      |
| Android |    225,144 B | `e7256a9806158453dc1cc016884ffcfc203e5b5a45222a56d72439180d4e548a` | 六个真实持久插件 port slot，第二轮复用原六槽 |

两端均核对文件完整字节、Flutter 实际 PNG 解码、六资源限额、generation 所有权、发布后的迟到 cancel、幂等 release / 文件删除、取消不发布资源以及 owner clear。受控图像的编码字节随平台 PNG 编码器不同，分别按本平台 Blob 摘要核对，不要求两平台编码结果相同。

随后分别真正执行 iOS `simctl terminate/launch` 和 Android `am force-stop/am start`。同一产品进度 controller / Drift / Native SQLite 恢复当前页、最远页、offset 和反序；不同 subject 隔离，reset 增加 epoch、回首页并清最远，旧 epoch 不能覆盖 reset。四份通过报告保留在该树 `.local/native-data/{ios,android}-{image,progress}-report.json`，构建与运行日志同目录。

这是正式双端 Native 机制与合成章节 SQLite 重启证据；图片输入是同源受控 Blob，未以这组结果宣称 Source、ReaderScreen、生产 Access、物理设备或峰值内存通过。真实 Source / ReaderScreen 使用与当前材料匹配的新 AOT 单独验收。

## 原版 xkcd、正式 ReaderScreen 与真实进程重启

同一 `d76e8a48f6898c06dd7413c430747d60e5cba34d` 固定树及上述 `80c9…95c7` 材料，在 iOS 26.4 模拟器通过实际 Source 阅读和进度重启。原版 xkcd AOT 在固定 `5148c60` 的 `bitmap-source-validation` 树构建，其材料与本次 Native 内置材料逐字节一致：

- buildId：`ext-all.xkcd-b96033033497e10d554cf94850e5793f`。
- 原 JAR SHA-256：`4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d`。
- bundle SHA-256：`a7efb40c8231bcde976321e91b44f88a51e2d6fe0aaba65bc6c6bd0cc10ad800`，原始 4,035,205 B / gzip 852,513 B。
- 英语 Source ID：`1538249443376436084`；章节 `3319: Elevators`，原 Page 列表两页。

忽略目录中的受控 Native 入口调用正式 `CatalogController → ChapterReaderRoute → ReaderScreen`，没有替换 Source、PageProvider、图片文件通道或进度实现。正常受信 `https://localhost:9446` 前端连接真实 workerd、隔离 D1 和 RS256 测试身份；仅允许 `xkcd.com`、`imgs.xkcd.com`。这是测试身份，不代表生产 Access。

实际热门、详情、章节和页列表成功；漫画请求返回 106,037 B PNG，SHA-256 为 `3bc6a7740ed3b630c74a68a7fb16b162ddf4c28953e5c1eb8c49c1514559d7ac`。正式 Native 文件路径供 Flutter 解码显示第一页，随后通过正式“下一页”按钮的合成 Pointer 事件显示 Source `TextInterceptor` 生成的末页文字图。界面显示 `2 / 2`，只有实际 observed frame 后点击启用的“读完本章”，SQLite 才记录末页 current / furthest 和 completed；退出等待真实 route / provider 清理 ACK。

随后对同一安装执行 `simctl terminate` / `launch`，PID 从 47752 变为 49027，未重装或重建数据库。重新经过 bootstrap 和原 Source 后，正式 ReaderScreen 恢复同章末页及已完成状态，退出清理再次通过。

```sh
# 固定树 apps/reader；只在 ignored 目录保存该测试入口
flutter build ios --simulator --debug --no-codesign --no-pub \
  --target .local/native-source/main.dart
xcrun simctl install <SIMULATOR_ID> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <SIMULATOR_ID> dev.karuyomi.karuyomi
xcrun simctl terminate <SIMULATOR_ID> dev.karuyomi.karuyomi
xcrun simctl launch <SIMULATOR_ID> dev.karuyomi.karuyomi
```

通过报告及截图在该树 `.local/native-source/ios-native-reader-{first,restart}-report.json`、`ios-native-reader-{first,restarted}.png`；网络记录为 `xkcd-network.json`。首次入口合成 End 键没有改变页码，90 秒后如实失败；该报告另存 `ios-reader-keyboard-attempt.json`。随后只把测试输入改为实际按钮的 Pointer 事件，未修改产品代码或 Source。

这覆盖模拟器中的正式产品 widget 路径、真实 Source 处理、文件解码和 SQLite 真重启；入口及输入事件仍是测试驱动，不等同正式 `lib/main.dart` 的人工手势、Android Source 阅读、后台恢复、真机、生产 Access 或内存峰值验收。

Android 同一受控入口的官方 APK 构建成功，但模拟器未信任该 localhost 测试 CA，WebView 实际报 TLS `net_error=-202`，随后握手超时，尚未进入 Source。失败及系统诊断保留为 `.local/native-source/android-reader-first-report.json`、`android-reader-tls-diagnostic.log`；未忽略证书错误、修改产品信任或回退 HTTP，先前生产 HTTPS 的六 slot 机制通过仍是独立证据。
