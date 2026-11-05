# 阅读器图片解码与长图评估

## 目标与状态

保持 Source 原有图片获取和处理语义，使 Web 与 Native 阅读器在真实客户端中完成解码、布局、显示及资源释放。先测量 Flutter 直接解码的正式 UI 基线，再依据首图、交互和内存数据决定是否采用分片、降采样或成熟区域解码器。

状态：**进行中，Source 图片交付已收敛为不透明编码资源，客户端实际帧尺寸与预算接线已实现；原 xkcd Web 下载完整性及 Arknights 当前合同下完整章/下一章/首次续读已通过分项，当前路径的多次真实 UI 性能基线、长图、EXIF/LOD 与真机验收仍待完成。** 本计划是 [P0 阅读计划](p0-runtime-and-reading.md)的图片子计划，不能以编译、逻辑预算或独立 codec 机制关闭产品门。

## 当前架构与实现边界

- `PageProvider.acquire` 仍返回 `ImageResource`，仅含 `id`、`generation`、`location` 和 `byteLength`。Source/host 交付边界只收集、传输、持有及释放编码正文，不检测 MIME、宽高或 EXIF，不为阅读器预解码，也不提供编码页、分片或窗口控制协议。保持原插件处理后的正文，不通过原图 URL 绕过插件。
- Web 使用受管 Blob URL，Native 使用受管文件；Flutter 的实际 `ImageProvider` 负责解码。`ResourceImage` 与显示用 `Image` 复用相同 provider/cache key/completer，额外 listener 只提取并释放其拥有的 `ImageInfo`，不再创建 codec 或重复解码。只有真实 frame 与尺寸均已就绪时才发出 decoded 通知；错误单独通知。
- `ImageDimensions` 是客户端布局模型，不进入 Source 描述。Reader 根据实际解码宽高学习页比例，保持逻辑页键、内容版本和页内归一化锚。预取成功不代表已读；解码失败或超预算资源不得推进 observed。
- `ImageScheduler` 未获得客户端尺寸时沿用既有未知页估算，获得实际帧后按 `width × height × 4` 更新解码估算。编码正文和已知 decoded 成本在资源退休后继续保留到释放 ACK；widget pin、帧尾和实际 provider cache eviction 仍决定何时可归还文件/Blob。当前预算没有提高。
- 这套后验账本限制接纳和后续生产，**不能证明平台整图 decoder 的初次临时分配或 GPU 峰值有界**。当前产品仍使用 Flutter 整图显示路径，尚未完成终端长图方案选型和性能验收。
- 候选 codec 源码集中在 `runtime/image-codec/`，保留独立构建和测试入口，退出默认构建、Web 静态资源和 Native 打包。尚无真实 UI 性能对照支持把它选为默认；候选 Worker、tile store 或 WASM 算法均未接入当前 Reader。

当前源码和候选库约束见[解码设计依据](../design/reader-image-decoding.md)，Source 交付与所有权见[图片资源通道](../IMAGE-RESOURCES.md)。

## 工程验证与历史证据

本轮领域与 widget 回归覆盖不透明资源引用、实际 provider 只 load/decode 一次、真实帧尺寸、缓存同步帧、错误/卸载后迟到结果、暂停时 observer 生命周期、布局锚保持，以及释放 ACK 前的编码/解码成本。它们是工程回归，不能代替正式 Web/Native 主入口和原 Source 的运行复验。

当前合同下，正式 Web release 的原 xkcd 漫画、TextInterceptor 文字图、显式完成及退出已通过分项；采集入口在保留首次导出失败后，完成一次真实 JSON 下载、正文解析、帧号关联和释放 ACK 完整性门。该单次样本不是首图/跳转性能分布；该固定版本同页在采集开始前仍有一次 RenderBox 未布局错误，后续诊断层复验分开记录。固定输入、运行条件、CI 与限制见[UI 图片证据](../verification/ui-image-boundary.md#web-报告下载完整性复验)。

原 Arknights DREAM 51 页、显式完成、下一章 HEARTBEAT 第 1–3 页及同标签页首次续读第 3 页也已通过当前合同的正式 Web 分项；后段采集观测到资源释放和章节退出 ACK，具体计数与区间只在证据记录维护。视口中途变化，采集未覆盖前 43 页全部生命周期；不能据此声称全章性能、进程/GPU 释放或诊断层初始焦点问题已解决。操作重试、固定身份与范围见[当前完整章记录](../verification/ui-image-boundary.md#当前合同的-arknights-完整章与首次续读)。

正式 `d312a387` 采集版将诊断控件延后到应用首帧布局完成后挂载，限定 1280×720 的三次新文档焦点复验未记录 error，随后原 xkcd 两页阅读、完成/退出和报告时间、帧号、资源 generation/释放完整性也已复验。无障碍实际通过 Enter 启用；该次下载按钮未取得文件，最终从页面已有 Blob 链接取得报告，保留交互限制。旧默认对照、两轮失败和当前限定通过范围见[焦点复验](../verification/ui-image-boundary.md#初始焦点对照与诊断层收敛)，不推广为浏览器进程、所有焦点条件或性能验收。

以下历史材料保留原输入、环境、失败和证据范围，**其架构已被本轮客户端解码决策替代**：

- [长图 codec 记录](../verification/long-image-codec.md)：固定 libspng/libjpeg-turbo、PNG 条带编码器、Node 和独立 Codex 内置浏览器 Worker 分项，及材料准备/打包的历史工程证据。独立解码、取消、背压、截尾和像素对照不代表 Reader 已接入，也不证明实际 UI 速度或进程/GPU 峰值。
- [编码页所有权记录](../verification/encoded-image-ownership.md)：历史 `EncodedImage/acquireEncodedImage`、Java 一致性/borrow 及合成正文 Web owner 机制。当前 Source 合同已删除这套图片信息与编码页分支，不保留兼容层。
- [分片控制记录](../verification/image-page-controls.md)：历史 host `open/window/wait/release/close`、Dart/Native 小片文件和模拟边界。该合同已退出正式 Source 路径，不能继续列为产品能力或当前验收。
- 此前普通图片、文字图恢复和模拟器 Source 阅读记录仍只证明各自固定版本。原 Web 黑屏、Android observed 调度、截断/progressive 不支持等失败与限制保持在原验证记录，不因架构调整改写为通过。

## 实施顺序与待办

1. **收敛并验证客户端直接解码路径。** 不透明资源合同与实际 `ImageInfo` 接线已经实现。原 xkcd Web 已观测到两份资源的 release ACK 和 reader exit ACK；继续核对双端传输、取消、迟到结果、文件/Blob 释放、真实 provider cache key 与帧尾 pin。当前 Arknights Web 完整章、下一章与首次续读已按新材料分项复验；继续完成更多 Source、Native 主入口与目标设备恢复；诊断层初始焦点已通过上述限定复验，后续自动化采集改用完整 JSON 复制，Web 复制链路待实测；更广焦点条件仍需另外验收。
2. **建立真实 UI 直接解码 baseline。** 默认关闭的采集入口已接正式 app 层，记录 acquire、实际 ImageInfo、逻辑 viewport、导航与 engine FrameTiming，并有界导出原始 JSON；用法与计量范围见[采集说明](../READER-BASELINE.md)。原 xkcd 的一次真实下载及报告完整性分项已通过，首次导出失败和采集前布局错误保留；入口回归或单次完整性均不等于实际性能门。固定同一原 Source、编码正文、构建版本和设备，覆盖普通图、长 JPEG/PNG、冷/热缓存、首图、中末页跳转、连续滚动、缩放与退出取消。Web 使用 Codex 内置浏览器；iOS/Android 区分模拟器和真机。记录首图可见时间及分布、跳转延迟、滚动卡顿/掉帧、CPU、RSS 和 GPU 峰值；明确运行次数、测量方法和无法取得的指标。
3. **依据瓶颈比较成熟方案。** 先查正式 Flutter/平台成熟 decoder 与区域解码库；在同一编码输入和实际 UI 上比较直接解码、目标 raster/降采样、成熟区域 decoder，以及有证据支持时的候选 `runtime/image-codec`。包含解码、重编码、跨线程传输、Flutter 再解码、缓存和显存成本，不只比较 WASM 或单个函数耗时。默认方案由性能、格式覆盖、维护和可用性共同决定，不能先接线后补理由。
4. **必要时实施客户端长图方案。** 选型后才设计逻辑页、EXIF 八方向、LOD/可见覆盖、跨页单 codec、合计工作预算和帧尾释放。分片序号不得成为持久页键；缩放 dialog 与主阅读视图协调所有权，错误/取消/迟到结果不得污染当前 generation。全部图片知识保留在客户端，不重新扩展 Source/host 图片协议。
5. **完成产品验收。** 在声明支持的 Web、iOS/Android 真机和格式上，验证真实长图首/中/末可辨、连续阅读、模式切换、旋转与缩放后的相同逻辑锚。对照 baseline 报告首图、滚动、CPU/RSS/GPU 和释放结果；缺少实测的格式、EXIF/LOD、Source 和设备继续列为待验。

## 验收条件

- 不修改官方 Source/JAR，不绕过插件，不以图片协议字段或类型断言掩盖边界错误。
- 客户端尺寸来自实际解码显示链，预取和 Source acquire 成功均不推进已读；错误、超预算与迟到结果不会推进 observed。
- 全部已拥有资源在释放 ACK 前持续计费；退出、错误与取消后能释放并恢复阅读。逻辑账本与进程/GPU 实测分别报告。
- 先取得可复验的正式 UI baseline 和候选对照，才确定长图默认方案；不通过调高整图预算或小图替身宣布长图支持。
- 真实长图与方向/缩放/恢复通过所声明的设备和格式范围，未测部分明确保留。

实施变化同步本计划和 [P0](p0-runtime-and-reading.md)，实际运行证据归入 [VERIFICATION](../VERIFICATION.md)。
