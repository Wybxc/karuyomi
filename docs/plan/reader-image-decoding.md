# 阅读器长图与终端解码

## 目标与状态

使真实长图经原 Source 图片链进入 Web 与 Native 阅读器，在条漫、旋转、缩放与位置恢复时保留原图坐标，并记录解码尺寸、资源释放和进程/GPU 峰值。状态：**进行中，独立 codec Worker、Blob 输入、256 行 PNG tile、Web / Native 材料和 portable 归档已实现，正式解码器/编码器的 Node 24 项通过；新管线内置浏览器 11 项通过，正式 Source / Reader / Native 产品尚未验收**。这是 [P0 阅读计划](p0-runtime-and-reading.md)的图片子计划，不以现有单图像素拒绝门替代长图支持。

## 当前证据与缺口

- 固定 libspng/WASM 的两张大尺寸合成 RGBA PNG、ACK 背压、首块取消与缺 IEND 尾部已通过 Node 与内置浏览器 Web Worker 机制分项；实际 heap 为 16 MiB，Web 不依赖 SAB / COOP/COEP，首/中/末区域已可见。范围、工具链偏差与剩余输入见[codec 证据](../verification/long-image-codec.md)，不将其视为真实 Source 或终端产品验收。
- 固定 libjpeg-turbo 3.2.1 已用官方 macOS SDK 在 Node 通过两张 baseline 长图的完整尺寸、1/2 与 1/4 原生 IDCT 输出，完整流及首/中/末像素分别匹配 Sharp JPEG 解码或独立原生 djpeg 缩放 oracle；另通过首 ACK 取消、缺 EOI 失败与 progressive 接纳拒绝，共九项。JPEG 又通过内置浏览器完整尺寸、背压、取消、截断、progressive 拒绝与强制 terminate 观察窗六项，首/中/末区域可见并匹配 SHA，无 SAB；Web 完整流 SHA、缩放和强制终止后的 heap 释放未测。不能把 progressive 拒绝算作其解码支持。
- SDK 准备器与工具链检查作为本轮独立工程门完成，入口为 `pnpm image-codecs:prepare` / `pnpm test:image-codecs`，后者纳入 `pnpm check`。来源和使用见[codec 工具链说明](../../runtime/image-codec/README.md)。正式 PNG/JPEG 源码构建另见下一项；Linux SDK 执行与跨主机字节一致性仍未验；材料构建已使用固定 portable 产物归档，不要求 CI 隐式编译或准备 Linux SDK。
- 已内化共同 C ABI、严格 TypeScript 顺序 session、双上游 submodule、构建指纹与自生成长图回归；此前正式源码通过两次同主机独立缓存构建和 Node 19 项真实 WASM 验收，范围按[正式证据](../verification/long-image-codec.md#正式源码构建与-node-验收)保留。本轮增加固定 libspng PNG encoder，正式 CLI 的 24 项全部通过，包括真实 WASM 编码后由 Sharp 解码对照的最大高熵条带、错误后恢复与直接 ABI 释放；见[编码器 Node 证据](../verification/long-image-codec.md#有界-png-编码器的-node-验收)。这不是新 Worker 的跨线程或浏览器证据，不能沿用历史探针 Web 结果。
- 独立 codec Worker/client 已实现：读取前限制 8 MiB 受管 Blob，PNG/JPEG 顺序解码并编码至多 256 行的 PNG tile，单片 RGBA 4 MiB / PNG 8 MiB，64 KiB DATA 逐块 ACK，下一次 pull 才推进下一片。tile 带原图 sourceRect 且保持 provisional，尾部失败或取消使已交付片整体失效；取消等待清理，超出 grace 只终止专用 codec Worker。源码、能力范围与命令见 [codec README](../../runtime/image-codec/README.md)。fake Worker / 生命周期回归及真实 Codex 内置浏览器 11 项均通过；590 个基础 tile 的 PNG 字节/几何、ACK/pull、三种取消边界、截尾和恢复范围见[正式 Worker 证据](../verification/long-image-codec.md)。这不是 Source / Reader 或 Native 执行证据。
- `MaterialCatalog.imageCodecs`、Static Assets MIME 与 Native host 内置 resolver 已接线，材料和构建来源参与 `materialVersion`。Web 使用共享静态材料；Native host 内置实际所需 Worker、模块、WASM 和许可证，不重复内置已 bundle 的 Web client.js，也不向 Source Worker 预载 codec。`artifacts-lock.json` 与 portable 归档准备/打包入口已实现，核对来源及成员后原子安装，不让 CI 临时构建 SDK。构建/装配通过不代表 Native WebView 内置执行通过，也不代表公开归档下载或 CI 运行门通过。
- 原 Source 处理后正文所有权、Protobuf 图片描述、Flutter Reader、tile 缓存与 LOD 仍未接入新运行库。现有 ProcessedImage/ImageResource 语义与 16 Mi 像素准入不变；Native 执行、缓存释放、锚点/LOD 以及真实合计峰值继续待验。
- 当前宿主、控制描述符、Dart 传输和 Native 文件接收边界限制每图 16 Mi 像素，1080×20000 等长图在到达 Flutter 前即被拒绝。
- 宿主完整解码验证处理后的图片，Flutter 再用完整 `NetworkImage` / `FileImage` 显示；布局缩放不等于请求较小 raster。调度器在 acquire 返回后接纳资源，现有账本不能证明在途解码峰值。
- 连续阅读已经按原尺寸计算页高，并保存页内归一化偏移；应扩展现有逻辑锚，不用分片序号替代逻辑页和进度。
- Flutter 目标尺寸 API 可改善部分平台/格式的最终 raster，但不能保证 Web 和所有原生格式都避免原尺寸临时解码。默认 wasm-vips 的共享内存与初始堆也不符合当前约束，不能直接引入后宣布完成。

固定源码、候选库与限制统一见[解码设计依据](../design/reader-image-decoding.md)，避免在计划中复制库实现细节。

## 实施顺序

1. **验收已实现的独立 Worker 与材料链。** C 适配、严格 TypeScript session/client/Worker、submodule、可复验 builder、Blob 输入、PNG 条带编码及 Web / Native 材料接线已实现。`pnpm image-codecs:check-worker` 已在 Codex 内置浏览器运行正式 catalog/client/VerifiedLoader/Worker，11 项覆盖逐片 PNG 字节与几何、ACK/pull、取消、截尾和错误后恢复。Node 24 项只提供独立 decoder/encoder 证据，旧探针 Web 机制继续保留原来源。portable 归档公开下载与 CI 门、Native 内置执行和冷启动另验。临时工程、下载与日志继续留在忽略目录，不以机制或构建成功关闭产品门。
2. **建立统一的图片描述与所有权。** 分开表示插件处理后图片的逻辑尺寸、方向与实际 raster/分片尺寸，保持原图坐标与已有逻辑页键。通过 Protobuf 同步 Web/Native 描述和限额；源插件内部图形预算、传输字节、解码工作区、驻留 raster 分别计费。只有管线实测成立后才调整当前像素准入条件。
3. **接入宿主与终端。** 保留原 Source 的请求、Cookie、拦截器及处理结果；把解码后的可见窗口交给 Flutter，按实际物理视口请求足够清晰的 raster，禁止无意义放大。消费已接线的 Web Static Assets / Native 内置材料，并实测各端解析与执行，不回退读取远端 Native 材料。所有实际使用的 provider/cache key 都由资源池跟踪，替换、缩放和释放等待真实终态，不只淘汰原 provider。
4. **完成预算与取消。** 解码启动前预留工作空间及输出，旧 raster 尚未释放时仍计费；在途取消、迟到解码、格式错误及预算拒绝均回收至明确终态。分片窗口、单边纹理限制、并发和预取纳入合计预算。
5. **完成正式产品验收。** 原图首/中/末位置可辨；条漫、DPR、旋转、模式切换和缩放后恢复相同原图坐标。检查缓存变体全部释放、坏图后恢复与取消时所有权。Web 内置浏览器、iOS/Android 真机分别记录首图时间与进程/GPU 峰值；模拟器与替身 Widget 只算对应分层证据。

## 验收条件

- 不修改官方 Source/JAR，不绕过插件访问原图，不用宽泛断言绕过协议类型检查。
- 真实超过当前上限的长图通过明确支持的解码路径显示，并能定位首、中、末区域；不能只调高常量或以小图替身通过。
- 所有新增 raster/分片及工作预留有拥有者，清理确认前持续计费，取消/错误后能继续阅读。
- 已显示页和进度仍由真实 Flutter frame 推进；分片预取不冒充已读。
- 固定输入的 Web 与 Native 实测证据说明所覆盖格式和资源边界；未测的格式、Source 和设备继续明确待验。

实施变化同步本计划和 [P0](p0-runtime-and-reading.md)，实际证据归入 [VERIFICATION](../VERIFICATION.md)。
