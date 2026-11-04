# Reader 长图解码与资源预算

## 状态与范围

状态：**独立 codec Worker、Blob 输入、PNG 条带 tile 与 Web / Native 材料接线已实现；正式解码器和编码器的 Node 24 项通过，Source / Protobuf / Reader 尚未接入，P0 超长图门未通过**。本轮新 Worker 管线已通过 Codex 内置浏览器 11 项验收；Native 内置执行、缓存、LOD 与真实进程/GPU 峰值仍待验。现有 16 Mi 像素准入没有调整。

最初设计以主仓库 `4645ade` 和仓库固定 Flutter `3.47.5` 做源码审查；2026-11-04 的历史机制另实际执行固定 libspng 的超 16 Mi 像素合成 PNG，以及 libjpeg-turbo 的 baseline 长图、背压、取消与错误场景，见[codec 证据](../verification/long-image-codec.md)。历史 Web 仅核首/中/末区域，不沿用 Node 的完整流 SHA 或缩放证明，也不转作新 Worker / 新产物的浏览器证据。实验未改变产品准入，没有测量进程/GPU 峰值；独立机制与正式 Source/Flutter/Native 验收分别维护。

目标是在既定 Flutter + TeaVM 架构中，经未修改 Source 的正式图片链，显示超过当前 16 Mi 像素限制的长图。需要同时解决真实解码、按需显示、缩放、原图坐标恢复和资源峰值；保留 16 Mi 拒绝只能说明现有限额生效。

本设计负责 Source 已处理正文交付后的终端图片路径。Source 内部 Bitmap/ImageDecoder 的 16 Mi 单 surface 限额是另一层边界；某个插件自身需要创建更大 Bitmap 时，终端分片不会使其自动成功。涉及这些 Source 的内部图形能力必须另验，不能绕过插件图片处理。

相关合同见[图片资源通道](../IMAGE-RESOURCES.md)，实施状态见[长图计划](../plan/reader-image-decoding.md)与 [P0](../plan/p0-runtime-and-reading.md)，实际证据继续维护于 [VERIFICATION](../VERIFICATION.md)。

## 当前实现与亲证缺口

### 获取与显示各有一次解码

`packages/runtime-host/src/image-resources.ts` 的 `ImageCollector.seal()` 先用 `image-dimensions` 解析头部、检查原始像素限额，再调用无 resize 参数的 `createImageBitmap(blob, { imageOrientation: 'from-image' })`，核对实际尺寸并 close。Java 成功结果一致后才发布 Blob URL。

Reader 的 `apps/reader/lib/features/reader/resource_image.dart` 再创建 Flutter `Image`；Web 的 provider 为受管 Blob 上的 `NetworkImage`，Native 的 provider 为受管文件上的 `FileImage`。两端均未传目标尺寸，也尚未调用新增的独立 codec Worker / tile 运行库。当前源码未发现名为 `FlutterImageDecoder` 的项目类。`BoxFit` 和 `InteractiveViewer` 没有给上述 provider 增加目标解码尺寸。

因此当前链路包含 host 的临时完整 bitmap 校验，以及 Flutter 的正式显示解码。两次通常先后发生，但没有统一计量它们与其它页、插件图形对象、编码副本和 GPU 资源的合计峰值。

### 超限长图尚不能进入终端 renderer

以下正式边界均使用原图 `width × height`：

| 边界             | 当前行为                                               | 源码                                                     |
| ---------------- | ------------------------------------------------------ | -------------------------------------------------------- |
| host 单图        | 超过 16 Mi 像素时，真实 bitmap decode 前拒绝           | `packages/runtime-host/src/image-resources.ts`           |
| 控制描述         | `processedImageSchema` 拒绝超过 16 Mi 像素             | `packages/contracts/src/image-control.ts`                |
| Dart 传输        | `acquireImage()` 在建立资源前再次限制 16 Mi 像素       | `packages/source_runtime/lib/src/transport_runtime.dart` |
| Native Dart      | 拒绝超过 16 Mi 像素，驻留合计 32 Mi 像素               | `apps/reader/lib/runtime/native_image_files.dart`        |
| iOS 文件桥       | 单图 16 Mi、共享合计 32 Mi 像素                        | `apps/reader/ios/Runner/NativeImageFiles.swift`          |
| Reader scheduler | 用完整 `width × height × 4` 估算，默认驻留上限 128 MiB | `packages/reader_core/lib/src/scheduler.dart`            |

例如 1080 × 20000 为 2160 万像素，已超过 16 Mi 限额。只给 Flutter 增加 `ResizeImage`，无法使这张图通过前面的合同。

### 当前账本不是解码瞬时峰值上限

`ImageScheduler` 在已知尺寸时可以提前缩小窗口，但未知尺寸页先用默认估算启动 `provider.acquire()`。实际尺寸及最终接纳判断发生在 acquire 返回后。snapshot 的 decoded 估算只统计 `_resources`，不统计在途 codec、解码临时对象和释放尚未确认的显示引用。

host 的原图像素账本有解码前预留，且取消时保留 tombstone 至不可中断的 bitmap decode 结束并 close；这些约束应保留。它仍是每个资源的一份像素计数，无法代表 WebView 与 Flutter 两个解码域、第三方 codec 内部缓存和 GPU 的全部占用。不得把该数字或 `ImageCache` 的缓存大小表述为进程硬上限。

`ReaderResourcePool` 已等待 widget/缩放 overlay 的 pin、帧结束和 provider cache eviction 后才释放正文所有者。后续加入不同目标尺寸或 tiles 后，必须记录并清理实际创建的全部 cache key；当前 `evictResourceImage()` 只重建并清理原始 provider，不能直接用于新增的 `ResizeImage` 变体。

### 原图锚点可复用，真实长图仍待验

`ReadingPosition` 已保存 `chapterKey/pageKey/manifestVersion/pageIndexHint/normalizedOffset`。Reader 连续布局按原图比例计算页高，将顶部位置映射为原图内归一化偏移；学习尺寸和旋转后恢复该坐标。后续 tile、LOD 或解码尺寸变化不应改变逻辑页身份、内容版本或原图锚点。

现有 `reader_screen_test.dart` 的尺寸学习与旋转回归使用 `ColoredBox` 图片替身及常规比例，能证明布局逻辑，不能证明超长编码图的真实解码、纹理、接缝或峰值通过。

## Flutter 与浏览器现成 API 的实际边界

本轮读取的固定 SDK 为 Flutter `3.47.5`，framework commit `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`，engine revision `af7e796e161ae0bb1ff0758c71a7105418bd9ded`。审查路径为 `/private/tmp/karuyomi-flutter-sdk`；该本地路径不是后续构建输入，后续复验应按 `.fvmrc` 准备 SDK。

- `ResizeImage` 和 `instantiateImageCodecWithSize` 可以表达目标输出尺寸，适合降低最终缓存和绘制资源。后者的回调获得本征尺寸，不能把这个回调本身记为像素解码。官方 API 见 [ResizeImage](https://api.flutter.dev/flutter/painting/ResizeImage-class.html) 和 [instantiateImageCodecWithSize](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodecWithSize.html)。
- Native engine 的 `lib/ui/painting/image_decoder_skia.cc` 和 `image_decoder_impeller.cc` 会查询 `get_scaled_dimensions`；支持相应缩放的 codec 可以先解码到较小尺寸，无支持时仍可能使用原尺寸工作图。目标 API 不提供跨格式的峰值保证。固定源码见 [Skia 解码](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/lib/ui/painting/image_decoder_skia.cc) 与 [Impeller 解码](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/lib/ui/painting/image_decoder_impeller.cc)。
- 固定 SDK 的 Web CanvasKit `lib/web_ui/lib/src/engine/canvaskit/image.dart` 先建立 browser/blob codec，再包裹 `ResizingCodec`；`image_decoder.dart` 的 `getNextFrame()` 先取得完整 frame 再缩放。browser decoder 的初始化未传 `desiredWidth/desiredHeight`。官方 [Image.network](https://api.flutter.dev/flutter/widgets/Image/Image.network.html) 文档也说明 Web cacheWidth/cacheHeight 的限制。不能只加 resize 参数就认定 Web 已限制原图解码峰值。
- Flutter 的 `ImageDescriptor.instantiateCodec` 没有 region rectangle 参数。Android 有真正的 [BitmapRegionDecoder.decodeRegion](https://developer.android.com/reference/android/graphics/BitmapRegionDecoder)，可重复读取原图矩形并控制采样；它是平台 API，不是当前 Flutter 图片 provider 已具备的能力。
- WebCodecs `ImageDecoderInit.desiredWidth/desiredHeight` 在 [W3C 规范](https://www.w3.org/TR/webcodecs/#imagedecoderinit) 中是 best effort，不能保证所有格式支持，也没有空间 region 参数。Canvas `drawImageRect` 或从已解码 bitmap 裁剪，仅证明显示裁剪，不能作为区域解码证据。

## libvips / wasm-vips 评估

### 有真实顺序管线，仍需区分格式和访问顺序

libvips 的 [evaluation 文档](https://www.libvips.org/API/current/how-it-works.html) 描述按区域请求像素的 demand-driven 管线。这是可用于长图的成熟解码基础，和先解完整 bitmap 再 Canvas 裁剪不同。

但 `access: sequential` 只适合从上到下的请求。随机读取、旋转、不同 codec 或显式 materialization 可能引入整图缓存。以下是 `libvips 8.18.7` 的固定证据：

- [JPEG loader 文档](https://www.libvips.org/API/current/ctor.Image.jpegload.html) 支持 1/2/4/8 倍 shrink-on-load，并说明 multiscan JPEG 需要大量工作内存。固定 `libvips/foreign/jpeg2vips.c` 还显示 loader 的非默认 autorotate 会先 `vips_image_copy_memory()` 再旋转。
- [PNG 固定源码](https://github.com/libvips/libvips/blob/v8.18.7/libvips/foreign/vipspng.c) 的 `png2vips_image()` 对 interlaced PNG 创建完整 memory image；非 interlaced 路径才使用按行 generate/sequential。
- [cache_set_max_mem](https://www.libvips.org/API/current/func.cache_set_max_mem.html) 调节 tracked memory 对 operation cache 的影响，不是所有 codec 分配的硬上限；第三方内部内存仍须计入实际实验。

所以不能仅检查图片扩展名并认为所有 JPEG/PNG 都具有同样的有界路径，也不能用默认 random access 加 crop 代替顺序解码设计。

### 默认 wasm-vips 不能直接作为当前移动预算方案

本轮只读取 npm `wasm-vips@0.0.19` 元数据及 tarball，没有安装或执行。npm 元数据记录的 `gitHead` 为 `49ac4378f2df80e38f45491abeeac9b86dddbedd`；包内 `versions.json` 固定 `libvips 8.18.7`、Emscripten `6.0.10`。

| 已核实项目  | 事实与影响                                                                                                                                                              |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 核心资源    | `lib/vips.wasm` 为 5,154,052 B；`vips-es6.js` 为 83,765 B。整个 npm 包解包约 12.98 MB，不能把总包大小当成所需初始下载量                                                 |
| 可选模块    | 默认加载 `vips-jxl.wasm`（2,224,543 B）和 `vips-heif.wasm`（3,802,681 B）；公开 `dynamicLibraries` 参数可显式设为 `[]`，但这样也失去这些模块的格式能力                  |
| WASM heap   | 发布 JS 固定 `initial:4096, maximum:32768, shared:true`，单位为 64 KiB page，即起始 256 MiB、最高 2 GiB。这里是线性内存配置，不等于已实测物理驻留；同样不能将其忽略为零 |
| 初始化参数  | 公开类型及 `INCOMING_MODULE_JS_API` 未提供自定义 `wasmMemory` / 最大 heap 参数，不能直接传一个小数字改变该发布构建                                                      |
| Worker 成本 | 上游每 pipeline 至少需要 3 个线程；默认预建至少 6 个 pthread Worker。`concurrency(1)` 不会把它变成无 pthread/SAB 的构建                                                 |
| 浏览器前提  | 上游 README 要求 SharedArrayBuffer、COOP/COEP，以及 SIMD / WASM exception handling；与当前不默认启用全站隔离、不要求 SAB 的产品设计存在集成工作                         |
| API         | 发布类型有 `SourceCustom` 同步 read/seek、`Image.newFromSource`、crop 与逐个输出 API；没有暴露 `Region.fetch`。不能把 C API 的 Region 示例直接当成 npm 已有接口         |

大小、版本与初始化可复验于[固定 npm 包](https://registry.npmjs.org/wasm-vips/0.0.19)，heap、线程池及参数白名单见[固定 src/meson.build](https://github.com/kleisauke/wasm-vips/blob/49ac4378f2df80e38f45491abeeac9b86dddbedd/src/meson.build)，SAB 前提见[固定 README](https://github.com/kleisauke/wasm-vips/blob/49ac4378f2df80e38f45491abeeac9b86dddbedd/README.md)。这些证据足以排除“安装默认包即可满足当前预算”的实现结论。

调整初始/最大 heap、保留最小线程池、裁剪 codec 与绑定属于新的可复现构建工作，必须验证能真正运行。无 pthread 的单线程构建尤其不能假定只改参数就可用：上游构建明确依赖 pipeline 线程。本文没有选定或实现该构建。

wrapper 的 MIT 标识不覆盖全部底层库。该 npm 包的 `THIRD-PARTY-NOTICES.md` 列有 LGPLv3 库；引入时应一并固定和交付实际版本的 notices，不能只复制 wrapper 的许可证。

### Web 与 Native 的共享边界

可以共享的是经过验证的 libvips codec 版本、颜色/方向规则、tile 布局和所有权协议。不能据此认定三端可以直接使用同一个现成二进制：

- Web 可评估隔离 codec Worker 中的 WASM 构建。SAB/COOP/COEP 必须连同 Access 登录、回跳和嵌入环境验收，不能因候选库要求就默默改变全站策略。
- iOS/Android 可以评估相同 WASM 在现有受管 WebView 中运行，但实际 SAB、worker、内置材料解析和 heap 成本均未验。本轮没有得到可以声明三端共享默认 wasm-vips 成功的证据。
- Native 也可以通过平台绑定调用同版本 libvips C API，读取现有受管文件并输出小 tile；需要 iOS/Android 的可复现交叉构建、GLib 及所需 codec 依赖，维护成本高于一个 Dart package。libvips 的[上游构建说明](https://github.com/libvips/libvips/tree/v8.18.7) 可作为依赖依据，不能用桌面编译成功代替移动端构建和真机峰值。
- Android `BitmapRegionDecoder` 是另一条成熟的原生候选，可避免在 Android 再装完整 libvips；如果采用，需要与 Web/iOS 分别验证格式、采样、EXIF 和色彩输出，三端仍共享业务协议而非实现假设。

## libspng 顺序 PNG 机制与采用边界

固定 `libspng v0.7.3` 的 progressive row API 已在独立 Node Worker 与 Codex 内置浏览器的 Web Worker 中实际运行：1080×20000 / 1080×40000 的合成 RGBA8 非交错 PNG，在实际 16 MiB 非共享 WASM heap 中顺序输出全部像素。Node 完整流 SHA 匹配编码前原始 RGBA 生成基准；Node 和 Web 的首/中/末区域 SHA 分别匹配独立 libpng oracle，Web 未计算完整流 SHA。单个 256 行条带加 64 KiB ACK 通道没有建立完整 raster；首块取消会关闭 C 上下文。仅删除 IEND 的文件在全部行输出后仍失败，说明正式片资源必须能因后部错误整体作废。具体输入、构建器偏差、计量范围和剩余格式见[实验记录](../verification/long-image-codec.md)。

这份历史机制证据使 libspng 成为当时顺序 PNG 路径的实际候选，本身未完成整套终端 codec 选型和产品验收。固定官方 macOS SDK 已重新构建并通过同样的 Node / Web 分项，独立新 WASM 身份与首轮分别保存；Linux 及跨主机一致性未验。当轮尚未维护正式构建入口、上游 submodule 或 Native 内置材料；当前工程化实现见后文，颜色/透明与方向合同、Native 内置执行及正式终端集成仍待验。RGB/灰度/调色板 tRNS、Adam7、16-bit、JPEG/WebP 等不套用这两张 RGBA 素材的结果。随机区域、反向读取和实际 Flutter 显示仍是后续实现门；新增 PNG tile 编码的 Node 验收另有独立产物与证据，不能沿用本段历史 Web 结果。

## libjpeg-turbo 顺序 JPEG 机制与采用边界

固定 libjpeg-turbo 3.2.1 / `7b4993786d856cbccabfc0ed2f923ba000e326cc` 已用同一官方 macOS SDK、独立缓存编译为无 pthread 的 250,040 B WASM。Node Worker 中，720×30000 / 720×60000 合成 baseline JPEG 的完整尺寸、1/2 和 1/4 IDCT 缩放均通过完整流与首/中/末像素 SHA。完整尺寸参考取自 Sharp 重新解码有损 JPEG；缩放参考是本机独立原生 `djpeg` 3.2.1 的整数 IDCT 输出，经无损 PNG 和 Sharp 解析，未用任意 resize kernel 代替原生缩放。输入、哈希与复验命令见[实验记录](../verification/long-image-codec.md#libjpeg-turbo-顺序-jpeg-机制)。

适配先读取头部，以 `jpeg_has_multiple_scans()` 拒绝多 scan，并限定 8-bit、Huffman、灰度/RGB/YCbCr 与顺序 DCT 的 SOS 参数。实际验证 SOF0 baseline；不依赖固定库未赋值的 `is_baseline` ABI 字段。条带至多 256 行、通道至多一个 64 KiB ACK 块，WASM 实际非共享 heap 为 16 MiB，最大图 C 计量峰值约 1.96 MB，包含约 1.18 MB 编码输入。请求账本和 heap 均不代表进程/GPU 峰值。

JPEG 先缩放再输出可以减小条带和终端 raster，但不使 progressive / multi-scan 的整图系数消失。当前机制在 `start_decompress()` 前拒绝这些输入，不用缩小目标图掩盖工作区需求；仅有一个小 progressive 拒绝素材，尚未另验 multi-scan sequential。输入高上限为 65500，不能把 PNG 的高度范围照搬到 JPEG。

首块 ACK 点取消后 C 账本归零；缺失 EOI 的文件在最后条带的扫描行阶段因 corrupt-data warning 失败，已输出片必须能整体作废。每个进入库的导出调用都有活跃错误恢复帧；完整输入最终仍经过 `finish_decompress()`。Codex 内置 Chromium 156 又实际通过两张完整尺寸的六个区域 SHA/Canvas、背压、取消、截断、progressive 拒绝及首块后强制 terminate 观察窗，无 SAB，五个协作终态 C 账本归零。Web 未计算完整流 SHA、未测缩放或强制终止后的 heap 释放；Native、EXIF/ICC/其它色彩、随机区域及正式 Source/Flutter 链仍待验，不关闭产品门。

## 正式源码基础与产品接线

`runtime/image-codec/` 已内化 PNG/JPEG decoder、PNG encoder 的 C ABI、严格 TypeScript 顺序接口，以及 `client.ts` / `worker.ts` 的独立 module Worker；真实上游通过 submodule 固定。`tools/images/` 提供锁定 SDK 构建、自生成长图回归和 portable 产物准备器。操作与首批能力见 [codec README](../../runtime/image-codec/README.md)。本节区分已经实现的运行库与尚未接通的正式产品合同。

### 已实现的独立 Worker 与显示片基础

`decodeImageTiles()` 接受受管 `Blob`，在读取前限制编码输入为 8 MiB。独立 Worker 顺序解码 PNG/JPEG，将解码输出宽度、至多 256 行的 RGBA 条带交给固定 libspng encoder，返回可独立解码的 PNG tile。RGBA 条带上限 4 MiB、单片 PNG 上限 8 MiB；传输块至多 64 KiB，每块等待 ACK，下一片由消费者的下一次 pull 驱动。它没有建立完整页 raster，也不是随机 region decoder。首批 PNG 仍限非隔行 RGBA8、分母1；JPEG 仍限 8-bit 单 scan 顺序 Huffman 灰度/RGB/YCbCr，支持 1/2/4 缩放；方向、颜色与拒绝范围继续按当前 codec 合同解释。

header、tile 与 terminal 是分开的事件。tile 保留原图 `sourceRect`，在完整 IEND/EOI 和清理成功前均为 provisional；尾部失败、取消或清理失败使此前全部 tile 失效。requestId/generation、几何、序号、大小与真实 WASM ABI 在边界检查。消费者退出、AbortSignal 与超时触发协作取消；超过 grace 时终止专用 codec Worker，不终止 Source Worker。已验证模块的 Blob URL 在 Worker 终止后释放；未取得的强制终止计量保持 null，不能记为 heap 已归零。

`MaterialCatalog.imageCodecs` 是独立于 `hostScripts` / `resources` 的共享组，包含 client、Worker、三组模块/WASM 和许可证，进入 `materialVersion` 并记录构建身份与 ABI。Web 使用 Static Assets；`prepareImageCodecAssets()` 经 VerifiedLoader 验证后提供 Worker / 模块 Blob URL 与完整拥有的 WASM 字节，不依赖相对 URL 再下载 WASM。Native 构建将所需 codec 字节及本地 resolver 只内置到 `host.js`，通过 `window.karuyomiImageCodecs` 提供相同准备入口；已 bundle 的 Native client 不重复嵌入 Web `client.js`。Source Worker 不预载或重复携带这一组，Native 缺材料时不回退网络。Native 构建接线不等于已经在 WKWebView / Android WebView 执行成功。

正式 C 产物已经通过 [24 项 Node 解码器/编码器验收](../verification/long-image-codec.md#有界-png-编码器的-node-验收)，包括独立 Sharp 像素对照与高熵最大条带；该证据没有运行新 Worker 的真实浏览器 ACK、重组、跨线程取消或显示。新管线另在 Codex 内置浏览器通过 11 项，590 个基础 tile 的 PNG 字节/几何与 Node 同产物基准一致，真实 ACK/pull、三种取消边界、截尾失效及恢复也通过；详见[正式 Worker 证据](../verification/long-image-codec.md)。两份 WASM 各自 32 MiB 最大 heap / 16 MiB C payload 是配置上界，不是两者同时运行的实际峰值；高熵 encoder 已观察到 heap 增长，不能将所有场景写为 16 MiB。

目前尚未把该运行库接到原 Source 的处理后正文、Protobuf 图片描述、Flutter Reader、tile 缓存或 LOD 调度；现有 ProcessedImage/ImageResource、host 完整 bitmap 校验和全部 16 Mi 像素门保持原状。以下是仍需完成的产品接线。

### 1. 保留原 Source 已处理正文，分开编码页与显示片

继续调用原 Page/getImageUrl/getImage、请求头、Cookie、拦截器和插件处理。新增的长图 decoder 只消费这一链路产生的受管 Blob/文件，不重新请求原图 URL，也不修改 Source 或原始 JAR。

把编码页所有权与显示 raster/tile 所有权明确分开。编码页描述保存原图尺寸、方向、格式、编码字节和 generation；它表示 Source 正文传输完成并与 Java 成功结果一致，不能叫作像素解码成功。显示 tile 必须经过实际 codec decode，记录原图矩形、输出尺寸和独立资源身份后才能显示。

这需要同步修改 Proto、TS/Dart 解析、host collector 和 Native 文件合同。当前 ProcessedImage/ImageResource 的单对尺寸及 16 Mi 全图限制不能直接拿来同时描述这两种对象。旧包无需兼容，但新合同、客户端和材料必须具有一致的协议身份。

不得只删除 host 的 `createImageBitmap`，保留原来“已验证可显示图片”的语义，再把头部尺寸作为真实解码证据。接纳编码页和完成 tile decode 必须是不同状态。坏图后部、部分解码失败和取消的状态也要能表达。

### 2. 用有限像素窗口显示同一逻辑长图

Reader 继续保留一个 Source 逻辑页；tile 不进入章节页序、不变成持久进度 pageKey。布局依据方向处理后的原图坐标，视口、缩放和 DPR 决定所需 tile/LOD。当前运行库输出解码宽度、至多 256 行的 PNG 条带；Reader 应先接入这一明确布局与单活动 decoder，再以真实视口和峰值证据调整片尺寸及 LOD，不能把待实现的任意矩形切片视为既有能力。

同一 Source 页内滚动会改变 tile 需求，因此调度签名必须加入原图 viewport/LOD，不能继续只比较 pageKey/width/height。可见 tile 优先，其次前向和后向准备；每份 raster、替换中的旧 LOD 和 zoom overlay 均单独计费。

`normalizedOffset` 保持相对于同一方向语义下的完整原图。tile 边界、输出分辨率和缓存命中不改变锚点。方向处理应避免把整张大图旋转成新 bitmap；如采用源坐标扫描加片内转换，必须验证八种 EXIF 方向的坐标映射、色彩及接缝。

### 3. codec 访问模式与缓存显式受预算

对真正支持顺序读取的格式，可以评估按源 scanline 从上到下生成有限条带或 tiles，再将片输出交给有界缓存。反向滚动和任意位置恢复不能倒读同一个 sequential 管线；需要命中已生成的有界 tile 存储，或明确重新打开编码页、从可支持的起点重新扫描。重复解码的耗时也属于首图和恢复门。

当前 client 的期限覆盖整个会话，且最后一个 tile 后还要继续 pull 才能取得真实 terminal；Reader 不得只拉可见片后无限暂停。产品 owner 应驱动有界顺序扫尾，按配额缓存或丢弃非可见 PNG，保留编码页供缺片时本地重新解码。真实尾部失败使该会话所有 provisional tiles 失效，必须同步撤下显示引用、驱逐全部实际 cache key 并释放 Blob/文件；不能把最后 tile 或可见 frame 当作整页成功。

若后续重新评估 libvips，`SourceCustom.onRead/onSeek` 可作为有界输入候选，但其回调是同步接口，不是可 await 的流。`writeToBuffer` 也会物化该次输出；只允许用于已限制尺寸的小片，不得对整张长图调用 `writeToMemory/copyMemory`。使用异步 ACK 或文件 sink 时，应先验证同步 codec 如何暂停并处理取消，不能在回调外无限排队。

编码输入、WASM/native heap、codec 工作空间、临时条带、编码 tile 存储、传输块、Flutter decoded tile 和 GPU 资源分别计量。operation cache 上限不是 codec 内存上限，WASM 最大 heap 也不是进程总上限。临时文件必须是有配额的真实持久层；WASM 内存文件系统不能被描述成磁盘卸载。

对 interlaced PNG、multiscan JPEG、动画和其它会完整 materialize 的路径，需要基于元数据/codec 能力单独预留最坏工作空间，或明确不支持该范围。首批接受哪些超过 16 Mi 的格式、位深、方向与尺寸，必须写入能力合同，不能将未支持输入计为完整通过。

### 4. 所有权与取消贯穿全部层

编码页需被活动 decoder、显示窗口和 zoom owner pin；tile 需被 scheduler、widget、Flutter cache 分别持有。等待实际 decode/encode 工作终态、帧结束、全部 cache key 淘汰和 Native 文件 ACK 后才归还对应预算。旧 generation、替换 LOD 和迟到 tile 不得发布到当前页。

不可协作取消的 codec 操作可以在独立 worker 的任务边界或整 worker 终止后回收，但必须证明线程/heap/缓存已退出，保留尚未清理的所有者。codec Worker 不应与 Source Java Worker 共用可被无条件终止的生命周期；否则取消长图会同时破坏原 Page 会话和 Source 对象。

## 依赖、静态材料与 AOT 输入身份

`runtime/image-codec/artifacts-lock.json` 已固定 PNG/JPEG decoder、PNG encoder、许可证和构建清单的 portable 归档。`tools/images/artifacts.ts` 校验归档 size/SHA、精确成员、逐成员大小/SHA、manifest 输入身份、自有构建源码与 index gitlink，原子安装到忽略缓存；同步只读核对成员后使用可取消的系统 tar，等实际提取器及后代退出才清理 stage/lock。材料构建消费这一已验证结果，CI 无需隐式构建 SDK，也不依赖尚未验收的 Linux SDK。归档是独立运行时构建依赖，不能把其准备或发布写成客户端扩展重新使用 GitHub Release 分发；公开依赖已通过新空缓存匿名下载和完整导入校验，见[公开下载证据](../verification/long-image-codec.md#固定构建依赖的公开下载)；Linux 项目 CI 也已通过获取和材料装配，不作为 Native 或 SDK 执行证明。

当前 `tools/extensions/catalog.ts` 的 `HOST_PATHS` 已包含 `runtime/image-codec`、相应 image 构建/准备工具与材料 helper，并保留整个 `protocol`、`packages/contracts/src`、runtime-host 材料定义及全仓锁文件；真实上游 gitlink 也参与身份。因此终端 codec 输入或共享材料变化会改变 `hostFingerprint`，不能因未修改 Java 就复用旧 AOT 身份。

`packages/runtime-host/materials.ts` 的 `materialVersion` 已包含协议、hostScripts、resources、imageCodecs 与 codec 构建来源。Native 省略 Web-only client 字节仍保留同一完整 catalog 的材料版本；扩展 manifest 的 Source 预载组不加入终端 codec。不得改变两套历史冻结 AOT 输入，也不得把新材料或协议混入旧 checkpoint；队列中断与恢复边界见[工程计划](../plan/engineering-and-release.md#中断复核与恢复边界)。后续发布按当前实际输入生成新 host 身份并重新验收。

无论采用 WASM 或 Native 库，Web 所需材料只发布一份 Static Assets；Native 所需材料/库随应用内置，不通过网络回退读取。产品 JS/桥接逻辑仍维护为严格 TypeScript，第三方构建产物按锁定包或校验后的构建器获取，不复制依赖缓存为维护源码。

## 下一轮实现与实测门

1. **验收已内化的新 Worker 管线。** C/TypeScript 适配、双上游 submodule、builder、独立 Worker、Blob 输入、256 行 PNG tile、共享材料与 portable 归档均已实现；[正式 Node 解码器/编码器证据](../verification/long-image-codec.md#有界-png-编码器的-node-验收)已具备。正式材料与新产物已在 Codex 内置浏览器通过 11 项：590 个基础 tile 的 PNG 字节/几何、ACK/pull、取消、截尾及恢复。证据来自当前 catalog/client/VerifiedLoader/Worker，独立 Sharp 像素正确性仍引用另行执行的 24 项 Node 门；[正式 Worker 证据](../verification/long-image-codec.md)不沿用历史探针的 Web 成功。冷启动、Native 内置执行和实际进程/heap 释放仍须另验。
2. **验证大于 16 Mi 的真实输入。** 至少包含 1080 × 20000 及更长的 baseline JPEG、非 interlaced PNG，用首/中/末可辨内容验证实际小片像素。增加 progressive JPEG、interlaced PNG、透明图、16-bit、EXIF 和截断文件，区分支持、预算拒绝与真实解码失败。头部尺寸和构造空白 widget 不算通过。
3. **验证有界生成和任意位置读取。** 记录输入副本、codec 高水位、条带/片数、缓存字节和存储配额；测试慢消费者、跳到末尾、连续反向滚动、LOD 替换与 zoom。不得由完整 raster、无界内存文件或全部 tile 同时驻留来实现“分片”。
4. **接通正式产品合同与锚点。** 生成双端模型，接入 host、Native 文件与 Reader，覆盖同一长图内滚动、旋转、DPR、模式切换、缩放、关章及恢复。显示与 observed 必须来自实际已解码且可见的 tiles。
5. **验证失败与退出。** 在获取、解析、解码、编码、传输、显示和 cache eviction 阶段取消/切 generation；证明迟到片不发布，相关所有者在终态后归零。单测账本归零不代表进程/GPU 峰值已通过。
6. **完成真实 Source 与环境门。** 使用未修改 Source 的处理后正文，在 Codex 内置浏览器和 iOS/Android 设备读取完整长图，验证首/中/末、锚点恢复与释放。分别记录冷/热首图、跳转分布及进程/GPU 峰值；模拟器、独立 codec 机制和真实 Source 证据分开保存。

只有实际超过 16 Mi 的输入在声明支持的正式链路与环境完成这些门，才能关闭相应长图验收项。全部 P0 仍按总计划收齐，其余未验范围继续保留。
