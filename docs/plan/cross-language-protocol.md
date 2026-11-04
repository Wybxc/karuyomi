# 跨语言协议统一

## 目标与状态

消除 TS schema 与 Dart wire DTO 手写重复，让 Worker、宿主与 Flutter 从同一份协议生成模型和标准 codec。**已实现，v3 Web、双端 Native 机制与原 xkcd Reader 分项通过，生产部署及剩余运行门待验收。** 选定 Protobuf `.proto` + Buf + Protobuf-ES / Google Dart 插件；小型控制消息使用 ProtoJSON，图片/HTTP 大正文仍走独立二进制通道。决策比较与限制见[设计文档](../design/cross-language-protocol.md)。

正式 Web/Native 控制入口统一为 `control(ControlRequest ProtoJSON) → ControlResponse ProtoJSON`；Source 与 Worker 使用生成 oneof，bootstrap/静态索引/清单和图片控制也从同一 IDL 解析。Java 保留 Gson DTO，仅将私有 memo 转成严格有界的 `memoJson` 字符串，避免跨 JS 数字精度损失；未引入 Java protobuf runtime。当前身份为 protocolVersion 2 / host ABI v3，原型不兼容旧材料。

## 已完成

- `.proto` 定义、Buf format/lint/build、精确锁定的 ES/Dart 生成器，生成 TS 经 `@karuyomi/protocol` 正常编译为 ESM。
- `pnpm protocol:setup` 准备独立锁定的 Dart generator；`pnpm generate:check` 在临时目录生成并比较完整文件集与字节，CI 同步检查。
- TS/Dart 正反 golden、标准二进制与 ProtoJSON 对照、oneof/presence/非法字段、业务预算、签名 ID 和 generation/build 绑定回归。
- 正式 Worker、Web 与 Native 小控制消息接入；Native 使用 JSON.stringify 文本再交官方 Dart codec，避免 WK NSNumber 的 double 表示改变整数输入。
- index 删除分页字段；Source 输出使用具体四类 payload；图片/HTTP 大正文继续独立有界二进制传输。Java memo 对象与 64 KiB UTF-8 限额通过 JVM oracle。

## 待验收

1. 固定 `6e08ec9` 的新指纹代表包已通过真实 Web Source 控制、首中末图片、重复释放与会话关闭，见 [v3 运行证据](../verification/protocol-v3-runtime.md)。继续验证实际取消和后续材料变更；不能复用旧 v2 或不同材料的证据。
2. iOS 模拟器正式 NativePlatformRuntime 已通过真实 Headless 握手和受控 Blob 文件交接，见 [Native 文件证据](../NATIVE-IMAGE-FILES.md)。固定 `a15c030` 的真实 Source 首中末文件、取消与容器重建也已分项通过；固定 `d76e8a4` 的双端 Native 图片机制、SQLite 真重启及 iOS 原 xkcd 正式 ReaderScreen/进度恢复也已通过分项，输入与测试驱动范围见[Native 记录](../verification/native-dependencies.md)；固定 `8eef7b4` 的 Android 原 xkcd Reader/force-stop 恢复及退出也已通过分项，仍须验收当前 Cache v3 材料、物理设备和生产 Access。编译、mock 和 Dart golden 不能替代这些门。
3. 新材料与静态快照、生产 Access 分项验收后再更新部署记录。固定 `022d828` v1 队列保持独立，尚不能部署为当前协议成果。

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
