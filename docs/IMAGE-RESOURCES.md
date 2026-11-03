# Source 图片资源通道

本文记录 P0 的产品图片合同。实现和分层验收见 [P0 计划](plan/p0-runtime-and-reading.md)及[验证记录](VERIFICATION.md)；协议设计本身不表示真实 Source 或移动设备已经通过。

当前合同使用 `karuyomi-source-host-v3`：Page 会话及 `hostAcquireImage/hostClosePageSession` 是必需 ABI，控制边界采用 Protobuf 生成模型和标准 ProtoJSON。控制信封 protocolVersion 为 2，HTTP bridgeVersion 为 2；三者含义不同。旧 ABI 的 AOT、客户端和材料必须同步重建，不混合部署。历史 v2 图片实测结果保留其原始身份，不能作为 v3 运行验收。

## 原始 Page 与逻辑页

`pages` 返回 `pageSessionId` 及 `pages`，每项包含 `pageKey/index/sourceIndex/url/imageUrl`。Java 在有界会话表中保留原 Source 返回的 Page 实例，包括其可变字段和子类；图片阶段不能用 DTO 重新构造 Page。会话绑定创建它的 Source 实例，Worker generation 或 build 改变时全部失效。

`ChapterPageProvider` 绑定 Source、会话、generation 和稳定章节引用，内部将阅读核心的逻辑页键映射到会话内 opaque pageKey。阅读位置不保存临时会话 ID 或有签名的 imageUrl。`reader_core.PageRef` 仅含 requestId、chapterKey、pageKey 和 generation，不依赖 TeaVM 或 Source URL。

章节导航负责关闭 Page 会话。释放显示资源与关闭 Page 会话是不同操作：前者撤销已交付的 Blob，后者解除 Java 原始 Page 引用。两者都必须在取消、路由离开及容器失效时清理。

## 处理与所有权

```mermaid
sequenceDiagram
  participant D as Dart PageProvider
  participant M as 主线程 manager
  participant W as Worker / TeaVM
  participant S as 原版 HttpSource
  D->>M: acquireImage(requestId, Source, 会话, 页, generation)
  M->>W: acquire-image + 独立 MessagePort
  W->>S: 原 Page 的 getImageUrl / getImage
  S-->>W: 经原拦截器处理后的 ResponseBody.source()
  loop 每块最多 64 KiB，等待确认
    W->>M: DATA(seq, transferable ArrayBuffer)
    M-->>W: ACK(seq)
  end
  W->>M: END(totalBytes)
  M->>M: 校验尺寸、预算，暂存未发布资源
  M-->>W: ACK(资源描述)
  W->>M: Java 成功结果
  M->>M: 确认结果一致，发布 Blob URL
  M-->>D: ImageResource 小描述
  D->>M: releaseImage(resourceId, generation)
  M->>M: 撤销 URL 并解除字节所有权
```

Java 仅在 Page 的 imageUrl 尚未解析时调用原 Source 的 `getImageUrl`，随后调用原 `getImage`。原请求头、Cookie、拦截器及图片处理保留在同一网络链中；不能直接读取原图 URL。cacheless/progress helper 也须保持上游语义。

Java 图片出口为 `teaImageOpen/Write/Close/Cancel`，同步控制信息保持小；Write 每次至多 64 KiB，等待 ACK 后才生产下一块。每次获取使用独立 MessageChannel，DATA buffer 转移所有权。END 时暂存已校验 Blob 并返回内部元数据 ACK，Java Close 完成后才返回 Source 调用成功。主线程必须同时收到有效流终态和一致的 Java 成功结果，才能创建 Blob URL 并向 Dart 发布资源；单独 END 或 RPC 成功均不足以显示图片。暂存后 Java 失败也须解除字节所有权。

HTTP handle 只属于当前 Source 调用，调用结束清理。图片资源归主线程 manager 所有，独立存活至 release；不能返回 HTTP handle 充当图片资源。资源描述为 `resourceId/generation/mimeType/byteLength/width/height/url`。Web 仅接受 manager 创建的 Blob URL；Native 需受管文件，尚未实现时返回能力不足。

编码字节、驻留资源与尺寸均受预算约束。尺寸头解析复用固定版本的 [image-dimensions](https://github.com/sindresorhus/image-dimensions)，先检查像素预算，再用浏览器 `createImageBitmap` 获取实际显示尺寸并立即 close，处理 EXIF 等浏览器方向语义。这会增加一次临时解码，不构成零复制或移动端峰值通过的证据。尺寸学习只更新 Reader 布局，保留 manifest.version 与逻辑锚。

| 范围                          | 当前上限                    |
| ----------------------------- | --------------------------- |
| DATA / 未确认块               | 64 KiB / 1 块               |
| 单图 / 在途与驻留编码字节合计 | 64 MiB / 64 MiB             |
| 单图 / 在途与驻留像素合计     | 16 Mi / 32 Mi 像素          |
| 在途与驻留资源数 / 尺寸头检查 | 6 / 前 1 MiB                |
| Java 原始 Page 会话           | 2 个会话，每个至多 2,048 页 |
| 取消退出宽限                  | 1 秒，超过则失效 generation |

像素预算只估算图片 surface（按 RGBA 为 64 / 128 MiB），不能代表浏览器进程合计峰值。浏览器解码无法中断时，取消也须等其完成并 close 后才能归还计数，不能用提前删除资源表来绕过总预算。

## 控制与清理

接口为 `acquireImage({requestId,sourceId,pageSessionId,pageKey,generation,timeoutMs?})`、`cancelImage({requestId,generation})`、`releaseImage({resourceId,generation})` 和 `closePageSession({pageSessionId,generation})`。release 幂等，重复释放不能复活资源。旧 generation 的结果不能落入当前会话。

ACK 和图片取消不能排在 Source 串行锁后等待。取消先终止图片 sink 与相应 HTTP 句柄，再等待当前 Java 调用退出；`teaDone/teaFail` 没有调用身份，提前解锁会使迟到回调污染下一次操作。超过取消宽限只能回收整个 Worker、失效 generation，并由客户端重新打开章节，不能静默复用旧 Page 会话。

Reader 在 widget、缩放 overlay 与解码缓存解除引用后释放资源。manager 在 invalidate、dispose 和 pagehide 中清理在途块、Blob URL 和资源表；失败、超限、解码错误及迟到结果也必须清理。图片窗口限制同时持有的页，不整章获取。

## 分层验收

- 通道：慢消费者背压、序号与字节预算、END/RPC 竞争、取消后退出、旧 generation、重复 release、空资源表。
- Java：原 Page 身份、Source 绑定、原图片方法与处理后正文、有界读取、关闭和失败路径。
- 实际 Web：未修改 Source 的真实章首中末页，经产品通道解码、阅读器导航、尺寸更新及释放。
- 后续设备门：Android ArrayBuffer / iOS 受管 WKDownload 文件交接、后台恢复及合计进程/GPU 峰值。

现有 Bitmap / ImageDecoder 内部的整图 Base64、`readAllBytes()` 与合计 graphics 预算仍需独立改造。外层图片通道通过不能代替图片解密/重排 Source、超长图或移动端完整阅读验收。
