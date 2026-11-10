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
- 首次安装 xkcd 后回到浏览页，已安装 Source 未立即置顶；重开客户端后可正常进入。根因未确认。

可复验输入、迁移/流量读回、匿名检查命令和续读截图留在本机忽略目录 `.local/first-release-0.1.0.7lGF2d/production/`；其中 `confirmed-state.json` 为确认后的生产检查点。

## 原生交接

六材料完整候选已产出 Android arm64 release APK 和 iPhoneOS arm64 App；两包未签名。已将归档的客户端产品源码、平台文件、Dart 依赖锁及三份内置运行时文件与首发输入逐字节比对，包内材料身份与生产一致。成品在本机忽略目录 `.local/prototype-full-six-material.tLNTHI/artifacts/`。同一首发源码和扩展候选还通过了 [MANGA Plus Creators iOS 模拟器完整章、跨章与新进程续读](aot-current-pilot.md#完整目录的代表源复验)。这些结果是构建或隔离模拟器证据。

续办时从上表源码和六份材料构建，默认 `APP_ORIGIN=https://karuyomi.wybxc.cc`。Android 按[发行签名配置](native-main-entry.md#android-发行签名配置)使用正式密钥；iOS 使用对应 `dev.karuyomi.karuyomi` 的 Apple Team、签名身份和 provisioning。真机分别通过生产 Access 登录同一测试账号，先跑 Web → iOS → Android → Web 的非默认页保存/续读，再按 [P0](../plan/p0-runtime-and-reading.md#验收)和 [P2](../plan/p2-sync.md#验收)补齐代表源、真实设备操作和一致性门。
