# 本地阅读进度底座

2026-11-03，使用官方 Drift 2.35.3、drift_flutter 0.3.1、drift_dev 2.35.2 与 build_runner 2.17.1。自有实现位于 `apps/reader/lib/data/`，官方生成模型随表定义提交。

## 数据语义

- 受信 bootstrap subject 与部署 origin 构成身份分区；漫画键、章节键区分 Source、漫画与重复章快照，不以显示标题定位。
- 当前回看位置、实际观察到的最远位置、阅读 epoch 与显式完成状态分别保存。预加载、恢复和导航本身不增加最远进度。
- 同 epoch 合并取实际观察的最远页与 offset；跨清单按稳定 pageKey 映射，找不到的旧最远锚保留为 unresolved，不拿旧 index 比较新页。
- reset 在事务中提升 epoch，旧离线写不能覆盖新 reset，也不能改变对应 resume。进度与漫画继续阅读位置在同一 SQL 事务写入。
- Web 使用 Drift 的正式存储适配，明确报告 persistent、memoryOnly 或 unsafePersistence；只有实际连接打开后才返回能力。Native 使用正式 SQLite；数据库失败不冒称保存成功。

## 已执行验证

`cd apps/reader && flutter test test/data` 的 12 项回归通过；相关静态分析通过。实际 SQLite 文件经关闭重开仍保持当前页、最远页、offset、epoch 与漫画 resume，文件头确认为 SQLite format 3。另覆盖 origin/subject/漫画/重复章隔离、并发观察合并、reset 后旧写拒绝，以及真实 SQL trigger 失败时进度和 resume 整体回滚。

生成与完整检查入口见 [TOOLING](../TOOLING.md#drift-生成模型)。上述为底座阶段，后续产品接线证据如下；文件数据库测试不能替代浏览器或原生应用重启门。P1 全部范围见[计划](../plan/p1-library-and-progress.md)。

## 产品接线与文件重启

2026-11-04，正式 `KaruyomiApp` 从平台 origin 与成功 bootstrap 的 subject 构造 repository，未确认身份时不创建进度会话。目录→详情→章节使用同一个生产路由；详情提供继续阅读，Reader 保存当前导航锚与实际观察锚，末页显示后通过明确的完成或下一章操作标记读完。重新阅读在 SQL 事务提升 epoch，并通过位置命令回首页，不关闭后复用旧图片 provider。

600 ms debounce 与 2 秒最长等待控制写入；切章、返回与进入后台触发提交。普通数据库读写异常不会移除阅读器：失败的精确草稿仍有 Catalog owner，可重试或在同一身份重新进入时继续使用。切换服务不因存储失败被阻止；应用只接管旧身份的数据库 writer，释放旧运行容器，设置提供全局重试。回到同一受信身份会接管原 writer，避免两个写者迟到覆盖。只有 Drift 报告 persistent 且写入完成时显示本地已保存；memoryOnly 明示关闭后不保留，unsafePersistence 明示不安全多窗口，均不冒称持久保存。

执行 `cd apps/reader && flutter test test/reader test/browse test/widget_test.dart`，47 项通过；`dart analyze lib test` 无问题。其中新增产品回归通过正常目录/详情/Reader，使用受控 ProtoJSON Source DTO 与真实 SQLite 文件：显式下一章完成前章，在次章记录 pageKey/normalizedOffset/方向，移除产品组件、关闭数据库，再打开同一文件并经详情继续阅读，恢复原章与锚。另覆盖首个 current 即使无图片也可保存、观察最远位置不因回看退后、SQL trigger 真实回滚后重试、旧 epoch 拒绝、数据库延迟打开时退出、reset 不重开页面会话，以及存储持续失败时切换服务成功、旧运行时释放、旧身份独立重试与同身份 writer 接管。

导航测试直接注入视口回调以隔离进度协调；实际 image frame/缩放/route 覆盖的观察门由已有 ReaderScreen 回归覆盖。此处不是在线 Source 或真实设备测试。Web 官方 WASM/worker 构建见[资源记录](reader-database-assets.md)，Native 打包见[依赖记录](native-dependencies.md)；浏览器关闭重开、Native 应用重启和真实 Source 连续阅读仍须分别验收。

2026-11-04，真实 Flutter Web 与原版 Source 已通过连续切章、关标签页重开后的章节/当前页/最远页/顺序恢复，见[Web 产品进度记录](reader-progress-web.md)；浏览器进程退出仍待验收；Native 进程重启分项见下文。

同日，固定 `d76e8a4` 的 iOS 模拟器通过原 xkcd 正式 CatalogController/ChapterReaderRoute/ReaderScreen：真实图片 frame 后翻到末页并显式读完，SQLite 保存 current/far/completed；实际 terminate/launch 后，用同一 HTTPS origin 与受信测试 subject 恢复原章末页及完成状态。入口和 Pointer 为测试驱动，Source/JAR、阅读组件和 SQLite 是正式实现；不等同于生产 Access、物理触控、Android Source 或整套日用流程。完整输入与报告见[Native 记录](native-dependencies.md)。

固定 `8eef7b4`（`d76e8a4` 加 Android channel 所有权修复）的 Android API 36 模拟器也通过原 xkcd 正式 ReaderScreen：两页及 Source 文字图、显式读完、route/provider 清理和最终 WebView dispose。两次真实 force-stop/relaunch 均恢复同安装 SQLite 的 current/furthest/completed；最终入口等待正式界面“本地进度已保存”后截图，再验证退出落盘。原 d76 的双 dispose 失败及首次 pre-flush 截图保留，完整身份和隔离 localhost CA 范围见[Native 记录](native-dependencies.md#android-独立-debug-app-的-tlssource-与退出复验)。这仍是受控测试入口，不代表物理设备、正式主入口人工操作、生产 Access 或后续 Cache v3 材料已通过。
