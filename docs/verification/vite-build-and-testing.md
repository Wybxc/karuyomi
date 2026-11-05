# Vite 与 Cloudflare 官方集成验证

2026-11-05，本地 macOS、Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。构建依赖固定为 Vite 8.3.6、Cloudflare Vite 插件 1.67.0 和官方 Vitest 插件 1.6.0，锁文件保留精确传递依赖。产品 Wrangler 4.156.1 与既有 D1 JSON 输出补丁保持原版本。

## 工程与产物

- `pnpm check` 完整通过，含生成一致性、严格类型检查、依赖层级、369 项 Vitest 测试、跨语言 golden、扩展流水线、HTTP 桥及候选图片工具测试。新增 API 配置、Workers 测试和官方 harness 均进入类型检查；依赖检查覆盖 212 模块、788 条依赖。
- `pnpm flutter:check` 三项目静态分析与测试通过，分别为 21、42、220 项。`pnpm format` 后完整 `pnpm format:check` 通过，包含原生格式检查。
- `pnpm build` 完整通过：Vite 宿主 → Native 材料组装 → Flutter Web → 静态组装 → Cloudflare Vite Worker/client 构建。本次为开发空扩展索引，组装检查 55 个文件，确认 Native payload 未进入公开树；没有部署空索引或替换生产快照。
- 正式 `wrangler deploy --dry-run` 使用 `apps/api/.wrangler/deploy/config.json` 重定向到 `dist/karuyomi/wrangler.json`，识别相邻 `dist/client` 以及 ASSETS、D1、Durable Object、既定 vars 和域名。输出文件与输入静态树逐项核对，额外文件仅为插件生成的 `.assetsignore`。

## 正式测试集成

`apps/api/vitest.config.ts` 使用官方 `cloudflareTest()`，测试直接在 workerd 中访问 `cloudflare:workers` 和 `cloudflare:test`，通过官方 D1 migration API 应用正式迁移。15 项业务测试全部通过；移开尚未构建的 `dist/public` 后独立重跑也通过，测试不依赖上次前端构建。

`apps/api/test/vite-harness.test.ts` 使用官方 `createTestHarness()` 运行 Cloudflare Vite 的生成配置，实际验证复制后的静态字节、`_headers`、静态路径绕过 Worker、host.html 的既有 307 路由、匿名 API 401、真实 RS256 身份及 D1 目录读取。生成的迁移目录可定位并应用。隔离构建前后，正式部署重定向字节保持不变。静态请求通过 harness server，API 通过其官方 Worker handle 保持原始 Host 检查。

HTTP v2 专项使用同一 Cloudflare Vite 配置构建测试 API，24 项受控 HTTP 检查通过，包含压缩字节、Range/表单、上传、截断、超时与取消/TCP reset。此专项保留 Miniflare 的原生用户 Worker socket 和受控 outbound service：官方普通请求代理不能代替这里的连接关闭证据。没有保留自有 esbuild 打包入口。

## 宿主与浏览器

Web host 保持 ESM，独立 Worker 保持 classic IIFE；Native host/Worker 内嵌全部 6 份共享材料，manifest 的大小与哈希匹配。Vite 资产转换前替换桥的 `import.meta.url`，避免将 zstd WASM 再次内联到桥中。仓库根与包目录执行得到相同材料身份；新 `materialVersion` 为 `97334724ed5cfd0b688d10c82f219893442260986c77b6ea1a4ce4a4e959a4ff`。

Codex 内置浏览器 Chrome 156 实际运行 Vite 构建的 Cache bridge/Worker/suite，39 项检查全部通过，覆盖真实 IndexedDB、Web Locks、owner 死亡、并发/CAS、限额、事务失败和二进制 reader 生命周期。报告保留在忽略目录 `.local/vite/cache-browser.json`，测试服务正常退出。

图片 Worker/Owners prepare-only、TeaVM enqueue build-only、扩展动态 runner 构建/HTTP 交付已通过；这些分项未重跑完整浏览器断言。构建工具与材料变化已进入 AOT host/input 身份，旧材料产物不能混入新快照。未重启全量 AOT、未启用扩展 CI，也未将历史 Source、生产 Access 或 Native/真机证据提升为新工具链下的完整验收。
