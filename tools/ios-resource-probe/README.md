# iOS 受管资源文件通道探针

这是独立的开发夹具，未接入 Flutter 产品工程。它验证公开 WebKit API 能否把同一受管 `WKWebView` 中 Worker 处理后的字节存为受管临时文件：

`Worker → transferable ArrayBuffer → 页面 Blob URL → WKWebView.startDownload → WKDownloadDelegate → 临时文件`

JS/native 消息只传请求 ID、Blob URL、字节数、摘要与状态。正文不通过 JSON、Base64、`WKScriptMessage.body` 或 localhost 资源代理搬运。原生端不替换下载过程中的 `navigationDelegate`，在 `startDownload` completion 中设置专用下载 delegate。

运行环境需要 macOS、Xcode、已安装的 iOS Simulator runtime、XcodeGen、Python 3 与 OpenSSL。默认命令创建专用测试模拟器，退出时关闭并删除它：

```sh
cd tools/ios-resource-probe
python3 run-simulator.py --https
```

`--https` 在被创建的测试模拟器里安装一天有效的临时 loopback 根证书，使用标准系统信任检查；没有跳过 TLS 校验的 delegate。它不修改 macOS 或物理设备的信任设置。移除 `--https` 可复核 loopback HTTP。默认 runtime 为 `iOS-26-4`，可通过 `--runtime` 和 `--device-type` 指定本机已安装版本。`--device UDID` 只用于已有专用测试模拟器，脚本不会删除该设备；HTTPS 模式安装的证书会保留在该测试设备中。

脚本构建原生 app，启动只服务 `web/` 夹具的 loopback server，安装并运行 app，读取 app 自身报告。结果位于被忽略的 `results/last-report.json`；构建与证书位于被忽略的 `.build/`。脚本会独立计算二进制样本的摘要，并检查五个用例、Worker buffer 脱离、原生文件删除、Blob 撤销与最终空资源目录。`sourceSha256` 记录执行源文件的摘要。

用例包括 256 KiB、4 MiB、16 MiB 受控二进制字节、Worker 用 OffscreenCanvas 生成的 128×256 PNG，以及 16 MiB 下载启动后的立即取消。原生端每次最多读取 64 KiB 进行 SHA256 验证，并以 ImageIO 验证 PNG 尺寸；下载文件名由原生随机生成。取消用例验证 `WKDownload.cancel` 回调和资源清理，不证明任意传输阶段取消或持续内存压力下的表现。

`evidence/` 保留一次小型实测报告。模拟器中 `secureContext=true` 可能来自 loopback 例外，须同时检查 `transportSecurity` 和 `localHTTPSVerified`。本地临时证书 HTTPS 的结果不证明真实 Source HTTPS、Cloudflare Access/cookie 上下文、物理 iPhone、真实图片处理链、超长图分片、后台/崩溃清理、进程/GPU 合计内存峰值或首图性能。报告对生产 HTTPS、真机与内存峰值始终明确标为未验证。

当前锁定的 `flutter_inappwebview 6.1.5` / `flutter_inappwebview_ios 1.1.2` 还不能直接消费这条通道：`InAppWebView.swift` 的 `download(_:decideDestinationUsing:...)` 在发送 `onDownloadStartRequest` 元数据后清空 delegate，并以 `completionHandler(nil)` 取消下载；`navigationResponse:didBecome download` 同样清空 delegate。Dart 下载回调不提供 Blob 正文，插件也没有暴露 `startDownload`。后续产品接入需要很薄的插件扩展：在已有受管 `WKWebView` 上调用公开 `startDownload`，使用独立 delegate 管理文件、ID、代次、大小、取消与释放。当前探针不代表这个扩展已实现。

依据为 Xcode 27.2 SDK 的 `WKWebView.h`（`startDownloadUsingRequest` 自 iOS 14.5 可用，使用当前页面上下文）和 `WKDownloadDelegate.h`（明确包含 Blob 的 synthesized response）；[Apple WKDownload 文档](https://developer.apple.com/documentation/webkit/wkdownload) 提供 API 入口。没有采用私有 API 或二进制桥接假设。
