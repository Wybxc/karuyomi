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

完整 `pnpm flutter:check` 已通过：Reader core 20 项、SourceRuntime 37 项、Flutter 应用 124 项；所有分析和官方 Drift 生成一致性检查通过。实际 PNG provider 回归确认观察者与 Image 共用一次 load/decode，覆盖同步缓存、坏编码、卸载后迟到和暂停。它们是工程测试，未启动本轮真实 Source 产品阅读。

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

默认材料测试确认 imageCodecs 为空、来源为 null 且候选准备器未调用。源码审查确认 Source host 无客户端 codec 导入，默认 build 与 Native 装配无 codec 输出路径；正常重建后的成品已按上述文件集核对，没有沿用旧 dist 目录证明新默认打包行为。以上均为工程/协议证据，未执行本轮真实 Source 阅读、浏览器交互或性能测试。

### Java 交付适配

`pnpm teavm:check` 已通过：原 seed 和正式自有 HttpSource 两套 `ImageTest` 各 8,355 断言，包括响应 `contentType()` 会抛错的输入仍可原样交付。原请求头、Cookie、getImageUrl/getImage、子类 Page、cacheless/progress 与原 Source 图片处理语义不变。本项为 JVM oracle，不等于新 AOT 的真实 Source 运行验收。

## 性能依据与下一门

现有顺序 PNG/JPEG 分片有正确性、条带缓冲、背压和取消机制证据，见[独立 codec 记录](long-image-codec.md)。16 MiB WASM heap 和 C payload 账本不等于进程 RSS、GPU 或 Flutter 端总峰值。尚无与 Flutter 直接解码、平台区域解码的同设备、同字节、同显示尺寸性能比较，不能据此选择默认分片算法。

顺序扫尾、反向跳转时重扫、PNG 再编码和跨端复制的成本须实测。下一步先记录 UI 直接解码的冷热首帧、首/中/末跳转、往返滚动与缩放，再在相同输入上比较候选方案的 CPU、帧耗时、RSS/GPU 和总峰值。标准见[设计](../design/reader-image-decoding.md)，实施顺序见[计划](../plan/reader-image-decoding.md)。

本轮未执行新合同的真实 Source 阅读或 Native/浏览器产品交互，未证明真实长图、EXIF/LOD、生产 Access、真机性能或 P0 通过。学习实际尺寸发生在客户端解码后，当前估算账本不能限制平台整图解码的瞬时峰值。
