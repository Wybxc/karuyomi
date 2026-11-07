# 官方 kotlinx.coroutines 验证

2026-11-06，官方核心已接入正式源码，自有 Green Job 与四个 kotlinx 覆盖已删除。正式工程检查和固定 `7e8fe769` AOT 的 BH3 / Komiic Web 分项通过。随后 HTTP 适配固定 `48c4526` 的实际 TeaVM / Node 取消子门、clab 两包重建与正式 harness HTTP smoke 通过；该次真实 Source/UI 受内置浏览器环境阻断而未执行，产品取消、Native 与生产仍独立待验。早期隔离、平台修复、owner 候选和真实 Source 保持分层记录。迁移目标和待办见[协程运行时计划](../plan/coroutine-runtime.md)。以下原五轮是接入前的历史证据。

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

这组结果证明官方核心可以完成真实挂起与取消闭环；尚未证明正式宿主的 operation owner/lease、GlobalScope、旧 LAZY/completion、HTTP、drain、配额或真实 Source。该阶段产品仍使用原自有入口，不能把该轮 fixture 计为已完成迁移、浏览器或 Native 通过；后续接入见下节。

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

## 官方核心与请求归属 v2

后续候选从 `a6dce64273e1165ba2744605227e4d631453bcde` 固定源码建立，正式最小 patch 以已包含平台修复的 `9b10390` 为基准。材料在 `/private/tmp/karuyomi-coroutine-owner-candidate-v2`，v1 保留在无 `-v2` 后缀目录。原始官方 core SHA-256 仍为 `d1d75aa01dffbb4d1c520e67e4c4e7f5f6174718e7cb4632412503f2f0e604fa`，与锁一致。seed 的 host JAR 没有 Green 或四个同名 kotlinx class；不存在删除自有源码后反而暴露 seed 旧覆盖的情况。

冻结 `HostCoroutines.java` 的 SHA-256 为 `f942830213816453bcb4eba072aa805505c6ff69085c924558571b257509c1fc`，生产 `PatchLibraries.java` 为 `f1c8f7698edd0ef5cb727ae226924a1089c954e983da26af546b2d742975e625`。正式接入使用同两份源码，不包含临时 compiler、JAR、stub、HTTP server 或 Node runner。TeaHost 与 SourceImages 三处入口使用官方 runBlocking；TeaHost 静态初始化在 Source 构造前设置官方堆栈恢复开关。

v1 审查确认三项需要修正的边界：过期/超额 LAZY 启动只抛错误、未完成其 waiter；ThreadContextElement 更新路径会向外抛过期错误；普通 `CompletableDeferred` 注册的旧完成回调会借后续请求执行。v2 分别改为官方 Job.cancel 后传播启动拒绝、context element 纯设置/恢复、公开 Function1 注册入口捕获原 owner。未增加全局 Job registry 或另一套取消状态机，未保留冗余的 JobNode.invoke hooks。普通持久 Job 本身不占工作 lease。

| 实际验证                                          | 结果与范围                                                                                                                                                                                            |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 同一真实 Kotlin fixture 的 JVM / TeaVM AOT / Node | 全部 exit 0；AOT 4,262,875 B / 13.40 s。此为机制 fixture 体积，不是代表 Source 包体或性能对照。                                                                                                       |
| 七组官方语义                                      | 取消中与 finally 后完成分离；父失败与兄弟取消；正常 LAZY；DEFAULT / ATOMIC / UNDISPATCHED 首段；ensureActive；withContext 调度/返回取消；失败 Job 的独立 join，均通过。                               |
| 请求归属和 lease                                  | GlobalScope 排队前保留配额；delay/await 恢复原 owner；Deferred 原 IOException 可捕获；未处理 launch 失败交给原 context handler；HTTP / 后续 finally / 完成链结束前 drain 不返回，均通过。             |
| 限额与失败清理                                    | 64 项配额、取消排队清理、dispatcher 拒绝；超额/过期 LAZY 被取消且 await 完成，旧 body 不运行，均通过。                                                                                                |
| 跨请求复用                                        | A 创建的持久 scope 在 B 新建工作归 B；A 的旧任务及已完成任务的 immediate callback 不借 B；generic CompletableDeferred 旧回调拒绝、新 B 回调仍执行且不泄漏 lease，均通过。                             |
| 独立 ThreadContext oracle                         | 复制冻结源码和原始官方 core，运行真实生产补丁器；经官方 ThreadContextKt 多 element 更新/恢复，过期 owner 不抛、仍禁止旧请求工作，B 与另一 ThreadLocal marker 恢复。独立 generic/context 两项 exit 0。 |
| 有界 HTTP supplier                                | JVM 和 Node 各 1 次回环请求，Node 最后 handles=0；不是 workerd、正式 harness 或真实 Source 验收，未覆盖 child Job.cancel 到 Call.cancel。                                                             |

v2 故意给已关闭请求的旧 LAZY 注册完成回调，官方通过 CompletionHandlerException 报告原 owner fence 拒绝；fixture 仍验证旧回调/body 均未执行、waiter 已取消完成、下一 owner 恢复。该诊断不作为无关日志忽略，也不通过修改核心吞异常。后续正式 JVM oracle 显式检查其异常通道。

详细输入、编译 argv、结果与清理保存在上述目录 `RESULTS-v2.md`、`results-v2.json`、`fixture/*-command.json`、`aot-v2.log`、`fixture/jvm-v2.log`、`node-v2.log`。独立审查的两份输入摘要和运行结果在 `/private/tmp/karuyomi-owner-review/provenance.json` 与 `result.log`。候选自启 JVM、Node 和 HTTP 进程均已退出。

### 正式回归接线

`pnpm teavm:check` 从锁定原 core 新建副本，并用生产 PatchLibraries 处理；清除旧 image oracle 类目录，编译当前 HostCoroutines，再执行全部原有 Enqueue 场景。运行时检查 BuildersKt、CoroutineScopeKt、Dispatchers、JobSupport 的实际 code source 是该官方副本，并拒绝任何可达 GreenCoroutines。单个 javac/java 子进程有 30 秒期限，避免挂起占住后续检查。

旧测试中“运行中的 cancel 立即 completed”改为官方合同：cancelled 为真，body/finally 未结束前 completed 为假，结束后才 completed。过期 LAZY 的启动错误仍需 owner-expired cause，后续 await 则验证官方 CancellationException 精确引用同一启动拒绝原因。保留原场景与失败门，不在 fixture 手动 cancel 掩盖宿主缺陷。

正式 `pnpm teavm:check` 已 exit 0：Enqueue 85 项断言通过（原 81 项保留，新增 4 项显式 completion 异常通道断言），8355 项图片/处理后正文合同在 seed 与 owned HttpSource 各通过；DTO、filters、preferences、HTTP body、缓存、文件、网络和两项平台 oracle 同时通过。`pnpm check` 全部 exit 0，包含 418 项 Vitest 集成测试、协议生成一致性、严格类型、依赖层级和工具测试；全库 `pnpm format` 与完整 `pnpm format:check` 通过。没有改动 Dart 产品代码，未将之前的 Flutter 检查重复计成本轮执行。详细日志留在 `/private/tmp/karuyomi-official-core-*.log`。

提交 `7e8fe769e0761581e065a71957efebd9011b0a32` 的[远端 CI](https://github.com/Wybxc/karuyomi/actions/runs/42167429386)全部通过，包含通用检查、Flutter 回归、完整构建和 D1 迁移。这是该提交的工程证据，真实 Source 见下节。

## 固定官方核心提交的真实 Web 分项

从上述 `7e8fe769` 建立独立目录 `/private/tmp/karuyomi-official-core-7e8fe769`，三份 submodule 与锁定工具链不变，使用正式 Gradle / TeaVM builder 重新构建 Komiic 1.6.11 和 BH3 1.6.1，未复用旧 AOT。原 Source JAR 和官方核心未修改；可变依赖缓存隔离。官方编译、AOT、完整性校验、`prepare-snapshot` 与正式 `acceptance:build` 均通过。首次 sandbox 下 Dart `cpuinfo_macos` SIGABRT 日志保留，同一输入在正常授权环境重跑通过。

| 扩展          | buildId                                          | canonical SHA-256                                                  | gzip / canonical 字节 |
| ------------- | ------------------------------------------------ | ------------------------------------------------------------------ | --------------------- |
| Komiic 1.6.11 | `ext-zh.komiic-974d4455d8168db478d2a45de3ce4400` | `e176efb7aab7f444829755f5441c19df15a318a03e130dad9b3d087ba50dec0b` | 566264 / 1828872      |
| BH3 1.6.1     | `ext-zh.bh3-185eabe825de16f9f651ccb68e46ad54`    | `a14b815ab13e97be669f41f7d8122f5d203403520dd86ca445aebc0d122f1778` | 882337 / 4290269      |

host 输入指纹为 `3d8c568877dd274c1f2e39ab922ce7bf77ab5e49e2cd5e0e9d9892d34d467031`，原包上游为 `efa93f5a3537856fe830450bbe33f69d21d28167`。Komiic 原 JAR SHA-256 为 `123ac3074dc02c3b65253dbbf097653c403a303a9220918e6b651e9425e8cf6d`，BH3 为 `7970b15879757f6e548f45a43c9eaa44f75f5f2ade223056317a64425c16f3f3`；Komiic 与前轮同版本原 JAR 字节不同，因此这里只记录当前体积，不能作 core-only A/B 或包体优化结论。

候选 revision 为 `534881ae689743e08fbbc300249fb6e9`，2 包 available、1446 包 pending，`bootstrap.complete=false`。host ABI 仍为 v6、控制和 HTTP bridge 仍为 2。未部署、未写发布 checkpoint，也未自动提升 `compiled_unverified/runtimeReady=false`。

通过官方 Wrangler `createTestHarness` 启动隔离 D1 / 真实 RS256 测试身份，使用正式 Flutter 主入口和 Codex 内置 Chromium，经正式控制与 HTTP 桥操作。复验入口：

```sh
cd /private/tmp/karuyomi-official-core-7e8fe769
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.zh.komiic","allowedHosts":["komiic.com","komiic.cc"]},{"packageName":"eu.kanade.tachiyomi.extension.zh.bh3","allowedHosts":["comic.bh3.com","act-webstatic.mihoyo.com"]}]' pnpm acceptance:serve
```

上述图片 host 来自 [BH3 官方页面](https://comic.bh3.com/book) 的实际封面链接。没有修改 Source、注入原图捷径或使用模拟供应器替代在线行为。

1. BH3 初始化、热门及“逃离长空篇”详情成功，返回 7 章。原 `BH3.fetchMangaUpdate` 使用 `coroutineScope`、两个 `async` 和两次 `await`。当前 TeaHost 的 details / chapters 调用传入互斥的 fetch 标志，其中一个分支直接返回；这证明真实 Source 协程业务运行，不表示一次两路 HTTP 并发已验。
2. 打开“第六话 新的旅程”，正式 Reader 显示真实漫画图像，21 页；翻页后自动双页显示 2 / 3，界面确认“阅读进度已保存到服务端，最远：第 3 页”。详情封面仍为占位图，本轮不登记封面通过。
3. 退出阅读、返回浏览并切换 Komiic，后续 Source 正常工作。只登记可见交互结果；没有直接量 Java/TS handle 数量，不据此声称完整取消竞争或 handles=0。
4. Komiic 默认 `.com` 热门仍失败；通过原镜像设置改为 `.cc`，界面确认设置，Source 重开后热门成功。重新打开原设置可见 `komiic.cc`。
5. 原动态分类树返回，选择“搞笑”并应用后显示“筛选（已应用）”，出现雅尼貓、敗犬女主太多了等新结果；“加载更多”追加被俘者的嘆息等条目。重新打开筛选，“搞笑”仍已选，关闭编辑后原查询保持。这里是可见分页与保留证据，未抓取上游 GraphQL 变量。

本轮限测试身份的 Web 分项，不覆盖 preference veto / 回调次数 / 丢 ACK、单个 Job 到 HTTP 的取消、迟到竞争、Native、生产 Access 或真机。正式验收服务已正常退出，61010 端口拒绝连接，所有本轮构建器已结束。详细固定输入、原 provenance 和构建日志在独立目录 `.local/official-core-harness/summary.json` 及同目录日志；截图为 `/private/tmp/karuyomi-official-core-bh3-reading.jpg`、`/private/tmp/karuyomi-official-core-komiic-filter.jpg`。这些临时产物不提交源码库。

## 复用上游 HTTP suspend adapter

后续候选从固定 `7e8fe769` 建立于 `/private/tmp/karuyomi-http-coroutines-candidate`。实际 seed 字节码的 await 已使用 CancellableContinuation、`invokeOnCancellation(Call.cancel)` 与 enqueue，awaitSuccess 保留上游 Kotlin 状态机；实际 seed 不含当前 vendor Kotlin 的堆栈切片代码，不能混同两份输入。项目删除阻塞 execute 的同名覆盖，直接复用依赖实现，没有新写 continuation。

seed 的 newCachelessCallWithProgress 仅 newCall，仍需项目图片集成；补丁器只按精确 owner / 名称 / descriptor 接管这一个方法，委托 BrowserCall，保留原 cacheless / progress。SeedAdapterIdentity 用 ASM 排除该方法及非语义 debug / frame 后比较原始与副本，确认 5 个 await / continuation class 不变；原 JAR 不修改。

原 BrowserCall 在 onResponse 返回后立即关闭正文，恢复到其它 dispatcher 的消费者可能读到已关闭资源。现在按 OkHttp 所有权交付，独立跟踪最多 64 份未关闭响应，与回调 / 工作 lease 分开；这是 Java 资源限额，正式二进制 HTTP 仍限 4 并发。最终正文 close 在 finally 关闭该 Call 遗留 transport handle，即使 interceptor 换 body 也回收；实际释放后才删除登记，已关闭响应不累计占额。

成功 drain 等待工作与回调后，锁外关闭遗留响应；另一线程正在 close 时，沿同一个原总 deadline 等待真实 release。清理异常阻止成功 ACK，并继续清理其它响应。超时后 hasPending 保留未清资源，TeaHost 要求回收 Worker。清理 set / restore 原 owner，不能借新请求启动 HTTP。Java 不能抢占任意同步 body.close，外层 Source / Worker deadline 仍是最终边界。

冻结候选实际 JVM 结果：

- Java HttpAwaitTest 202 / 202：真实 seed await / 官方 Deferred，延迟消费、交付前后取消及 finally、IOException / 非 2xx、换 body、连续 70 次关闭、64 / 65 限额与释放复用、ACK 前清理及异常、确定性等待态、25 ms 清理超时保留 pending、原 owner 上下文均通过。
- 额外真实 Kotlin suspend fixture 168 / 168，原 Enqueue 85 / 85，两路 seed / owned HttpSource 图片各 8355 / 8355；各 JVM exit 0、stderr 空、无超时。正式回归内化 Java fixture，不搬入临时 K2 compiler 或整套探针。
- 8 个原调用边界、5 个精确 cacheless 正负例、官方 Worker 继承调用、seed suspend 保留、网络配置和两个 TS 入口严格类型均通过。
- 两个负向版本确定失败：换回原 BrowserCall 在第 7 断言发现 callback 提早关闭；移除 drain 等待也被确定性事件门拒绝。

冻结摘要见候选目录 integration/frozen-sha256.json，实际结果 final-run.log，负向日志在 red/；候选进程已退出。本节仅证明隔离 JVM，尚非本次 HTTP 变更后的 TeaVM AOT、正式 Source、Native 或生产取消验收，前一节 7e8 结果不能自动覆盖新适配。

正式接入后，主仓库完整 `pnpm teavm:check` exit 0，实际执行上述 Java 202、Enqueue 85、seed suspend 保留、两路图片各 8355，以及全部现有 DTO / filters / preferences / HTTP / cache / file / network / platform oracle。`pnpm check` exit 0，418 项 Vitest、跨语言 golden、生成一致性、严格类型、依赖层级和工具回归均通过；全库 `pnpm format` 与完整 `pnpm format:check` 通过。本轮未改 Dart 产品代码，未重复本地 Flutter 全套。详细日志留在 `/private/tmp/karuyomi-http-upstream-*.log`。

## 固定 48c HTTP AOT 与 Node 取消子门

2026-11-06，从 HTTP 适配正式提交 `48c452668ed4d91b9983af1ca4e0679351aec9e1` 的独立 `git archive` 建立 `/private/tmp/karuyomi-http-coroutines-aot-48c4526`，固定 TeaVM gitlink 和锁定 seed；`prepareSources` 核对供体输入/输出摘要，实际 work 中 123 份生产 Java/compat 源码逐字节匹配。`Bridge`、`BrowserCall`、官方核心 owner 适配和 `PatchLibraries` 未改。原始 seed 保留，生产编译器仅处理构建副本，seed await / awaitSuccess 及内部类继续通过精确身份 oracle。

临时 Kotlin fixture 仅提供 main 与检查信号，不提供 Source 实现；使用已有临时 Kotlin 2.4.10 compiler，不新增项目依赖。正式 `prepareSources` / `compileExtension` 与 TeaVM 0.16.0 编译成功，debug JS 为 3,674,816 B，耗时 13.663 秒，摘要 `14a42d9e153424bfc2babcf3296469a7b57fe3f88ce7d11f6d8e659debb55bcf`。这些是机制 fixture 数据，不是扩展包体或性能对照。

Node 24.15.0 实际执行生产 AOT，通过四条受控 HTTP 路径：

1. callback 返回后协程才恢复，正文继续存活；经正式 Bridge 异步读取 13 B 后到 EOF。
2. 响应已交付但未消费时取消 Job，原 `Call.cancel` 和 Kotlin finally 各执行一次，未读正文的 handle 关闭。
3. 对真实 localhost fetch 等待响应头时取消 Job，执行原取消/finally，fetch 被 abort，并在成功收尾前观察到服务端连接关闭。
4. seed `awaitSuccess` 对 HTTP 404 抛出 `HttpException`，关闭未消费正文。

协程 body/finally/callback 的原 owner，以及四条请求的 requestId/generation/token 组合均核对通过。每路径恰好一次 GET、一次 handle 释放，取消及非 2xx 正文均零读取。supplier 有 4 handle / 64KiB metadata 与正文预算，但实际仅单请求顺序执行，不能据此登记 64 响应资源限额或并发压力通过。

**退出限定：** 首轮业务标记与 supplier 断言全部完成，但子进程未自然退出，20 秒外部 watchdog 失败。保留原 `node-first-*`。第二轮只修改临时 runner 收尾：确认 supplier 清理、记录公开 active-resource 诊断和结果、flush 输出后显式退出子进程，对应机制 Worker dispose；未改 AOT 或生产输入。最终外部 runner exit 0、无 watchdog 超时，总用时约 196ms，不能作为自然 event loop idle 或执行性能证据。

最终 supplier 自有 handles/sockets/timers 为零、监听已关闭，但 Node 诊断仍有包括 `Timeout` 的异步资源，其精确归属尚未独立审计。外部 watchdog 仍约束 AOT main 和收尾；临时构建/fixture/supplier 进程均已结束。此门证明生产 Java/seed await/官方 core/TeaVM/Node 的 HTTP 取消与正文所有权子链，不能替代官方 workerd harness、浏览器 UI、真实 Source、Native、旧代竞争或完整阅读取消。

临时材料尚在且工具链已准备时，可在该目录复验；清理后须按上述固定输入重建，不将临时 runner 当正式项目入口：

```sh
cd /private/tmp/karuyomi-http-coroutines-aot-48c4526
node run-build-watchdog.ts
node run-node-watchdog.ts work/public/teavm/httpcoroutineprobe/app.js
```

详细输入、原失败及最终结果保留在该目录 `RESULTS.md`、`inputs.json`、`production-source-identity.json`、`node-watchdog-result.json` 与日志，不复制入源码仓库。使用仓库锁定 Node，并沿正式工具链设置 `JAVA_HOME`。

## 固定 48c clab 后台重建与正式 harness

同一正式提交在 `fedora@clab` 后台独立目录 `/home/fedora/karuyomi-builds/http-adapter-48c4526-20261106-0718` 完成两包原 Source Gradle → TeaVM → 完整性校验 → `prepare-snapshot`。固定 extensions 上游 `efa93f5a3537856fe830450bbe33f69d21d28167`、suwayomi `6b481e8b62938b9c060eb210b934e0fbfdfa466b`、TeaVM `e87d452e4bd70c77b9e19314a46c3d6971c148b6`；Linux x86_64、Node 24.15.0、pnpm 12.6.0、Temurin JDK 25.0.5+8。官方扩展源码与原 JAR 未改，tracked 输入在完成后仍干净。

| 扩展          | buildId                                          | canonical SHA-256                                                  | gzip / canonical 字节 |
| ------------- | ------------------------------------------------ | ------------------------------------------------------------------ | --------------------- |
| BH3 1.6.1     | `ext-zh.bh3-f8487a7957847a8aa607f868ceeb9b74`    | `cab61200d5363fa9ae7765e54c67593d4fa0806b80b53bf5aacca79637e990e9` | 886398 / 4321383      |
| Komiic 1.6.11 | `ext-zh.komiic-dd3c0806d5ab43cc523334af1602dc12` | `0d9e12bfe655386e00f86373f04fee60543e1c8897f3ac8dc413db9c1b62b831` | 573795 / 1865562      |

hostFingerprint 为 `802fd45ac7d381c1ca58a62a2b66d4a2eb18b03c66db611737f41ba9b6f1ad27`，候选 revision 为 `f1f8608129dc46d7be53ff58cc7c4a81`，2 available / 0 failed / 1446 pending，`bootstrap.complete=false`。两包均保持 `compiled_unverified/runtimeReady=false`，不因编译或下述 HTTP 200 提升。没有部署或写正式 checkpoint；远端 controller、timeout 和构建任务均结束。取回的结果在 `/private/tmp/karuyomi-clab-http-48c4526/remote-results/`，传输归档已校验；详细 summary/日志留在忽略的临时目录。

独立主树 clone `/private/tmp/karuyomi-http-48c4526-harness` 固定相同提交与 submodules，使用本机固定工具链及 frozen 离线依赖，tracked clean。正式 `acceptance:build` 通过，包含 Flutter Web、运行时/Native 材料及官方 Worker/harness；静态装配 60 文件 / 2 当前扩展。**该候选 manifest/index 尚无后续 `sources` 元数据字段，只由固定 48c 产品读取，不补字段冒充当前目录/扩展管理功能产物。**

在该 clone 中复验静态构建与官方 harness（先按项目要求设置 `JAVA_HOME`、`FLUTTER_ROOT` 和固定 Node PATH）：

```sh
pnpm install --offline --frozen-lockfile
EXTENSION_ASSETS_DIR=/private/tmp/karuyomi-clab-http-48c4526/remote-results/results/snapshot pnpm acceptance:build
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.zh.komiic","allowedHosts":["komiic.com","komiic.cc"]},{"packageName":"eu.kanade.tachiyomi.extension.zh.bh3","allowedHosts":["comic.bh3.com","act-webstatic.mihoyo.com"]}]' pnpm acceptance:serve
```

官方 `createTestHarness` 应用正式迁移并登记两包显式网络政策，隔离 D1 和 RS256 测试身份 `acceptance-owner` 下，真实 loopback GET `/`、`/api/bootstrap`、`/extensions/index.json` 均 HTTP 200，index 返回精确两包。这不是生产 Access 或 Source 执行证据。

**浏览器未执行：** CUA inventory 无可用 browser，创建 IAB 标签返回 `Browser is not available: iab`，子任务与主任务的 `open_in_codex` 均仅 queued。未操作 Safari/其它浏览器，没有真实页面截图；BH3 详情/阅读、Komiic 设置重开/筛选分页、实际 UI 取消和资源收尾均未执行。这是环境阻断，不登记产品失败，也不沿用前轮 `7e8fe769` 的 Web 通过结果覆盖本次 HTTP 改动。

官方 harness 收到 Enter 后正常 exit 0，finally 关闭服务；本 clone / 原端口无残留进程，SDK 锁释放。详细 `RESULTS.md`、`candidate-summary.json`、`http-smoke.json` 与 build/serve 日志留在临时目录。后续继续实际 Web 产品取消及 Source、Native、生产与真机门；本轮 AOT 和工程 HTTP 子门不缩减这些待办。

## 非 IO 执行失败的异步终态修复

2026-11-07，Source 重开诊断期间发现 `BrowserCall.enqueue` 只将 `executeOwned` 的 `IOException` 交给 `onFailure`；拦截器或运行时抛出 `RuntimeException` / `Error` 时，owner 虽记录失败，真实 seed await 的 continuation 仍可能等待。修复按 OkHttp 的异步失败语义取消调用，并在 owner 仍有效时交付一次带原 cause 的 `IOException`；owner 保留原异常，回调和清理的次生异常作为 suppressed 保留。`onResponse` 或 callback 自身抛错不再次触发 `onFailure`，过期 owner 仍拒绝迟到交付。

正式 `HttpAwaitTest` 新增真实 seed `await` / `awaitSuccess`、直接 enqueue、非 IO 执行错误和 response / failure callback 抛错回归，验证一次终态、原 cause、owner drain 与资源释放。同一 fixture 使用旧 BrowserCall 在 3 秒等待门失败，修复后 HttpAwaitTest 270、EnqueueTest 85、ImageTest 8355 项断言通过；隔离输出在 `/private/tmp/karuyomi-enqueue-failure-XCrmCZ`。正式复验入口仍为 `pnpm teavm:check`。

这些是 JVM 红绿证据；当时真实 TeaVM 候选、Source 重开和独立客户端书签门仍未通过，不能以本修复替代[重开诊断](source-reopen.md)的后续实测。
