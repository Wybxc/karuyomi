# 协程运行时收敛

## 目标与状态

状态：**已接入官方核心；正式工程检查、JVM / AOT 语义与请求归属分项、固定 `7e8fe769` AOT 的 BH3 / Komiic Web 分项通过；HTTP 适配固定 `48c4526` 的 TeaVM / Node 取消子门、clab 两包重建与正式 harness HTTP smoke 通过，产品取消与剩余平台门继续推进。** 本计划细化 [P0 宿主](p0-runtime-and-reading.md) 的 Kotlin 执行语义，与 [Source preferences](source-preferences.md) 配合。

使用锁定的 `kotlinx-coroutines-core-jvm-1.11.0.jar`，由 TeaVM 将其与未修改的 Source JAR 一起 AOT 成 JavaScript。官方 `Job`、`Deferred`、父子关系、取消、builder、Default / IO / Unconfined dispatcher 和计时器保持原实现；项目只适配已有 TeaVM 平台和请求生命周期，不再维护自有 Job 子集。

## 当前实现

| 范围         | 实现与边界                                                                                                                                                                                                                                                                                                                    |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 协程核心     | 官方 JAR 保留在实际编译及 JVM oracle 类路径。已删除自有 `GreenCoroutines` 和同名 `BuildersKt`、`CoroutineScopeKt`、`Dispatchers`、`StackTraceRecoveryKt` 覆盖。                                                                                                                                                               |
| 宿主入口     | `TeaHost` 与两处 `SourceImages` 调用 [`HostCoroutines.block`](../../runtime/teavm/java/src/main/java/prototype/HostCoroutines.java)，使用官方 `runBlocking` 并加入当前请求的 context element。                                                                                                                                |
| 归属与配额   | `ThreadContextElement` 只设置/恢复原请求，不向外抛异常；活动协程从排队前至整个完成回调链结束持有原请求的工作 lease，LAZY 在实际启动时获取。持久 scope 在新请求中创建的新任务归当前请求；旧任务不借用新请求。                                                                                                                  |
| 构建副本适配 | [`PatchLibraries`](../../tools/teavm/PatchLibraries.java) 精确接入 `AbstractCoroutine` 构造、`JobSupport.startInternal`、两个公开 Function1 completion 注册入口和完成链外层；不重写官方 Job 状态机。不用静态 Job 强引用表，也不为普通持久 `Job` / `CompletableDeferred` 建立工作 lease。完成链重命名和 wrapper 仅由构建生成。 |
| TeaVM 平台   | `parkNanos(n <= 0)` 无操作且不消费 permit；精确适配官方 scheduler Worker 的 context classloader 调用。TeaHost 在 Source 初始化前用官方配置关闭可选协程堆栈恢复，异常和取消继续按官方核心传播。                                                                                                                                |
| 原始输入     | [`prepareLibraries`](../../tools/teavm/build.ts) 和补丁器只操作构建副本，原始官方核心、seed 和 Source JAR 不变。Java/补丁变化自动进入 host 输入指纹，必须重建代表包。                                                                                                                                                         |

[`BrowserCall.Operation`](../../runtime/teavm/java/src/main/java/prototype/BrowserCall.java) 继续管理 HTTP、工作配额、超时、drain 和 generation 生命周期。普通可捕获 Deferred 失败不强制升级成宿主全局失败；失败时仍有工作未结束的 Worker 按既有流程回收。

## 已收敛的差异与依据

旧 `GreenCoroutines.Task` 的父子关系、运行中取消立即完成、`join` 直接重抛原任务错误、简化 `withContext`、启动模式和 active 查询均不能代表官方语义。当前已删除这些实现，改用官方核心，并用真实 Kotlin fixture 对照 JVM 与 AOT：取消等待 finally、父失败与兄弟取消、正常 LAZY、DEFAULT / ATOMIC / UNDISPATCHED 首段、ensureActive、withContext 返回时取消、失败 Job 的独立 join 均通过。它们不是重新实现的宿主语义。

TeaVM 维护者的 [2024 年讨论](https://groups.google.com/g/teavm/c/ipcePs1mHAc)区分语言层 suspend/Continuation 与 TeaVM 线程变换；Promise 示例本身不代表完整 kotlinx 支持。当前结论来自锁定官方 JAR 加项目平台的真实执行。[官方 ThreadContextElement 合同](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-thread-context-element/update-thread-context.html)要求更新/恢复不抛异常，过期检查位于实际工作与回调边界。

原失败、平台修复、候选 v1 红门、v2 JVM/AOT 和独立审查证据见[验证记录](../verification/coroutine-runtime.md)。临时 supplier 只证明 Bridge、二进制 HTTP 和请求归属，不是官方 harness、真实 Source 或 Native 验收。

## 待办与验收

- [x] **官方核心及平台：** 锁定官方 JAR；删除自研 Job/builder 覆盖；修复已复现的平台错误；关闭可选诊断堆栈重建而不吞异常。
- [x] **真实 suspend 与已知语义差异：** 同一 Kotlin fixture 的 JVM/AOT 分项对照通过；不以仅编译成功代替执行。
- [x] **隔离归属：** delay/HTTP/完成回调不提前释放 lease；过期 LAZY 拒绝且其官方 waiter 完成；generic completion 不借下一请求；配额/调度失败清理；ThreadContext 与其它 element 正确恢复。
- [x] **正式工程回归：** `pnpm teavm:check` 使用同一生产补丁器处理的官方 core 副本，保留 Enqueue 全部有效场景，验证运行时类来源且旧 Green 不可达；Enqueue 85 项断言、完整格式与 `pnpm check`（含 418 项集成测试）均通过；按本里程碑提交。
- [x] **HTTP 上游适配与 JVM 分项：** 删除自有阻塞 `OkHttpExtensionsKt`，恢复 seed 的可取消 await / awaitSuccess；只精确适配图片 cacheless / progress 方法。BrowserCall 交付后保留正文，关闭归还独立 64 资源额度，drain 在原总期限内清理后才允许成功确认，超时保留回收信号。隔离真实 seed / 官方 core 的 Java 202、Kotlin 168、原 Enqueue 85 及两路图片各 8355 断言通过；完整 `pnpm teavm:check`、`pnpm check`（418 项集成测试）、全库格式化与完整格式检查均通过。
- [x] **HTTP AOT 子门：** 固定 `48c4526` 的正式 Java/seed await/官方 core 经 TeaVM AOT 后，在 Node 实际通过延迟正文消费、交付后 Job 取消、等待真实 localhost fetch 响应头时取消及 404 关闭；四 handle 各释放一次。首轮业务通过但自然退出超时；最终临时 runner 显式退出后通过，仍有 `Timeout` 资源诊断，不声称自然 idle、64 响应压力或产品取消。
- [x] **HTTP 新包与 harness 工程门：** 固定 `48c4526` 在 clab 后台完成 BH3/Komiic 原 Source 重 AOT、完整性及候选快照；两包保持 `compiled_unverified/runtimeReady=false`。本机同提交的正式构建、60 文件/2 包静态装配、官方 harness 迁移/网络政策和三路径 HTTP 200 通过，无部署或正式 checkpoint 变更。
- [ ] **HTTP 产品取消与新 Source Web：** 新两包实际 Web Source/UI 受 IAB provider 不可用阻断，尚未执行；继续验证正式产品中单个 Job 到 Call.cancel、响应消费与资源收尾、旧代竞争。不能用 Node、HTTP 200、请求级回收或前轮 `7e8fe769` 阅读代替这一门。当前候选缺少后续 `sources` 元数据，仅配固定 48c 客户端，不补字段接入新目录/管理功能。
- [x] **代表 Source Web 分项：** 固定 `7e8fe769` 独立重建两包，通过正式 harness / Flutter 主入口完成 BH3 真实 async / await 详情、21 页阅读与服务端进度确认，以及 Komiic 原镜像设置 / Source 重开、动态筛选 / 分页 / 已应用保留。仅登记实际范围，未部署，自动构建记录仍为 `compiled_unverified` / `runtimeReady=false`。
- [ ] **剩余 Source / 生命周期门：** preference veto / 回调次数 / 丢 ACK、取消迟到竞争与直接资源计数分别验收；继续更多 Source 与平台覆盖，不能由页面正常切换推断所有清理门通过。
- [ ] **交付边界：** Web 实际验收、Native、生产 Access 和真机分别列证据；不据隔离 fixture 通过升级其它层级。全量 baseline 和 CI 增量仍按原计划独立处理。

不为旧宿主增加兼容路径；不以穷尽上游协程库或可选性能研究延迟本轮功能交付。
