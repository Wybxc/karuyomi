# 正式图片页与分片控制

2026-11-04，正式 main 工作区。本轮把已发布的 Source 编码页、独立 codec/store 与 Web/Dart/Native 控制边界接通。Reader 尚未消费此合同；真实 Source 长图、八方向显示、Native 新 codec 执行与设备资源峰值仍待验收。[此前编码页与真实 Web owner 证据](encoded-image-ownership.md)保持其原有材料身份和范围，不能自动扩大为本轮正式控制或 Flutter 显示证据。

## 实现范围

- 唯一 Protobuf 合同新增 `openImagePage`、`requestImageWindow`、`waitImageWindow`、`releaseImageTile` 和 `closeImagePage`；Buf 生成双端模型。窗口含 page/generation/windowId/revision、raw header、逐片 sourceRect/缩放/session、临时状态和失效租约。TS 与 Dart 在消息边界独立解析并校验业务预算；完整图像字节不进入控制 JSON。
- `ImagePageControl` 只借用已匹配 Java 成功回包的处理后 Blob，不重新调用 Source。打开逻辑页后，调用方显式 `releaseImage` 归还原编码 owner；borrow 继续计费至页关闭且实际 codec 终止。单活动 codec、16 MiB PNG 缓存、64 份显示 lease 和 32 Mi 像素门沿用独立 store。
- Web 每个 lease 只创建一次 Blob URL，重复观察复用身份和 URL。坏尾撤下临时片并列入失效集合，已发布 URL/像素仍等待客户端显示释放 ACK；关闭页不代替该 ACK。未对客户端发布的隐藏 pin 由宿主清理。重建关闭旧页和借用，但仍接受旧 generation 的显示释放。
- 窗口 ID 不可改几何或重新使用已经替换的身份。长轮询最多 25 秒、并发最多 32 个，超时返回当前快照，不重建正常 Source。每次可观察失效列表变化，包括失败页的释放 ACK，都会推进 revision；同 revision 的结果不能悄悄改变。
- Native 复用现有 WKDownload / Android 有界 ArrayBuffer 文件通道，`copy` 接受显式 requestId/generation/resource，而不伪造 Source 请求。编码页留在 JS；只复制单片最多 8 MiB、4096×256 的 PNG。重复或并发快照复用同一文件，Android 仍复用原有至多六条通道。小片限额为 64 份 / 16 MiB，整图仍为六份；两者共用 32 Mi 像素和 64 MiB 文件预算，预留包括在途复制与保留文件。
- Dart 返回深冻结 DTO，核对 page/encoded raw header、窗口、revision、稳定 lease/文件身份及合计预算。`file:` 还必须经正式 Native transport 所有权表确认。关闭、换代和失效不自动清空已交付 lease 的账本；释放 ACK 才清账。

控制身份仍为 protocolVersion 2 / host ABI v3；原 Java 图片桥不变，新宿主和协议源码进入当前构建指纹。没有修改官方扩展/JAR，没有复用或覆盖旧冻结 AOT checkpoint，也没有部署生产。

## 已执行的检查

使用固定 Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4 和 Xcode 27.2：

```sh
pnpm format
pnpm format:check
pnpm check
pnpm flutter:check
pnpm build

# 正式 iOS target；选择可用模拟器。
cd apps/reader/ios
pod install --deployment
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  FLUTTER_TARGET=lib/main.dart -only-testing:RunnerTests/NativeImageFilesTests test
```

上述完整格式化、格式检查、`pnpm check`、`pnpm flutter:check` 和 `pnpm build` 均已通过。自动回归的覆盖边界：

| 入口                                                     | 覆盖与限制                                                                                                                                                                                                      |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| contracts 与 TS↔Dart golden                              | 五命令、页和 pending/complete/failed 窗口的标准 ProtoJSON/二进制往返；身份、几何、片数、像素和字节预算。这是实际双语言 codec，未执行浏览器或 Native 容器。                                                      |
| `packages/runtime-host/test/image-page-control.test.ts`  | 正式 host.control → manager → borrow/store 的真实 MessageChannel/collector；稳定 URL、Source 槽独立、窗口替换、有界等待、坏尾、跨代释放、关闭等待终态及未发布 pin 清理。Source driver、codec 与材料为受控替身。 |
| `packages/source_runtime/test/image_windows_test.dart`   | 冻结、幂等打开、重复窗口、入参/响应解析、被拒窗口恢复、迟到或 foreign 响应、局部超时、失效/关闭/换代后计费，以及释放与在途观察的竞态。transport 为替身。                                                        |
| `apps/reader/test/runtime/native_tile_control_test.dart` | 超过六片的稳定文件、并发复用、关闭等待复制取消、窗口替换、被拒窗口恢复、额度持续计费、释放重试，以及释放前后旧快照禁止重新发布。文件通道为测试实现，不是 WKDownload/Android WebView 实际传输。                  |
| `NativeImageFilesTests`                                  | iOS 模拟器正式 RunnerTests 12 项通过；包括 tile 大小与独立份数/字节限额、整图与小片共享像素预算、绑定及取消终态。不是实际 codec 或 Reader 长图显示。                                                            |

首次 XCTest 因该工作区缺少本地 `Pods/Manifest.lock` 而在 CocoaPods 同步检查失败，未进入测试。`pod install --deployment` 按现有锁文件恢复生成目录、锁文件无变化后，iPhone 17 Pro / iOS 26.4 Simulator 的正式测试全部通过；Xcode 使用的测试克隆随后已自动关闭。首次全工程检查也因并行补写的 Dart 测试尚未格式化而失败，后续以完整格式化后的重跑结果为准。

原始日志保留于 ignored `.local/tile-control-*.log`，不把完整机器日志入库。完整构建只证明 Web/Native 材料装配、Flutter Web 与 API dry-run，不等于 Native 材料已经实际执行。

## 剩余产品门

1. Reader/provider 改为逻辑页加可见 raw 窗口，页内滚动、缩放、LOD 和 EXIF 方向需要进入需求身份；不能用完整页 raster 或 tile 序号替代逻辑锚。
2. 逐片撤下 widget/pin、等待实际 frame 与对应 provider cache eviction 后，再释放 Blob URL/Native 文件和 lease；坏尾须撤下同 session 的所有临时片。可见 Flutter frame 和实际页 terminal 是不同状态。
3. 在正式 Source 图片链上分别验收 Web、iOS、Android 的长图首/中/末位置、取消恢复、缓存/LOD、方向和资源峰值。现有合成 owner、模拟 driver、文件替身和 XCTest 不能关闭这些门。
