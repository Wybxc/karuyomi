# Cache v3 移动 WebView 机制验收

2026-11-04，固定 `31555e8e367405501b7f485f534f533e0299a6cd`，Android 与 iOS 的真实 WebView 均通过未修改的正式 **39 组** Cache 桥套件，最终 `HeadlessInAppWebView.dispose()` 成功。这是移动引擎中的 Worker / IndexedDB / Web Locks 机制门，未运行 Java CacheInterceptor 或正式 Source，不代表生产 Access、物理设备、完整 Native Cache 或性能验收。

## 输入与结果

独立受管树为 `/Users/wybxc/.codex/worktrees/native-cache-v3-validation/karuyomi`，受跟踪文件保持干净。使用 Node 24.15.0、锁定的 npm 依赖、Flutter 3.47.5 / Dart 3.13.4 和官方 `flutter_inappwebview 6.2.0-beta.3`。无需 Java、seed 或扩展 AOT。

正式 `compileBridge('cache')` 与 [Worker driver](../../packages/runtime-host/test/cache-lifecycle-worker.ts)、[browser suite](../../packages/runtime-host/test/cache-lifecycle-browser-suite.ts) 由固定源码编译。以下实际服务字节与 [Chromium 39 组主报告](http-cache-runtime.md#namespace-固定分区门) 逐项一致：

| 产物                      | SHA-256                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| 产品 Cache 桥             | `7fc988f9937eaaf232c42a52e61e9a45112377e4d09be857386b356e77c36518` |
| 桥与测试 driver 的 Worker | `d0d93b4f8be48a30c1d014aaf157d19340a9fc900af502ecfa52b1e89ad1f98d` |
| browser suite             | `cce9f8a3317720e566ab42a8fad6cf66a7628a146a2ba4e0438d53fd1a15de72` |

| 实际环境                                                                                     | 结果                        |
| -------------------------------------------------------------------------------------------- | --------------------------- |
| Android Emulator 37.2.13，Google APIs ARM64 API 36 r7 / Android 16，WebView `133.0.6943.137` | 39/39，`disposePassed:true` |
| iPhone 17 Pro Simulator，iOS 26.4，Xcode / SDK 27.2，实际 WKWebView                          | 39/39，`disposePassed:true` |

两端实际检查 `secureContext`、`indexedDB`、`webLocks`、`worker` 均为 true，没有替代这些 API。套件的 39 个 check 名称原样保存在结果中，覆盖活 owner / handle / CAS / clear generation、死亡 Worker 回收、不可变 snapshot pin、chunk 损坏与真实事务 abort，以及跨目录 namespace 配额。实际写入 16384 个不超过 8 KiB 的块到 128 MiB 边界和两个 Worker 争用最后一个 payload 字节均通过；未篡改 usage 值伪造边界。计费是逻辑 reservation，不是进程、GPU 或物理磁盘峰值。

UA 原文另存于 JSON：Android 包含 `Android 16`、`Chrome/133.0.6943.137`、`wv`；iOS 为 `Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148`。后者不能据此改称设备运行 iOS 18.7；实际模拟器 runtime 由 `simctl` 确认为 iOS 26.4。这是 Flutter 内嵌 WebView，不是桌面 Safari 或 Codex 内置浏览器。

## TLS 与清理

正式 runner 只监听 loopback，HTTPS 前端正常验证 `https://localhost:9448/`。既有证书有效期为 2026-11-03 04:17:53 UTC 至 2026-11-04 04:17:53 UTC，本轮执行时有效。iOS 使用已受信的系统证书链及官方默认处理，没有自定义 server-trust 回调；未使用 PROCEED、trust exceptions 或忽略证书错误。

Android 仅在 ignored、可丢弃的独立 debug App 中使用此前验过的 exact-localhost CA 配置：保留系统 CA，`includeSubdomains=false`、`overridePins=false`、禁止明文，不安装全局 CA。APK 实际 manifest、网络策略及解包证书均已核对。独立 applicationId / bundleId 为 `dev.karuyomi.karuyomi.nativeCacheV3Fixture`，未覆盖已有 Source App 或 SQLite 数据。

Native 驱动只加载正式页面，读取其原始结果，并在 finally 中等待真实 WebView dispose；任何 dispose 异常都会将整门置为失败。两个正式 runner 均收到对应平台报告并退出 0，Native 报告的 39 项及 UA 与 runner 报告一致。完成后关闭自有 HTTPS 服务、移除本次 adb 9448 映射，模拟器和 App 数据保留，其他 Source 服务未改动。

## 复验与本地材料

正式 [runner](../../tools/teavm/check-cache-storage.ts) 可从干净检出使用；Native 夹具与 HTTPS 编排仅保留在上述固定树 ignored 的 `.local/cache-native/`，不是新产品入口：

```sh
# 固定树根目录；按仓库固定版本安装依赖
git rev-parse HEAD
pnpm install --frozen-lockfile
node .local/cache-native/compile-identity.ts
node tools/teavm/check-cache-storage.ts --port 0 --timeout-ms 300000 \
  --report .local/cache-native/ios-suite.json

# 另一个终端；53823 是本轮实际端口，复验须使用 runner 新输出的端口
CACHE_GATE_UPSTREAM=53823 node .local/cache-native/https.ts

# .local/cache-native/app/apps/reader；使用锁定 SDK、PUB_CACHE，移除发布凭据
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub --target lib/fixture/cache_main.dart
flutter build ios --simulator --debug --no-codesign --no-pub \
  --target lib/fixture/cache_main.dart
```

两端分别启动 runner、安装并启动独立 App，不复用上一轮成功结果。Android 使用 `adb reverse tcp:9448 tcp:9448`；iOS 使用 `simctl install` / `launch`。App 从 Application Support 输出 `native-cache-<platform>.json`，最终报告只在 dispose 后生成。过期证书须正常更新并重新建立测试信任，不能跳过验证。

`.local/cache-native/` 中保留 `input.json`、`compiled-identity.json`、`https.ts`、`app/`、正式 runner 的 `{android,ios}-suite.json`、原 App 的 `{android,ios}-native.json` 和核对后的小报告 `{android,ios}-result.json`。Android 最终报告 SHA-256 为 `6a9c0ebfe65c10b88eaaa5291b5e631de37d1863ff0bed45ebff4ea754be3204`，iOS 为 `c9f52ea1339778a68850f869c3b1dc043ea414d35ba28526e9f42016c622b6aa`；完整日志未复制入库。

保留的早期失败不计入套件成功：

- `ios-fixture-trust-cancel-failed.json`：测试驱动误将每次 server-trust 回调一律 CANCEL。WKWebView 对正常证书也发此回调，`sslError:null` 仍被夹具取消，尚未运行 Cache。仅移除 ignored 驱动回调，恢复官方 `.performDefaultHandling` 后重验；未改产品或套件。
- `ios-port-collision.log`：8898 已被另一项 Source probe 占用，runner 明确 `EADDRINUSE` 失败。停止自己的夹具，改用 runner 随机端口；未停止其他服务。
- iOS 首次构建遇到官方 sqlite3 x64 simulator 下载失败，保留 `app/ios-build.log`。随后仅预热同一官方 SHA-256 的已有下载缓存，由未修改的 hook 重新验证；`app/ios-build-cached.log`、`app/ios-build-default-trust.log` 记录后续成功。

双端结果不扩展为 Native 正式 Source Cache 命中、Java CacheInterceptor、生产登录、物理设备或性能结论；这些仍需各自固定输入和独立验收。
