# Java HTTP Cache 截断与取消验证

2026-11-04，官方原 JVM 与实际 TeaVM 在 Codex 内置 Chromium 156 各通过同一份四场景、50 项 Java 断言；最终正式 runner 退出 0，连接关闭检查也全部通过。本门独立于[HTTP Cache 历史场景](http-cache-runtime.md)的 18/13/7/8 计数，不修改或合并历史结果。它验证受控 HTTP，不代表正式 Source、生产 Access 或 Native 已通过相同取消门。

## 场景与实际链路

`tools/teavm/CacheFailureScenarios.java` 对空 cache 和已有完整条目分别执行截断、半途 `Call.cancel()`。受控 origin 真实发送 `Content-Length: 131079`，写出 8192 字节后保持尾部。Java 精确读满该前缀后，截断场景才发出独立控制请求关闭真实原点 socket；取消场景同步调用原 Call。故障由读取确认驱动，不依赖计时碰巧发生。

两端均断言后续正文读取抛出 IOException，不能视为成功 EOF；缓存写入恰好 abort 一次。关闭 Cache 后以同目录重开，空 cache 半成品不可见、旧完整条目保留原字节；完整网络恢复后可再次缓存并 warm hit。原 JVM 截断报告 `ProtocolException: unexpected end of stream`，取消报告 `SocketException: Socket closed`；TeaVM 不要求错误文案或具体子类完全相同。

原 JVM 使用未适配的[官方 OkHttp JVM 5.5.0 JAR](https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp-jvm/5.5.0/okhttp-jvm-5.5.0.jar)，SHA-256 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52`。runner 隔离 classpath，排除 seed 的适配版同名 JAR 与 host JAR，并断言 Cache、OkHttpClient 的实际 CodeSource。

TeaVM 从当前维护模板生成忽略的临时工程，使用正式 `prepareSources`、`compileExtension`、owned class strip 和锁定官方插件。实际 Worker 加载 canonical `compileBridge('cache')` / crypto、Java bundle 和维护 driver；经真实二进制 JSO、原 CacheInterceptor、`BinaryHttpTransport`、HTTP v2、workerd、IDB 与 Web Locks。没有修改官方 Source 或原始 JAR；这不是发布扩展的 AOT 身份。

## 连接关闭证据与边界

最终浏览器报告为 Java 50 项/四场景通过、transport open=0、cancel=2、真实中继 backendResets=2，`originVerified` 与 `upstreamClosed` 均为 true。四条准确失败路径各出现一次，均声明 131079 B、只发送 8192 B、实际观察到原点响应 close；两个截断事件均确认前缀读取。5 秒只用于等待关闭的失败截止，不是性能保证。

测试层通过 Miniflare 的公开随机 HTTP 监听访问真实 API，把隔离 APP_ORIGIN 配置成该监听的实际 origin，保留产品的 RS256 JWT、Host、Origin 与 X-App-Request 检查。测试 `outboundService` 把允许的 fixture.example.org 映射到隔离受控原点，没有给生产网络政策增加 loopback 例外。Node 标准 `httpRequest` / `pipeline` 仅在外层真实客户端断连且响应尚未完成时，对中继自己的真实 HTTP/1 后端 socket 执行 `resetAndDestroy()`；没有直接调用产品 AbortSignal、伪造 close 事件或提前关闭原点。runner 使用官方 Wrangler 配置读取器与当前显式 `enable_request_signal`。

先前 Node fetch/dispatchFetch gentle 关闭的失败报告仍保留：Java 语义和本地句柄清理可以通过，但本地 workerd 等尾部时未观察到原点断连。本次 RST 成功只证明 loopback HTTP/1 转发链，不能推广为生产 HTTP/2、HTTP/3、真实 Access、正式 Source 或 Native 取消证据。

## 本轮输入

最终报告留在忽略的 `.local/cache-failure-http/browser-rst-v3-final-passed.json`；同轮 JVM 报告在 `jvm-report.json`。摘要对应实际服务字节，格式或构建输入变化后重新生成。

| 输入                             | SHA-256                                                            |
| -------------------------------- | ------------------------------------------------------------------ |
| 正式 API runner                  | `064041dd2c29aa70ab4db4d81643a06ad2c634dbd23f14bc579657a0c4bf32de` |
| 产品 Cache 桥                    | `7fc988f9937eaaf232c42a52e61e9a45112377e4d09be857386b356e77c36518` |
| 共享 Java 场景                   | `12bdf33209d74dc8f27eedbe703dd02ea0c9fc75a111844602917cab1ed34f29` |
| 实际 Java bundle（1006231 B）    | `fc7a0eca28376208da89faea53061e318da133c2d902e6fe32671581ee22de95` |
| 桥、Java 与 driver 的实际 Worker | `656d6b22737f5e7c77f4592bd08ccba4cb1cd2035833068e1035ad6acd3b5921` |

## 复验与失败报告

准备仓库锁定 Node、依赖、JVM 工具链和 seed 后，在当前 checkout 运行：

```sh
node apps/api/test/cache-http-probe.ts --port 0 --timeout-ms 300000
# Codex 内置浏览器打开 stdout URL，点击 Run shared Java failures。
node apps/api/test/cache-http-probe.ts --jvm-only
```

复用入口只维护 fixture、oracle、受控 origin 和 API 编排，不提交生成的 Maven 工程、下载 JAR、缓存或产物。它只编译当前官方桥，不保留选择旧桥的分支；历史输入应在固定 Git checkout 复验。两份 Java 入口分别是 `CacheFailureOracle.java` 和 `fixtures/cache-failure/CacheFailureProbe.java`，浏览器 driver 为 `packages/runtime-host/test/cache-failure-java-browser-worker.ts`。严格检查为 `pnpm typecheck:tools`、`pnpm exec tsc -p packages/runtime-host/test/tsconfig.bridge-browser.json` 与 `pnpm check:dependencies`。

每次运行在准备/编译前写入新的失败初态。最终报告位于忽略的 `.local/cache-failure-http/browser-report.json`，含实际脚本、共享 Java、Java bundle、Worker 和桥摘要；原 JVM 报告在同目录 `jvm-report.json`。成功退出 0。未打开浏览器的实际 `--timeout-ms 1000` 门退出 1，写入 deadline exceeded，并经异步 finally 清理；SIGTERM 的真实门在 stdout URL ready 后发送一次信号，写入明确 interrupted、本轮 identity，然后按锁定 Miniflare 自身 exit-hook 退出 143。该信号路径不声称执行了 runner 的异步 finally，也不承诺编译中立即停止 Maven；独立 TCP 检查确认 harness、workerd API、origin 三个端口均 ECONNREFUSED。

启动错误与 gentle 断连失败、`browser-timeout-failed.json`、`browser-sigterm-before-fix.json`、`browser-sigterm-failed.json` 及最终成功报告保留在该忽略目录。SIGTERM 门与最终成功门的 runner 摘要相同；超时报告保留其实际运行身份。曾有测试编译分支将 Uint8Array 错解码为空桥，已删除该分支；正式 Worker 在启动 Java 前验证三项 Cache 函数安装。报告失败不能被旧成功文件覆盖，编译成功也不能替代实际运行门。
