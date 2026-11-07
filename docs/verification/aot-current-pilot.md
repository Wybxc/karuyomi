# v6 本地 AOT 试编与公开构建身份

2026-11-07，在干净的独立 checkout 固定项目 `993fe544`、Keiyoushi `efa93f5a`、host ABI v6 / control 2 / HTTP bridge 2 / release9。以匿名 HTTPS 重新核对线上 build-state 与 index 的精确字节，基线 revision 为 `702cc6bfb2974682bf1c83325458535a`，`bootstrap.complete=false`。正式发现 1,448 包，无发现失败；全量计划 SHA-256 为 `ed1e73ed6eb423fdab76cdbf6b9cf82fb642f602b094597aa3d2c07b0e556eec`，大小 14,321,059 B。仅从该计划选三个代表包，按 `jobs=1` 走正式构建与静态快照装配。

| 扩展             |    耗时 |      gzip |
| ---------------- | ------: | --------: |
| xkcd             | 42.14 s | 930,610 B |
| Arknights Comics | 36.27 s | 669,533 B |
| CuuTruyen        | 41.46 s | 888,248 B |

三份终态均为 `compiled_unverified`，静态候选 revision 为 `21204762900b4cb88ed88c9d908d1a5a`，index SHA-256 为 `e424ec777f9fbdb12fd6c6d5abf041a436086e9a9ea6a3c7c134029efc26276e`。构建与装配正常退出，其余 1,445 包没有启动，未部署、未提交生产 checkpoint、未启用增量 CI。固定输入、输出和逐包记录留在本地忽略的 `/private/tmp/karuyomi-local-baseline-993fe54-yDXFKs`，只作该次证据。

## 同一输入两次输出的对照

当前候选和先前 `5ba6fff` 的 xkcd 使用同一个输入指纹 `dd84d305506e2bdc34ac62988aef645f56bb7b6567c85ed55b73d2b4284ca491`。原始 JAR、15 份 donor、seed、材料及实际工具链 JAR 摘要一致。两份 canonical JS 均为 4,477,929 B，AST 可正常解析，字符串池排序后完全相同；37 个索引和相应代码顺序发生移动。当前 SHA-256 为 `31de2bd8c529bb0cbd310725b7c400cf511be1863554bf9d55a17ffc03f27e55`，此前为 `5fd6e868d3b077db8893ce4a517dd486dc7938c04a7af5c70507ba0eabea7682`。TeaVM 0.16.0 实际字节码的依赖传播存在按对象身份哈希排列的集合，发射器依赖发现顺序；本轮未隔离触发具体重排的传播边，不声称已使编译器可复现。

当时仅以输入指纹生成公开 ID，两份不同 JS 共用同一个清单路径和索引身份。Flutter 会把已安装记录识别为当前版本，隐藏更新操作；下载准备读取新清单后又会按已确认的旧摘要拒绝打开。现有缓存与授权以 canonical SHA 隔离，两份字节不会被错误混用。旧候选保留为观察证据，原 `5ba6fff` 的在线验收不能移用到新字节。发布身份与恢复合同见[扩展静态分发](../EXTENSIONS.md)。

## 绑定摘要后的正式三包和同站 Web 更新

固定 `952bbab` 的新 checkout 再次从原 JAR 串行编译三包。1,448 条完整计划 SHA-256 `8606cad23bd27a10b5588ef0e4bdcb23cee255d53e87524bc0eb247c5c797532`；生产 parent 仍为 `702cc6bfb2974682bf1c83325458535a`，构建前后远端 state/index 字节不变，正式 `check-base` 通过。候选 revision `48dc5b618c924a6eaa53bb5ed02a49cf`，index SHA-256 `57bcd5bd0cda4d3467950c2d8b399d8f4bccb56e1f396291146bde4cc5339277`，3 成功、0 失败、1,445 待构建，`bootstrap.complete=false`。xkcd、Arknights Comics、CuuTruyen gzip 分别为 930,554、669,511、888,219 B。逐包确认公开 ID 的后缀、清单、索引、状态记录与实际正文一致；内部工作名没有公开路由。

Web 使用固定 `d2a21aa` 的 Flutter 产物（`main.dart.js` SHA-256 `178c4b43bfe620ef8df51078db0e87a8bb53c8c05d9e555f2ed221d42063794c`）。旧 `5ba6fff` xkcd 快照与新三包快照都经正式 Vite 组装，客户端和验收 Worker 的 JS 字节相同。Codex 内置浏览器在同一文档、同一 loopback origin、同一隔离 workerd/D1 和 `acceptance-owner` 进行：

| 阶段         | 实际结果                                                                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 旧快照       | 正式扩展管理确认安装 xkcd 1.6.1；从英文 Source 收藏 xkcd，打开 `/3319/` 并保存第 2 页，真实文字图显示；缓存只有旧摘要 `5fd6e868d3b0…`。                                        |
| 切换静态快照 | 官方 TestHarness 重载配置，origin 不变。独立请求确认旧清单和旧 gzip 为 404，新清单和新 gzip 为 200；独立读取的设置、书架、作品和章节进度与切换前逐字段相同。                   |
| 正式更新     | 版本号仍为 1.6.1，界面显示旧构建下架和「准备并确认更新」。确认后只修改已确认安装的 ID、摘要与对应 revision；书架、阅读锚点和其它设置不变，本机缓存只剩新摘要 `969bd86a14e9…`。 |
| 新构建续读   | 从原书架点击「继续阅读：xkcd」，首次即显示 `3319: Elevators` 第 2 页真实文字图，未手动翻页，进度获得服务端确认。独立 GET 核对 epoch、当前页与最远页的稳定 key 不变。           |

正式复验命令（依次执行，使用已核对的两个快照绝对路径）：

```sh
EXTENSION_ASSETS_DIR="$before" pnpm acceptance:build
EXTENSION_ASSETS_DIR="$after" pnpm --filter @karuyomi/api build
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts \
  --outDir "$stage/next"
ACCEPTANCE_NEXT_CONFIG="$stage/next/karuyomi/wrangler.json" \
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
pnpm acceptance:serve
```

用服务打印的 URL。旧版阅读已确认且退出后，在验收进程的 stdin 输入 `switch`，等待 `ACCEPTANCE_SWITCH=switched`；在产品界面确认更新并复验续读。输入 `stop` 关闭验收服务。切换过程只更新本地 Source 网络登记，不重跑 D1 migrations；没有用直接业务写入代替 UI。原始业务采样与构建日志留在本地忽略目录，试跑目录和文件未发布。三个候选仍为 `compiled_unverified` / `runtimeReady=false`；本门只验证 xkcd Web 更新与续读，生产、Native 更新、其它 Source 及完整 baseline 独立验收。
