# 服务端权威业务状态验证

2026-11-05：本地真实 Miniflare/workerd + D1 验证通过。本记录证明正式 API 路由、真实 SQL 事务和签名身份验证的集成行为；没有使用内存仓库或伪造数据库接口。

## 执行入口与结果

```sh
pnpm exec vitest run apps/api/test/state-workerd.test.ts
pnpm exec vitest run apps/api/test
pnpm --filter @karuyomi/api typecheck
pnpm exec tsc --noEmit --target ES2022 --module ESNext --moduleResolution Bundler --strict --skipLibCheck --allowImportingTsExtensions --noUncheckedIndexedAccess --exactOptionalPropertyTypes --types node apps/api/test/state-workerd.test.ts
```

- 新增的 `state-workerd.test.ts`：9 个测试通过。
- API 完整测试目录：6 个文件、136 个测试通过，其中 Access 路由 39 项。
- API TypeScript 与新增集成测试的独立严格类型检查通过。
- 测试通过 esbuild 打包正式 `createApp`，由锁定的 Miniflare/workerd 执行；使用现场生成的 RS256 密钥、真实签名 JWT 和测试入口的本地 JWKS 校验。测试入口不改变生产鉴权代码。
- 隔离 D1 执行全部仓库 Drizzle 迁移，包括新增的 `0003_overconfident_champions.sql`；测试结束后关闭 workerd。

## API 与数据权威

新增路由：

- `GET /api/library?afterKey=&revision=`：每页至多 8 项，按 `mangaKey` 排序；后续页必须提交第一页的 `accountRevision`。任何已确认业务写入都会增加账户 revision；revision 改变时返回冲突并要求重新分页，不拼接不同快照。
- `GET /api/state/manga/:mangaKey?chapterKey=`：用单条 SQL 同时读取账户 revision、作品状态和指定章节进度，避免读出不同时刻的组合。未写入作品返回 revision 0 的空业务状态。
- `POST /api/state/mutations`：使用 Protobuf 生成模型和标准 ProtoJSON；支持收藏、取消收藏、元数据更新、保存进度及重置进度。

账户身份只取正式鉴权中间件验证后的 Access subject。`X-App-Subject` 仅与这个 subject 比较，用于绑定客户端会话，不能选择账户；不匹配返回 403。正式 JWT、Origin 和 `X-App-Request` 约束继续生效。所有 SQL 查询和主键均包含可信 subject。

D1 新增 `account_state`、`manga_state`、`chapter_progress` 和 `state_mutations`。每作品 revision 覆盖元数据、收藏、章节进度和 resume 的所有写入；章节进度独立存行。浏览但未收藏的作品可以先保存进度。取消收藏保留作品 revision、元数据、resume 和进度。

## CAS、幂等与原子性证据

写入先读取规范状态并验证 `expectedRevision`，随后用单个 D1 `batch` 提交：

1. 按作品当前 revision 条件插入幂等记录，记录规范请求的哈希、随机本次 attempt nonce 和响应。
2. 账户 revision、作品和章节写入都必须满足该 nonce 存在的条件；只有新获准的请求能产生业务效果。
3. 在同一个 batch 中把已递增的真实账户 revision 写入持久响应。同 ID、同内容始终返回原成功响应；同 ID、不同内容返回冲突。

测试实际发出两个独立签名客户端的并行请求，确认同作品相同 revision 只有一个成功；不同作品的并行成功响应分别保存准确的账户 revision。相同 ID 并行提交只产生一次业务写入。在后续写入已完成后重试原请求，仍返回最初确认的完整响应，模拟提交成功但响应丢失的重试。

原子失败测试在真实 D1 安装临时 SQLite trigger，令章节插入中途 `RAISE(ABORT)`。API 返回可重试错误；随后查询确认账户 revision、作品 revision、章节数据与幂等记录全部回滚。删除 trigger 后使用原 mutation ID 重试成功，两个 revision 均只增加一次。

## 阅读语义与预算

- 首次章节保存使用 epoch 0。重置由服务器递增 epoch，并清空 furthest 和完成状态；原重置 ID 重试不会再次递增。旧 epoch 的后续写入被拒绝并返回规范状态。
- current 只是导航位置，恢复或跳转不增加 furthest。furthest 只合并客户端实际观察的锚点。
- 跨 manifest 比较先按本次 snapshot 的稳定 `pageKey` 映射，不比较旧 `pageIndexHint`。历史最远页不存在时保留原锚点，以便 UI 显示 unresolved；该页再次出现后按新快照重映射。完成状态只在同一 manifest 中保留。
- 独立章节行分别保留进度和 epoch；作品 resume 指向最近确认的导航章节。
- 请求正文按实际流入字节限为 128 KiB，超限返回 413；非法 JSON、无效协议、无效 Source 元数据与作品身份不匹配均无法写入。
- 元数据至多 96 KiB，其中 Source opaque memo 至多 64 KiB；snapshot 至多 2048 个唯一页面身份。单页书架至多 8 个作品，响应协议预算 2 MiB。请求整体的 128 KiB 限额仍优先限制 snapshot 与元数据的实际组合。

## Web 同页登录与会话草稿

Web 登录改为同步打开独立窗口，当前应用文档与尚未获确认的内存草稿继续保留。应用不再要求先保存成功才能登录，避免 Access 过期时出现“需要登录才能保存、必须保存才能登录”的阻塞。Native 继续使用原登录流程。

登录窗口请求 `/api/auth/login?returnTo=/auth/complete&attempt=<UUIDv4>`。正式 API 验证 Access 后，仅将合法 attempt 重定向到固定第一方 `/auth/complete`。调用方轮询自己持有的窗口句柄，仅在 origin、callback 路径和本次 UUID 全部一致时接受完成；跨域 Access 页面不可读取期间继续等待。完成信号不能决定账户身份，随后 Catalog 仍须重新 bootstrap，并只对确认相同身份的草稿重绑 API。没有增加持久草稿、outbox、跨窗口消息协议或手写静态 JavaScript。

阻止弹窗、手动关闭或被浏览器隔离、3 分钟超时与服务销毁取消均有明确失败路径；完成和失败都会清理轮询、截止计时器并尝试关闭对应窗口。Continuation 只保存在当前 Web runtime 内存中。

```sh
cd apps/reader
flutter test test/runtime/popup_authentication_test.dart
flutter analyze --no-pub lib/runtime/platform_runtime_web.dart lib/runtime/popup_authentication.dart test/runtime/popup_authentication_test.dart
```

5 个独立状态机测试通过，覆盖同源回调成功、错误 origin/path/attempt 拒绝、窗口关闭、超时和取消，以及计时器与窗口关闭的幂等清理；三个文件的 Flutter analyze 无问题。API 测试另外覆盖合法 attempt 保留、非法 attempt 和非固定 callback 拒绝。这些测试未运行真实 Access 页面、浏览器弹窗策略或 COOP 隔离，生产登录窗口仍需在 Codex 内置浏览器验收。

## Flutter 正式入口与工程回归

同日完整执行：

```sh
pnpm format
pnpm format:check
pnpm check
pnpm flutter:check
EXTENSION_ASSETS_DIR="$PWD/.local/v4-production/snapshot" pnpm build
```

- 通用检查通过，包括 23 个 Vitest 文件的 358 项测试、跨语言协议 golden、严格类型、依赖层级与工具/真实 workerd 回归；其中 API 集成范围按上文单独说明。
- Dart/Flutter 三个项目静态分析均无问题，`reader_core` 21 项、`source_runtime` 42 项、客户端 190 项测试全部通过。
- 客户端组件使用明确标注的共享测试服务与独立会话，覆盖收藏后另一客户端读回/续读、完整 Source 快照、取消收藏保进度、前台/手动书架刷新与刷新失败保留确认视图。收藏 CAS 只刷新状态，必须用户再次明确操作才发送新 mutation。
- 旧幂等成功只证明过去提交发生。重试或已知落后响应会读回当前权威作品，再决定确认还是 revision/epoch 冲突；另一端取消收藏/reset 后不会重现旧收藏或假报旧进度已保存。
- 进度冲突按原操作归属保留。收藏、resume 与整库刷新不能解除旧阅读草稿的 CAS/epoch 冲突；重新打开相应章节后才恢复写入。
- 正式 Catalog 在 bootstrap 确认当前身份前不提交草稿，随后仅提交同身份 writer。真实 `TransportSourceRuntime` 的 AccessDenied 事件回归覆盖身份切换、原身份恢复后重绑与原请求正文重试；确认身份期间立即清除旧书架视图。
- 正式 Flutter Web release、已有 v4 三包快照的 Static Assets 组装与 Worker dry-run 构建通过；默认空索引构建也通过，不能将它代替含三包的组装检查。共享 materialVersion 仍为 `629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b`，未启动新的全量 AOT；新 API/D1 及客户端尚未部署生产，也未构建/安装本轮 Native App。
- 本地业务数据库、Drift/build_runner 依赖、生成模型和数据库 Web 资产已移除；Source 文件/HTTP Cache、扩展缓存与图片资源的原存储未改变。

## 阅读中前台重取与登录恢复

同日新增 `reading_progress_refresh_test.dart` 及正式路由回归，完整 `pnpm flutter:check` 通过：三个项目分析无问题，测试分别为 21、42、208 项。`pnpm check` 再次通过，包括 23 个 Vitest 文件、358 项测试及完整工具/协议/workerd 检查；含原生产三包的 `pnpm build` 与 Worker dry-run 通过，扩展静态目录与原快照逐字节相同，共享材料版本未变。

- 恢复前台与“刷新进度”先以当前阅读视图的已确认 revision 提交草稿，再只读检查服务器；inspect 不推进共享客户端的 CAS 基线，不解除别章或旧 mutation 的冲突。
- 其他端改变 current、furthest、epoch、resume 或未知来源的作品 revision 时，当前画面与锚点保持不变；旧视图不能再保存，必须明确“重新打开本章”才采用服务器位置及章节顺序。同一客户端已经确认的收藏操作仍可共享连续 revision。
- 显式重开复用章节切换的旧 provider 清理 ACK，在新 leaf 挂载前完成；当前阅读模式及双页选择保留。刷新 503 可重试，迟到读取、新 viewport、切章及 dispose 不污染新视图。
- Access 登录恢复沿用旧阅读视图的基线，通过相同只读检查决定是否需要重开；不能读取新 epoch 后把旧 continuation 位置写回。组件回归在登录回调内用第二客户端 reset，确认恢复仍保留原画面、服务器首页未被覆盖，明确重开后才采用新 epoch。

新增前台测试 14 项、inspect/CAS 测试 1 项、路由前台/失败重试 2 项和登录期间 reset 1 项。这些是组件与正式路由测试；真实内置浏览器、生产 Access 和 Native 生命周期验收仍独立进行。

## 真实 Web 独立会话闭环

同日以 `d1e280e` 的正式 Flutter Web 构建、原生产 xkcd v4 包和 Codex 内置浏览器完成同 origin 的 A→B→新 A 会话验收。入口为 `apps/api/test/source-metadata-probe.ts` 的正式 Flutter 模式，所有业务与 Source HTTP API 均进入真实 workerd 和同一隔离 D1，使用真实 RS256 测试身份 `probe-owner`；没有使用组件测试服务或改变原扩展代码。

```sh
SOURCE_PROBE_READER_DIR=apps/reader/build/web \
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_IMAGES=1 SOURCE_PROBE_PORT=8897 \
SOURCE_PROBE_EVIDENCE=.local/server-state-web/xkcd-network.json \
node apps/api/test/source-metadata-probe.ts \
  .local/v4-source-validation/xkcd/manifest.json \
  .local/v4-source-validation/xkcd/artifacts
```

| 操作                                                                 | 实际 UI 与权威读取结果                                                                                                                                                                      |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 浏览原 Source，收藏 xkcd 后关闭标签                                | UI 变为“移出书架”；`GET /api/library` 的 account revision 为 1，favorite=true                                                                                                               |
| 新 B 会话从书架进入详情，打开 `3320: House Majority` 并阅读到第 2 页 | 书架显示收藏 1 部；真实图片/文字页可见，UI 显示“阅读进度已保存到服务端”；对应 state revision 为 5，current/furthest 的 pageIndexHint 均为 1，furthest offset 为 1，epoch=0、completed=false |
| 关闭 B，新 A 会话从书架进入详情，点击“继续阅读”                      | 正式阅读页直接恢复 `2 / 2`，显示服务端已保存；state revision 为 7，current/furthest 与 B 的已确认位置一致                                                                                   |

三个文档使用同一 `http://127.0.0.1:8897`；依次关闭前一文档以释放 Source 文件写入锁，每个新文档重新 bootstrap、打开 Source 和读取 D1，扩展/HTTP 缓存可正常复用。详情刷新元数据及打开阅读都会产生合法写入，revision 不等同于点击次数。只读核对使用 `X-App-Request: 1`、`X-App-Subject: probe-owner`，经 library 取得 mangaKey、state 的 resume 取得 chapterKey，再读取指定章节；原始 JSON 与网络日志仅留在忽略目录。

这完成真实 Web 独立会话的收藏→书架→阅读保存→重启续读基础门。没有执行生产 Access、两个并发阅读文档、远端修改时的实际前台重取或 Native 平台配对；不把本项升级为完整 P1/P2 验收。测试结束后已确认端口 8897、harness 与 workerd 子进程均退出。

## 验证边界

工程测试证明本地真实 workerd/D1、正式路由和签名测试身份之间的闭环；浏览器独立会话范围按上节单独验收。它不代表生产 Cloudflare Access 登录、远程 D1 部署、Web/iOS/Android 跨端交互或真机阅读已经验收。分类、书签与非敏感设置仍需按计划接入相同服务端权威模型，不能由本记录推断已经实现。
