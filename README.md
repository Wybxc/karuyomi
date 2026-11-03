# Karuyomi

个人漫画阅读应用。Flutter + TeaVM 浏览器宿主，Cloudflare Workers 后端。

当前为项目脚手架；已迁入[完整计划](docs/PLAN.md)。应用只展示书架、浏览、设置空态，尚未支持真实漫画源或在线阅读。

## 工程结构

```text
apps/reader/            Flutter Web / iOS / Android 应用
apps/api/               Hono 入口、Access 校验、D1 / R2 / DO bindings
packages/reader_core/   独立 Dart 阅读位置、PageProvider 与图片资源契约
packages/source_runtime/ Dart SourceRuntime 接口与共享协议版本
packages/contracts/    Zod 边界校验与协议版本源文件
packages/runtime-host/ 公开控制页、Worker 引导与握手
scripts/               协议生成、Flutter 命令及静态资源组装
docs/design/           五份设计文档及来源校验记录
```

## 本地开发

需要 Node 24 LTS（`.node-version`）、pnpm 12.6.0、Flutter 3.47.5（`.fvmrc`）。可用 FVM 安装 Flutter，或将固定版本加入 PATH；也支持 `FLUTTER_ROOT=/path/to/flutter`。原生构建另需 Xcode / Android SDK。TeaVM 的 Java/Maven 工具链将在 P0-A 导入冻结宿主时配置。

```sh
pnpm install --frozen-lockfile
pnpm flutter:setup
pnpm check
pnpm flutter:check
pnpm build
pnpm db:migrate:local
pnpm dev
```

打开 Wrangler 输出的本地地址即可访问同源 Flutter Web 和 `/runtime/host.html`。先执行 `pnpm build` 创建静态目录；重新修改 Flutter 或 JS 宿主后再次构建。`pnpm dev:flutter` 提供 Flutter Chrome 热重载，用于独立 UI 开发；Access 联调使用同源 Wrangler / HTTPS 环境。

`pnpm build` 依次构建公共 JS 宿主、Flutter Web、`dist/public`，然后执行 Wrangler dry-run，仅生成本地部署产物。Web 渲染资源随产物提供。当前不注册 Service Worker，不缓存 API、登录响应或私有扩展。

修改 `packages/contracts/protocol.json` 后执行 `pnpm generate`，同时更新 TypeScript 和 Dart 常量；CI 的 `generate:check` 防止版本漂移。完整业务 DTO 和图片帧协议在 P0 中继续定义，当前不声称已完成跨语言 DTO 生成。

## Access 与部署准备

`/api` 和 `/api/*` 始终经过 Worker JWT 校验；未配置时返回 503，缺 JWT 返回 401，验签或身份失败返回 403。没有开发鉴权绕过。公开 shell 不读取私有 bindings。可复制 `apps/api/.dev.vars.example` 为忽略提交的 `.dev.vars` 进行 Access 联调。

部署前须完成：

1. 创建 D1、私有 R2，替换 `apps/api/wrangler.jsonc` 的全零数据库 ID；为 Worker 绑定自有 hostname。
2. 创建一个 Access self-hosted application，同时覆盖裸 `/api` 和 `/api/*`；Allow policy 仅允许本人，启用 HttpOnly Cookie。
3. 设置 `ACCESS_TEAM_DOMAIN`、`ACCESS_AUD`、`ACCESS_SUBJECT`。Subject 为已验证 JWT 的本人 `sub`，不依赖未验证的邮箱头。不把 JWT、service token 或 Cloudflare 凭证写入静态资源。
4. 审查并应用正式 D1 迁移；验证真实 HTTPS、Access 登录回跳与路径边界。

Wrangler 已关闭 `workers.dev` 与预览 URL。当前仓库未创建云端资源、未部署；R2 无公网入口。SQLite DO 仅预留运行会话边界，未启动后台任务。数据库初始迁移只有工程元信息表，业务表随功能契约引入。

## 下一阶段

优先执行 [P0-F 接入验证](docs/design/flutter-teavm-integration.md#9-实施验证次序) 与 P0-R 阅读器基线，并从冻结 release9 建立 P0-A 工作副本。JS 握手成功仅说明 Worker 控制链可用；原生 WebView、Access 会话、iOS 图片交付和真实源完整阅读仍须分别验证。

脚手架实现参考：[Flutter 创建工程](https://docs.flutter.dev/reference/create-new-app)、[Workers 静态资源路由](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/)、[Hono Workers](https://hono.dev/docs/getting-started/cloudflare-workers)。
