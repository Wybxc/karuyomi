# 收藏源与快捷打开验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。收藏源已接入生成业务协议、既有全局设置权威 API 与正式 Flutter 浏览入口；[设计](../design/source-favorites.md)记录身份、完整全局 CAS、显式重试与打开流程。状态为**已实现待独立客户端验收**，以下只记录实际执行的工程范围。

## 定向合同、API 与 Dart 数据

TypeScript 合同与真实 workerd/D1 定向组合 46/46 通过，覆盖有界收藏列表的合同校验、组合身份唯一性，以及全局 JSON 持久化、读取、取消和现有原子确认路径。复验入口：

```sh
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
```

新增收藏源 6 项与原设置数据 11 项共 17/17 通过：

```sh
cd apps/reader
flutter test test/data/source_favorites_repository_test.dart test/data/settings_repository_test.dart
```

使用正式 `BusinessStateClient/SettingsRepository/SettingsController` 和生成模型，业务响应由既有受控 `TestBusinessServer` 提供，完整全局设置经 ProtoJSON 往返；未为收藏增加 fake 专用字段存储。覆盖：

- 同一身份的独立 client 读取收藏和取消结果；不同 subject 隔离；两个包内相同 Source ID 分别保留，取消其中一个不影响另一个。
- 收藏/取消保留主题与全部阅读偏好；正式 `GlobalSettingsPanel` 在 480×800 视口编辑主题后仍完整提交收藏列表。
- 丢 ACK 后重建 repository/controller，保持原 UUID、正文和 CAS；刷新不重发，新编辑不能替换未确认原请求，显式重试只应用一次。
- 另一 client 修改主题/阅读偏好并取消收藏后，旧 global CAS 失败，不能覆盖当前设置；旧幂等 ACK 必须读回当前状态，不能复活已取消来源。
- 身份关闭后迟到 ACK 被拒绝，不发布旧确认，也不污染下一 subject。

这两份 Dart 文件首次组合执行即全部通过；临时日志为 `/private/tmp/karuyomi-source-favorites-data-test.log`，原始输出不入库。受控 supplier、同进程多个 client 和 widget 测试不称为实际多设备同步。

## 控制器、正式组件与集中检查

快捷打开控制器新增 10 项与既有 catalog/library 导航、业务 validation 回归的组合 44/44 通过；正式收藏源 UI 6/6 通过，相关严格分析无问题。控制器覆盖按包定位当前构建与原 Source ID、缺包/缺源、重复点击互斥，以及切页或换身份后的迟到流程。复验入口：

```sh
cd apps/reader
flutter test test/browse/source_favorites_controller_test.dart test/sources/
```

容量回归在 480×800 视口实际滚动，验证 128 项时明确提示、禁用新增且没有 POST 或假 pending；打开与取消仍可用，取消至 127 项后可以再收藏。请求预算回归使用合法字段将无 UUID 草稿补至 128KiB，再验证加入 UUID 后的最终正文在发送前拒绝、不留下 pending，后续正常设置写入仍可执行。正式编码器原本已默认执行 128KiB 上限，本轮在业务调用点显式标注同一限额；不将该回归称为历史漏检修复。

`pnpm flutter:check` 完整通过：reader_core 22 项、source_runtime 42 项、客户端 413 项，三个项目严格分析无问题，128 份自有 Dart 文件格式一致。集中回归修正了旧浏览导航直接点击离屏漫画的测试：改用正式列表的标准滚动与可见区域点击，保留原视口和业务断言。预算样本的尺寸测量使用明确的较大测量预算，正式发送限额与拒绝断言没有放宽。

`pnpm check` 完整通过，包含协议生成一致性、portable 格式、严格类型、依赖方向、392 项 Vitest 与全部协议/扩展/工具回归。`pnpm build` 完整通过，包含 Web/Native runtime 材料、Flutter Web release 和 Worker/Static Assets。提交使用全库 `pnpm format`、完整 `pnpm format:check` 和正常 prek；没有修改原生插件或构建设置，也未重新构建或运行 Native App。

控制器、容量、完整检查与构建临时日志位于 `/private/tmp/karuyomi-source-favorites-*.log`，原始输出不入库。

## 独立运行门

以下均未由本轮组件结果替代：

- Codex 内置浏览器和 Web/iOS/Android 独立客户端，同一身份收藏、取消、只读刷新及重启后恢复；实际同时写与响应丢失后的恢复。
- 实际 Static Assets 索引更新后按稳定 package/source 身份打开当前构建；缺包、缺 Source、Access 失效、打开期间切页或换身份的真实行为。
- 生产 Access、实际 Native 会话和目标设备。当前没有因这些工程测试执行生产部署或完成 AOT baseline。

其余扩展管理、全目录语言筛选、typed preferences 与源迁移保持 [P3](../plan/p3-extensions-and-migration.md) 的未实现状态。完整 P0/P1/P2/P3 均不能按本页局部结果判为完成。
