# TypeScript Worker 桥验证

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

测试入口为 [`bridge-browser-suite.ts`](../../packages/runtime-host/test/bridge-browser-suite.ts)，分别执行 `write`、`isolation`、`reopen` 三个阶段；实际 IDB 与锁没有替代实现。最终类型边界修正后再次通过 IAB 复验，五份脚本直接使用正式 `compileBridge()` 输出，SHA 与材料目录逐项一致，对应 `materialVersion` 为 `3b2b173e86d576656d27852f6177d377735ccbb1af2372740c48793ca41a2a3e`。测试页先核对 WASM SHA-256，再通过 Blob 资源供桥初始化。临时本地服务与原始结果写入 ignored 目录，不作为构建输入入库。

此前同一套机制回归也在 **Safari 27.0.1** 通过；这份历史结果与上述 IAB 复验属于不同执行环境。后续浏览器验证按要求仅使用 Codex 内置浏览器。

这些门槛没有验证 Access、HTTP 传输解码、真实 Source、Java 图片字节通道或完整阅读。
