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

这是正式双端 Native 机制与合成章节 SQLite 重启证据；图片输入是同源受控 Blob，未以这组结果宣称 Source、ReaderScreen、生产 Access、物理设备或峰值内存通过。早期机制夹具 finally 未将最终 WebView dispose 异常计入结果，因此这组 passed 报告不能证明完整平台退出终态。后续 Source 测试保留 dispose 失败并在修复后重新验收，见下文。

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

这覆盖模拟器中的正式产品 widget 路径、真实 Source 处理、文件解码和 SQLite 真重启；入口及输入事件仍是测试驱动，不等同正式 `lib/main.dart` 的人工手势、后台恢复、真机、生产 Access 或内存峰值验收。Android 后续分项结果见下节。

Android 同一受控入口的官方 APK 构建成功，但模拟器未信任该 localhost 测试 CA，WebView 实际报 TLS `net_error=-202`，随后握手超时，尚未进入 Source。失败及系统诊断保留为 `.local/native-source/android-reader-first-report.json`、`android-reader-tls-diagnostic.log`；未忽略证书错误、修改产品信任或回退 HTTP，先前生产 HTTPS 的六 slot 机制通过仍是独立证据。

## Android 独立 debug App 的 TLS、Source 与退出复验

2026-11-04，使用 [Android 官方 Network Security Config](https://developer.android.com/privacy-and-security/security-config) 与 [debug build variant](https://developer.android.com/build/build-variants)，只在 ignored、可丢弃的 App 副本配置测试 CA：base 保留系统 CA 且禁止明文；domain-config 仅 `localhost`、`includeSubdomains=false`、专用 CA `overridePins=false`，不使用覆盖所有域的 debug-overrides。不安装全局 CA，不改正式产品配置，不在 TLS challenge 中放行证书错误。

从 APK 实际解析出的 manifest 确认为独立 debug applicationId、`debuggable=true` 和该 Network Security Config；解包的专用证书与输入逐字节一致。有效期为 2026-11-03 04:17:53 UTC 至 2026-11-04 04:17:53 UTC，执行时仍有效。真实 Android WebView 的四项结果：

| URL                                      | 结果                               |
| ---------------------------------------- | ---------------------------------- |
| `https://localhost:9446/runtime/host`    | 专用 CA 正常验证成功               |
| `https://karuyomi.wybxc.cc/runtime/host` | 系统 CA 正常验证成功，仅公开控制页 |
| `https://127.0.0.1:9446/runtime/host`    | 未获 domain-config 信任，拒绝      |
| `https://localhost:9447/runtime/host`    | 错误 CA，拒绝                      |

两个负例均收到 CA 不受信的 challenge 后返回 CANCEL，未使用 PROCEED。公共控制页成功不代表生产 Access 登录。

首个 d76 debug App 的原 xkcd 两页阅读与 SQLite 重启已成功，但最终 `platform.dispose()` 抛出 `AndroidWebMessageChannel was used after being disposed`，首轮与重启整门均为 false。根因是文件 sink 先 dispose 了 WebView controller registry 持有的 channel，controller 销毁时再次 dispose。原报告保留在 `native-ready-validation/karuyomi/.local/android-source-app/android-reader-{first,restart}-d76-dispose-failed.json`，TLS 报告和截图仍保留；不以阅读成功覆盖退出失败。

正式修复 `6c2e09c` 仅修改 `android_image_files.dart` 及其生命周期测试：文件 sink 关闭自身端点，controller 唯一销毁 channel；并发 clear 共享同一终态 Future，关闭一个端点失败后仍尝试其余端点和文件清理，保留原错误，重复 clear 不能伪造成功。回归包含真实临时文件、端点异步 gate、失败后再次调用和 controller 唯一 dispose；完整 Flutter analyze 与 89 项测试通过。

为避免混入 main 后续 Cache 材料，新受管树 `native-owner-validation/karuyomi` 从 d76 cherry-pick 该修复，形成固定提交 `8eef7b4e5881b4e83e7259c4e56da4af5c7dee64`。与 d76 的受跟踪 diff 只有上述两文件；内置材料仍为 `80c9e303184623dea1b56acdd1c02cac0db522b83fe01f5f68285d7145f395c7`，原版 xkcd JAR / AOT 身份与上节一致。独立 ignored debug 包为 `dev.karuyomi.karuyomi.nativeSourceOwnerFixture`，正式 Flutter debug APK SHA-256 为 `2f88ce1de49d220231f1b120d279c2b2fbfd6f5085013fb4a73f2bc49aed1e7f`。

此新包实际通过四项 TLS 检查、原版 xkcd `3319: Elevators` 的热门 / 详情 / 章节 / 页列表、两页正式 ReaderScreen 解码显示、实际 observed 后的末页 current / furthest 保存，以及合成 Pointer 经正式“读完本章”按钮保存 completed。漫画图仍为上节 106,037 B 原响应，末页仍为 Source 原 `TextInterceptor` 生成文字图。退出等待 route / provider ACK，最终 `platform.dispose()` 成功，未吞异常。

随后真正 force-stop PID 7443，再启动同一安装得到 PID 7656；没有重装、清数据或替换 SQLite。重新完成受信 bootstrap 与 Source 初始化，恢复同章末页 current / furthest 和 completed，实际 ReaderScreen 显示 `2 / 2` 和本章已读完，第二次最终退出再次成功。重启首张截图时，本次导航仍显示“本地进度待保存”；截图早于随后 route 退出和最终 flush，不作为本次写入已经完成的视觉证据。首轮与重启报告是在 flush / 清理完成后生成，均 `passed:true`，且把任何 provider / progress / platform 清理错误纳入失败条件。

为补足截图时机，随后只在 ignored 测试入口增加等待正式 UI “本地进度已保存”的条件；未额外调用 flush、修改产品状态文字或产品源码。新 debug APK SHA-256 为 `ecb7c497f0c10983b4a0996a2af1dc63e16ba3b260bc527bf039c592525aa1ad`。同包保留数据安装后通过该条件，再真正 force-stop PID 7840 / relaunch PID 8036，没有再次安装。最终报告同时通过 SQLite 恢复、真实末页、已保存 UI 和最终退出；新截图实际显示 `2 / 2`、本地进度已保存、本章已读完。原 pre-flush 截图及报告单独保留，不被新结果覆盖。

```sh
# 新固定树 .local/android-source-app/apps/reader；锁定官方 SDK 与依赖
flutter build apk --debug --no-pub --target lib/fixture/main.dart
adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5556 shell am start -n \
  dev.karuyomi.karuyomi.nativeSourceOwnerFixture/dev.karuyomi.karuyomi.MainActivity
adb -s emulator-5556 shell am force-stop \
  dev.karuyomi.karuyomi.nativeSourceOwnerFixture
adb -s emulator-5556 shell am start -n \
  dev.karuyomi.karuyomi.nativeSourceOwnerFixture/dev.karuyomi.karuyomi.MainActivity
```

新树 `.local/android-source-app/` 保留 `input.json`、`apk-manifest.xml`、`apk-network-security.xml`、`android-tls-report.json`、`android-reader-{first,restart}-report.json`、`android-reader-{first,restarted}.png` 和脱敏 `xkcd-network.json`。Reader 首轮报告 SHA-256 为 `e23fc2a839d76561ec084033d028b7a5a3d8b4f45e9814af47228394f772f946`，重启报告为 `900bace37c808c02c8e11d6f937bd5ee146945fec9ccd226e54317b1576e60cf`。

等待已保存 UI 后再次真实重启的最终记录为同目录 `android-reader-force-stop-saved-report.json`（SHA-256 `fd246b91958a2595933a21789ca2402e380a4ce942ad9e1a9d56ecd5f0b17a69`）及 `android-reader-force-stop-saved.png`；`run-summary.json` 记录各轮 PID 与测试边界。测试 HTTP / TLS 服务均已正常关闭，模拟器和 App 数据保留。

这是 Android 模拟器、隔离 localhost CA / RS256 测试身份中的正式 Catalog / ReaderScreen / 原 Source / Native 文件 / SQLite 路径。入口和输入为受控测试驱动，不代表生产 Access、正式主入口人工手势、物理设备、后台恢复或进程 / GPU 峰值内存通过。

更新至 Cache v3 材料 `63a061…` 后的双端 Source / 真重启复验，以及实际发现的 Reader 帧调度缺陷、早期 iOS 黑截图与最终系统 / Flutter 并列核验，见 [Reader 帧调度与 Native 复验](reader-frame-native.md)。该记录使用独立固定输入和 App，不覆盖本页的旧材料、TLS 或 dispose 失败证据。
