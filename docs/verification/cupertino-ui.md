# Cupertino UI 迁移验证

2026-11-13，应用壳、全部业务界面、阅读器、诊断与原生 Access 页面已完成 Cupertino 代码迁移。本机工程检查通过，完整 Web 构建、浏览器与生产验收继续推进。范围和未验门槛见[迁移计划](../plan/cupertino-ui.md)。原生现场验证继续按用户要求停止。

## 工程与交互回归

使用固定 Flutter 3.50.0 / Dart 3.14.0、Node 24.15.0 与 pnpm 12.6.0。`cupertino_ui: 1.1.6`、`cupertino_icons: 1.0.9` 通过正式 pub get 设为精确直接依赖并更新 reader lock；移除直接 `material_ui` 与 `uses-material-design`。自有 lib、test、integration_test 已无 Material 或旧 SDK Cupertino 导入、Material 图标引用。

`hooks_riverpod`、`flutter_hooks` 与 `flutter_inappwebview` 的传递 Material 导入仍保留。实际集成未要求 MaterialApp/Material Theme，三个项目严格分析及组件回归通过；原生插件现场仍待验，不把依赖扫描当作运行或包体证据。Riverpod generator、Hooks 和 riverpod_lint 保持启用。

单并发检查通过 reader_core 22 项、source_runtime 87 项、reader 633 项，共 **742 项**；三个项目严格分析无问题。Riverpod 与 Protobuf 生成一致性、全范围格式化及格式检查、依赖边界检查通过。回归包括权威读写、CAS 冲突、身份变化、未确认草稿、取消、迟到确认、generation 和资源关闭。普通页面继续遵守减少动态效果及禁用动画的既有策略。

新增选择流程回归覆盖少量菜单选择 null、禁用项、Escape、关闭后焦点返回、Tab/方向键/Enter、360px 下双倍字号的中文搜索，以及搜索页取消与选择的区别；已打开选择页后 owner 被禁用，不得回写。长分类名和忙碌编辑的迟到 ACK 保留原回归。阅读器显式返回汇入既有退出流程；书架、详情及重登恢复入口均等待阅读路由退场后关闭章节。

当前缺失组件通过调整流程解决：分类选择当前范围，章节用分段筛选与书签开关，源偏好单选直接选择后等待确认，长选项和迁移章节复用可搜索选择页。多选及复杂编辑保留明确应用/取消和可见操作栏；通知改为持续业务状态。未额外引入第三方 UI 库，也未仿制一套 Material 控件。

可复验入口：

```sh
pnpm flutter:check --concurrency=1 --reporter=expanded
pnpm generate:check
pnpm format
pnpm format:check
pnpm check:dependencies
```

本机只做编辑、生成、分析与单并发测试；完整 Web 编译交给 CI，没有执行 AOT、模拟器或真机验证。原始输出留在 ignored `.local/cupertino-migration/`。

## 代码量

基线 `5352d8f7624a62258e74643e193963e335b8b875`，范围固定为 `apps/reader/lib`、`packages/reader_core/lib`、`packages/source_runtime/lib` 的生产 Dart，排除 `.g.dart` 与 `/src/pb/`，计入所有新增生产组件。正式格式化后由 **30,354 行降至 30,282 行，净减 72 行**。这是本次 UI 迁移的净变化；不将此前重构的削减重复计入，也不宣称已取得包体或性能收益。

删除来源包括重复选择确认层、卡片布局、编辑布局、普通监听装配，以及 43 个 Widget 的字段/构造参数重复声明。新增 `ChoiceField` / `ChoicePage`、`EditSheet` 与无障碍路由策略已计入；业务校验和生命周期约束保留。生成代码、测试与文档单独统计。

## CI、浏览器与生产

待同一提交的完整 CI / Web 构建，以及 Codex 内置浏览器的导航、扩展、详情/收藏、设置、真实图片阅读、退出和独立新文档续读验收。生产按既有主线 CI 自动发布，复用当前 runtime 与扩展快照，不重做 AOT；真实 Access 与独立 API/D1 核对另行记录。原生共享代码和 integration_test 的迁移不能代替 iOS/Android 实际运行证据。
