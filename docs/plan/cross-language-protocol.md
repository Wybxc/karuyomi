# 跨语言协议统一

## 目标与状态

消除 TS schema 与 Dart wire DTO 手写重复，让 Worker、宿主与 Flutter 从同一份协议生成模型和标准 codec。**已实现，v4 三包已部署并通过匿名交付验收；Web/iOS 正式入口与服务端状态分项通过，Android 与生产正向待验收。** 当前 Web↔iOS 证据见[记录](../verification/native-server-state.md)，历史双端 Native 机制、原 xkcd Reader 分项保留各自实际范围。选定 Protobuf `.proto` + Buf + Protobuf-ES / Google Dart 插件；小型控制消息使用 ProtoJSON，图片/HTTP 大正文仍走独立二进制通道。决策比较与限制见[设计文档](../design/cross-language-protocol.md)。

正式 Web/Native 控制入口统一为 `control(ControlRequest ProtoJSON) → ControlResponse ProtoJSON`；Source 与 Worker 使用生成 oneof，bootstrap/静态索引/清单和图片控制也从同一 IDL 解析。Java 保留 Gson DTO，仅将私有 memo 转成严格有界的 `memoJson` 字符串，避免跨 JS 数字精度损失；未引入 Java protobuf runtime。当前身份为 protocolVersion 2 / host ABI v4，原型不兼容旧材料。v4 增加 host entry/HTTP owner 约束，IDL 新增 `storage_busy` 明确表示 namespace 执行槽占用；历史 v3 运行证据不自动覆盖 v4。

以上运行时与现有 API 控制合同之外，**收藏与阅读进度业务合同已接入**：`business.proto` 生成双端模型，正式 Worker/Dart 通过 ProtoJSON 交换带 revision、epoch 和 mutation ID 的状态；分类、书签与设置尚待扩展。多端同步现为首要设计目标，书架、进度和设置的 Worker API + D1 合同是当前优先待办，与 [P2](p2-sync.md)共同推进；不等待外围 UI 全部完成后再定义跨端状态。

## 当前优先主线：业务状态合同

1. 收藏与阅读进度的查询、写入、确认和标准错误已在 `business.proto` 接入；继续扩展分类、书签和非敏感设置。使用 Protobuf + Buf、TS/Dart 官方生成模型和 ProtoJSON，不新增竞争性的手写 DTO 或通用 Struct/Any。
2. 已实现 `mutationId`、服务端 `revision`、CAS、阅读 `epoch`、数值范围与精确映射；后续功能复用同一约束。请求跟踪 ID、幂等 ID、资源 generation 各自负责不同约束；身份由鉴权上下文确定，不能信任正文指定的 subject。
3. 已接入未登录/拒绝、格式与业务约束错误、revision/epoch 冲突、暂时不可用等标准结果和重试语义。成功结果返回服务端确认状态和 revision；同 mutationId 重试返回相同结果、不重复执行，后续功能继续覆盖这些回归。
4. 当前状态有界分页、前台重新读取、分页 revision 与消息预算已接入，继续验证实际客户端的完整性和恢复。增量日志/cursor、DO 通知及持久 outbox 不作为初版前置。
5. TS↔Dart golden、非法输入与真实 D1/API 回归已通过；Web↔iOS 实际读取、确认和非默认页恢复通过。继续验收 Android、生产 Access 与实际并发/前台重取；客户端只保留会话内草稿和可丢弃缓存，服务端确认才表示已保存。

## 已完成

- `.proto` 定义、Buf format/lint/build、精确锁定的 ES/Dart 生成器，生成 TS 经 `@karuyomi/protocol` 正常编译为 ESM。
- `pnpm protocol:setup` 准备独立锁定的 Dart generator；`pnpm generate:check` 在临时目录生成并比较完整文件集与字节，CI 同步检查。
- TS/Dart 正反 golden、标准二进制与 ProtoJSON 对照、oneof/presence/非法字段、业务预算、签名 ID 和 generation/build 绑定回归。
- 正式 Worker、Web 与 Native 小控制消息接入；Native 使用 JSON.stringify 文本再交官方 Dart codec，避免 WK NSNumber 的 double 表示改变整数输入。
- index 删除分页字段；Source 输出使用具体四类 payload；图片/HTTP 大正文继续独立有界二进制传输。Java memo 对象与 64 KiB UTF-8 限额通过 JVM oracle。

## 待验收

1. 固定 `6e08ec9` 的代表包通过真实 Web Source 控制、首中末图片、重复释放与会话关闭，仅为历史 [v3 运行证据](../verification/protocol-v3-runtime.md)。当前 v4 三包已本地重编并通过限定 Web Source/图片、xkcd 阅读及跨标签写入分项，见[v4 运行证据](../verification/v4-source-runtime.md)；实际 TeaVM owner/enqueue/取消另见[回调证据](../verification/teavm-enqueue.md)。继续验收生产控制链与剩余取消门，不能复用旧 v2/v3 或不同材料的证据。
2. iOS 模拟器正式 NativePlatformRuntime 已通过真实 Headless 握手和受控 Blob 文件交接，见 [Native 文件证据](../NATIVE-IMAGE-FILES.md)。固定 `a15c030` 的真实 Source 首中末文件、取消与容器重建也已分项通过；固定 `d76e8a4` 的双端 Native 图片机制、SQLite 真重启及 iOS 原 xkcd 正式 ReaderScreen/进度恢复也已通过分项，输入与测试驱动范围见[Native 记录](../verification/native-dependencies.md)；固定 `8eef7b4` 的 Android 原 xkcd Reader/force-stop 恢复及退出也已通过分项。以上均按原材料保留。当前 v4 材料的 iOS 正式主入口与 Web 业务同步已分项通过，见[新记录](../verification/native-server-state.md)；Android、物理设备和生产 Access 仍待验收。编译、mock 和 Dart golden 不能替代这些门。
3. 固定 `13494a0` 的当前材料与 v4 三包静态快照已部署，匿名 26 路径和远端仅三包 verified 的准确 host 政策已核对，见[生产部署记录](../verification/v4-production.md)；后续客户端/API 与 D1 业务表部署见[同步生产记录](../verification/server-state-production.md)。部署 revision 与 baseline 状态以[工程计划](engineering-and-release.md)为准；部署不代表已通过真实 Access 控制链。当前 Access 会话已失效，用户答复稍后登录，生产正向仍未验收。固定 `022d828` v1 及 `b4f72f7` v3 checkpoint 仅保留历史冻结证据，不得直接覆盖当前生产；baseline 未完成，CI 继续 `disabled_manually`。

## 后续边界评估

当前主控合同继续沿用 Protobuf；本节是新增评估和待办，不将选型建议写成已实施能力。完整范围与官方依据见[数据交换边界评估](../design/data-exchange-boundaries.md)。

- 自有 iOS 文件 MethodChannel 优先使用 Pigeon 生成 Dart/Swift API；保持正文走 WKDownload 文件、原绑定与清理 ACK。不重写第三方 Android WebMessagePort 插件。
- Native runtime manifest 与注入配置仍有手写 shape：对比 JSON Schema + quicktype 和加入现有 .proto 的维护成本，只保留一个权威结构来源。已在 .proto 的扩展索引/BuildManifest 不另建 schema 副本。
- Java HostDto/Gson 尚未生成：以真实 DTO 做 TeaVM/AOT 小范围对照，核对 protobuf/javalite 与 quicktype 的编译、正确性、包大小和启动/解析成本。quicktype 默认 Java 使用 Jackson，只有 POJO 不等于 Gson/TeaVM codec 已可用。
- HTTP 接口增长时以 OpenAPI 描述端点、鉴权、状态码和 SDK，复用既有 DTO；当前不为少量 bootstrap 请求重写运行时主控。
- 现无证明需要 FlatBuffers 的大型结构化随机访问数据，也无 GraphQL 查询图服务；保持二进制正文与 C/WASM ABI，按真实需求再评估。

## 验收

- 改一份 `.proto` 能稳定重建两端模型和 codec，CI 能发现未提交的生成变化；生成物无手改。
- 产品边界不再维护同一消息结构的 TS Zod 与手写 Dart 解析副本；业务与资源状态校验仍真实执行。
- 双端传输字段、presence、oneof 和错误解释一致；真实 Worker/WebView 控制链可用。
- 图片和 HTTP 流仍保持有界分块、背压、取消与所有权；没有新增大正文 JSON/Base64 通道。
- 新增业务合同由同一 `.proto` 生成双端模型，正式 API 对幂等、revision/CAS、epoch 和预算作运行时校验；两个独立客户端共享服务端确认状态。运行时控制协议已有证据不能替代这一门。
