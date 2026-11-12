# 扩展与浏览 UI 流程验证

2026-11-12。对应[设计流程](../design/extension-browse-ui-flow.md)和[实施计划](../plan/browse-ui-flow.md)。本轮使用本机固定的 Flutter 3.47.5 / Dart 3.13.4、Node 24 和 pnpm 12.6.0。用户授权本机运行 Flutter 分析、测试和 Web 构建；扩展 AOT 仍只在远端，本轮没有编译 AOT。原生验证继续停止。

## 实现范围

- `CatalogPage` 提供“漫画源 / 扩展”入口；源目录只投影账户已确认的精确构建资料，名称搜索、语言筛选和收藏排序不运行扩展。
- `SourceBrowsePage` 自动准备并打开所选源，独立维护作品列表、查询上下文、刷新和追加状态。失败保留原列表；离开时等待当前列表或详情请求收尾，不接受迟到结果或继续请求章节。
- 扩展列表按“需要处理 / 已安装 / 可安装”分组；详情、仓库管理和本机存储独立。账户确认、冲突、待确认操作和本机清理失败分开展示。
- `MangaDetailsPage` 从原浏览页移出，保留原详情、书架和阅读流程。普通 Source 缩略图尚无正式资源通道，因此显示占位；账户自定义封面继续使用既有正式字节通道，不以原始图片 URL 绕过插件处理。

## 自动回归

本机完整 `pnpm flutter:check` 已通过：`reader_core` 22 项、`source_runtime` 87 项与客户端 621 项全部通过，三个项目严格分析和 Dart 格式检查成功。完整 `pnpm format`、`pnpm format:check` 和正式 `pnpm build` 均通过；最终通用工程检查由本分支 PR 的 CI 记录。

重点覆盖：

- 精确构建准备不写账户、不静默升级；未安装、停用、仓库移除、已下架和设置未确认保持门禁。
- 收藏等待 ACK、丢确认恢复、身份隔离、收藏上限和不可用收藏的取消；禁用收藏按钮不会穿透而打开源。
- 输入不自动搜索，新查询、刷新和追加失败保留正确标记的原结果；下一页重试使用原页码；空结果与首次失败不同。
- 列表或详情请求中返回，等待收尾后退出；迟到详情不触发章节请求或重新导航。
- 阅读后的跨源搜索只忽略已收到关闭确认的预备章节；关闭确认仍在途的章节继续阻止搜索获取执行槽。内置浏览器发现旧集合误计已关闭预备章节后补此修正，服务层 13 项定向回归通过。
- 原书架、分类、书签、设置、自定义封面、章节已读、阅读进度和身份退休回归。原生 integration test 的新导航调用已更新并参与分析，但未运行原生验收。

原始本机日志保存在忽略目录 `.local/ui-flow-{flutter-check-final,format-final,format-check-final,build-final,source-final,search-final,navigation-final}.log`。完整提交使用仓库真实 prek hook，没有跳过检查；用户原有的 `pnpm-lock.yaml` 未纳入任务提交。

## Web 验收输入与边界

Web 使用正式 `pnpm build`、Vite acceptance 配置和 Cloudflare `createTestHarness`；测试身份及 D1 与生产隔离。扩展来自已上线七材料首批归档中的 190 包静态快照，保留原索引、清单、gzip 和 `compiled_unverified/runtimeReady=false` 声明。组装时执行正式完整性及材料匹配门，不修改扩展业务源码、JAR 或发布检查点。

首轮内置浏览器已通过：安装、停用、阻断源跳回管理、重新启用、本机清理、自动下载精确构建、语言筛选、收藏源、源内搜索空态、清除查询、真实 xkcd 详情与阅读、两页服务端保存，以及返回原列表的书架标记。

本机清理前与清理后、自动准备并打开源后的独立 `/api/settings` 响应逐字节相同，确认这些操作没有提交账户安装或更改所选构建。原始响应分别是 `.local/ui-flow-settings-{before-cleanup,after-auto-download,after-open}.json`。

首轮发现的阅读后跨源搜索误报已修复。基于 `a0b9cfa` 的正式 Web 产物通过内置浏览器复验：安装 xkcd、从源列表进入详情、加入书架、读取两页并保存、返回原列表、再从目录执行跨源搜索。搜索显示“1 / 1 源完成”，目标源“已返回 · 0 项”，退出时完成清理。之后关闭旧标签，在新标签的书架点“继续阅读”，首次显示第 2 页真实图片、`2 / 2` 与服务端已保存提示。

独立 API 读回 `current.pageIndexHint=1`、`furthest.pageIndexHint=1`，对应第 2 页。权威响应为 `.local/ui-flow-evidence/resume-{library,progress}.json`。源目录、真实读图、书架标记和阅读后搜索的截图/AX 在同一忽略目录；新标签续读的截图见[本轮验收聊天](codex://threads/01a1c5f6-bbbd-7582-9e11-2c01c6a5bb3b)。

浏览器复验后，将详情的等待范围收束到详情请求，避免把已打开页面的导航寿命当作待完成请求。对应三份导航测试 17 项及最终完整 621 项客户端回归、严格分析和正式 Web/Worker 构建均通过；这处等待范围修正未单独重复浏览器整条阅读链路。

## 复验入口与限制

使用固定工具链，设置 `FLUTTER_ROOT`、`XDG_CONFIG_HOME` 和可写的 `WRANGLER_LOG_PATH`；本机产物输入为 `EXTENSION_ASSETS_DIR=.local/ui-flow-acceptance-assets`，包含归档提取的 `extensions/`。可复验入口：

```sh
pnpm format
pnpm format:check
pnpm flutter:check
pnpm build
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts
pnpm acceptance:serve
```

内置浏览器访问最后一条命令返回的 `ACCEPTANCE_URL`。验收结束后已停止本轮 harness。上述隔离验收不覆盖原生、真机、生产 Access 或全目录兼容；随后的生产分项如下。

## 生产发布

2026-11-12 16:27:42（UTC+8），[PR #1](https://github.com/Wybxc/karuyomi/pull/1) 已合入 `main@13138c1632e319c546f13957c3954b68863895e4`，[该提交的完整 CI](https://github.com/Wybxc/karuyomi/actions/runs/43181546134)通过。产品输入与 `f735e52` 逐项比较无差异，复用该输入的最终正式本机构建，没有重复 Flutter 或 AOT 编译。Wrangler dry-run 通过，先上传再切换到全部流量；上传阶段核对旧版本仍在服务。

| 身份                         | 已确认结果                                                                  |
| ---------------------------- | --------------------------------------------------------------------------- |
| Worker version               | `d6281303-d106-4bdf-8bbd-8f505342a5f4`，100%                                |
| Deployment                   | `baeb3cd2-ed9a-4f6e-809b-80a040b0aba0`                                      |
| Flutter main.dart.js SHA-256 | `528ba9b437b8653420cace8660d91c864d47b377bca24561b1d60827b6647b03`          |
| 扩展 revision                | 保持 `6bf6597462c449d58b73a48512c9aca2`，190 包，`bootstrap.complete=false` |

切流前后扩展 index/state 与候选逐字节相同，七材料不变；没有提交新的扩展 checkpoint。D1 账本只读核对连续至 `0010`，与源码文件一致，本次未执行数据库迁移。生产 HTML 使用 `/` 作为规范入口；线上 Flutter、host/worker 与七份材料的字节/摘要匹配候选，四个匿名 API 路径仍跳转 Access。

Codex 内置浏览器在真实生产 Access 会话中读回原书架，显示新“漫画源 / 扩展”分栏，从目录直接打开已安装 Komiic，自动准备账户所选构建并返回真实热门作品；返回时完成关闭收尾，扩展列表显示“已安装 / 可安装”和本机就绪。此次采用针对新入口的最小生产检查，没有重复此前完整的阅读/保存/新标签矩阵，没有更改书架或阅读进度。

原始上线证据保存在 `.local/ui-flow-production-13138c1/`，含上传/切流日志、前后部署身份、`pre.json`、`post.json` 和 `production-source.png`。原生验证继续停止，普通 Source 缩略图及全目录运行兼容仍按原限制记录。随后用户选择[主线 CI 后自动发布](../DEPLOYMENT.md)，后续自动发布以相同 SHA 的 CI job 日志及 `web-release-<sha>` artifact 为执行证据。
