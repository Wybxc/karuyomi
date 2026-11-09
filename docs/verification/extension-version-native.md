# 正式 iOS 同版本 AOT 构建替换与续读

2026-11-10，固定产品 `426536dcdde6af1a28931ee2d8336fa70137e44c` 的正式 iOS 主入口通过默认仓库 xkcd 同版本构建替换：在旧构建收藏并确认第 2 页，切换静态资源后经管理页明确确认新构建，运行时扩展代码缓存移除旧副本；新进程从原书架首次打开即显示新构建提供的第 2 页，退出未改变服务端阅读状态。

## 固定输入

iPhone 17 Pro / iOS 26.4 专用模拟器，Xcode 27.2、Flutter 3.47.5 / Dart 3.13.4、Node 24.15.0、pnpm 12.6.0、Wrangler 4.156.1。正式 `app.main()`、Native 运行时、官方 Wrangler HTTPS 验收入口使用同一 `https://127.0.0.1:52011`、同一空库起步的隔离 D1 和签名身份 `acceptance-owner`。回环测试 CA 加入专用模拟器，使用正常 TLS 校验。

两份工件均来自冻结 `c04d436` 的 xkcd **1.6.1**，包 `eu.kanade.tachiyomi.extension.all.xkcd`，英文 Source `1538249443376436084`，输入指纹 `31777c287c69f021ac4ebcdcd0a35cac8304c872dbe9a8f5ff0178efd68949b1`，同一组六份运行材料、host v6 / control 2 / bridge 2 / release9。两者是不同的构建 ID 和 bundle，并非上游版本号升级。

| 工件 | 来源                                                                                 | buildId                                                                                                          |
| ---- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| 旧   | 本地既有 `.local/details-fault.WdZHpi/dist/public`                                   | `ext-all.xkcd-31777c287c69f021ac4ebcdcd0a35cac-43d97485f779b768af7861a6a25522db433ab6d229a6d989e70e3f3c88a848a3` |
| 新   | 从 clab 只读取既有 `linux-smoke-xkcd` 指定工件，经正式 `prepare-snapshot` 校验与装配 | `ext-all.xkcd-31777c287c69f021ac4ebcdcd0a35cac-792d491c6e1169cc165332d0e21723c53e5ed964574af99614e4ce5d034257bb` |

新清单的官方序列化补出空的 `preferenceSyncRules`；除此及构建、bundle 字段外，两份清单一致。两份静态目录经官方 Vite 构建各自只含当前构建，未启动 AOT，未改 clab 冻结输入或正式发布状态。

## 操作与独立核对

| 阶段                 | 实际结果                                                                                                                                                              | 账户 / 全局 / 作品 revision |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| 旧构建已确认         | 正式 UI 安装、收藏 `SINGLE`、阅读 `/3319/`（`3319: Elevators`）真实图片并确认第 2 页。退出章节并释放资源，同一运行时仍能枚举唯一的旧构建缓存。                        | `4 / 1 / 3`                 |
| 已换静态快照         | 官方 Wrangler harness 用 `switch` 切换配置，origin 与 D1 不变；新清单及 gzip 实际返回 200，旧清单及 gzip 返回 404。六路只读 API 与切换前逐字节相同。                  | `4 / 1 / 3`                 |
| 明确确认更新         | 正式 UI 点「检查更新」后仍选择旧构建，旧缓存仍在；点「准备并确认更新」后，运行时扩展代码缓存只剩新构建。独立核对显示确认只改账户安装项的 build/hash 和相应 revision。 | `5 / 2 / 3`                 |
| 新进程首次续读并退出 | 从原书架直接续读，首次显示精确新构建提供并真实解码的第 2 页。阅读 epoch 0、当前位置、最远位置和章节页清单版本均保留；退出后六路响应与确认后逐字节相同。               | `5 / 2 / 3`                 |

六路 API 为设置、书架、作品、书签、进度、目标章节。前后核对证明业务状态与 revision 未被额外改变，不是网络写请求计数。旧缓存清理在同一运行时实测；新进程验证从 D1 恢复账户选择和进度，未单独验证代码缓存跨进程持久性，也未验证 Source HTTP Cache 正文或普通文件在换版后的复用。

## 复验与范围

仓库忽略目录 `.local/native-xkcd-build-replacement-426536d/` 的 `REPRODUCE.md` 保存固定输入、双快照装配、正式 HTTPS 配置、专用设备、三阶段 Flutter 参数和独立采样命令。旧快照从固定产品副本用 `EXTENSION_ASSETS_DIR="$old" pnpm acceptance:build:native` 装配；新快照经 `prepare-snapshot`、正式 runtime-host/native assets 构建后，用 `EXTENSION_ASSETS_DIR="$new" pnpm --filter @karuyomi/api build` 和该包的 `vite.acceptance.config.ts --mode native-acceptance` 生成。使用 `ACCEPTANCE_NEXT_CONFIG` 运行官方 `pnpm acceptance:serve`；保留同一个 iOS 运行时贯穿旧构建阅读、切换和缓存清理，确认后再新开进程续读。

`evidence/` 内保留隔离驱动差异、两套静态 HTTP 结果、四阶段六路快照、三份正式 Flutter 日志和独立验证汇总 `verified.json`。三个 Flutter 阶段、驱动分析/格式及独立校验均通过。两轮早期中止分别未观测到重启后旧缓存、未找到滚出视口的短暂提示；均在确认前停下，前后快照一致，保留在 `first-attempt/`、`second-attempt/`。本轮模拟器、临时服务及私钥均已清理。

此记录只覆盖默认仓库的 iOS 模拟器同上游版本换构建。Native 真正上游版本升级、Android 换版、停用与卸载等完整生命周期、真机和生产 Access 仍待独立验收。[历史 Web Arknights 1.6.1 → 1.6.2](extension-version-web.md)是另一套固定输入的上游版本升级记录。
