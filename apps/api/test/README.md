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

`ACCEPTANCE_FIXTURE=progress-d1-error` 对同一末页完成请求在真实 D1 批次最后一次回执更新时触发 SQLite 拒绝，检查正式 503、状态不变及无回执后移除 trigger。它保留原业务响应；普通翻页和其它章节不触发故障。正常停服输出 `ACCEPTANCE_PROGRESS_D1_ERROR_AUDIT`，用于核对同 UUID、正文摘要和 CAS 的 503→200 重试。[Native 驱动](../../reader/integration_test/README.md#d1-拒绝阅读进度写入)另验证未确认界面和显式重试。

`ACCEPTANCE_FIXTURE=settings-cas-race` 只在隔离验收入口同时放行两个 revision 0、UUID 和主题均不同的全局设置 POST；只有正式业务写入成功才有 D1 回执。正常停服输出 `ACCEPTANCE_SETTINGS_RACE_AUDIT`，见[双 Web 设置复验](../../../docs/verification/reader-settings.md#双-web-全局设置同时保存)。

`ACCEPTANCE_FIXTURE=progress-cas-race` 使用独立 D1 和当前英文 xkcd 的 `SINGLE`、`/3319/`。先用正式客户端把两个 Reader 准备到同一已保存且未完成的第 2 页、相同清单与写入基线。一个点「读完本章」，另一个点「重新阅读本章」。普通翻页不会占用名额；只有同基线、不同 UUID 的这两个意图能占满两个槽。第一条最多等待 15 秒；两条正式请求进入 Worker 后，最多再等待 5 秒以确认两边都已通过前置校验并到达 D1 原子批次。夹具原样提交业务批次，缺少任一请求则不会提交本轮批次。

正常停服输出 `ACCEPTANCE_PROGRESS_RACE_AUDIT`。要求两个 Worker 处理时段重叠，两条都到达原子批次；一个 HTTP 200 有持久回执，另一个 HTTP 409 为 revision 冲突且无回执；两条返回同一权威状态，独立只读确认账户和作品 revision 只各增加 1。双 Reader 的保持画面、冲突提示和明确重开另由正式 UI 验收；Workers 回归只验证 API 和 D1。
