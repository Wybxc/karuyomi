# SourceRuntime

纯 Dart 协议包；`TransportSourceRuntime` 将 Source 调用和图片生命周期映射到小型控制 DTO，并检查 build、generation、request ID 与字符串 Long Source ID。结构化异常保留错误类别与 Java class；容器重建后丢弃迟到结果，迟到图片会请求释放。图片正文不进入 Dart 控制消息。

`ChapterPageProvider` 绑定 Source、Java Page 会话和运行代次，将 reader_core 的逻辑页键映射到宿主保存的 opaque Page 句柄。`acquireImage` 返回尺寸、MIME、字节数和受管 Web Blob URL；`cancelImage` 等待停止生产确认，`releaseImage` 和 `closePageSession` 等待清理确认。章节关闭会取消未完成请求、释放迟到图片和存活资源，再关闭 Page 会话；普通 Source `cancel` 与图片取消分开。

Flutter 平台实现放在 `apps/reader/lib/runtime`。Web 通过 `dart:js_interop` 连接全局 `karuyomiRuntime`；原生使用 HTTPS 部署 origin 和同源受管 WebView。打开前从 bootstrap 确认身份，提供当前 Static Assets 清单路径、build ID 和 bundle SHA-256。`ApiFetch` 使用同一个浏览器/WebView 的 cookie 上下文。Native 受管文件图片通道仍未实现，图片获取明确报 `unsupportedCapability`，不会把 Blob URL 或 Source 原图 URL交给原生图片视图。

`platform.authenticate(context, returnTo: '/', pending: {...})`：Web 保存 sessionStorage 后顶层访问 `/api/auth/login?returnTo=...`；原生在应用内打开可见 InAppWebView，完成 Access/IdP 登录后验证 bootstrap，再重建隐藏宿主。`takePendingAuthentication()` 一次性恢复 `{returnTo, pending}`。Web 登录会离开当前页面；原生返回 `true` 才表示身份已确认。

本包的 `dart test` 覆盖并发打开合并、静态路径与身份前置条件、跨代结果隔离、图片描述校验、取消确认、迟到释放和章节幂等清理。测试使用受控传输夹具，不代表真实 Source 图片、浏览器渲染或移动真机验收。
