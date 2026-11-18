# API 验证

`pnpm test` 先用 Vite CLI 的声明式配置生成受控夹具，再运行 Node 和官方 Workers 两个 Vitest project。测试入口、公钥、绑定与静态夹具均不进入正式构建。

- Node 单元测试验证鉴权、claims、请求 origin/host、返回路径、HTTP 帧协议与业务边界。
- `state-workerd.test.ts` 和 `http-worker.test.ts` 通过 Cloudflare 官方 Vitest 插件在 workerd 中运行，应用正式 D1 migrations、验证真实 RS256 JWT；HTTP upstream 使用官方推荐的 `@msw/cloudflare`，不启动手写 HTTP server 或自有 API builder。
- `vite-harness.test.ts` 直接读取 `vite.test.config.ts` 经 CLI 生成的配置，使用官方 Wrangler `createTestHarness` 检查 Static Assets 字节、headers、绕过 Worker、host.html 307、匿名401与 D1 迁移。夹具的 root 和配置重定向独立于正式构建。

单独执行官方 Workers 测试：

```sh
pnpm exec vitest run --project workers
```

单独验证生成配置与静态交付：

```sh
pnpm --filter @karuyomi/api exec vite build --config vite.test.config.ts
pnpm exec vitest run apps/api/test/vite-harness.test.ts
```

HTTP 测试覆盖 Range、headers、上传、表单、禁止自动重定向、新域名、限额、截断、超时和消费者取消。gzip 夹具发送真实压缩字节；Brotli 只检查已解码后的边界与 metadata。MSW 不是真实 TCP origin，测试不宣称网络 Brotli 解压、incoming socket abort 或 TCP reset 证据。旧 `*-probe.ts`、socket adapter 和独立浏览器 runner 已退役，历史记录只说明对应历史输入。

扩展唯一公开来源是 Static Assets 的 `/extensions/index.json`、`/extensions/builds/<buildId>/manifest.json` 和 `/extensions/artifacts/<canonicalSHA>.gz`。gzip 为 payload 编码，不使用 HTTP `Content-Encoding`；API 不提供扩展正文或 R2 绑定。中继由官方 Workers Vitest 和 MSW 覆盖，已登录请求无需网络登记；业务测试仍在隔离 D1 应用正式迁移。

Wrangler 只让 `/api`、`/api/*` 和 `/runtime/host.html` 优先经过 Worker；已有扩展与共享资源直接由 Static Assets 交付，缺失资源404，应用 shell 路由显式声明。参考 [Static Assets 配置](https://developers.cloudflare.com/workers/static-assets/binding/)与[官方 HTTP mock 集成](https://developers.cloudflare.com/workers/testing/vitest-integration/mock-outbound-requests/)。

通过这些测试不代表真实 Source、生产 Access、完整阅读或真机性能通过；分层证据见[验证总览](../../../docs/VERIFICATION.md)。

本地官方 acceptance harness 默认不注入故障。`ACCEPTANCE_FIXTURE=settings-ack-loss` 与 `progress-ack-loss` 分别在独立 D1 的指定全局设置或 xkcd 末页完成写入已提交后中断首次响应正文；服务正常退出时输出对应的 `ACCEPTANCE_*_ACK_AUDIT`。复验步骤见[阅读进度丢确认记录](../../../docs/verification/concurrent-server-state.md#web-阅读进度已提交后丢确认)。

`ACCEPTANCE_FIXTURE=bookmark-ack-loss` 对英文 xkcd 的 `SINGLE`、`/3319/` 首次添加书签执行同样的已提交后中断。它核对正式响应和 D1 回执后截断响应正文，普通进度、其它章节、移除书签和未成功的请求不占用故障名额。正常停服输出 `ACCEPTANCE_BOOKMARK_ACK_AUDIT`，可核对是否原样重试并复用同一回执。

`ACCEPTANCE_FIXTURE=progress-d1-error` 对同一末页完成请求在真实 D1 批次最后一次回执更新时触发 SQLite 拒绝，检查正式 503、状态不变及无回执后移除 trigger。它保留原业务响应；普通翻页和其它章节不触发故障。正常停服输出 `ACCEPTANCE_PROGRESS_D1_ERROR_AUDIT`，用于核对同 UUID、正文摘要和 CAS 的 503→200 重试。[Native 驱动](../../reader/integration_test/README.md#d1-拒绝阅读进度写入)另验证未确认界面和显式重试。

`ACCEPTANCE_FIXTURE=settings-cas-race` 只在隔离验收入口同时放行两个 revision 0、UUID 和主题均不同的全局设置 POST；只有正式业务写入成功才有 D1 回执。正常停服输出 `ACCEPTANCE_SETTINGS_RACE_AUDIT`，见[双 Web 设置复验](../../../docs/verification/reader-settings.md#双-web-全局设置同时保存)。

`ACCEPTANCE_FIXTURE=progress-cas-race` 使用独立 D1 和当前英文 xkcd 的 `SINGLE`、`/3319/`。先用正式客户端把两个 Reader 准备到同一已保存且未完成的第 2 页、相同清单与写入基线。一个点「读完本章」，另一个点「重新阅读本章」。普通翻页不会占用名额；只有同基线、不同 UUID 的这两个意图能占满两个槽。第一条最多等待 15 秒；两条正式请求进入 Worker 后，最多再等待 5 秒以确认两边都已通过前置校验并到达 D1 原子批次。夹具原样提交业务批次，缺少任一请求则不会提交本轮批次。

正常停服输出 `ACCEPTANCE_PROGRESS_RACE_AUDIT`。要求两个 Worker 处理时段重叠，两条都到达原子批次；一个 HTTP 200 有持久回执，另一个 HTTP 409 为 revision 冲突且无回执；两条返回同一权威状态，独立只读确认账户和作品 revision 只各增加 1。双 Reader 的保持画面、冲突提示和明确重开另由正式 UI 验收；Workers 回归只验证 API 和 D1。

`ACCEPTANCE_FIXTURE=editor-ui pnpm acceptance:serve` 为设置、封面、迁移、分类与连接状态提供隔离故障控制。仅通过进程 stdin 输入 `editor <mode> [manga|global|cover|migration|categories|classification|connection|preferences|extension-manifest]`，没有 HTTP 控制入口；`manga`、`global` 对应阅读设置，`cover` 对应作品快照、JSON 清除封面及私有图片读取，`migration` 对应作品快照和迁移命令，`categories` 对应分类目录读取与命令，`classification` 对应作品快照与分类关联命令，两种分类范围均包含首段书架读回；`connection` 仅对应 bootstrap GET。默认查询规则见下文的 preferences 范围。图片预置通过正式 multipart API，上传路径本身不注入故障，也不把图片字节存入审计。

模式为 `pass`、`hold-read`、`delay-read`、`fail-read`、`fail-image`、`hold-confirm`、`delay-confirm`、`confirm-read-failure`、`confirm-next-loss`、`lose-confirm`、`reject-save`、`login-required`和`access-denied`。`hold-confirm` 先等待真实 D1 提交，再暂停回执交付；`lose-confirm` 仅在成功提交后返回502。人工挂起最多30秒，以新的控制命令推进 generation 释放；取消会退出等待，未释放超时不记成功。`delay-read` 自动等待5秒，`delay-confirm` 在真实提交后自动等待2秒再交付原回执；`confirm-read-failure` 正常交付同样延迟的成功回执，同时把该 generation 的后续读取设为503。`confirm-next-loss` 同样正常交付首个成功命令的延迟回执，再把该 generation 切为`lose-confirm`，使后续成功提交只丢确认；用`editor pass <scope>`后才能明确重试原命令。自动等待也检查取消，显式改模式优先于预定故障；产品超时不变。`fail-image` 仅对私有图片字节返回503，作品记录保持真实。用 `audit` 查看最多256条请求正文/状态审计，`stop` 正常停服并输出 `ACCEPTANCE_EDITOR_UI_AUDIT`。有界JSON状态命令均进入审计；进度、收藏等其它命令始终原样执行，不受编辑器故障模式影响。此入口替代先前仅设置的夹具，生产入口与配置不包含测试控制。

`editor <mode> preferences` 对应默认仓库的 Source 偏好。读取要求整包路径和标准的 `catalogUrl`、`repoId` 参数，写入使用正式 Source 偏好命令与 D1 事务。以 `delay-read` 验收打开表单，以 `lose-confirm` 验收未确认原请求，以 `confirm-read-failure` 验收已确认后的只读恢复。

`editor delay-read extension-manifest` 延迟同源的标准构建清单 GET 五秒。打开扩展安装或本机准备时，可在等待界面取消，再用 `editor pass extension-manifest` 复验正常完成。清单仍由官方 Static Assets 提供，索引、压缩产物与运行时资源照常交付。取消观测以真实请求的终态和临时账户快照为准。

`ACCEPTANCE_FIXTURE=migration-chapters pnpm acceptance:serve` 在隔离验收入口为固定的英语、中文 xkcd 上游章节列表各提供 257 条可唯一匹配的记录。正式扩展解析响应，Worker 仍经过正常鉴权、二进制桥和 D1。先收藏英语作品，再按 `/1/` 至 `/257/` 通过正式书签 API 保存标记。切到中文源的迁移预览后，检查超限时禁用确认，取消一条映射后可进入二次确认。返回检查且不提交；通过前后读回核对作品和全部书签。夹具只替换两个章节列表的响应，结果仅用于验收选择上限。

测试运行时确认的等待、丢失与精确重试时，先按正式 Web 构建装配客户端和扩展快照，再运行以下命令。

```sh
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts --mode runtime-acceptance
ACCEPTANCE_FIXTURE=runtime-control pnpm acceptance:serve
```

使用验收地址的 `?acceptance-runtime=stop`、`close` 或 `cache`。验收脚本调用原 CI runtime host 和扩展。`stop` 暂扣第一笔搜索的结果，最长 25 秒；结束等待时按原 requestId 和 generation 向真实 host 发送停止，在 6.5 秒后模拟停止确认丢失，并丢弃第一次已成功重置的确认。`close` 从同样的有活动搜索点击返回，另丢弃一次关闭中尝试的重置确认。确认失败后，界面应提供原停止或原关闭的重试。`cache` 在真实清除成功后保留同一摘要的确认 7 秒。通过浏览器控制台的 `ACCEPTANCE_RUNTIME_CONTROL` 和前后权威 API 读回核对结果。脚本及路由仅由显式验收构建和本机启动选项启用。

`?acceptance-runtime=filters` 在正式 Source 枚举筛选说明或执行带筛选条件的搜索时，最多将相同请求的结果暂扣八秒。打开长筛选表单，滚到底后点重置，再明确应用，核对进度、禁用语义与实际恢复。新文档还可加上 `filter-outcome=read-error` 或 `reset-error`，分别把第一次或第二次筛选说明结果替换为 `SOURCE_ERROR`，再用界面重试。加上 `filter-outcome=retire` 会在第二次读取完成后通过正式 host 重建运行时，并向原请求返回 `RUNTIME_LOST`。核对旧草稿退出、重连、重新打开筛选，按审计中的 requestId、generation、snapshotId 以及前后账户读回确认隔离。

`?acceptance-runtime=migration` 要求提供精确的 `migration-reject-build`（构建 ID）和 `migration-listing-source`（读取列表的 Source ID）。先选择可用的目标并读取，切换到指定构建时，首次打开向客户端返回 `SOURCE_ERROR`。核对原目标及候选保留、可继续读取原目标、显式重试打开原失败构建。指定 Source 的热门和搜索在首次取得真实的第二页非空结果时分别丢弃该响应，其余响应照常交付。修改输入框但不提交，再重试失败的分页，与 `ACCEPTANCE_RUNTIME_CONTROL` 中的 sourceId、query、page 和 generation 核对。用隔离账户的前后读回确认向导零业务写入。

`?acceptance-runtime=preference-groups` 将真实 Komiic 的两个设置放进受控的启用、禁用和空分组。先在普通文档保存可用镜像，再在夹具文档打开漫画源设置。验证子组仍显示、镜像继承禁用、可编辑的章节选项能完成实际保存。夹具保留 snapshotId 与 generation，将客户端提交的嵌套路径还原到同一真实设置的原始路径，再交付原监听器结果。核对 `ACCEPTANCE_RUNTIME_CONTROL` 的两条路径、确认值和同一隔离账户的读回。
