# HTTP Cache 运行证据

2026-11-04。正文分块、Cache 生命周期、namespace 总预算与共享 Java 场景已通过以下门；同一 namespace 的 Cache/files 组合压力、正式 Source、生产 Access 和 Native Cache 仍须分别验收。普通文件分层机制见[文件运行证据](file-storage-runtime.md)，固定分区合同见[Cache 存储设计](../design/runtime-cache-storage.md)。不能把本记录作为整个存储或阅读能力完成的证明。

## 正式维护入口

- `runtime/teavm/bridge/cache-bridge.ts`：直接使用 `idb@8.0.4` 的 typed schema、原子 metadata/body 指针和二进制 chunks。
- `runtime/teavm/java/src/main/java/okhttp3/Cache.java`、`prototype/CacheSink.java` 与 `prototype/Bridge.java`：原 CacheInterceptor 的 Java 集成、存储写失败隔离，以及每次不超过 65536 字节的实际 JSO 读写。
- `packages/runtime-host/test/cache-lifecycle-browser-suite.ts`、`cache-lifecycle-worker.ts`：正式产品桥的真实 Worker/IDB/Web Locks 回归。
- `tools/teavm/check-cache-storage.ts`：从干净检出编译产品桥与上述测试，提供仅 loopback 的浏览器入口；无需 JVM seed、私有凭据或 Source 网络。
- `tools/teavm/CacheScenarios.java`：两端完全相同的 Java 场景；`CacheTest.java` 提供原 JVM origin 与 CodeSource 断言；`CacheSinkTest.java` 提供 19 项 JVM 写入终态检查。JVM 两项已接入 `pnpm teavm:check`。

## 浏览器机制门

Codex 内置浏览器 Chromium 156 当前通过 **39 组**。其中原 27 组保留活 owner/CAS/clear generation、terminate 后首次 begin 回收、close/delete 在途 begin fence、真实提交失败后的独立 CAS 清理、不可变 reader snapshot、分块和 allocated 预算、metadata 操作不读正文、Java handle 隔离。可见预算无法在活 editor 竞争下满足时，commit/update 原子拒绝；close/delete 的真实 IDB `ConstraintError` 后，关闭 handle 的 editor 被清理，原错误、旧完整条目、reader、sibling 和其他 owner 均保持预期。

前一分项的十组覆盖 reader 所属 Worker 死亡后的回收与活兄弟 pin、六类实际 IDB chunk 损坏（缺失、空、超过 64 KiB、首块截短、末块截短、末块超长但不超过 64 KiB）、读完部分正文后的显式 reader-close、读事务真实 abort，以及 reader-close 失败的独立清理。损坏可以先返回有效前缀，但最终必须报存储错误，不能返回成功 EOF 或隐式网络重试。错误 reader 关闭后，修复测试损坏块的活兄弟仍能读到完整原字节；最后 pin 释放才回收 retired body 计费。

本轮修复了 reader-close 事务 abort 后的活 owner 泄漏：Java 已标记 snapshot 释放，不会再次 close，原实现会把失败事务回滚的 pin 长期保留。现在等待原事务终态，再以 readerId、worker、Java handle、directory 验证独立清理，只释放该 snapshot；原始错误仍报告，清理也失败则聚合两个错误。真实 ConstraintError 回归同时验证错 handle、外来 owner 与活兄弟 reader 不被误清理。

故障注入只在测试 driver：通过真正的重复主键请求触发浏览器事务 abort、直接改写测试 chunk 记录，或控制 Web Locks 探测的等待顺序。没有替代浏览器事务或锁。单次恢复时间不构成性能分布。这里没有验证 body metadata 或 pin 计数记录本身损坏后的恢复。

## Namespace 固定分区门

当前 `teavm-http-cache-v3` 将全部目录纳入同一个增量 usage 账本：allocated 128 MiB、结构 metadata 4 MiB，目录/entry/body/reader/editor/owner/chunk 各有全域记录上限。未知 size/get/clear 不创建目录；保留的 generation tombstone 不超过 32 个。Cache 与普通 files 的独立固定分区在政策上合计最多 262 MiB 逻辑 reservation，不跨两个 DB 借贷，不能据此声称物理磁盘或进程内存上限。

2026-11-04，主代理在 Codex 内置 Chromium 156 实际执行最终 64hex namespace 版本，39 组全部通过，正式 runner 收到报告并退出 0。新增十二组覆盖：

- 真正写入 16384 个不超过 8 KiB 的二进制块，使两个目录加 staging metadata 达到恰好 128 MiB；活 editor 不能被淘汰以突破配额。没有直接改 usage 值伪造正文边界。
- 另用真实 64 KiB 块填至剩一个字节，两 Worker 并发争用该字节，只能一方成功；chunk 计数仍有空余，独立于 chunk cap。
- reader 固定的 retired body 不提前退款，最终 ACK 只退款自己的 body；跨目录 LRU 可淘汰其他目录的未固定 current entry。
- 跨目录 64 reader、64 editor、32 owner；终止 A 目录 owner 后访问 B 即回收 A 的 staging 与 owner 名额，活兄弟保留。
- 32 目录 tombstone、未知目录不增长；小正文的 16384 个单字节 chunk 仍受记录 cap；长动态键、4 MiB 结构 reservation 与 UTF-8 字段上限。
- 普通 pending 4 满时 reader-close 仍能完成；真实 IDB commit abort 后记录和 usage 同步回滚，再独立清理本 editor；两个 namespace 相互隔离。
- 单块 read 只发生一个 chunk lookup，未扫描记录；结构/目录元数据操作不读取正文值。

最终编译身份由正式 runner 对实际服务字节计算，报告位于忽略的 `.local/cache-lifecycle/namespace-final.json`：

| 字节                          | SHA-256                                                            |
| ----------------------------- | ------------------------------------------------------------------ |
| 产品 Cache 桥                 | `7fc988f9937eaaf232c42a52e61e9a45112377e4d09be857386b356e77c36518` |
| 桥与测试 driver 的实际 Worker | `d0d93b4f8be48a30c1d014aaf157d19340a9fc900af502ecfa52b1e89ad1f98d` |
| 浏览器 suite                  | `cce9f8a3317720e566ab42a8fad6cf66a7628a146a2ba4e0438d53fd1a15de72` |

此前施工 checkpoint 的 27 组和较短 namespace 的 38 组报告保留为历史分项；本表对应最终生产长度键和独立 payload 竞态。固定分区的 files 一侧仍引用其既有 14 组独立门，本轮没有让两个数据库在同一 namespace 同时承受 128+128 MiB 压力。manager 的 namespace 升级/重建保留与 identity/repo/package/schema 四维隔离单元回归已通过；真实 IDB 数据跨版本保留仍是另一门。

## 同版原 JVM 与 TeaVM

原 JVM 使用官方未适配的 [OkHttp JVM 5.5.0 JAR](https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp-jvm/5.5.0/okhttp-jvm-5.5.0.jar)，SHA-256 为 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52`。独立 classpath 排除 seed 的适配版 OkHttp，并断言 Cache/OkHttpClient 的实际 CodeSource；不能把 seed 中已替换为 BrowserCall 的同名 JAR 当作原版 oracle。

TeaVM 侧从当前维护 Java 模板生成独立临时工程，调用正式 `prepareSources` 生成上游 regex donor，再调用 `compileExtension`。该流程保留 owned class strip、Bridge bootstrap、compat 和锁定的官方 TeaVM 0.16.0 插件；仅把 mainClass 改为临时 `CacheProbe`，由线程调用未修改的 `CacheScenarios.run`。没有改官方扩展或原始 JAR。

历史首轮构建基于 `7edf1237b254360ec791207f4a89cb405ff27cfd` 加 Cache v2 维护变更，`app.js` SHA-256 为 `4959ffbabb622b4c36ff602342caac2acd4833e31eee9b0ceb4168b05fd041fe`，共享场景源码 SHA-256 为 `b2597eebd5ab974d3e4a898e409b8706415e20cd6e478eda142484b3aa10f88d`。该分项两端均为 11 次请求、8 次网络、4 次命中、5 次成功写入，保留为历史证据。

本轮在 `d76e8a4` 主线加本次 Cache 维护变更重建，追加 no-cache 和 POST invalidation 对照。独立测试 bundle 为 1022989 B，SHA-256 `d94a10763b7cc2ef54f58a047bc4947ea8850ae99e37a056966ee28d478ecfda`；共享场景源码 SHA-256 `0bdc33131cc3bcbf44c12b602c0fa14f159216df67567eb74b37bf735fa81943`。这不是发布扩展的 AOT 身份；格式或输入改变后应重新确认构建身份。

真实浏览器 Worker 加载产品 crypto/cache 桥及该 bundle，经二进制 JSO、`BinaryHttpTransport` 和真实 workerd HTTP v2 访问隔离的受控 origin。测试 JWT/JWKS 仅用于受控 Access verifier，不证明生产登录。生产网络策略没有增加 loopback 例外。

同一场景覆盖 131079 字节冷/热命中、ETag 304 合并与原正文、no-store、Cookie Vary、evictAll 后已打开 snapshot 继续读，以及 cache 继续可用。新增 no-cache 强制条件重验证并保留 304 原正文，POST 实际上传并回显 mutation、失效同 URL 的旧 GET，之后 GET 重新请求并缓存。

| 结果       | 官方 JVM | TeaVM / Chromium 156 |
| ---------- | -------- | -------------------- |
| 请求数     | 18       | 18                   |
| 网络数     | 13       | 13                   |
| 命中数     | 7        | 7                    |
| 成功写入数 | 8        | 8                    |

两端正文 SHA-256 均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`。共享 Java 断言全部通过，机制回归与此 Java 场景是两个独立层级。

## 复验

准备锁定的工具链和 seed 后，正式维护入口：

```sh
pnpm typecheck:bridges
pnpm exec vitest run packages/runtime-host/test/bridge.test.ts
pnpm teavm:check
```

39 组浏览器桥机制已有正式入口。安装固定 Node/pnpm 依赖后运行以下命令；用 Codex 内置浏览器打开 stdout 的 URL，页面自动运行。命令在报告通过后退出 0，失败、超时或中断退出非零并关闭监听端口；默认报告为 `.local/cache-lifecycle/browser-result.json`。每轮先写未运行状态，避免误用旧成功报告；可用 `--report PATH`、`--timeout-ms 300000`、`--port 0` 指定输出与期限。成功/失败报告包含实际桥、Worker 和 suite 摘要，临时测试 namespace 在退出时清理。

```sh
node tools/teavm/check-cache-storage.ts --timeout-ms 300000
```

正式 runner 的实际成功退出已通过；未打开浏览器的期限失败与 SIGTERM 中断均退出 1、留下明确失败报告并释放端口。没有自动启动外部浏览器，也未把该手动机制门冒称 CI 浏览器检查。

Java 浏览器编排与产物仍留在忽略的 `.local/cache-java/`，以下临时驱动不随干净检出提供：

```sh
node .local/cache-java/build.ts
node .local/cache-java/server-policy.ts
# 内置浏览器打开 stdout 的 loopback URL，运行共享 Java Cache 场景。
```

改桥或测试后重新运行命令以生成新产物；改 Java 后先重新运行 build。Java runner 使用正式 `prepareSources`、`compileExtension`、`compileBridge`，隔离自身 Maven/workerd state；不要复用正在运行的发布器目录。新 Java 报告为 `.local/cache-java/policy-browser-result.json`，维护文档只保留有用结论。

## 未通过的后续门

- body metadata/pin/usage 记录损坏恢复、清理事务持续失败，以及更广的存储损坏恢复尚未验证；六类 chunk 门不能替代这些情况。
- 共享 Java 场景尚未覆盖截断网络正文、网络半途取消及更广的异常类型对照；桥上的 reader-close/read abort 不等于完整 Java HTTP 取消门。
- 新 host 输入的扩展 AOT、正式 Source、扩展版本与 storage namespace 切换、生产 Access、Native 和设备资源测量须另验。
- allocated 是 current/staging/pinned-retired 正文及响应 metadata 的逻辑预算，另有结构 reservation，不是浏览器物理磁盘占用。跨目录 namespace 上限已实现并通过上述门；Cache/files 组合压力、origin 所有 namespace 总占用与设备峰值仍未测量。

实施目标与后续顺序见 [运行时文件与 HTTP Cache 计划](../plan/runtime-storage.md)。
