# Flutter 状态管理重构验证

2026-11-12，工程迁移已完成，Web 构建和交互验收继续推进。设计见[状态与依赖装配](../design/flutter-state-management.md)，范围见[计划](../plan/post-prototype-flutter-state.md)。原生现场验收按用户要求停止；组件测试中的 Native 分支属于受控 TestPlatform 回归。

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

原始输出和计数留在 ignored `.local/flutter-state-refactor/`。这里的通过结果不代表实际浏览器、生产 Access 或真机通过。

## Web 与剩余门槛

分支 CI 已配置保留成功的 Web/runtime artifact，供隔离内置浏览器验收，避免本机再次编译。当前尚未把编译或组件结果算作实际阅读验收；Web 结果在取得后补充。
