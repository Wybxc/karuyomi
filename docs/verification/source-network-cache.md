# Source 默认 HTTP Cache 配置

状态：**宿主配置已修复并通过 JVM / TeaVM 配置门；真实 Source 缓存仍待新 AOT 复验**。本项不替代 [Cache 正文与失败语义](http-cache-runtime.md)、[namespace 机制门](cache-v3-native.md) 或 [31555e8 三源在线门](cache-v3-sources.md)。

## 已复现的缺口

2026-11-04，固定 `31555e8` 的未修改 xkcd Source 通过正式 Source RPC、真实 workerd、隔离网络策略 D1 和受控 RS256 测试身份完成两项观察：同一 Page 会话的 direct PNG acquire/release 两次；另一个真实章节 `/3318/` 的 pages 两次，每次关闭 Page 会话。图片各有一次 HTTP 200 / 106037 字节，pages 各有一次 HTTP 200 / 7187 字节；Cache 控制、正文读写、commit 全部为零，两项均为 `not_demonstrated`。不能把网络减少、Source 自有章节列表 memo 或两个相同正文当作 HTTP Cache 命中。

该夹具仅在正式 Worker 末尾包装 `teaCache` / `teaCacheRead` / `teaCacheWrite` 观察原返回和异常，未改变原 Source、JAR、AOT、桥字节或请求头；它记录 store 事件，不是 Java CacheInterceptor 的精确计数。原报告保留在固定验证树的 `.local/cache-v3-source/cache-observation/result.json`，SHA-256 `56e36d7b7b12004d3bb82fef67560adc5defc2f824219a478a00a61948f5ab6e`。

锁定 seed 的 `host-44fb93b22828.jar` 为 244927 字节，SHA-256 `44fb93b228289e631863919700f0bd2fc6a86194449b78e4a5703a4fa78bd5f1`。`javap` 与独立 JVM classpath 均确认其中 `NetworkHelper` 构造器没有调用 `Builder.cache(...)`。`TeaHost.init()` 直接实例化它，`HttpSource.getClient()` 返回该 client；`OkHttpClient.Builder` 默认 Cache 为 null，原 CacheInterceptor 因而不调用 store。此次 metadata 零事件有明确的宿主配置原因，不能归因上游缓存策略。图片还按原 `newCachelessCallWithProgress` 明确关闭 Cache，保持该语义。

## 当前适配与来源

正式 [NetworkHelper.java](../../runtime/teavm/java/src/main/java/eu/kanade/tachiyomi/network/NetworkHelper.java) 内化默认配置，保留 seed 的公开 ABI、`Cookies.INSTANCE`、动态 UA provider，以及 UncaughtException / UserAgent / Cloudflare 三个应用拦截器的参数和顺序。普通 `OkHttpClient.Builder` 继续默认 cacheless；Source 显式选择的 Cache 或 null 不被覆盖。seed 中的 Cloudflare 类是既有 pass-through 适配，不能据此宣称通过挑战页。

默认 Cache 使用 `new File(context.getCacheDir(), "network_cache")` 与 5 MiB。当前 Context/Application 的稳定路径为 `/files/cache/network_cache`，namespace 与全域预算仍由产品 Cache 桥执行。它不创建普通文件正文副本，也不把 Context 路径当作浏览器身份隔离边界。Source 版本升级、repo/package/storageSchema 等隔离继续由 manager 派生的 namespace 决定。

配置来源为真正 submodule 中固定 Suwayomi-Server `6b481e8b62938b9c060eb210b934e0fbfdfa466b` 的 [NetworkHelper.kt](../../vendor/suwayomi-server/server/src/main/kotlin/eu/kanade/tachiyomi/network/NetworkHelper.kt)，该上游类配置 5 MiB Cache；新 Java 文件保留 MPL-2.0 来源头。项目使用稳定目录替代服务端的随机临时目录。构建器按现有 owned 类裁剪机制移除 seed 同名类及其旧内部类，不修改 seed 或扩展 JAR。

## 已运行的门

```sh
node tools/teavm/check-network.ts
pnpm teavm:check
```

需要先按运行时锁文件准备 seed、JDK 和 TeaVM 依赖。`check-network` 清空自己的 ignored class 输出，分别运行旧 seed 和 owned classpath：

- seed：15 项，核对实际 CodeSource、公开方法和已有配置，明确断言默认 Cache 为 null。
- owned：22 项共享配置，覆盖稳定 5 MiB Cache、Context 路径、newBuilder、Source 自选 / cacheless 副本、Cookie、拦截器顺序与动态 UA；另有 12 项 JVM ABI / 实际类来源 / 图片 helper 隔离检查。NetworkHelper、OkHttpClient、Cache 必须来自新编译的 owned 输出，实际图片 helper 的 client 必须为 null Cache 且不改变原 client。
- 完整 `check-dto` 本轮退出 0，保留原 DTO、HTTP、graphics、image 与 file 门，新配置门已接入该正式入口。

主代理在 Codex 内置 Chromium 156 的真实 Worker 中执行正式 TeaVM 0.16.0 构建的 [NetworkHelperProbe](../../tools/teavm/fixtures/network/NetworkHelperProbe.java)，共享配置 **22/22 passed**，目录 `/files/cache/network_cache`、预算 5242880 字节。loopback runner 收到完整报告后退出 0。该门没有发起网络或存储操作，没有测 Source、Cache 命中、Native 或性能。

| 输入 / 输出                    | SHA-256                                                            |
| ------------------------------ | ------------------------------------------------------------------ |
| owned NetworkHelper.java       | `428c4c5de2e48b708951d748684f15c11cdee017a27e56be4cd53d631e3ed4cc` |
| NetworkHelperTest.java         | `1c621d6be6eb5283de4cf756c6b273e5ff41af120522b969d15affcacd337bb1` |
| 实际 TeaVM bundle，334040 字节 | `6b5f62446539384f39ab677dbc6e9c2f1ac9b83f36352ff2ac9bc0fd9d8bffba` |
| 实际浏览器 Worker              | `81679fbef18802744b9d692a2220b7aee698a47940dc5daf3824d3a2807da416` |

小门使用同份 `NetworkHelperTest.run()`，通过正式 `compileExtension` 复制当前 owned 源码、物化固定上游补丁、裁剪 seed 并将 mainClass 设为 `prototype.NetworkHelperProbe`。本机编排与原始报告位于 ignored `.local/network-configuration/`：`node .local/network-configuration/build.ts` 构建，`node .local/network-configuration/server.ts` 输出随机 loopback URL，内置浏览器打开后自动运行。它们是本次执行材料，不是自动 CI 浏览器入口；可维护的 Java fixture 与正式 JVM 入口已入源码。

## 下一门

提交后从新固定提交重新生成完整 input 计划，仅本地重建原 xkcd JAR 的 AOT，保持严格原 JAR 摘要与新材料身份。沿正式链重复 metadata pages cold / warm，并观察 store entry、commit、正文读取及实际 HTTP 200 / 304 流水。fresh reuse、304 重验证、上游不允许缓存和 store 错误必须分别报告，不能为取图命中修改原请求头或启用图片 Cache；观察不到时继续保留 `not_demonstrated`。
