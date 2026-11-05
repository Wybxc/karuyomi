# v4 生产部署与匿名静态交付

2026-11-05，固定 `13494a0e473f946910960d8883c54864471b9410`，正式客户端、API 与三个 v4 扩展已部署至 `https://karuyomi.wybxc.cc`。Wrangler 成功退出，部署后匿名静态交付与 D1 网络策略核对通过，正式 `commit-snapshot` 已确认远端并提交本地 checkpoint。生产正向 Access、Source 动态请求和阅读仍未验收；用户选择稍后登录。

## 固定身份与范围

| 项目              | 本次身份                                                           |
| ----------------- | ------------------------------------------------------------------ |
| Worker version    | `9a95d6e6-7578-4781-99aa-3d8bdae6b467`                             |
| snapshot revision | `702cc6bfb2974682bf1c83325458535a`                                 |
| parent revision   | `22378bbcb89d40f5a0397c5098310072`                                 |
| index SHA-256     | `93228f734c1908a3baf467d90f03565c899826a3a71c6afda64214bc0de25219` |
| host fingerprint  | `d76795dcf2d36e8e6ec89447446e4b1a16d491f21fbf4c47eae37a4d1041613b` |
| materials version | `629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b` |
| 协议              | host ABI v4、protocolVersion 2、HTTP bridgeVersion 2               |

三包 AOT 固定 `1f599cd`，与部署提交的产品 host 输入相同；原 JAR、buildId、manifest/bundle 摘要和本地运行分项见[v4 Source 记录](v4-source-runtime.md)。此次没有重新编译扩展或修改其验证标记，仍为 `compiled_unverified` / `runtimeReady=false`。

索引只包含 xkcd、Arknights Comics、CuuTruyen 三包。build-state 为 available 3、unavailable 1、pending 1445、failed 0；旧 MangaDraft 只保留不可用诊断，不进入索引或复制旧 ABI 正文。`bootstrap.complete=false`，首次全量 baseline 仍未完成；定时扩展工作流继续 `disabled_manually`。本次未启动全量 AOT，未改动历史 v1/v3 checkpoint。

## 部署与 checkpoint

部署前，远端 D1 显示没有待应用迁移。三包冻结计划使用经过索引摘要校验的远端 state 对齐基线，保留原 descriptor 与构建身份。正式 `prepare-snapshot` 生成新目录；显式指定该目录执行完整 `pnpm build`，最终输出仅包含当前三份清单/gzip 和匹配的共享材料。固定提交的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41956751079) 为 completed/success。

在确认没有并发发布器后，紧邻部署执行 `check-base`，再执行 Wrangler deploy。部署成功后运行正式网络政策同步、逐包显式登记，最后查询 D1 核对。匿名验收完成后，正式 `commit-snapshot` 再次读取远端 index/state；本地 state 与候选 build-state 逐字节一致，revision 已前进至上表值。没有手写 checkpoint 或仅凭 Wrangler 成功更新状态。

部署与恢复入口以 [EXTENSIONS](../EXTENSIONS.md#候选部署与-checkpoint) 为准。本次复核命令为：

```sh
node tools/extensions/pipeline.ts commit-snapshot \
  --state .local/v4-production/state.json \
  --assets-dir .local/v4-production/snapshot
pnpm --filter @karuyomi/api exec wrangler d1 execute DB --remote \
  --command 'SELECT package_name,build_id,bundle_sha256,status,allowed_hosts_json FROM extension_builds ORDER BY package_name' \
  --json
```

生产 parent 已前进，旧 v1/v3 冻结候选不能直接部署覆盖当前快照。后续发布必须从已确认的新 checkpoint 规划当前 v4 输入，并继续串行发布；历史批次保留其当时证据。

## 已通过的远端分项

匿名工具于 02:51:05–02:51:14 UTC 对 26 个不同路径各 GET 一次，`passed=true`、零失败，不携带应用或 GitHub 凭据，也不跟随 API 登录跳转：

- index、build-state、三份 manifest 与本地候选逐字节一致，ABI/protocol 身份正确；索引和清单使用 no-cache。
- 三个 gzip 均返回 200、`application/gzip`，没有 HTTP Content-Encoding，具备一年 immutable 与 nosniff。每份收到的 gzip 仅调用现有 `decodeBundle` 一次，encoded/canonical 双域完整性与大小验证通过。
- 共享 catalog 与本地 dist 字节一致；六份共享桥/WASM 的长度、摘要、MIME 和 immutable 缓存正确。
- 原生产 MangaDraft/Arknights 的两份旧 manifest 和两个旧 gzip 路径均为 404；未知扩展以及三个 Native 内置资源路径也为 404。该结果不证明客户端已清除旧本地缓存。
- 正式 `/`、`/runtime/host.js` 返回 200；匿名 `/api/bootstrap` 实际 302 到配置的 Cloudflare Access 团队。

远端 `extension_builds` 查询成功且只有三行，buildId、canonical bundle SHA 与当前 manifest 相同，status 均为 `verified`。这里的 status 表示网络政策登记，不是 Source 运行兼容标记。允许主机为显式配置：

| 包               | allowed hosts                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------- |
| xkcd             | `xkcd.com`, `imgs.xkcd.com`                                                                         |
| Arknights Comics | `arknights.global`, `webusstatic.yo-star.com`                                                       |
| CuuTruyen        | `cuutruyen.net`, `hetcuutruyen.net`, `storage-bravo.cuutruyen.net`, `storage-charlie.cuutruyen.net` |

Codex 内置浏览器的生产 Flutter 首页可加载，进入浏览后实际显示“访问验证已失效，请重新登录”。生产登录页也显示 Access 登录入口；没有导出 Cookie/JWT 或绕过鉴权。用户回复“稍后登录”，因此本次没有正向 bootstrap、生产 Source 请求、阅读或失效后恢复结论。

## 剩余门槛与证据位置

真实登录后仍须核对 protocolVersion 2 的 bootstrap、本人身份、动态 Source HTTP、正式阅读与进度，以及单独的 Access 失效/重新认证恢复门。Native 必须重建正式 `lib/main.dart` 并单独登录 WebView；本次 Web 部署不会更新已安装 App，IAB 会话也不等于 Native 会话。Native 主入口、真机和完整 P0 验收均保持待完成。

计划、候选、checkpoint、构建/部署日志、策略查询、匿名报告及浏览器截图保存在 ignored `.local/v4-production/`。原始 JSON 和临时验收工具不纳入源码。核对后无本轮 pipeline、Wrangler D1、Source probe、workerd 或 TeaCompiler 活动进程；该进程检查不作为性能或资源峰值证据。
