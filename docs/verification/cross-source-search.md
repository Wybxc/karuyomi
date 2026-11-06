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

## 2026-11-07：含关闭修复的四包 Web 复验

新的官方 Vite / Wrangler harness 为 `http://127.0.0.1:56104`，subject 仍为 `acceptance-owner`，使用新的空 D1；它与上节端口的账户状态相互独立。本轮子代理的内置浏览器 provider 不可用，因此由主代理独占 Codex 内置浏览器实际操作，独立验收代理只读核对 API、候选输入和截图；没有切换其它浏览器。客户端包含 `e71f657` 的已安装 Source 名称筛选修复与 `637d322494b2465fda4864091b7bf7d7c59a5aba` 的关闭认领修复；四包 AOT 仍固定在 `9b98d006`，没有用旧提交的 CI 代替新客户端检查。

前三包构建不变，新增 CuuTruyen（vi，Source `8222087175453285202`），构建为 `ext-vi.cuutruyen-6a74c453163c495195b6d9b0727bbff3`。四包快照位于 `/private/tmp/karuyomi-local-cuutruyen-aot-9b98d006-kNsNNZ/results/snapshot-four`，provenance 的上游、host commit 与 fingerprint 一致；文件大小与 manifest 相符，复用已验证哈希，没有重新计算产物哈希。候选仍为 `compiled_unverified` / `runtimeReady=false`，未部署生产。

独立 GET 确认初始 bootstrap / settings / library / 静态索引均为 HTTP 200，account/global revision 为 0，书架为空，目录为四包八个 Source。主代理通过正式 UI 准备并安装四包后，独立 GET 确认为 revision 4、四条精确 catalog / package / build / bundle hash 均匹配且启用，阅读设置仍为默认。随后管理页搜索“崩坏”仍显示已安装 BH3 的启用与卸载控件，没有实际禁用或卸载；独立重读完整设置与安装后相同，revision 仍为 4。该筛选修复的正式记录另见[扩展管理验证](extension-management.md)。

### 前台交接、结果隔离与真实分页

先通过普通浏览打开 CuuTruyen，并实际得到包括 `Spy x Family` 的热门作品；保留普通 Source 后进入跨源搜索，选择 xkcd en / ru、CuuTruyen、BH3，共四个 Source、三个包，冻结非空查询 `a`。xkcd ru 的 Source ID 为 `3742763978853704441`，其余 ID 见本页表格与上述 CuuTruyen 记录。

浏览器先观察 xkcd en 与 CuuTruyen 同时显示正在搜索，同包 ru 与第三包 BH3 等待；随后 en / ru 各返回 0，CuuTruyen 返回 24 项，BH3 返回原实现的 `No search`，没有再次出现 `RangeError`。这完成了有普通前台 Source 时的实际交接与逐源结果隔离分项；UI 同时显示活动状态不能代替实际 Worker 数量或底层关闭 ACK 的仪器证据。

只点击 CuuTruyen 的“此源下一页”，加载中保留已有 24 项，完成后累计 48 项，并出现第二页的不同标题（包括 `Oniichan…`、`Manga Giáng Sinh…`）。第三页完成后累计 72 项。固定上游的非空搜索确实携带 `q` / `page` / `per_page=24`，本轮同时取得正式 UI 的不同页结果，没有将 Komiic 不带页号的非空搜索当作分页。

第 3 页的一次停止尝试在点击前已完成、控件消失，因此不算取消。随后发起第 4 页，在同一次浏览器操作中读取到“正在搜索、72 项、停止此源”后点击现有停止控件；下一份新状态明确变为“已停止、72 项、重试此源”，没有追加到 96 项。再次滚动检查仍为停止 72 项，其它 xkcd 结果保持不变。截图为 `/private/tmp/karuyomi-cross-search-four-{page1-isolation,page2,stopped}.jpg`。

分页后独立 GET 确认 account/global 仍为 4，四包安装与阅读默认未变，书架仍空，CuuTruyen 无 Source 设置 snapshot。阶段原始响应为 `/private/tmp/karuyomi-cross-source-search-web-four-{baseline,installed,page2-state}.json`，详细机器输出不入库。

### 从跨源结果进入正式详情、图片与服务端进度

在已停止的 72 项中点击 CuuTruyen 的 `A Manga About a Couple Choosing Earrings`，实际进入正式详情，显示作者 `Mikazuki Lamp`、`romance` / `slice of life` 与 1 个章节。点击 `Chương 1 Oneshot` 进入正式阅读，1/5 的真实图片可见；下一页后显示 2/5，AUTO 双页同时呈现第 2、3 页真实图片。新状态明确显示阅读进度已保存到服务端、最远第 3 页。独立审阅详情与第 2 页截图，图片走原 Source 的正式处理及产品阅读链路，没有以直接图片 URL 补足。

独立 GET `/api/settings` 确认 account revision 为 7，global revision 仍为 4，四条安装和全局阅读默认未变。`/api/library` 仅列收藏，本次没有收藏该作品，因此仍为空；没有为验收额外写入收藏。

为定位非收藏漫画的业务 key，按授权只进行一次官方 CuuTruyen 搜索 API 的只读查询，精确标题与作者唯一匹配 id `2414`，章节 id `42231`。这次直接 API 读取只用于定位记录，不算 Source 搜索或阅读证据。按当前 `LibraryRepository` / `ChapterSequence` 算法，以 package、Source ID、原始漫画 / 章节 URL 生成 key，catalog 精确性独立核对，不改变业务身份算法。正式 GET `/api/state/manga/:mangaKey` 及 `/progress` 均为 HTTP 200：

- manga key 为 `dbe3a8aed5902a94b76a655438bddba1748cdc1eb8b204c07d387da3b251bed3`，manga revision 为 3、account revision 为 7。
- resume 与进度均指向 `3759806d3531144a653c4d7c981bc7db8501303eba29b9f6aa8b019dfb039da3`，与原章节 URL `42231` 的正式 key 相同。
- current `pageIndexHint=1`、furthest `pageIndexHint=2`，分别对应第 2 页当前位置与第 3 页最远阅读，与实际双页状态一致；没有标记全章读完。

此非收藏进度记录没有漫画 metadata，不能称 D1 返回了作品标题；标题、作者与原 URL 的绑定来自实际详情截图、单次精确查询和 key 一致性。原始证据为 `/private/tmp/karuyomi-cross-source-search-web-four-reader-{state,progress}.json`，截图为 `/private/tmp/karuyomi-cross-search-four-{detail,reader-page1,reader-page2}.jpg`。这只证明该构建该作品已观察的图片与进度，不证明全 5 页、所有包、Native 或生产 Access。

### 本次工程检查

主代理在冻结修复后完整运行 `pnpm format` → macOS `pnpm format:check`、`pnpm flutter:check`、`pnpm build` 和官方 acceptance Vite 构建，均退出 0。独立读取最终日志核对三个项目分析无问题、Reader Core 22 / Source Runtime 86 / Reader 591 项通过、172 份 Dart 格式零变化，依赖检查为 179 模块 / 590 依赖无违规。日志为 `.local/search-slot-claim-{format,format-check,flutter-check-final,dependencies,build,acceptance-build}.log`。本轮本地没有重复完整 `pnpm check` 的记录。独立一次查询确认精确客户端提交 `637d322494b2465fda4864091b7bf7d7c59a5aba` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42301547558) 为 completed / success，`pnpm check`、`pnpm flutter:check`、`pnpm build`、`pnpm db:migrate:local` 各步成功；不将旧 `9b98d006` 的 CI 当作此修复结果。这些工程结果不替代上述真实 Source 分项。

本轮官方 harness 以 stdin 换行正常关闭、退出 0；`56104` 无监听，原 workerd PID `32636` 已退出，旧 `52409` 也已关闭。四包 AOT controller / JVM 与唯一 CI watch 均已正常退出，没有遗留本轮验收服务。

## 尚未通过的层级

固定三包发现的前台关闭竞态已有四包客户端复验；真实单源分页和活动停止的具体范围见上节。跨源结果进入详情、限定图片阅读与服务端进度已取得上述实际记录；两个包同时返回作品、实际双 Worker 数量与生命周期，以及 Native、生产 Access、独立设备和真机性能仍未因上述分项通过。测试中的两个 transport 不能当作真实双 Worker 运行证据；Source 能力说明使用实际目录、原实现或运行事实，不推断登录、验证码或脚本支持。
