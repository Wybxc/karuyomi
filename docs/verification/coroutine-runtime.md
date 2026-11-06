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
