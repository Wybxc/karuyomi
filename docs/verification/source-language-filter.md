# Source 语言筛选验证

设计见[扩展目录与当前包语言筛选](../design/source-language-filter.md)。以下区分新增静态目录和原包内筛选，旧阶段的通过项不自动覆盖新增协议、元数据或当前构建。

## 静态目录语言筛选：集中工程检查通过

本轮已接入 `CatalogSource{id,name,lang}`、官方 Gradle `metadata.sources` → manifest → index 投影、TS/Dart 校验及正式目录 UI。目录覆盖当前可用索引，不含尚未交付的上游包；语言操作仅投影已取得的静态资料，明确开包时才加载扩展。manifest/index 资料不一致会在设置注入与 runtime 打开前拒绝。

2026-11-06，本地 macOS，固定 Node/pnpm、Flutter 3.47.5 / Dart 3.13.4 与完整 Xcode 格式工具。新增 Dart 目录 7 项和原包内筛选 4 项均通过，最终完整回归实际覆盖：

- 合同拒绝缺失、重复或不匹配 Source ID、signed int64 越界、非法标量及超长名称/语言，保留空语言与 `all`；静态信息不混入运行时能力。
- `staticIndex` 保留 manifest 的完整 Source 信息；静态装配与注册拒绝名称/语言不一致，manifest 与 index 分别遵守 64KiB / 2MiB。
- 正式 Dart 模型保存不可变资料；打开前拒绝 manifest/index 身份或元数据不一致，不执行 Source、不注入偏好或写业务状态。
- 480×800 正式组件在未加载扩展时可按目录语言显示名称、计数和清除；筛选不增控制/Source/业务请求。隐藏当前构建保留阅读上下文，目录与包内筛选独立；刷新/身份切换和 busy/空目录状态有明确行为。

定向复验入口：

```sh
pnpm exec vitest run packages/contracts/test/static-extensions.test.ts apps/api/test/vite-assets.test.ts packages/runtime-host/test/verified-loader.test.ts packages/runtime-host/test/manager.test.ts
node --test tools/extensions/registration.test.ts tools/extensions/pipeline.test.ts tools/extensions/builder.test.ts tools/extensions/verify-build.test.ts
cd apps/reader
flutter test test/sources/catalog_language_filter_test.dart test/sources/source_language_filter_test.dart --reporter expanded
```

完整 `pnpm format` → `pnpm format:check` 通过，包含 Xcode 原生格式检查；最终文档补录后再次执行相同完整检查。`pnpm check` 通过生成一致性、portable 格式、严格 TypeScript 与依赖层级，官方 Vitest 30 文件 / 424 项、协议 golden 10 项、登记/网络政策 30 项、扩展流水线 50 项、构建工具 14 项、完整性 15 项、TeaVM 源码补丁 4 项和 Cloudflare 工具 9 项全部通过。manager 的 3 个流式预算场景分别确认 manifest 64KiB、index 与 private API 2MiB 的精确边界成功、超一字节拒绝并取消 reader。

`pnpm flutter:check` 最终通过：reader_core 22、source_runtime 58、reader 450 项；三个包严格分析无问题，146 份 Dart 文件格式一致。`pnpm build` 通过运行时材料、Native 内置资源装配、Flutter Web release 及 Worker/Static Assets 构建；本轮使用空扩展目录，装配报告 0 个当前扩展。这不是 Native 应用或真实 Source 构建/运行验收。

首轮完整 Flutter 为 410 项通过、40 项失败：新目录静态名称与已加载 Source 文案相同，旧 `find.text` 定位匹配多个控件。修复 10 个旧导航测试，改按既有 Source ID key 定位；两个详情 helper 用正式浏览列表的标准滚动定位后点击，保留原视口、文案、业务断言与产品行为。修复期间定向回归曾有 6 项因控件尚未滚入视口失败，补齐上述滚动后相邻 9 项通过，随后完整 450 项通过。原始失败及最终日志分别保留在 `/private/tmp/karuyomi-static-catalog-acceptance-*.log` 和 `/private/tmp/karuyomi-static-catalog-locators-*.log`，机器输出不入库。

尚未用当前元数据重建正式 Source 候选，也未据此完成 Codex 内置浏览器、Native 或生产验收；旧清单不增加兼容 fallback，后续候选须由当前固定输入重建。静态目录语言筛选状态为**已实现，集中工程检查通过，实际 Source 与平台待验收**。本记录不把目录可见、AOT 编译或组件通过当作扩展运行可用。

## 历史：当前包 Source 语言筛选

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。正式 Flutter 浏览页的当前包语言筛选已实现；设计见[包内 Source 语言筛选](../design/source-language-filter.md)。状态为**已实现待实际 Source 与平台验收**，以下组件工程结果不代表在线来源或设备通过。

### 定向正式组件回归

新增 4/4 项通过，使用正式 `CatalogPage/CatalogController`、生成模型和现有受控 runtime supplier；480×800 视口通过标准滚动定位控件。复验入口：

```sh
cd apps/reader
flutter test test/sources/source_language_filter_test.dart --reporter expanded
```

实际覆盖：

- 当前包包含 zh/en/ja/all 时，按语言匹配、显示数量并可清除；真实 `all` 值与“全部语言”区分，Source 保留顺序和完整字符串 ID，包括长负数 ID。
- 隐藏当前已选 Source 时显示说明，保留 `activeSource` 和漫画结果；筛选与清除不增加 runtime 控制请求、Source 调用或业务请求。用户明确点击另一 Source 后才新增既有列表请求。
- 切包和正式 reconnect 后的 generation 变化重置为“全部语言”；尚未加载包时不显示筛选，正式开包后才显示控件。没有绕过协议构造空 Source 会话。
- 列表请求 pending 时禁用筛选、清除和 Source 切换；响应完成后保持同会话语言选择，用户可继续明确选择来源。

测试准备曾错误假设重复打开同 build 会重新建立会话；正式 transport 会复用会话，最终改走 `connect` 后重开验证新 generation。空 `sources` 被正式运行时严格拒绝，因此删除不可达空包 UI/夹具，改验未加载会话的控件边界。保留原运行时检查，没有放宽协议或以伪造空 session 取得通过。

### 集中检查与实际运行门

`dart analyze --fatal-infos lib/features/browse/catalog_page.dart test/sources/source_language_filter_test.dart` 通过，无问题。`pnpm flutter:check` 完整通过：reader_core 22 项、source_runtime 42 项、客户端 417 项；三个项目严格分析无问题，129 份自有 Dart 文件格式一致。新增控件改变列表高度后，既有浏览、认证恢复和章节标记测试改用正式浏览列表的标准滚动与可见区域点击，保留原视口、断言和业务路径。

`pnpm build` 完整通过，包含 Web/Native runtime 材料、Flutter Web release 和 Worker/Static Assets。提交使用全库 `pnpm format`、完整 `pnpm format:check` 与正常 prek。本轮产品改动限于浏览页列表投影，不增加协议、业务 API、D1 表或原生插件，也未重新构建或运行 Native App。

组件、分析、全库回归与构建的临时日志位于 `/private/tmp/karuyomi-source-language-*.log`，原始输出不入库。

受控 `SourceInfo` 验证了界面投影和调用边界，不能证明实际 Source 语言清单正确。Codex 内置浏览器、Web/iOS/Android 正式入口与实际多语言包须另留环境证据；生产 Access 和目标设备门继续按 [P0](../plan/p0-runtime-and-reading.md) 与 [P3](../plan/p3-extensions-and-migration.md) 维护。本次筛选不宣称全目录语言检索或多端同步偏好。
