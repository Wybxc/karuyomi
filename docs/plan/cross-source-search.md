# 能力提示与有界跨源搜索计划

## 目标与当前状态

从已确认安装、启用且来源有效的 Source 中手动选择搜索范围，以最多两个独立执行槽逐源返回结果、分页和错误，并通过精确来源进入正式详情与阅读链。能力说明只使用现有运行时事实，不新增人工能力矩阵。设计见[能力提示与有界跨源搜索](../design/cross-source-search.md)，上级见 [P3](p3-extensions-and-migration.md)。

**状态：已实现待实际运行验收。** 正式双槽协议与运行时、包队列搜索服务和 Flutter 入口已接线；独立服务 10 项、UI 控制器 12 项和 Widget 5 项回归通过。完整工程检查与构建已通过，实际 Source/平台行为继续验收，不能据此标为 P3 或完整跨源搜索通过；实际结果维护在[验证记录](../verification/cross-source-search.md)。

## 已接入范围

- [x] 浏览页独立入口，静态候选只读枚举、名称/包搜索、语言筛选、默认不选与手动选择。
- [x] 精确绑定 catalog URL、repoId、package、build、digest、Source 与原账户 client；每次执行和打开结果重新核验 confirmed 安装、仓库及网络登记。
- [x] 两个物理运行槽和槽内响应/事件隔离；无阅读资源时搜索独占，完整包 namespace 分组、`pool(2)`、同包串行。
- [x] 各源独立等待/加载/结果/错误，首轮第一页、手动单源下一页、显式重试与取消；一个普通错误不清其它源结果。
- [x] query/选择冻结，32 Source、500 UTF-16 搜索词、每源累计 200/总计 1000 项；超限整页拒绝，不截断或自动拆分。
- [x] 新查询、后台、离页和打开详情前停止；精确关闭或 reset ACK 后归还槽，失败独立展示并允许重试清理。
- [x] 原身份永久退休、迟到结果抑制及详情惰性 route 身份检查；后台恢复与普通刷新不重放 Source 请求。
- [x] 根据 `supportsLatest=false` 显示具体限制；不把静态元数据、AOT 或错误码推测为逐源登录/验证码/完整阅读能力。

以上勾选表示功能已接入，不代替下列独立验收。

## 待办与验收

- [x] 独立服务测试使用正式双 transport 验证调度并发、同包串行、来源/安装改变时的执行门禁；实际双 Worker 另验。
- [x] 独立服务回归覆盖 queued/active/opening 取消、close/reset ACK 失败及再次清理，未确认槽保持占用；Native 图片公共入口另有错槽门回归。
- [x] 正式服务回归覆盖首轮旧浏览 session 关闭、全部包完成自动归还、活动阅读拒搜索及精确原来源详情；实际平台另验。
- [x] 固定 SDK 的完整 Reader/source_runtime 分析与回归、协议生成一致性、全库格式和完整构建；精确层级见[验证记录](../verification/cross-source-search.md)。
- [ ] Codex 内置浏览器使用当前固定 AOT 的至少两个真实包验证结果逐源返回、慢源/失败隔离、单源下一页、停止和真实详情/阅读。
- [ ] 同包多个 Source、原设置/敏感会话值保留、仓库移除/停用/换构建、Access 失效、离页及后台的实际运行边界。
- [ ] Native 正式入口和平台生命周期、生产 Access 分别记录；工程或 Web 分项不能代替这些门。

## 已过的 UI 定向层级

使用仓库固定 Flutter SDK，在 `apps/reader` 运行：

```sh
flutter test test/search/cross_source_search_controller_test.dart
flutter test test/search/cross_source_search_page_test.dart
```

控制器覆盖独立返回、冻结 query 分页、显式重试、新轮等待旧清理、取消失败重试、旧取消回调、选中/结果预算、身份退休及迟到详情。Widget 覆盖明确选择、逐源分页和正式目标参数、关闭失败留页、首帧前退休、后台不重放，以及运行时最新列表能力提示。

这 17 项使用受控搜索服务与正式 Flutter 组件；能力提示用例读取测试运行时事实。它们不证明真实 Worker 调度、在线 Source、Access 登录、图片或 Native 行为。独立服务 10 项的实际范围与后续集中工程、平台结果见[验证记录](../verification/cross-source-search.md)；不将尚未执行的命令写成已通过。
