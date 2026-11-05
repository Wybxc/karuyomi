# 当前包 Source 语言筛选验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。正式 Flutter 浏览页的当前包语言筛选已实现；设计见[包内 Source 语言筛选](../design/source-language-filter.md)。状态为**已实现待实际 Source 与平台验收**，以下组件工程结果不代表在线来源或设备通过。

## 定向正式组件回归

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

## 集中检查与实际运行门

`dart analyze --fatal-infos lib/features/browse/catalog_page.dart test/sources/source_language_filter_test.dart` 通过，无问题。`pnpm flutter:check` 完整通过：reader_core 22 项、source_runtime 42 项、客户端 417 项；三个项目严格分析无问题，129 份自有 Dart 文件格式一致。新增控件改变列表高度后，既有浏览、认证恢复和章节标记测试改用正式浏览列表的标准滚动与可见区域点击，保留原视口、断言和业务路径。

`pnpm build` 完整通过，包含 Web/Native runtime 材料、Flutter Web release 和 Worker/Static Assets。提交使用全库 `pnpm format`、完整 `pnpm format:check` 与正常 prek。本轮产品改动限于浏览页列表投影，不增加协议、业务 API、D1 表或原生插件，也未重新构建或运行 Native App。

组件、分析、全库回归与构建的临时日志位于 `/private/tmp/karuyomi-source-language-*.log`，原始输出不入库。

受控 `SourceInfo` 验证了界面投影和调用边界，不能证明实际 Source 语言清单正确。Codex 内置浏览器、Web/iOS/Android 正式入口与实际多语言包须另留环境证据；生产 Access 和目标设备门继续按 [P0](../plan/p0-runtime-and-reading.md) 与 [P3](../plan/p3-extensions-and-migration.md) 维护。本次筛选不宣称全目录语言检索或多端同步偏好。
