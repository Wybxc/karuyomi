# Flutter 客户端

支持 Web / iOS / Android。客户端通过部署域的受保护 API 读取构建清单和漫画源元数据；阅读视图与图片调度已有开发夹具测试，图片桥未通过验收时章节保持不可读。

从仓库根目录执行 `pnpm flutter:setup`、`pnpm flutter:check`、`pnpm build`；详见[开发说明](../../README.md)。Flutter 版本固定在根目录 `.fvmrc`。

`reader_core` 与 `source_runtime` 是纯 Dart 包。Web 使用 JS interop + Worker；Native 使用固定的 `flutter_inappwebview` 6.1.5 管理 HTTPS 控制页，和可见的 Access 登录页共享 Cookie。Native 不使用 `file://` 页面，也不在客户端保存 GitHub 下载令牌。

构建 Native 前，先在仓库根目录执行 `pnpm --filter @karuyomi/runtime-host build`，生成并复制 `host.js`、`worker.js`、`manifest.json` 到忽略的 `assets/runtime/`。这三个文件由 Flutter 作为 app assets 打包；每次启动容器均核验 SHA256、长度、协议/ABI 与材料版本，再在部署域 `/runtime/host.html` 或规范化的 `/runtime/host` 主框架文档开始时注入。Worker 及通用 JS/WASM 由 app 内置，扩展 AOT bundle 继续经受保护 API 下载。缺少或不匹配的内置材料明确报错，旧版依赖 URL 查询参数的桥要求更新扩展构建；Android WebView 缺少 `DOCUMENT_START_SCRIPT` 时明确拒绝启动。

从本目录启动设备客户端可使用 `flutter run --dart-define=APP_ORIGIN=https://部署域`。HTTPS 控制页、身份认证与 Source API 仍需联网；内置运行时不等于离线漫画源。Native 资源与 API 数字解码边界测试位于 `test/runtime/`。

Android/iOS 工程由 Flutter 3.47.5 模板生成，应用 ID 为 `dev.karuyomi.karuyomi`。iOS 26.4 模拟器的本地受信任 HTTPS 夹具已验证内置 Worker、Cookie、真实扩展初始化、AOT 篡改拒绝和重建恢复，运行时材料网络请求为零。它不代表物理设备、生产 Access 登录或图片通道已通过；正式签名与这些验收仍需完成。
