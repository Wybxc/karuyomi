# 协程运行时收敛

## 目标与状态

状态：**产品迁移进行中；官方核心的真实挂起、取消与 Default 隔离闭环已通过，平台修复和宿主所有权集成分开推进。当前产品仍使用自研入口。** 本计划细化 [P0 宿主](p0-runtime-and-reading.md) 的 Kotlin 执行语义，与 [Source preferences](source-preferences.md) 和[跨语言边界](../design/cross-language-protocol.md)配合。

优先复用已锁定的 `kotlinx-coroutines-core-jvm-1.11.0.jar`，保留官方 `Job`、`Deferred`、结构化并发、取消和 builder 语义，把项目代码缩小到 TeaVM 平台调度、计时、HTTP 取消及 operation 生命周期集成。下一步交付是验证并接入官方核心所需的最小平台适配，不是继续补写一套 `Job` 实现。既有 Source 原业务源码与原始 JAR 保持不变，不为旧宿主增加兼容分支。

## 当前替换范围

[构建流程 `prepareLibraries`](../../tools/teavm/build.ts) 根据自有 Java 源码路径，从依赖的构建副本移除同名 class 及其内部类，再编译自有类；工具链锁定的原始 JAR 不因此被直接修改。当前 `kotlinx.coroutines` 下的自有同名类包括：

| 自有类                                                                                                                          | 当前作用                                                                                                         |
| ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| [`BuildersKt`](../../runtime/teavm/java/src/main/java/kotlinx/coroutines/BuildersKt.java)                                       | `async`、`launch`、`withContext`、`runBlocking` 及部分默认参数入口，转向 `GreenCoroutines`。                     |
| [`CoroutineScopeKt`](../../runtime/teavm/java/src/main/java/kotlinx/coroutines/CoroutineScopeKt.java)                           | scope 构造、`coroutineScope`、上下文查询，以及当前简化的 active/cancellation 查询。                              |
| [`Dispatchers`](../../runtime/teavm/java/src/main/java/kotlinx/coroutines/Dispatchers.java)                                     | Default、IO、Unconfined 共用一个基于有界 operation 任务的 TeaVM cooperative thread dispatcher；Main 明确不支持。 |
| [`internal.StackTraceRecoveryKt`](../../runtime/teavm/java/src/main/java/kotlinx/coroutines/internal/StackTraceRecoveryKt.java) | 异常恢复/unwrap 大多直接返回原异常，不进行官方协程堆栈恢复。                                                     |

[`GreenCoroutines`](../../runtime/teavm/java/src/main/java/prototype/GreenCoroutines.java) 自有 `Scope`、`Waiter` 与实现官方 `Deferred` 接口的 `Task`，承担实际执行和等待。官方 JAR 仍在依赖中，不代表上述路径运行的是官方 builder 或 `Job` 状态机。

[`BrowserCall.Operation`](../../runtime/teavm/java/src/main/java/prototype/BrowserCall.java) 与 [`TeaHost`](../../runtime/teavm/java/src/main/java/prototype/TeaHost.java) 另外负责 entry owner、HTTP/后台工作配额、drain、过期拒绝和回收。它们解决宿主资源归属，不能替代 Kotlin 的父子取消语义；迁移需要保留这些边界。

## 已由代码确认的语义偏差

下列是当前实现与官方合同的直接差异，尚不是本轮新增修复，也不能用已有编译成功掩盖。

| 范围                | 当前实现与影响                                                                                                                                                                                                                                                    | 对照合同                                                                                                                                         |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| 父子 `Job` 与 scope | `Task` 没有把自身放进其上下文，`getParent()` 总为 null、`getChildren()` 为空、`attachChild()` 抛不支持。只有自有 `Scope.children` 列表在 `block` 返回后顺序等待，不能表示官方父子树或及时传播子失败。`CoroutineScopeKt.isActive` 恒 true，`ensureActive` 无操作。 | [Job](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-job/) 定义父子取消、失败传播与完成前等待子任务。 |
| 取消与完成          | `Task.cancel` 直接完成 waiter；运行中的 block 及子任务未因此完成。`isCancelled` 只读显式取消标志，body 失败未设置该标志；completion 回调的 `onCancelling` 参数也未实现。operation lease 仍可等待后台工作，但这与 Job 的 cancelling/completed 状态不同。           | [Job 生命周期](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-job/)区分取消进行中与最终完成。         |
| `join` 与 `await`   | `join` 直接调用返回结果或原异常的 `value()`，与 `await` 共用失败路径。对不受该子任务失败影响的调用方，官方 `join` 等完成而不直接重抛该任务的原失败；调用方自身被取消则另行失败。                                                                                  | [Job.join](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-job/join.html)。                            |
| `withContext`       | 仅合并上下文并调用 `GreenCoroutines.block`，没有官方的目标 dispatcher 切换、返回原上下文调度或及时取消检查。                                                                                                                                                      | [withContext](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/with-context.html)。                      |
| 启动与 dispatcher   | 仅 LAZY 单独处理，其余 `CoroutineStart` 都走同一新任务路径；没有分别实现 ATOMIC 的启动保证与 UNDISPATCHED 的首段立即执行。Default、IO、Unconfined 也没有各自调度语义。                                                                                            | [CoroutineStart](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-coroutine-start/)。                   |

现有 [`EnqueueTest`](../../tools/teavm/EnqueueTest.java) 覆盖 operation drain、过期 LAZY、后台 HTTP、任务配额和启动失败等具体边界。它没有证明上述官方语义等价。普通 `Deferred` 失败仍应允许原 Source 的 `await`/catch 恢复；不能把所有协程失败都升级为整个宿主失败来替代语义修复。

## 上游依据与实测边界

TeaVM 维护者在 [2024 年的讨论](https://groups.google.com/g/teavm/c/ipcePs1mHAc)区分了 TeaVM 的线程/阻塞兼容变换与 Kotlin 语言层的 suspend/Continuation，并展示了 Promise 桥接。该示例说明 suspend 可以独立桥接 JavaScript；它没有实现 `kotlinx.coroutines.Job`、调度、取消或结构化并发，也没有证明锁定的官方核心 JAR 可直接完整运行。该讨论同样不能用于断言所有协程库均不受支持。

固定输入、原五轮及后续定位、JVM / AOT / Node 结果与本机复验命令见[验证记录](../verification/coroutine-runtime.md)。最初 await 停滞已定因为平台把 `parkNanos(0)` 当无限等待；平台窄修与官方可选堆栈恢复配置后，debug 和普通 AOT 的全官方核心均完成真实 suspend、取消清理和 Default 闭环。当前下一步是正式平台回归及 operation owner/lease 集成；不从裸 TeaVM 缺类推断项目缺类，也不将隔离 fixture 通过记为产品迁移或真实 Source 通过。

## 实施顺序与边界

1. **固定官方核心与项目平台基线。** 使用[工具链锁](../../runtime/teavm/toolchain-lock.json)内的官方 1.11.0 核心及现有 Kotlin stdlib，不替换 Source JAR。先按正式构建的 `java/compat`、TeaVM 上下文补丁和依赖适配流程复验，记录实际可达调用链。已存在的兼容类先检查 ABI 和行为，不因为裸 classlib 报缺类就重写同一类。
2. **打通官方核心的首个真实挂起闭环。** 在隔离构建副本中去掉自有 `BuildersKt` / `CoroutineScopeKt` 同名覆盖，保留官方 builder、Job/Deferred 状态机及父子关系。已用真实 fixture 打通最初 await、delay、取消与 Default；将确认的平台修复接入正式检查，并明确 TeaVM 下可选堆栈恢复配置。保持阶段断言，不扩展无实际调用依据的全库兼容。仅为已复现的调度、时钟、类加载或诊断平台缺口提供最小适配；每个覆盖说明所需方法和保留的官方语义。不能用吞异常、空实现、忽略类型检查或恢复自研 `Task` 路径换取 AOT 通过。
3. **收敛宿主调度与入口。** 选择能实际运行官方核心的 cooperative dispatcher / timer；若最外层入口改为 Continuation→Promise，只改宿主 entry 桥，不把语言级桥接宣称成官方 builder 实现。operation owner 必须跨 suspension、delay、恢复和 completion 保持归属，lease 覆盖整段后台工作，不能在一次 dispatcher runnable 结束时提前视为工作完成。保留 generation、HTTP 取消、配额、超时、drain 和过期任务拒绝；GlobalScope 后台工作也不能借用下一 entry。
4. **按语义门替换产品路径。** 先在官方核心 JVM oracle 与固定 TeaVM AOT 上对照，再接回真实 Source 的 browse / filters / preferences / 图片与关闭流程。语义和平台分项通过后删除不再调用的 `GreenCoroutines` 与覆盖类，更新构建输入身份并按既有增量流程本地重建代表扩展。未通过的包仍单独记录，不继续补写通用自研 Job 作为替代路线。

## 有界验收

- [ ] **构建来源：** 原始官方 JAR 哈希与锁一致；实际 AOT 类路径保留官方核心，明确剩余自有替换列表；原始 Source JAR 未变。临时 probe 不成为运行依赖。
- [ ] **真实 suspend 与结构化并发：** 同一 Kotlin fixture 分别在 JVM 与 AOT 执行 `async/await`、`launch/join`、`yield/delay`、父子取消、子失败/兄弟取消和 cleanup；对比事件顺序与最终状态。不能只有 Java 手工调用 Continuation 或 AOT 编译成功。
- [ ] **已知差异闭环：** 独立调用者对失败/取消 Job 的 `join`、LAZY、ATOMIC、UNDISPATCHED、`withContext` 调度与返回时取消、`ensureActive`、completion 回调均有边界断言。仅对本项目支持的 dispatcher 定义平台行为，Main 或其它不支持能力明确失败。
- [ ] **宿主所有权：** delay/HTTP/后台 continuation 未结束时不提前 ACK；取消/超时后回收，旧 owner 的 LAZY 或 completion 不启动新 entry 的 HTTP/任务。跨 entry、配额耗尽和 dispatcher 启动失败不泄漏任务 reservation；不把正常可捕获的 Deferred 失败改成强制宿主失败。
- [ ] **正式 Source：** 固定代表原包经标准 API/控制入口完成浏览和至少一条真实异步业务链；筛选保留/分页、偏好 listener 只调用一次与丢 ACK 恢复、图片释放和 Worker 重开无旧 generation 结果复活。Source 网络失败与宿主语义失败分别记录。
- [ ] **工程与交付：** 按改动通过 `pnpm teavm:check`、相关 TS/Dart 严格检查和正式 harness；本地代表 AOT 重建、工程检查及实际 Web 运行分别列证据，Native 未执行时保留未验收。只有量到实际瓶颈才扩性能优化，不以全上游兼容为本轮验收目标。

阶段结论与余留缺口按本计划维护；详细 probe 源码、编译命令 JSON、日志和生成 JS 留在忽略/临时目录，不进入源码仓库。
