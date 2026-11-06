# 书架续读与详情恢复验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。书架直接续读、详情开章显式重试和续读位置只读重取已接入正式 Flutter 入口；设计见[书架续读与详情恢复](../design/reading-entry.md)。以下工程检查与独立客户端门分别记录。

## 验证入口

```sh
cd apps/reader
flutter test test/library/ test/browse/details_recovery_test.dart test/browse/chapter_list_navigation_test.dart test/browse/library_navigation_test.dart test/data/library_repository_test.dart test/data/library_snapshot_mutation_test.dart --concurrency=1
```

本轮使用正式生成模型、`BusinessStateClient`、`CatalogController`、书架/详情和 `ChapterReaderRoute`，业务与 Source 请求由既有受控 supplier 提供。测试不会将受控 supplier 称为实际 Source 或多设备验收。

## 定向组件与数据回归

书架新增 6 项、详情新增 5 项正式组件测试通过。详情使用 480×800 视口及标准滚动定位，覆盖长列表即时失败提示、持久的同章显式重试、重复 URL 的原出现 DTO、续读读取成功/再次失败、保留逆序草稿、pending POST 不重放及身份变化后丢弃迟到读取。书架保留整卡详情入口，并验证：

- 书架投影尚旧时，点击读取当前服务端章节；pages 等待期间远端再改同章位置与顺序，正式 Reader 恢复最后确认的二维锚与顺序，重复点击不重复开章。
- 目标章节消失时明确回详情，不猜测新章节；页面切换后迟到 pages 会话释放，身份变化后旧 resume 不进入 Reader。
- 当前会话未保存草稿优先、按钮明确标识未保存；附带元数据更新不重放原进度写入。
- 资料更新丢 ACK 后，用户明确重试同一 UUID/正文/CAS，服务端只应用一次；ACK 成功后书架 GET 失败仍准确显示资料已确认，原 pending 不复活。

共享数据回归同时覆盖 confirmed resume 投影/无记录 presence、非法章节键拒绝，以及 metadata 专用 retry 不重放其它命令。旧 metadata ACK 必须读回当前权威状态，远端较新资料不能被旧 ACK 复活；确定拒绝的原命令由只读刷新解除。

实现期间实际发现并修复三项产品问题：Reader 初始化同步通知导致书架在 build 中 setState；读取失败时逆序草稿被默认顺序覆盖；书架预先固定顺序覆盖 Reader 最后读回的新顺序。测试准备中的懒列表可见性、框架泵送和 transport 故障注入问题也已修正；中断的初轮组合不算完成验收，最终集中检查单独记录。未修改全局 runner、扩大手机视口或跳过既有断言。

临时日志位于 `/private/tmp/karuyomi-library-resume-new.log` 与 `/private/tmp/karuyomi-details-recovery-test.log`，未复制原始输出入库。

## 集中工程检查

`pnpm flutter:check` 完整通过：reader_core 22、source_runtime 42、客户端 389 项，三个项目严格分析无问题，124 份自有 Dart 文件格式一致。首次集中分析发现 SnackBar 在异步开章失败后缺少直接的 `context.mounted` 检查，已修正并重新完整检查；没有禁用 lint 或放宽类型/生命周期检查。日志位于忽略的 `.local/reading-entry-flutter.log` 与 `.local/reading-entry-flutter-final.log`。

`pnpm build` 完整通过，包含 Web/Native runtime 材料、Flutter Web release 及 Worker/Static Assets。提交前执行全库 `pnpm format`、完整 `pnpm format:check` 和正常 prek；临时构建/格式输出保留在忽略的 `.local/reading-entry-*.log`。本轮未修改原生插件或构建设置，也未重新构建/运行 Native App，不把共用 Dart 检查和 Web 构建等同于原生验收。

## 无差异打开与跨端 CAS

2026-11-07，修复书架每次打开详情都提交资料更新的问题。Source 名称、语言及完整 Manga 快照不变时不发送 mutation，避免无意义地推进作品 revision，使另一端的书签编辑产生冲突；真正变化仍保存，不改变原资料请求的 CAS、幂等或显式重试语义。

`library_navigation_test.dart` 14 项通过，包含重复打开零写后另一业务客户端持原 revision 成功标书签、Source 名称/语言/opaque memo 变化、旧书架项不覆盖远端新资料、失 ACK 原命令在无差异打开后保留并精确重试，以及真正变更保存失败后仍可阅读。新增跨端 CAS 回归对照旧实现先失败（两次打开多提交两次），修复后通过。既有书架资料失响应组件夹具改为明确变化的 Source 快照，继续验证真实写入的恢复路径。

完整 `pnpm flutter:check` 通过：三个项目严格分析无问题，reader_core 22、source_runtime 86、客户端 597 项，173 份 Dart 文件格式一致；新 Native 书签驱动也通过严格分析。全库格式和完整 Web/Native 材料、Flutter Web、API 构建通过。日志保留于忽略的 `.local/bookmarks-*.log`，旧实现对照与集中回归位于 `.local/metadata-noop-*.log`。

真实 Web 书签准备发现新文档 Source 重开/调用失败，尚未取得实际平台上无差异打开零 revision 的证据；不能以受控回归代替该运行门。实际观察、D1 核对及 HTTPS 信任限制见[书签记录](bookmarks.md)。

## 独立运行门

新增入口仍需在 Codex 内置浏览器、Web/Native 独立客户端、生产 Access 及目标设备分别验收。现有三端经详情续读的历史证据不能自动扩展为新书架按钮验收。实际 Source 的章节变化、临时故障、身份恢复、屏幕与输入交互须保留真实环境证据。

本轮没有新增业务存储、协议或远端部署；Worker API + D1 继续作为业务权威。完整 P0/P1/P2 及真机门仍未通过，继续按 [P1](../plan/p1-library-and-progress.md) 和 [P2](../plan/p2-sync.md) 推进。
