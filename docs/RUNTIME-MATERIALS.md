# 共享运行时材料

共享桥和 WASM 随客户端版本交付，扩展 AOT bundle 继续通过受 Access 保护的私有 API 加载。材料按 SHA-256 寻址；Web 与原生都在使用前验证摘要、长度和 MIME，不把缺失材料回退为私有 API 下载。

## 来源与构建

当前材料包含 5 份项目桥：crypto、zstd、graphics、cache、file，以及 `zstd.wasm`。WASM 来自 pnpm 精确锁定的 `@bokuweb/zstd-wasm@0.0.27`，构建直接读取该包的 `dist/web/zstd.wasm`，同时检查包名、版本、长度和摘要：

- 长度：251,806 bytes。
- SHA-256：`80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df`。
- 来源与许可见 [运行时 NOTICE](../runtime/teavm/NOTICE.md)；npm tarball 的完整性另由 `pnpm-lock.yaml` 固定。

普通 Web / 原生客户端构建不需要下载包含 JVM 依赖的私有 runtime seed。

```sh
pnpm install --frozen-lockfile
pnpm --filter @karuyomi/runtime-host build
```

运行时构建会生成：

| 输出                                                           | 用途                                                |
| -------------------------------------------------------------- | --------------------------------------------------- |
| `packages/runtime-host/dist/materials.json`                    | 当前材料、Web 兼容材料、来源和 `materialVersion`    |
| `packages/runtime-host/dist/materials/<sha256>`                | Web 静态字节，包含当前 6 份与兼容 2 份              |
| `packages/runtime-host/dist/native/host.js`                    | 原生控制 IIFE                                       |
| `packages/runtime-host/dist/native/worker.js`                  | 原生 Worker；内嵌当前 6 份材料的字节                |
| `packages/runtime-host/dist/native/manifest.json`              | 协议、ABI、材料版本及 host/worker 的 SHA-256 和长度 |
| `apps/reader/assets/runtime/{host.js,worker.js,manifest.json}` | 自动复制的 3 份 Flutter 资源；生成文件不入库        |

原生只打包上述 3 个文件，材料字节只出现在 Worker 中，避免把原始 WASM/桥或第二份 Worker 源重复塞入应用。构建保留资源目录里的 `.gitignore`。

逐包 AOT 构建和注册工具可只读取材料元数据：

```sh
node packages/runtime-host/prepare-materials.mjs --print
```

`--print` 只读取项目桥和固定的 WASM 元数据，不读取 npm WASM 或私有 JVM 材料。实际生成静态字节时使用 `--output DIR`；该模式会检查安装的 npm 包和 WASM。

`materialVersion` 覆盖协议/ABI、当前材料与兼容材料的路径、摘要、大小和 MIME。它描述客户端材料集合；扩展构建另外绑定自己的输入身份和 bundle 摘要。

## Web 加载契约

新扩展清单的 `hostScripts` 和 `resources` 引用 `/runtime/materials/<sha256>`，`bundle` 仍引用 `/api/extensions/artifacts/<sha256>`。Web loader 对材料使用同源静态请求、`credentials: omit` 与可缓存的内容寻址 URL，并验证实际字节；扩展 bundle 和清单仍走已鉴权的私有交付。

`scripts/assemble-assets.mjs` 将材料复制到 Web 静态目录，合并 `_headers`，为无扩展名的哈希文件设置正确 `Content-Type`、`nosniff` 和一年 immutable 缓存。`materials.json` 使用 `no-cache`。原生构建目录不复制到公开 Web 目录。Flutter Web 还会按 pubspec 将原生资源复制到 `assets/assets/runtime/`；组装时同时排除这一份（包括 `.gitignore`），Web 代码不读取该目录。脚本递归检查实际公开文件树，并比对原生 host、worker、manifest 的完整字节摘要，防止它们以其他文件名进入静态产物。

历史 e350 清单中的共享材料仍写作私有路径。loader 会从路径取出已声明摘要，再读取同摘要的静态材料；它不会为了旧清单重新下载私有共享材料。私有扩展 bundle 的加载规则不变。

## 原生页面与 Worker 契约

原生容器使用同源 HTTPS `/runtime/host.html`（同时接受 Cloudflare 规范化后的 `/runtime/host`），保留该 WebView 的 Access cookie 与 API 请求上下文。Dart 从应用资源读取清单，验证协议/ABI、host 和 worker 的长度/摘要，再在 document start 的页面 world 中注入：

```js
window.__karuyomiNativeRuntime = { workerSource, materialVersion };
// 随后执行已验证的 host.js IIFE。
```

注入仅在配置的部署 origin 和控制页路径生效。Native host 再检查 HTTPS、上述两个控制页路径和编译绑定的材料版本，消费后删除配置。控制页发现已有 `window.karuyomiRuntime` 后跳过远程 Web host 脚本。

SourceRuntimeManager 继续计算身份、仓库、包与存储 schema 的命名空间。Native host 把受校验的 origin、plugin 和 fsNamespace 放进 Blob Worker 的 `karuyomiWorkerContext`；当前 cache/file 桥读取该上下文。Worker 首次响应、错误或终止时释放启动 Blob URL。

Native material resolver 从内置数据返回独立字节，loader 仍验证长度、摘要和 MIME。材料不存在时返回 `unsupported_capability`，提示更新应用；没有共享材料的网络回退。私有清单、扩展 bundle 和 Source 网络仍经同源已鉴权通道。

## 兼容保留策略

当前 Web 共保留 8 份材料：当前 6 份，加上 `bridge/compat/release9-v1/` 的旧 cache/file 两份，供已经发布的 e350 清单使用。旧文件必须保持逐字节不变：

| 旧材料 | SHA-256                                                            |
| ------ | ------------------------------------------------------------------ |
| cache  | `d48b31850eca8b4ac588e7385dba9ac54dd0e189f36627b650fec336ea02c06e` |
| file   | `5fceb245573118980385044c4025100da5f4fdf9466d6f62dff52685e9672518` |

这两份旧桥只读取 Worker URL 查询参数，在 Blob Worker 内会落入默认命名空间。因此原生不内置它们，并针对这两个摘要明确返回 `unsupported_capability`，提示升级扩展构建；不能静默使用默认命名空间。原生清单列出 6 份支持材料和 `unsupportedMaterialHashes`。

已发布构建仍受支持期间，不能删掉它所引用的静态哈希文件。更换当前桥时，应先保留上一份准确字节并加入兼容 catalog，再发布引用新摘要的构建；不能用新内容覆盖旧哈希 URL。退役材料需要明确退出相应构建的支持范围，不能仅因它不再属于当前 5 份桥就自动清理。Native 新版本是否携带旧材料须单独判断其存储和 ABI 语义；缺少新材料的旧应用明确提示升级。

## 验证范围

```sh
pnpm exec vitest run packages/runtime-host/test/materials.test.ts
pnpm --filter @karuyomi/runtime-host typecheck
```

材料回归核对 npm WASM 的精确身份、metadata-only 与完整 catalog 一致、8 份 Web 文件摘要、Native 返回字节的独立所有权，以及旧材料/缺失材料不发起网络请求。真实原生 HTTPS、登录 cookie、Worker 初始化与恢复需要独立容器验证。材料加载通过不代表 Source 在线语义、图片通道或完整阅读已通过。
