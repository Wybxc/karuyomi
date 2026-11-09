# 源迁移验证

2026-11-07，本轮源迁移功能与独立集中工程检查已通过，真实 Source、独立客户端及平台验收继续推进。设计见[用户确认的源迁移](../design/source-migration.md)，剩余范围见[计划](../plan/source-migration.md)。本记录只登记已完成的实际层级，不以既有扩展管理工程通过结果覆盖本轮新代码。

## 正式合同与真实 D1 定向检查

主树基于 `ad869d2759ae9d878a89154f80a1d094bba36564` 推进本轮变更；迁移协议/API 定向检查运行于 macOS、本仓库锁定 Node/pnpm，Worker 集成沿 Cloudflare 官方 Vitest 插件执行真实 workerd/D1，不用 Dart 测试供应器代替 SQL。

- `packages/contracts/test/business-state.test.ts` 与 `apps/api/test/state-workerd.test.ts` 两文件合计 60/60 通过。覆盖源/目标/分类三 CAS 的实际 batch 前竞争、目标已有 progress 整行与 metadata/cover/resume 保留、分类并集、正向已读/书签增补、跨身份、UUID 同 body 幂等/异 body 拒绝、trigger 故障全回滚、256 组映射与请求预算。
- `pnpm test:protocol` 10/10 通过，TS ↔ Dart 生成 ProtoJSON/二进制 golden 加入 `migrateFrom` 和 `MigrationResult`；运行时类型、oneof、字段存在性、身份及预算检查仍生效。
- API 产品/测试及 contracts 的 TypeScript 严格 typecheck 通过。首次 fixture 浅复用导致的失败已修为官方 `clone` 后重跑，原失败日志保留；未通过缩小检查或掩盖类型错误恢复。

可复验入口（先按仓库指引设置固定 Node、JDK 与 Flutter/Dart 环境）：

```sh
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
pnpm --filter @karuyomi/api typecheck
pnpm --filter @karuyomi/contracts typecheck
pnpm test:protocol
```

原始结果保留 `/private/tmp/karuyomi-migration-tests-green.log`、`karuyomi-migration-protocol.log`、`karuyomi-migration-api-typecheck-final.log` 与 `karuyomi-migration-contracts-typecheck-final.log`。这些日志不提交源码库；后续全库检查及最终提交须另外记录。

## 正式客户端回归与独立审查

Dart 数据层与章节匹配覆盖只读完整分页、混合 revision 拒绝、目录变动不触发隐式书架刷新、冻结预览、双作品/分类 pending、跨 repository 包装器恢复、原 UUID/body/CAS 重试、已拒绝草稿显式处理，以及旧幂等 ACK 不覆盖新目标。每次实际 GET 前后和排队 POST 前检查页面；已发写仍由业务客户端处理 ACK。重复 URL、缺号、零/小数章、扫描组和多重认领均保留正式身份，不把未知号当自动匹配证据。

正式书架/详情菜单、目标搜索分页、手动映射、独立确认和仅迁收藏/分类路径有组件回归。原 Source 的 runtimeLost/timeout 不再禁用账户迁移；用户明确选择只迁收藏/分类后可重建并打开目标。映射改到已有完整状态的目标后移除无效选中，257 条选择拒绝 POST，不隐式拆批。最终迁移 UI/Controller 定向 15/15 通过。

独立审查补齐点击与 route 懒构建间的身份窗口：入口捕获原 `BusinessStateClient` 并显式传入页面和 Controller；Access 失效或业务客户端变化使旧向导永久退休。四项书架/详情与失效/换身份组合回归确认不发新 GET/POST、Source invoke 或 open，没有 null 断言崩溃；即使原客户端恢复也不自动启用旧向导。

实际回退用例还暴露容器重建的异步失效事件晚到、误废弃新操作的问题。正式 Transport 先提交内部失效/Access 状态，再同步通知；保留图片超时、管理及独立 API 的事件抑制规则。Transport 定向 29/29 通过，包含通知时观察到已提交状态与重建后正式 open/invoke。此处 Source 与 Access 由受控 supplier 提供，不是实际在线或生产登录证据。

定向日志保留 `/private/tmp/karuyomi-migration-ui-domain-tests-final.log`、`karuyomi-migration-route-tests.log` 与 `karuyomi-migration-runtime-tests.log`；全量回归覆盖后续路由修复和格式修复。

## 独立集中工程检查

最终代码冻结后，独立验收代理在同一 macOS 主树、锁定 Node/pnpm/JDK 与 Flutter 3.47.5 / Dart 3.13.4 环境顺序执行：

- 全库 `pnpm format` → 完整 `pnpm format:check` 通过，159 个 Dart 文件最终格式无变更，包含全部项目自有语言。
- 完整 `pnpm check` exit 0：生成一致性、portable 格式、严格 TypeScript、依赖层级、32 文件 455 项官方 Vitest、10 项跨语言 golden 和全部注册、扩展编排、工具链、完整性、上游补丁及 Cloudflare 工具测试通过。
- 完整 `pnpm flutter:check` exit 0：三个包严格分析无问题；reader_core 22、source_runtime 66、Reader 507 项全部通过。
- 完整 `pnpm build` exit 0：Web/Native 运行时 JS、Native 内置资源、Flutter Web 与 API Static Assets 构建成功；装配 57 静态文件、0 current extensions。这是空扩展目录的工程构建，不是原生 App 或真实 Source 阅读验收。
- `git diff --check` 通过；测试与构建均正常退出，本轮没有遗留可归因的后台进程。

首轮集中 check 在补路由修复后、再次格式化前停于格式检查；重新全库格式化并由 Dart 官方修复器补齐新代码花括号 lint 后，完整三步均重跑通过。未缩小格式范围、跳过 hook、降低类型检查或把失败夹具当成功。失败与最终日志分别保留 `/private/tmp/karuyomi-source-migration-acceptance-check.log` 和 `karuyomi-source-migration-acceptance-{check,flutter,build}-final.log`，完整格式日志为 `karuyomi-source-migration-format{,-check}-final.log`。

## 尚未登记通过

- 本轮 Codex 内置浏览器 inventory 无可用 browser；没有迁移页面截图或实际 Source 搜索/章节映射运行证据，也未改用其它桌面浏览器。
- Web/Native 独立客户端、真实 Source、实际跨端冲突/丢 ACK、生产 Access 与真机均未执行；模拟 supplier 不覆盖这些门。
- 本轮没有迁移生产部署或 AOT baseline 完成。后续实际运行必须使用与最终 host/协议输入一致的正式构建，不能补字段或沿用旧通过结论。

## 正式 Web 的真实源搜索与热门列表

2026-11-09，Codex 内置浏览器在正式 Flutter Web 和隔离 workerd/D1 上，安装固定 `c04d436` 的 xkcd v6 1.6.1。英文 `SINGLE` 的详情返回 3,320 章；从正式界面收藏作品，再给第 2978 章 `Stranded` 加书签及已读标记。独立 HTTP 读回为账户/作品 revision `4/3`，中文 `SINGLE` 尚无业务状态。旧向导能打开中文源，但搜索 `xkcd` 无结果；同一 Source 的原实现返回空搜索列表，只能通过正式热门操作列出作品。搜索前后书架响应逐字节相同。

向导新增独立的热门列表和无搜索结果提示，沿用已安装 Source 的正式 `Popular` 及分页；另可只显示原作有已读或书签的章节，以便在长列表定位标记。三个 Flutter 迁移测试文件共 37 项通过。新增回归核对空搜索不暗中发热门请求、热门两页都使用所选 Source 与原操作、标记筛选不改变已选项、确认前零 POST、确认后一次复制两类标记。组件中的 Source 响应受控。

正式复验使用 `pnpm acceptance:build` 的 Vite 产物和官方 `wrangler dev --local`（复用已授权回环端口、独立 `--persist-to`），同一签名测试身份。修复版 `main.dart.js` SHA-256 为 `4f6f6b07d69c86f6bcbba271f78ee70cf220ec68ad95c1a6ed9df67155ffe8a8`。更新构建后重启 Wrangler 以重新索引静态资源，同一隔离 D1 持久目录保留已写原作。修复版从书架进入，在线读取英文原章节，再从中文源热门选中 `SINGLE`（详情 676 章）；筛出原标记，手动映射 `2978: Stranded` → `2978: 困住` 并选中复制。

- 独立确认框打开后，书架、两部作品状态、两部作品的进度和书签七份 API 响应与迁移前逐字节一致；没有业务 POST。
- 显式确认后，正式界面确认新增已读 1 章、书签 1 个。复验服务日志恰好一个业务 POST 200，账户 revision `4 → 5`，英文作品 revision 保持 3、章节状态与书签不变；中文作品首次 revision 为 1，有已读 epoch 1 和书签，没有页位、最远位置或续读目标。
- 关闭原文档后，新文档从 D1 读到书架中英两部作品，打开中文详情确认第 2978 章已读且有书签。读回没有再次提交。原始快照与截图保留在忽略目录 `.local/live-migration-evidence/`；服务已停止。

本分项验证两个真实 Source、同一浏览器 profile 的独立文档和一次正常确认。未覆盖分类非空并集、同时修改、实际断网或丢 ACK、Native、真机和生产。
