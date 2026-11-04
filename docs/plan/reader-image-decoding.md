# 阅读器长图与终端解码

## 目标与状态

使真实长图经原 Source 图片链进入 Web 与 Native 阅读器，在条漫、旋转、缩放与位置恢复时保留原图坐标，并记录解码尺寸、资源释放和进程/GPU 峰值。状态：**进行中，codec Worker、PNG tile、共享材料、Source编码页/双端描述与独立tile store已实现；tile控制、Reader和Native产品接线尚未完成，真实长图产品未验收**。既有Node24项和独立Worker内置浏览器11项保留原证据范围；本轮编码页工程检查及TS↔Dart协议交叉验证已通过，见[编码页记录](../verification/encoded-image-ownership.md)；合成正文的真实Web owner机制已通过，范围见同一记录。这是 [P0 阅读计划](p0-runtime-and-reading.md)的图片子计划，不以现有单图像素拒绝门替代长图支持。

## 当前证据与缺口

- 固定 libspng/WASM 的两张大尺寸合成 RGBA PNG、ACK 背压、首块取消与缺 IEND 尾部已通过 Node 与内置浏览器 Web Worker 机制分项；实际 heap 为 16 MiB，Web 不依赖 SAB / COOP/COEP，首/中/末区域已可见。范围、工具链偏差与剩余输入见[codec 证据](../verification/long-image-codec.md)，不将其视为真实 Source 或终端产品验收。
- 固定 libjpeg-turbo 3.2.1 已用官方 macOS SDK 在 Node 通过两张 baseline 长图的完整尺寸、1/2 与 1/4 原生 IDCT 输出，完整流及首/中/末像素分别匹配 Sharp JPEG 解码或独立原生 djpeg 缩放 oracle；另通过首 ACK 取消、缺 EOI 失败与 progressive 接纳拒绝，共九项。JPEG 又通过内置浏览器完整尺寸、背压、取消、截断、progressive 拒绝与强制 terminate 观察窗六项，首/中/末区域可见并匹配 SHA，无 SAB；Web 完整流 SHA、缩放和强制终止后的 heap 释放未测。不能把 progressive 拒绝算作其解码支持。
- SDK 准备器与工具链检查作为本轮独立工程门完成，入口为 `pnpm image-codecs:prepare` / `pnpm test:image-codecs`，后者纳入 `pnpm check`。来源和使用见[codec 工具链说明](../../runtime/image-codec/README.md)。正式 PNG/JPEG 源码构建另见下一项；Linux SDK 执行与跨主机字节一致性仍未验；材料构建已使用固定 portable 产物归档，不要求 CI 隐式编译或准备 Linux SDK。
- 已内化共同 C ABI、严格 TypeScript 顺序 session、双上游 submodule、构建指纹与自生成长图回归；此前正式源码通过两次同主机独立缓存构建和 Node 19 项真实 WASM 验收，范围按[正式证据](../verification/long-image-codec.md#正式源码构建与-node-验收)保留。本轮增加固定 libspng PNG encoder，正式 CLI 的 24 项全部通过，包括真实 WASM 编码后由 Sharp 解码对照的最大高熵条带、错误后恢复与直接 ABI 释放；见[编码器 Node 证据](../verification/long-image-codec.md#有界-png-编码器的-node-验收)。这不是新 Worker 的跨线程或浏览器证据，不能沿用历史探针 Web 结果。
- 独立 codec Worker/client 已实现：读取前限制 8 MiB 受管 Blob，PNG/JPEG 顺序解码并编码至多 256 行的 PNG tile，单片 RGBA 4 MiB / PNG 8 MiB，64 KiB DATA 逐块 ACK，下一次 pull 才推进下一片。tile 带原图 sourceRect 且保持 provisional，尾部失败或取消使已交付片整体失效；取消等待清理，超出 grace 只终止专用 codec Worker。源码、能力范围与命令见 [codec README](../../runtime/image-codec/README.md)。fake Worker / 生命周期回归及真实 Codex 内置浏览器 11 项均通过；590 个基础 tile 的 PNG 字节/几何、ACK/pull、三种取消边界、截尾和恢复范围见[正式 Worker 证据](../verification/long-image-codec.md)。这不是 Source / Reader 或 Native 执行证据。
- `MaterialCatalog.imageCodecs`、Static Assets MIME 与 Native host 内置 resolver 已接线，材料和构建来源参与 `materialVersion`。Web 使用共享静态材料；Native host 内置实际所需 Worker、模块、WASM 和许可证，不重复内置已 bundle 的 Web client.js，也不向 Source Worker 预载 codec。`artifacts-lock.json` 与 portable 归档准备/打包入口已实现，核对来源及成员后原子安装，不让 CI 临时构建 SDK。构建/装配通过不代表 Native WebView 内置执行通过，公开构建依赖已发布，并通过新空缓存匿名下载及完整导入校验；Linux 项目 CI 的通用检查、Flutter、完整构建及 D1 迁移也已通过，见[工程证据](../verification/long-image-codec.md#固定构建依赖的公开下载)。
- `EncodedImage`、`acquireEncodedImage` 与END编码页ACK已接Proto/Buf、TS运行时解析和Dart接收；Source collector限制8 MiB编码正文，raw宽≤4096、PNG高≤100000/JPEG高≤65500，保存EXIF1..8方向而不作整页raster解码。固定exifr读取完整有界metadata输入副本，END ACK不代表decode成功；Java成功描述一致后才publish/borrow。owner release禁止新borrow，既有lease继续占正文预算。本轮Source链、Dart与TS↔Dart协议交叉验证属于工程回归；合成正文的真实Web owner机制已通过；原Source与EXIF方向显示另验。
- 独立 `ImageTileStore` 已有单活动会话、有界顺序扫尾、窗口缓存、缺片重扫和失效lease确认；PNG缓存16 MiB、显示lease≤64且合计≤32 Mi像素。尚未与编码页borrow、正式tile控制、Reader或Native小片文件串接，不能将独立store实现写成实际provider cache eviction或产品显示通过。
- 现有完整图 `ProcessedImage/ImageResource` 语义及宿主、Dart/Native文件的16 Mi像素门保留；新增编码页边界不按整页像素否决。Reader尚未消费新合同，不能据此称1080×20000等长图已进入正式阅读器。协议version2/hostAbi v3保持，变化仍进入hostFingerprint/materialVersion，不建设旧版兼容层。
- 宿主完整解码验证处理后的图片，Flutter 再用完整 `NetworkImage` / `FileImage` 显示；布局缩放不等于请求较小 raster。调度器在 acquire 返回后接纳资源，现有账本不能证明在途解码峰值。
- 连续阅读已经按原尺寸计算页高，并保存页内归一化偏移；应扩展现有逻辑锚，不用分片序号替代逻辑页和进度。
- Flutter 目标尺寸 API 可改善部分平台/格式的最终 raster，但不能保证 Web 和所有原生格式都避免原尺寸临时解码。默认 wasm-vips 的共享内存与初始堆也不符合当前约束，不能直接引入后宣布完成。

固定源码、候选库与限制统一见[解码设计依据](../design/reader-image-decoding.md)，避免在计划中复制库实现细节。

## 实施顺序

1. **验收已实现的独立 Worker 与材料链。** C 适配、严格 TypeScript session/client/Worker、submodule、可复验 builder、Blob 输入、PNG 条带编码及 Web / Native 材料接线已实现。`pnpm image-codecs:check-worker` 已在 Codex 内置浏览器运行正式 catalog/client/VerifiedLoader/Worker，11 项覆盖逐片 PNG 字节与几何、ACK/pull、取消、截尾和错误后恢复。Node 24 项只提供独立 decoder/encoder 证据，旧探针 Web 机制继续保留原来源。portable 归档新空缓存公开下载已通过；Linux 工程 CI 已通过；Native 内置执行和冷启动另验。临时工程、下载与日志继续留在忽略目录，不以机制或构建成功关闭产品门。
2. **验收已实现的编码页描述与所有权。** Proto/TS/Dart模型、Source编码页collector、Java成功一致性与borrow生命周期已实现；新增crosswire和合成正文的真实Web owner机制已通过；下一步接tile控制与Reader，再进入真实Source长图门。编码页接纳、实际codec decode与显示frame保持不同状态；EXIF元数据1..8被保留不等于八种方向显示正确，源插件内部surface预算仍独立限制。
3. **接通borrow、tile store与正式控制。** 将已发布的Source处理后Blob借给独立store，保持原请求、Cookie、拦截器及处理结果。增加tile窗口/变化/释放控制与Dart小描述，Native只交付有界小片文件，不把编码页拷贝成整页PNG。复用Static Assets/Native内置材料，确认各端执行；编码页owner等待codec与borrow终态，tile失效后等待显示adapter确认释放。
4. **接入Reader窗口、预算与取消。** 将逻辑页header与tile资源分开，页内滚动更新source窗口/LOD，不将tile序号写成持久页键。解码/pull前预留工作与输出，旧片在帧/pin、实际provider cache eviction及Native ACK完成前继续计费。消费store的有界扫尾、非可见丢弃/缓存和缺片本地重扫，不积存整页raster或全部PNG。尾部失败撤下同会话全部provisional片；observed来自可见tile的实际Flutter frame，章节完成等待真实页terminal。覆盖取消、迟到、格式失败、缩放替换与完整cache key清理，合计预算和真实峰值另验。
5. **完成正式产品验收。** 原图首/中/末位置可辨；条漫、DPR、旋转、模式切换和缩放后恢复相同原图坐标。检查缓存变体全部释放、坏图后恢复与取消时所有权。Web 内置浏览器、iOS/Android 真机分别记录首图时间与进程/GPU 峰值；模拟器与替身 Widget 只算对应分层证据。

## 验收条件

- 不修改官方 Source/JAR，不绕过插件访问原图，不用宽泛断言绕过协议类型检查。
- 真实超过当前上限的长图通过明确支持的解码路径显示，并能定位首、中、末区域；不能只调高常量或以小图替身通过。
- 所有新增 raster/分片及工作预留有拥有者，清理确认前持续计费，取消/错误后能继续阅读。
- 已显示页和进度仍由真实 Flutter frame 推进；分片预取不冒充已读。
- 固定输入的 Web 与 Native 实测证据说明所覆盖格式和资源边界；未测的格式、Source 和设备继续明确待验。

实施变化同步本计划和 [P0](p0-runtime-and-reading.md)，实际证据归入 [VERIFICATION](../VERIFICATION.md)。
