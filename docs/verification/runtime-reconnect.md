# 重连与迟到控制响应

2026-11-04，正式 Dart 回归先在旧码复现两类问题：Catalog 的旧 bootstrap/index 在容器失效后仍将状态改回 ready；Transport 的旧 API 错误或旧图片清理错误，在新 open 成功后清空新会话或向新 generation 发事件。旧失败日志留在 ignored 目录，不以格式检查代替语义验证。

## 当前实现

- Catalog 显式重连立即撤销当前身份、选择和清单，并先提交绑定原身份的进度。失败草稿仍可重试，不改绑新身份。只有曾尝试加载 runtime 的重连才调用平台的可重开 rebuild；纯目录连接不销毁容器。
- Worker、WebView 与原生图片资源的清理由 PlatformRuntime 拥有；Catalog 通过显式依赖调用 rebuild，不调用永久 dispose。主动重建中的旧容器 runtimeLost 不自我取消当前重连，重建失败仍报告并允许下次重试。
- bootstrap、index、manifest 和 open 每次 await 后均核对 epoch，失效的结果不发布。传输层在请求前捕获 epoch；旧成功或异常不能向新会话发事件、清空新 session 或发布旧 API 结果。
- 有效的迟到图片仍交还原 acquireImage 所有者执行释放；旧 generation 清理失败保留原错误，不能破坏新 slot。dispose ACK 和正常控制交互保持有效，不自动重发任何副作用请求。

## 已运行的验证

旧码 Catalog 4 项、Transport 3 项回归明确失败。修后 source_runtime 完整 29 项及 Dart 分析通过；Reader 六个受影响测试文件 46 项与 Flutter 分析通过，包含身份更换前的旧进度保存、保存失败草稿、迟到 manifest、无已加载 runtime 时不重建、重建失败恢复及迟到图片所有权。正式入口为 `packages/source_runtime/test/transport_test.dart`、`apps/reader/test/browse/catalog_controller_test.dart` 与 `apps/reader/test/reader/reading_progress_controller_test.dart`。

该结果是正式组件/传输与本地 SQLite 回归；真实浏览器/Native 主入口的身份切换、版本更新和生产 Access 过期恢复仍须另验，不能用模拟 transport 替代。分项产品验收继续按[P0](../plan/p0-runtime-and-reading.md)推进。
