# 阅读状态一致性验证

本文记录历史双 Web 的手动刷新与写冲突、[双 iOS 模拟器前台冲突](#双-ios-模拟器前台-epoch-冲突)、[Android 前台恢复与 iOS 重置](#android-前台恢复与-ios-重置同一账户)、[Android 已加载阅读断连与显式重试](#android-已加载阅读断连与显式重试)，以及阅读进度已提交后丢确认的 [Web](#web-阅读进度已提交后丢确认)、[iOS](#ios-模拟器阅读进度已提交后丢确认)和 [Android](#android-模拟器阅读进度已提交后丢确认)复验。各分项均使用正式阅读入口和真实隔离 workerd / D1。

> 双 Web 入口状态（2026-11-05）：保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。历史双 Web 结果不算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-05：两个真实 Flutter Web 阅读文档保持打开，在本地真实 workerd/D1 和同一受验签测试身份下，已通过远端位置/epoch 更新时保持旧画面、停止旧视图写入、明确重开采用权威位置，以及未先刷新时正常写路径进入 revision 冲突的分项。业务操作按下表顺序执行，未测试两个写请求同时到达；本记录不代表完整并发、恢复或 P2 验收。

## 输入与边界

- 使用正式 Flutter Web 入口、原版 xkcd 1.6.1、v4 材料及 `3319: Elevators` 两页，扩展、材料与稳定身份沿用[三端配对记录](android-server-state.md)。没有替换 runtime、图片 supplier 或业务数据库。
- 当前文档提交为 `c7b0deb`。`git diff --exit-code 86fc43d -- apps/reader packages/source_runtime packages/reader_core packages/runtime-host apps/api/src protocol` 无差异，正式产品代码与已验证输入相同；测试代理使用 `307a372` 的逐请求真实 RS256 签名，subject 为 `probe-owner`，由正式校验逻辑验证。
- Codex 内置浏览器的 A 为 `http://127.0.0.1:8897`，B 为 `http://localhost:8897`。两条明确的测试 origin 别名连接同一个测试代理、workerd 和隔离 D1；不同 origin 的存储空间避免 Source namespace 执行互斥。它不证明同 origin 多标签可同时执行同一 Source，也不证明生产 Access、Cookie 共享或真实身份切换。
- 两端都通过正式浏览、书架、详情和阅读控制操作；业务状态另经只读 API 确认。详情刷新和正常打开章节会产生业务写入，revision 不等于翻页次数。

## 已通过的实际结果

| 操作                                            | 实际 UI 与服务端结果                                                                                                                                                                                                                                                         |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 正常浏览、收藏 xkcd，打开指定章节并选择单页   | 第 1 页真实原图显示，UI 确认已保存。`a-initial.json` 为 account/manga revision=3，current/furthest 均为第 1 页、epoch=0。                                                                                                                                                    |
| B 从服务端书架进入详情并继续阅读，再翻到第 2 页 | 第 2 页保存确认后，`b-page-two.json` 为 account/manga revision=6，current/furthest 均为第 2 页、epoch=0。                                                                                                                                                                    |
| A 手动“刷新进度”                                | 仍显示 `1 / 2` 及第 1 页真实图片，明确提示“阅读进度已在其他设备更新，当前阅读位置保持不变。请重新打开本章后继续保存。”；按钮改为“重新打开本章”，“重新阅读本章”和完成操作禁用。                                                                                               |
| A 正常翻到第 2 页，再回到第 1 页                | 阅读仍可继续，冲突提示保持。`a-conflicted-reading.json` 与 `b-page-two.json` 经 `cmp` 逐字节相同，revision 仍为6，current/furthest 仍为第 2 页；旧视图没有覆盖服务端状态。                                                                                                   |
| A 明确“重新打开本章”                            | 首次显示 `2 / 2` 及真实文字图，确认已保存。`a-reopened.json` 为 revision=7、epoch=0、current/furthest 均为第 2 页。                                                                                                                                                          |
| B 刷新、重新打开后“重新阅读本章”                | 刷新先提示“此作品已在其他设备更新”且保持第 2 页；明确重开后再重新阅读，实际显示第 1 页并保存。`b-reset.json` 为 revision=10、epoch=1、current/furthest 均为第 1 页。新 epoch 首图实际显示后已产生观察进度，furthest 不再为空。                                               |
| A 刷新后继续在旧视图翻页                        | 原画面保持 `2 / 2`，提示“本章进度已在其他设备重置，当前阅读位置保持不变。请重新打开本章后继续保存。”；重新阅读和完成禁用。A 回看第 1 页再到第 2 页，警告保持；`a-stale-epoch-reading.json` 与 `b-reset.json` 逐字节相同，revision 仍为10，新 epoch 的第 1 页未被旧视图覆盖。 |
| A 再次明确“重新打开本章”                        | 首次显示 `1 / 2` 并确认已保存。`a-reopened-reset.json` 为 revision=11、epoch=1、current/furthest 均为第 1 页，采用了服务端重置后的状态。                                                                                                                                     |
| B 不先刷新，直接正常翻到第 2 页                 | UI 先显示待服务端确认，节流写路径随后进入“此作品已在其他设备更新，请重新打开本章后继续保存。”状态。画面仍为 `2 / 2`，重新阅读和完成禁用；`b-stale-revision.json` 与 `a-reopened-reset.json` 逐字节相同，revision 仍为11，B 的旧视图未覆盖服务端。                            |
| B 明确“重新打开本章”恢复                        | 首次恢复第 1 页真实原图，UI 确认已保存。关闭两页后独立 `b-final-reopened.json` 为 revision=12、epoch=1、current/furthest 均为第 1 页。                                                                                                                                       |

ProtoJSON 省略的零值按协议解码。前两组逐字节比对证明刷新已发现冲突后，旧视图继续翻页没有产生新的业务写入；它们不单独证明旧请求被发送并拒绝。最后一项单独覆盖未先刷新时的正式写路径冲突及权威状态未变；未取得该请求的精确 HTTP 状态码证据，不将 UI 文案写成已观察到 HTTP 409。实际 API 的 CAS、epoch 与幂等事务测试另见[服务端状态记录](server-state.md)。

## 复验与剩余门

启动同一后端的正式 Flutter 模式见[Source 测试服务](../../apps/api/test/source-metadata-probe.md)。使用同一当前 xkcd 构建和明确的 `xkcd.com,imgs.xkcd.com` 测试网络政策，分别打开上述两个 origin。先等待 A 第 1 页的真实图片与保存确认，再由 B 保存第 2 页；A 刷新前后分别记录页码、提示及只读业务状态。刷新后正常翻页不应提升服务端 revision 或覆盖 B 的位置。恢复前台也可能触发刷新，复验时记录实际触发路径，不以手动操作意图代替观察结果。

只读业务 API 同时携带 `X-App-Request: 1` 和与受验签身份匹配的 `X-App-Subject: probe-owner`，通过 library/state 取得作品与章节键；该 header 仅校验会话绑定，不能选择账户。请求缺少或不匹配 subject 时不能作为有效状态证据。

原始状态、网络和临时日志留在忽略的 `.local/sync-conflicts/`，不提交。必要状态比对命令：

```sh
cmp .local/sync-conflicts/b-page-two.json \
  .local/sync-conflicts/a-conflicted-reading.json
cmp .local/sync-conflicts/b-reset.json \
  .local/sync-conflicts/a-stale-epoch-reading.json
cmp .local/sync-conflicts/a-reopened-reset.json \
  .local/sync-conflicts/b-stale-revision.json
```

两页已关闭，测试服务收到中断后退出；独立进程复核未见该测试代理或 workerd，`8897` 无监听。Miniflare 退出后遗留的本轮临时 D1 与静态快照目录已精确删除，必要 API 状态与网络证据保留在上述忽略目录。

上述历史双 Web 分项尚未验收：实际前台自动刷新事件、断网/重连、响应丢失、同时到达的写竞争、Native 生命周期、生产 Access 和真机。分类、书签与同步设置继续按[P2](../plan/p2-sync.md)推进，少量 xkcd 分项不提升其它扩展的运行兼容标记。

## 双 iOS 模拟器前台 epoch 冲突

2026-11-07，两个独立 iPhone 17 Pro / iOS 26.4 模拟器在同一官方 Wrangler HTTPS harness 和全新隔离 workerd / D1 下通过测试。固定产品提交为 `d2a21aadc2eeb450f717389eac3760e96ed808e1`；阅读驱动 SHA-256 为 `ae88f7f6f45298cbdd3fc52f4ec718b5a9349f60c21d3ea8a6e79686af2f78f4`。正式 `app.main()` 使用本机 WebView、包内 runtime materials、真实 xkcd 图片和受验签测试身份 `acceptance-owner`。两端都以系统信任校验同一 `https://127.0.0.1:58084`，仅登记 `xkcd.com` 和 `imgs.xkcd.com`。使用[三包静态候选](aot-current-pilot.md#绑定摘要后的正式三包和同站-web-更新)中的英文 xkcd（Source ID `1538249443376436084`，canonical 摘要 `969bd86a14e9850b3c4bffe9c827ff7ce52a2eb5e3e4e3437ca70587ddbc6926`），作品 `SINGLE`、章节 `/3319/`（3319: Elevators）。未替换 Source、图片或业务读写。

| 阶段                   | 实际 UI 与独立服务端读回                                                                                                                                                                                                                                              |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 准备并开始阅读       | 正式安装并收藏后，account / global / manga revision 为 `2 / 1 / 1`，无书签与进度。A 打开真实第 1 页并翻至第 2 页，确认保存；通过系统打开设置进入 `PAUSED`。最后一次正常视口保存后，独立 GET 为 `4 / 1 / 3`、epoch 0，current / furthest 均在第 2 页。                 |
| B 正式重新阅读         | A 保持后台。B 从书架标题进入详情，续读真实第 2 页后点击“重新阅读本章”，回到真实第 1 页，收到 epoch 1 的确认。退出阅读并等待清理确认后，独立 GET 为 `7 / 1 / 6`、epoch 1，第 1 页，furthest 缺省。                                                                     |
| A 回前台并继续看旧画面 | 通过系统回到同一 PID `74827` 和原阅读叶，无手动刷新。A 自动提示另一端重置，保留第 2 页真实图与原 provider，禁用“重新阅读本章”和“读完本章”。旧叶实际翻 `2 → 1 → 2`；重开前独立取得的六路响应与 B 退出后完全相同，驱动跨 3 秒保存观察窗再次只读检查也确认权威进度未变。 |
| A 明确重开并退出       | 点击“重新打开本章”，旧资源取得清理确认，新阅读叶首次在 epoch 1 显示第 1 页真实图；退出后独立 GET 为 `9 / 1 / 8`，current / furthest 均在第 1 页。                                                                                                                     |

六路 GET 为 `/api/settings`、`/api/library`、作品状态、作品书签、作品章节进度列表和带精确 `chapterKey` 的章节状态。对照完整响应与作品/章节身份，忽略采样时间和阶段标签。B 重置后的快照与 A 旧叶翻页后的快照相同，证明旧叶没有覆盖 D1；该证据未记录全部 POST。正常打开、关闭或视口观察可保存导航，因此 revision 不等于重置次数。

首轮使用另一隔离 D1。测试驱动点击书架整行的中心，误命中内嵌的续读图标，B 直接打开真实第 2 页；驱动等不到详情，120 秒后失败。该轮未执行重置，独立 GET 仍是 epoch 0，A 也未恢复前台。只把驱动改为点书架标题，两台专用模拟器卸载该测试应用并使用全新 D1，重走三阶段均 1/1 通过。首轮失败日志与截图保留。

### 复验与证据

按[驱动说明](../../apps/reader/integration_test/README.md#阅读中的前台-epoch-冲突)准备匹配 ABI 的静态候选、Native 内置 runtime、已正常信任本轮 CA 的两台独立 iOS 模拟器。在仓库根目录，以固定工具链运行：

```sh
EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm --filter @karuyomi/api build
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts --mode native-acceptance
NODE_EXTRA_CA_CERTS=/absolute/path/rootCA.pem \
WRANGLER_HTTPS_KEY_PATH=/absolute/path/key.pem \
WRANGLER_HTTPS_CERT_PATH=/absolute/path/cert.pem \
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
  pnpm acceptance:serve
```

在 `apps/reader` 先对 A 运行 `bookmarks_sync_test.dart` 的 `prepare`，再分别对 A、B 运行 `server_sync_test.dart` 的 `resume` 和 `reset`：

```sh
flutter test integration_test/bookmarks_sync_test.dart --no-pub \
  -d "$device_a" --dart-define-from-file="$prepare_defines" --reporter expanded
flutter test integration_test/server_sync_test.dart --no-pub \
  -d "$device_a" --dart-define-from-file="$resume_defines" --reporter expanded
flutter test integration_test/server_sync_test.dart --no-pub \
  -d "$device_b" --dart-define-from-file="$reset_defines" --reporter expanded
```

A 的 `resume` 保持运行；在另一终端等 `SYNC_RESUME_READY` 后运行 `xcrun simctl launch "$device_a" com.apple.Preferences`，观察 `SYNC_RESUME_PAUSED` 再执行 B。B 测试结束并独立采样后，运行 `xcrun simctl launch "$device_a" dev.karuyomi.karuyomi`，核对同一 PID。复验时提前监听 `SYNC_RESUME_STALE_VIEW` 采集显式重开前的独立快照。只读请求使用正常 TLS 和 `Origin`、`X-App-Request: 1`、`X-App-Subject: acceptance-owner`。比对归档可运行：

```sh
diff -u <(jq -S '{identity, responses}' api-b-reset.json) \
  <(jq -S '{identity, responses}' api-a-stale.json)
```

原始阶段配置、输入摘要、两轮日志、`api-*.json` 和旧叶取样时序保留在 `/private/tmp/karuyomi-native-epoch-d2a21aa-KgLChg/`；成功轮使用上述修正后的驱动摘要，`first-attempt/` 保存首轮失败。两轮 harness 已退出，测试端口无监听，两台本轮专用模拟器已关闭和删除。此分项仅覆盖双 iOS 模拟器、顺序写入和真实系统前后台；混合模拟器的复验见下节。Web 阅读自动前台、同时写竞争、断网、生产 Access 和真机仍分别验收。

## Android 前台恢复与 iOS 重置（同一账户）

2026-11-08 在固定产品提交 `a14ee43d2ac272fe89ae6c88a9b1291d2c2a5345` 的独立副本，用 Flutter 3.47.5 / Dart 3.13.4 复验。正式 `server_sync_test.dart` 的 SHA-256 为 `ae88f7f6f45298cbdd3fc52f4ec718b5a9349f60c21d3ea8a6e79686af2f78f4`。A 为新建 Pixel 9 / Android API 36 ARM64（`emulator-5586`），B 为新建 iPhone 17 Pro / iOS 26.4（`BC36D11B-3491-47D9-98EB-002BEF22F938`）。两台设备使用同一全新官方 HTTPS harness（`https://127.0.0.1:58319/`、`acceptance-owner`）与 D1；未修改 AOT。确切扩展为 `ext-all.xkcd-0ba2a6ca758deefaae43a1fe569a0654-969bd86a14e9850b3c4bffe9c827ff7ce52a2eb5e3e4e3437ca70587ddbc6926`，英文 Source `1538249443376436084`，作品 `SINGLE`、章节 `/3319/`（Elevators）。Android 以专用 ADB 将相同端口转入模拟器，隔离 debug APK 只对 `127.0.0.1` 追加测试 CA，保留系统根与 hostname 校验，禁用明文；Dart 驱动也用标准 CA 输入。

iOS `prepare`、iOS `reset`、Android `resume` 三次正式测试均通过。A 保存第 2 页后以 `adb shell input keyevent KEYCODE_HOME` 真实暂停；B 恢复第 2 页，点击「重新阅读本章」并确认新 epoch，退出取得资源释放确认。随后 Android 用 launcher intent 热恢复同一 task、同 PID `3385`。A 在测试主动读取或点击之前显示远端重置提示，仍保留旧阅读页、图片与第 2 页，重置与读完按钮不可用。A 在原页面实际翻页 `2 → 1 → 2`，独立六路 GET 与 B 退出后的完整响应逐字段相同；驱动等待 3 秒后再次只读检查，仍未覆盖服务端状态。A 显式点「重新打开本章」后采用已确认的新锚点、显示真实第 1 页，旧资源释放成功。

| 节点                             | 账户 / 全局 / 作品 revision | 目标章                         |
| -------------------------------- | --------------------------- | ------------------------------ |
| iOS 安装并收藏                   | 2 / 1 / 1                   | 无进度                         |
| Android 已进入后台               | 5 / 1 / 4                   | epoch 0；当前与最远均为第 2 页 |
| iOS 重置并退出                   | 8 / 1 / 7                   | epoch 1；当前第 1 页，无最远锚 |
| Android 旧页面翻页后、显式重开前 | 8 / 1 / 7                   | 六路响应与上一步完全相同       |
| Android 显式重开并退出           | 10 / 1 / 9                  | epoch 1；当前与最远均为第 1 页 |

复验沿用前一节的 harness、驱动与六路比对，`prepare` 由 B 执行，A 加 `SYNC_TEST_CA_BASE64`，见[集成测试说明](../../apps/reader/integration_test/README.md#阅读中的前台-epoch-冲突)。阶段日志、OS 生命周期、输入摘要与独立 GET 保存在 `/private/tmp/karuyomi-mixed-epoch-a14ee43-LZI43e/results.json` 同目录。本轮两次临时 HTTPS 均已关闭，专用 ADB、AVD 和 iOS 模拟器已清理，无本轮监听或进程残留。该证据覆盖 Android 模拟器前台恢复和 iOS 模拟器顺序重置；未验证 Web 前台、同时写竞争、断网、生产 Access 或真机。独立 GET 证明旧页面没有覆盖 D1，不能据此断言从未发送写请求。

## Android 已加载阅读断连与显式重试

2026-11-08，固定产品提交 `4a7f7c3bb8b55a73c3209f3e86b266bba45ac92d`，Flutter 3.47.5 / Dart 3.13.4。新建 Pixel 9 / Android API 36 ARM64（`emulator-5582`）和 iPhone 17 Pro / iOS 26.4（`F59A3249-6EB3-46CE-90BB-FEB07EB9CE0B`）共用正式 HTTPS harness `https://127.0.0.1:52326/`、受验签测试身份 `acceptance-owner` 与新隔离 D1。Native 使用正式 `app.main()`、WebView、内置运行时材料及原版英文 xkcd Source `1538249443376436084`，作品 `SINGLE`、两页章节 `/3319/`（Elevators）。静态构建为 `ext-all.xkcd-0ba2a6ca758deefaae43a1fe569a0654-969bd86a14e9850b3c4bffe9c827ff7ce52a2eb5e3e4e3437ca70587ddbc6926`；未重新编译 AOT。Android 测试 CA 仅用于本轮 loopback 验收，禁用明文，保持标准证书与 hostname 校验。

| 节点                                      | 账户 / 全局 / 作品 revision | 实际结果                                                                                                                                         |
| ----------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| iOS 正式安装并收藏                        | 2 / 1 / 1                   | 无书签或进度。                                                                                                                                   |
| Android 在线解码两页并回到第 1 页         | 5 / 1 / 4                   | epoch 0，当前第 1 页、最远第 2 页。                                                                                                              |
| 仅阻断 A 到该 HTTPS 端口，真实翻至第 2 页 | 5 / 1 / 4                   | 同 PID `4961`、同阅读页及 Source provider；已加载的第 2 页真实图像仍可显示，UI 明确提示未保存且「重试保存」可用。六路独立 GET 与断连前完整相同。 |
| 撤规则后点击「重试保存」                  | 8 / 1 / 7                   | 恢复连接时草稿仍在；显式重试后 UI 清除未保存提示。独立 D1 确认当前与最远均为第 2 页，epoch、章与清单身份不变。                                   |
| iOS 重新打开同一章节并正常回看            | 10 / 1 / 9                  | 正式阅读先恢复第 2 页真实图，再回看第 1 页；最终当前第 1 页、最远第 2 页、epoch 0。                                                              |

断连规则仅作用于专用 Android 模拟器的 `lo → 127.0.0.1:52326`，用 TCP reset 覆盖已有和新建连接，实际命中 5 个 TCP 数据包；ADB 转发始终保持。独立请求按本页同样六路 TLS GET 采样，断连窗口没有业务变更，之后除了该章进度及修订号外其余业务字段不变。仅删除 ADB reverse 的首轮仍可复用既有 HTTPS 连接并保存，因此未通过断连门；使用新 D1 后复验。iOS 首次因旧驱动没有筛选长章节列表而未找到目标；六路无变化，修正精确章节搜索后才通过。

复验见[驱动说明](../../apps/reader/integration_test/README.md#已加载阅读在-android-断连后重试)。Android 实际通过驱动摘要为 `fd81725da5c94f02723c98232d370a09080d84e4f698f650765aff9b7d1d910f`；iOS 重跑的驱动为 `8c60bf6a22795794303e4c7313d1d1350f0276179422d5e0df2ab21a002d9918`，只额外调整明确指定构建的 `navigate` 选择和身份断言。原始证据在 `/private/tmp/karuyomi-android-reader-offline-4a7f7c3-whQNym/results.json` 同目录。两轮服务退出、临时网络规则已撤回、专用 Android AVD、私有 ADB 和 iOS 模拟器已清理，无本轮监听或进程残留。

本分项验证真实服务连接中断时已加载阅读可继续，以及同一会话显式重试、另一设备续读；未覆盖设备全断网、服务已提交后丢 ACK、请求 UUID/单次写入、进程关闭后草稿恢复、生产 Access 或真机。

## Web 阅读进度已提交后丢确认

2026-11-08，固定产品 `aef05f7` 的正式 Flutter Web 与官方 Wrangler/Vite harness，Codex 内置浏览器连接 `http://127.0.0.1:59128`、测试身份 `acceptance-owner` 和全新隔离 workerd/D1。使用[同一原版 xkcd 静态构建](#android-已加载阅读断连与显式重试)，仅登记 `xkcd.com` 和 `imgs.xkcd.com`。未替换业务客户端、Source 或图片请求。

| 节点                                       | 账户 / 全局 / 作品 revision | 实际结果                                                                                                    |
| ------------------------------------------ | --------------------------- | ----------------------------------------------------------------------------------------------------------- |
| A 正式安装、收藏、打开 `/3319/` 并翻到末页 | 6 / 1 / 5                   | 已保存；当前与最远均为第 2 页，epoch 0，未读完。                                                            |
| A 点「读完本章」，成功响应正文中断         | 7 / 1 / 6                   | 同一阅读页保留「重试保存」；独立 GET 已读到 `completed=true`，当前/最远仍为第 2 页，章、清单与 epoch 不变。 |
| A 点「重试保存」                           | 7 / 1 / 6                   | 变为已保存，重试入口消失；六路只读业务响应与上一阶段完整相同。                                              |

夹具只在显式启用后观察已通过正式鉴权、校验和事务的指定章末页完成请求，先核实匹配的持久 D1 回执，再中断首次 HTTP 200 正文。停服审计只有两条目标记录，`drop_ack=1/0`；两次 UUID、原始正文 SHA-256、预期作品 revision 5、正式 ACK 摘要及持久回执摘要完全一致。D1 只提交了一次；正常翻页不消耗故障。业务 POST 均来自正式浏览器 UI，独立采样只发 GET。实测时底层网络错误文案说「尚未保存到服务器」；根据现场，将这类不确定结果改为「尚未获服务器确认」，不改变写入与重试行为。

使用包含该 xkcd 候选的当前静态快照复验：

```sh
EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build
ACCEPTANCE_FIXTURE=progress-ack-loss \
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
  pnpm acceptance:serve
```

在打印的本地地址通过正式界面准备第 2 页，分阶段从独立进程比较设置、书架、作品、书签、进度与指定章节六路 GET。按 Enter 停止后核对 `ACCEPTANCE_PROGRESS_ACK_AUDIT`，要求恰好两次观察及上述身份相等。原始采样、夹具摘要与服务日志保存在 `/private/tmp/karuyomi-web-progress-ack.jqHHp8/`；服务正常退出且端口已释放。两项官方 Workers 回归另覆盖普通末页观察、其它章、409、默认关闭及既有设置夹具；不把这轮 Web 验收当作 Native、实际断网、同时写、生产或真机验收。

## iOS 模拟器阅读进度已提交后丢确认

2026-11-08，使用固定 `5e6a526` 加本次 Reader 改动的隔离产品副本、iPhone 17 Pro / iOS 26.4 模拟器、官方 HTTPS harness 与空 D1。专用设备正常信任回环测试 CA，身份为 `acceptance-owner`。用固定 `c04d436` 的当前 v6 原版 xkcd 1.6.1 独立 AOT 候选（revision `6a46bd01d90a432686a8b28b9180cbd6`）；核对构建指纹与全量计划相同，产品生成的 Native host、worker 与材料清单和候选逐字节相同。正式 `prepare` 安装并收藏英文 xkcd，仅登记 `xkcd.com` 和 `imgs.xkcd.com`。

前次真实复验中，首次丢响应及显式重试已复用同一个 UUID，但还有一条新 UUID 的完成进度写入，只有 `current.viewportY` 改变。底部控件变化会使阅读区重新布局：恢复同一个已解码的原图点时，约束把它放在略有不同的屏幕相对高度，旧逻辑将该变化记录为新的进度。单独固定保存控件高度仍重现第三条请求。现在当外部窗口与阅读宽度不变、仅阅读区高度发生变化时，同一可见且未被裁切的原图点保留原视口放置偏好；真实窗口变化、用户手势、翻页和原图锚修正仍按原逻辑。定向回归实际改变章节控件高度并检验窗口变化后的渲染锚。

修复后重装同一专用模拟器的正式应用，从空 D1 重跑[正式驱动](../../apps/reader/integration_test/README.md#阅读进度已提交后丢确认)：

| 节点                          | 账户／作品 revision | 实际结果                                                                                     |
| ----------------------------- | ------------------- | -------------------------------------------------------------------------------------------- |
| 打开原 `/3319/` 并确认第 2 页 | `4/3`               | 当前、最远均第 2 页，epoch 0，未完成；普通进度已确认。                                       |
| 点「读完本章」，成功响应中断  | `5/4`               | 独立进程已读到完成，原 Reader 与图像仍在，客户端显示待确认与重试。                           |
| 点「重试保存」                | `5/4`               | 原 Reader 清除待确认，页码、清单、epoch 与锚点保持；独立六路完整业务响应与上一阶段完全相同。 |

正式驱动通过 1/1。停服审计恰好两条，`drop_ack=1/0`，UUID、请求原始字节摘要、预期作品 revision 3、ACK 与持久回执摘要全部相同。原始设备报告、对照快照、审计和失败复现保存在 `/private/tmp/karuyomi-ios-ack-current.uX8fbo/`；AOT 快照和材料证据见 `/private/tmp/karuyomi-xkcd-v6-c04d436.S0u88B/`。本轮证明实际 iOS 模拟器及此进度请求；Android 另见下节，同时写、生产 Access 和真机另验。

## Android 模拟器阅读进度已提交后丢确认

2026-11-08，固定产品提交 `9ef3ccbf0add36577a447536219752aa1b85270e`，Flutter 3.47.5 / Dart 3.13.4，专用 Pixel 9 / Android API 36 ARM64 模拟器（`emulator-5596`，系统 WebView `133.0.6943.137`）。官方 Wrangler HTTPS harness 为 `https://127.0.0.1:63457`，使用 `acceptance-owner` 和独立空 D1；通过私有 ADB 将同一实际端口转给模拟器。隔离 debug APK 仅对 `127.0.0.1` 添加本轮测试根 CA，保留系统根、标准证书和 hostname 校验，并禁用明文；Dart 驱动用标准 CA 输入。实际 APK 的 CA、Native host、worker 和材料清单均核对过原始字节；材料与上一节当前 v6 xkcd 候选一致。

正式 xkcd 英文 Source 为 `1538249443376436084`，作品 `SINGLE`，构建为 `ext-all.xkcd-31777c287c69f021ac4ebcdcd0a35cac-43d97485f779b768af7861a6a25522db433ab6d229a6d989e70e3f3c88a848a3`。本轮执行的 `server_sync_test.dart` SHA-256 为 `2934cf908298317644e83db3ee5fe7d4ecb3777cbe15e5e416af7ec28f4e0aea`。

| 节点                          | 账户／全局／作品 revision | 实际结果                                                                                     |
| ----------------------------- | ------------------------- | -------------------------------------------------------------------------------------------- |
| 安装当前英文 xkcd 并收藏      | `2/1/1`                   | 正式 `prepare` 从账户 revision 0 起跑；独立读回无阅读进度。                                  |
| 打开原 `/3319/` 并确认第 2 页 | `4/1/3`                   | 真实图片已解码，当前与最远均为第 2 页，epoch 0，未完成。                                     |
| 点「读完本章」，成功响应中断  | `5/1/4`                   | 独立 GET 已读到 `completed=true`；同一 Reader 保留待确认草稿和「重试保存」。                 |
| 点「重试保存」                | `5/1/4`                   | 同一进程（PID `4501`）和 Reader 清除待确认；当前、最远、清单、epoch 和原图／视口锚保持不变。 |

`prepare` 和 ACK-loss 驱动各通过 1/1。独立进程在驱动仅输出 `SYNC_ACK_LOSS_READY` 时已取得提交后快照；重试后设置、书架、作品、书签、进度和指定章六路完整 GET 响应逐字段相同。停服审计恰好两条（`drop_ack=1/0`），同一 UUID `a8cef6b7-cab4-4ec9-992d-50ebf08a4bbd`、预期作品 revision 3、原始请求正文、ACK 与持久回执摘要逐项一致，D1 只提交一次。

复验使用[正式驱动及阶段参数](../../apps/reader/integration_test/README.md#阅读进度已提交后丢确认)。从独立产品副本构建，生成包含 `127.0.0.1` IP SAN 的回环证书，并按该说明为隔离 debug APK 配置 WebView 信任：

```sh
EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build:native
NODE_EXTRA_CA_CERTS=/absolute/path/rootCA.pem \
WRANGLER_HTTPS_KEY_PATH=/absolute/path/key.pem \
WRANGLER_HTTPS_CERT_PATH=/absolute/path/cert.pem \
ACCEPTANCE_FIXTURE=progress-ack-loss \
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
  pnpm acceptance:serve
```

从实际输出取得端口并执行 `adb -s "$device" reverse "tcp:$port" "tcp:$port"`；在 `apps/reader` 依次用 `flutter test -d "$device" --dart-define-from-file=...` 运行 `integration_test/bookmarks_sync_test.dart`（`prepare`）和 `integration_test/server_sync_test.dart`（`ack-loss`）。两份阶段参数分别用 `BOOKMARKS_TEST_CA_BASE64`、`SYNC_TEST_CA_BASE64` 追加同一测试根。核对独立 GET，按 Enter 停服取得 `ACCEPTANCE_PROGRESS_ACK_AUDIT`。

阶段输入、APK 校验、设备日志、快照及汇总见 `/private/tmp/karuyomi-android-ack-9ef3ccb.9Uq8k8/verified.json` 同目录。已撤下 reverse，停止官方 harness、私有 ADB，删除专用 AVD 并核对相关端口释放。该分项只证明此 Android 模拟器与同一进程中的指定完成请求；同时写竞争、关闭后的草稿、生产 Access 与真机不在此分项。

## 阅读进度同时写：正式 API 与 D1 夹具

2026-11-08，独立空 D1 上的官方 Wrangler 回环 HTTPS harness（`https://127.0.0.1:54760`，`acceptance-owner`）验证了 `ACCEPTANCE_FIXTURE=progress-cas-race`。两个独立 Node 进程（PID `61015`、`61016`）使用相同作品 revision 1、相同两页清单、epoch 0 和不同 UUID，分别提交完成第 2 页与重置请求。用正式 API 先保存未完成的第 2 页，使用真实 xkcd 作品与章节键及合成页键；此次未启动 Reader、Source 或图片加载。

停服审计恰好两条，两条请求都通过正式 Worker 的鉴权、请求校验和写前读取，到达 D1 原子批次入口后才提交原有批次；两条 Worker 处理窗实测重叠 3 ms。完成写入返回 HTTP 200 并有唯一持久回执，重置返回 HTTP 409 / `REVISION_CONFLICT`、无回执，两条响应的权威进度与作品相同。第三个独立进程（PID `60878`）只读同一章，读到与两条响应相同的状态：账户和作品 revision 各从 1 增至 2，当前及最远均为第 2 页、已完成、epoch 仍为 0。

官方 Workers 全套 8 文件 86 项通过；新增回归覆盖两种到达顺序、普通观察和其它章节不占槽、单请求超时，以及两条虽均准入但只有一条到达 D1 批次时不写入。夹具和复验步骤见[正式驱动说明](../../apps/reader/integration_test/README.md#阅读进度同时写)，原始请求、响应、审计及汇总见 `/private/tmp/karuyomi-progress-cas.qWCrho/verified.json` 同目录，服务已停止。此项仅证明 API 层事务竞争；两个正式 Reader 的冲突提示、画面保持、显式重开和权威状态收敛仍待验。

## 双 iOS 阅读器的开章基线

2026-11-08，固定 `4e5ca90`，使用同型号 iPhone 17 Pro / iOS 26.4 模拟器、正常信任的同一隔离 HTTPS/D1 与当前 v6 英文 xkcd。正式界面安装、收藏后打开 `/3319/`，真实第 2 页已解码，当前和最远均为第 2 页，未完成，epoch 0，账户／作品 revision `4/3`。

同一模拟器新进程打开原章，无翻页或平移，独立六路 GET 显示 revision 增至 `5/4`；进度内唯一变化是 `current.viewportY` 从 `0.3830245901639345` 到 `0.3762630057803469`。原图坐标、页和清单、最远、完成和 epoch 均不变。验收协调器拒绝继续；停服审计 `[]`，没有执行完成或重置。失败对照在 `/private/tmp/karuyomi-ios-progress-cas.l682bk/first-attempt/`。

确认续读的阅读叶在首帧尺寸与布局恢复期间保持已保存的放置偏好，前提是同一原图点仍可见、未被裁切。真实翻页、手势、显式跳转、外部窗口变化与新的已解码观察仍走原流程。Flutter 回归用延迟解码复现不同的实际屏幕落点，核对保存锚保持且新观察正常发布，显式跳转则按新位置更新。正式双 Reader 的竞争与重开另验。
