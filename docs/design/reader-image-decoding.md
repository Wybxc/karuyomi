# Reader 图片解码与资源预算

## 当前决策与状态

**Source 与宿主仅交付插件处理后的不透明编码正文；图片识别、解码、尺寸、方向、解码预算、缓存与分片由 UI 客户端负责。** 宿主只校验传输字节、资源身份、generation 和生命周期，不查看 MIME/图片头/EXIF，不预解码，也不选择完整图或 tile。原 Source 内部主动执行的解密、重排、Bitmap 等业务仍保留，不能改扩展源码或通过原图 URL 绕过处理。

当前普通图路径已将宿主的 metadata 解析和完整 bitmap 校验移除。Flutter 从实际 `ImageInfo` 获取尺寸，在 `frameBuilder` 确认显示帧后才通知 Reader。未采用的自研分片候选源码、专属工具与构建配置已删除；尚无同条件真机性能证据支持引入该方案。当前以 UI 直接解码建立基线，**长图阅读和进程/GPU 峰值门仍未通过**。

现行资源合同见[图片资源通道](../IMAGE-RESOURCES.md)，实施状态见[长图计划](../plan/reader-image-decoding.md)与 [P0](../plan/p0-runtime-and-reading.md)，实际证据维护于 [VERIFICATION](../VERIFICATION.md)。先前[编码页所有权](../verification/encoded-image-ownership.md)与[宿主页控制](../verification/image-page-controls.md)属于已替代架构的历史工程证据，不是当前合同。

## 当前链路与限制

每次 `acquireImage()` 通过原 Page 的 `getImageUrl/getImage` 完成一次 Source 图片处理，保留处理后的编码字节，不因终端解码失败在宿主自动重跑 Source。host 的 collector 收齐有界正文，确认 Java 成功描述一致后交付 `ImageResource {resourceId,generation,byteLength,url}`；内部 `ProcessedImage` 只有前三项。宿主不判断这些字节是否为图片，传输成功不能叫作 decoded、可显示或已阅读。

Web UI 的 provider 为受管 Blob 上的 `NetworkImage`，Native 为受管文件上的 `FileImage`。`ResourceImage` 监听与 `Image` 相同的 provider/completer，读取实际 `ImageInfo` 的宽高并释放自己的 handle；这个监听器不另外创建 codec。Reader 只在已呈现 frame 后学习尺寸、更新布局和解码估算。预取、编码正文到达或仅出现 `ImageInfo` 都不能单独推进可见阅读进度；解码失败由 UI 呈现。

当前普通图仍由平台完整图 decoder 处理，没有给 provider 设置目标尺寸，也没有调用独立 tile Worker。原宿主与 Source 传输层的 16 Mi 像素门已删除，但这不表示任意长图能够显示或其峰值受控。格式、方向和动画支持以实际客户端 decoder 为准，不能把“宿主不拒绝”写成跨平台格式验收。

`ImageScheduler` 在 UI 侧限制驻留页、编码字节与估算的解码字节；未知尺寸先用估算，实际显示尺寸到达后重新计费并缩减窗口。它保留释放尚未确认的资源成本，但这些数字不限制平台 decoder 的临时分配、GPU 或进程总峰值。长图所需的解码前识别、路径选择与工作区预留仍应在 UI 实现，不能放回 Source host。

`ReaderResourcePool` 等待 widget/缩放 overlay pin、帧结束和实际 provider cache eviction，再释放编码正文。新增目标尺寸或 tile provider 时必须记录并驱逐所有实际 cache key，不能只重建原 provider 代替清理。`ReadingPosition` 的逻辑页与归一化锚点继续独立于临时资源、输出分辨率和 tile 边界。

以下 SDK、候选库和 codec 机制评估保留当时固定版本、输入与环境。候选源码可在 `a2251a6` 查阅，旧浏览器入口按各记录的更早 checkout 复验。它们为 UI 解码设计提供依据；历史独立 Worker、Node 或浏览器结果均不自动升级为当前 Reader、Native 或真实设备验收。

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

这份历史机制证据使 libspng 成为当时顺序 PNG 路径的实际候选，本身未完成整套终端 codec 选型和产品验收。固定官方 macOS SDK 已重新构建并通过同样的 Node / Web 分项，独立新 WASM 身份与首轮分别保存；Linux 及跨主机一致性未验。当轮尚未维护正式构建入口、上游 submodule 或 Native 内置材料；后续曾工程化的实现见下述历史记录，候选现已删除，颜色/透明与方向合同、Native 内置执行及正式终端集成仍待验。RGB/灰度/调色板 tRNS、Adam7、16-bit、JPEG/WebP 等不套用这两张 RGBA 素材的结果。随机区域、反向读取和实际 Flutter 显示仍是后续实现门；新增 PNG tile 编码的 Node 验收另有独立产物与证据，不能沿用本段历史 Web 结果。

## libjpeg-turbo 顺序 JPEG 机制与采用边界

固定 libjpeg-turbo 3.2.1 / `7b4993786d856cbccabfc0ed2f923ba000e326cc` 已用同一官方 macOS SDK、独立缓存编译为无 pthread 的 250,040 B WASM。Node Worker 中，720×30000 / 720×60000 合成 baseline JPEG 的完整尺寸、1/2 和 1/4 IDCT 缩放均通过完整流与首/中/末像素 SHA。完整尺寸参考取自 Sharp 重新解码有损 JPEG；缩放参考是本机独立原生 `djpeg` 3.2.1 的整数 IDCT 输出，经无损 PNG 和 Sharp 解析，未用任意 resize kernel 代替原生缩放。输入、哈希与复验命令见[实验记录](../verification/long-image-codec.md#libjpeg-turbo-顺序-jpeg-机制)。

适配先读取头部，以 `jpeg_has_multiple_scans()` 拒绝多 scan，并限定 8-bit、Huffman、灰度/RGB/YCbCr 与顺序 DCT 的 SOS 参数。实际验证 SOF0 baseline；不依赖固定库未赋值的 `is_baseline` ABI 字段。条带至多 256 行、通道至多一个 64 KiB ACK 块，WASM 实际非共享 heap 为 16 MiB，最大图 C 计量峰值约 1.96 MB，包含约 1.18 MB 编码输入。请求账本和 heap 均不代表进程/GPU 峰值。

JPEG 先缩放再输出可以减小条带和终端 raster，但不使 progressive / multi-scan 的整图系数消失。当前机制在 `start_decompress()` 前拒绝这些输入，不用缩小目标图掩盖工作区需求；仅有一个小 progressive 拒绝素材，尚未另验 multi-scan sequential。输入高上限为 65500，不能把 PNG 的高度范围照搬到 JPEG。

首块 ACK 点取消后 C 账本归零；缺失 EOI 的文件在最后条带的扫描行阶段因 corrupt-data warning 失败，已输出片必须能整体作废。每个进入库的导出调用都有活跃错误恢复帧；完整输入最终仍经过 `finish_decompress()`。Codex 内置 Chromium 156 又实际通过两张完整尺寸的六个区域 SHA/Canvas、背压、取消、截断、progressive 拒绝及首块后强制 terminate 观察窗，无 SAB，五个协作终态 C 账本归零。Web 未计算完整流 SHA、未测缩放或强制终止后的 heap 释放；Native、EXIF/ICC/其它色彩、随机区域及正式 Source/Flutter 链仍待验，不关闭产品门。

## 历史客户端 codec 候选

本节及下一节记录的 `runtime/image-codec/`、专属工具和上游依赖已删除，保留实现约束与失败范围作为历史评估；源码与构建说明见固定 `a2251a6` 的 [codec README](https://github.com/Wybxc/karuyomi/blob/a2251a6/runtime/image-codec/README.md)，旧浏览器 runner 须使用各验证记录对应的更早 checkout。

该候选当时内化了 PNG/JPEG decoder、PNG encoder 的 C ABI、严格 TypeScript 顺序接口与独立 module Worker，真实上游通过 submodule 固定。`assets.ts`、`tile-store.ts`、`errors.ts` 曾从 Source host 移至该客户端目录；二者互不依赖。Source 协议已删除 `EncodedImage/acquireEncodedImage`、页/窗口/tile 控制或编码 borrow。

### 独立 Worker 与材料

`decodeImageTiles()` 接受客户端持有的 Blob，在读取前限制输入为 8 MiB。Worker 顺序解码 PNG/JPEG，将至多 256 行的 RGBA 条带编码为可独立解码的 PNG；传输块至多 64 KiB，逐块等待 ACK，消费者下一次 pull 才推进。当时 PNG 限非隔行 RGBA8、分母 1；JPEG 限 8-bit 单 scan 顺序 Huffman 灰度/RGB/YCbCr，支持分母 1/2/4。这些是客户端 codec 的局部能力和预算，不是 Source 传输的格式准入。

header、tile 与 terminal 分开表达。tile 保留原图 `sourceRect`，IEND/EOI 与真实清理成功前为 provisional；尾部失败、取消或清理失败作废已交付片。专用 codec Worker 与 Source Worker 分开，取消解码不应销毁原 Page 会话。材料 URL 在 codec Worker 终止后释放；强制终止未取得的 heap 计量保持 null，不能写成已测归零。

`assets.ts` 的 `prepareImageCodecAssets()` 接受验证工具或 UI 提供的材料目录和结构化 loader，所有必需 Worker/模块/WASM 验证后才创建 Blob URL；WASM 使用已取得字节，不通过相对 URL 回退下载。该入口当时仅供显式候选验证，未纳入默认产品构建、Web Static Assets、Native 应用资源或 Source `host.js`。旧产品 catalog 的 codec 字段、Native host 内嵌及后续独立 `assets/image-codec/` 装配均是已撤回的中间接线。

[codec 历史记录](../verification/long-image-codec.md)分别保存正式 C 构建、Node 像素 oracle 与独立浏览器 Worker 的产物身份和验证范围。目录迁移后的工程回归不能替代新客户端接入的浏览器或 Native 实测，也不能把历史合成正文 owner 结果作为真实 Source 长图阅读结论。

### 窗口、缓存与所有权

`tile-store.ts` 的 `ImageTileStore` 保留单活动 codec、窗口请求、revision 快照/等待、有界扫尾和缺片时从持有编码正文重扫。调用方传入 Blob、格式与原始尺寸；这些信息必须来自 UI 自己的识别，不能新增 Source metadata 合同。store 只缓存所需窗口 PNG，缓存上限 16 MiB；显示 lease 至多 64 份、合计 32 Mi 像素，失效但尚未确认释放的片继续计费。store 不创建显示 URL 或 Native 文件。

Reader 当时未消费此库。若未来对照证据支持采用类似方案，客户端接入才需拥有编码正文、创建受管显示资源、处理失效通知，并在 widget/overlay、实际 cache key、URL/文件和活动 codec 释放后归还对应预算。窗口关闭不得抹掉仍被显示 owner 持有的片。原 `ImagePageControl` 及 `openImagePage/requestImageWindow/waitImageWindow/releaseImageTile/closeImagePage` 已删除，不能将它们作为现行跨语言合同或恢复宿主编排。

顺序 decoder 不能倒读。反向滚动和任意位置恢复需命中有界片缓存，或从已经持有的编码正文重新扫描；这不会重跑 Source。store 继续扫尾以确认真实 terminal，不能无限停在可见片后，也不能积存全部页 PNG/raster。新 UI adapter 须将 pending/complete/failed 和可见 Flutter frame 分开，最后一片、解码 terminal 与可见阅读进度均不是同一事件。

### 坐标、预算与显示

一张 Source 长图始终是一个逻辑页，tile 不加入章节页序或持久 pageKey。UI 按方向处理后的图像坐标计算布局，并由视口、缩放与 DPR 决定 tile/LOD；调度需随同页内 viewport 变化，不能只比较逻辑页。八种 EXIF 方向的源坐标映射、片内变换、色彩与接缝仍须实际验证，不能用整张大图旋转生成新 bitmap 掩盖内存成本。

编码正文副本、codec heap/工作区、临时条带、PNG 缓存、传输块、Flutter decoded tile 和 GPU 资源分别计量。旧 LOD、zoom overlay 和释放未确认的显示引用也要计费；WASM 最大 heap、operation cache 或 scheduler 估算均不是进程总上限。对隔行 PNG、progressive/multiscan JPEG、动画等可能物化整图的输入，应由 UI 根据真实 codec 能力预留工作空间或明确报告不支持，不能令 Source host 筛选格式。

## 历史候选的依赖与构建身份

当时的 `artifacts-lock.json` 固定候选 decoder、encoder、许可证与构建清单归档，显式准备器在下载/导入边界验证并原子安装，默认产品构建与打包不消费该归档。历史公开下载、Linux 材料装配与 SDK 执行证据分别见[codec 验证](../verification/long-image-codec.md)。这些入口随候选一并删除。未来若采用有实测支持的客户端方案，其共享资源仍须通过 Web Static Assets 或 Native 应用内置交付，Native 不作网络回退。

当时的候选源码、gitlink 与初始化状态未进入 `tools/extensions/catalog.ts` 的默认 Source 身份，也未由 runtime-host 正式执行路径导入。当前候选与闲置 catalog 字段均已删除；协议、contracts、材料构建定义和仓库锁文件按当前源码参与身份，具体变化以实际指纹为准。六份正式材料的字节不因本次清理改变，但简化 catalog 元数据仍可能改变 `materialVersion`，不得沿用历史值。不得将新协议或材料混入历史冻结 AOT checkpoint；发布按当前输入和已完成的 baseline 推进。

## 性能决策与剩余验收

现有 Node/Worker 证据证明限定输入下可以顺序解码、输出小片并执行局部预算；它们没有测出该方案比 Flutter/平台直接解码更快、更省 CPU 或更低 RSS/GPU。额外 WASM 初始化、条带 PNG 重编码、复制与 Flutter 再解码均可能增加开销，不能因机制有界就选择它作为默认。

下一步先使用相同 Source 处理后的编码字节、同设备、同显示尺寸与阅读操作建立 UI 直接解码基线，再针对实测瓶颈优先比较成熟平台或第三方方案。对照记录冷/热首个可见 frame、跳转到中部/末尾、连续与反向滚动、CPU 时间、峰值 RSS 和 GPU 占用；同时记录格式/尺寸限制及失败。不同像素、缓存状态、设备或计量范围的结果不得混成性能结论。只有真实需求与同条件证据支持，才决定是否采用、采用哪些输入范围，以及是否值得接入默认交付。

仍需完成的产品门：

1. 验证 UI 直接解码的实际格式、方向、尺寸学习、取消、失败和普通图阅读，记录目标设备的长图能力与峰值。
2. 补齐上述性能对照；若决定采用分片，再接通客户端识别、解码前工作预算、窗口/LOD、Native 消费及显示资源所有权。
3. 对选定路径验证实际大图首/中/末像素、反向滚动、跳末尾、透明图、16-bit、EXIF、截断、progressive JPEG 与隔行 PNG，区分支持、预算拒绝和解码失败。
4. 在获取、解码、显示与 cache eviction 中取消或替换 generation，证明迟到结果不发布、相关所有权在实际终态后收回；覆盖旋转、DPR、模式切换、缩放和原图锚点恢复。
5. 用未修改 Source 的处理后正文完成 Codex 内置浏览器与 iOS/Android Reader 实测。独立 codec、模拟器和真实设备证据分别维护。

只有声明支持的实际长图在选定正式路径与目标环境完成对应验证，才能关闭长图门；移除宿主像素门、工程测试或独立机制通过均不足以关闭它。
