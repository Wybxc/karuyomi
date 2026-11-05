# Android 服务端状态与 Native 配对验证

2026-11-05：正式 Flutter 入口已通过测试身份下的 Web↔Android、iOS↔Android 非默认页恢复，以及 Native 正式阅读和 D1 保存。四次 Android、两次 iOS 官方集成测试各 1/1 通过，新 Web 会话实际恢复 Android 保存的第 2 页。Native HTTPS 观测未见共享材料网络回退；本轮后台进程、端口与临时设备目录已完成清理复核。本记录不代表完整 P1/P2、生产 Access 或真机验收。

## 输入与测试边界

- 应用与 `integration_test/server_sync_test.dart` 以 `86fc43d` 为固定输入，调用正式 `app.main()`、NativePlatformRuntime、Source、ReaderScreen 和业务 API，不注入 fake runtime、内存业务服务或图片供应者。扩展、材料和章节沿用[Web/iOS 记录](native-server-state.md#输入身份与环境)的原 xkcd 1.6.1、v4 材料与 `3319: Elevators` 两页。
- Android 使用本轮新建的可丢弃 Android 16 / API 36 Google APIs ARM64 模拟器，emulator 37.2.13、WebView 133.0.6943.137。iOS 配对使用独立 iPhone 17 Pro / iOS 26.4 模拟器；Web 操作使用 Codex 内置浏览器。测试由官方 Flutter `integration_test` 驱动，不等同于物理触控、Native 视觉检查或真机性能。
- Android 副本只位于忽略目录。177 个受管文件比对中，仅 applicationId、debug Manifest 和 Gradle 运行配置三个测试打包文件有预期差异，业务源码和集成测试逐字节一致。实际 APK 为 `dev.karuyomi.serversync`，保留正式 `dev.karuyomi.karuyomi.MainActivity`；包内 manifest、host、worker 与正式 Native 材料逐字节一致。
- 实际 APK 的 Network Security Config 保留系统 CA、禁止明文，仅 exact `localhost` 信任本轮专用 CA，`includeSubdomains=false`、`overridePins=false`；包内 CA 与输入一致。没有修改产品信任、已有 AVD 或 Mac 全局信任，也没有放行证书错误。本轮只运行正常 TLS 正向链路，错误 CA、非 localhost 等负例未执行。
- HTTP Web 和 HTTPS Native 是同一测试代理的明确 origin 别名，共用真实 workerd/D1 和经签名校验的 `probe-owner` 身份。它们不是生产 origin、Access Cookie 共享或真实身份切换的证明。

## 首次失败与业务状态恢复

首轮 Web 已通过正常 UI 保存第 2 页，但启动时签发的测试 JWT 在 Android 测试前超过 30 分钟有效期。bootstrap/state 返回 401，`android-from-web.log` 中正式测试进入 Access-paused 状态并失败；本次不能计为同步或 Access 恢复通过。

`307a372` 将测试代理改为每次 `/api/*` 转发时以相同 subject、issuer、audience 和 key ID 现场签发真实 RS256 assertion，当前 `iat`、有效期仍为 30 分钟，正式校验器继续验证每个请求。没有缓存不失效的凭据、延长旧凭据或修改产品鉴权/TLS。该测试代理行为不证明生产 Access 登录、过期或恢复；相关门须单独验收。

为保留已经确认的 Web 状态，使用 SQLite 官方在线 `.backup` 创建 `before-renewal.sqlite`，再以 `.mode insert` 导出 `account_state`、`manga_state`、`chapter_progress`、`state_mutations` 四张业务表。重启隔离后端后导入，再导出为 `restored-business.sql`，与 `restore-business.sql` 逐字节相同。独立 API 的 `web-start-state.json` 确认 account/manga revision=4、favorite=true、current/furthest 均为第 2 页。

恢复的是本轮 Web 正式 UI 已保存的数据，没有用 SQL 制造新的预期进度；后续客户端共用重新建立的同一个 workerd/D1。此操作仅为测试服务重启保留现场，不是产品备份恢复能力或生产 D1 恢复验收。

## 已通过的正式入口结果

| 操作                                                   | 实际结果与独立 API 读回                                                                                                                                                                                                                                      |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Android 从 Web 已确认的第 2 页开始，`START=2 TARGET=1` | `android-from-web-renewed.log` 为 1/1 通过；先显示第 2 页真实解码帧，再经正常“上一页”回看。`android-from-web-state.json` 为 revision=6、current 第 1 页、furthest 第 2 页。非默认起点排除了默认首页掩盖恢复错误。                                            |
| Android 再次启动，`START=1 TARGET=2`                   | `android-for-ios.log` 为 1/1 通过；正常阅读并保存第 2 页。`android-for-ios-state.json` 为 revision=9、current/furthest 第 2 页。此步骤证明正式写入，为 iOS 非默认恢复准备状态。                                                                              |
| iOS 从 Android 已确认的第 2 页开始，`START=2 TARGET=1` | `ios-from-android.log` 为 1/1 通过；先显示第 2 页再正常回看。`ios-from-android-state.json` 为 revision=11、current 第 1 页、furthest 第 2 页。                                                                                                               |
| iOS 再次启动，`START=1 TARGET=2`                       | `ios-for-android.log` 为 1/1 通过；正式阅读并保存第 2 页。`ios-for-android-state.json` 为 revision=14、current/furthest 第 2 页。此步骤为 Android 非默认恢复准备状态。                                                                                       |
| Android 从 iOS 已确认的第 2 页开始，`START=2 TARGET=1` | `android-from-ios.log` 为 1/1 通过；先显示第 2 页再正常回看，测试进程已退出。`android-from-ios-state.json` 为 revision=16、current 第 1 页、furthest 第 2 页，完成 iOS→Android 读回。                                                                        |
| Android 再次启动，`START=1 TARGET=2`                   | `android-for-web.log` 为 1/1 通过、进程 exit=0；正式保存第 2 页。`android-for-web-state.json` 为 revision=19、current/furthest 第 2 页。                                                                                                                     |
| 新 Web 会话从书架“xkcd→继续阅读”进入                   | 首次即恢复 `3319: Elevators` 第 2 页，全程未翻页；Codex 内置浏览器 AX 显示 `2 / 2`、已保存到服务端、最远第 2 页，截图实际显示 Elevators 文字图片。关闭页面后独立 `web-readback-state.json` 为 revision=21、current/furthest 第 2 页，完成 Android→Web 读回。 |

各结果的作品、章节和 manifest 身份相同，pageKey 对应同一 manifest 的实际页索引，epoch=0、completed=false；current offset=0，furthest 保持第 2 页、offset=1。ProtoJSON 省略的零值按协议解码为 0。revision 包含详情刷新及正常打开产生的写入，不等同于点击次数。

六次 Native 正式集成测试同时要求当前页码和有效 `RawImage.image`，等待服务端保存提示，再经正式 repository/API GET 核对 current/furthest；没有把图片返回、spinner 消失或本地缓存当成完成。每次成功输出在当前章节 provider 的资源 ACK、进度关闭和 Native runtime/file-store dispose 之后产生；不扩大为所有 UI 缓存与邻章预取的故障清理验收。

## 网络观测与收尾

最终 `network.json` 的 `tlsRequestPathOverflow=false`，Native HTTPS 路径计数包含六次 `/runtime/host`，以及 bootstrap、索引、扩展产物、业务 API 和 Source HTTP 桥请求；没有 `/runtime/materials.json`、`/runtime/materials/*`、`/runtime/host.js` 或 `/runtime/worker.js`。结合 APK 材料核对，本轮正式 Native 链路未通过网络回退获取内置共享材料。此观测限于本轮流程，不是任意故障条件下的穷尽证明。

测试代理已响应中断并退出，`8897`、`8898` 均无监听。Android 的本轮 `8898` reverse 已移除，专用模拟器退出后，通过本轮独立 Android 用户目录执行 `avdmanager delete avd`，确认其 `.ini` 和 `.avd` 目录均不存在；配对 iOS 模拟器已关机并删除，设备列表无该 UUID、无启动设备。ADB 设备列表为空后已停止 server，最终进程复核未见本轮 adb、workerd、测试代理、模拟器、Flutter 集成测试或 Gradle daemon 遗留。

## 复验与待补证据

准备同一后端的 HTTP/HTTPS 服务见[Source 测试服务](../../apps/api/test/source-metadata-probe.md)，正式入口与断言见[Native 集成测试说明](../../apps/reader/integration_test/README.md)。使用固定源码的独立 debug 副本、锁定依赖与独立 Gradle/Pub 缓存，只加入上述 localhost 专用 CA；不要修改业务源码或正式产品 TLS。Android 仅对本轮设备设置反向端口：

```sh
adb -s ANDROID_SERIAL reverse tcp:8898 tcp:8898
cd apps/reader
flutter test integration_test/server_sync_test.dart --no-pub \
  -d ANDROID_SERIAL \
  --dart-define=APP_ORIGIN=https://localhost:8898 \
  '--dart-define=SYNC_CHAPTER_LABEL=3319: Elevators' \
  --dart-define=SYNC_START_PAGE=2 \
  --dart-define=SYNC_TARGET_PAGE=1 \
  --reporter expanded
```

运行前先以正常 Web/另一 Native UI 保存非默认第 2 页，并独立读回确认；构建环境不得携带 GitHub 或 Cloudflare 发布 token。保留首次失败和随后成功的不同日志，不覆盖原始失败。临时工程、SQLite 备份/导出、JSON、APK、证书与私钥均留在忽略的 `.local/android-server-sync/`，不提交。

实际并发/前台重取、生产 Access、物理设备、分类、书签和同步设置仍按[P2](../plan/p2-sync.md)继续验收；少量 xkcd 分项不提升其它扩展的 `compiled_unverified` / `runtimeReady=false` 状态。
