# Web 完整章与下一章阅读

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，主代理在 Codex 内置 Chromium 156，以固定 `b4f72f70804f12caef21bb51a17cb5adad6982d4` 的正式 Flutter Web release，通过两源完整章的逐页显示、进度保存与同路由下一章阅读。这里使用本地受控 RS256 身份及隔离 workerd/D1，不是生产 Access、Native、物理设备或性能验收。

## 固定输入

客户端 `main.dart.js` 为 3604376 B，SHA-256 `f66f896a8a9e9fef7ef325fe25c4b2c294b58a751078aa65c38989615e437027`。host/worker 与六项共享材料逐项匹配正式清单；hostFingerprint 为 `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db`，materialVersion 为 `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`，protocol 2 / host ABI v3。原 JAR、AOT、清单完整身份见[同 host Source 记录](source-network-cache.md#同新-host-的其它-source-回归)。没有修改原 Source/JAR，也没有直接请求原图绕过图片链。

| Source / 实际新构建                                                         | 完整章                                                                         | 同一路由下一章                                                     |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| Arknights Comics，`ext-en.arknightscomics-ef114e43af44b3bda11182fc16202bb5` | Prelude Suite: The Lone Walker / DREAM，51 页逐页显示并保存，末页显式完成      | HEARTBEAT，51 页清单，实际显示第 1–3 页并保存；其余页未在本轮阅读  |
| CuuTruyen，`ext-vi.cuutruyen-94c37a892ae82a87c4600d5ee1704eeb`              | Spy x Family / Chương 142，23 页经原 Source 解密、逐页显示并保存，末页显式完成 | Chương 141，27 页清单，实际显示第 1–4 页并保存；其余页未在本轮阅读 |

## 实际操作与边界

从正式主入口依次选择浏览、扩展、Source、热门漫画、详情和章节。先手动关闭双页，随后每次点击下一页，等待可见 UI 同时显示当前页码、对应最远页和“本地进度已保存”，再继续。DREAM 的 1–51 和 Chương 142 的 1–23 均有逐页 AX 记录；首、中、末页另存截图，末页图片实际可见。完成按钮可用后显式点击，UI 显示“本章已读完”；下一章通过正常章序控制进入，未替换路由或绕过旧资源关闭流程。

下一章使用默认布局：HEARTBEAT 的第 2/3 页形成双页，Chương 141 的宽第 2 页独立显示，之后第 3/4 页形成双页。锚点页与最远已显示页可以不同，不以二者相等作为双页阅读合同。退出阅读后，两源入口均返回原漫画详情并显示“继续阅读”。这不代表浏览器进程重启或生产登录恢复。

本地网络记录分别包含 64 和 34 条已完成 HTTP 200，其中图片请求为 59 和 29 条，包括正常有界预取；这些数字不能代替资源峰值或逐请求 Cache 命中证据。章节退出会取消无用预取，本轮没有把记录数或网络减少当作缓存命中。图片 release/Blob 撤销精确分项仍引用[原 Source 图片门](source-network-cache.md#同新-host-的其它-source-回归)，本轮 UI 未增加隐藏资源计数器。

实际发现一个产品缺口：手动关闭双页后，末页进度/邻章控件引发 viewport 高度变化，自动宽度策略又将双页打开。完整章图片和保存分项已通过，但该布局选择保持门失败，正式 Widget 回归已先复现旧码失败，修复后章内手动选择不受面板、工具栏或尺寸变化覆盖；外部显式参数或章节变化重置选择，未手动时仍按宽度自动布局。Reader 37 项测试及定向 Dart 分析通过，修复后的实际浏览器复验另行记录。没有把本轮所有阅读设置认定为通过。

自动化曾因 Flutter tooltip 使“下一页”的可访问名称重复而匹配失败，改为匹配名称前缀；第 28 页一次等待超时后，新的 AX 已确认该页可见且保存，再继续。两项保留在 UI 报告，不通过重读或补帧伪造第一次显示。双页与宽图的最远页预期也按实际可见布局核对。

## 修复后末页布局复验

2026-11-04，主代理在同一 Codex 内置 Chromium 156，以固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 的正式 Flutter Web release，于新 origin `8926` 重验上述布局缺口。客户端 `main.dart.js` 为 3605960 B，SHA-256 `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa`；Source 使用原 Arknights AOT `ext-en.arknightscomics-ef114e43af44b3bda11182fc16202bb5`，canonical SHA-256 `8969cab4db08462d60284f193a3680e0704b41303eb81c9deb7dea761fdfc98c`，未修改 Source/JAR 或替换图片链。

从正式入口进入漫画详情和第 1 章 `DREAM`，手动关闭双页，再以 End 到 `51 / 51`，等待“本地进度已保存”并显式读完本章。主代理读取的新 AX 确认双页值仍为 0，当前 `51 / 51`、已保存及“本章已读完”；截图也实际显示末页。正常返回后详情显示“继续阅读”。本项确认末页进度与邻章面板出现时仍保留手动单页选择，**没有重新逐页阅读 51 页**；上文旧 b4 完整章报告及当时布局失败保留，不以本项替代完整章、其它布局或 Native 验收。

材料已从 `/tmp` 复制到固定树 `/Users/wybxc/.codex/worktrees/reconnect-reader-validation/karuyomi` 的 ignored `.local/reader-layout-browser/`，客户端摘要与报告一致，跟踪输入未改。`ui.json` 保存主代理本轮观察及末次 AX 摘录；截图是实际末页可见证据，网络记录不作为 Cache 命中或资源峰值证据。

| 材料          | SHA-256                                                            |
| ------------- | ------------------------------------------------------------------ |
| ui.json       | `585c6e203f8ebcf44254ff151f61c04ff9275d856e344abf411612ede89c1588` |
| last-page.png | `5b909e4feff847a526d1f2958f5da6b3de4c0cba166f64561233429395ffe3ce` |
| network.json  | `9a4c1279514b2b516094af05963776d308a1a1986a687a38e1f95855236f77e5` |

复验沿用下一节正式产品入口与受控 RS256/workerd/D1 方式，`SOURCE_PROBE_READER_DIR` 指向该 be5 固定树的 `apps/reader/build/web`，端口为 `8926`、Source ID 和域名仍使用 Arknights 的显式配置。这里只验证修复后的末页分项，不是生产 Access、浏览器进程重启或性能门。

## 复验与材料

固定树为 `/Users/wybxc/.codex/worktrees/source-network-cache-validation/karuyomi`。先以三包候选运行正式 `pnpm build`，再使用该树未修改的 `apps/api/test/source-metadata-probe.ts`，设置 `SOURCE_PROBE_READER_DIR=apps/reader/build/web`。Arknights Source ID 为 `5973713386239249589`，显式域名为 `arknights.global,webusstatic.yo-star.com`，origin 8922；CuuTruyen ID 为 `8222087175453285202`，显式域名为 `cuutruyen.net,hetcuutruyen.net,storage-bravo.cuutruyen.net,storage-charlie.cuutruyen.net`，origin 8923。按照[正式 probe 说明](../../apps/api/test/source-metadata-probe.md)从产品入口复验，不运行 `/probe` 代替产品阅读。

原始材料位于固定树 ignored `.local/network-cache-source/full-chapter/`，临时服务与标签页完成后正常关闭；生产登录页未操作。启动时一项 Source ID 配置校验失败及一次尚未请求网络的 CuuTruyen allowlist 配置更正不计作运行通过。

| 报告                   | SHA-256                                                            |
| ---------------------- | ------------------------------------------------------------------ |
| arknights-ui.json      | `ba48784149310a9a222627cd8d013dbc25dba5d800eb6209c14942c8be60ba54` |
| arknights-network.json | `bf07c21711a5d3e8b9838f3962962e25b0ec8313645b65cc5ce82886982d6ac2` |
| cuutruyen-ui.json      | `0eb97cc715f318b36ead2cb067a5c18637a819d04010c06587de6f50efe4013e` |
| cuutruyen-network.json | `c8609be84e975336a01720d3bdfef677c12f23a0782e557d7ba446281783948a` |

AOT 保持 `compiled_unverified` / `runtimeReady=false` 的保守交付状态；这些实际运行分项单独记录，不能推广为全源、完整 P0 或所有平台已经通过。
