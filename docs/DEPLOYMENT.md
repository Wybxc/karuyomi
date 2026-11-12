# 原型阶段 Web 自动上线

用户于 2026-11-12 明确选择：**主线 CI 通过后自动上线**。功能通过必要检查并合入 `main` 后，由同一次 `CI` 的 `deploy` job 发布到 <https://karuyomi.wybxc.cc>，不另等人工确认、完整 AOT 或原生验收。分支和 PR 的检查保持正常；Release tag 不触发。

## 日常流程

1. 按实际改动做有意义的本机检查；同一输入已有通过结果时不反复本机构建或重跑完整矩阵。
2. 合入主线，CI 完成工程、Flutter、构建与本地迁移检查，保存同一 SHA 的 `web-build-<sha>`。
3. 发布 job 下载这份 Web/runtime artifact，不再编译 Flutter、共享材料或 AOT。从生产拉取完整的当前扩展快照，校验清单、材料与传输完整性，再用正式 API Vite CLI 装配。
4. 紧邻发布核对主线提交和生产快照，使用正式 Wrangler 部署并应用待执行的 D1 迁移。
5. 自动核对线上 HTML、Flutter、host/worker、材料字节及匿名 API 的 Access 跳转，保留 `web-release-<sha>` 证据 artifact。

CI 成功只表示该次发布与自动交付检查通过。涉及交互改动时做一次针对性的内置浏览器检查；登录、整章阅读、跨端同步和真机矩阵仍分别记录，不要求每次重复全部人工验收。本轮 UI 的实际生产证据见[记录](verification/browse-ui-flow.md#生产发布)。

## 扩展与发布协调

Web 发布原样保留生产 index、build-state、manifest 和 gzip，不生成新扩展 revision，不修改 `bootstrap.complete` 或运行兼容声明。因此可复用已经上线的分批快照，UI 发布无需等待全语言 baseline。协议、ABI 或所需材料不匹配时停止，不把旧 AOT 重新贴标签；配套 AOT 仍在 clab 按 [EXTENSIONS](EXTENSIONS.md)推进。

Web 与扩展的发布 job 共用 `karuyomi-production` concurrency group。扩展的 plan/build 不持有这把发布锁，不阻塞 UI；扩展切流前还检查主线身份，避免将较旧 Web 覆盖到生产。扩展增量工作流的启停及完整 baseline 门槛保持独立。

凭据使用已有仓库 secrets `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`，只交给发布步骤。日常自动上线不依赖本机 Wrangler 登录。

## 证据与恢复

入口是 `.github/workflows/project-ci.yml`、`scripts/release-web.ts` 和 `tools/cloudflare/web-release.ts`。API 资源装配仍由 `apps/api/vite.assets.ts` 负责；发布工具只处理线上快照和交付核对，不引入自有构建器。

`web-release-<sha>` 中的 `release.json` 记录源码 SHA、生产 origin、扩展 revision 和待交付文件的长度/摘要；`verification.json` 只在所有自动冒烟通过后生成。Wrangler 的版本及部署结果保留在相同 job 日志。[主线 CI](https://github.com/Wybxc/karuyomi/actions/workflows/project-ci.yml?query=branch%3Amain)是每次自动上线的执行记录。

较旧的主线作业会跳过发布。其它失败按失败步骤修复或重新运行，不补跑 AOT、不改写扩展 checkpoint，也不自动回退 D1。重跑失败 job 会再次检查当前主线和生产快照；构建 artifact 已过期时重新运行整轮 CI。
