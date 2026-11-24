# 生产发布与停机迁移

原型阶段，生产只运行一套当前代码、协议、扩展材料和数据库结构。已应用的 D1 SQL 保持原样，结构变化通过 Drizzle 新增迁移。每次切流直接使用 100% 的单一版本。

Web 主线和增量扩展的自动发布在切流前只读生产 D1 的迁移账本。账本必须按顺序与候选的 SQL 一致。缺失、超前、乱序或无法读取时停止发布。自动流程不执行生产迁移。合并含新增迁移的 PR 不会自动切换生产。

## 开发机准备

1. 固定待发布提交。使用 `pnpm db:migrate:local` 验证新建数据库，并用隔离的原结构数据验证升级后读写。检查迁移、正式构建和流水线结果。准备与当前扩展材料匹配的完整 Web/Worker 和 Static Assets。沿用 Web 的快照预检或[扩展候选流程](EXTENSIONS.md#候选部署与-checkpoint)核对现网父快照。
2. 在拟定的维护窗口合并前暂停自动和手动发布器。记录当时已启用的 Actions 工作流，临时停用 `project-ci.yml` 与 `extensions.yml`，并确认已在运行的生产作业都已结束。扩展候选和生产 Worker 在预检后不得被其他工作区覆盖。
3. 核对开发机 Wrangler 会话、目标 Worker 和生产 D1 绑定。保留实际在服务的版本号及 D1 恢复点，用只读查询确认已应用项是候选的连续前缀。若存在未知迁移或顺序异常，保持当前生产数据。

```sh
release_config="$PWD/apps/api/dist/karuyomi/wrangler.json"
maintenance_dir=$(mktemp -d /tmp/karuyomi.XXXXXX)
maintenance_config="$maintenance_dir/wrangler.maintenance.json"

pnpm exec wrangler deployments list --config "$release_config" --json
pnpm exec wrangler d1 execute DB --remote --config "$release_config" \
  --command 'SELECT name FROM d1_migrations ORDER BY id' --json
node scripts/release-web.ts stage-maintenance --config "$release_config" \
  --maintenance-dir "$maintenance_dir"
pnpm exec wrangler versions upload --dry-run --config "$maintenance_config"
pnpm exec wrangler deploy --dry-run --outdir "$maintenance_dir/release" \
  --config "$release_config"
```

维护版保留现有 Worker 和 Durable Object 的绑定身份。它只返回不可缓存的 503，所有请求均经过维护入口，且没有数据库、对象存储或静态素材绑定。路由保持在原 Worker 上。路由或 Durable Object 生命周期也要改变时，用当前线上配置及对应类准备维护版，再在停机期用正式配置部署新 Worker。通常的 D1 变更可以提前上传维护版和候选版，上传不会切流。[Workers 部署管理](https://developers.cloudflare.com/workers/versions-and-deployments/deployment-management/) · [Durable Object 生命周期变更](https://developers.cloudflare.com/workers/versions-and-deployments/gradual-deployments/with-durable-objects/)

## 暂停、迁移和恢复

1. 在开发机用 `wrangler versions upload --config "$maintenance_config"` 上传维护版，记录版本号。路由和 Durable Object 无待改动时，用 `wrangler versions upload --config "$release_config"` 上传匹配候选，也记录版本号。
2. 将维护版设为 100% 流量。查阅实际部署状态，重复检查首页和扩展索引，确认返回 503 及 `X-Karuyomi-Maintenance: 1`。受 Access 保护的 API 在具备会话时核对。确认旧版在途请求结束后获取 D1 恢复点，才开始迁移。
3. 从开发机对生产 D1 应用候选中的所有待迁移项。随后运行只读账本检查，核对目标表、关键数据与预期一致。任何一步失败都维持维护版。
4. 将已验证的候选版切到 100%。若候选涉及路由或 Durable Object 生命周期变更，此时使用正式配置 `wrangler deploy`。确认首页、Access 门、登录后关键读写及扩展快照，再恢复先前启用的发布器。请活动客户端重新加载，Native 客户端使用匹配版本。

```sh
# 从上传回执取得 maintenance_version
pnpm exec wrangler versions deploy "$maintenance_version@100%" \
  --config "$release_config" --yes &&
  node scripts/release-web.ts check-maintenance
```

确认在途请求已结束后，从开发机迁移。

```sh
node scripts/release-web.ts check-maintenance &&
  pnpm exec wrangler d1 time-travel info DB --config "$release_config" --json &&
  pnpm exec wrangler d1 migrations apply DB --remote --config "$release_config" &&
  node scripts/release-web.ts check-schema --config "$release_config"
```

核对数据后恢复匹配版本。

```sh
# 从上传回执取得 release_version
node scripts/release-web.ts check-maintenance &&
  node scripts/release-web.ts check-schema --config "$release_config" &&
  pnpm exec wrangler versions deploy "$release_version@100%" \
    --config "$release_config" --yes
```

恢复后的验证若失败，切回维护版。Worker 版本回退不会改回 D1。数据修复或恢复须在维护期单独确认，再用匹配的应用验证后恢复服务。[D1 迁移命令](https://developers.cloudflare.com/d1/wrangler-commands/#d1-migrations-apply) · [D1 恢复点](https://developers.cloudflare.com/d1/reference/time-travel/)
