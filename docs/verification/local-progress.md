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

生成与完整检查入口见 [TOOLING](../TOOLING.md#drift-生成模型)。此时底座尚未接入产品路由，Web 静态数据库资源与真实浏览器持久化、Native 应用重启恢复仍待验收；文件数据库单测不能替代这些门。P1 全部范围见[计划](../plan/p1-library-and-progress.md)。
