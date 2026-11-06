# 官方 kotlinx.coroutines 隔离验证

2026-11-06，验证能否以官方核心替换当前自有协程入口；迁移目标和验收维护在[协程运行时计划](../plan/coroutine-runtime.md)。本轮未修改正式运行时，未发布扩展。

## 固定输入与隔离范围

2026-11-06 的实验材料位于本机 `/private/tmp/karuyomi-official-coroutines-probe`，源码、日志和生成 JS 均不入库。运行材料使用锁定的 coroutines core 1.11.0 与 Kotlin stdlib 2.4.21，SHA-256 与[工具链锁](../../runtime/teavm/toolchain-lock.json)一致；Kotlin fixture 由扩展工具链的 compiler 2.4.10 编译，其 SHA-256 为 `9309638a2ee03e6bde9ef4b7444055a94b84ab906563675d71ff9aecb64da913`。AOT 使用 Maven 3.9.11、JDK 25.0.5+8、TeaVM 0.16.0。

正式平台变体从提交 `d2a8184e939db4fb7c9a0d73e3f69f4a1ff0fce0` 的 `git archive` 建立隔离副本，通过项目 `prepareSources` / `compileExtension` 使用正式 `java/compat` 与 `PatchLibraries`。它们移除 `GreenCoroutines`、`SourceImages` 和自有 kotlinx 覆盖，入口改为真实 Kotlin `probe.ProbeKt`；`TeaHost` 仅保留无用字段 stub。实验没有修改主仓库或官方 Source JAR，也不是正式 Source 或浏览器验收。每个变体的 `inputs.json`、`run.ts` 记录其输入与差异。

## JVM、AOT 与 JS 结果

JVM 上原始与阶段 fixture 均执行通过；阶段版 `staged/jvm.log` 包含 `async/await`、`launch/join`、`yield/delay`、`cancelAndJoin` / `finally` 和 `withContext(Dispatchers.Default)=42`。这些是 JVM oracle，不代表 TeaVM 已通过相同语义。

| 隔离变体                                 | AOT 结果                                                                                                                                                                              | JS 结果与适用边界                                                                                                                                                  |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 裸 TeaVM + 完全官方核心                  | 失败：缺 `LockSupport`、`AtomicReferenceArray`、`ReentrantReadWriteLock` / ReadLock / WriteLock、`RejectedExecutionException`、部分 `ClassLoader` / `Thread` API。                    | 未运行；仅证明未加载项目兼容层的 classlib 不足。日志 `aot-default.log`。                                                                                           |
| 裸 TeaVM + 仅小 `Dispatchers` 替换       | 失败：`BlockingCoroutine.joinBlocking`、事件循环、堆栈恢复和 `DefaultExecutor` 仍触达上述平台 API。                                                                                   | 未运行；不能据此推论项目兼容层下只换 dispatcher 也不可行。日志 `aot-dispatcher-only.log`。                                                                         |
| 正式项目兼容层 + 完全官方核心            | 先前缺类已解决；仅剩 `CoroutineScheduler$Worker.setContextClassLoader(ClassLoader)` 缺方法。                                                                                          | 未运行；现补丁只匹配 `java/lang/Thread` 调用 owner，遗漏继承调用 owner。日志 `aot-project-compat.log`。                                                            |
| 正式项目兼容层 + 仅小 `Dispatchers` 替换 | 阶段版编译成功，1,015,845 B / 16.98 s；保留官方 Builders / Scope / Job / Deferred。                                                                                                   | 同步入口完成，首个 `await` 未返回，5 s watchdog 退出码 2。日志 `aot-project-compat-dispatcher-staged.log`、`node-project-compat-dispatcher-staged.log`。           |
| 正式项目兼容层 + 精确继承 owner 窄修     | 阶段版编译成功，1,666,796 B / 13.88 s；保留完全官方 Default / Builders / Scope / Job / Deferred。窄修仅在临时副本匹配 Thread 或 Worker 的 `setContextClassLoader(ClassLoader)` 调用。 | 同步入口完成，首个 `await` 未返回，5 s watchdog 退出码 2。日志 `aot-project-compat-inherited-owner-staged.log`、`node-project-compat-inherited-owner-staged.log`。 |

主仓库已有 [`LockSupport`](../../runtime/teavm/java/compat/java/util/concurrent/locks/LockSupport.java)、[`ReentrantReadWriteLock`](../../runtime/teavm/java/compat/java/util/concurrent/locks/ReentrantReadWriteLock.java)、[`AtomicReferenceArray`](../../runtime/teavm/java/compat/java/util/concurrent/atomic/AtomicReferenceArray.java) 和 [`RejectedExecutionException`](../../runtime/teavm/java/compat/java/util/concurrent/RejectedExecutionException.java) 等适配。前两轮的裸 classlib 缺口不能写成项目缺类；第三轮与后两轮也表明官方核心可以跨过 AOT 编译门槛。

后两轮 Node 输出均到 `STAGE_SYNC_DONE`、`STAGE_ASYNC_CREATED`、`STAGE_LAUNCH_CREATED`，但没有进入 async 或 launch 子 body，停在首次 `result.await()`。同步 `runBlocking` 已完成；`yield/delay`、取消 / finally 及尾部 Default 阶段均未到达，不能计为通过。现有证据将下一步收敛到子任务入队、事件循环恢复与首次挂起等待，尚不足以判定唯一根因，也不能据 AOT 成功替换产品路径。两组包大小只是不同隔离构建的结果，不是性能或优化对照结论。

## 首次挂起根因与后续闭环

在原五轮之后，新隔离变体保留同一固定平台输入和全部官方核心，以生成 JS 的有界 trace 定位首次挂起：async/launch 已进入 BlockingEventLoop 队列；父 block 返回挂起后 `processNextEvent` 返回 0，官方 `runBlocking` 调用 `LockSupport.parkNanos(0)`。项目兼容层误将其转为 `Thread.wait(0)`，导致无限等待、队列不再前进。

[JDK 官方合同](<https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/concurrent/locks/LockSupport.html#parkNanos(long)>)规定非正等待时间无操作，且不消费已有 permit；`park()` 则另行等待。候选平台窄修区分两者，保留原 monitor/permit 路径，并保留上轮精确的 `CoroutineScheduler$Worker.setContextClassLoader(ClassLoader)` 继承调用适配。

修正后真实 async/await、launch/join、yield/delay 均运行，取消阶段暴露另一个独立的诊断平台问题：官方堆栈恢复初始化读取 `new Exception().stackTrace[0]`；该 Node 环境没有 TeaVM `$rt_decodeStack`，空栈产生读取 `$fileName` 的 TypeError。原 CoroutinesInternalError 和 JS stack 保留，未吞异常。只在隔离 fixture 入口使用官方配置 `kotlinx.coroutines.stacktrace.recovery=false` 后，全官方核心完整通过；该配置仅关闭可选协程诊断堆栈重建，不改 Job、取消或异常传播。

| 隔离验证                                      | 实际结果                                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------------------------- |
| 平台窄修、保留官方堆栈恢复                    | 通过原 await 停点；取消阶段发生上述诊断 TypeError，watchdog exit 2                        |
| 平台窄修、官方关闭堆栈恢复配置、debug AOT     | JVM/Node 完整 staged 通过，Node exit 0                                                    |
| 平台窄修、未关闭恢复、普通 minified AOT       | 仍在取消阶段发生同一诊断错误，不能归因于仅 debug 探针                                     |
| 平台窄修、官方关闭恢复配置、普通 minified AOT | Node 完整 staged 通过，exit 0                                                             |
| LockSupport 边界 fixture                      | JVM 与正式 TeaVM AOT/Node 通过非正值、预 permit、unpark、正等待超时与 interrupt flag 分项 |

完整 staged 包括同步 `runBlocking`、`async/await=21`、`launch/join`、`yield/delay`、`cancelAndJoin/finally` 和 `withContext(Dispatchers.Default)=42`。固定 TeaVM 的 `TClass.desiredAssertionStatus()` 恒 true；本项目 debug 配置只控制 sourceMaps/minifying，普通产物同样须正确处理可选堆栈恢复。LockSupport 边界覆盖 0、-1、MIN_VALUE 及 blocker overload、非正值保留 permit、MAX_VALUE 正等待消费已有 permit、`park(Object)` 等待另一线程 unpark、正等待和中断标志，不宣称穷尽所有竞争或 spurious return。

详细固定输入、候选 patch、命令和产物摘要位于 `/private/tmp/karuyomi-official-coroutines-probe/diagnostic-eventloop/RESULTS.md` 与 `results.json`，原失败日志均保留。该轮所有自启构建和 Node 已结束。平台修复的正式落盘与工程检查另按当前提交记录，隔离官方配置尚未接入产品入口。

正式平台修复的回归已接入 `pnpm teavm:check`：

- `LockSupportContract` 在未修改 JDK 与仅 `--patch-module` 当前自有 LockSupport 的两个 JVM 上执行同一 17 项行为合同并比较结果。原兼容层的非正值调用先在有界 join 内失败，修复后通过；没有以源字符串比较代替执行。
- `PatchLibrariesTest` 对合成调用 JAR 和锁定官方核心的临时副本运行真实生产补丁器。8 项 owner/方法/签名边界、实际 Worker 继承调用、非 class 资源保留与原核心未变检查通过。它检查转换字节码，完整官方协程的运行证据仍以上面的独立 AOT fixture 为准。
- 完整 `pnpm teavm:check`、`pnpm typecheck:tools` 与 `pnpm check:dependencies` 通过。新入口仅依赖 TeaVM 领域模块；JDK 优先使用明确 `JAVA_HOME`，否则按现有工具链锁的平台 home 选择。检查不修改原 JAR，临时目录 finally 清理，线程和子进程均有界。

该检查入口的完整字节码部分需要本地锁定 seed 和已有 ASM 依赖，未因此扩大公开 CI 的下载或伪称普通 CI 已执行私有工具链 oracle。原失败、检查结果和详细日志留在 `/private/tmp/karuyomi-platform-*.log` 及对应忽略目录。

这组结果证明官方核心可以完成真实挂起与取消闭环；尚未证明正式宿主的 operation owner/lease、GlobalScope、旧 LAZY/completion、HTTP、drain、配额或真实 Source。产品仍使用原自有入口，不能把本轮 fixture 计为已完成迁移、浏览器或 Native 通过。

## 本机复验入口

在临时材料仍存在、项目工具链已准备的前提下，以下命令分别复验 JVM、正式兼容层阶段 AOT 和 Node 执行。`kotlin-command.json` 保留 Kotlin 编译的完整 argv；裸 TeaVM 的 Maven 入口与其独立 `pom.xml` 也保留在该目录。临时目录清理后需按上述固定输入重建，不能把这些路径当作项目正式构建入口。

```sh
cd /private/tmp/karuyomi-official-coroutines-probe/staged
java -cp 'classes:../libs/*' probe.ProbeKt

cd /private/tmp/karuyomi-official-coroutines-probe
node project-compat-inherited-owner-staged/run.ts
node run-node.cjs project-compat-inherited-owner-staged/work/public/teavm/coroutinesprobe/app.js
```

上述 AOT 命令需使用仓库锁定的 Node，并设置与正式 TeaVM 构建一致的 `JAVA_HOME`；`run.ts` 通过固定 Maven 路径和 `TEAVM_DEBUG=1` 调用正式构建。Node runner 为主入口回调设置 5 秒 watchdog，超时只表示该环境在限时内未完成，不等于已测得浏览器行为。
