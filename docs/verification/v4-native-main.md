# v4 Native 正式入口构建

2026-11-05，正式产品源码固定 `5eab527`（功能输入与 `1f599cd` 相同），重新构建 `lib/main.dart` 的 iOS 模拟器 App 和 Android arm64 调试 APK，生产 origin 为 `https://karuyomi.wybxc.cc`。两次最终构建均退出 0，成品中的 v4 运行时材料和 SQLite 打包核对通过。**App 未安装或启动，Native UI 与生产 Access 未验收。**

## 输入与成品身份

Flutter 3.47.5 / Dart 3.13.4、Xcode 27.2、Temurin JDK 25.0.5+8；Android 使用现有 SDK 36、NDK 28.2.13676358、AGP 9.1.0 / Gradle 9.3.1 缓存。没有修改全局 Flutter 配置、第三方包、正式入口或应用身份。双端包名均为 `dev.karuyomi.karuyomi`，不是历史受控入口的临时 AppID。

Runner.app 和 APK 内的以下三份资源均与 `apps/reader/assets/runtime/` 逐字节一致，也与当前 runtime-host Native 输出一致：

| 文件          |  字节数 | SHA-256                                                            |
| ------------- | ------: | ------------------------------------------------------------------ |
| manifest.json |    2669 | `56e022259d93baa037b2170f29df83b048abfbedba4dc6500d1eb6178ceff5f1` |
| host.js       |  612374 | `3ff1834ee2e318db6ac32a42aa9711e8c91bc39c8d9c6c8278a7277137485411` |
| worker.js     | 1321304 | `5fb139640629ee0c04f14ac758fc8b1d4c10b866eb3ffe19cb07e568e43233e5` |

manifest 为 host ABI v4 / protocolVersion 2，materialVersion 为 `629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b`，与[当前生产三包](v4-production.md)匹配。两端实际编译的 kernel 均包含配置的生产 origin；这不证明 App 已连接该 origin。

| 成品          | kernel SHA-256                                                     |
| ------------- | ------------------------------------------------------------------ |
| iOS Simulator | `e643a348b84c5afd9f1a59e41d9d11e86e944a4afea0088d070dfb5130b25a4d` |
| Android arm64 | `9a89fc4d2e0f1af622fa633cde2e8fcecb89bb3c269d63b19d3492610ff22bf7` |

## 构建与 SQLite

在 `apps/reader` 执行以下正式入口命令；SDK 路径按当前环境设置，依赖仍以锁文件为准：

```sh
/private/tmp/karuyomi-flutter-sdk/bin/flutter build ios \
  --simulator --debug --no-pub --no-codesign --target=lib/main.dart \
  --dart-define=APP_ORIGIN=https://karuyomi.wybxc.cc
env \
  JAVA_HOME=/Users/wybxc/karuyomi/runtime/teavm/.local/jdks/jdk-25.0.5+8/Contents/Home \
  ANDROID_HOME=/Users/wybxc/karuyomi/runtime/teavm/.local/android-sdk \
  ANDROID_SDK_ROOT=/Users/wybxc/karuyomi/runtime/teavm/.local/android-sdk \
  GRADLE_USER_HOME=/Users/wybxc/karuyomi/runtime/teavm/.local/gradle \
  /private/tmp/karuyomi-flutter-sdk/bin/flutter build apk \
  --debug --no-pub --target=lib/main.dart --target-platform=android-arm64 \
  --dart-define=APP_ORIGIN=https://karuyomi.wybxc.cc \
  --no-android-gradle-daemon \
  --android-project-arg=android.builder.sdkDownload=false
```

iOS 首次构建失败于 sqlite3 3.5.2 官方 GitHub 文件的下载连接。复用本地同版本官方 native-assets 文件前，逐项核对包内固定 SHA-256，再放入当前构建的标准 shared download 缓存。未修改 pub-cache 源码、编译 hook 或输入/输出记录；未关闭 TLS 或校验。原 hook 随重试重新校验缓存，iOS 最终构建成功。原始失败日志保留，不能写成首次成功。

- iOS SQLite arm64/x64 原文件摘要分别为 `1ce8ac8e…502510b`、`7bf9c426…fff2fcfbd7`。实际 `sqlite3.framework/sqlite3` 同时包含 arm64/x86_64；两种 NativeAssetsManifest 映射均指向该 framework，`sqlite3_open_v2`、`sqlite3_prepare_v2`、`sqlite3_close_v2` 导出存在。
- Android arm64 原文件/Gradle merged 输出摘要为 `0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161`。APK 中的库与正式 Gradle stripped 输出逐字节相同，为 1732360 B、SHA-256 `081df67ee9ab852daea6a0679427e90fc89a0245d06f93dafe2309875c609c5c`；三个 SQLite 导出仍存在。去除调试符号是构建转换，不能将包内摘要不同误判为下载文件损坏。
- Android 本轮仅构建/核对 arm64 NativeAssetsManifest。`aapt` 的通用 native-code 列表还包含插件的其他 ABI，不能据此宣称 SQLite 的其他 ABI 或对应设备已通过。APK 为 debuggable、minSdk 24、targetSdk 36，不是正式签名发布或性能成品。

## 交互限制与后续验收

本轮重新查询 CUA，应用 surface 仍没有 Simulator；按已确认的完整 Simulator.app 路径连接返回 `Invalid app`。`simctl` 只读确认没有 booted 设备。没有改用其他 UI 自动化技术，也没有安装、启动 App 或操作生产登录。旧 be5 本地 HTTPS 证书已于 2026-11-04 过期，旧成品/服务不作为本轮 v4 证据。

后续须在可控制设备上安装当前成品，从正式主入口完成 Native WebView 自己的 Access 登录，再验证选源、真实图片阅读、进度、退出/后台恢复和会话失效/重新认证。IAB 会话不与 Native 共享；当前构建与内置资源一致性不替代这些门。真机、当前 v4 Native Source 运行和完整 P0 均仍待验收。

构建日志、缓存来源与完整摘要、临时 TypeScript 成品核对工具及报告留在 ignored `.local/v4-native-main/`；机器 JSON 和成品不提交源码。历史 be5 的主入口准备失败继续保留在[原记录](native-main-entry.md)，历史受控双端 Reader 证据仍按各自输入维护。
