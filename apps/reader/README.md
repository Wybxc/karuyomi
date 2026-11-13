# Flutter 客户端

支持 Web / iOS / Android。客户端从部署域的公开静态资源读取扩展索引、构建清单和 AOT 正文，通过受保护的 Worker API 读写书架、进度等业务数据。

从仓库根目录执行 `pnpm flutter:setup`、`pnpm flutter:check`、`pnpm build`；详见[开发说明](../../README.md)。Flutter 版本固定在根目录 `.fvmrc`。

当前 `cupertino_ui` 的返回箭头以文本字形绘制，Flutter 的图标裁剪不能发现它。Web 正式构建入口已使用 `--no-tree-shake-icons`；手动构建原生 release 时也须加入此官方选项，直至依赖修复并通过实际 release 字形验收。该选项不改变图片、运行时或扩展资源合同。

`reader_core` 与 `source_runtime` 是纯 Dart 包。Web 使用 JS interop + Worker；Native 使用固定的 `flutter_inappwebview` 6.1.5 管理 HTTPS 控制页，和可见的 Access 登录页共享 Cookie。Native 不使用 `file://` 页面，也不在客户端保存 GitHub 下载令牌。

构建 Native 前，先在仓库根目录执行 `pnpm --filter @karuyomi/runtime-host build`，生成并复制 `host.js`、`worker.js`、`manifest.json` 到忽略的 `assets/runtime/`。这三个文件由 Flutter 作为 app assets 打包；每次启动容器均核验 SHA256、长度、协议/ABI 与材料版本，再在部署域 `/runtime/host.html` 或规范化的 `/runtime/host` 主框架文档开始时注入。Worker 及通用 JS/WASM 由 app 内置。缺少或不匹配的内置材料会报错；Android WebView 缺少 `DOCUMENT_START_SCRIPT` 时拒绝启动。

从本目录启动设备客户端可使用 `flutter run --dart-define=APP_ORIGIN=https://部署域`。HTTPS 控制页、身份认证与 Source API 仍需联网；内置运行时不等于离线漫画源。Native 资源与 API 数字解码边界测试位于 `test/runtime/`。

Android/iOS 工程由 Flutter 3.47.5 模板生成，应用 ID 为 `dev.karuyomi.karuyomi`。iOS 26.4 模拟器的本地受信任 HTTPS 夹具已验证内置 Worker、Cookie、真实扩展初始化、AOT 篡改拒绝和重建恢复，运行时材料网络请求为零。它不代表物理设备、生产 Access 登录或图片通道已通过；正式签名与这些验收仍需完成。

Android 发行签名遵循 [Flutter 的签名配置约定](https://docs.flutter.dev/deployment/android#sign-the-app)。发行时在本目录的 `android/key.properties` 提供 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`；`storeFile` 的相对路径以 `android/` 为起点。配置文件已由 Git 忽略，密钥库也须保存在版本控制之外。没有配置时，release 产物为未签名包。安装或分发前，用 `apksigner verify --verbose --print-certs <apk>` 核对发行证书；实际验证见[发行签名记录](../../docs/verification/native-main-entry.md#android-发行签名配置)。
