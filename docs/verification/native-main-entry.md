# Native 正式主入口准备与阻断

2026-11-04，对固定 `be5c3ed6d254c6ebd21048f801e49c0f60b5d3c6` 的 Native 成品和本地 HTTPS 服务做独立预验。**正式 App UI 未运行，验收未通过**；本记录不替代既有受控 ReaderScreen 或 Source Cache 分项，也不代表生产 Access。

2026-11-05，当前 v4 正式入口的双端构建与包内材料核对另见[新记录](v4-native-main.md)。它未运行 UI，也未复用本记录的旧证书或成品；下文保留 be5 当时的输入与限制。

## 固定输入与已验证范围

构建入口是正式 `lib/main.dart`，AppID 为 `dev.karuyomi.karuyomi.nativemainbe5`，部署 origin 固定为 `https://localhost:9461`。未注入 runtime 或客户端身份。62 份 tracked Dart 的 Git blob、磁盘内容和输入摘要逐项一致；Runner.app 中的 manifest、host、worker 字节匹配共享材料 `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`。

服务使用隔离 D1、正常 TLS、本地测试 issuer 与真实产品 Worker 的 RS256 验签。九项 HTTP 预验通过，覆盖匿名 bootstrap 401、剥离客户端 Access assertion、可见登录跳转、Secure/HttpOnly Cookie 后的受信身份、受限回跳、mutation Origin/请求头校验、过期 401、非本人 403、显式失效和重新登录 B，以及独立于 API 认证的公开静态索引/原版 gzip。未发出 Source 网络请求。

本地 CA 的 DER 与已有模拟器 TrustStore 精确匹配；当轮有效期截至 `2026-11-04T04:17:53Z`。恢复时应重新核验有效期，不能复用过期证书或关闭 TLS 验证。

## UI 阻断与恢复入口

CUA 分别通过 Simulator 名称、完整应用路径和 bundle ID 连接，均返回应用不可用；可用 surface 未列出 Simulator。Xcode 的工具入口也未能完成连接。因此未安装、启动或操作 App，报告明确保留 `nativeUi=not_run`、`passed=false`。后续在可控制的 Simulator 或真机上，使用同一正式入口完成可见登录、选源、详情、真实图片阅读、退出/后台恢复和身份切换后，再记录产品通过。

可复用的成品、服务、输入摘要和启动记录位于 main 的 ignored `.local/native-main-be5/`，本轮证据在 `ui-run-20261103T2347/`。在 main 运行 `pnpm exec tsc -p .local/native-main-be5/tsconfig.json` 检查服务，再按输入记录运行 `node .local/native-main-be5/service.ts`，另开终端运行 `node .local/native-main-be5/preflight.ts`。正常 HTTP 预验只能证明服务边界，不能补作 App UI 证据；证书失效时先按准备步骤重建。

| 证据                 | SHA-256                                                            |
| -------------------- | ------------------------------------------------------------------ |
| `summary.json`       | `203f7a1f17b728bbe0baea7541f3c5fcacb0a8237e90caa58dcc2c113182135c` |
| `preflight.json`     | `e6d2904833b1fe8f4175192507ab85204753acad8a8cb36d4533679889c19708` |
| `service-input.json` | `7d7647bd59d5492fb6b4cc728eb0ac257d4a1305f6227d099beaada8610dec20` |

本轮服务、esbuild/workerd 子进程、单个 iOS 模拟器和工具尝试启动的 Xcode 均已正常停止；正式 AOT 队列未受影响。详细日志和临时工程不入源码库。
