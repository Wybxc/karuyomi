# 公共运行宿主

`host.html` 是同源 HTTPS 原生控制壳，创建 `worker.js`，向 Web adapter 暴露 `window.karuyomiRuntime.ready` 与 `dispose()`。握手包含协议版本、host ABI、release9 基线、generation、能力与 `sourceReady: false`。页面关闭终止 Worker。

本包仅建立引导与协议边界。Flutter Web 后续直接用 JS interop 连接 Worker；原生在 `flutter_inappwebview` 控制页中转小型 RPC。尚未实现原生 adapter、TeaVM 加载、Source 调用或图片资源桥。私有包清单/AOT 产物只能通过 Access 保护的 `/api` 获取，不能复制到本包 `public` 或部署静态目录。
