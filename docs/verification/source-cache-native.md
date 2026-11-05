# 原 xkcd Source 的 Native HTTP Cache

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

状态：**iOS / Android 模拟器均通过原 Java Source 的 metadata 冷请求、热正文复用及正式 Native 容器重建后复用**。两端均通过正式 `NativePlatformRuntime` 加载同一原扩展 AOT；不是受控 TS supplier、桥机制门或 Java 精确 hit 计数。没有更改图片 cacheless 行为。

## 固定输入与执行环境

2026-11-04，固定验证树 `/Users/wybxc/.codex/worktrees/source-network-cache-validation/karuyomi` 的提交为 `b4f72f70804f12caef21bb51a17cb5adad6982d4`，构建和执行前后跟踪输入干净。原 JAR / AOT 身份与 [Web 原 Source Cache 证据](source-network-cache.md) 相同；使用 protocol 2 / host ABI v3 / bridge 2。

| 输入                     | 身份                                                               |
| ------------------------ | ------------------------------------------------------------------ |
| hostFingerprint          | `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db` |
| buildId                  | `ext-all.xkcd-b33800f6d02ddab83b60b6d7ac85b49d`                    |
| 原 JAR，125470 B         | `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d` |
| canonical AOT，4038599 B | `4d6f571a4d4e806512a9d28fc8a2f93f59a44bbe5c02a6eec809f90f2579ad02` |
| materialVersion          | `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d` |
| Native manifest，2393 B  | `9b5e83244b2941839b798136d0aa8c040817820077b7582f55ead335c9a6623b` |
| 内置 host，616969 B      | `168a20f474ad1448f98ddac7ad733a00f1ff1ceaf12b6ac9f0cd158a7533a444` |
| 内置 Worker，1320565 B   | `d74b5fb8ac476af64b8b1df8d6dfcda5c93f1e8b2852dc2e92d76c084cbbbeb8` |

隔离 App 由固定树的正式 Flutter 工程和两个 Dart package 复制到 ignored 目录，独立 App ID 为 `dev.karuyomi.karuyomi.nativeSourceCacheB4FixtureRun2`，使用锁定的 `flutter_inappwebview 6.2.0-beta.3`。iOS 为 iPhone 17 Pro Simulator / iOS 26.4 / WKWebView；Android 为 API 36 arm64 模拟器 / WebView `133.0.6943.137`。两端正式 debug 构建、测试入口 Dart analyze 和观察器严格 TS 检查通过。

控制页分别使用正常 HTTPS `https://localhost:9449` / `:9450`，转发至独立真实 workerd、隔离 D1 和受控 RS256 的 `probe-owner` 测试身份；网络策略只批准 `xkcd.com`、`imgs.xkcd.com`。iOS 使用已信任的测试 CA；Android 仅在隔离 debug App 对精确 `localhost` 增加测试 CA，禁止明文、不覆盖 pin，没有 TLS 忽略回调。没有操作生产登录或部署。

正式 Native host 和 Worker 资产先按摘要验证后内置加载。夹具仅在原产品 Worker Blob 之后追加观察后缀，原样透传 `teaCache` / `teaCacheRead` / `teaCacheWrite` 的参数、返回和异常；原始 Blob、合并 Blob 与后缀摘要保存在逐阶段报告。后缀 SHA-256 为 `5226d6502eafef1e704fe96a9eda65ab8592779bd5304b1a2c3e5bf5f32e85f8`。没有改原 Source/JAR、AOT、桥材料或请求头，也没有注入成功结果。两端网络版 runtime host/Worker/materials 请求记录均为空。

## 实际结果

通过原 popular / details / chapters 取得实际章节 `/3318/`，每次调用原 pages 后等待 Page 会话关闭确认。随后正式 `platform.rebuild()` 销毁并重建控制容器，再正常 open 相同 build；新 generation 与旧值不同。每阶段网络计数取真实网络流水的 before/after 增量。

| 阶段                   | iOS store / 上游                                                                 | Android store / 上游 |
| ---------------------- | -------------------------------------------------------------------------------- | -------------------- |
| cold                   | get1/miss1/begin1/commit1；写入共 7187 B；上游 1 次 200/7187 B                   | 同左                 |
| warm                   | get1/entry1；读取 7187 B、EOF1、reader-close1；上游 0                            | 同左                 |
| 正式 Native 容器重建后 | 新 generation；get1/entry1，读取 7187 B、EOF1、reader-close1；上游 0             | 同左                 |
| 最终清理               | 三个 Page 会话均关闭；`NativePlatformRuntime.dispose()` 确认；cleanupErrors 为空 | 同左                 |

六次 pages 均返回原 2 页，PageList SHA-256 均为 `cf4df2da1b455de6533e8a3563e764ef414857c49b3f574f27b702bed0665bd4`。所有阶段 store/观察器错误为 0，双端 `passed=true`、`finished=true`。实际流的分块数不同：iOS cold 写 2 次、热读含 EOF 共 3 次；Android 为 3 / 4 次。正文长度、EOF、关闭确认与实际网络流水是验收依据。

完整报告留在该固定树 `.local/native-source-cache/`：

| 报告                        | SHA-256                                                            |
| --------------------------- | ------------------------------------------------------------------ |
| `ios-report-final.json`     | `6a2fb1f310edabffadd62a98779f00df6b6f841712daebf8737fcdc0788de459` |
| `android-report-final.json` | `3b714d807764bc9593e3d0659fee222a63c237424829c3993dc8408f804c50f4` |

`validate-results.ts` 对两份报告的固定身份、冷提交、热正文/EOF、零网络、新 generation、PageList 和清理重新断言，严格类型检查与执行均退出 0；`summary.json` 保存精简结果。完整上游流水和网络资源记录另存 `{ios,android}-network-final.json` / `{ios,android}-native-resource-network.json`。

## 复验入口与首轮问题

临时 Flutter 工程、观察器与 HTTPS 编排均保留在上述 ignored 目录，不作为维护源码。复验需有效且正常受信的 localhost 测试证书、锁定工具链及相同正式构建输入；另用新 App ID / 数据目录并另存报告，避免把已有 Cache 当作 cold。保留的主要命令如下，iOS 与 Android 分别使用 `8924/9449`、`8925/9450`：

```sh
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com SOURCE_PROBE_IMAGES=1 \
SOURCE_PROBE_PORT=8924 SOURCE_PROBE_EVIDENCE=.local/native-source-cache/ios-http.json \
node .local/network-cache-source/cache-observation/server.ts \
  .local/network-cache-source/xkcd/manifest.json \
  .local/network-cache-source/xkcd/artifacts
SOURCE_GATE_PLATFORM=ios SOURCE_GATE_UPSTREAM=8924 SOURCE_GATE_HTTPS_PORT=9449 \
node .local/native-source-cache/https.ts

# 在 .local/native-source-cache/app/apps/reader 中，固定 Flutter SDK：
flutter analyze --fatal-infos --no-pub lib/fixture/cache_main.dart
flutter build ios --simulator --debug --no-codesign --no-pub \
  --target lib/fixture/cache_main.dart
flutter build apk --debug --no-pub --target lib/fixture/cache_main.dart
# 分别正常安装至模拟器；Android 仅映射本轮 HTTPS 端口。
adb -s emulator-5556 reverse tcp:9450 tcp:9450
```

App 自动执行并将结果写入正式 Application Support 目录；iOS 用 `simctl get_app_container` 定位，Android 用隔离 App 的 `adb exec-out run-as` 读取。将报告另存为上表文件后，在固定树执行 `node .local/native-source-cache/validate-results.ts`。完成后正常结束本轮四个服务并移除 `tcp:9450` 映射；本轮已完成这些回收。

首轮 iOS 报告 `ios-report-first.json` 保留 `passed=false`：fixture 将初始 archive 操作与重建阶段都标为 `metadata`，错误累计了早先网络流水。其 cold/warm 及重建后真实 store 读取均已完成；修复仅发生在 ignored fixture，改为网络 before/after 增量，并以新 App ID 重跑，未修改产品。Android 首次构建因公开 Maven/Google 依赖的 DNS/TLS 下载失败；之后设置 `GRADLE_USER_HOME` 为既有 `/Users/wybxc/karuyomi/runtime/teavm/.local/gradle`，复用相同官方依赖缓存后构建成功，未修改依赖或 TLS。

本项没有发生 304；store 事件不等于 Java CacheInterceptor 精确计数。只证明原 xkcd 元数据在双端模拟器正式 Native runtime 中的 fresh 正文复用和容器重建保留，没有重启 App/系统进程，没有验收图片 Cache、完整阅读 UI、跨版本/身份切换、真机、生产 Access 或性能。其它 Source 的 Native Cache 仍待独立验收。
