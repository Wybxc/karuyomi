# Web 与 iOS 服务端状态验证

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-05：正式 Flutter 入口已完成本地真实 workerd/D1 下的 Web 收藏、iOS 阅读保存、Web 非默认页续读及回看保存。首轮两次 iOS 官方集成测试通过；随后独立隔离 run 从 Web 保存第 2 页，全新 Native 恢复第 2 页并回看保存第 1 页，通过第三次集成测试，补齐 Web↔iOS 双向非默认位置恢复。完整 P1/P2、生产 Access、Android 配对与真机仍待验收。

## 输入、身份与环境

- 测试入口以 `fe43afd` 新增的 `apps/reader/integration_test/server_sync_test.dart` 为基线；反向 run 在此基础上将最远进度断言加强为至少 `max(startPage, targetPage)`，本轮已实际运行。它调用正式 `app.main()`，使用真正的 `NativePlatformRuntime`、系统 WebView、内置运行时材料、Source、ReaderScreen 和业务 API；不注入测试 runtime、内存业务服务或图片 supplier。
- Web 操作使用 Codex 内置浏览器与正式 Flutter Web 构建；Native 使用本轮可丢弃 iPhone 17 Pro 模拟器、iOS 26.4，测试由 Flutter 官方 `integration_test` 驱动。该结果不代表物理触控、真机性能或 Native 视觉检查。
- 每个 run 只启动一个 `source-metadata-probe.ts` 进程，同时提供 Web 的 `http://127.0.0.1:8897` 和 Native 的 `https://localhost:8898`。两个 listener 共用同一个 handler、真实 workerd 和隔离 D1；反向 run 重新建立独立状态，不沿用首轮 D1。它们是明确的测试代理别名，不是生产 origin 或 Cookie 共享的证明。
- `/api/*` 由代理提供真实 RS256 测试 assertion，正式鉴权逻辑验证测试 JWKS、身份和请求约束。可信 subject 为 `probe-owner`；没有执行生产 Cloudflare Access 登录或身份切换。
- HTTPS 使用当日生成、SAN 覆盖 localhost 的正常有效证书，仅向本轮专用模拟器加入签发 CA。未运行 `mkcert -install`，未修改 Mac 全局信任、既有模拟器或产品 TLS 校验。首轮证书预验包含一次对 `/runtime/host` 的 HEAD 请求。
- 原版 xkcd 扩展为 `eu.kanade.tachiyomi.extension.all.xkcd` 1.6.1，Source ID 为 `1538249443376436084`；构建为 `ext-all.xkcd-d923dd3fb233cfd194936da9cca51309`，host ABI 为 `karuyomi-source-host-v4`、protocolVersion 2。扩展通过正式静态索引、清单和 gzip 产物加载，未修改扩展业务代码或原 JAR。
- 共享 materialVersion 为 `629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b`。测试章节为 `3319: Elevators`，共 2 页；使用正式 Source 请求与图片通道，不由 UI 直接请求原图 URL。

## 首轮实际结果

| 步骤                                | 实际结果与权威读取                                                                                                                                                                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Web 从正式 UI 收藏 xkcd             | 按钮变为“移出书架”；`GET /api/library` 返回 favorite=true、account revision=1。                                                                                                      |
| 首次 iOS 启动，`START=1 TARGET=2`   | 从服务端书架进入详情与指定章节；等第 1 页真实解码帧后，通过正式“下一页”显示第 2 页。UI 显示服务端已保存，正式 repository/API 读回 current 第 2 页、furthest 第 2 页。测试 1/1 通过。 |
| 新 Web 会话从书架继续阅读           | 新会话看到收藏 1 部；“继续阅读”恢复 `3319: Elevators` 的 `2 / 2`，真实文字图可见，显示服务端已保存。这证明 Web 恢复 iOS 已确认的非默认位置。                                         |
| Web 使用“上一页”回看并保存          | 显示 `1 / 2` 与服务端已保存；独立 state 读取为 current 第 1 页、furthest 第 2 页，account/manga revision=9。回看没有抹掉最远位置。                                                   |
| 第二次 iOS 启动，`START=1 TARGET=2` | 重新从服务端书架进入同章，第 1 页与第 2 页的真实帧均通过；保存后读回 current/furthest 第 2 页，account/manga revision=11。测试 1/1 通过。                                            |

两次 iOS 输出均为 epoch 0，current 的 normalizedOffset=0，furthest 的 normalizedOffset=1，未显式标为完成。`ios-first-state.json` 的 revision=5 是新 Web 已进入详情后的只读采样，包含元数据刷新，不能当作纯 iOS 写入次数；详情刷新和正常打开也会产生业务写入。ProtoJSON 省略的零值按协议解码为 0，不表示缺失页码。

本轮稳定身份如下，便于复核而无需保留整份机器输出：

- mangaKey：`62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f`。
- chapterKey：`3ebd1a075e8cc6fad4cae9daa7595caac80545bdf9499496417bb3d3b6b1142c`。
- manifestVersion：`ed4c8a330872e37255bc114025ec7ff7b16ab9e83f2d2d210b493df3204a46b7`；第 1/2 页 pageKey 分别为该版本加 `:0` / `:1`。

首轮 Web 保存第 1 页后，Native 也从第 1 页启动，但这与无恢复时的默认位置相同；该次结果单独不足以证明反向恢复。以下独立 run 用非默认起始位置补齐这一证据。

## 独立反向恢复结果

反向 run 使用新的隔离 workerd/D1 和全新专用 iOS 模拟器 `D6464DFC-D8E8-4DC3-8E13-2B5B3BF4107A`，沿用同版正式 xkcd 构建、业务身份和章节身份。没有通过恢复旧客户端业务数据来准备起始位置。

| 步骤                                 | 实际结果与权威读取                                                                                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Web 正常 UI 阅读并保存非默认第 2 页  | Codex 内置浏览器已观察 `2 / 2`；独立业务 API 的 `reverse-web-state.json` 确认 account/manga revision=3，current/furthest 均为第 2 页、furthest offset=1。                                                                                                                                                     |
| 全新 Native 启动，`START=2 TARGET=1` | 从服务端书架进入同一章节，先等第 2 页真实解码帧，再通过正式“上一页”回到第 1 页；UI 保存状态与正式 API 读回均满足测试，`ios-reverse.log` 为 1/1 通过。                                                                                                                                                         |
| Native 确认位置与最远进度            | `SYNC_RESULT` 的 current 为第 1 页、offset=0，furthest 仍为第 2 页、offset=1，epoch=0；独立 `reverse-native-state.json` 进一步确认 account/manga revision=5、current pageKey=`:0`、furthest pageKey=`:1`、hint=1、offset=1。章节与清单身份一致，强化后的最远进度断言实际通过，回看没有使最远进度退回第 1 页。 |

这次 Web 标签页在最后一次“已保存”文字确认前被浏览器工具清理，所以仅记录已观察的页码与独立 API 确认，不声称看到了该次 Web 保存状态文字；首轮的保存文字观察保留原范围。非默认第 2 页经独立 API 确认后，全新 Native 实际先显示第 2 页，不能由默认第 1 页解释，因此 Web→iOS 恢复门已通过。与首轮 iOS→新 Web 恢复第 2 页的结果共同构成本地测试身份下的双向闭环。

反向最终 state 中 current 的 `pageIndexHint` 和 normalizedOffset 按 ProtoJSON 省略零值，解码为第 1 页、offset=0；epoch=0、completed=false。该独立读回与集成测试输出一致，不以首轮 revision 或计数代替本轮结果。

## 图片、材料与清理边界

集成测试通过语义标签定位当前页下的 `RawImage`，要求非空 `ui.Image` 及有效宽高，并同时核对当前页码；不是只有图片资源返回或 spinner 消失就通过。目标页获得“阅读进度已保存到服务端”后，再调用正式 `ProgressRepository.loadChapter`，经业务 API 实际 GET 检查章节、清单、pageKey、current 和 furthest。它没有用本地确认缓存代替服务器读取；Web 的文字图与续读另经内置浏览器观察。

首轮最终 `network.json` 的 `tlsRequestPathOverflow=false`，HTTPS 共记录 `/runtime/host` 3 次、bootstrap 2 次、扩展索引 2 次、清单 4 次、gzip 产物 2 次和 HTTP bridge 12 次。`/runtime/host` 包含前述一次 HEAD，不能把全部计数都归因 Native 初始化。没有 `/runtime/materials.json`、任何 `/runtime/materials/*`、`/runtime/host.js` 或 `/runtime/worker.js` 请求；HTTP 浏览器流量不进入这些 TLS 计数。

反向最终 `reverse-network.json` 同样为 `tlsRequestPathOverflow=false`：`/runtime/host`、bootstrap、扩展索引和 gzip 产物各 1 次，书架 2 次、清单 2 次、HTTP bridge 5 次、mutation 2 次、指定作品 state GET 5 次。仍无材料清单、材料正文、`/runtime/host.js` 或 `/runtime/worker.js` 请求。

这两次观测结合正式 Native 内置材料校验、Source 实际运行与解码图片，支持“两轮 Native 均没有从该 HTTPS origin 回退下载共享材料”。计数器只覆盖该 listener 的 pathname，不独立识别客户端，也不证明其它 origin 的全部网络行为；超过记录预算或证据未成功持久化时不能作完整观测结论。它不改变材料服务行为，不能把零路径计数单独当作阅读通过。

首轮 `harness.log` 保留了一次 Web 标签中断对应的 `AbortError`，cause 为 `probe_client_disconnected`；未将这次中断写成成功请求。两个 run 均无 `Could not persist` 错误，反向 harness 日志未出现 error。

测试返回详情并等待章节入口重新启用，再显式等待当前章节 provider 的同一幂等 close future；该 future 涵盖取消、迟到资源释放和 page-session ACK。随后卸载 App，等待进度关闭及正式 Native runtime/file-store dispose；失败不会输出最终 `SYNC_RESULT`。这些证据证明当前章节 provider 与 Native 容器的成功关闭，未单独故障验收所有 UI cache eviction、邻章预取或私有 scheduler 聚合清理 future，不扩大为完整生命周期门。

两轮服务均已通过 Ctrl-C 停止，端口 8897/8898 已确认无监听。首轮专用模拟器 `B7151FAC-DF8A-432D-8051-17CB4F52A137` 与反向专用模拟器 `D6464DFC-D8E8-4DC3-8E13-2B5B3BF4107A` 均已 shutdown、delete，命令退出码为 0。原始报告、证书与私钥只留忽略目录，不入库；后续 run 使用新的隔离状态和可丢弃设备。

## 工程检查

增强后的集成测试通过 `flutter analyze --no-pub integration_test/server_sync_test.dart`；`pnpm check:dependencies` 通过。含既有生产三包快照的 `EXTENSION_ASSETS_DIR="$PWD/.local/v4-production/snapshot" pnpm build` 完成正式 Flutter Web release、Native 材料组装、62 文件静态资源检查和 Worker dry-run。共享材料版本不变，没有启动新 AOT 或部署生产。`fe43afd` 的开发分支与 main CI 均已成功；本轮最远进度断言另由上述实际反向测试覆盖。

## 复验与剩余门

启动同一 workerd/D1 的 HTTP/HTTPS 服务、准备受信本地证书以及执行 Native 测试的完整步骤见[正式集成测试说明](../../apps/reader/integration_test/README.md)和[Source 测试服务](../../apps/api/test/source-metadata-probe.md)。运行正式 `app.main()`，不要替换成历史机制入口、fake runtime 或测试图片供应者。

当前 iOS 命令形态如下；页码必须匹配 Web 已确认的当前章节状态：

```sh
cd apps/reader
flutter test integration_test/server_sync_test.dart --no-pub \
  -d IOS_SIMULATOR_UUID \
  --dart-define=APP_ORIGIN=https://localhost:8898 \
  '--dart-define=SYNC_CHAPTER_LABEL=3319: Elevators' \
  --dart-define=SYNC_START_PAGE=1 \
  --dart-define=SYNC_TARGET_PAGE=2 \
  --reporter expanded
```

复验反向恢复时，先从 Web 正常 UI 保存第 2 页并通过独立 API 确认，再在全新 Native 安装中将 `SYNC_START_PAGE` 设为 2、`SYNC_TARGET_PAGE` 设为 1；不能以默认第 1 页启动代替这一门。

必要原始证据位于忽略的 `.local/server-sync-native/`：`ios-first.log`、`ios-second.log`、`web-favorite.json`、`ios-first-state.json`、`web-back-state.json`、`ios-second-state.json` 与首轮 `network.json`；反向结果保留在 `reverse-web-state.json`、`ios-reverse.log`、`reverse-native-state.json` 与 `reverse-network.json`。两轮服务日志分别为 `harness.log`、`reverse-harness.log`。文档只保留有用结论；不复制正文、详细日志或凭据。

尚待单独完成：Web↔Android 和 iOS↔Android、实际并发/前台重取/Access 恢复、生产正向登录、物理设备触控与性能，以及分类、书签和同步设置。基础 API 幂等/冲突与 Web 独立会话证据见[服务端状态记录](server-state.md)，生产部署边界见[生产记录](server-state-production.md)。少量 xkcd 实测不提升其它扩展的 `compiled_unverified` / `runtimeReady=false` 状态。
