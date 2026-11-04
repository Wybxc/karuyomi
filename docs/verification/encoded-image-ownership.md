# 编码页与分片所有权

2026-11-04：`EncodedImage`、Source 接收链、TS / Dart 控制解析及独立 `ImageTileStore` 已实现。这是长图产品接线的中间层；Reader 仍使用完整图路径，真实 Source 长图、Native codec 执行、方向显示和进程 / GPU 峰值尚未验收。当前控制身份仍为 protocolVersion 2 / host ABI v3，Java 图片桥原样传递描述；新代码、协议和依赖进入新的 host / material 输入身份，不修改旧 AOT checkpoint。

## 工程与所有权边界

- Protobuf 新增 `EncodedImage` 与 `acquireEncodedImage`，Buf 生成双端模型；编码页只描述处理后正文、原始尺寸和 EXIF 方向，没有显示 URL。PNG / JPEG 单页至多 8 MiB，原始宽至多 4096，PNG / JPEG 原始高分别至多 100000 / 65500，方向为 1..8。完整图显示操作仍有独立的 16 Mi 像素门。
- 原 Source 的 Page / `getImageUrl/getImage` / Cookie / 拦截器 / 处理链不变。END ACK 只确认收齐有界编码正文及解析元数据；Java 成功回包逐字段一致后才允许发布和借用 Blob。编码路径不创建整图 bitmap，不按原始像素申请完整 raster。
- `image-dimensions` 解析 raw 尺寸；精确锁定的 `exifr 7.1.3` 从完整有界 Uint8Array 读取方向，避免漏掉 IDAT 后的 PNG eXIf。额外 metadata 输入副本最多 8 MiB；该值不是实际进程峰值，也不证明八方向显示正确。
- owner 释放后禁止新借用；已经借出的 Blob 持续计费，直到最后一个 lease 归还。取消时若元数据工作仍未结束，也须等其终态才归还预算。Source 串行槽只等 Java 调用完成，后续 codec 不占用该槽。
- 独立 tile store 只允许一个活动 codec，持续扫到真实 terminal；不需要的 PNG 丢弃，缺片从同一编码 Blob 重新扫描。PNG 缓存最多 16 MiB，显示 lease 最多 64 份且合计最多 32 Mi 像素。失效片在显示 owner 确认释放前仍计费。store 不创建 URL / Native 文件，Reader 和正式 tile 控制仍待接入。

## 已执行的自动检查

在正式 main 工作区使用仓库固定 Node 与 Flutter / Dart：

```sh
pnpm generate
pnpm test:protocol
pnpm exec vitest run packages/contracts/test/encoded-image.test.ts
pnpm exec vitest run packages/runtime-host/test/encoded-image-resources.test.ts packages/runtime-host/test/image-resources.test.ts packages/runtime-host/test/image-manager.test.ts packages/runtime-host/test/image-driver.test.ts
pnpm exec vitest run packages/runtime-host/test/image-tile-store.test.ts
pnpm typecheck
cd packages/source_runtime
dart analyze
dart test
```

TS 编码页协议三项、Source 链四文件 35 项、tile store 23 项、Dart 包 37 项及跨语言黄金矩阵九项均通过。跨语言门实际调用固定 Dart codec，覆盖新命令、控制 / Worker 响应与 encoded END ACK 的 TS → Dart → TS / Dart → TS → Dart；没有用 TypeScript 类型代替跨语言解析。

Source 链测试通过真实 MessageChannel / ImageSink / collector；Java driver 和 manager 的测试包含受控替身，因此不算原 Source 在线成功。JPEG 的八个真实 EXIF 元数据和大于 1 MiB IDAT 后的真实 PNG eXIf 均经正式接收器解析；这些断言不涉及旋转显示。还覆盖超字节 / 几何预算、MIME / ACK 模式不符、Java 回包不一致、取消中计费、旧 generation、Dart 局部超时及迟到资源释放。

独立 store 的自动回归覆盖同窗口稳定 lease、重复请求不重复解码、显式 release 后不悄悄重新借出、缓存逐出与原 Blob 重扫、全局单 codec、缓存 / lease / 像素的独立预算、预算释放后的恢复、尾部失败失效和等待真实清理。其注入 codec 只证明领域状态机，不能代替真实 Worker 执行。

## 真实浏览器分项

Codex 内置 Chromium 156 在 `http://127.0.0.1:8954` 实际运行正式 `ImageSink` / collector / encoded END ACK / Blob borrow / `ImageTileStore` / VerifiedLoader / codec Worker。输入为合成的 Source 处理后正文，Java 成功结果由夹具模拟；未加载真实扩展，也没有 Flutter Reader。

| 输入          | 尺寸       |  编码字节 | SHA-256                                                            |
| ------------- | ---------- | --------: | ------------------------------------------------------------------ |
| PNG RGBA8     | 1080×20000 | 1,243,254 | `ef6a833915ade80ef3d3551f7993521125e94e53a5b8b1b465c30ec168a4e329` |
| baseline JPEG | 720×30000  |   904,939 | `59ade1e320abb7873e896f58543307721b561277e31aa18571122dc8618e9d0f` |

两图均超过完整图路径的 16 Mi 像素门，按分母 1 输出。六项全部通过：

- 每图各运行首→末→中→首窗口；前三次各一个完整本地扫描，最后一次命中缓存。每图只收一次 Source 正文，不重新获取原图；重复窗口保持相同 leaseId 和 Blob。
- 所需 PNG tile 的字节 SHA、几何与同一固定 C 构建的 Node 逐片 oracle 一致，HTML 图片元素实际解码并核对条带尺寸。Node 参考并非新的独立像素算法；此前独立 Sharp 像素对照仍引用[正式 codec 证据](long-image-codec.md)。这不是 Flutter frame 或实际 Reader 显示证据。
- PNG 删除 IEND / JPEG 删除 EOI 后，头部和正文接收仍可完成，真实 decoder 随后失败；已交付临时片从快照撤下并列入失效集合，显示 lease 确认前继续计费。
- 两图各在真实 Worker 活动且首片临时可用时调用 `removePage()`；均协作取消，无强制 terminate。Worker 终止、completion 和材料释放后 remove 才完成，最后归还 encoded borrow。

十个真实 codec Worker 均有对应 terminate，最大同时活动数为 1；十份执行材料均释放。各场景最终 Source resource / bytes / pixels、tile cache / leases / pixels / active decode / page 以及显示 URL 均为 0；编码接收的完整 bitmap 调用数为 0。账本和 terminate 调用不证明 OS / GPU 或物理 heap 回收峰值。

本轮 runId 为 `95bf4439-1e0a-4c4f-a2f4-a6c8b84187f1`；报告在 ignored `.local/image-owners/final-20261104/result.json`，SHA-256 `c0502a6f9d99c8eeddb9d1c8e7bc29ddb5cf9ba4eca3febb22ae1fec68c86643`。材料版本为 `5421945805ad29d489990bcf9836af697e3f6f65ad934da17fe939421af73b6f`，C build identity 仍为 `8b006f9bd99fa115394c48fd22ecbf929659be8ed9152c25701bbfbc822f8854`。无 cross-origin isolation，不使用 SAB。页面确认报告保存后正常关闭服务，CLI exit 0，8954 端口随后释放。

可复验入口：

```sh
# 先准备同一固定 codec 的合成输入和 Node 逐片 oracle。
pnpm image-codecs:check-worker --prepare-only
pnpm image-codecs:check-owners --output .local/image-owners/recheck --port 8954
```

在 Codex 内置浏览器打开打印的本地地址，运行六项并通过页面按钮正常关闭；详细配置、scope、trace 和报告保留于指定 ignored 输出目录。`--fixtures` 可明确指定首条命令产生的 `public` 目录。CLI 在首次准备前用 proper-lockfile 独占锁定输出目录，持有至服务结束；仅收到通过报告才成功退出，无报告、拒收或取消均退出 1。

### 首轮报告身份失败与修复

首轮服务期待 `2029cb34…`，并行 prepare-only 却将共享目录配置覆写为 `0536061b…`。UI 六项显示通过，报告 POST 因 runId 不一致被 400 拒收，不能计作已通过验收；失败配置、必要记录和截图保留在 ignored `.local/image-owners/report-id-mismatch-2029cb34/`。旧 CLI 无报告仍 exit 0 的错误也已修复。三个短回归证明持锁的第二入口不能覆写 sentinel、准备失败释放锁、无报告服务保持未通过；修复后使用独立目录取得上述有效报告。

## 最终工程检查

完整 `pnpm format`、macOS `pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build` 均通过。Vitest 为 329 项，image 工具及 runtime 自动检查为 94 项；Flutter 三包分析及 reader_core / source_runtime / reader 测试分别为 16 / 37 / 102 项。完整构建包含 Native 内置材料装配、Flutter Web 和 Worker dry-run；没有执行生产部署，也不将构建成功写为 Native codec 运行成功。

## 后续产品门

将编码页借用与 tile store 接入正式 Protobuf tile 控制、Web URL / Native 小片文件、Reader 视口调度及实际 provider cache。显示进度须来自真实 Flutter frame，页完成须等完整 terminal；尾部失败撤下同会话临时片。随后按[长图计划](../plan/reader-image-decoding.md)验真实 Source、任意位置 / 反向滚动、EXIF 方向 / LOD、Native 执行及设备峰值。
