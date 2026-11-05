# Vite 构建与 Cloudflare 官方测试集成

## 目标与状态

状态：**已验收，声明式构建与官方测试集中检查通过**。按用户要求删除程序化 Vite builder、独立资源组装脚本和不适合官方集成的旧测试；必要断言迁入官方 Workers、Wrangler harness 与 Vitest Browser。Flutter/Dart、Java/TeaVM 仍使用各自正式工具链。

当前实现和实测范围见[验证记录](../verification/vite-build-and-testing.md)。Source 在线行为、生产 Access、Native 与三端同步仍按各自计划验收。

## 构建合同

- `pnpm build` 声明依赖顺序：runtime materials → Web/Native runtime → `cpy-cli` 复制 Native 资源 → Flutter Web → API Vite。Vite 默认 app builder 根据 `environments` 构建；项目不调用 `build()`、`createBuilder()` 或自定义 `buildApp`。
- `packages/runtime-host/vite.materials.config.ts` 声明五个 classic bridge，插件输出六份共享材料及 catalog；`vite.config.ts` 声明 Web ESM host、classic Worker 和内嵌材料的 Native host/Worker，并输出 Native manifest。资源生成与 Native 内嵌全部集中在 Vite 插件，已删除 `materials.ts` 及其收集/复制 API。AOT 和分发消费者直接读取 Vite 生成的 JSON，并使用 contracts 的纯 schema 验证。
- 未采用且缺少性能依据的图片 codec 候选源码、专属工具与 Vite 配置已删除；当前构建只包含产品实际使用的资源。Java/TeaVM 编译继续由其正式工具链处理。
- API 使用 Cloudflare 官方 Vite 插件。`vite.assets.ts` 只在正式构建的 Vite hook 中组合 Flutter、runtime 与当前扩展快照、生成 `_headers` 并验证 Native 排除；不存在独立资源组装入口。
- 正式 `publicDir` 指向仓库 `dist/public`。部署使用插件生成的 `dist/karuyomi/wrangler.json` 与相邻 `dist/client`，保留 ASSETS、路由、D1、Durable Object 与正确的迁移目录。
- workflow 在完整 `pnpm build` 后从 API 目录执行无 `--config` 的 `wrangler deploy`，读取本次正式 `.wrangler/deploy/config.json`。源码配置仍用于 D1 命令；不显式绕过生成产物重定向部署。

## 官方测试与隔离

- `pnpm test` 先经 CLI 声明式构建测试依赖，再执行 Node 与 Workers 两个 Vitest project；不在测试中程序化构建 API。`vite.test.config.ts` 以固定受控夹具目录为 root，生成配置和部署重定向与正式构建隔离。
- 官方 Workers 插件直接使用 workerd、正式 D1 migrations 与验签 JWT；HTTP upstream 使用官方推荐的 `@msw/cloudflare`。静态路由、复制字节、headers 和生成迁移路径由官方 `createTestHarness` 检查。
- `pnpm test:browser` 使用官方 preview provider；Vite 直接处理 TS 和 Worker 入口，Comlink 连接测试 Worker。配置固定 `BROWSER=none`；从官方生成的 session URL 在 Codex 内置浏览器运行。真实 IndexedDB、Web Locks、Worker 生命周期、文件句柄和 OffscreenCanvas 均通过该入口。
- 删除旧 Miniflare socket/HTTP origin 探针、独立 Source/static/cache 探针和手写浏览器 suite/runner；不为它们保留特殊 builder。真实 Source、TCP 连接关闭、网络 Brotli 与真机行为不能由 MSW 或构建替代。
- 配置、插件与测试均参与严格类型与依赖检查。生成模型、业务预算和 runtimeReady 门不因工具迁移放宽。

## 待办与验收条件

- [x] 删除旧 builder、组装脚本、浏览器 runner 及孤立 fixture，核对调用与文档。
- [x] 清理未采用的图片 codec 候选源码、专属工具、配置及闲置 catalog 字段，保留固定版本历史结论和真机测量门。
- [x] Workers HTTP/状态测试和官方 harness 实测通过。
- [x] 内置浏览器通过新版官方 Browser 测试；关闭临时测试服务。
- [x] 完整格式、`pnpm check`、`pnpm flutter:check` 与 `pnpm build` 通过。
- [x] 部署 dry-run 核对本次生成配置、静态目录、迁移与 Native 排除；测试不污染正式重定向。
- [x] 更新准确证据、调用入口与计划。提交使用 main，推送后由仓库 CI 复核。

扩展 workflow 仍遵守本地 baseline、预算、持久增量状态与单发布者规则；本次工具重构不启动全量 AOT 或自动部署开发空索引。
