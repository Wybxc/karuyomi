# HTTP Cache 运行证据

2026-11-04。正文分块、Cache 生命周期与共享 Java 场景已通过以下门；普通文件、namespace 总预算、正式 Source、生产 Access 和 Native 仍须分别验收。不能把本记录作为整个存储或阅读能力完成的证明。

## 正式维护入口

- `runtime/teavm/bridge/cache-bridge.ts`：直接使用 `idb@8.0.4` 的 typed schema、原子 metadata/body 指针和二进制 chunks。
- `runtime/teavm/java/src/main/java/okhttp3/Cache.java`、`prototype/CacheSink.java` 与 `prototype/Bridge.java`：原 CacheInterceptor 的 Java 集成、存储写失败隔离，以及每次不超过 65536 字节的实际 JSO 读写。
- `packages/runtime-host/test/cache-lifecycle-browser-suite.ts`、`cache-lifecycle-worker.ts`：正式产品桥的真实 Worker/IDB/Web Locks 回归。
- `tools/teavm/CacheScenarios.java`：两端完全相同的 Java 场景；`CacheTest.java` 提供原 JVM origin 与 CodeSource 断言；`CacheSinkTest.java` 提供 19 项 JVM 写入终态检查。JVM 两项已接入 `pnpm teavm:check`。

## 浏览器机制门

Codex 内置浏览器 Chromium 156 通过十七组。覆盖活 owner/CAS/clear generation、terminate 后首次 begin 回收、close/delete 在途 begin fence、真实提交失败后的独立 CAS 清理、不可变 reader snapshot、分块和 allocated 预算、metadata 操作不读正文、Java handle 隔离。可见预算无法在活 editor 竞争下满足时，commit/update 原子拒绝；close/delete 的真实 IDB `ConstraintError` 后，关闭 handle 的 editor 被清理，原错误、旧完整条目、reader、sibling 和其他 owner 均保持预期。

故障注入只在测试 driver：使用真正的重复主键请求触发浏览器事务 abort，或控制 Web Locks 探测的等待顺序。单次 Worker 恢复延时约 2.2 ms，只证明无需旧超时回收机制，不是性能分布或承诺。

## 同版原 JVM 与 TeaVM

原 JVM 使用官方未适配的 [OkHttp JVM 5.5.0 JAR](https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp-jvm/5.5.0/okhttp-jvm-5.5.0.jar)，SHA-256 为 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52`。独立 classpath 排除 seed 的适配版 OkHttp，并断言 Cache/OkHttpClient 的实际 CodeSource；不能把 seed 中已替换为 BrowserCall 的同名 JAR 当作原版 oracle。

TeaVM 侧从当前维护 Java 模板生成独立临时工程，调用正式 `prepareSources` 生成上游 regex donor，再调用 `compileExtension`。该流程保留 owned class strip、Bridge bootstrap、compat 和锁定的官方 TeaVM 0.16.0 插件；仅把 mainClass 改为临时 `CacheProbe`，由线程调用未修改的 `CacheScenarios.run`。没有改官方扩展或原始 JAR。

测试构建基于 `7edf1237b254360ec791207f4a89cb405ff27cfd` 加当前 Cache v2 维护变更，属于独立测试 bundle，不是发布扩展的 AOT 身份。本次 `app.js` SHA-256 为 `4959ffbabb622b4c36ff602342caac2acd4833e31eee9b0ceb4168b05fd041fe`；共享场景源码 SHA-256 为 `b2597eebd5ab974d3e4a898e409b8706415e20cd6e478eda142484b3aa10f88d`。格式或输入改变后应重建并重新记录身份。

真实浏览器 Worker 加载产品 crypto/cache 桥及该 bundle，经二进制 JSO、`BinaryHttpTransport` 和真实 workerd HTTP v2 访问隔离的受控 origin。测试 JWT/JWKS 仅用于受控 Access verifier，不证明生产登录。生产网络策略没有增加 loopback 例外。

同一场景覆盖 131079 字节冷/热命中、ETag 304 合并与原正文、no-store、Cookie Vary、evictAll 后已打开 snapshot 继续读，以及 cache 继续可用。

| 结果       | 官方 JVM | TeaVM / Chromium 156 |
| ---------- | -------- | -------------------- |
| 请求数     | 11       | 11                   |
| 网络数     | 8        | 8                    |
| 命中数     | 4        | 4                    |
| 成功写入数 | 5        | 5                    |

两端正文 SHA-256 均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`。共享 Java 断言全部通过，机制回归与此 Java 场景是两个独立层级。

## 复验

准备锁定的工具链和 seed 后，正式维护入口：

```sh
pnpm typecheck:bridges
pnpm exec vitest run packages/runtime-host/test/bridge.test.ts
pnpm teavm:check
```

本次浏览器编排与产物留在忽略的 `.local/cache-lifecycle/` 和 `.local/cache-java/`。当前开发 checkout 的复验命令如下；这些临时驱动不随干净检出提供，后续须把最小编排内化为正式浏览器测试入口，不能据此宣称已有 CI 浏览器门。

```sh
node .local/cache-lifecycle/server.ts
# Codex 内置浏览器打开 http://127.0.0.1:53215/，点击 Run cache lifecycle
node .local/cache-java/build.ts
node .local/cache-java/server.ts
# Codex 内置浏览器打开 http://127.0.0.1:53217/，点击 Run shared Java cache scenario
```

改桥或测试后重启 server 以重新生成桥产物；改 Java 后先重新运行 build。Java runner 使用正式 `prepareSources`、`compileExtension`、`compileBridge`，隔离自身 Maven/workerd state；不要复用正在运行的发布器目录。结果分别落在上述忽略目录的 `browser-result.json`，维护文档只保留有用结论。

## 未通过的后续门

- reader 所属 Worker 死亡后的回收、正文 chunk 损坏或缺失、真实读到一半取消和失败注入仍待专门验收。
- 共享 Java 场景尚未覆盖 no-cache、POST invalidation、截断网络正文及更广的异常类型对照。
- 新 host 输入的扩展 AOT、正式 Source、扩展版本与 storage namespace 切换、生产 Access、Native 和设备资源测量须另验。
- allocated 是 current/staging/pinned-retired 正文及 metadata 的逻辑预算，不是浏览器物理磁盘占用；普通文件与跨目录 namespace 总预算尚未实施。

实施目标与后续顺序见 [运行时文件与 HTTP Cache 计划](../plan/runtime-storage.md)。
