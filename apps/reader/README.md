# Flutter 客户端

支持 Web / iOS / Android 的应用脚手架。当前只有响应式书架、浏览、设置空态及本次会话内的外观切换。

从仓库根目录执行 `pnpm flutter:setup`、`pnpm flutter:check`、`pnpm build`；详见[开发说明](../../README.md)。Flutter 版本固定在根目录 `.fvmrc`。

`reader_core` 与 `source_runtime` 是纯 Dart 包。`flutter_inappwebview` 固定为 6.1.5，供 P0-F 原生控制页探针使用；尚未创建 WebView adapter。Web 将直接使用 JS interop + Worker，不使用该插件的 iframe 实现。完整图片桥和 Access 会话必须通过原生验证后再启用真实源。

Android/iOS 工程由 Flutter 3.47.5 模板生成，应用 ID 为 `dev.karuyomi.karuyomi`。正式签名、部署 hostname 和生产环境在发布前配置；目前没有移动真机验收结果。
