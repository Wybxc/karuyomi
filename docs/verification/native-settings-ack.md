# Native 全局设置已提交后丢确认

2026-11-08，产品提交 `78e6c47` 的正式 Flutter 全局设置入口在 iOS 和 Android 模拟器分别通过。各端使用独立官方 Wrangler HTTPS harness、新 D1、`acceptance-owner` 测试身份、空书架与零扩展索引；两端不共享数据，也没有启动 Source。夹具在正式 API 提交首个 `setGlobal`、核对持久回执后截断 HTTP 200 正文。

| 平台    | 设备和信任                                                                                                                          | 正式 UI 结果                             | 两条审计共同的 mutation UUID           |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------- |
| iOS     | iPhone 17 / iOS 27.2；专用模拟器信任本轮回环 CA                                                                                     | 同一 PID `12700`；1/1 通过，驱动约 11 秒 | `b73becd7-662d-4e3d-9f9f-ae0e7238385e` |
| Android | Pixel 7 AVD / API 36 ARM64，WebView `133.0.6943.137`；debug APK 的精确主机信任与 Dart 测试进程分别追加本轮 CA，同端口 `adb reverse` | 同一 PID `3978`；1/1 通过，驱动约 11 秒  | `56b683e5-40f1-4ed3-a8ac-f62f9fcdcd71` |

每轮从跟随系统主题、账户及全局设置 revision `0/0` 开始。用户在正式设置面板选择深色并保存，首次丢确认时仍保留旧确认主题、原草稿和重试入口；此时驱动通过同进程的独立 HTTPS 连接读到服务端已是深色 `1/1`，未向产品仓储发布确认。点「重新读取设置」后同一面板应用深色，原操作仍待确认；点「重试原设置操作」后才清除待确认，版本保持 `1/1`。各端均输出同 PID 的 `SETTINGS_ACK_LOSS_COMMITTED_UNCONFIRMED`、`SETTINGS_ACK_LOSS_RELOADED_PENDING`、`SETTINGS_ACK_LOSS_RETRY_CONFIRMED`。

另一个主机进程分别在测试前后用正常 TLS 只读请求 `/api/settings` 和 `/api/library`。完整快照只变化了全局主题及账户/全局设置 revision；书架仍为空，其它设置保持不变。各端停服输出的 `ACCEPTANCE_SETTINGS_ACK_AUDIT` 恰好两条：`sequence=1/2`、`drop_ack=1/0`，两条均是 `expected_revision=0`，确认的账户和全局设置 revision 均为 `1/1`，同一轮的 UUID、原请求正文、正式确认与持久回执三种 SHA-256 均相同。D1 各只提交一次，重试复用原请求。

复验使用[正式驱动与参数](../../apps/reader/integration_test/README.md#全局设置已提交后丢确认)。每端分别为 `127.0.0.1` 配置本轮 HTTPS 证书，从空 D1 启动一次：

```sh
pnpm acceptance:build:native
NODE_EXTRA_CA_CERTS=/absolute/path/rootCA.pem \
WRANGLER_HTTPS_KEY_PATH=/absolute/path/key.pem \
WRANGLER_HTTPS_CERT_PATH=/absolute/path/cert.pem \
ACCEPTANCE_FIXTURE=settings-ack-loss pnpm acceptance:serve
```

iOS 通过专用模拟器的设备信任，不传测试 CA 字段；Android 通过 debug APK 中仅用于 `127.0.0.1` 的 WebView CA 配置和阶段 JSON 的 `SETTINGS_TEST_CA_BASE64` 追加同一 CA，保留系统根、证书/主机名校验并禁止明文。Android 核对 APK 中的信任配置及 Native 内置材料与输入一致。取基准快照后执行 `SETTINGS_PHASE=ack-loss`，再次独立 GET，然后按 Enter 停服核对审计。两轮专用设备和验收端口均已清理。

原始日志和快照保存在 `/private/tmp/karuyomi-native-settings-ack.k8pjsK/`（iOS）及 `/private/tmp/karuyomi-settings-ack-android-78e6c47.2jpONI/`（Android）。本轮只验证全局主题保存已提交后响应丢失及同一会话精确重试；独立 GET 不计作第二个 Native 客户端或新进程读回。本分项不覆盖实际断网、漫画覆盖、同时写、关闭后草稿恢复、生产 Access 或真机。
