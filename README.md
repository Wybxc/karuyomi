# Karuyomi

个人漫画阅读应用。Flutter + TeaVM 浏览器宿主，Cloudflare Workers 后端。

项目正在实施 [P0](docs/PLAN.md)，已部署到 [karuyomi.wybxc.cc](https://karuyomi.wybxc.cc)。已内化 TeaVM 运行时并构建真实 MangaDraft AOT 包，具备私有产物交付、JS / Dart 运行接口、漫画资料浏览界面和独立阅读器。真实浏览器已通过 Source 初始化；产品图片通道与完整在线阅读尚未接通，P0 尚未通过。

## 当前能力与边界

| 范围           | 已实现 / 已验证                                                                                                                           | 尚待完成                                                                      |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| TeaVM 公共宿主 | 固定 TeaVM 0.16.0 JS；按包构建、输入及产物 hash；完整 DTO 与显式漫画/章节引用；真实 MangaDraft Web 初始化；热门/最新/搜索列表返回完整 DTO | 3–5 个原版源完整操作与阅读回归、持久层重启/升级验证                           |
| JS / Dart 接入 | 私有清单及资源执行前校验、串行 Worker、代次隔离、取消/超时回收；Web JS interop 与原生 WebView 控制、可见登录流程                          | 真实域名 Access/cookie 会话、原生容器恢复与真机验收                           |
| 浏览与阅读器   | 构建/Source 选择、热门/最新/搜索分页、详情与章节；单/双页、RTL、竖向/Webtoon、缩放和有界资源调度                                          | 产品图片获取仍明确不支持；章节暂不可读，ReaderScreen 尚未接入实际 Source 导航 |
| API 与私有交付 | JWT 再校验、D1 构建注册、私有 R2 流式产物与 Range/HEAD、按构建域名白名单的 P0-A 网络桥                                                    | 生产 Access 登录与正向私有交付；P0-B 替换文本/Base64 网络正文                 |
| 独立机制探针   | TeaVM 有界字节复制/fiber 取消/ArrayBuffer 所有权；iOS 模拟器 HTTPS 下 Worker → Blob → WKDownload → 文件                                   | 两者尚未汇合为产品图片通道；真实源、物理设备与合计内存峰值未验收              |

`ready.sourceReady: false` 只描述控制握手；`open` 必须在真实宿主初始化、Source 列表与清单一致后才返回运行会话。六个 Java 操作边界为 `popular`、`latest`、`search`、`details`、`chapters`、`pages`；边界与 JVM oracle 通过不代表六项在线 Source 语义均已验收。真实网络探针中热门/最新/搜索返回列表，已核对原版 MangaDraft 普通文本搜索未把关键词加入请求，不能将返回列表当作匹配验收；详情/章节遇到 Source 的 Human Verification 挑战，返回 source_error，未伪造页面结果。验证范围见 [记录](docs/VERIFICATION.md)。

## 工程结构

```text
apps/reader/            Flutter Web / iOS / Android 应用
apps/api/               Hono 入口、Access 校验、D1 / R2 / DO bindings
packages/reader_core/   独立 Dart 布局、位置、资源窗口与调度
packages/source_runtime/ Dart SourceRuntime、版本协议与传输验证
packages/contracts/    Zod 边界校验与协议版本源文件
packages/runtime-host/ 公开控制页、私有 TeaVM 加载与串行 Worker
runtime/teavm/          项目运行时、适配层与构建输入
tools/                 正式回归测试与扩展发布工具
scripts/               协议生成、构建、私有产物注册与资源组装
docs/design/           五份设计文档及来源校验记录
docs/verification/     精简验证结论与正式复验入口
```

## 本地开发

需要 Node 24.15.0（`.node-version`）、pnpm 12.6.0、Flutter 3.47.5（`.fvmrc`）。可用 FVM 安装 Flutter，或将固定版本加入 PATH；也支持 `FLUTTER_ROOT=/path/to/flutter`。原生构建另需 Xcode / Android SDK。TeaVM 工具链与依赖材料由锁文件固定；历史验证使用 JDK 25.0.4、Maven 3.9.11；当前构建与校验见 [运行时说明](runtime/teavm/README.md)。

```sh
pnpm install --frozen-lockfile
pnpm flutter:setup
pnpm hooks:install
pnpm check
pnpm flutter:check
pnpm build
pnpm db:migrate:local
pnpm dev
```

打开 Wrangler 输出的本地地址即可访问同源 Flutter Web 和 `/runtime/host.html`。先执行 `pnpm build` 创建静态目录；重新修改 Flutter 或 JS 宿主后再次构建。`pnpm dev:flutter` 提供 Flutter Chrome 热重载，用于独立 UI 开发；Access 联调使用同源 Wrangler / HTTPS 环境。

`pnpm build` 依次构建公共 JS 宿主、Flutter Web、`dist/public`，然后执行 Wrangler dry-run，仅生成本地部署产物。Web 渲染资源随产物提供。当前不注册 Service Worker，不缓存 API、登录响应或私有扩展。

提交前运行 `pnpm format` 与 `pnpm hooks:check`。prek 0.5.9 由 pnpm 精确锁定，统一检查 Java、Dart、JS/TS、Python、Kotlin、Swift、Objective-C、Ruby、SQL 与 XML；工具版本和源码范围见 [提交要求](AGENTS.md)。完整原生格式检查需要 macOS / Xcode，Ubuntu CI 显式运行 portable 检查。

修改 `packages/contracts/protocol.json` 后执行 `pnpm generate`，同时更新 TypeScript 和 Dart 常量；CI 的 `generate:check` 防止版本漂移。控制协议、清单与 Source 调用已经接通；完整 DTO 的跨语言代码生成与图片字节协议仍需继续实现。

## 本地 TeaVM 构建与回归

项目维护正式 Java / bridge 源码，第三方源码通过 submodule 固定；TeaVM 派生实现由上游加补丁物化。工具链、runtime seed 和隔离产物位于被忽略的 `runtime/teavm/.local/`，正式构建不依赖研究 ZIP。完整本地批量构建与增量发布见 [扩展发布说明](docs/EXTENSIONS.md)。

```sh
git submodule update --init --recursive
pnpm teavm:prepare --android
pnpm teavm:check
pnpm teavm:build --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
python3 scripts/register-build.py PATH_TO_OUTPUT/manifest.json --artifacts PATH_TO_OUTPUT/artifacts --allow-host www.mangadraft.com
```

注册命令默认仅校验并输出计划；加 `--local` 才写入本地 R2 / D1，加 `--remote` 才写入云端。网络域名需要显式声明，图片 CDN 尚未据此开放。清单与 AOT 经私有 API 获取；共享桥/WASM 使用 Web 静态或 Native 内置材料，见 [交付契约](docs/RUNTIME-MATERIALS.md)。正式 API 与 Source 浏览器回归入口见 [验证记录](docs/VERIFICATION.md)。独立字节、Zstd 和 iOS 机制研究保留简洁验证摘要；临时工程已归档到被忽略的本地研究目录，不作为源码提交。

## 部署与 Access

2026-11-03 已部署 `karuyomi.wybxc.cc`，Worker version 为 `0332ef7a-3d49-47c1-ac41-edbed49bd7fe`；云端 D1 迁移完成，MangaDraft e350 构建的 7 个产物已注册为 verified。公开 Flutter 页面与运行脚本可访问，Safari 已真实渲染书架和三个主导航页签。Access self-hosted application 与仅允许本人的策略同时覆盖裸 `/api` 和 `/api/*`；匿名 API 请求已确认跳转登录并保持 private/no-store。生产 Access 登录成功后的正向私有交付尚未验收。

`/api` 和 `/api/*` 始终经过 Worker JWT 校验；未配置或密钥服务不可用返回 503，缺少、无效或过期凭据返回 401，身份或 origin 拒绝返回 403。没有开发鉴权绕过。写请求要求同源 `Origin` 和应用请求头；公开 shell 不读取私有 bindings。可复制 `apps/api/.dev.vars.example` 为忽略提交的 `.dev.vars` 进行 Access 联调。

部署后继续核验：

1. 保持 `apps/api/wrangler.jsonc` 的 D1 / 私有 R2 bindings、迁移、`APP_ORIGIN` 与已绑定域名一致。
2. 复核已创建的 Access 应用双路径与本人 Allow policy、HttpOnly Cookie、固定回跳及失效行为。
3. 设置 `ACCESS_TEAM_DOMAIN`、`ACCESS_AUD`、`OWNER_EMAIL`。`ACCESS_SUBJECT` 可进一步固定已验证 JWT 的本人 `sub`；邮箱约束同样只读取已验签的声明，不信任邮箱头。不把 JWT、service token 或 Cloudflare 凭证写入静态资源。
4. 验证生产 Access 登录成功后的 bootstrap、私有清单/产物与会话失效；继续原生恢复和 Source 完整操作验收。

Wrangler 已关闭 `workers.dev` 与预览 URL；R2 不提供公网正文入口。D1 已定义构建、产物、关联和允许网络域名的注册表；书架、进度和同步业务存储尚未实现。SQLite DO 保留运行会话边界，未启动后台任务。

## 后续工作

按 [完整计划](docs/PLAN.md) 继续 P0-B 分帧二进制 HTTP/Okio 桥、P0-F 原生资源插件与 Access 会话验证，再在 P0-C 汇合真实 Source 图片和完整阅读。P1 的书架/进度持久化、P2 同步、P3 扩展升级/迁移、P4 覆盖与性能工作继续保留，不以独立探针通过替代产品验收。

脚手架实现参考：[Flutter 创建工程](https://docs.flutter.dev/reference/create-new-app)、[Workers 静态资源路由](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/)、[Hono Workers](https://hono.dev/docs/getting-started/cloudflare-workers)。
