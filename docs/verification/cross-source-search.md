# 跨源搜索验证

2026-11-07，本地 macOS，Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。实现范围见[设计](../design/cross-source-search.md)，剩余验收见[计划](../plan/cross-source-search.md)。主代理实现正式搜索服务与运行槽接入，独立验收代理维护正式服务测试并只读审查；界面与控制器由另一子代理实现。

## 独立服务与界面回归

`apps/reader/test/search/catalog_source_search_test.dart` 的 10 项独立回归通过。它走真实 `CatalogController`、业务状态客户端、`TransportSourceRuntime` 和两个控制 transport，Source 返回与网络时序受控；没有执行官方扩展 AOT 或真实上游请求。

覆盖不同包两个槽并行与第三包等待、同包多 Source 串行、排队与启动取消、活动取消的真实 `runtimeLost` 合同、启动/活动重置 ACK 丢失后保留清理门和显式重试、账户精确来源替换后丢弃旧结果、活动阅读拒绝搜索，以及打开结果前等待旧槽关闭。搜索服务的物理清理确认与结果 epoch 检查分别断言，不能用拒绝迟到结果替代 Worker 已关闭。

验收中修复了三类问题：活动取消以 `runtimeLost` 结束时仍等待显式 reset ACK；启动取消的 reset ACK 丢失后，即使尚无 session 也登记待清理槽；取消与关闭按包单飞，避免两个并发 reset 使对方 ACK 失效。取消先发生时关闭等待该清理，关闭先发生时后续取消只等待关闭。

界面侧 12 项控制器与 5 项 Widget 回归通过，覆盖冻结查询与 Source 选择、分组结果、分页/重试/取消、明确限额、不自动复活旧身份、关闭失败重试、生命周期停止和正式详情导航。另有 Native 图片门回归确保 SEARCH / UNSPECIFIED 的 acquire、cancel、release 不影响前台图片。

宿主侧独立审查另发现同一 turn 并发 SEARCH dispose/open 会误用已退休 manager；先等待关闭并持续复查关闭状态后才选择 manager。新增正式 manager 回归已验证修复前失败、修复后通过，51 项该文件测试通过。

临时日志保留在 `/private/tmp/karuyomi-cross-source-search-*`，不提交机器输出。

## 集中工程检查

独立代理运行完整 `pnpm check`，退出 0：生成一致性、portable 格式、严格 TypeScript / tools / bridge 类型及依赖层级通过；33 文件 478 项 Vitest、10 项跨语言 golden、34 项登记/网络政策、50 项扩展工具、14 项构建、15 项完整性、4 项 TeaVM 与 9 项 Cloudflare 回归全部通过，共 614 项。

最终完整 `pnpm flutter:check` 退出 0：三个项目严格分析均无问题，Reader Core 22 项、Source Runtime 78 项、Reader 573 项测试通过，171 份自有 Dart 格式零变化。首次完整运行在测试后因尚未统一格式化而退出非零；统一格式后暴露的 13 处大括号 lint 已通过官方 `dart fix` 修复，再完整格式化与重跑上述检查，未降低分析门槛。

全库 `pnpm format` → 完整 `pnpm format:check` 通过，含 Java、Dart、TypeScript、配置和原生语言。`pnpm build` 通过 runtime-host、Native runtime 资源复制、Flutter Web release 与 API/Cloudflare Vite 构建；本次 Static Assets 为 57 文件、0 个 current extensions，因此只是工程构建，没有据此宣称官方 Source 在线能力。没有跳过正常 prek hook。

## 2026-11-07：固定三包的真实 Web 分项与关闭竞态

本轮主代理用 Codex 内置浏览器操作正式 Flutter Web 客户端和官方 Vite / Wrangler acceptance harness `http://127.0.0.1:52409`；独立验收只读核对 bootstrap、设置、Source 设置和静态目录，没有代写账户。subject 为 `acceptance-owner`，隔离 D1 从 revision 0 开始，不是生产 Access 会话。

客户端与本地三包 AOT 基线为 `9b98d006dd12d5a62106abde846716d9cd6f7b26`；其精确 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42297248814) 已独立核为 completed / success，作为工程前提。扩展上游为 Keiyoushi `efa93f5a3537856fe830450bbe33f69d21d28167`，三包 provenance 的 host commit / fingerprint 一致，索引与 build / snapshot manifest 的来源、版本、Source ID 和 bundle 标识相符。独立审查只复用已验证的记录并核文件大小，没有重复计算产物哈希。

| 实际选择          | Source ID             | 固定构建                                         |
| ----------------- | --------------------- | ------------------------------------------------ |
| xkcd，en          | `1538249443376436084` | `ext-all.xkcd-aa5f4f1052b403b7872a5164324530c8`  |
| 《崩坏3》IP站，zh | `5943234929466346733` | `ext-zh.bh3-da7ecec8046b9b2096163008cb2f8d96`    |
| Komiic，zh        | `792932060924485302`  | `ext-zh.komiic-f3fca8341e357a54bfc986666b378744` |

三包分别通过正式 UI 准备并确认安装。独立 GET 核对 account/global revision 到 3，三条记录均启用，精确 catalog URL / `keiyoushi` / package / build / bundle hash 与 snapshot 一致；阅读设置保持默认，书架、收藏 Source 与额外仓库列表为空。构建候选仍为 `compiled_unverified` / `runtimeReady=false`，本地 bootstrap 未完成且没有部署生产；不因下面的 Web 分项修改候选状态或推广到其它 Source、平台与构建。

### 实际返回与原 Source 的能力边界

首轮明确选择上述三个 Source，冻结查询词 `女`。浏览器先观察两组同时显示正在搜索，随后各组独立更新：

- xkcd 返回 0 项，UI 显示此漫画源没有找到漫画。
- 崩坏3 显示 `java.lang.Exception: No search`；明确只重试该源后仍是原错误，xkcd 空结果和 Komiic 错误保留。
- Komiic 默认 `.com` 镜像返回 HTTP 500。这里只记录实际错误，没有据此推断登录、验证码或权限要求。

这些结果与固定上游源码的事实边界分别核对：xkcd 的 `getSearchMangaList` 固定返回空列表，崩坏3 的原实现直接抛 `No search`；Komiic 非空关键词分支调用不含页号的 `searchQuery`，只有空关键词列表分支使用分页，而产品跨源搜索要求非空词。因此本轮不证明两个包都返回作品，也不证明真正的单源下一页，不能以热门列表、空结果或重复第一页替代该门。

主代理退出搜索，按普通浏览正式入口打开 Komiic，默认镜像热门同样返回 HTTP 500；通过原 Source 的“漫画源设置 → 镜像站点”选择第二镜像 `komiic.cc` 并应用，UI 显示设置已确认。独立 GET 核对 account revision 到 4、global revision 仍为 3，精确 Komiic Source 的设置 snapshot revision 为 1，只有 `preferred_mirror` 文本值 `1`；三条安装和全局阅读设置均未改变。随后 `.cc` 的普通热门实际返回“腦洞學生會”，这仅计为该镜像的热门结果。

### 真实操作发现前台关闭与双包认领竞态

保留上述已打开的普通浏览会话，再进入新跨源页，以同样三源和查询词开始，第二轮出现正式产品失败：xkcd 正常返回 0，崩坏3 / Komiic 却显示 `RangeError Value not in range: 0`。该轮已停止并保留修复前截图 `/private/tmp/karuyomi-cross-search-claim-race-before.jpg`，不记为跨源运行通过。

独立代码复核确认：首包先占据 `_searchOwner`，再等待前台 `closeBuild` ACK，空闲槽尚未填入；第二包在 `_claim` 看到 owner 已是自己后提前返回，绕过共享的 `_claiming`，对空 `_free` 执行 `removeAt(0)`。修复将等待进行中的 `_claiming` 放到已持有 owner 的判断之前，使所有包等待同一次前台关闭确认。

新增两项正式搜索服务回归：held 前台关闭 ACK 时两个包均不能打开或调用 Source，ACK 后才执行；关闭拒绝时两个包都不能绕过失败，保留待清理门，显式 reset 确认后恢复。held ACK 用例在旧逻辑下先失败，修复后服务、控制器和 Widget 定向集合 29/29 通过，日志为 `/private/tmp/karuyomi-search-claim-race-{red,green}.log`。这 29 项仍是受控组件回归，含修复客户端的真实浏览器复验与最终工程结果另行记录，不用原 `9b98d006` 的 CI 代替。

本轮本地候选与构建记录保留在 `/private/tmp/karuyomi-local-cross-search-aot-9b98d006-7b4V07/results/`，独立输入审计、D1 原始响应与阶段快照为 `/private/tmp/karuyomi-cross-source-search-{aot-input-audit,web-*}.json`。详细机器输出和产物不入库；后续继续使用官方 harness、正式 UI 和原 Source 设置验证，未使用手写服务器或直接业务写入补足 UI 结果。

## 尚未通过的层级

已取得的固定三包 Web 分项见上节；真实运行同时发现了前台关闭竞态，修复后的浏览器复验仍须完成。两个包有作品的独立返回、真实单源分页、活动停止、跨源结果进入详情与阅读、实际双 Worker 数量与生命周期，以及 Native、生产 Access、独立设备和真机性能均未因上述分项通过。测试中的两个 transport 不能当作真实双 Worker 运行证据；Source 能力说明使用实际目录、原实现或运行事实，不推断登录、验证码或脚本支持。
