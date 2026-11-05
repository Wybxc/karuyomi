# 共享运行时材料

共享桥与 WASM 随客户端版本交付：Web 使用静态资源，Native 将字节打包进应用。所有客户端的扩展 AOT bundle 均从 Static Assets 获取，索引每包只保留最新可用构建。原型仅维护当前材料，不保留旧版本兼容集合或私有路径回退；完整交付见[扩展静态分发](EXTENSIONS.md)。

## 来源与构建

`runtime/teavm/bridge/` 的 crypto、zstd、graphics、cache、file 五个桥使用严格 TypeScript。产品构建由 Vite CLI 读取声明式多环境配置，按两阶段执行：

1. `packages/runtime-host/vite.materials.config.ts` 声明五个独立 classic IIFE。`vite.runtime-plugin.ts` 的构建 hook 根据最终字节生成内容寻址材料和 catalog，并加入固定 Zstd WASM。
2. `packages/runtime-host/vite.config.ts` 声明 Web host ESM、Web Worker classic IIFE，以及独立的 Native host/Worker classic IIFE。同一 `vite.runtime-plugin.ts` 读取已生成材料，生成 Native 材料虚拟模块与运行时 manifest；六份 Source 材料只内嵌到 Native Worker。

资源生成和 Native 内嵌集中在现有 Vite 插件中；独立的 `materials.ts` 已删除。`@karuyomi/contracts` 仅提供纯 `runtimeMaterialCatalogSchema` 模型及其类型。工具与测试在调用点直接使用 `readFile` 读取 `dist/materials.json`，再用 `runtimeMaterialCatalogSchema.parse(JSON.parse(...))` 校验；按 catalog 路径读取需要的字节。材料读取不启动编译，缺少产物时先运行对应 CLI。

Zstd 上游 JS glue 与 WASM 来自 pnpm 精确锁定的 `@bokuweb/zstd-wasm@0.0.27`。项目只维护有界 codec 与桥封装，不复制上游生成代码。WASM 固定为 251,806 bytes，SHA-256 `80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df`；来源和许可见 [NOTICE](../runtime/teavm/NOTICE.md)，tarball 完整性由 `pnpm-lock.yaml` 固定。

```sh
pnpm install --frozen-lockfile
pnpm typecheck
# 只生成共享材料，供 AOT 构建与材料读取使用
pnpm --filter @karuyomi/runtime-host build:materials
# 先生成材料，再构建全部宿主
pnpm --filter @karuyomi/runtime-host build
# 将三个 Native 文件复制到 Flutter 应用
pnpm build:native-assets
```

普通客户端构建不需要私有 JVM seed 或 SDK 编译。catalog 只包含五桥与 Zstd WASM 六份正式材料，已删除闲置的 codec 字段。未被默认产品采用、缺少性能依据的图片 codec 候选源码、专属工具与构建配置已删除；图片由 Flutter/UI 直接解码。历史机制与限定结果保留在 [codec 记录](verification/long-image-codec.md)，不构成当前资源交付或性能验收。

| 生成输出                                                              | 用途                                          |
| --------------------------------------------------------------------- | --------------------------------------------- |
| `packages/runtime-host/dist/materials.json`                           | 当前六份产品材料、来源及 materialVersion      |
| `packages/runtime-host/dist/materials/<sha256>`                       | 五桥与 Zstd WASM 的 Web 静态字节              |
| `packages/runtime-host/dist/{host.js,worker.js}`                      | Web host ESM 与独立 classic Worker            |
| `packages/runtime-host/dist/native/{host.js,worker.js,manifest.json}` | Native 运行时；六份 Source 材料在 Worker 内嵌 |
| `apps/reader/assets/runtime/{host.js,worker.js,manifest.json}`        | cpy-cli 复制的 Flutter 应用资源，不入库       |

`materialVersion` 覆盖协议、ABI、材料顺序、路径、摘要、长度和 MIME。同一源码与锁定依赖须生成一致 catalog。当前 host ABI 为 `karuyomi-source-host-v4`、protocolVersion 为 2；Web/Native 材料与扩展须按同一身份重建。扩展 AOT 另有输入指纹与 bundle 摘要，Vite 配置及依赖锁属于构建输入。

## Web 与 Native

扩展清单中的 hostScripts/resources 只能使用 `/runtime/materials/<sha256>`。Web loader 使用同源静态请求、`credentials: omit` 和内容寻址缓存，在传输边界验证字节。Web 与 Native 的扩展 bundle 都使用 `/extensions/artifacts/<canonicalSHA>.gz`；先验证编码后的长度/摘要，再有界解压并验证 canonical 长度/摘要。索引和清单使用 no-cache，gzip 使用 immutable 缓存及 `application/gzip`，不附加 HTTP Content-Encoding。公开扩展下载不携带 Access cookie。

API 的 `apps/api/vite.assets.ts` 插件在正式构建时装配静态资源，合并 MIME、nosniff 与一年 immutable 缓存规则；catalog 使用 no-cache。它排除 runtime/native 和 Flutter Web 复制出的 assets/assets/runtime，并遍历公开文件，防止原生 host/worker/manifest 以其它名字进入公开产物。

Native 材料解析器只返回应用内字节，缺失时明确失败，不访问网络。扩展 bundle 与 Web 一样从静态索引加载。Dart 校验运行时 manifest 和 host/worker，再于受控 HTTPS 页面 document-start 注入。控制页采用 `/runtime/host.html` 或 Cloudflare 规范化后的 `/runtime/host`；动态 API 使用该 WebView 的同源 Access cookie。Native host 将当前 origin、plugin 与 fsNamespace 传给 Blob Worker，cache/file 桥据此使用当前构建命名空间。图片交付后由 Flutter/UI 解码。

## 验证范围

```sh
pnpm test
BROWSER=none pnpm test:browser
pnpm test:extension-integrity
```

`pnpm test` 包含声明式预构建与材料测试，检查固定 WASM、实际材料摘要、MIME、catalog 身份、Native 独立字节所有权、正式材料文件集，以及缺失材料无网络回退。官方 Browser 测试在真实 Worker、IndexedDB、Web Locks 与 Canvas 中验证已迁移的桥场景。仅有工程构建或 fixture 通过不能证明 Source 在线语义、图片阅读、Native 执行、生产 Access 或真机性能；当前覆盖见 [Vite 计划](plan/vite-build-and-testing.md)，实际门见 [VERIFICATION](VERIFICATION.md)。
