# Flutter 3.50 / Dart 3.14 更新与优化

## 目标与状态

状态：进行中（升级与优化准备）。2026-11-12 按用户要求准备从 Flutter 3.47.5 / Dart 3.13.4 更新到 Flutter 3.50 系列及其内置 Dart 3.14，并将官方更新对应的 Web 发布、代码精简和 UI 改善纳入本轮。保持固定补丁版本、严格分析、生成一致性和主线自动上线。当前 `.fvmrc` 和 CI 尚未切换；[状态管理重构的已验收产物](../verification/flutter-state-management.md)仍使用原固定工具链。

已核对[官方 Flutter 3.50 发布说明](https://flutter.dev/blog/whats-new-in-flutter-3-50)与 [Dart 3.14 changelog](https://dart.dev/changelog#3-14)：两者已于 2026-11-11 发布。实施时从[官方 SDK archive](https://docs.flutter.dev/install/archive)确认同一 Flutter bundle 的精确版本、Dart 版本和校验值，再固定到仓库，不独立替换 Flutter 内置 Dart。

目标是改善频繁上线后的资源一致性和复访加载，实质减少手写 Dart 代码，并取得 Karuyomi 自身的 Wasm 对照数据。当前只完成官方变更核对、仓库入口清点和计划整理，以下实现与验收均待执行；官方基准和引擎改进不作为产品性能证据。

## 交付顺序

1. 首批完成固定 SDK、独立设计包迁移、手写代码精简、Web 内容哈希与发布校验，以及明确的 UI 改善，通过工程和 Web 验收后沿用主线 CI 自动上线。
2. 同轮在 CI 构建 Wasm 候选，使用相同输入与 JavaScript 版本对照，依据实际结果决定默认配置；可选性能实验不阻塞已通过验收的首批交付。
3. 原生直接互操作与 WebParagraph 保留为后续候选，取得相应开销或瓶颈证据后再实施。

## 首批：工具链、设计包与代码精简

- [ ] 一次更新 `.fvmrc`、`.github/workflows/{project-ci,extensions}.yml`、`scripts/format.ts` 的 Dart 版本校验及 `AGENTS.md` 工具链要求。三个业务 Dart 项目与 `tools/protocol/generator` 的 pubspec SDK 下限统一调整；用正式 pub 命令刷新各自 lock。用户已有的 `pnpm-lock.yaml` 改动另行保留，不混入升级。
- [ ] 当前业务包语言下限仍为 `^3.12.0`。按 [Dart 3.14 的迁移流程](https://dart.dev/blog/announcing-dart-3-14)，先运行 `dart migrate --dry-run --target-sdk=3.14.0` 审阅，再应用准备、版本更新与清理；不能仅替换 SDK 后仍按旧语言版本维护代码。
- [ ] 使用[主构造函数](https://dart.dev/language/primary-constructors)精简 `SettingsState`、`SettingsSnapshot`、`SettingsDraft`、`ReadingPosition`、`PageRef`、`ImageResource` 等适合的值对象。该特性自 Dart 3.13 起可用，并非 3.14 新增；保留构造校验、不可变状态与复制语义，生成模型继续由正式生成器维护。
- [ ] 以本轮实施前提交为基线，分别记录生产手写 Dart 的新增、删除、净变化及生成代码变化。验收要求实质净减少手写代码，不以移动文件、压缩可读性或删除必要校验计作收益；具体行数由实施后的 diff 给出。
- [ ] 自有 UI 仍导入 SDK `material.dart`；按[官方迁移指引](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)运行 `dart fix --apply --code=migrate_design_widgets`，精确固定 `material_ui`，统一生产、测试和 integration_test 导入及本地化 delegates。按实际使用引入 Cupertino，删除不再使用的旧依赖，不增加项目自有兼容桥。核对第三方库公开 API 的设计类型，遇到类型冲突通过依赖或调用修复。独立设计包的收益是维护与独立更新，包体变化另行测量。
- [ ] 在新 Dart 上解析固定的 generator / annotation / hooks / analyzer plugin 依赖，先运行生成一致性和严格分析，必要时精确更新冲突依赖；不关闭 riverpod_lint、不抑制类型或废弃警告。核对 [Dart 3.14 的 flow-analysis 与 SDK 变更](https://dart.dev/changelog#3-14)，根据实际诊断改代码。
- [ ] Android 当前使用 AGP 9.1.0；核对插件的 Built-in Kotlin 要求。iOS 核对当前 Swift Package Manager 配置和 WebView 插件构建要求。这里只做工程准备；原生现场验收继续停止，不能将工程检查标成原生运行已验证。

## 首批：Web 内容哈希与发布校验

依据[官方 Web 发布文档](https://docs.flutter.dev/deployment/web#web-content-hashing---web-content-hash)，由 Flutter 生成内容哈希和资源清单，项目仅维护 Static Assets 集成与发布合同。

- [ ] 在 `scripts/flutter.ts` 的正式 Web 构建入口启用 `--web-content-hash`，保留现有资源自托管要求。启用前核对 deferred imports；当前内容哈希与 deferred loading 不同时启用，本轮不新增延迟加载方案。
- [ ] 将 `tools/cloudflare/web-release.ts` 中写死的 `main.dart.js` 改为读取官方 `precache_manifest.json`，校验清单格式并纳入实际生成的 JS/Wasm 模块、资源及 bootstrap。保留 runtime、materials 和扩展各自的发布验证合同，不把 Flutter 清单当成全部发布内容。
- [ ] 在 `apps/api/vite.assets.ts` 按官方清单中的哈希标记生成缓存规则：带内容哈希的 Flutter 文件长期 `immutable` 缓存，HTML、bootstrap 与其它未哈希入口重新验证；自托管 `canvaskit/**` 仍按未哈希资源处理。扩展索引与共享材料继续遵循现有独立规则。
- [ ] 为清单接入和缓存头增加必要的发布回归，使用官方构建与 Wrangler harness 验证实际产物，覆盖入口引用、完整性校验、资源可达及缓存策略。
- [ ] 用 Codex 内置浏览器验收首次访问、复访、发布切换、持续打开的阅读标签与新文档。明确旧标签遇到资源失效时的更新提示和刷新路径，保持未确认草稿提示；不建立历史发布目录或旧版本兼容层，不能只加构建参数就标为完成。

## 首批：UI 改善

- [ ] 封面评估采用 `Image.useLogicalCacheSize` / `ResizeImage.useLogicalSize`，简化 `custom_cover.dart` 的 DPR 换算，核对尺寸单位并保留现有解码上限。当前已有限制解码尺寸，只报告实际代码和测量收益；正文缩放、裁白、缓存键与资源释放语义不能因该 API 变化而简化。
- [ ] 在 `apps/reader/web/index.html` 补齐适合移动浏览器的 viewport 配置，并按[官方 SafeArea 说明](https://docs.flutter.dev/deployment/web#mobile-browser-viewport-and-safearea)验收安全区、页面缩放和阅读控件可达性。
- [ ] 核对新增 `MediaQueryData.reduceMotion` 与现有 `disableAnimations` 的使用，适配系统减少动态效果设置下的非必要位移和转场；动图播放策略单独保持明确语义，不把两者无条件等同。
- [ ] 设置、书架、源筛选、源偏好和跨源搜索使用 `DropdownButtonFormField`，迁移后逐处保持忙碌/停用语义；参考[显式 enabled 变更](https://docs.flutter.dev/release/breaking-changes/dropdownbuttonformfield-enabled-parameter)。验收文本选择、键盘焦点、缩放与输入，不只通过导入替换判断完成。

## 同轮：Wasm 对照与采用门槛

- [ ] 自有 Web 桥已使用现代 `dart:js_interop`；通过 `--no-deprecated-js-interop` 检查完整依赖链，修复真实依赖问题，不以自有源码没有旧导入代替构建证据。
- [ ] 在 CI 用相同提交、Source 材料与发布配置生成 JavaScript 和 `--wasm` 候选，复用现有构建链与扩展产物。使用[官方 loader 的双目标与自动 JavaScript 回退](https://docs.flutter.dev/platform-integration/web/wasm)，不自建回退层，TeaVM Source 继续使用已确定的 JavaScript backend。
- [ ] 核对 Wasm MIME、自托管渲染资源和必要响应头；如调整跨源隔离，连同 Access 登录窗口与运行时资源一起验收。Safari / Firefox 的 `wasmAllowList` 采用须有对应浏览器证据，无法测试的平台保持待验。
- [ ] 对照记录冷启动与复访到可操作时间、章节首图、连续滚动帧耗时及可取得的内存指标，注明浏览器、设备、缓存条件、网络、素材与重复次数。确认实际执行 Wasm，并完成真实阅读、保存、取消、关闭与新文档续读回归。
- [ ] 根据同条件测量与正确性回归决定默认配置，记录采用结论及未覆盖环境。官方重组件基准的两倍帧率不能作为 Karuyomi 收益；未证明收益前不增加应用专有的浏览器分支或性能机制。

## 后续性能候选

- **原生直接互操作**：FFIgen / JNIgen 已稳定，但当前 iOS 图片正文走文件通道，MethodChannel 主要传小控制消息。先测自有文件服务的调用开销，再判断是否迁移；即使改用直接互操作，跨 TeaVM 边界的正式协议、generation、限额、取消与释放 ACK 仍须保留。当前不恢复原生现场验收。
- **WebParagraph**：仍是实验预览，阅读主体为图片，潜在收益主要在中文 UI、文本布局与冷启动。取得相关瓶颈后再做对照，不纳入首批完成条件。
- **引擎内建改善**：iOS 触控调度等随 SDK 更新取得实现变化，不据此重写现有手势或宣称目标设备性能已通过。

## 验收与交付

- 本机仅允许轻量编辑、格式、生成、分析和必要测试，采用低优先级单并发；Web 完整构建交给 CI，扩展 AOT 仅在获准的 clab 运行，不使用 pku-dasys，不为本次 UI 工具链更新重做全量 AOT。
- 使用新固定 SDK 依次通过 `pnpm flutter:setup`、`pnpm flutter:generate:check`、`pnpm generate:check`、`pnpm format`、`pnpm format:check`、`pnpm flutter:check --concurrency=1` 和完整 CI `pnpm check` / `pnpm build`。生成变化由正式生成器提交，检查完整范围不缩小。
- 使用 CI 产物与 Codex 内置浏览器验收输入/焦点、目录搜索、设置保存和覆盖继承、真实图片翻页与新文档续读，继续保持 API + D1 权威、CAS、身份隔离及关闭 ACK。新增功能、性能对照、生产发布与原生待验分别记录。
- 首批通过工程与 Web 验收后按现有主线 CI 自动发布，不等待后续性能候选；上线后核对入口、资源缓存、真实阅读、保存及新文档续读。同步本计划、索引、工具链说明与实际验证记录，未执行项继续保持待办。
