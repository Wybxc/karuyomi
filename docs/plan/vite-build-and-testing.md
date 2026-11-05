# Vite 构建与 Cloudflare 官方测试集成

## 目标与状态

状态：**已验收，迁移与集中工程检查通过**。用户要求将项目自有 esbuild 调用迁移到 Vite，并将 Workers 集成测试接入 Cloudflare 官方 Vitest 插件。保留 Flutter/Dart、TeaVM 与 Static Assets 的既定架构；构建成功不能替代 Source、生产 Access 或三端同步验收。

正式 API 使用 `apps/api/vite.config.ts` 和 Cloudflare Vite 插件，入口与绑定继续由 `apps/api/wrangler.jsonc` 定义；Workers 集成测试使用 `apps/api/vitest.config.ts` 和 Cloudflare 官方 Vitest 插件。独立 API 探针通过 `apps/api/test/probe-build.ts` 使用同一 Vite 配置构建专用夹具。实际工程、部署 dry-run、官方 harness 与内置浏览器 Cache 证据见[验证记录](../verification/vite-build-and-testing.md)。其它 Source、生产 Access、Native 和真机验收仍按各自计划推进。

## 构建与部署合同

- 仓库 `pnpm build` 保持依赖顺序：runtime-host → Native 资源组装 → Flutter Web → `scripts/assemble-assets.ts` → API Vite 构建。资源组装仍负责当前扩展快照、共享材料、MIME/缓存规则与 Native 资源排除。
- API Vite 的 `publicDir` 必须明确指向已组装的仓库 `dist/public`，再由 Vite 复制到客户端输出。仅在输入 Wrangler 配置中保留 `assets.directory` 不足以让插件构建客户端：客户端未构建时，Cloudflare 插件会移除生成配置的 `assets`。
- 正式产物使用 Cloudflare 插件生成的 Worker 配置及相邻客户端目录。不得继续把旧的平铺 `apps/api/dist/index.js` 当作产物入口。生成配置须保留 `ASSETS`、`run_worker_first`、404 行为、D1、Durable Object 和自定义域名，并使 `migrations_dir` 相对新输出位置正确定位。
- 正式构建在 `apps/api/.wrangler/deploy/config.json` 生成配置重定向。`.github/workflows/extensions.yml` 先执行 `pnpm build`，再从 `apps/api` 执行不带 `--config` 的 `wrangler deploy`，会使用这个生成配置；部署前必须确认重定向确实来自本次正式构建。显式传入源码 `wrangler.jsonc` 会绕过重定向，不作为部署修复方式。
- D1 迁移和网络策略命令继续使用源码配置中的绑定与迁移定义；它们不承担 Worker 打包。独立 Cloudflare 权限探针使用临时目录和显式临时配置，不依赖正式产物的重定向。

## 测试隔离与依赖边界

- API 探针以独立临时目录作为 Vite `root`，同时隔离 `outDir` 与 `.wrangler/deploy/config.json`；只改变 `outDir` 不能隔离配置重定向。测试入口、公钥与测试绑定不进入生产构建。
- 官方 Workers 测试关闭远程 bindings，在 workerd 中应用正式 D1 迁移并验证受信 JWT、条件写入、幂等重试及事务失败。Node 单元测试与 Workers 测试在 Vitest projects 中分别选取，避免同一用例在两种环境重复运行。
- `vite.config.ts`、`vitest.config.ts`、独立 probe builder 与 Workers 测试都纳入严格 TypeScript 检查；Vite/Vitest 转译成功不代表类型检查通过。新增配置入口参与依赖层级检查，产品源码继续不得导入探针或工具。
- runtime-host 和浏览器专项工具使用适合各自输出的 Vite 配置；TypeScript 类型擦除也使用迁移后的工具链。扩展 AOT 的 Java/TeaVM 编译不改为 Vite；第三方工具内部的构建依赖不作为项目自有 esbuild 调用维护。
- Wrangler 的 pnpm patch 只解决 D1 JSON stdout，与 Vite 配置重定向无关。若迁移引起 Wrangler 版本变化，同时更新补丁、精确版本断言、锁文件和工具文档；不能默默丢失 D1 JSON 行为。

## 已完成的迁移与验收

1. 完成 API、runtime-host、浏览器专项工具和 API 探针的 Vite 迁移，核对所有旧入口与产物读取位置。
2. 补齐正式静态目录接入及干净输出检查，确认扩展 workflow 的部署配置包含完整静态资源。保留首次 baseline 保护与停用状态，不因工具迁移自动启用定时构建。
3. 将新增配置与 Workers 测试的 TypeScript 检查接入 `pnpm typecheck`，使现有 CI 的 `pnpm check` 实际执行这些检查。
4. 隔离构建和正式构建均通过；官方 harness 实测隔离构建不修改正式部署重定向，正式 build/dry-run 确认生成配置与静态目录正确。
5. 执行正式 `pnpm build` 和无凭据的 Wrangler deployment dry-run，核对生成 Worker、Static Assets、迁移目录及路由；检查 `_headers`、扩展索引/清单/gzip 和 Native 排除规则。
6. 单元、官方 Workers/harness、HTTP 流式探针、依赖与完整格式检查通过。专项真实浏览器仅重跑 Cache 门，其它工具的 build-only/prepare-only 与剩余运行门如实记录。

## 验收条件

- 项目自有调用不再直接使用 esbuild；API、宿主与浏览器工具的真实构建或对应回归通过，输出合同保持当前设计。
- 全新 checkout 使用锁定依赖完成 `pnpm check`、`pnpm flutter:check` 和 `pnpm build`；Workers 测试及新增构建配置确实经过严格类型检查。
- 正式生成配置包含预期绑定与完整静态资源，`wrangler deploy --dry-run` 使用本次 Vite 产物，不重新部署源码入口或测试夹具。
- 临时构建不污染 `apps/api/.wrangler/deploy/config.json`，测试不访问远程 D1 或真实 Access 服务；临时资源正常释放。
- 扩展发布仍只在部署确认后提交 checkpoint；CI 不因迁移绕过本地 baseline、预算、单发布者或凭据隔离规则。
