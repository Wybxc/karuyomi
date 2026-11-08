# 0009 网络策略隔离预演

2026-11-08，在固定 `9ef3ccb` 的独立 checkout 运行正式登记、策略同步和 Wrangler D1 工具，所有操作使用 `--local --persist-to` 指向隔离目录。以生产 v4 三包的实际静态身份及[已批准域名](v4-production.md#已通过的远端分项)构造迁移前数据，另写入独立业务测试记录。按正式迁移执行 `0000` 至 `0008`、写入测试数据，再应用 `0009_cute_master_mold.sql`。回读确认旧三条网络审批、Source 设置及其写入回执被清空；书架、进度、阅读器设置、账户 revision 和漫画写入回执的测试记录保持原值。

用同一份工具在两个独立 D1 中验证：

- **当前 v6 材料**：从冻结 `c04d436` 的正式终态复制 xkcd 和未批准的 SandraAndWoo，用 `prepare-snapshot` 装配 revision `56473de6e4094adfb7627362bf7f6c1f`，材料清单与全量 checkout 逐字节相同。用实际 xkcd 清单（公开 buildId 末段 `bc5dbfd8870e…`）仅登记 `imgs.xkcd.com`、`xkcd.com`；同来源过期行被删除，其他 catalog 或 repo 的行保持原值。同步前没有审批可继承，登记后仅继承 xkcd，SandraAndWoo 保持未批准。对同一 build 增加域名或尝试以其他 catalog 覆盖均被 D1 拒绝，回读结果不变。
- **旧 v6 材料**：试编 revision `48dc5b618c924a6eaa53bb5ed02a49cf` 的三个 manifest 引用旧 graphics bridge（`39d84a…`，当前为 `afc8baa…`）。当前材料明确拒绝其 xkcd；换用该试编自己的材料清单后，按既有域名显式登记 xkcd、Arknights Comics、CuuTruyen，回读恰好三条，随后同步继承三条。该结果只验证三包登记流程，不能作为当前宿主候选的验收。

最终快照的本地复验应从同一个候选 index 的 `manifestPath` 取三个实际清单，在宿主材料匹配的独立 checkout 运行。下例展示 xkcd 登记；另外两个包照上述既有审批逐项指定 hostname。使用绝对路径指定独立本地 D1 和快照：

```sh
pnpm --filter @karuyomi/api exec wrangler d1 migrations apply DB --local --persist-to "$D1"
node tools/extensions/registration.ts "$XKCD_MANIFEST" \
  --local --static-root "$SNAPSHOT" --persist-to "$D1" \
  --catalog-url https://karuyomi.wybxc.cc/extensions/index.json \
  --allow-host imgs.xkcd.com --allow-host xkcd.com
# 按相同方式登记另两个包后，再同步并回读。
node tools/extensions/network-policies.ts \
  --local --static-root "$SNAPSHOT" --persist-to "$D1" \
  --catalog-url https://karuyomi.wybxc.cc/extensions/index.json
pnpm --filter @karuyomi/api exec wrangler d1 execute DB --local --persist-to "$D1" --json \
  --command 'SELECT catalog_url, repo_id, package_name, build_id, bundle_sha256, status, allowed_hosts_json FROM extension_builds ORDER BY package_name'
```

`--catalog-url` 在此仅作为本地策略的来源标识，工具从 `--static-root` 读取元数据。核对最终本地 D1 中只有三条预期的审批，各条来源、buildId、摘要和域名都匹配；若最终快照缺包，不能拿旧包或扩大域名来通过此门。当前全量尚无最终快照，因此这项验收未完成。

远程登记会核对**已经部署**的索引与清单，无法在部署前批准新候选；`network-policies.ts` 仅继承既有审批，不能恢复 `0009` 清空的审批。迁移、部署和三次显式登记不构成原子切换：先备齐并本地复验最终清单与域名，再安排生产切换；迁移后到重登记完成前，相关 Source 可能暂时无法联网。此次预演未写生产、未部署、未修改冻结全量。脚本、日志和隔离数据库留在 `/private/tmp/karuyomi-policy-0009-replay.tJ3T9p/`；`replay-final.log` 含 `REPLAY_PASS`，关键回读在 `final-after-0009.json`、`current-exact-after.json` 和 `previous-v6-three-after.json`。
