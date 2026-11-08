# 服务端权威状态生产部署

2026-11-05，将已提交的 `466acdd5340457e40d9593ad1357a8e0e9b1844f` 部署到 `https://karuyomi.wybxc.cc`。收藏与进度 API、D1 权威读写、前台重取与 Web 独立登录窗口已进入正式部署；生产 Access 正向和 Native 配对尚未验收。

## 构建与部署输入

- Worker version：`1244f8cb-d5f4-4ccf-b40d-f963a2955fb5`。
- 扩展快照 revision 保持 `702cc6bfb2974682bf1c83325458535a`，parent 为 `22378bbcb89d40f5a0397c5098310072`，index SHA 为 `93228f734c1908a3baf467d90f03565c899826a3a71c6afda64214bc0de25219`。
- 三包仍为 xkcd、Arknights Comics、CuuTruyen；扩展 `compiled_unverified` / `runtimeReady=false` 标记未提升。available 3、pending 1445、unavailable 1；baseline 未完成，扩展 CI 继续保持禁用。
- 共享材料版本保持 `629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b`；没有重建 AOT、改动旧 checkpoint 或重新发布扩展。

使用独立 `.local/server-state-deployment/state.json` checkpoint，在部署前后通过 `commit-snapshot` 确认远端 index/state 与原三包快照逐字节相同。app/API 更新不运行扩展 `prepare-snapshot`，也不对已部署快照执行要求 parent 匹配的 `check-base`。

```sh
EXTENSION_ASSETS_DIR="$PWD/.local/v4-production/snapshot" pnpm build
diff -qr .local/v4-production/snapshot/extensions dist/public/extensions
node tools/extensions/pipeline.ts commit-snapshot \
  --state .local/server-state-deployment/state.json \
  --assets-dir .local/v4-production/snapshot
pnpm --filter @karuyomi/api exec wrangler d1 migrations list DB --remote
pnpm --filter @karuyomi/api exec wrangler d1 migrations apply DB --remote
pnpm --filter @karuyomi/api exec wrangler deploy
```

唯一待应用迁移为 `0003_overconfident_champions.sql`，纯新增 `account_state`、`manga_state`、`chapter_progress`、`state_mutations` 四张表；迁移成功，部署后列表返回无待应用迁移。没有删除或转换原生产数据。

## 实际检查与边界

完整格式、通用检查、Flutter 分析与测试、Web/API 构建和 Worker dry-run 的工程记录见[服务端状态验证](server-state.md)。真实 Web 独立会话的收藏→阅读保存→新会话续读也在该记录，使用本地 workerd/D1 测试身份。

部署提交 `466acdd` 的 [main CI](https://github.com/Wybxc/karuyomi/actions/runs/41987544385) 全部通过，包含 `pnpm check`、`pnpm flutter:check`、`pnpm build` 与本地 D1 迁移。此前 `d1e280e` 的 CI 暴露大日志测试对 stdout/stderr 全局顺序的错误假设；`db4dc57` 只修正测试为检查两路各 5 MiB 完整内容，不修改生产日志合流逻辑，定向 14 项回归通过。

部署后匿名检查 **29 个路径全部通过**：

- Flutter shell、`main.dart.js` 和 runtime host 与当前本地构建逐字节一致。
- 三包 index/state、manifest、gzip 及六份共享材料的响应、缓存头、完整性和版本匹配。每条路径只 GET 一次，每个扩展在收到字节的下载边界校验一次。
- 旧扩展路径、未知构建和 Native 专用文件返回 404；公开静态资源无需 Access。
- `/api/bootstrap`、`/api/library`、`/api/state/mutations` 的匿名请求均重定向到预期 Access 登录页，没有跟随重定向或注入凭据。

原始检查脚本与 JSON 留在忽略的 `.local/server-state-deployment/`，独立于旧生产部署证据。没有把过期的生产浏览器会话、测试 JWT 或本地双会话记录算作真实 Access 登录；生产正向与 iOS/Android 同步继续按 [P2](../plan/p2-sync.md) 验收。

## 生产 Web 恢复登录态

2026-11-08，获准在 Codex 内置浏览器打开生产域名确认 Access 状态。首次打开显示「访问验证已失效，请重新登录」；用户自行登录后，同一生产页面恢复正式书架，显示「刷新服务端书架」。记录不包含身份、凭据或书架内容。本分项只确认实际生产 Web 从过期状态恢复到登录后的书架入口；未操作登录表单、未打开 Source 或阅读器，也未验证 Cookie 轮转细节、原生回跳、跨端读写或真实 Source 请求。
