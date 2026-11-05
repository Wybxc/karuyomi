# host ABI v4 的原 Source 运行复验

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-05，固定 `1f599cd5ce0ff716d3a6a1fbe85d816d74a53565`，在独立验证树重新构建 xkcd、Arknights Comics 与 CuuTruyen，并使用 Codex 内置浏览器 Chromium 156 运行真实元数据、原 Source 图片处理、浏览器解码及释放分项。三个完整报告均为 `finished=true`、`imageGate=passed`。本记录不代表生产 Access、Native、真机或完整 P0 验收。

## 固定输入与交付身份

工作树为 `/Users/wybxc/.codex/worktrees/ui-image-baseline-validation/karuyomi`。正式 planner 扫描 1448 包、0 discovery failure，仅顺序构建本次三包；构建期间 host 输入保持固定。该次验证未启动全量 AOT、未部署、未修改历史 v1/v3 checkpoint，也未完成新的全量 baseline。随后三包与正式客户端/API 已部署，部署范围和匿名验收另见[生产记录](v4-production.md)，不改写本记录的本地运行范围。

- host 输入指纹：`d76795dcf2d36e8e6ec89447446e4b1a16d491f21fbf4c47eae37a4d1041613b`。
- 材料版本：`629d6e30fe3a1ac956e39630354cfd5ce390923c4b07af2a0603a181d348d11b`；catalog SHA-256：`9215919337449082bac57f9946027088bc870b0490036777ad6ad224aa98109f`。
- 协议：`hostAbi=karuyomi-source-host-v4`、`protocolVersion=2`、`bridgeVersion=2`、`runtimeBaseline=teavm-0.16.0-js-release9`；storage schema 为 `release9-v1`。
- 工具链：Node 24.15.0、JDK 25.0.5、Maven 3.9.11、TeaVM 0.16.0；锁与 seed 仍由正式准备器校验。
- 上游 pin：extensions-source `efa93f5a3537856fe830450bbe33f69d21d28167`，Suwayomi `6b481e8b62938b9c060eb210b934e0fbfdfa466b`，TeaVM `e87d452e4bd70c77b9e19314a46c3d6971c148b6`。必需 submodule 匹配 gitlink，tracked clean。

官方 Gradle 生成的原扩展 JAR 未修改；宿主适配位于项目自有源码。摘要与此前原 JAR 基线一致：

| Source                 | 原 JAR SHA-256                                                     |
| ---------------------- | ------------------------------------------------------------------ |
| xkcd 1.6.1             | `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d` |
| Arknights Comics 1.6.2 | `e1a706cc4b504af04bf2ebbb3046d36421a949fca0633e69166e34415d657cf3` |
| CuuTruyen 1.6.2        | `5bdd45cd036c0be02097bd025d359293d33485848210fcd809ad063715e263ce` |

| 本地目录    | buildId                                                   | canonical 字节 | gzip 字节 |
| ----------- | --------------------------------------------------------- | -------------: | --------: |
| `xkcd`      | `ext-all.xkcd-d923dd3fb233cfd194936da9cca51309`           |        4033242 |    852774 |
| `arknights` | `ext-en.arknightscomics-1cf2870991dad50ff7c54d8701fa59be` |        1904906 |    605322 |
| `cuutruyen` | `ext-vi.cuutruyen-16366de1277e199886b6a2c90f51cea5`       |        2108833 |    656285 |

| Source           | manifest SHA-256                                                   | canonical bundle SHA-256                                           |
| ---------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| xkcd             | `cf2c7f570d569ce5a3b6af936dc21ddd76bdd9b225d62a53bdfdae44380a5918` | `439efb7adc083c8b28b9dc8f1429974c6388763a075402ae17e823e8a1693f74` |
| Arknights Comics | `10d6261f92d0f4e29e26e7320fcb21e4d0ac342015e77aaf65c65aeeda401ef0` | `338f3c62055ceb7a8d9d0fab010d4c5b8f16a426bd90208eddf3bd0c3c8269a2` |
| CuuTruyen        | `354a1a1c05d482785520dd468775e5c940a19cc0e97d4d4dda78335ee766ae23` | `f9bca45fde99312833508628b002ae71706dfd54ad30e6c168f0cb6d61218552` |

## 在线分项

入口为固定树的正式 `apps/api/test/source-metadata-probe.ts`，使用产品 host/Worker、直接静态 gzip、真实 workerd HTTP v2、仅含显式网络政策的隔离 D1，以及实际 RS256 校验的本地测试身份。loopback API hop 使用测试 origin alias；报告明确为 `realRS256Verification=true`、`productionAccessVerified=false`。政策按下表精确主机设置，没有从请求自动学习白名单。

| Source / Source ID                     | 显式允许主机                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------------ |
| xkcd 英文 `1538249443376436084`        | `xkcd.com,imgs.xkcd.com`                                                                   |
| Arknights Comics `5973713386239249589` | `arknights.global,webusstatic.yo-star.com`                                                 |
| CuuTruyen `8222087175453285202`        | `cuutruyen.net,hetcuutruyen.net,storage-bravo.cuutruyen.net,storage-charlie.cuutruyen.net` |

| Source           | 实际元数据                                                                                               | 实际图片                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| xkcd             | 热门 1 项；搜索按原实现返回 0；详情、3319 章、`3320: House Majority` 两页成功；latest 按源声明跳过       | 页 0：70925 B、546×596；页 1：原 TextInterceptor 文字图 38446 B、1000×238                      |
| Arknights Comics | 热门 17 项、标题搜索 1 项、详情及 3 章；`DREAM` 返回 51 页；latest 按源声明跳过                          | 首/中/末 0/25/50：39602/719916/718931 B，均 1200×1691                                          |
| CuuTruyen        | 热门两页各 24 项、标题搜索 5 项、latest 30 项、详情及 175 章；`Chương 142` 返回 23 页，全部保留 DRM 引用 | 首/中/末 0/11/22 经原 Source 解密重排：746910/493881/563725 B，2048×1152、1024×1606、2048×1223 |

2/3/3 张要求图片均通过实际浏览器解码；每张撤下后释放并确认 Blob URL 已 revoke，最后取得 `pageSessionClosed=true`，三个通过报告均无 `disposeError`。没有直接使用原图 URL 绕过 Source，也没有让 Source 宿主识别图片 MIME、尺寸或方向；表中尺寸来自客户端解码。xkcd 的文字图保留原 TextInterceptor 处理，CuuTruyen 保留原图像解密重排。

CuuTruyen 的服务日志保留一次 `probe_client_disconnected`；后续完整报告才取得上述全部成功及释放终态，不能将其写成全程无错误。网络报告中的响应字节、摘要和请求计数也不构成 Cache 命中或进程/GPU 峰值证据。

## 正式 Flutter 阅读与跨标签写入门

同一固定输入的正式 Flutter Web 主入口通过“浏览 → xkcd → 详情 → 章节”打开 `3320: House Majority`。直图与原 TextInterceptor 文字图均实际可见，单页布局及显式“读完本章”完成后显示 `2 / 2`、本地进度已保存、最远第 2 页及本章已读完。截图 `xkcd-reader-completed.png` 与语义记录 `xkcd-reader-completed.txt` 保存在同一 ignored 目录；这不是仅用 probe 的图片计数替代正式 Reader 显示。

正式 Reader 标签持有同一 namespace 时，另一个同 origin `/probe` 标签实际打开相同扩展，返回 `openError.code=storage_busy`，没有启动元数据操作或图片获取，记录为 `xkcd-storage-busy.json`。该拒绝报告的 `imageGate=failed` 表示没有运行图片门，不能当成 Source 图片失败或成功。关闭正式 Reader 标签后，第二标签重新加载并运行，成功获得新的 Worker 和 generation `95798b04-34d1-4f84-b344-9afa21eba9c8`，两张图解码、释放及 Page session 关闭均通过。最终 `xkcd-online-passed.json` 对应这次重开；冲突记录单独保留。这证明此次真实标签生命周期中的写入门拒绝与释放后重新取得，不代表所有异常终止或多窗口场景。

## 复验与证据位置

完整计划、三包 descriptor/provenance、manifest/gzip、构建日志与报告均在 ignored `.local/v4-source-validation/`，没有将机器输出或图片正文提交为源码。三个不可变通过报告为 `xkcd-online-passed.json`、`arknights-online-passed.json`、`cuutruyen-online-passed.json`。编译与完整性验证依然记录 `compiled_unverified`、`runtimeReady=false`；本次人工分项没有改写流水线验证状态。

在同一固定树中，可从新 planner 产出的 descriptor 重建至全新目录，再启动正式 probe：

```sh
node scripts/build-extension.ts \
  --descriptor .local/v4-source-validation/xkcd/descriptor.json \
  --output .local/v4-source-recheck/xkcd
pnpm --filter @karuyomi/runtime-host build
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_IMAGES=1 \
SOURCE_PROBE_EVIDENCE=.local/v4-source-recheck/xkcd-online.json \
node apps/api/test/source-metadata-probe.ts \
  .local/v4-source-recheck/xkcd/manifest.json \
  .local/v4-source-recheck/xkcd/artifacts
```

在 Codex 内置浏览器打开命令输出的 loopback URL，点击 `Run real metadata operations`。另两包更换 descriptor、目录及上表的 Source ID/主机集合。原产物目录已含不可变 manifest，不能作为重建输出；host 输入变化后必须重新运行 planner，不能沿用旧 descriptor。

测试结束后三个 Source 服务均已停止；另行核对原监听端口均无监听，且无本轮 Source probe、workerd、Gradle 或 TeaCompiler 进程。未将浏览器标签关闭或命令退出码本身视为完整资源账本或进程峰值清理证据。

本轮尚未证明生产 Access 失效与恢复、Native 正式主入口、真机、多源完整章连续切章、所有取消阶段或设备性能。enqueue owner/drain 的受控实际 TeaVM 验证见[专门记录](teavm-enqueue.md)，不从三源正常 RPC 成功推导。P0 总状态仍按[计划](../plan/p0-runtime-and-reading.md)维护。
