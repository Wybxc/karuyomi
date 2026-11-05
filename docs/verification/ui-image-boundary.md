# UI 图片职责边界与分片候选

2026-11-04，用户确定 Source/插件宿主只交付处理后的编码字节，图片识别与解码由 Flutter/UI 负责。本轮直接更新当前原型合同，不保留旧编码页或 host tile/window API。旧 [编码页所有权](encoded-image-ownership.md) 与 [分片控制](image-page-controls.md) 保留各自输入身份和当次证据，当前实现已替代它们。

## 当前实现

- `ProcessedImage` 只有 `resourceId/generation/byteLength`，`ImageResource` 增加受管 `url`；`ImageMeta` 为空。Proto/Buf 正式双端生成，TS/Dart 边界拒绝旧 MIME、尺寸及 encodedOnly 等字段。
- Source collector 只处理 64 KiB/ACK、总计 64 MiB、六资源及 generation/生命周期；不解析图片头，不创建 bitmap，不获取 EXIF。Java `Sink.open()`/JSBody/TS 出口均已收敛无参，交付适配不读取图片 Content-Type；Java 成功描述与传输结果一致后才发布无图片类型的 Blob URL。插件原业务主动处理图片的路径继续保留。
- Native 文件桥只复制有界编码资源，保留 URL/身份/长度与 HTTPS 校验。Swift 不根据图片 MIME 或像素做准入；Android 仍使用固定六槽二进制通道。
- Flutter 观察实际 `ImageProvider` 使用的同一个 `ImageStream`，从 `ImageInfo` 学习实际尺寸并释放自己的 handle；只有实际 frame 才推进 observed。坏编码、过预算与迟到帧不能推进进度。调度器在 release ACK 前持续计费，包含退休中和已获取但尚未准入的资源。
- `runtime/image-codec/` 仅保留为独立客户端候选。Source host 不导入该库，候选也不导入 host；专项测试允许注入宿主的传输 verifier。默认材料不准备 codec 归档、不编译 client/worker，默认 Web/Native 成品不携带该候选；专项验收显式 opt in。

## 实际工程验证

本轮完整 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build` 全部通过；通用检查包括生成一致性、严格类型、依赖、322 项 Vitest、TS↔Dart 黄金矩阵、发布/静态装配、workerd HTTP 与 94 项候选工具/运行库回归。远端 CI 仍须对应提交另行确认。

完整 Web/API dry-run 构建通过；成品 catalog 仅五个桥脚本和 zstd WASM，默认 Web 静态材料共六份，Native 目录仅 host.js、worker.js 与 manifest.json，没有候选 codec。材料版本为 `0b2ce10766319fab0fa0f3014ae10fa157ac1e74bebc24eda92a7f17b194f6ff`。

默认材料、候选 assets/tile store 的三文件 35 项 Vitest 通过；默认 catalog 的 imageCodecs 为空且准备器未调用。候选正式模块、Worker 与迁移后的测试分别经严格 TypeScript 检查通过；测试的 browser bundle 使用 esbuild 支持的 TypeScript 语法，运行库本身继续要求 erasableSyntaxOnly。

完整 `pnpm flutter:check` 已通过：Reader core 20 项、SourceRuntime 37 项、Flutter 应用 124 项；所有分析和官方 Drift 生成一致性检查通过。实际 PNG provider 回归确认观察者与 Image 共用一次 load/decode，覆盖同步缓存、坏编码、卸载后迟到和暂停。它们是工程测试；后续诊断性真实 Source 产品阅读分项单列如下。

Native Dart 定向 30 项通过，覆盖迟到原响应的正常/错 requestId/错 generation 与 host/本地释放失败组合、挂起控制随 close 结束、clear ACK 前保留文件及并发 release。Xcode 27.2（27B52）/ iOS 26.4（23E244）Simulator 的正式 `NativeImageFilesTests` 11/11 通过，xcodebuild exit=0；测试新启动的 iPhone 17 Pro 已关闭，Booted devices 为空。日志与 xcresult 位于忽略目录 `.local/ui-image-boundary/native-image-files-20261104.*`。这不等于真实 Source/Native Reader 或物理设备验收。

### TS Source 与协议证据

在 macOS main 工作区运行以下分项：

```sh
pnpm --filter @karuyomi/contracts typecheck
pnpm --filter @karuyomi/runtime-host typecheck
pnpm typecheck:tools
pnpm check:dependencies
pnpm exec vitest run packages/runtime-host/test packages/contracts/test
FLUTTER_ROOT=/private/tmp/karuyomi-flutter-sdk pnpm test:protocol
```

contracts、runtime-host 与工具严格类型检查通过，依赖检查未发现跨层违规；宿主和 contracts 的 14 个文件共 172 项回归通过。正式 host.control 测试使用真实 MessageChannel/collector，Source driver 为受控替身：任意非空字节原样交付、Java 完成前不创建 URL、描述不一致拒绝、URL 创建失败回收并释放 Source 串行槽、取消后等待退出、非协作宽限回收、迟到 cancel/close 不撤销已发布资源、旧 generation 与重复请求隔离。注入的 createImageBitmap 会抛错，该不透明字节用例仍通过；这证明宿主没有为交付额外解码，不证明字节能够显示。

TS↔Dart 黄金矩阵 9 项通过，实际运行双端生成 codec 的 ProtoJSON/二进制往返及语义校验，覆盖空 ImageMeta、三字段内部 ACK、四字段对外资源，以及拒绝旧 MIME、非空 meta 和 encodedOnly 字段。该跨语言验证不执行浏览器或 Native 容器。

默认材料测试确认 imageCodecs 为空、来源为 null 且候选准备器未调用。源码审查确认 Source host 无客户端 codec 导入，默认 build 与 Native 装配无 codec 输出路径；正常重建后的成品已按上述文件集核对，没有沿用旧 dist 目录证明新默认打包行为。以上均为工程/协议证据，不包含后续单列的真实 Source 浏览器分项或性能测试。

### Java 交付适配

`pnpm teavm:check` 已通过：原 seed 和正式自有 HttpSource 两套 `ImageTest` 各 8,355 断言，包括响应 `contentType()` 会抛错的输入仍可原样交付。原请求头、Cookie、getImageUrl/getImage、子类 Page、cacheless/progress 与原 Source 图片处理语义不变。本项为 JVM oracle，不等于新 AOT 的真实 Source 运行验收。

## 新合同的诊断性 Web 分项

固定 `c294c71a95382834df82ba6871e1c87ad54da560` 的独立 `ui-image-baseline-validation/karuyomi` 工作树，在 Codex 内置浏览器、正式 `lib/main.dart` Web release、隔离 workerd/D1 与 RS256 测试身份下，通过原版 xkcd `3319: Elevators` 的漫画页和原 `TextInterceptor` 文字页。手动改为单页后，第 2/2 页文字实际可见；显式完成显示“本地进度已保存／本章已读完”，退出返回详情后“继续阅读”首次恢复末页文字与完成状态。此项是同一标签页中的路由重开，不是浏览器进程重启、生产 Access、Native 或性能门。

原 JAR SHA-256 为 `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d`，本轮 AOT canonical JS 为 `b04dacb990df567cdb08c2155845d2936bf4c93be948fbd42dce8836a5b38e34`，材料仍为上述 `0b2ce107…f6ff`。构建和正式运行没有改动原 Source/JAR，也没有用原图 URL 替代文字处理。

准备过程中发现旧 `hostSubmodules()` 会从未初始化的候选 codec 目录向上找到父仓库，导致本树 host 指纹错误包含父提交。诊断 buildId `ext-all.xkcd-ce8b19debe9b65d53c82fa75c08fdf40` 的指纹为 `832ae9f93415090979c2c2aa6a7adc39311f36f0f898a4bfebfda5a2237411bd`，只保留其固定输入下的功能观察，不作为修复后的发布身份或性能基线。当前构建器的 Source 必需依赖收敛为 TeaVM/Suwayomi，后续须重新计划和构建。

原始构建与网络报告保存在该树 ignored `.local/ui-image-baseline/`。页面已关闭，服务会话退出 130 后另行确认端口 8930、Node 与 workerd 子进程均消失，并仅删除匹配本 buildId 的临时静态快照和 D1；退出码本身不作为清理证明。UI 成功不等于内部 Blob/缓存账本或进程/GPU 峰值归零。

## 默认关闭的采集入口工程验收

正式 app 已接入默认关闭的 `READER_BASELINE` 采集入口，使用方法与数据含义见[采集说明](../READER-BASELINE.md)。它复用实际 provider/ImageStream、布局后 viewport 与官方 FrameTiming，不更换图片实现；默认 release 不挂载记录器或性能面板。

完整 `pnpm check`、`pnpm flutter:check`、默认 `pnpm build` 与提交前完整格式检查通过。Flutter 三包分别为 20、37、130 项测试；新增回归覆盖真实 provider 仍只 decode 一次、离屏图片不冒充当前可见页、raw 帧号关联、限额/收尾、迟到 acquire/release 跨采集隔离，以及默认/显式启用的 app shell。

完整套件首轮暴露 raw timing 测试依赖尚未初始化的 engine frameNumber；该失败日志保留。锁定 SDK 没有对应 testValue setter，测试现通过明确标记的实例级测试 reader 固定帧号，生产默认仍读真实 PlatformDispatcher，未知帧号仍拒绝，未放宽匹配。之后完整 Flutter 检查 130 项通过。详细日志在 main ignored `.local/ui-image-boundary/baseline-*.log`，不作为性能数据。

本项工程验收之后执行了下述真实采集，但首次报告导出失败；不能报告首图/跳转分布或帧性能通过。CPU、RSS、GPU 与物理呈现均未采集。P0 保持先用最简单直接的实现完成真实流程，再按实测瓶颈优化。

## 修复 AOT 身份后的 Web 采集尝试

固定 `8494757c00e0337e4d3d5b34885bb8ef484e56c0`，在独立验证树重新计划并顺序构建原版 xkcd 与 Arknights。必需 submodule 已初始化且匹配已提交 gitlink；候选 codec 未参与默认 Source 输入。新 host 指纹为 `964de7e6d37bfd1f63cf15597adda6af36bb6bc929e7f4fe9658f65c6393b435`，xkcd buildId 为 `ext-all.xkcd-6624520c0b18799a9a0f87c34a4aed72`；canonical 字节与上述原 xkcd 相同，材料版本不变。正式 gzip/canonical 交付验证通过，尚未发布，兼容标记仍为 `compiled_unverified`。

以正式 `lib/main.dart` release 显式开启 `READER_BASELINE`，在新的本地 origin、Codex 内置浏览器默认 1280×720 视口、已启用 Flutter 无障碍树、隔离 workerd/D1 和 RS256 测试身份下，从详情开始采集并进入原 xkcd `3319: Elevators`。漫画及原 TextInterceptor 文字页实际可见，显式完成后显示本地进度已保存并返回详情。这不是生产 Access、Native、真机或性能验收。

60 秒自动停止后，面板显示 30 个事件和 406 个帧样本；这些只是 UI 显示计数，没有可用的原始报告。点击“查看 JSON”产生真实 Web `Bad state: RenderBox was not laid out`，复制后读取剪贴板为空，空 JSON 文件无法解析。因此本次采集完整性门失败，不能根据这些计数计算或声称首图、帧分布通过。修复方向为有界摘要与成熟库的文件下载，随后必须复验实际下载正文。

截图、网络记录、空导出和 `capture-1-failed.json` 保存在验证树 ignored `.local/ui-image-baseline/confirmed/`；失败记录保留。测试标签页已关闭，服务退出后确认端口 50188 无监听，且无本次 Node/workerd/Java/Gradle 子进程；仅删除匹配本 buildId 的临时快照/D1。

## Web 报告下载完整性复验

2026-11-05 核对实际下载文件。正式 UI 固定 `5e1e014340f96a390ce5a07be2f7f343fb14e24e`，通过精确锁定的 `cross_file` 下载完整 JSON；面板只布局摘要和最多 1024 字符预览。该提交只改变客户端导出，Source host 指纹仍为上述 `964de7e6…93b435`，复用固定 `8494757` 构建并已验证的原 xkcd AOT，未修改原 Source/JAR。对应 [CI 41857359648](https://github.com/Wybxc/karuyomi/actions/runs/41857359648) 已确认该完整提交为 completed/success。

在新的 loopback origin、Codex 内置浏览器默认 1280×720 视口、已开启 Flutter 无障碍树、正式 `lib/main.dart` release、隔离 workerd/D1 和 RS256 测试身份下，从详情开始采集并进入原 xkcd `3319: Elevators`。漫画实际显示，改为单页后原 TextInterceptor 文字图可见；显式完成显示本地进度已保存及本章已读完，退出返回详情。报告环境记录 DPR 2 和 SDK 报告的刷新率 60 Hz；浏览器版本未取得，不猜测补齐。这些条件不是生产 Access、Native 或真机。

60 秒自动停止后，点击“查看摘要”和“下载 JSON”，浏览器返回真实下载文件。复制该文件到 ignored 证据目录后，实际 UTF-8 JSON 可解析，大小为 278,785 字节，schema 为 `karuyomi.reader-baseline.v1`，revision 与上述 UI 提交一致。报告共有 33 个事件和 481 个帧样本，`truncated=false`；两份 acquire 结果、实际 ImageInfo、图片 frame/post-frame、目标 viewport 和导航 epoch 均保留。两个 `release_ack` 分别匹配已交付的资源与 generation，之后存在 `reader_exit_ack`；这证明本次观测到的释放控制完成，不代表浏览器 Blob/Flutter cache 或 RSS/GPU 全部归零。

本次报告 `frameTimingStatus=associated`，未关联计时数为零，图片帧和事件帧缺失计时列表均为空；逐项核对确认事件时间单调且在采集期限内、全部事件帧号精确匹配真实帧、每份已获取资源均有对应释放 ACK，两幅图片均有 decoded viewport。没有使用回调到达时间或不同时钟相减补齐样本。报告 `startedAtUtc=2026-11-04T15:27:00.829Z`，属于一次采集和下载完整性样本；不能据此报告冷热首图/跳转分布、CPU、RSS、GPU 或真机性能通过。

同页控制台在 `2026-11-04T15:26:01.945Z` 曾记录一次 `Bad state: RenderBox was not laid out`，早于上述采集开始。固定 release 栈与锁定 SDK 源码比对定位到视图焦点变化后的 ReadingOrderTraversalPolicy 排序：FocusNode.rect 读取尚未布局的 RenderSemanticsAnnotations.size。该路径不经过 JSON 或图片交付，具体焦点节点与触发时序仍待复验，现有证据不足以认定 SDK 缺陷。最终摘要和下载文件实际可用，但不能声称全程零错误，也未将该错误归因于大报告。旧 `8494757` 的导出失败与空文件继续保留，不由本次下载成功改写。

原始报告 `xkcd-export-capture.json`、完整性复核 `export-integrity.json`、网络记录 `xkcd-export-network.json`、漫画/文字/下载结果截图 `export-*.jpg` 保存在固定验证树 ignored `.local/ui-image-baseline/confirmed/`。测试标签页已关闭，服务会话退出 130 后另行确认端口 53920 无监听，且无本次 Source probe/workerd/Gradle 进程；仅删除唯一匹配本 buildId 的 `karuyomi-source-probe-kur9sp` 临时快照/D1，没有只依赖退出码判断清理完成。下一步在当前不透明图片合同下复验 Arknights 正式完整章、下一章与首次续读，再按固定条件补齐多次 baseline 和目标设备指标。

## 当前合同的 Arknights 完整章与首次续读

2026-11-05，在独立验证树复用上述正式 UI `5e1e014` 和不透明图片合同，加载未修改的 Arknights Comics 1.6.2 原 JAR。buildId 为 `ext-en.arknightscomics-664db9291ee98ae9231b39a4aa2d536b`，canonical JS SHA-256 为 `e6def8e3e5fcca10057be1ecaf384418e3087e58ef95a012e6d8fefc9133a162`，原 JAR SHA-256 为 `e1a706cc4b504af04bf2ebbb3046d36421a949fca0633e69166e34415d657cf3`；host 指纹与共享材料仍为上述当前版本。没有修改扩展业务源码、原 JAR 或绕过 Source 直接加载原图。

正式 `lib/main.dart` Web release 在新的本地 origin、Codex 内置浏览器、已启用无障碍树、隔离 workerd/D1 和真实 RS256 测试验签下，从首页进入源和 `Prelude Suite: The Lone Walker`。DREAM 的 51 页逐页实际显示，页码和本地已保存进度逐页推进；末页显式完成后实际显示“本地进度已保存／本章已读完”。随后使用正式“下一章”进入 HEARTBEAT，依次显示并保存第 1–3 页；退出回详情后“继续阅读”首次恢复 HEARTBEAT 第 3 页，图片和已保存状态均可见。该恢复属于同一标签页内路由重开，不是关标签页、浏览器进程、Native 或生产 Access 恢复。

本轮保留操作中的限制：第 12 页曾发生 locator 等待超时，之后新的 AX 状态确认实际已保存；首次尝试第 23 页时仍停在第 22 页，刷新观察后再次操作才成功到达并保存第 23 页。没有把这次未推进尝试算作成功。51 张编号截图齐全，操作记录包含页 2–51 的全部已保存状态及上述失败尝试。视口过程中由 1280×720 变为约 453×764；后段采集报告记录 DPR 2、SDK 刷新率 60 Hz，因此本轮是可用性和续读功能门，不作固定显示条件的性能比较。

隔离网络记录共 65 个 GET，HTTP bridge 和上游状态均为 200，其中 59 个为图片响应，没有网络错误记录。这个计数不等于实际显示页数；实际阅读范围由 UI 状态和截图证明。原 Source 的网络请求和处理路径保持有效，本地允许域名明确为 `arknights.global` 与 `webusstatic.yo-star.com`，没有据此推定生产网络政策或 Access 已通过。

另一次 60 秒有界采集在 DREAM 第 43 页后开始推进，覆盖第 44–51 页、切换 HEARTBEAT 第 1–3 页和退出。真实下载 JSON 为 879,608 字节，含 152 个事件及 1,472 个帧样本，`truncated=false`、`frameTimingStatus=associated`。事件时间单调且在采集期限内，带帧号事件均精确匹配原始计时，图片和事件缺帧列表为空。报告有 11 份捕获期 acquire 结果，全部对应到 14 个 `release_ack`；额外 3 份释放属于采集前已持有的资源，不能把 acquire 与释放总数误写为相等。14 份 release 请求、发送和 ACK 的资源/generation 集合一致，DREAM 切章和 HEARTBEAT 退出分别有一个 `reader_exit_ack`。这份报告只证明该采集区间内的生命周期，未覆盖前 43 页全部资源，也不包含随后首次续读的完整采集，不能代表整个浏览器、Flutter cache、RSS/GPU 或进程峰值全部释放。

控制台记录仍只有一次早期焦点异常及其栈两条 entry，时间为 `2026-11-05T00:11:36.496Z`，早于报告开始 `00:18:49.695Z`；后续阅读未新增错误记录。它与上述 ReadingOrderTraversalPolicy 路径一致，具体触发原因和默认构建对照继续验收，不把本轮功能成功写成全程零错误。

逐页截图 `arknights-pages/01.jpg` 至 `51.jpg`、操作记录 `arknights-current-ui-steps.json`、完成/首次续读截图、`arknights-heartbeat-ui.json`、`arknights-resume-ui.txt`、`arknights-lifecycle-capture.json`、`arknights-current-network.json` 和 `arknights-console-errors.json` 保存在同一 ignored 证据目录。`arknights-run-cleanup.json` 记录标签页已关闭，服务会话退出 130 后端口 61624 无监听，且无本次 Source probe/workerd 进程；仅删除唯一匹配本 buildId 的 `karuyomi-source-probe-B9DSM0` 临时快照/D1。当前产物未发布为已兼容，仍不以这两个源的限定 Web 分项替代 3–5 源、Native、真实 Access、长图/EXIF 或真机门。

## 初始焦点对照与诊断层收敛

在同一固定 `5e1e014` 源码、相同材料下，另行构建默认未启用 `READER_BASELINE` 的正式 Web release，独立输出到 ignored `.local/ui-image-baseline/default-web`，保留原采集版。Codex 内置浏览器临时固定为 1280×720；三次新文档加载均执行启用无障碍、Tab/Shift+Tab 和进入浏览，操作前后的控制台 error 数均为零，且界面不含性能采集按钮。这是三个新文档的默认构建对照，不是三个浏览器进程，也不能证明所有条件下不会发生焦点问题。

官方 [Flutter #193287](https://github.com/flutter/flutter/issues/193287) 记录同一稳定 SDK 中 builder 外层 Overlay 的同类焦点遍历栈，但其示例同时含 SelectionArea，不能直接认定与本项目完全同因。当前最小候选用锁定 SDK 的 `Overlay.wrap` 接管诊断 entry 生命周期，移除手写 entry 创建、更新和释放，保持 Source、图片链和 recorder 不变。工程回归及后续固定版本浏览器对照分别记录；仅收敛到官方组件不能预先宣布焦点异常已修复。

默认对照原始记录为 `default-focus-runs.json`，成品与构建日志独立保留。三个标签页均已关闭，临时视口已恢复；服务退出后确认端口 49608 无监听且无本次 probe/workerd 进程，只删除匹配本 buildId 的 `karuyomi-source-probe-abtvn9` 临时目录，见 `default-focus-cleanup.json`。

## 性能依据与下一门

现有顺序 PNG/JPEG 分片有正确性、条带缓冲、背压和取消机制证据，见[独立 codec 记录](long-image-codec.md)。16 MiB WASM heap 和 C payload 账本不等于进程 RSS、GPU 或 Flutter 端总峰值。尚无与 Flutter 直接解码、平台区域解码的同设备、同字节、同显示尺寸性能比较，不能据此选择默认分片算法。

顺序扫尾、反向跳转时重扫、PNG 再编码和跨端复制的成本须实测。下一步先记录 UI 直接解码的冷热首帧、首/中/末跳转、往返滚动与缩放，再在相同输入上比较候选方案的 CPU、帧耗时、RSS/GPU 和总峰值。标准见[设计](../design/reader-image-decoding.md)，实施顺序见[计划](../plan/reader-image-decoding.md)。

当前已新增原 xkcd 阅读/下载完整性和 Arknights 当前合同下完整章/下一章/首次续读分项，未重新完成 Native 产品交互，也未证明真实长图、EXIF/LOD、生产 Access、真机性能或 P0 通过。学习实际尺寸发生在客户端解码后，当前估算账本不能限制平台整图解码的瞬时峰值。
