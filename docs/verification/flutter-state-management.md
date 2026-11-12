# Flutter 状态管理重构验证

2026-11-12，工程迁移、集中回归、CI Web 构建及内置浏览器主流程已通过。设计见[状态与依赖装配](../design/flutter-state-management.md)，范围见[计划](../plan/post-prototype-flutter-state.md)。原生现场验收按用户要求停止；组件测试中的 Native 分支属于受控 TestPlatform 回归。

## 工程与代码量

相对 `dfce68a`，完整格式化后变更范围内的生产手写 Dart 从 15,702 行降为 15,239 行，**净减 463 行**。首阶段净减 330 行；最新要求扩大到所有控制器和普通订阅组件，新增范围进一步净减 133 行。统计包含新增的账户、书架和漫画 provider，排除 `.g.dart`；设置表单从 716 行降为 429 行，来源目录从 446 行降为 374 行。生成器另产生 423 行，不与手写代码混算。测试、文档和依赖另计。主要删除两套设置字段控件、设置 ChangeNotifier 的手工装配及页面输入/订阅生命周期。

本次全库审计覆盖 AppShell、阅读器/横向页/缩放窗口、书架、章节详情/阅读路由、源迁移、跨源搜索、扩展和仓库管理、漫画源偏好/筛选、分类/书架批量/章节已读/封面弹窗及性能诊断面板。以上控制器与普通 Listenable/Stream/前后台订阅均由 hooks 管理。混合资源的组件保留 StatefulHookWidget / StatefulHookConsumerWidget；剩余普通 StatefulWidget 无此类控制器或普通订阅，ImageStream 解码句柄、资源 pin 与原生 WebView 继续沿用各自专属所有权。

本机固定 Flutter 3.47.5 / Dart 3.13.4，以低优先级单并发执行：

```sh
pnpm flutter:check --concurrency=1 --reporter=expanded
```

三个项目严格分析均无问题；reader_core 22 项、source_runtime 87 项、reader 625 项测试全部通过，生成一致性和最终 192 文件的 Dart 格式检查通过。riverpod_lint 3.2.0 另以临时 `@riverpod` 函数传入 BuildContext 验证，正式 analyzer 确实报告 `avoid_build_context_in_providers`；样例随后移除。

回归覆盖设置 CAS 冲突、迟到确认、同身份恢复保留 UUID/CAS、换身份/服务丢弃旧视图、旧命令不得写入新账户、设置继承与显式 AUTO/false/0，以及既有阅读/图片/预取关闭确认。新增回归确认替换阅读位置输入后，旧输入失效，当前章节和页位保留；新输入仍可跳转，卸载后不再处理输入。两个 provider 消费者共用一次书架读取；失效和退订不增加业务写，也不关闭 runtime。

`request_budget_test.dart` 在主入口记录：启动时各一次设置/书架 GET；来源目录和设置页进入各一次设置 GET；书架重挂载一次书架 GET；恢复前台各一次设置/书架 GET。整个过程只有测试明确发起的一次收藏 POST，未调用 Source。改动前已有 45 项组件基线，但未记录请求数量，故不声称量化的前后请求降幅。

同一导航回归通过 Flutter 官方 `debugOnRebuildDirtyWidget` 按 Element 身份观测构建次数。下表是各阶段累计的“总构建 / 其中重建”，包含初次挂载；书架在返回时会重新挂载：

| 阶段           | AppShell | LibraryPage |
| -------------- | -------- | ----------- |
| 初次确认       | 2 / 1    | 3 / 2       |
| 收藏后进入浏览 | 4 / 3    | 4 / 3       |
| 进入设置       | 5 / 4    | 4 / 3       |
| 返回书架       | 6 / 5    | 6 / 4       |
| 恢复前台       | 7 / 6    | 7 / 5       |

该链路中 KaruyomiApp 始终只构建一次；CatalogPage 和 SourceDirectory 各构建两次，其中各重建一次，GlobalSettingsPanel 构建一次。回调仅用于测试，结束时恢复原回调，没有进入生产路径。该观测属于组件 debug 行为，不能代表真实设备性能，也没有改动前的同口径构建计数可用于宣称降幅。

原始输出和计数留在 ignored `.local/flutter-state-refactor/`。以上工程结果不代表生产 Access 或真机通过；实际 Web 证据单列如下。

## CI 构建与真实 Web 主流程

生产代码提交 `989be6fd4d376b264487d6251f15760a4155974f` 的[完整 CI](https://github.com/Wybxc/karuyomi/actions/runs/43219543794)已通过 `pnpm check`、`pnpm flutter:check`、`pnpm build` 和本地 D1 migrations。分支未执行生产 deploy，属于预期条件。Web/runtime artifact 下载后校验 ZIP SHA256 为 `52b1fe693920c5118b5a0fb519d24e43be68394084269852c8521831eeb5dad7`；Flutter `main.dart.js` 为 `67e288c168028944f67f75c64045a304532b2d537efa9f37666076ec4bf00ded`。后续仅补测试观测和文档，未改变该生产输入。本机仅以官方 Vite 入口装配已有 CI 产物与 190 包扩展快照，没有再次编译 Flutter 或 AOT。

使用 Cloudflare 官方 `createTestHarness`、隔离 D1 和临时 RS256 测试身份 `acceptance-owner`，在 Codex 内置浏览器访问 `http://127.0.0.1:60367/`。使用正式 API、runtime 和真实 xkcd Source，未操作生产业务数据。以下交互实际通过：

1. 全局设置改深色主题及白色阅读背景，等待保存确认；独立 API 读回 global revision 1。
2. 扩展输入框将 190 包筛选为 xkcd，安装后显示账户选择已确认、本机产物已准备；收藏英文 xkcd 后，目录按钮变为取消收藏，API revision 3 包含安装与收藏源。
3. 真实热门列表进入 xkcd 详情并加入书架，章节搜索 `3318`，打开 `3318: Earth Sized Planets`，实际显示第 1 页图片及服务端保存状态。
4. 作品背景改黑色并保存，API 读回 BLACK、revision 1；再改跟随全局，API revision 2、`overrides: {}`、effective WHITE，阅读画面同步为白底。
5. 翻到第 2 页，观察待服务端确认变为已保存、最远第 2 页；放大及重置缩放后仍在第 2 页。退出阅读、详情和 Source，等待收尾完成后回到目录。
6. 跨源搜索选择英文 xkcd，输入唯一无结果查询，显示 `1 / 1 源完成 · 0 项` 和此源无结果，退出并正常返回浏览页。
7. 从书架关闭旧标签，用同 URL 创建全新文档，直接继续阅读。真实图片恢复到 `2 / 2`，显示进度已保存、最远第 2 页；独立 API 读回 current 与 furthest 的 `pageIndexHint` 均为 1。新文档控制台未捕获 error。

本轮精确扩展构建为 `ext-all.xkcd-6fbce1478d2c16bf8f688f9e4bb711b0-d4c7fd8c83a3c5cdd43cb9de2a2a1ebcbbbb793e711794b4dfc13fbb21a60536`。抽样验收不改变其它扩展的 `compiled_unverified` / `runtimeReady=false` 声明。未执行“读完本章”，不将该操作算作本轮通过项。

截图、AX 和独立 API 读回保留在 ignored `.local/flutter-state-refactor/`：`web-evidence/page-1.jpg`、`web-evidence/resume-page-2.jpg`、`web-progress-resumed.json` 及 `web-manga-{overridden,inherited}.json`。验收结束后正常关闭 harness 并释放端口。

## 交付与剩余门槛

变更通过 [PR #2](https://github.com/Wybxc/karuyomi/pull/2) 交付，沿用[主线 CI 自动上线](../DEPLOYMENT.md)。生产发布的权威证据是合入后 main CI 的 deploy 与 `web-release-<sha>` artifact：必须通过公开字节校验和匿名 Access gate，不能用分支编译代替部署成功。

原生现场、正式签名、真机与生产完整写入矩阵未执行，保留各原计划的待验状态。本轮不启动原生环境，也不将隔离身份的 Web 读写记作生产 Access 验收。Flutter 3.50 / Dart 3.14 的升级准备另见[工具链更新计划](../plan/flutter-3.50.md)，上述产物仍使用固定 Flutter 3.47.5 / Dart 3.13.4。
