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

分析无问题，23 项测试通过，包括 Android 二进制 block / transfer 标识、匹配 ACK、持久 port、旧 transfer 消息与取消，以及 Native 文件预算、迟到结果和释放失败。这里的 port 场景运行在 Node，不代替 Android WebView。升级后的完整 iOS / Android 打包、Android 六 slot 实际传输与 iOS 薄 WKDownload 接线，仍须在新固定提交上分别验收；旧 `7edf123` 的打包结果不能自动转移到新依赖身份。
