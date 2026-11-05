# TypeScript Worker 桥验证

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-03，正式 crypto、zstd、graphics、cache、file 桥迁为 TypeScript。专用 WebWorker 配置开启严格类型检查；Java JSON 与 IndexedDB 结果先按 `unknown` 校验。Zstd 的生成 glue 来自精确锁定的 `@bokuweb/zstd-wasm@0.0.27`，项目只维护帧边界、8MiB 解压上限、9MiB 压缩输入上限和初始化包装。

Worker 全局使用精确声明，方法类型来自实际实现，安装前可缺省；不通过泛型断言宣称方法存在。TypeScript 6.0.3 的 `ImageData` 构造器仍缺少 Float16 重载，局部扩展仅补充该签名、保留标准重载和运行时能力检查。

## 可重复的自动回归

```sh
pnpm exec tsc -p runtime/teavm/bridge/tsconfig.json
pnpm exec tsc -p packages/runtime-host/test/tsconfig.bridge-browser.json
pnpm exec vitest run packages/runtime-host/test/bridge.test.ts
```

6 个 Node 回归通过，执行实际 WebCrypto 与 npm WASM，覆盖 RFC4231 HMAC、NIST AES-GCM、AES-CBC 二进制往返、Zstd 空流/00/ff/UTF-8/拼接帧、截断/输出预算/帧数限制，以及未验证 WASM、缺失命名空间和错误输入的拒绝。这是 Node 运行机制验证，不代表浏览器存储或 Source 在线兼容。

## 实际浏览器

正式浏览器复验使用 **Codex 内置浏览器（Chrome 156.0.0.0）**，通过 CUA 点击本地测试页的 `Run real Worker regression`，界面与原始报告均为 `passed: true`。`write` 阶段的 5 项检查、`isolation` 与 `reopen` 阶段全部通过，执行真实 Blob Worker、IndexedDB、Web Locks、OffscreenCanvas 和 npm WASM：

| 门槛                                                    | 结果 |
| ------------------------------------------------------- | ---- |
| HMAC 标准向量、Zstd 二进制往返                          | 通过 |
| Canvas RGBA、PNG 编解码与回收后拒绝句柄                 | 通过 |
| Cache 并发唯一 editor、版本 CAS、metadata 更新保留 body | 通过 |
| 文件独立 cursor、打开时 rename/unlink、句柄保留 inode   | 通过 |
| 两个 Worker 的存储命名空间隔离                          | 通过 |
| 关闭并重建 Worker 后的 cache 与文件持久化               | 通过 |

测试入口为 [`bridge-browser-suite.ts`](https://github.com/Wybxc/karuyomi/blob/f623a8263c87ac198ff3882fd3eade1072e6abfc/packages/runtime-host/test/bridge-browser-suite.ts)，分别执行 `write`、`isolation`、`reopen` 三个阶段；实际 IDB 与锁没有替代实现。最终类型边界修正后再次通过 IAB 复验，五份脚本直接使用正式 `compileBridge()` 输出，SHA 与材料目录逐项一致，对应 `materialVersion` 为 `3b2b173e86d576656d27852f6177d377735ccbb1af2372740c48793ca41a2a3e`。测试页先核对 WASM SHA-256，再通过 Blob 资源供桥初始化。临时本地服务与原始结果写入 ignored 目录，不作为构建输入入库。

此前同一套机制回归也在 **Safari 27.0.1** 通过；这份历史结果与上述 IAB 复验属于不同执行环境。后续浏览器验证按要求仅使用 Codex 内置浏览器。

这些门槛没有验证 Access、HTTP 传输解码、真实 Source、Java 图片字节通道或完整阅读。

## Cache editor 的 Worker 生命周期

2026-11-03，Codex 内置浏览器 Chromium 156 点击独立 `Run cache lifecycle` 入口，十组真实 Worker、IndexedDB 与 Web Locks 回归全部通过。产品桥不再用五分钟过期时间判断 owner：Worker 持有 lifetime Web Lock，终止后重开可立即获取 editor，保留旧完整条目；活 owner、外来 Worker、Java handle、版本 CAS 和 clear generation 继续隔离。

新增故障门使用真实重复 IDB `add` 触发 `ConstraintError` 与事务回滚。产品等 `onabort` 后，独立事务按 editor、owner/handle 和 generation 清理；原错误仍返回，旧完整正文/版本不变，替代 editor、另一个活 Worker 和新 generation 均不被误解锁。另将 begin 停在事务外 Web Lock 恢复等待处，先完成同 handle 的 close，再恢复 begin，确认不会重新创建 editor。`delete()` 在 Java 先标记关闭，桥以同 handle 的 begin fence 和原子清空推进 generation；`evictAll()` 仍允许原 handle 后续正常 begin。只追踪正在执行的 begin，不保存无限增长的关闭 handle 历史。

复验源码为 `cache-lifecycle-browser-suite.ts` 和 `cache-lifecycle-worker.ts`，由正式 `compileBridge('cache')` 输出驱动；执行上述 strict tsc 与桥单测，再用本地静态页加载 suite、产品桥和测试 Worker。服务与原始 JSON 留在 ignored `.local/cache-lifecycle/`。单次重开约 1 ms 只用于确认无需 TTL 等待，不是设备性能分布。正文当前仍有整段 Base64 与全目录扫描；本门未验证 Java CacheInterceptor、原 Source、正文内存上界或原 JVM 等价。后续范围见[存储计划](../plan/runtime-storage.md)。
