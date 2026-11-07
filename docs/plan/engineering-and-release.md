# 工程、AOT 与静态发布

## 目标与状态

Static Assets 是所有客户端扩展分发的最终权威来源。每包只部署最新可用构建，由客户端或 Service Worker 检查索引、更新和清理旧缓存；不再向 GitHub Release 发布扩展，不经 R2/Worker 转发扩展正文。状态：**已实现待完整验收，v4 三包已部署并通过匿名交付验收，首次本地 baseline 已启动、尚未完成**。旧 `7f54463` 全量队列已停止。v3 的固定 `b4f72f7` 独立队列与旧 `022d828` v1 队列均曾启动，但 2026-11-04 复核时已无活动进程，首次 baseline 未完成；两套冻结输入与本地产物仅保留历史证据，不得直接覆盖当前生产。

操作入口见 [EXTENSIONS](../EXTENSIONS.md)，材料契约见 [RUNTIME-MATERIALS](../RUNTIME-MATERIALS.md)，包体方案见 [AOT-SIZE](../AOT-SIZE.md)。扩展 Release/R2 发布实现已删除。实际证据见 [VERIFICATION](../VERIFICATION.md)。

2026-11-05 功能收尾将 host ABI 升至 v4：Java entry 和 HTTP 传输加入每次调用的 owner token，后台 enqueue 有界排空后才交付主结果。Web/Native 材料及扩展必须按 v4 新指纹一起重建；旧 v3 产物在加载前明确拒绝，不提供兼容回退。固定 `1f599cd` 的 xkcd、Arknights、CuuTruyen 已本地重编并通过限定 Web 运行/图片分项，见[v4 运行证据](../verification/v4-source-runtime.md)。固定 `13494a0` 的客户端、Worker 与 v4 三包快照现已部署；Worker 版本为 `9a95d6e6-7578-4781-99aa-3d8bdae6b467`，revision 为 `702cc6bfb2974682bf1c83325458535a`，parent 为 `22378bbcb89d40f5a0397c5098310072`。`commit-snapshot` 后的 `state.json` 已确认新 revision，`bootstrap.complete=false`，状态为 available 3 / unavailable 1 / pending 1445 / failed 0。

匿名 26 路径验收通过，远端网络政策仅含这三个已核对准确 host 的 verified 包，见[生产部署记录](../verification/v4-production.md)。Access 会话已失效，用户答复稍后登录；当前生产正向与 Native 主入口仍未验收。扩展增量工作流继续为 `disabled_manually`，不在 CI 运行首次全量，完成并部署 baseline 前不启用定时 CI。下文 v1/v3 记录均为历史冻结批次，其 checkpoint 不修改、不混装，也不得作为覆盖当前生产的恢复输入。

2026-11-07，固定 v6 完成全量发现与 3 包本地串行试编，试编候选未部署。试编发现同一输入可能生成不同 canonical JS，旧的仅输入派生 ID 会隐藏实际更新。见[试编与身份对照](../verification/aot-current-pilot.md)。绑定摘要的公开 ID 已通过固定三包真编译和静态装配。内置浏览器在同一 D1 验证旧路由下架、xkcd 正式确认更新、本机旧副本清理及原书架首次续读。同日用固定 `952bbab` 的完整计划启动本地单并发 baseline，复用三个精确匹配的试编检查点，开始处理其余 1,445 包。见[本地启动记录](../verification/aot-current-pilot.md#首次本地全量启动)。待全量结束并验证候选后，才进行生产发布与增量 CI 验收。

## 已完成

- Keiyoushi、TeaVM、Suwayomi 通过固定提交的 submodule 引入；研究交付中的项目代码已内化，真正上游用正式补丁追踪。依赖/JAR/seed/大产物留在忽略目录。
- generalized builder 能发现扩展、准备固定工具链、构建原版 JAR 并按包 AOT；源码依赖闭包与 host 输入参与内部指纹，失败按包隔离。
- 包体方案已有真实 A/B：保留 `ADVANCED` 和服务，桥/WASM 共享交付，每包确定性 gzip。额外字典与低收益裁剪不阻塞发布。
- 自有代码统一格式化并由 prek 检查；项目自有自动化与运行时桥统一使用严格 TypeScript；依赖分层由 dependency-cruiser 纳入 CI，细节见 [TOOLING](../TOOLING.md)。通用 CI 仅响应分支 push/PR，tag 不触发。
- HTTP 生产链、构建和注册清单只维护 v2；受控 workerd、真实 TeaVM 编译的模拟 supplier 及 v4 三源 Web 运行/图片分项通过，生产 Access 与当前 Native 运行门仍待验收。
- GitHub 已确认公开，但 IAB 实测 Release/CDN 正文不能跨域读取。用户据此选定最终 Static Assets 方案；不建设私有下载凭据服务。

## 实施与剩余验收

1. **提交稳定宿主。** 完成 HTTP v2、设计解冻与当前决策的整合检查，按里程碑提交并推送。
2. **替换交付合同。** 构建输出 gzip bundle 的 canonical/encoded 元数据；共享材料继续静态/Native 内置。所有客户端从静态索引获取当前清单和扩展，下载时各字节域只校验一次，解压、大小、取消均有界。不提供旧私有路径或旧 Release 回退。
3. **建立静态快照。** 客户端索引只列每包最新成功构建；清单与产物只保留当前集合。索引重新验证，内容寻址产物可缓存；客户端刷新索引后更新所需包，旧会话在操作边界切换并清理不再引用的缓存。不要求为此新增 Service Worker，采用现有客户端逻辑也可满足。
4. **迁移增量状态。** 与客户端索引分开保存当前上游提交、每包依赖闭包/host/输入指纹、最近尝试结果及当前成功构建引用。按输入变化构建，失败保留当前协议和材料仍可加载的上次成功；不兼容旧结果仅保留诊断、不进入部署索引。同一失败指纹不自动反复重试，显式重试或输入变化才再尝试。缓存丢失可重新下载当前静态产物或重建所需包，不能把缓存当唯一 checkpoint。
5. **改造本地与 CI。** 首次全量仍只在本地，固定提交的隔离 checkout、checkpoint、按包诊断和进程组清理不变。定时 CI 检查上游，只处理有界变化集合；缺少已完成 baseline 明确停止，不退化为全量。成功生成完整快照后统一部署，上传或部署失败不提交新状态。部署凭据仅在受信部署阶段使用，不交给扩展 Gradle/AOT 子进程。
6. **移除旧分发。** 删除扩展 R2 正文路由、上传和关联表；D1 的扩展分发相关数据仅保留动态 Source 所需网络授权元数据，书架与阅读进度等业务状态仍以 D1 为唯一权威。已停用旧工作流并删除 90 个扩展 AOT/索引 Release 及其 tag；运行时 seed 是独立锁定构建依赖，保留。清理旧发布器与 Release 专属 CI，源码不保留无用兼容分支。
7. **实际验收后全量。** 用当前代表包验证静态发布、客户端下载、更新替换、旧包清理、失败保留和断点恢复，再建立新完整 plan 与首次本地 baseline。旧 `7f54463` 队列和材料不能继续作为当前产品结果。

当前实现已移除 R2 正文路由和关联表、迁移 Dart/TS 静态索引、加入 gzip 有界验证与可信部署后的网络政策同步。历史固定提交 `022d828` 的两包真实 AOT / 内置浏览器初始化、线上匿名 gzip 下载和旧版本远端清理均通过，D1 仅继承已有域名授权。该提交的本地单并发全量曾启动，原队列包含剩余 1,446 包，后续中断且未完成 baseline；该历史计数不表示当前生产状态。首次全量最终部署、有界 CI 部署及客户端真实更新/旧缓存清理仍需收齐证据；CI 在完整 baseline 部署前继续停用。Actions secrets、全 TS 自动化、依赖规则与固定 Node 24 检查已验证，详细证据见 [VERIFICATION](../VERIFICATION.md)。

当前 Protobuf 控制合同使用 host ABI `karuyomi-source-host-v4`、protocolVersion 2，HTTP bridgeVersion 保持 2；原型不兼容旧控制协议或 Page DTO。历史 `022d828` 全量仍是独立冻结的 v1 输入，不能修改其源码，也不能用当前客户端/材料装配或部署其候选。它的编译覆盖仅证明 v1 批次；当前 v4 包须按新指纹重新构建和验收。三包部署和匿名交付通过不等于生产正向、完整发布或 baseline 验收，完成并部署新 baseline 前不能启用定时 CI。当前图片合同和预算见 [IMAGE-RESOURCES](../IMAGE-RESOURCES.md)。

## 历史冻结批次

2026-11-04，当时 hostFingerprint `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db` 的三包候选已通过正式交付校验。重连 / 布局修复后的客户端从固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 成功完成正式 build、API Worker dry-run 与静态组装一致性检查；`main.dart.js` SHA-256 为 `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa`。host 输入、三包 AOT、共享材料 `63a061a…7a9d` 和 Native 内置 runtime 字节与原 b4 候选一致，静态索引 / 清单精确匹配，仅包含索引引用产物，MIME 规则正确。固定树跟踪输入干净，未改 checkpoint。

该历史 v3 本地候选 revision 为 `e8d72f7ca646483bb98a7e83b0a26334`，parent 为 `22378bbcb89d40f5a0397c5098310072`；当时 `bootstrapComplete=false`、未部署、未启用定时 CI，不是当前生产 revision。完整摘要留在固定树 `/Users/wybxc/.codex/worktrees/reconnect-reader-validation/karuyomi` 的 ignored `.local/reconnect-client-build/client-build-summary.json`。三包及客户端实际分项分别见 [Source Cache](../verification/source-network-cache.md)、[Native Cache](../verification/source-cache-native.md)与[完整章阅读](../verification/full-chapter-web.md)，不将本地构建等同生产或完整 baseline 验收。

历史 v3 首次全量在 main ignored `.local/aot-static-abi3-b4/` 独立 clone 固定 `b4f72f7`，三 submodule 与工具链均锁定、跟踪输入干净；独立 state 来自当时最后已部署 revision，不复制在途 v1 checkpoint。完整冻结计划覆盖 1448 包，并发 1，曾通过正式校验导入三个真实交付供恢复复用。官方 `bootstrap --jobs 1 --limit 10000 --finalize` 曾启动，仅构建和准备本地快照，不自动部署或提交已部署 state，之后已中断。完整 baseline 尚未完成；当时的进程与本地恢复说明保留在 ignored `.local/v3-baseline-plan/` 和独立队列目录，仅供追溯。当前生产已前进到 v4，不能恢复该旧计划后直接发布，也不能修改 parent 绕过前置检查；后续产品 baseline 应基于当前协议、固定输入及已确认的生产 checkpoint 另建计划。

已亲读新 v3 队列的首个实际新构建样本 `all.ahottie`：buildId `ext-all.ahottie-b92d36ca170dd2e6ef9dccdeb92c82d0`，正式 builder 204.91 秒完成，canonical 3791303 B、gzip 793431 B；pipeline 结果为 `built` / `compiled_unverified`，不代表 Source 已可运行。记录位于该独立队列 `builds/b92d36ca170dd2e6ef9dccdeb92c82d0673b49a9d7ae71baa45241bfc1518600/` 的 `build-result.json` 与 `pipeline-result.json`。这是固定样本证据，不维护变化中的完成计数；该记录仅证明当时执行的固定样本，当前队列是否活动以本节末尾复核为准；旧 v1 冻结输入未改。另已核对 `bookorbit` 的正式 AOT 日志：缺少 `OkHttpClient.Builder.dns(Dns)`，属于按包隔离的宿主 ABI 失败，不是环境下载或工具链失败，不将其标为可运行。

历史冻结批次暴露的宿主缺口可供后续正式回归使用，不从失败包自动重试，也不修改原扩展：bookorbit/lanraragi/mango 缺 `OkHttpClient.Builder.dns`，旧 v1 的 komga 缺 `Builder.authenticator`，dragonballmultiverse/manhuarm 缺 `StaticLayout.Builder` 等文本绘图 ABI（后者还用到字体度量与旋转），mangafire 缺 `Class.getResource` 与协程 cancel ABI。DNS 和认证须实现真实请求语义，不能以 no-op 仅换取编译成功。当时 lunaranime 只有 TeaVM `2/2` 无栈错误。当前冻结批次已在独立副本定位该编译器缺陷；隔离修正后仍缺加密和 Android WebView 能力，见[诊断记录](../verification/aot-current-pilot.md#lunaranime-编译器诊断)。原始逐包日志留在各自冻结 checkout 的 ignored 构建目录，不把旧批次的诊断直接归于新输入。

2026-11-04 重新核对当时 v3 的实际 checkpoint 和日志：komga 的该轮失败处于 `upstream` 阶段，是从 `dl.google.com` 下载 `commons-text:1.11.0` 时 DNS 解析失败，尚未进入 AOT，不能称为该轮认证 ABI 失败。后续包持续成功，未见持续的全局下载故障；该轮未完成，记录仅保留其历史范围，不据此恢复当前生产。相同失败输入仅在明确重试时再尝试，不修改 checkpoint 或启动第二个发布器。两条队列的 baseline 均未完成，继续保持定时扩展 CI 停用。

正式 Web 客户端的真实扩展更新已有独立分项：官方 Arknights 1.6.1 → 1.6.2 经当前静态索引、不同 AOT/Worker 重新加载后，首次续读恢复 DREAM 第 3 页并显示原图；旧远端清单/产物 404、两会话与 Worker 最终清理均确认，见[版本更新证据](../verification/extension-version-web.md)。该门使用本地隔离快照，不代表生产 baseline 部署、Native 更新或旧本地 bundle 缓存清理，后几项仍待验收。

## 中断复核与恢复边界

2026-11-04 清理测试进程时，以当时进程列表与工作目录复核，两条历史 AOT 主进程及项目 builder 子进程均不存在。两树跟踪输入仍干净，冻结 state 都保持 revision `22378bbcb89d40f5a0397c5098310072`、`bootstrap.complete=false`；该 revision 已不是当前生产 checkpoint。v3 当时尚无完整候选快照，扩展增量工作流为 `disabled_manually`。日志没有全量完成汇总，因此应记为未完成中断，不能沿用“正在运行”或当作首次 baseline 已完成。

最近的 v3 正式包终态为 `en.aethonwebcomics`（02:45:22 UTC）；其后 `en.akazascans` 仅有部分交付文件，缺少 validation 与 pipeline 终态，不能凭 manifest 或构建输出计为完成。已有正式终态由 runner 在恢复时复验复用，部分输出由正式入口重新构建，不手造成功记录。

该次复核没有重启队列、删除过期锁或改动 state。两套 v1/v3 full-plan、state 和 builds 继续冻结，仅用于历史诊断；不得将旧 checkpoint 或候选直接覆盖当前 v4 生产。后续按 [EXTENSIONS 的恢复约束](../EXTENSIONS.md#首次本地全量与恢复)，以当前协议、固定输入和已确认的生产 checkpoint 另建 baseline 计划，复验后仅复用输入身份匹配的结果；先确认无发布者，过期锁交给 `proper-lockfile` 处理，不修改 parent 绕过前置检查，也不因恢复自动重试相同失败输入。以上为历史复核；当前固定 `952bbab` 的本地全量独立运行，不复用这些历史队列。

## 验收

- 干净 checkout 与固定依赖能重建代表包，原版业务源码/JAR 未修改，构建身份可追踪。
- Web/Native 均以静态当前索引为准，扩展正文不进入 Worker/R2，不依赖 GitHub Release；共享 Native 材料缺失明确失败且无网络回退。
- 输入不变不构建；单包、共享依赖、host 变化分别触发正确集合。失败输入不循环重试，成功旧版本保留；成功更新后快照不含旧版本和孤立大产物。
- 同一部署中索引、清单和正文一致；中断恢复不把半完成输出当成功，客户端取消/有界解压/校验与旧缓存处理有真实证据。
- 本地 baseline 覆盖所有发现项及明确结果，CI 保持增量限额、单部署者与缺 baseline 保护。仅编译成功仍为 `compiled_unverified`、`runtimeReady=false`。
- 提交前 `pnpm format`、`pnpm format:check` 和适当回归通过，prek 不跳过；及时提交推送，源码不夹带临时工程或机器输出。
