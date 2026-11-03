# 工程、AOT 与静态发布

## 目标与状态

Static Assets 是所有客户端扩展分发的最终权威来源。每包只部署最新可用构建，由客户端或 Service Worker 检查索引、更新和清理旧缓存；不再向 GitHub Release 发布扩展，不经 R2/Worker 转发扩展正文。状态：**已实现待完整验收，两包代表快照已部署验证，本地 baseline 未完成**。旧 `7f54463` 全量队列已停止，当前 v3 的固定 `b4f72f7` 独立队列已启动；旧 `022d828` 的 v1 队列保持原状，二者不可混用。

操作入口见 [EXTENSIONS](../EXTENSIONS.md)，材料契约见 [RUNTIME-MATERIALS](../RUNTIME-MATERIALS.md)，包体方案见 [AOT-SIZE](../AOT-SIZE.md)。扩展 Release/R2 发布实现已删除。实际证据见 [VERIFICATION](../VERIFICATION.md)。

## 已完成

- Keiyoushi、TeaVM、Suwayomi 通过固定提交的 submodule 引入；研究交付中的项目代码已内化，真正上游用正式补丁追踪。依赖/JAR/seed/大产物留在忽略目录。
- generalized builder 能发现扩展、准备固定工具链、构建原版 JAR 并按包 AOT；源码依赖闭包与 host 输入参与内部指纹，失败按包隔离。
- 包体方案已有真实 A/B：保留 `ADVANCED` 和服务，桥/WASM 共享交付，每包确定性 gzip。额外字典与低收益裁剪不阻塞发布。
- 自有代码统一格式化并由 prek 检查；项目自有自动化与运行时桥统一使用严格 TypeScript；依赖分层由 dependency-cruiser 纳入 CI，细节见 [TOOLING](../TOOLING.md)。通用 CI 仅响应分支 push/PR，tag 不触发。
- HTTP 生产链、构建和注册清单只维护 v2；受控 workerd 与真实 TeaVM 编译的模拟 supplier 回归通过，真实 Source/cache 和产品图片仍待验收。
- GitHub 已确认公开，但 IAB 实测 Release/CDN 正文不能跨域读取。用户据此选定最终 Static Assets 方案；不建设私有下载凭据服务。

## 实施与剩余验收

1. **提交稳定宿主。** 完成 HTTP v2、设计解冻与当前决策的整合检查，按里程碑提交并推送。
2. **替换交付合同。** 构建输出 gzip bundle 的 canonical/encoded 元数据；共享材料继续静态/Native 内置。所有客户端从静态索引获取当前清单和扩展，下载时各字节域只校验一次，解压、大小、取消均有界。不提供旧私有路径或旧 Release 回退。
3. **建立静态快照。** 客户端索引只列每包最新成功构建；清单与产物只保留当前集合。索引重新验证，内容寻址产物可缓存；客户端刷新索引后更新所需包，旧会话在操作边界切换并清理不再引用的缓存。不要求为此新增 Service Worker，采用现有客户端逻辑也可满足。
4. **迁移增量状态。** 与客户端索引分开保存当前上游提交、每包依赖闭包/host/输入指纹、最近尝试结果及当前成功构建引用。按输入变化构建，失败保留当前协议和材料仍可加载的上次成功；不兼容旧结果仅保留诊断、不进入部署索引。同一失败指纹不自动反复重试，显式重试或输入变化才再尝试。缓存丢失可重新下载当前静态产物或重建所需包，不能把缓存当唯一 checkpoint。
5. **改造本地与 CI。** 首次全量仍只在本地，固定提交的隔离 checkout、checkpoint、按包诊断和进程组清理不变。定时 CI 检查上游，只处理有界变化集合；缺少已完成 baseline 明确停止，不退化为全量。成功生成完整快照后统一部署，上传或部署失败不提交新状态。部署凭据仅在受信部署阶段使用，不交给扩展 Gradle/AOT 子进程。
6. **移除旧分发。** 删除扩展 R2 正文路由、上传和关联表，D1 仅保留动态 Source 所需网络授权元数据。已停用旧工作流并删除 90 个扩展 AOT/索引 Release 及其 tag；运行时 seed 是独立锁定构建依赖，保留。清理旧发布器与 Release 专属 CI，源码不保留无用兼容分支。
7. **实际验收后全量。** 用当前代表包验证静态发布、客户端下载、更新替换、旧包清理、失败保留和断点恢复，再建立新完整 plan 与首次本地 baseline。旧 `7f54463` 队列和材料不能继续作为当前产品结果。

当前实现已移除 R2 正文路由和关联表、迁移 Dart/TS 静态索引、加入 gzip 有界验证与可信部署后的网络政策同步。固定提交 `022d828` 的两包真实 AOT / 内置浏览器初始化、线上匿名 gzip 下载和旧版本远端清理均通过，D1 仅继承已有域名授权。固定该提交的本地单并发全量已经启动，队列包含剩余 1,446 包，尚未完成 baseline。首次全量最终部署、有界 CI 部署及客户端真实更新/旧缓存清理仍需收齐证据；CI 在完整 baseline 部署前继续停用。Actions secrets、全 TS 自动化、依赖规则与固定 Node 24 检查已验证，详细证据见 [VERIFICATION](../VERIFICATION.md)。

当前 Protobuf 控制合同使用 host ABI `karuyomi-source-host-v3`、protocolVersion 2，HTTP bridgeVersion 保持 2；原型不兼容旧控制协议或 Page DTO。正在运行的 `022d828` 全量仍是独立冻结的 v1 输入，不能修改其源码，也不能用当前客户端/材料装配或部署其候选。它的编译覆盖仅证明 v1 批次；当前 v3 包须按新指纹重新构建和验收。完整 baseline 尚未部署、ABI 更新尚未验证前，不能启用定时 CI。当前图片合同和预算见 [IMAGE-RESOURCES](../IMAGE-RESOURCES.md)。

2026-11-04，当前 hostFingerprint `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db` 的三包候选已通过正式交付校验。重连 / 布局修复后的客户端现已从固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 成功完成正式 build、API Worker dry-run 与静态组装一致性检查；`main.dart.js` SHA-256 为 `a20e6595ed2a299ac227402e9a5ab475b503205b9c6ddb8058e34aeca350d6fa`。host 输入、三包 AOT、共享材料 `63a061a…7a9d` 和 Native 内置 runtime 字节与原 b4 候选一致，静态索引 / 清单精确匹配，仅包含索引引用产物，MIME 规则正确。固定树跟踪输入干净，未改 checkpoint。

本地候选 revision 仍为 `e8d72f7ca646483bb98a7e83b0a26334`，parent 为 `22378bbcb89d40f5a0397c5098310072`；`bootstrapComplete=false`、未部署、未启用定时 CI。完整摘要留在固定树 `/Users/wybxc/.codex/worktrees/reconnect-reader-validation/karuyomi` 的 ignored `.local/reconnect-client-build/client-build-summary.json`。三包及客户端实际分项分别见 [Source Cache](../verification/source-network-cache.md)、[Native Cache](../verification/source-cache-native.md)与[完整章阅读](../verification/full-chapter-web.md)，不将本地构建等同生产或完整 baseline 验收。

当前 v3 首次全量在 main ignored `.local/aot-static-abi3-b4/` 独立 clone 固定 `b4f72f7`，三 submodule 与工具链均锁定、跟踪输入干净；独立 state 来自最后已部署 revision，不复制在途 v1 checkpoint。完整冻结计划覆盖 1448 包，并发 1，已通过正式校验导入三个真实交付供恢复复用。官方 `bootstrap --jobs 1 --limit 10000 --finalize` 已启动，仅构建和准备本地快照，不自动部署或提交已部署 state。完整 baseline 尚未完成，CI 继续停用；准确进程与本地恢复说明保留在 ignored `.local/v3-baseline-plan/` 和独立队列目录。中断后使用同一输入、同一 builds/state 恢复；不要启动第二个 supervisor 写同一 state。若期间部署 parent 前进，等待 builder 完全退出后按新确认 checkpoint 重新计划，复用匹配结果，不修改 parent 绕过前置检查。

已亲读新 v3 队列的首个实际新构建样本 `all.ahottie`：buildId `ext-all.ahottie-b92d36ca170dd2e6ef9dccdeb92c82d0`，正式 builder 204.91 秒完成，canonical 3791303 B、gzip 793431 B；pipeline 结果为 `built` / `compiled_unverified`，不代表 Source 已可运行。记录位于该独立队列 `builds/b92d36ca170dd2e6ef9dccdeb92c82d0673b49a9d7ae71baa45241bfc1518600/` 的 `build-result.json` 与 `pipeline-result.json`。这是固定样本证据，不维护变化中的完成计数；既有单一 supervisor 继续执行，旧 v1 冻结队列未改。另已核对 `bookorbit` 的正式 AOT 日志：缺少 `OkHttpClient.Builder.dns(Dns)`，属于按包隔离的宿主 ABI 失败，不是环境下载或工具链失败，不将其标为可运行。

该冻结批次目前已定位的宿主缺口可供后续正式回归使用，不从失败包自动重试，也不修改原扩展：bookorbit/lanraragi/mango 缺 `OkHttpClient.Builder.dns`，komga 缺 `Builder.authenticator`，dragonballmultiverse/manhuarm 缺 `StaticLayout.Builder` 等文本绘图 ABI（后者还用到字体度量与旋转），mangafire 缺 `Class.getResource` 与协程 cancel ABI。DNS 和认证须实现真实请求语义，不能以 no-op 仅换取编译成功。lunaranime 当前只有 TeaVM `2/2` 无栈错误，尚不能确定首因，需要后续独立诊断。原始逐包日志留在冻结 checkout 的 ignored 构建目录。

## 验收

- 干净 checkout 与固定依赖能重建代表包，原版业务源码/JAR 未修改，构建身份可追踪。
- Web/Native 均以静态当前索引为准，扩展正文不进入 Worker/R2，不依赖 GitHub Release；共享 Native 材料缺失明确失败且无网络回退。
- 输入不变不构建；单包、共享依赖、host 变化分别触发正确集合。失败输入不循环重试，成功旧版本保留；成功更新后快照不含旧版本和孤立大产物。
- 同一部署中索引、清单和正文一致；中断恢复不把半完成输出当成功，客户端取消/有界解压/校验与旧缓存处理有真实证据。
- 本地 baseline 覆盖所有发现项及明确结果，CI 保持增量限额、单部署者与缺 baseline 保护。仅编译成功仍为 `compiled_unverified`、`runtimeReady=false`。
- 提交前 `pnpm format`、`pnpm format:check` 和适当回归通过，prek 不跳过；及时提交推送，源码不夹带临时工程或机器输出。
