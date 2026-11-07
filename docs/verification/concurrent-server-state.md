# 阅读状态一致性验证

本文分别记录历史双 Web 的手动刷新与写冲突、[双 iOS 模拟器](#双-ios-模拟器前台-epoch-冲突)及 [Android 前台恢复与 iOS 重置](#android-前台恢复与-ios-重置同一账户)。各分项均使用正式阅读入口和真实隔离 workerd / D1。

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
