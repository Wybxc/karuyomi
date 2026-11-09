# 通用中继的 D1 生产切换演练

2026-11-08，在本地隔离 workerd / D1，用最后一次确认的生产部署 `466acdd` 和当前通用中继 `2cde709` 演练从迁移 `0003` 切换到 `0010`。使用 Wrangler 4.156.1 官方 harness、同一隔离 D1、临时 RS256 测试身份和独立模拟 R2。旧 Worker 使用该提交的 Worker 源码；新版来自 `pnpm acceptance:build`，静态树含固定 `c04d436` 的 xkcd v6 1.6.1 单包验收产物。旧 Worker 也挂载这棵测试静态树，仅用于验证 API 与 schema 顺序。桥请求故意提交空帧；400 代表通过前置分支到达协议解析。

| D1 迁移阶段 | 旧 Worker                                          | 当前 Worker                                       |
| ----------- | -------------------------------------------------- | ------------------------------------------------- |
| 至 `0003`   | 正式 API 收藏成功；中继到达协议解析                | 未运行                                            |
| 至 `0008`   | 正式 API 继续保存进度，书架/作品读回，中继仍可解析 | 书架可读；Source 设置返回 503                     |
| 至 `0009`   | 中继返回 `404 build_not_found`                     | Source 设置返回 200；中继无需登记即可到达协议解析 |
| 至 `0010`   | 中继返回 500（故意重启旧版以验证单独回退的边界）   | Source 设置、书架/作品和 Static Assets 均可读     |

`0009` 删除了测试预置的旧 Source 设置与对应写入回执；收藏、当前页、最远页、视口锚和两条作品写入回执在最终状态保持。另用官方 Wrangler CLI 对同一临时持久化目录依次应用原 SQL 前缀至 `0008`、`0009`、`0010`，迁移记录按文件名顺序追加，最终无待应用迁移。无生产写入、无真实 Access 登录、无真实上游 Source 请求。

可复验的本地脚本与原始结果保存在忽略目录 `.local/d1-cutover-rehearsal.t4nTkx/`；目录内有两次 harness 输出及 `cli-prefix.l9hYIl/results.log`。在本仓库根运行：

```sh
export XDG_CONFIG_HOME="$PWD/.local/d1-cutover-rehearsal.t4nTkx/config"
export WRANGLER_LOG_PATH="$PWD/.local/d1-cutover-rehearsal.t4nTkx/wrangler.log"
export WRANGLER_SEND_METRICS=false
.local/node24/bin/node .local/d1-cutover-rehearsal.t4nTkx/rehearse.ts
```

该结果确认旧、新 Worker 的切换顺序与隔离 D1 状态保留。尝试只读查询生产迁移列表时，Wrangler 因当前无管理 API 认证退出；生产迁移账本和私有封面桶仍须发布前核对。现网 v4 三包须由完整、匹配当前运行时的候选接替。操作顺序见[发布文档](../EXTENSIONS.md#旧网络登记部署切换)；新版真实中继和中文列表见[本地验收](generic-source-relay.md)。

2026-11-10，基于 `51c7b1b` 的正式配置和 SQL，准备了截至 `0008`、`0009` 的原样前缀。使用不同数据库 ID 和独立本地持久目录的对应配置，以 Wrangler CLI 顺序应用 `0003 → 0008 → 0009 → 0010`，每步以 `SELECT name FROM d1_migrations ORDER BY id` 读取账本，逐文件核对四个结果与原前缀一致。配置、SQL 摘要和读回留在 `.local/cutover-preflight-51c7b1b.u4E4Vi/`。当前 `wrangler whoami` 报本机管理会话已过期；未执行生产命令。完整候选、生产账本、Access 和封面桶的当前状态仍需在发布前核对。

同一提交的正式 Vite Worker 配置通过 `pnpm --filter @karuyomi/api exec wrangler deploy --dry-run --config dist/karuyomi/wrangler.json`，识别到 `DB`、`COVERS`、`ASSETS` 与 Access 变量。此次使用 xkcd 单包验收快照，只证明本地配置与构建可被 Wrangler 接受，未向生产上传，也不代替完整候选的 dry-run。

2026-11-10，为缩短 `0009` 后的中继中断，用正式 `2c012db` / 六材料 xkcd 验收构建执行 Wrangler 4.156.1 `versions upload --dry-run`。生成 Worker 与 `DB`、`COVERS`、`ASSETS`、`RUNTIME_SESSIONS` 及 Access 变量均被识别；本地源码确认真实上传会同步 Static Assets，dry-run 不上传。与已部署 `466acdd` 的配置比对，Worker 自定义域名和 Durable Object `v1` 声明无变更。正式切换拟先上传完整版本，再执行 `0009` 和 100% 版本切换；生产 Worker 版本、路由和待应用迁移需在当次发布前核实。本轮未上传或切流，也未应用远端迁移。原始日志位于 `.local/versions-upload-cutover-2c012db.xteibk/dry-run.log`。
