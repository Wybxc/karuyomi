# 共享运行时材料

共享桥与 WASM 随客户端版本交付：Web 使用静态资源，Native 将字节打包进应用。所有客户端的扩展 AOT bundle 均从 Static Assets 获取，索引每包只保留最新可用构建。当前处于原型阶段，仅维护当前材料，不保留旧版本兼容集合或私有路径回退；完整交付流程见[扩展静态分发](EXTENSIONS.md)。

## 来源与构建

`runtime/teavm/bridge/` 中的 crypto、zstd、graphics、cache、file 五个桥使用严格 TypeScript。`packages/runtime-host/materials.ts` 用 esbuild 编译成 classic IIFE，再根据实际生成字节计算材料摘要。浏览器执行生成的 JavaScript，不执行 TS 源文件。

Zstd 的上游 JS glue 与 WASM 都来自 pnpm 精确锁定的 `@bokuweb/zstd-wasm@0.0.27`。项目只维护有界 codec 和桥封装，不复制上游生成代码。WASM 的固定身份为 251,806 bytes，SHA-256 `80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df`；npm 包来源和许可见 [NOTICE](../runtime/teavm/NOTICE.md)，tarball 完整性由 `pnpm-lock.yaml` 固定。

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm --filter @karuyomi/runtime-host build
```

普通客户端构建不需要私有 JVM seed。元数据入口 `node packages/runtime-host/prepare-materials.ts --print` 也会编译 TS 桥及其 npm 依赖，但只读取固定的 WASM 元数据；`--output DIR` 另外读取和验证 WASM 字节。

| 生成输出                                                              | 用途                                    |
| --------------------------------------------------------------------- | --------------------------------------- |
| `packages/runtime-host/dist/materials.json`                           | 当前六份材料、来源及 materialVersion    |
| `packages/runtime-host/dist/materials/<sha256>`                       | 五份 JS 与一份 WASM 的 Web 静态字节     |
| `packages/runtime-host/dist/native/{host.js,worker.js,manifest.json}` | Native 运行时，材料只内嵌于 worker 一次 |
| `apps/reader/assets/runtime/{host.js,worker.js,manifest.json}`        | 自动复制的 Flutter 应用资源，不入库     |

`materialVersion` 覆盖协议、ABI、材料顺序、路径、摘要、长度和 MIME。同一提交、锁定工具链和依赖必须生成一致的 catalog。当前 host ABI 为 `karuyomi-source-host-v3`、protocolVersion 为 2；Web/Native 材料与扩展须按同一身份重建。扩展 AOT 另有自己的输入指纹与 bundle 摘要。

## Web 与 Native

扩展清单中的 hostScripts/resources 只能使用 `/runtime/materials/<sha256>` 静态路径。Web loader 使用同源静态请求、`credentials: omit` 和内容寻址缓存，并验证收到的字节。Web 与 Native 的扩展 bundle 都使用 `/extensions/artifacts/<canonicalSHA>.gz`；先验证编码后的长度/摘要，再有界解压并验证 canonical 长度/摘要。索引和清单使用 no-cache，gzip 使用 immutable 缓存及 `application/gzip`，不附加 HTTP Content-Encoding。公开扩展下载不携带 Access cookie。

`scripts/assemble-assets.ts` 合并静态 MIME、nosniff 与一年 immutable 缓存规则；catalog 使用 no-cache。它同时排除 runtime/native 和 Flutter Web 复制出的 assets/assets/runtime，并遍历实际公开文件，防止原生 host/worker/manifest 以其它名字进入公开产物。

Native 的共享材料解析器只返回应用内字节；缺失时明确失败，不访问网络。扩展 bundle 则与 Web 一样从静态索引加载。Dart 校验运行时 manifest 和 host/worker，再于受控 HTTPS 页面 document-start 注入。控制页采用 `/runtime/host.html` 或 Cloudflare 规范化后的 `/runtime/host`；动态 API 使用该 WebView 的同源 Access cookie。Native host 将当前 origin、plugin 与 fsNamespace 传给 Blob Worker，cache/file 桥据此使用当前构建命名空间。

## 验证范围

```sh
pnpm exec vitest run packages/runtime-host/test/materials.test.ts
pnpm test:extension-integrity
```

材料测试覆盖 TS 编译确定性、固定 WASM、六份输出的真实字节摘要、MIME、Native 独立字节所有权、缺失材料无网络回退和私有旧路径拒绝。桥单独进行 crypto/WASM/IndexedDB/graphics 回归；类型检查覆盖维护源码。材料检查不代表 Source 在线语义、图片通道、真实 Access 登录或完整阅读通过；对应证据见 [VERIFICATION](VERIFICATION.md)。
