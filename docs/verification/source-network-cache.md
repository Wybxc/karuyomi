# Source 默认 HTTP Cache 配置

状态：**宿主配置已修复；新固定 AOT 的原 xkcd Source 已在 Web 实测 metadata fresh Cache 正文复用**。本轮没有发生 304，图片保持原 cacheless 行为。本项不替代 [Cache 正文与失败语义](http-cache-runtime.md)、[namespace 机制门](cache-v3-native.md) 或 [31555e8 三源在线门](cache-v3-sources.md)。

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

## 原 Source 新 AOT 在线复验

2026-11-04，主代理在 Codex 内置 Chromium 156 执行新固定树的观察夹具，原报告 `finished=true`、`metadataResult=fresh_store_body_reused_without_upstream`。树固定于 `b4f72f70804f12caef21bb51a17cb5adad6982d4`，构建前后跟踪输入干净；完整计划发现 1448 包、发现失败 0，仅本地重建原 xkcd 1.6.1。官方 Gradle 使用相同 debug keystore 重产原 JAR，摘要精确一致，没有改 Source 业务源码或 JAR。

| 固定输入 / 输出             | 身份                                                               |
| --------------------------- | ------------------------------------------------------------------ |
| hostFingerprint             | `46e63625a0e1920d284c1077de8aca939f8948d1e50694259834f0846844e0db` |
| inputFingerprint            | `b33800f6d02ddab83b60b6d7ac85b49db7bd85ba625ee77cead3c22a5ca76de5` |
| buildId                     | `ext-all.xkcd-b33800f6d02ddab83b60b6d7ac85b49d`                    |
| 原 JAR，125470 字节         | `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d` |
| manifest SHA-256            | `6c5af3b869c190302b58de0845c2611941e7af5fc2f39d012f24016744592c07` |
| canonical AOT，4038599 字节 | `4d6f571a4d4e806512a9d28fc8a2f93f59a44bbe5c02a6eec809f90f2579ad02` |
| gzip，852898 字节           | `f70cce3a54c4fa2c5ac30d1668ee4b2898edc45fe787cca40692ccdb51a6657f` |
| materialVersion             | `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d` |
| 原报告 SHA-256              | `211ab6ed7a3bc3852ed229a8612c82453de7ca04d64b4298ee03b895ebfc4cb4` |

协议身份为 protocol 2 / host ABI v3 / bridge 2。新树正式 runtime-host 重新编译，六个共享材料的摘要、大小和路径与 manifest 逐项一致；没有混用旧 AOT。原 Worker、观察后缀与合并 Worker 的精确 SHA 保存在报告，观察后缀只透传包装 Cache 控制及二进制读写，未改变 Source 请求头、桥材料或返回结果。隔离 D1 仅批准 `xkcd.com`、`imgs.xkcd.com`，Access 使用受控 RS256 测试身份。

| 实际操作                                  | store 观察                                                  | 真实上游网络                              | 结果                                                      |
| ----------------------------------------- | ----------------------------------------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| 原章节 `/3318/` pages cold                | get 1、miss 1、begin 1、commit 1；2 次写入共 7187 字节      | 1 次 200，正文 7187 字节                  | 原正文完整缓存                                            |
| 同章节 pages warm                         | get 1、entry 1；3 次读取共 7187 字节、EOF 1、reader-close 1 | 0 次                                      | fresh store 正文复用                                      |
| 原 direct PNG，同一 Page 会话 cold / warm | 两轮所有 Cache 计数均为 0                                   | 各 1 次 200，正文各 106037 字节且摘要相同 | 保持 cacheless；两轮均解码 607×716，release / revoke 通过 |

metadata 两轮均返回 2 页，PageList 摘要一致，每次 Page 会话关闭均有确认，观察器错误为 0，最后 dispose 完成。真实响应被缓存的 metadata 为 `Cache-Control: max-age=300`，带 ETag；本轮发生的是有效期内复用，没有向上游发起重验证，**不能据此宣称原 Source 的 304 门通过**。这里的 get / commit / read 是 store 事件，不是 Java CacheInterceptor 的精确 request/network/hit 计数，也没有以网络减少或 Source 自有 memo 代替正文复用证据。

可复验目录为 `/Users/wybxc/.codex/worktrees/source-network-cache-validation/karuyomi`，ignored 输入和完整命令保存在 `.local/network-cache-source/README.md`、`build-summary.json` 与 `cache-observation/preparation.json`。使用仓库固定 Node / pnpm，在该固定树执行：

```sh
node scripts/prepare-runtime.ts --android
node tools/extensions/pipeline.ts plan \
  --state .local/network-cache-source/state.json \
  --output .local/network-cache-source/full-plan.json --limit 10000
# descriptor 从本次完整计划取准确的 all.xkcd 条目。
node scripts/build-extension.ts \
  --descriptor .local/network-cache-source/xkcd/descriptor.json \
  --output .local/network-cache-source/xkcd
pnpm --filter @karuyomi/runtime-host build
node .local/network-cache-source/cache-observation/prepare.ts
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_IMAGES=1 SOURCE_PROBE_PORT=8918 \
SOURCE_PROBE_EVIDENCE=.local/network-cache-source/cache-observation/result.json \
node .local/network-cache-source/cache-observation/server.ts \
  .local/network-cache-source/xkcd/manifest.json \
  .local/network-cache-source/xkcd/artifacts
```

观察器从该固定树的正式 `source-metadata-probe.ts` 重生成，client / Worker / server 三份严格 TypeScript 检查通过。内置浏览器在新 loopback origin 单次点击 Run；重跑应另存报告并区分已存在的持久 Cache，不能将热状态伪称冷请求。原报告位于 `.local/network-cache-source/cache-observation/result.json`；旧 `31555e8` 的零 store 报告原样保留。本轮只验 Web 原 Source fresh metadata 复用，不代表生产 Access、Native Source Cache、304 重验证、性能或其它 Source。
