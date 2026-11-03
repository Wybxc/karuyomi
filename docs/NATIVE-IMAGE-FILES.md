# Native 受管图片文件

本文记录 P0-F3 的 Native 产品实现与已执行的机制验收。公开图片合同仍由 [IMAGE-RESOURCES](IMAGE-RESOURCES.md) 和 Protobuf 定义；本文不新增 Source 控制方法。原 Source 完整阅读、Android 设备、物理 iPhone、后台恢复和进程/GPU 合计峰值仍需分别验收。

## 产品路径

`NativePlatformRuntime` 在部署 HTTPS 控制页的 document-start 注入已校验的内置 host/Worker，以及该容器独有的随机图片绑定 token。仅通过平台能力检查并成功绑定文件存储后，Dart 才能获取图片；TS Native 入口仅在 `imageFiles === true` 时启用图片 manager。`/runtime/host.html` 和 Static Assets 规范化后的 `/runtime/host` 均受支持，其他 origin、路径、frame 不安装该能力。

Source 仍从原 Page 实例调用图片处理链，经 Worker 的 64 KiB/ACK 通道生成 manager 持有的 Blob。Dart 的 `NativeImageControl` 接收生成模型中的小描述，将同上下文 Blob 交给平台文件 sink，完成后仅将 `ImageResource.url` 换成受管 `file:` URI。图片字节不放进 ProtoJSON、MethodChannel JSON 或 Base64，也不重新请求原图 URL。

`TransportSourceRuntime` 只允许实现 `ManagedImageTransport` 的平台表确认过的 `resourceId/generation/file URI` 三元组。Web 继续只接受 manager 的 Blob URL。Reader 的 widget、overlay 和图片缓存解除引用后，release 同时删除本地文件并释放 manager 的 Blob；任一 owner 未确认清理均不返回成功 ACK。取消只作用于在途获取，迟到 cancel 不删除已交付文件。

## iOS

锁定的 `flutter_inappwebview 6.1.5`（iOS 子包 1.1.2）没有暴露现有 Headless WebView 的公开原生 registry 或 `startDownload` 方法。Runner 内的薄插件使用公开 UIWindowScene/UIView 树发现 WKWebView，再同时核对 HTTPS 控制页和 document-start token，且必须恰有一个匹配。它不使用 KVC、私有 registry 或私有 WebKit API，也不接管插件的 navigation delegate。找不到或多重匹配会明确失败；此发现方式依赖锁定插件确实将 Headless view 挂入公开视图树，不是上游提供的稳定 accessor。

绑定后，插件在同一个 WKWebView 上调用公开的 [`startDownload(using:completionHandler:)`](<https://developer.apple.com/documentation/webkit/wkwebview/startdownload(using:completionhandler:)>)，由 [`WKDownloadDelegate`](https://developer.apple.com/documentation/webkit/wkdownloaddelegate) 决定随机私有文件目标。只接受同 origin Blob，校验下载 MIME、声明长度、实际文件长度及普通文件类型，拒绝下载重定向与认证挑战。目录权限为 `0700`，文件为 `0600`；每次进程首次建立存储时移除自身目录中的崩溃残留。

绑定有自身期限与一次完成 fence；迟到 JavaScript 探测不得再创建目录或 binding。下载任务在尚无 WKDownload handle 时强持 originating WKWebView。取消/clear 等待真实取消回调和文件删除，正常完成才归还预算。超过 1 秒宽限只返回 `runtime_lost` 并失效容器，不能伪造取消成功；无公开 handle 或回调永久不返回时保留有界 tombstone、容器和 reservation。晚到 handle 只取消，不重新登记为活动下载；真实停止后再删除文件、归还预算，并在 closed binding 排空后自动删除目录和表项。

## Android

复用锁定插件的 `WebMessageChannel` 与 [`WEB_MESSAGE_ARRAY_BUFFER`](https://developer.android.com/reference/androidx/webkit/WebViewFeature#WEB_MESSAGE_ARRAY_BUFFER) 能力，所有必需 feature 均在启用前检查。缺少能力时明确返回 unsupported，不回退到图片 JSON/Base64。

插件原生 channel registry 只随 WebView 销毁清空，因此文件 sink 使用最多六个常驻 port 槽位，每槽只安装和转移 port 一次，不能将已关闭或已转移的 port 再次转移。每次传输使用该槽单调递增且不回绕的 identity；二进制消息前八字节为 transfer/sequence 两个 u32 BE，余下至多 65,528 字节为图片内容，总消息不超过 64 KiB。每块写入文件后才 ACK；ACK、END、取消终态均绑定 transfer，旧消息不会确认新任务。槽位只在上一任务终态清理后复用，clear 关闭端点，容器销毁释放插件 registry。

这段私有平台 sink 使用 ArrayBuffer 正文和小 ACK/终态字符串，不改变公开 ProtoJSON Source 控制合同。取消需等 reader 退出、端点终态与本地写入结束；无法确认时返回 runtime_lost 并销毁容器。文件位于应用私有临时目录，release 删除文件。Android 路径已实现与静态检查，但尚未在 Android WebView/设备运行验收。

## 预算与生命周期

在途和驻留文件共同计入六资源、64 MiB 编码字节、单图 16 Mi 像素、合计 32 Mi 像素预算。manager 的 Blob 仍占其原有预算，直到本地文件 release 后对应的 JS release 完成。文件是额外磁盘副本；浏览器临时解码、Flutter 图片缓存、graphics surface、GPU 和进程总内存不由文件预算代表，不能声称零复制或峰值已通过。

总 acquire 期限包含 Source 获取和文件交接。本地 timeout 优先于其取消导致的 Source cancelled 错误。失败清理未确认时保留资源 reservation，并报告 runtime_lost；不因删除任务表就归还额度。重建先失效代次、阻断旧控制调用、关闭文件存储，再 dispose WebView；并发重建共享同一清理。迟到绑定若属于旧代次立即 clear，不进入当前图片表。

## 验证与复验

2026-11-03，在 Xcode/SDK 27.2、iOS 26.4 Simulator、iPhone 17 Pro 执行了真实 Flutter 机制夹具：本地证书加入 Simulator 系统信任，正常 HTTPS 校验，无证书回调绕过。产品 `NativePlatformRuntime` 完成内置 host 握手和 token 文件绑定；另一个相同配置的真实 Headless 容器生成受控 PNG Blob，经文件桥完成以下检查：

- `.html` → `/host` 的 307 后仍可绑定和下载。
- 文件 1,175 字节，与页面 SHA-256 `f694470448464f9a7a687ccae167c7ec648af449b4c4169689326e08f0c73b95` 一致，Flutter 文件解码为 256×128。
- 实际 `NativeImageControl` 仅发布匹配 resource/generation/file 的所有权；stale generation 无权使用文件，release 撤销所有权。
- late cancel 保留已交付文件，release 幂等删除，在途取消等待实际清理，clear 删除绑定目录。

夹具使用当次 main 构建的内置材料 `fba63bcd9b2a194131eb76a500c2e8f046d987b4650d510d6b6f5205bf32a9e8`，原始报告与临时 HTTPS 工程保存在忽略的 `apps/reader/.local/native-image-probe/`，未作为产品假 Source 入口提交。这是容器和文件交接的证据，尚非原版 Source→Native Reader、生产 Access 或真机验收；冻结版本的 Web Source 证据不能与另一材料版本混装。

本轮 Flutter analyze 与 SourceRuntime analyze 均无问题；Flutter 全部 45 项、SourceRuntime 全部 23 项测试通过，iOS 模拟器 XCTest 11 项通过。正式回归包括 Dart 资源所有权、取消 ACK、timeout 分类、迟到结果、配额、目录边界；Android 头部解析与实际嵌入脚本的 Node MessagePort 背压/复用/旧 ACK/取消；iOS XCTest 的路径、描述、共享预算、目录与绑定/pending-start/cancel deadline。Node MessagePort 测试不代表 Android WebView 已通过。

```sh
# apps/reader；使用仓库锁定的 Flutter SDK 和 PUB_CACHE
flutter analyze --fatal-infos
flutter test

# packages/source_runtime
dart analyze
dart test

# apps/reader/ios，指定可用 Simulator ID；不使用旧探针 target
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  FLUTTER_TARGET=lib/main.dart -only-testing:RunnerTests/NativeImageFilesTests test
```

## 原版 Source 到 Native 文件的分项验收

同日固定 `a15c030` 的独立工作树，在上述 iOS 26.4 模拟器用实际 `CatalogController → ChapterPageProvider → NativePlatformRuntime` 完成原版 Arknights Comics 1.6.2 的目录、详情、章节、页会话和图片交接。正常受信 HTTPS 前端流式转发到真实 workerd、隔离 D1 与 RS256 测试身份；没有放宽产品 TLS 或生产鉴权。热门 17 项、所选漫画 3 章、DREAM 51 页，latest 依源声明不支持。

复用了 [v3 构建](verification/protocol-v3-runtime.md) 的 `ext-en.arknightscomics-23489f22c8a1d874d1a62ca1ecd743a3`：新树 host 指纹仍为 `2229bb210e74c8def41cda1fcbc7bbce6937dd8ad92a8aa01fdb765430ea1508`，materials 仍为 `fba63bcd9b2a194131eb76a500c2e8f046d987b4650d510d6b6f5205bf32a9e8`，清单 SHA-256 `f3373696187454a2465a022bca977ce700bc0f94a59bdec5c19b96ba05af42be`。Native host/Worker 与本次内置索引逐字节匹配，未放宽材料身份检查；后续 graphics/Cache 输入变化必须重新 AOT 验证。

| 实际章节页 |       文件字节 | Flutter 文件解码 | 释放                                    |
| ---------- | -------------: | ---------------- | --------------------------------------- |
| 第 1 页    | 39,602 B，JPEG | 1200 × 1691      | 文件删除、所有权撤销、重复 release 通过 |
| 第 26 页   | 719,916 B，PNG | 1200 × 1691      | 同上                                    |
| 第 51 页   | 718,931 B，PNG | 1200 × 1691      | 同上                                    |

三份文件的 SHA-256 均机器核对为对应 workerd 上游流的摘要。`ChapterPageProvider.close()` 在获取中取消并关闭原 Page 会话；保留一张未释放图片后调用真实 `NativePlatformRuntime.rebuild()`，文件和 binding 目录消失、旧所有权失效，新 Source 在不同 generation 下重开。原始小报告留在冻结工作树忽略的 `.local/native-source/`；测试服务、隔离 D1、静态快照和 App 已清理。仅合法的空 process 根目录残留，不将其误报为未清理 binding。

这是实际 Dart 产品控制器与 Source/文件通道的分项证据，尚非 Native ReaderScreen 的完整交互、3–5 个处理源、整章/下一章、后台恢复、物理设备、生产 Access 或峰值验收。公开 API 没有直接暴露原 Blob URL 或 Swift reservation 计数，文件消失不能单独证明内存或全部账本归零。后续保留这些门；Android 还需真实 ArrayBuffer 插件链与端点复用验证。
