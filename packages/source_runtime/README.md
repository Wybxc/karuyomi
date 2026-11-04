# SourceRuntime

纯 Dart 协议包；`TransportSourceRuntime` 将 Source 调用和图片生命周期映射到小型控制 DTO，并检查 build、generation、request ID 与字符串 Long Source ID。结构化异常保留错误类别与 Java class；容器重建后丢弃迟到结果，迟到图片会请求释放。图片正文不进入 Dart 控制消息。

控制模型由 `protocol/karuyomi/v1/control.proto` 生成，`control_protocol.dart` 导出模型及标准 ProtoJSON codec。边界使用 `mergeFromProto3Json` / `toProto3Json`，不使用数字字段名的旧 JSON API。Web 和 Native 都调用 `karuyomiRuntime.control`，请求、响应、Source 操作和结果由生成的 oneof 区分；响应必须匹配独立的 control request ID 与原 Source request ID。字段结构和 enum 由生成 codec 校验，oneof 冲突通过生成描述符检查，预算、generation 和资源生命周期继续由业务层检查。Native 返回 `JSON.stringify` 文本，避免 WebView 将整数统一映射为 Dart `double`。

`RuntimeSession`、`SourceInfo` 和 `SourceResult` 直接使用生成类型；`SourceRequest.call` 为生成的 `SourceCall`。`supportsLatest` 使用显式 presence 区分缺省与 `false`；Source ID、上传时间和 opaque 句柄保留字符串。只有扩展私有 memo 使用有界 `memoJson` 对象文本，校验后原样保留，不解析后重写大整数。控制请求上限 128 KiB，响应 8 MiB，Page 清单 2 MiB，memo 64 KiB，JSON 嵌套上限 64。

`ChapterPageProvider` 绑定 Source、Java Page 会话和运行代次，将 reader_core 的逻辑页键映射到宿主保存的 opaque Page 句柄。`acquireImage` 仅返回资源身份、代次、字节数和受管 Web Blob URL 或 Native 文件 URI；Source 与宿主不解析图片格式、尺寸或方向，也不预解码。图片解释、解码、显示、窗口与缓存由客户端负责。正文按 64 MiB、6 份资源限制，已交付资源在释放 ACK 前继续计费；`cancelImage` 等待停止生产确认，`releaseImage` 和 `closePageSession` 等待清理确认。章节关闭会取消未完成请求、释放迟到图片和存活资源，再关闭 Page 会话；普通 Source `cancel` 与图片取消分开。

Flutter 平台实现放在 `apps/reader/lib/runtime`。Web 通过 `dart:js_interop` 连接全局 `karuyomiRuntime`；原生使用 HTTPS 部署 origin 和同源受管 WebView。打开前从 bootstrap 确认身份，提供当前 Static Assets 清单路径、build ID 和 bundle SHA-256。`ApiFetch` 使用同一个浏览器/WebView 的 cookie 上下文。iOS 的受管文件通道将同源 Source 处理后 Blob 复制到应用管理的文件，校验字节数、取消和文件所有权后交付；文件资源仍等显示端释放 ACK。其它尚未实现的 Native 平台明确报 `unsupportedCapability`；工程回归不代表真实 Source 或 Native 图片显示已验收。

`platform.authenticate(context, returnTo: '/', pending: {...})`：Web 保存 sessionStorage 后顶层访问 `/api/auth/login?returnTo=...`；原生在应用内打开可见 InAppWebView，完成 Access/IdP 登录后验证 bootstrap，再重建隐藏宿主。`takePendingAuthentication()` 一次性恢复 `{returnTo, pending}`。Web 登录会离开当前页面；原生返回 `true` 才表示身份已确认。

本包的 `dart test` 覆盖并发打开合并、静态路径与身份前置条件、跨代结果隔离、图片描述校验、取消确认、迟到释放和章节幂等清理。测试使用受控传输夹具，不代表真实 Source 图片、浏览器渲染或移动真机验收。

`tool/protocol_crosswire.dart` 是跨语言 golden 的官方 Dart codec oracle：接收 NDJSON `{type,value}`，逐行输出标准 ProtoJSON，非法输入退出非零。根目录的协议测试将其与真实 Protobuf-ES codec 双向核对；这不代表 Source 在线行为通过。
