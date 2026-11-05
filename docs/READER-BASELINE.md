# 阅读器直接解码基线采集

当前默认图片路径为 Flutter/UI 直接解码，候选分片不进入默认构建。本入口采集正式应用的原始事件和 Flutter 帧计时，用于建立对照条件；入口可用不代表性能门已通过。计划见 [图片解码](plan/reader-image-decoding.md)，实际证据见 [UI 图片边界](verification/ui-image-boundary.md)。

## 构建与使用

在固定、干净的验证 checkout 中，按 [扩展构建](EXTENSIONS.md) 重建匹配当前 host 的原版 Source，并构建 runtime-host。使用仓库锁定的 SDK：

```sh
pnpm --filter @karuyomi/runtime-host build
node scripts/assemble-native-assets.ts
pnpm flutter:setup
node scripts/flutter.ts build \
  --dart-define=READER_BASELINE=true \
  --dart-define=BASELINE_REVISION=<完整提交号>
```

通过正式 Flutter 入口使用“性能采集”。在需要测量的操作之前打开面板、开始采集并收起面板，正常进入章节、跳页或滚动，再打开面板停止。停止后最多等待 1.5 秒接收已开始帧的计时。使用“查看摘要”确认事件、帧数与截断状态；面板只显示最多 1024 字符的预览，不布局完整报告。Web 和 Native 均可使用“复制 JSON”取得完整报告；Web 另保留“下载 JSON”。自动化验证优先通过面板复制，再用 Codex 内置浏览器的剪贴板接口读取正文并保存到 ignored 本地证据目录，避免每次下载需要人工确认；“已请求下载”只表示调用已发起，必须另行检查实际文件存在、可解析且包含完整正文。默认每次最多 60 秒、12,000 个事件及 12,000 个帧样本；触及限额的报告标为 truncated。关闭应用会撤销计时回调、定时器与本次下载的 Blob URL。

Web 文件下载直接使用精确锁定的 `cross_file`；每份报告复用一个下载文件，新采集或卸载时释放其 Blob URL。查看摘要不依赖剪贴板权限。复制使用 Flutter 官方 Clipboard，在按钮操作中写入完整报告；“已请求复制”不代表读取完成，需核对实际读取的 UTF-8 字节、revision、事件和帧样本。

未设置 `READER_BASELINE=true` 的正常构建不挂载采集面板或记录器。测量使用正式 `main.dart`、Source、provider 和图片解码路径；不安装全局 JS 控制接口，不用测量入口代替产品导航。

## 事件含义

| 原始数据                         | 可说明的范围                                                                                               |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| 章节动作、阅读器附着及导航 epoch | 操作起点与目标；附着已晚于章节元数据请求，不冒充点击章节时间                                               |
| acquire 开始、结果及资源身份     | 实际 provider 获取，Native 包含 Source 与文件交接；不是纯网络或 decoder CPU 时间                           |
| ImageInfo 与 synchronousCall     | 实际显示 provider 的解码结果/同步缓存命中；不创建额外 decoder                                              |
| image frame 与 post-frame        | 图片参与的 Flutter 框架帧及帧尾通知；不是物理屏幕呈现                                                      |
| viewport                         | 布局后与逻辑内容区相交的页、当前资源/代次及 decoded 状态；排除页间距，不证明遮挡、letterbox 像素或物理可见 |
| release 请求、发送与 ACK         | widget/frame/cache 清理等待和实际 provider 释放；不能证明 RSS/GPU 回落                                     |
| FrameTiming                      | 引擎原始 phase、build/raster/totalSpan、帧号与回调接收时间；raster 时长不是独立 GPU 执行时间               |

事件用单调 Stopwatch；引擎 phase 保留自身 epoch。只能用实际 engine `frameNumber` 关联，不能直接相减不同时钟，也不能用图片自身的解码帧序号关联。Flutter 批量上报时序，Web 还可能丢弃场景或不提交最后一小批；没有精确匹配就保留 unmatched/unavailable，不用下一条计时补齐。停止时不会无限等待或把缺样本填零。

开始和停止所处的边界帧可能包含面板操作，只按导航事件限定目标区间，不把整份报告直接当阅读性能分布。若在已经静止的阅读器中才开始且随后没有导航、滚动或布局变化，可能没有新的 viewport 事件；这时相关指标证据缺失。

连续列表的 cacheExtent 可能提前解码离屏图片。首图必须按目标逻辑 pageKey、导航 epoch、当前 resourceId/generation 和实际 viewport 事件筛选；任意 ImageInfo、windowReady、预取结束或进度已保存均不能充当首图端点。后续导航、布局切换和退出使旧目标失效。截图单独确认实际画面，工具点击到截图的耗时不作为精确首图延迟。

## 运行条件与验收

每份原始报告旁保存固定代码提交、原 JAR/AOT/材料身份、Source/章节/目标页、编码正文身份、设备/系统、浏览器/渲染器、DPR、视口、刷新率和操作顺序。报告自带真实构建模式、构建标签与采集时的显示环境；刷新率为 SDK 报告值，须与设备条件核对；缺少的上下文由运行记录补齐，不由采集器猜测。

分别记录网络/Source Cache、runtime 热启动和 Flutter decoded cache。重开路由、重载标签页与重启浏览器进程是不同条件，不能统称为冷/热。无障碍树是否开启、测量面板覆盖期间和采集工具开销也应保持一致并注明。

先通过一次采集完整性门，再对每类条件至少运行五次首图/跳转和固定滚动，保留全部原始样本、样本数、p50/max及按实际刷新率计算的帧预算统计。普通图不能代替长 JPEG/PNG，桌面和模拟器不能代替目标真机。iOS Simulator 在当前 SDK 只有 debug 运行，功能复验可以记录，性能不当作真机 profile/release 结论。

当前采集器不测量物理屏幕呈现、CPU、RSS 或 GPU 内存。Native `ProcessInfo` 也只涵盖调用进程，不能自动包括 WebContent/GPU；Web JS heap、逻辑编码/decoded 字节与 Flutter cache 不替代完整进程集合的峰值。profile 可结合官方 integration_test/DevTools 作归因，正式 release 时延使用实际帧回调；缺失平台指标明确标为未采集。在同输入、同设备、同显示与缓存条件下完成对照后，再决定采用成熟区域 decoder、降采样或候选分片。
