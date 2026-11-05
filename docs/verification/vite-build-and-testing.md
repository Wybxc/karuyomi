# Vite 与 Cloudflare 官方集成验证

## 删除未采用的候选 codec（2026-11-05）

`runtime/image-codec`、`tools/images`、专属脚本与 Vite 配置已删除，同时移除 libspng/libjpeg-turbo submodule、sharp 与无调用的 undici 直接依赖。Dart、Native 与正式控制协议不依赖该候选；默认图片路径继续由 UI 直接解码。Source 主动执行的 Android 图片处理仍保留。

最终默认 `pnpm build` 已通过，正式 catalog 只描述五桥与 zstd WASM；闲置候选字段已移除。新 materialVersion 为 `6175132a0e80c94491ab708894dac63d08c4e02b4507b9686b111de84339a839`，六材料实际大小和 SHA 匹配。版本变化来自清单元数据简化，不能沿用前一阶段的 materialVersion。忽略缓存移到 `.local/retired-image-codec-cache`，源码目录已不存在。

以下 `a2251a6` 阶段的集中工程检查和 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42045547601) 已通过；它的独立候选构建记录是删除前的历史证据。当前清理后的 `pnpm check` 完整通过（359 项 Vitest；依赖检查覆盖 151 模块、490 条依赖），包含跨语言 golden、AOT 流水线/runner/完整性、上游补丁和 Cloudflare 工具回归。完整 `pnpm format` → `pnpm format:check`、默认 `pnpm build`、Wrangler 本地部署预演及 peer 检查通过。不将历史候选结果当作产品能力。

## 声明式重构：a2251a6（2026-11-05）

当前重构删除自有程序化 Vite builder、`materials.ts` 资源管理层、独立资产组装入口、手写测试服务器与浏览器 runner。资源生成与 Native 内嵌由 Vite 插件实现，工具只直接读取生成清单；静态扩展装配也内化为 API Vite 插件的一部分。本地集中验收已通过，环境为 macOS、Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。以下分项已实际运行：

- `pnpm test:build` 使用官方 Vite CLI，依次生成共享材料、Web/Native runtime、API 静态夹具；候选 codec JS 保留独立声明式构建入口。无测试内调用 Vite build。
- `pnpm exec vitest run --project workers`：HTTP 21 项与状态 15 项，共 36/36。官方 Workers 插件、正式 D1 migrations、RS256 JWT 与 `@msw/cloudflare`；gzip 为真实压缩字节，Brotli 仅为已解码边界。消费者取消与 deadline 中止模拟 upstream 已验证，不宣称真实 TCP reset 或 incoming socket abort。
- 官方 `createTestHarness`：声明式生成配置的两项测试通过，覆盖静态字节、headers、Worker 绕过、307、401、JWT 与 D1。
- 官方 Vitest Browser：Codex 内置浏览器实际打开官方生成的 session URL，7/7 通过，覆盖 IndexedDB、Web Locks、真实 Worker 生命周期、文件句柄和 OffscreenCanvas。`BROWSER=none` 固定在配置；之前误由默认浏览器执行的结果不计入本轮 IAB 证据。runner 已结束，临时日志在忽略目录 `.local/verification/vitest-browser-2026-11-05.log`。

- `pnpm check` 完整通过：386 项 Vitest、跨语言 golden、扩展发现/runner/完整性、上游补丁、Cloudflare 权限工具与候选 codec 回归；严格类型及依赖检查覆盖 179 模块、595 条依赖。冻结 builder 新回归确认材料先准备且同 checkout 只准备一次。
- `pnpm flutter:check` 三项目静态分析和测试通过（21/42/220）；完整 `pnpm format` → `pnpm format:check` 通过，包含原生语言。peer 依赖检查无冲突。
- 最终 `pnpm build` 完整通过。API 的 `sharedConfigBuild: true` 确保静态组装 hook 仅执行一次；57 份输入静态文件与 client 输出逐字节一致，额外仅 `.assetsignore`。Native payload 排除验证通过。开发输入为空扩展索引，未上传或覆盖生产快照。
- 最终无 `--config` 的 `wrangler deploy --dry-run` 使用正式 Vite 配置重定向；Static Assets、D1、Durable Object、域名及迁移目录定位正确。本地 D1 migrations 成功。测试构建前后生产重定向 SHA 不变。
- Vite 插件重构前后六材料与 catalog 字节一致，materialVersion 保持 `97334724ed5cfd0b688d10c82f219893442260986c77b6ea1a4ce4a4e959a4ff`。Native manifest 的实际脚本 hash/size 与内嵌六材料由产物测试验证；contracts 声明 `sideEffects: false` 以避免未使用 schema 初始化进入宿主。

本轮删除旧 Source/HTTP/socket/static/cache 探针及独立浏览器 suites；历史专项记录保留对应提交与执行环境，不作为当前可复验入口。扩展完整性工具继续输出 `compiled_unverified` / `runtimeReady=false`，不把已删除动态 runner 的构建结果当作运行通过。

## 历史迁移：f623a82

以下为程序化 Vite 初次迁移的历史证据。后续声明式重构已删除其 probe builder、HTTP socket 专项与浏览器 runner；测试数和复验入口只适用于 [f623a82](https://github.com/Wybxc/karuyomi/tree/f623a82)。

2026-11-05，本地 macOS、Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。构建依赖固定为 Vite 8.3.6、Cloudflare Vite 插件 1.67.0 和官方 Vitest 插件 1.6.0，锁文件保留精确传递依赖。产品 Wrangler 4.156.1 与既有 D1 JSON 输出补丁保持原版本。

### 工程与产物

- `pnpm check` 完整通过，含生成一致性、严格类型检查、依赖层级、369 项 Vitest 测试、跨语言 golden、扩展流水线、HTTP 桥及候选图片工具测试。新增 API 配置、Workers 测试和官方 harness 均进入类型检查；依赖检查覆盖 212 模块、788 条依赖。
- `pnpm flutter:check` 三项目静态分析与测试通过，分别为 21、42、220 项。`pnpm format` 后完整 `pnpm format:check` 通过，包含原生格式检查。
- `pnpm build` 完整通过：Vite 宿主 → Native 材料组装 → Flutter Web → 静态组装 → Cloudflare Vite Worker/client 构建。本次为开发空扩展索引，组装检查 55 个文件，确认 Native payload 未进入公开树；没有部署空索引或替换生产快照。
- 正式 `wrangler deploy --dry-run` 使用 `apps/api/.wrangler/deploy/config.json` 重定向到 `dist/karuyomi/wrangler.json`，识别相邻 `dist/client` 以及 ASSETS、D1、Durable Object、既定 vars 和域名。输出文件与输入静态树逐项核对，额外文件仅为插件生成的 `.assetsignore`。

### 正式测试集成

`apps/api/vitest.config.ts` 使用官方 `cloudflareTest()`，测试直接在 workerd 中访问 `cloudflare:workers` 和 `cloudflare:test`，通过官方 D1 migration API 应用正式迁移。15 项业务测试全部通过；移开尚未构建的 `dist/public` 后独立重跑也通过，测试不依赖上次前端构建。

`apps/api/test/vite-harness.test.ts` 使用官方 `createTestHarness()` 运行 Cloudflare Vite 的生成配置，实际验证复制后的静态字节、`_headers`、静态路径绕过 Worker、host.html 的既有 307 路由、匿名 API 401、真实 RS256 身份及 D1 目录读取。生成的迁移目录可定位并应用。隔离构建前后，正式部署重定向字节保持不变。静态请求通过 harness server，API 通过其官方 Worker handle 保持原始 Host 检查。

HTTP v2 专项使用同一 Cloudflare Vite 配置构建测试 API，24 项受控 HTTP 检查通过，包含压缩字节、Range/表单、上传、截断、超时与取消/TCP reset。此专项保留 Miniflare 的原生用户 Worker socket 和受控 outbound service：官方普通请求代理不能代替这里的连接关闭证据。没有保留自有 esbuild 打包入口。

### 宿主与浏览器

Web host 保持 ESM，独立 Worker 保持 classic IIFE；Native host/Worker 内嵌全部 6 份共享材料，manifest 的大小与哈希匹配。Vite 资产转换前替换桥的 `import.meta.url`，避免将 zstd WASM 再次内联到桥中。仓库根与包目录执行得到相同材料身份；新 `materialVersion` 为 `97334724ed5cfd0b688d10c82f219893442260986c77b6ea1a4ce4a4e959a4ff`。

Codex 内置浏览器 Chrome 156 实际运行 Vite 构建的 Cache bridge/Worker/suite，39 项检查全部通过，覆盖真实 IndexedDB、Web Locks、owner 死亡、并发/CAS、限额、事务失败和二进制 reader 生命周期。报告保留在忽略目录 `.local/vite/cache-browser.json`，测试服务正常退出。

图片 Worker/Owners prepare-only、TeaVM enqueue build-only、扩展动态 runner 构建/HTTP 交付已通过；这些分项未重跑完整浏览器断言。构建工具与材料变化已进入 AOT host/input 身份，旧材料产物不能混入新快照。未重启全量 AOT、未启用扩展 CI，也未将历史 Source、生产 Access 或 Native/真机证据提升为新工具链下的完整验收。
