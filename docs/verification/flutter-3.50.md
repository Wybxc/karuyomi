# Flutter 3.50 / Dart 3.14 更新验证

2026-11-13，进行中。范围见[更新计划](../plan/flutter-3.50.md)。本记录区分本机工程、CI 构建、Web 交互、生产与原生证据。

## 工具链与工程

本机为 macOS arm64，固定 Node 24.15.0、pnpm 12.6.0。Flutter 官方 Git 标签 `3.50.0` 对应 `ab2912035e160d9cad6306df307576da6128ebdb`，engine `371f77202a73e8dff57a8b3bff75bca55c090aee`，配套 Dart 3.14.0 stable。官方归档 URL 本次返回 404，因此以官方标签 bootstrap，下载使用 Flutter 支持的 `FLUTTER_STORAGE_BASE_URL` 镜像；没有手改 SDK 或独立替换 Dart。版本输出保存在 ignored `.local/flutter-350-sdk-version.log`。

四个 Dart 项目均通过官方 `dart migrate --target-sdk=3.14.0` 的准备、版本更新和清理；随后运行正式 `pub get`。`material_ui` 精确固定 1.11.0，官方 `migrate_design_widgets` 更新 64 个文件，本地化使用该包的正式 delegates。Riverpod generator、hooks 和 riverpod_lint 继续开启。

Web 发布合同的 Node 回归 15 项通过，正式 Vite fixture 与 Wrangler harness 的 11 项回归通过，覆盖内容哈希清单、双目标条目、大小/哈希不一致、缓存策略及实际 Static Assets 响应。`pnpm typecheck:tools` 通过。以上使用受控 fixture，不能代替真实 Flutter 产物、浏览器或生产验证。

完整格式化与格式检查通过；三个业务项目严格分析（含 riverpod_lint）无问题，单并发回归 reader_core 22 项、source_runtime 87 项、reader 627 项，共 736 项全部通过。Riverpod 生成一致性、Protobuf 生成一致性与依赖边界检查通过。可复验命令：

```sh
pnpm flutter:setup
pnpm protocol:setup
pnpm flutter:check --concurrency=1
pnpm generate:check
pnpm format
pnpm format:check
pnpm check:dependencies
```

原始输出在 ignored `.local/flutter-350-*.log`，不提交机器日志。

## 代码量

本轮前的 `b248648` 为基线，范围为 `apps/reader/lib`、`packages/reader_core/lib`、`packages/source_runtime/lib` 的生产 Dart，排除 `.g.dart` 和 `src/pb`。完整格式化后，手写 Dart 由 30,414 行降至 30,354 行：新增 340 行、删除 400 行，**净减 60 行**，已计入新的转场策略及新 formatter 的格式变化。生成代码仍为 19,680 行，新增/删除均为零；测试另计。主构造函数保留阅读锚点范围、不可变集合、深拷贝/冻结、图片身份与字节预算校验；没有通过删除校验减少行数。

## UI 与原生配置

新增减少动态效果的路由策略：`reduceMotion` 使用淡入淡出，`disableAnimations` 直接显示页面；正文动图仍由原有播放策略管理。两项新增组件回归已通过：分别检查转场中页面保持原位、仅淡化，以及停用动画时没有淡化；同时确认两个系统标志仍独立。下拉表单明确设置忙碌/停用状态，既有设置、筛选和搜索组件回归通过；viewport 加入 `viewport-fit=cover`。输入、焦点、缩放、安全区与真实阅读仍待浏览器验收。

封面保留当前物理像素换算和 1024 高度预算。逻辑缓存尺寸 API 接收整数逻辑尺寸，保持该物理上限仍需额外换算，当前没有简化收益，未宣称内存优化。

Android 静态核对仍为 AGP 9.1.0、模板 `builtInKotlin=false` / `newDsl=false`；WebView 插件使用旧 DSL，未在本轮未经构建就切换。[官方迁移说明](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)要求连同插件准备情况判断。iOS 已有 `FlutterGeneratedPluginSwiftPackage`、prepare pre-action，WebView 插件提供 SwiftPM manifest；现有 CocoaPods 集成保留，参照[官方 SwiftPM 说明](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)核对。原生现场验收按用户要求继续停止，以上不是新 SDK 的原生构建或运行证据。

## CI、浏览器与发布

待执行。JavaScript 默认构建与同提交 Wasm 候选交给 CI，完整 Flutter Web 不在本机编译。Wasm 的收益和默认采用结论须有实际运行及同条件测量；未验证前维持 JavaScript 默认。原生直接互操作与 WebParagraph 属于后续候选，不阻塞首批交付。
