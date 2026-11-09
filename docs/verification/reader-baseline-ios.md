# iOS 模拟器的真实阅读采集基线

2026-11-10，以固定 `2c012dbb0f45f88d6da4532204485ea24424f46d` 的正式 `app.main()` 和冻结 `c04d436` 的 Arknights Comics v6 1.6.2 采集一次真实阅读流程。用 iPhone 17 Pro / iOS 26.4（23E244）专用模拟器、Flutter 3.47.5 / Dart 3.13.4 debug、arm64 macOS 27.0.1 / Xcode 27.2。应用内报告为竖屏、逻辑视口 402×874、DPR 3、刷新率 60 Hz。官方 Wrangler HTTPS / workerd / D1 使用隔离身份 `acceptance-owner`；测试 CA 仅用于回环验收，正常校验证书和主机名。

实际提供的索引、扩展清单和 gzip 已核对；运行材料清单与先前核验的同组六份材料字节一致。单包快照为 `b1ab2d45307a4a2cbc51ccfcb38860d7`，build ID 为 `ext-en.arknightscomics-48a036bbf2f728fa5df501db31a28903-e04bbbaa083a27afed28e79d20742d59c89b1c998250f65254270240079131e6`；英语 Source `5973713386239249589`。从正式详情进入《Prelude Suite: The Lone Walker》的《DREAM》，读第 1–7 页，在第 7 页切换「竖向连续」做三次固定拖动，再通过正式「下一章」打开《HEARTBEAT》第 1 页。两章均为 51 页，采集未读完整章；打开章节前详情和 Source 已就绪，两章均无服务端进度，未单独核验所有网络、Source 与解码缓存的冷热状态。

## 实测数据

正式 [READER_BASELINE](../READER-BASELINE.md) 的约 9.90 秒报告含 222 个事件、294 个原始引擎帧，无截断，事件和图片帧的计时均按真实 `frameNumber` 匹配。首图和翻页耗时从正式 `navigation` 事件到同目标资源的 `image_frame`；用目标页键、generation 和 resourceId 核对前置逻辑 viewport 以及随后实际显示的 `RawImage`。快速操作后没有留下目标 `viewport.decoded=true` 的精确端点，单独保留为空；下表是 Flutter 框架图片帧的耗时，不能当作物理屏幕呈现。

| 操作                             | 到匹配框架图片帧                |
| -------------------------------- | ------------------------------- |
| 从详情打开 DREAM 第 1 页         | 1,324 ms                        |
| DREAM 逐次翻到第 2–7 页          | 304、244、743、102、584、644 ms |
| 正式切到 HEARTBEAT 后显示第 1 页 | 2,830 ms                        |

三次名义 420 逻辑像素、400 ms 的拖动净位移约 628 逻辑像素。连续 viewport 帧号区间内收到 58 份 FrameTiming；在 16.67 ms 刷新预算下，build p50/max 为 1.083/34.793 ms（1 份超预算），raster 为 0.472/1.181 ms（0 份超预算）。原始 `totalSpan` 另存报告，不能用超预算样本数推断实际屏幕掉帧。两次章节退出收到 ACK，13 份成功取得的资源均有对应身份和代际的释放 ACK；这不证明进程内存立即回落。

探针从正式应用同一进程（PID 35668）以 Dart `ProcessInfo.currentRss` 约每 100 ms 采样，附关键操作点，共 109 个样本。章节打开前为 572.4 MiB，采样峰为 639.2 MiB，关闭后采样为 634.0 MiB，进程生命周期 `maxRss` 为 661.3 MiB。生命周期峰值可能包含本轮采集及导出开销；这些值只涵盖模拟器 App 进程，不含 WebContent 或 GPU，也没有测量解码 CPU、设备总内存、耗电或热状态。

## 复验与范围

本机忽略目录 `.local/ios-arknights-reader-baseline-2c012db.oOf5Bd/` 的 `REPRODUCE.md` 保存固定输入和命令。用正式 `bookmarks_sync_test.dart` 在新隔离 D1 安装并收藏，再通过 `run-ios.sh capture` 用相同材料、`READER_BASELINE=true` 和固定 `BASELINE_REVISION` 运行忽略目录里的驱动。驱动以正式面板开始、停止并复制报告，通过 Native Clipboard 读回原始 JSON；测试停止采集后将正文和 RSS 样本打包到编号日志，`extract.ts` 检查连续序号、原始报文 SHA-256 及事件数，再以 `summarize.ts` 派生指标。`evidence/` 保留原始 `baseline.json`、`probe.json`、`summary.json` 和完整日志。第一次流程虽通过，但 Flutter runner 退出时删除应用临时目录，原始报告未提取；该轮日志留在 `evidence-first-run/`，不计作有效采集。两轮服务和专用模拟器已清理，临时 TLS 私钥已删除。

这是一份单轮模拟器 debug 采集，翻页序列是六个不同目标页。真机 profile/release、同条件冷热重复分布、长图与其它格式、实际帧呈现以及 App/WebContent/GPU 合计峰值仍待实测，不据此决定解码、预取或分片优化。
