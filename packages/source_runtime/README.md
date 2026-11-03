# SourceRuntime

纯 Dart 协议包；`TransportSourceRuntime` 将 `open/invoke/cancel/dispose` 映射到小型 JSON 控制通道，并检查 build、generation、request ID 与字符串 Long Source ID。结构化异常保留错误类别与 Java class；容器重建后丢弃迟到结果。图片资源通道尚未开放，`acquire` 明确报 `unsupportedCapability`。

Flutter 平台实现放在 `apps/reader/lib/runtime`。`createPlatformRuntime({origin})` 在 Web 通过 `dart:js_interop` 连接全局 `karuyomiRuntime`；原生要求 HTTPS 部署 origin，并使用 `HeadlessInAppWebView` 加载同源 `/runtime/host.html`。调用 `platform.runtime.open(BuildDescriptor(...))` 前，必须从 bootstrap 确认身份，并提供私有 manifest URL、build ID 与 bundle SHA-256。`ApiFetch` 使用同一个浏览器/WebView 的 cookie 上下文。

`platform.authenticate(context, returnTo: '/', pending: {...})`：Web 保存 sessionStorage 后顶层访问 `/api/auth/login?returnTo=...`；原生在应用内打开可见 InAppWebView，完成 Access/IdP 登录后验证 bootstrap，再重建隐藏宿主。`takePendingAuthentication()` 一次性恢复 `{returnTo, pending}`。Web 登录会离开当前页面；原生返回 `true` 才表示身份已确认。

本包的 `dart test` 验证并发打开合并、私有路径与身份前置条件、跨代结果隔离、Java 错误保留、图片门与重复销毁。原生进程重建和登录目前仅通过静态分析，仍需 iOS/Android 真机验证。
