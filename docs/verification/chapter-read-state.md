# 章节已读状态与范围操作验证

2026-11-06，章节标已读/标未读已从 Protobuf 合同、Worker API、现有 D1 进度表接入正式详情 UI。支持读状态筛选、多选及当前显示顺序的闭区间操作；标记不请求 Source `pages()` 或图片。状态与批次语义见[设计](../design/chapter-read-state.md)。以下分别记录真实 workerd/D1 回归、受控客户端 supplier 和独立客户端实测。

## 协议与真实 D1

`business-state.test.ts` 9 项、官方 Cloudflare Vitest 的 `state-workerd.test.ts` 30 项通过。后者包含本轮新增的 6 项章节状态回归，使用正式 Worker 路由、隔离 D1 和测试 RSA 身份，覆盖：

- 未打开章节可直接标已读或未读，保留独立 epoch，不伪造页面锚；标记不创建 resume 或 Source 元数据。
- 标已读保留已有真实 current/furthest；标未读清除 current/furthest，重新阅读复位到实际首页，两者清除完成状态并提升 epoch。普通保存跨 manifest 保留章级已读状态。
- 收藏、分类、元数据、resume 和书签保留；并发 CAS 只有一个胜者，原 UUID 重试不重复提升 epoch，旧 ACK 不恢复已清除状态。
- 64 项分页包含未读 epoch，固定 account revision，验证身份隔离、游标与快照变化；事务失败回滚进度、revision 和幂等结果，epoch 达上限时明确拒绝。

本轮同时修复上一里程碑的正式合同缺口：`SetFavorite` 无条件要求 metadata，导致批量移出书架的无 metadata 请求在进入 store 前被拒绝。合同现仅在字段存在时校验，新增作品收藏仍由 store 要求可取得合法 metadata。独立真实 Worker/D1 的 `library-removal-worker.test.ts` 1 项通过，核对移出保留元数据、分类、resume、进度和书签，已有元数据可直接重新收藏，缺元数据的新作品收藏仍返回 400。此前 supplier 通过没有覆盖此正式 API 拒绝路径。

新增 `ChapterProgressPageResponse`、显式已读与默认 false 未读、无锚 ACK 和无 metadata 移出的 golden，使用正式 Protobuf-ES / Dart codec 完成双向 ProtoJSON 往返；协议 golden 10 项通过。

## Dart 数据与 Reader

新增 `chapter_read_repository_test.dart` 12 项、完整 `test/data` 94 项及进度/Reader 定向 30 项通过；这些集合存在交集，不相加作为独立测试数。相关静态分析无问题。客户端测试使用受控业务 supplier，覆盖：

- 无锚响应保留 epoch/已读值；Reader 用实际 manifest 首页建立锚，继承已确认状态。远端无锚更新可使旧 Reader 停止写入，用户明确重开后恢复。
- 完整分页遇写入重启，不拼接不同快照；未确认 mutation 经书架或进度读取仍保留，原 UUID、正文及 CAS 精确重试。
- 旧 ACK、错误 revision/章身份/已读值不算确认；未读只清目标章节锚，保留其它业务字段。只有读取成功的完整集合中缺失的章节才视为未读。
- 阅读器自然完成仍要求真实末页观察；详情人工标已读不伪造该观察。

## 正式详情组件

`chapter_read_navigation_test.dart` 7 项通过，目标静态分析、格式与 diff 检查通过。测试经正式应用浏览、详情与标记窗口，使用受控业务 supplier；前六项标记路径将 Source `pages()` 入口设置为失败并核对未被调用，第七项单独等待受控 Source pages 回调，核对旧详情失效后的清理。覆盖以下组合路径：

- 完整读取后缺失记录为未读；已读/未读筛选与书签、搜索取交集。
- 可见选择与反序范围保留重复 URL/标题的独立章节条目、Source 索引和隐藏选择，确认清单包含全部目标。
- 已读/未读不改变 resume；系统返回与完成按钮共用关闭出口，已确认选择清除，未完成选择保留。
- 首失败停止，只精确重试原未确认项，取得 ACK 后明确继续余项；不重复发送已确认项目。
- 旧批次保持原 revision，冲突经只读重取后结束；仓储替换使旧窗口永久失效，迟到 ACK 不续发或串入新身份。
- 同客户端重开详情后章节列表变化，未确认旧项仍使用原 key/正文；结束批次后明确提示不匹配数量，不把旧 key 转入新的章节选择。
- 同一详情 State 的作品参数被替换时，迟到的 Source pages 结果精确关闭旧会话，不打开混用新旧身份的 Reader。

旧进度导航及书架流程与新 UI 合计定向 15 项通过。全库回归发现旧测试在新增控件后直接定位尚未构建的章节，或在滚动后检查已离开构建范围的简介；本轮改为真实滚动及在离开前检查简介，保留原视口和全部业务断言。

## 2026-11-07：真实 Web 范围往返与收藏后首次标记

在 Codex 内置浏览器操作正式 Flutter Web，使用官方 HTTP harness、同一测试身份 `acceptance-owner`、隔离 workerd / D1。使用固定 `5ba6fff` 无插桩 xkcd 构建 `ext-all.xkcd-dd84d305506e2bdc34ac62988aef645f`，英文 Source `1538249443376436084`，作品原 URL `SINGLE`。从真实列表选择原序第 5 至第 3 项，目标原章节 URL 为 `/3317/`、`/3318/`、`/3319/`，相邻 `/3316/` 为负对照。章节键按正式 `ChapterSequence` 由 package、Source、作品和原章节 URL 计算。

| 旧客户端 Web 阶段      | account / manga / global revision | 正式 UI 与独立 D1 核对                                                      |
| ---------------------- | --------------------------------- | --------------------------------------------------------------------------- |
| A 安装与收藏           | 2 / 1 / 1                         | 书架仅 xkcd，章节进度和书签为空。                                           |
| A 首次确认             | 2 / 1 / 1                         | 收藏后直接确认，首章误报冲突，0/3 确认且后两章未开始。全业务快照不变。      |
| A 显式重读后确认新清单 | 5 / 4 / 1                         | 反向来源顺序的闭区间恰好 3 章，3/3 确认；只有三个目标变为已读，epoch 1。    |
| B 新文档读回           | 5 / 4 / 1                         | 从正式书架重开，已读筛选仅这三章，业务快照不变。                            |
| B 标未读               | 8 / 7 / 1                         | 在已读筛选中按来源原序选择同一范围，3/3 确认；三个目标均变为未读，epoch 2。 |
| C 新文档读回           | 8 / 7 / 1                         | 正式书架重开，目标均显示未读，已读筛选 0/3320；业务快照不变。               |

独立验收只使用正式 GET，比较全局/漫画设置、书架、作品、书签、完整章节进度及四章逐章状态。负对照始终没有进度行；三章没有 current/furthest 锚点，作品没有新增 resume。收藏、分类、设置和书签均不受标记影响。写入均从正式界面触发。

首次冲突的原因是详情进度控制器在收藏前读到作品 revision 0，收藏 ACK 更新共享客户端到 revision 1，却没更新该页的完整章节快照。修复后，同一详情确认收藏会等待已经在途的旧读取，再读取完整快照；新范围确认在这段时间内禁用。已有批次保留原 revision，真实远端冲突仍需显式重读。新增回归覆盖同页收藏后直接确认、在途旧读和详情退役，旧代码下新增流程失败；修复后相关定向套件 13 项、完整 `pnpm check`（513 项 Vitest 与其它检查）、`pnpm flutter:check`（22 / 86 / 600 项）及正式构建通过。

以相同 xkcd 快照重建修复后的正式客户端（Web 入口 SHA-256 `98a25af607b34eb2583baf837553165cc467845541b33af0f8f5d1859496b644`），另开空 D1。从正式 UI 安装、打开详情、收藏，不点手动刷新，第一次确认相同反序范围即 3/3 成功。独立三阶段快照为 0/0/0 → 2/1/1 → 5/4/1，只有目标三章新增 epoch 1 已读，负对照与其它业务字段不变。两个本地 harness 和浏览器标签均已关闭，未部署该候选。

复验使用 `EXTENSION_ASSETS_DIR=<固定快照> pnpm acceptance:build`，按[正式 xkcd 流程](source-reopen.md#固定-5ba6fff真实-web-重开与书签往返通过)用显式 Source 政策启动 `pnpm acceptance:serve`。旧构建的故障与显式恢复、修复后首次提交分开登记。Native 实测见下节。

## iOS ↔ Android 模拟器范围往返

2026-11-08，使用固定产品 `9ef3ccb`、Flutter 3.47.5 / Dart 3.13.4，iPhone 17 Pro（iOS 26.4 模拟器）和 Android API 36 Google APIs arm64（Pixel 7 配置，WebView 133.0.6943.137）。两端通过同一官方 HTTPS 回环 origin、隔离 workerd/D1 和测试身份 `acceptance-owner`，使用当前 v6 内置材料匹配的真实 xkcd 构建 `ext-all.xkcd-31777c287c69f021ac4ebcdcd0a35cac-43d97485f779b768af7861a6a25522db433ab6d229a6d989e70e3f3c88a848a3`。两个模拟器分别正常信任本轮测试 CA；Android 只为回环 HTTPS 的隔离 debug WebView 与测试 Dart 进程追加 CA。未设置故障夹具。

| 阶段                 | account / manga / global revision | 正式界面结果                                                                                                           |
| -------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| iOS 安装与收藏       | 2 / 1 / 1                         | 正式书签驱动 `prepare` 安装指定构建并收藏英文 xkcd `SINGLE`，无进度或书签。                                            |
| iOS 标已读           | 5 / 4 / 1                         | 从书架重开真实详情，以来源顺序的反向端点选中 `/3317/`、`/3318/`、`/3319/`，核对清单并获 3/3 确认。三章 epoch 1、已读。 |
| Android 读回并标未读 | 8 / 7 / 1                         | 从同一书架打开正式已读筛选，读回原三章，再选同一闭区间并获 3/3 确认。三章 epoch 2、未读。                              |
| iOS 新进程读回       | 8 / 7 / 1                         | 重开详情后已读筛选为 0 章；全部独立快照不变。                                                                          |

各阶段正式集成测试分别 1/1 通过。独立进程使用正常 TLS 和业务请求头，核对全局设置、书架、作品、完整进度、书签及四章逐章状态：两次写入各推进三次 account 与 manga revision；相邻 `/3316/` 始终无进度记录，目标章均无 current/furthest 锚点，没有新增 resume，收藏、分类、资料、全局设置及书签不变。作品设置由正式驱动通过作品作用域 API 核对不变；当时独立采样中标作作品设置的请求实际重复了全局路径。Android 首轮在进入详情后的前置检查中把独立 ProtoJSON Map 作浅比较，误报失败；尚未开始写入，独立 GET 逐字段与 `5/4/1` 一致。修正驱动为深比较后才执行 Android 写入，无产品修改。复验见[正式驱动](../../apps/reader/integration_test/README.md#章节范围已读与未读)；本轮专用服务与设备已关闭；四次设备日志、独立 GET 快照和 `check-transition.mjs` 留在 `/private/tmp/karuyomi-native-chapter-sync.bztPAx/`。

## 复验与剩余门槛

仓库根目录执行：

```sh
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts apps/api/test/library-removal-worker.test.ts
```

客户端使用仓库固定 Flutter SDK：

```sh
cd apps/reader
flutter test test/data/chapter_read_repository_test.dart test/reader/reading_progress_controller_test.dart
flutter test test/browse/chapter_read_navigation_test.dart
```

集中工程检查通过：

- `pnpm format` 与完整 `pnpm format:check`，覆盖全部项目自有语言与结构化配置。
- `pnpm check`：生成一致性、portable 格式、严格类型、依赖层级、381 项 Vitest、10 项协议 golden 及全部工具回归。
- `pnpm flutter:check`：reader_core 21、source_runtime 42、客户端 337 项，三个项目静态分析无问题。
- `pnpm build`：正式 Web/Native runtime 资源、Flutter Web 与 Worker/Static Assets 构建成功；此项仅为工程构建；独立 iOS/Android 实测见上节。

详细临时日志留在忽略的 `.local/chapter-read-*.log`，不提交机器输出。

Web 独立文档与 iOS ↔ Android 模拟器的顺序闭环已通过。Web ↔ Native 范围同步、Reader 与详情同时写、真实部分提交与丢响应恢复、实际生命周期、生产 Access 和真机仍待验收。
