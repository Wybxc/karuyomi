# Karuyomi

个人漫画阅读应用。Flutter + TeaVM 浏览器宿主，Cloudflare Workers 后端。

多端同步是首要设计目标：同一身份在 Web、iOS、Android 共用 Worker API + D1 的权威业务状态，客户端只保留当前会话状态和可丢弃缓存。收藏与阅读进度已按[同步计划](docs/plan/p2-sync.md)接入业务协议与服务端读写，并行收齐 [P0](docs/plan/p0-runtime-and-reading.md) 的真实阅读、Access 和设备验收；本地业务数据库已移除，实际跨平台闭环仍待验收，分类/书签/同步设置继续推进。各阶段见[计划目录](docs/plan/README.md)。已部署域名为 [karuyomi.wybxc.cc](https://karuyomi.wybxc.cc)，当前代码是否完成线上验收以[验证记录](docs/VERIFICATION.md)为准。

Static Assets 是所有客户端扩展分发的权威来源，每包只部署最新可用构建。客户端刷新静态索引并切换当前版本，不再向 GitHub Release 发布扩展，也不经 Worker/R2 转发扩展正文。共享桥/WASM 在 Web 作为静态资源、Native 随应用打包。动态 Source 网络请求仍经 Access 保护的 HTTP v2 API。

## 当前能力与边界

| 范围           | 已实现 / 已验证                                                                                      | 尚待完成                                            |
| -------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| TeaVM 宿主     | 固定 TeaVM 0.16.0 JS、按包构建、完整 DTO、漫画/章节引用；历史真实 MangaDraft 初始化与列表请求        | 当前 gzip 交付的真实 AOT 验收、多源操作与持久层回归 |
| JS / Dart 接入 | 静态索引/清单、传输校验、有界解压、串行 Worker、代次隔离、取消和超时；Web interop 与 Native 内置宿主 | 生产 Access 会话、Native 恢复和真机验收             |
| 浏览与阅读器   | 包/Source 选择、热门/最新/搜索分页、详情与章节；单双页、RTL、Webtoon、缩放和有界资源调度             | 产品图片通道与 ReaderScreen 的真实 Source 导航      |
| API            | Access 会话校验、D1 业务同步、统一的 v2 分帧中继；本地真实 workerd 回归                              | 真实 Source/cache 和生产 Access 正向验收            |
| 构建分发       | 最新静态快照、输入指纹增量、失败保留可用成功构建、部署后 checkpoint、缺 baseline CI 保护             | 当前宿主首次本地全量与实际增量部署                  |

`ready.sourceReady: false` 只描述控制握手；`open` 在真实初始化、Source 列表与清单一致后才返回会话。AOT 编译成功保持 `compiled_unverified` / `runtimeReady=false`，不能当作在线兼容。历史 MangaDraft 普通文本搜索未在原 Source 请求中加入关键词；详情/章节遇到 Human Verification。证据与限制见 [VERIFICATION](docs/VERIFICATION.md)。

## 工程结构

```text
apps/reader/             Flutter Web / iOS / Android 应用
apps/api/                Hono、Access 校验、D1 业务 API 与 DO
packages/reader_core/    Dart 布局、位置、资源窗口与调度
packages/source_runtime/ Dart SourceRuntime 与传输验证
packages/contracts/     Zod 边界校验与协议版本源文件
packages/runtime-host/   控制页、TeaVM 加载与串行 Worker
runtime/teavm/           项目运行时、适配层与构建输入
vendor/                  固定提交的第三方 submodule
tools/extensions/        发现、指纹、AOT 与静态快照流水线
scripts/                 协议生成、构建与资源组装
docs/design/             持续维护的设计与来源记录
docs/plan/               分阶段计划与统一索引
docs/verification/       验证结论与复验入口
```

## 本地开发

需要 Node 24.15.0（`.node-version`）、pnpm 12.6.0、Flutter 3.50.0 / Dart 3.14.0（`.fvmrc`）。支持 `FLUTTER_ROOT=/path/to/flutter`；原生构建另需 Xcode / Android SDK。JVM 工具链和依赖由[锁文件与运行时说明](runtime/teavm/README.md)固定。

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

打开 Wrangler 输出的同源地址访问 Flutter Web 和 `/runtime/host.html`。修改 Flutter 或宿主后重新构建；独立 UI 热重载使用 `pnpm dev:flutter`，Access 联调使用同源 HTTPS。

`pnpm build` 构建宿主、Flutter Web、静态目录并执行 Wrangler dry-run，不会部署。默认没有本地扩展快照时生成空开发索引；正式部署必须显式设置 `EXTENSION_ASSETS_DIR`，避免遗漏快照。当前没有注册 Service Worker，客户端重新连接时刷新索引。

提交前先运行 `pnpm format`，再运行 `pnpm format:check` 和适当测试。prek 由 pnpm 精确锁定，完整原生格式检查需要 macOS/Xcode；Ubuntu CI 使用 portable 检查。项目规则见 [AGENTS.md](AGENTS.md)。跨语言消息以 `protocol/` 中的 Protobuf `.proto` 为唯一结构来源；修改后运行 `pnpm generate`，用 `pnpm generate:check` 核对两端生成结果。已有运行时控制合同不等于书架、进度和设置的业务同步合同已经实现。

## TeaVM 与静态扩展

```sh
git submodule update --init --recursive
pnpm teavm:prepare --android
pnpm teavm:check
pnpm teavm:build --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
```

构建输出 gzip、manifest 和 provenance。运行时材料契约见 [RUNTIME-MATERIALS](docs/RUNTIME-MATERIALS.md)，本地首次全量、增量计划、静态部署及恢复命令见 [EXTENSIONS](docs/EXTENSIONS.md)。首次全量只在本地固定 checkout 中运行；CI 每次最多处理有界变化，缺少完整 baseline 时停止。

Source 请求统一经过受 Cloudflare Access 保护的 v2 中继，安装和使用扩展无需登记包或域名。官方 AOT 清单可声明已审核的非敏感设置键；应用按静态元数据同步这些设置。

## 部署与 Access

单 Worker 同源部署。Static Assets 中的扩展和材料路径直接命中静态服务；`/api`、`/api/*` 和实际需要规范化的控制页路径经过 Worker。缺失扩展路径保持 404，不能变成 SPA HTML。

Access 应用和本人 Allow policy 覆盖 `/api` 与 `/api/*`。Worker 验证 Access 签名、issuer 和 AUD，使用已签名的 subject 区分账户；准入名单只在 Access 配置。未配置或密钥不可用返回 503，无效凭据返回 401。可复制 `apps/api/.dev.vars.example` 为忽略的 `.dev.vars` 进行联调。不要把 Cloudflare 凭据、JWT 或 service token 写进静态资源。

Actions 使用 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID`，所需权限包括当前账户的 Workers 部署、D1 Edit，以及 `wybxc.cc` 的 Workers Routes Edit。手动凭据检查工作流会更新预先建立的隔离 Worker，并创建/清理临时 D1 与路由；Workers Editor 足够用于部署现有应用，不要求创建/删除 Worker 的 Admin。正式增量工作流仅在可信部署阶段接触这些 secrets。`workers.dev` 和预览 URL 均关闭。

扩展和索引旧 Release 已删除，锁定的 TeaVM runtime seed Release 保留为构建依赖。当前原型只维护当前协议、ABI 和材料，不维护旧版兼容层；上线前重建当前宿主代表包并应用当前 D1 业务迁移。

后续业务开发优先按[同步计划](docs/plan/p2-sync.md)完成服务端权威状态、跨端读写和一致性闭环，书架、进度和设置随同一合同交付；Source/cache、真实阅读、生产 Access 和设备门继续按 [P0](docs/plan/p0-runtime-and-reading.md)验收，不等待所有外围界面完成后再补同步。用户扩展与覆盖性能等范围见[计划目录](docs/plan/README.md)。
