# P0 功能收尾

2026-11-05，按“先完成功能，再进行测试”调整推进顺序：暂停追加浏览器、性能和多源采样，先完成静态审查确认的四项功能缺口，再集中回归。实现清单见 [P0 计划](../plan/p0-runtime-and-reading.md#当前功能收尾先实现后集中验收)。

## 已补齐的行为

- Access 失效终止 Source 执行与新网络，保留已交付图片及其预算，旧代次新调用保留原鉴权错误，正常 release/close 继续可用。Dart 在 await 返回后也检查暂停状态，丢弃迟到成功并释放迟到图片。
- Reader 暂停图片调度与邻章准备，手动登录后等待旧 view 释放 ACK，再核对身份/服务、重开当前章并恢复原逻辑锚、章序与布局。身份变化退出旧阅读；Web 全页登录前保存当前与退休草稿，失败保留页面和重试提示。恢复与切章、退出之间有明确所有者检查。
- manager 为四维存储 namespace 持有跨标签页独占 Web Lock；冲突通过生成协议的 `storage_busy` 提示，结束或启动失败后释放，不引入版本广播与兼容层。
- 原 Source 的 `enqueue` 在调度前绑定执行 owner，主结果交付前有界排空回调和响应清理。每个 Java entry 使用独立 token，旧请求不能归入下一次调用；未受控结束时回收 Worker，不重发 POST。Android 首次绑定清理专属目录中的旧运行文件，失败可显式重试，活跃 store 互不删除。

## 已执行的工程验证

使用仓库固定的 Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4，macOS 的完整格式工具与现有锁定 Java 工具链。

- `pnpm check` 通过，包含生成一致性、完整 TS 类型/依赖检查、TS↔Dart 黄金往返、增量构建与分发、产物校验、受控真实 workerd HTTP 桥等回归。`pnpm format` 与完整 macOS `pnpm format:check` 通过。
- `pnpm test`：22 个文件、345 项通过。包含暂停资源预算、真实 Web Locks 冲突/释放、迟到 API 响应隔离、每 entry token、旧 open/finish 和 fatal 回收回归。
- `pnpm teavm:check` 通过，新增 enqueue JVM oracle 40 项检查覆盖有界排空、嵌套回调、响应清理、POST 不重发、跨 RPC 创建后首次执行，以及旧绑定失败后新 owner 仍可使用。TS 与 JVM 分项不代替实际 TeaVM AOT 在线运行。
- `pnpm flutter:check` 通过：reader_core 21 项、source_runtime 42 项、Flutter App 141 项，三处分析、Drift 生成一致性及 Dart 格式检查通过。覆盖 scheduler 暂停、Source/图片的迟到结果清理、Reader 同身份/异身份、原锚/布局、退出与切章竞争，以及占用提示；Android 目录与既有释放回归四项包含在 App 全套内。
- `pnpm build` 通过：正式 Flutter Web release、Web/Native 宿主资源、Static Assets 装配和 API Worker dry-run。此次本地构建索引含 **0 个扩展**，只证明打包入口，不证明 v4 Source 已运行或发布。

## 尚未覆盖的门槛

当前 host ABI 为 `karuyomi-source-host-v4`，protocolVersion 2、HTTP bridgeVersion 2 不变。Java 调用约定已改变，必须按新指纹重建扩展 AOT 和配套材料；旧 v3 输入、checkpoint 与证据保留原身份，不能混装或推广为 v4 通过。此次没有启动全量发布器或部署。

受控 JVM、TS 和 Flutter 回归分别证明自身边界，不代表真实生产 Access 失效/回跳、v4 官方 Source 在线阅读、Native 主入口、真机或性能验收。P0 总状态仍为进行中；历史三源限定阅读证据见[图片边界记录](ui-image-boundary.md)，不以功能代码或工程检查替代总验收。
