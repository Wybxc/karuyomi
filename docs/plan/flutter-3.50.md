# Flutter 3.50 / Dart 3.14 更新

## 目标与状态

状态：进行中（升级准备）。2026-11-12 按用户要求准备从 Flutter 3.47.5 / Dart 3.13.4 更新到 Flutter 3.50 系列及其内置 Dart 3.14，保持固定补丁版本、严格分析、生成一致性和主线自动上线。当前 `.fvmrc` 和 CI 尚未切换；[状态管理重构的已验收产物](../verification/flutter-state-management.md)仍使用原固定工具链。

已核对[官方 Flutter 3.50 发布说明](https://flutter.dev/blog/whats-new-in-flutter-3-50)与 [Dart 3.14 changelog](https://dart.dev/changelog#3-14)：两者已于 2026-11-11 发布。实施时从[官方 SDK archive](https://docs.flutter.dev/install/archive)确认同一 Flutter bundle 的精确版本、Dart 版本和校验值，再固定到仓库，不独立替换 Flutter 内置 Dart。

## 仓库影响与实施顺序

1. 一次更新 `.fvmrc`、`.github/workflows/{project-ci,extensions}.yml`、`scripts/format.ts` 的 Dart 版本校验及 `AGENTS.md` 工具链要求。三个业务 Dart 项目与 `tools/protocol/generator` 的 pubspec SDK 下限统一调整；用正式 pub 命令刷新各自 lock。用户已有的 `pnpm-lock.yaml` 改动另行保留，不混入升级。
2. 严格分析会受独立设计包影响。自有 UI 仍导入 SDK `material.dart`；按[官方迁移指引](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)运行 `dart fix --apply --code=migrate_design_widgets`，精确固定 `material_ui`，统一生产、测试和 integration_test 导入及本地化 delegates。按实际使用引入 Cupertino，删除不再使用的旧依赖，不增加项目自有兼容桥。核对第三方库公开 API 的设计类型，遇到类型冲突通过依赖或调用修复。
3. 设置、书架、源筛选、源偏好和跨源搜索使用 `DropdownButtonFormField`，迁移后逐处保持忙碌/停用语义；参考[显式 enabled 变更](https://docs.flutter.dev/release/breaking-changes/dropdownbuttonformfield-enabled-parameter)。核对 Web SafeArea、文本选择、缩放和键盘焦点的实际行为，不只通过导入替换判断完成。
4. 在新 Dart 上解析固定的 generator / annotation / hooks / analyzer plugin 依赖，先运行生成一致性和严格分析，必要时精确更新冲突依赖；不关闭 riverpod_lint、不抑制类型或废弃警告。核对 [Dart 3.14 的 flow-analysis 与 SDK 变更](https://dart.dev/changelog#3-14)，根据实际诊断改代码。
5. Android 当前使用 AGP 9.1.0；核对插件的 Built-in Kotlin 要求。iOS 核对当前 Swift Package Manager 配置和 WebView 插件构建要求。这里只做工程兼容性准备；按用户现有要求继续停止原生现场验收，不能将其标成已验证。

## 验收与交付

- 本机仅允许轻量编辑、格式、生成、分析和必要测试，采用低优先级单并发；Web 完整构建交给 CI，扩展 AOT 仅在获准的 clab 运行，不使用 pku-dasys，不为本次 UI 工具链更新重做全量 AOT。
- 使用新固定 SDK 依次通过 `pnpm flutter:setup`、`pnpm flutter:generate:check`、`pnpm generate:check`、`pnpm format`、`pnpm format:check`、`pnpm flutter:check --concurrency=1` 和完整 CI `pnpm check` / `pnpm build`。生成变化由正式生成器提交，检查完整范围不缩小。
- 使用 CI 产物与 Codex 内置浏览器验收输入/焦点、目录搜索、设置保存和覆盖继承、真实图片翻页与新文档续读，继续保持 API + D1 权威、CAS、身份隔离及关闭 ACK。
- 工程、Web 与生产发布分别记录证据，CI 通过后按现有流程上线；更新本计划、索引及工具链说明。当前仅完成官方变更核对与仓库入口清点，新 SDK 的依赖解析、检查、构建和运行均待实施。
