# Karuyomi 0.1.0 Web 生产发布

2026-11-10 23:18:48（UTC+8），[Karuyomi Web](https://karuyomi.wybxc.cc/) 与 API 的全部生产流量切至首版。真实 Access 测试账号通过 xkcd 安装、收藏、阅读、保存与重开续读。iOS、Android 的正式签名、真机和同账号三端读写仍待验。

| 项目           | 已确认的发布输入                                                                                                                                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Web 版本       | `0.1.0+1`                                                                                                                                                                                                                          |
| 源码           | [`0f43779d4d9ea1ec965154c2897551230a088bcb`](https://github.com/Wybxc/karuyomi/commit/0f43779d4d9ea1ec965154c2897551230a088bcb)，`codex/first-release`，[通用 CI 通过](https://github.com/Wybxc/karuyomi/actions/runs/42841930912) |
| Worker version | `e37f0569-6ceb-4499-ace7-4ca09746b781`                                                                                                                                                                                             |
| 扩展快照       | `3c24b0d7c0a745a58de4bd6b5ffb7654`，父 revision `702cc6bfb2974682bf1c83325458535a`                                                                                                                                                 |
| Index SHA-256  | `b819024786b18fa87be8f9f16b350cf4e70564268e592d28946866d24ccf11eb`                                                                                                                                                                 |
| 运行时材料     | v6、六材料 `5d1260e5d20b2f2f05fd378a6e8b697338e5fdfd4feca2c5a8c361e756bb92e4`                                                                                                                                                      |

完整候选的 `pnpm check`、`pnpm flutter:check`、`pnpm build` 与生成配置的 Wrangler dry-run 通过。静态快照可分发 1,371 包；另有 77 包构建失败、零待构建。发布只确认分发身份；包仍保留 `compiled_unverified/runtimeReady=false`。当前 `main` 使用七份运行时材料，不能用它重建本次快照。扩展增量 CI 保持停用，启用前须先发布与该工作流匹配的基线。

## 切换与确认

按[旧网络登记部署切换](../EXTENSIONS.md#旧网络登记部署切换)执行。先确认旧 Worker `1244f8cb-d5f4-4ccf-b40d-f963a2955fb5` 承接全部流量、D1 账本连续至 `0003`、封面桶无公开入口。上传新 Worker 和 Static Assets 后，读回仍由旧版服务。先应用 `0004–0008`，临切前核对生产父快照并留存 D1 Time Travel 恢复点。随后应用 `0009` 并切到新版，切换前后书架和进度行数一致。

生产 Web 实际读图与续读通过后，应用 `0010_remove-extension-network-registry.sql`。再次只读确认账本连续至 `0010`、待应用迁移为空、旧网络登记表已移除，且全部流量仍由同一新版 Worker 服务。

首次 `commit-snapshot` 使用的新检查点文件缺少父状态，工具在确认远端后拒绝写入。将切换前已下载的生产状态与历史已确认检查点比对，并核对当时的索引摘要后，才以该父状态初始化本次独立文件。再次用正式 `commit-snapshot` 核对生产 index/state 与候选并成功提交。新文件逐字节等于候选状态，`bootstrap.complete=true`；未改历史检查点。

## 实际 Web 验收

- 37 条匿名路径通过：应用 shell、运行时、目录和设置规则可读；六份共享材料摘要通过；xkcd、Arknights Comics、CuuTruyen、MANGA Plus Creators 四包的清单与 gzip 传输/原文摘要通过。旧三包清单和 gzip 均返回 404；五个匿名 API 路径仍跳转 Access。
- 在 Codex 内置浏览器由用户登录真实 Access 测试账号。正式客户端打开书架、安装 xkcd 1.6.1、从英文 Source 打开作品详情并收藏，显示 `3319: Elevators` 两页并确认第 2 页已保存到服务端。关闭原标签，在新标签从书架直接续读，首次显示第 2 页文字图。
- `0010` 完成后再重载客户端，书架仍能直接恢复 `Elevators` 第 2 页。随后从详情打开此前未读的 `3322: Dragonfly`，确认首图显示且第 1 页已保存，验证清理后的 Source 请求和进度写入。
- 首次安装 xkcd 后回到浏览页，视觉目录已将它置顶，辅助功能树仍保留旧行；重开客户端后可通过辅助功能进入。复现与修复见下文。

可复验输入、迁移/流量读回、匿名检查命令和续读截图留在本机忽略目录 `.local/first-release-0.1.0.7lGF2d/production/`；其中 `confirmed-state.json` 为确认后的生产检查点。

## 首装后的目录顺序

2026-11-11，从六材料分支、完整扩展快照和新隔离 D1 复现。在 Codex 内置浏览器启用辅助功能，从空账号安装 xkcd 并等账户确认，返回浏览页时视觉首行已是 xkcd，但原版辅助功能树仍列旧行。修复让每个扩展成为独立滚动行，换位时更新该行的辅助功能节点。

同环境复验：从 `0 / 128` 安装并等服务端确认 `1 / 128`，直接返回，不刷新页面。浏览器 DOM 与辅助功能树均把 xkcd 排在 AHottie、Akuma 前，可通过辅助功能控件打开 `xkcd · en` 并看到漫画列表。完整 Flutter 检查、617 项应用测试、完整快照的正式 Web/Worker 构建和 Wrangler 上传预演通过。

2026-11-11 00:13:41（UTC+8），发布分支 [`2f5a8ec`](https://github.com/Wybxc/karuyomi/commit/2f5a8eca655638d8f3e88fdeee6b93dd257088f2) 的[通用 CI](https://github.com/Wybxc/karuyomi/actions/runs/42850970404)通过后，Worker `537cd188-b50c-43db-8852-69087681796e` 接管全部生产流量。Web 版本仍为 `0.1.0+1`，Worker 脚本、绑定、扩展索引与状态、运行时材料保持原样；D1 账本仍连续至 `0010`。37 条匿名路径复验通过，线上 `main.dart.js` 与本次候选字节一致。

真实 Access 测试账号在新标签页读回书架；生产目录的首个辅助功能条目为已安装的 xkcd。旧阅读标签持有漫画源时，新标签显示占用提示；刷新旧会话的服务端进度后确认已保存，关闭旧标签并连接即可恢复《3322: Dragonfly》第 1 页。在新版翻到第 2 页并获服务端确认，关闭后从另一个新标签页直接续读，实际显示第 2 页文字图。生产复验沿用现有安装；空账号首装回归使用上面的隔离环境。切流与匿名检查留在本机忽略目录 `.local/first-run-catalog.HIprOz/production/`。

## 生产代表源整章与续读

2026-11-11，核对现网全部流量仍为 Worker `537cd188-b50c-43db-8852-69087681796e`，索引摘要与上表相同。使用同一个真实 Access 测试账号和 Codex 内置浏览器，从生产默认 Keiyoushi 目录安装并由账户确认 Arknights Comics 1.6.2 与 CuuTruyen 1.6.2。分别从原 Source 列表打开作品、加入书架、逐页阅读。每一页都等当前页码、同页最远位置与「阅读进度已保存到服务端」同时成立；首、中、末页另外核对实际画面。

| 漫画源              | 完整章节                                                                                       | 跨章与新会话续读                                                    |
| ------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Arknights Comics en | 《Prelude Suite: The Lone Walker》`DREAM`：第 1–51 页逐页确认，末页显式标记读完                | 正常进入 `HEARTBEAT`，确认第 3 页；新标签从书架首次显示第 3 页实图  |
| CuuTruyen vi        | 《Spy x Family (FULL HD)》`Chương 142`：第 1–23 页逐页确认，末页显式标记读完，核对原扩展处理图 | 正常进入 `Chương 141`，确认第 3 页；新标签从书架首次显示第 3 页实图 |

两次续读均先关闭旧阅读标签，未经过作品详情。最后的新标签读回 xkcd 与这两部作品。逐页确认记录、完成状态和实图保存在本机忽略目录 `.local/first-run-catalog.HIprOz/production/representative/`。这是 xkcd 之外的生产 Web 证据；没有更改扩展快照，不将其它包标为已验收，也不代替 Native 生产 Access、同账号三端读写或签名真机验收。

## 原生交接

六材料完整候选已产出 Android arm64 release APK 和 iPhoneOS arm64 App；两包未签名。已将归档的客户端产品源码、平台文件、Dart 依赖锁及三份内置运行时文件与首发输入逐字节比对，包内材料身份与生产一致。成品在本机忽略目录 `.local/prototype-full-six-material.tLNTHI/artifacts/`。同一首发源码和扩展候选还通过了 [MANGA Plus Creators iOS 模拟器完整章、跨章与新进程续读](aot-current-pilot.md#完整目录的代表源复验)。这些结果是构建或隔离模拟器证据。

目录修复后，以六材料发布分支 [`2f5a8eca655638d8f3e88fdeee6b93dd257088f2`](https://github.com/Wybxc/karuyomi/commit/2f5a8eca655638d8f3e88fdeee6b93dd257088f2) 重建 Android arm64 release APK 和 iPhoneOS arm64 App，均未签名。包名、生产地址、架构和包内六份材料均核对通过，Dart 锁文件未变。新版成品与核对记录在本机忽略目录 `.local/first-run-catalog.HIprOz/` 的 `artifacts/` 与 `native-*-verified.json`。未执行真机安装或生产 Native 登录。

续办时用修复后的六材料源码构建，默认 `APP_ORIGIN=https://karuyomi.wybxc.cc`。Android 按[发行签名配置](native-main-entry.md#android-发行签名配置)使用正式密钥；iOS 使用对应 `dev.karuyomi.karuyomi` 的 Apple Team、签名身份和 provisioning。真机分别通过生产 Access 登录同一测试账号，先跑 Web → iOS → Android → Web 的非默认页保存/续读，再按 [P0](../plan/p0-runtime-and-reading.md#验收)和 [P2](../plan/p2-sync.md#验收)补齐代表源、真实设备操作和一致性门。
