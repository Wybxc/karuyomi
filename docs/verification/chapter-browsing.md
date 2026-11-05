# 详情章节浏览验证

2026-11-06，正式 Flutter 详情页已接入章节名、扫描组及显示编号搜索，支持来源原序/反序和书签组合筛选，并显示同名、重复链接与来源序号。章节身份、完整阅读目录和会话状态边界见[设计](../design/chapter-browsing.md)。

## 受控正式入口

`apps/reader/test/browse/chapter_list_navigation_test.dart` 的 4 项导航测试通过，目标静态检查无问题。测试使用正式 `KaruyomiApp`、详情与阅读路由，Source/业务请求由既有测试 supplier 提供。

- 相同标题/URL、缺失编号、小数和零编号全部保留；原序及反序按原始出现顺序展示，不按 `sourceOrder` 或章节号猜测重排。
- 章节名、扫描组及显示编号可搜索，空白和清空恢复列表。搜索、排序和书签筛选不增加 Source 调用。
- 搜索、反向和“仅书签”组合后打开重复 URL 的指定出现，实际 Source pages 调用仍携带原始完整 Chapter DTO（包括 memo），章节键和 `sourceIndex` 正确；阅读器保留完整目录及选定顺序，返回详情保留当前会话筛选。
- 经正式进度 mutation 预存反向顺序，阻塞首次详情 state 读取，在未返回前从真实 UI 打开章节；确认未强传页面默认顺序，放行后实际阅读器恢复服务端反向顺序，返回详情也采用同一顺序。

受控 pending spinner 期间使用有界帧推进等待路由挂载；真实顺序断言和请求 gate 保留。未修改产品 spinner、全局测试 runner 或增加手工服务器。

## 复验与范围

```sh
cd apps/reader
flutter test test/browse/chapter_list_navigation_test.dart --concurrency=1
```

使用仓库固定 Flutter SDK。本轮集中检查已通过：

- `pnpm check`：372 项 Vitest 及全部协议/工具测试通过，157 模块 / 509 依赖无违规。
- `pnpm flutter:check`：reader_core 21、source_runtime 42、客户端 295 项通过，静态检查无问题。
- `pnpm build`：正式 runtime 资源、Flutter Web、Worker 与 Static Assets 构建通过。
- 提交前执行 `pnpm format` 与完整 `pnpm format:check`。

新增控制使窄视口内部分章节处于屏幕外，旧导航测试因此补上真实滚动。沿用原 800×600 视口、收藏/精确进度/身份/重试及迟到资源清理断言；未放大测试视口或静默忽略未命中点击。懒列表使用官方 `scrollUntilVisible`，现有 ListView 子项结构保留，没有把整份章节目录放入一个 Column。

临时输出留在忽略的 `.local/chapter-browsing-*.log`。

这四项是正式产品组件导航与受控 supplier 证据，尚不是实际 Source、独立浏览器、Web/Native 组合、生产 Access 或真机验收。章节浏览不新增跨端业务记录；范围已读/标未读、书架批量操作和其余 P1 功能继续保留待办。
