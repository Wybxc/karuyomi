# 跨语言 IDL 与序列化决策

日期：2026-11-03。**双端生成与产品控制边界已实现；新 ABI 的真实 Web Source/图片与 iOS 模拟器 Source 文件链分项通过，完整交互、设备和生产 Access 门仍待完成。** 当前采用 protocolVersion 2 / host ABI v4；v4 的 host entry/HTTP owner 合同及 `storage_busy` 新错误须重新验收，历史 v2/v3 证据保留原身份。实施进度见[协议计划](../plan/cross-language-protocol.md)。

选择 **Protobuf `.proto` 作为唯一消息定义，Buf 管理生成与格式，Protobuf-ES 和 Google Dart 插件生成双端模型及 codec；小型控制消息先使用标准 ProtoJSON**。这个选择针对当前 Flutter、Worker、WebView 和 Node 工具边界，不以未经测量的序列化性能作为依据。

当前各实际边界、quicktype/OpenAPI/FlatBuffers/GraphQL 与平台通道的适用范围见[数据交换评估](data-exchange-boundaries.md)。Protobuf 主控不意味着所有文件、原生平台通道和二进制 ABI 都必须套用同一种方案。

2026-11-05，业务设计以多端同步为首要目标：Worker API + D1 是唯一业务权威，Flutter Web/iOS/Android 共用业务状态合同。现有运行时控制、bootstrap 和静态 DTO 已接入，不代表书架、进度、设置的读写与并发合同已实现；新增范围按[协议计划](../plan/cross-language-protocol.md)和[同步计划](../plan/p2-sync.md)优先推进。

## 比较

IDL 定义消息结构，encoding 定义字节表示，transport 管理投递和生命周期，三者分别选择。Protobuf 可以用 binary 或 ProtoJSON；换编码不会自动解决重复手写 DTO。Protobuf-ES 用同一份生成 schema 支持这两种编码。[官方序列化说明](https://protobufes.com/guides/serialization/)

| 方案                          | 对本项目的价值                                                                                 | 代价与判断                                                                                                                                                                                                                                                                   |
| ----------------------------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Protobuf + Buf                | TS 与 Dart 均有成熟生成器；枚举、显式字段存在性、oneof 和标准 JSON 映射覆盖当前控制消息        | **选用**。需要新增代码生成步骤；业务限额和生命周期仍需校验。[ES](https://protobufes.com/reference/generated-code/)、[Dart](https://protobuf.dev/reference/dart/dart-generated/)                                                                                              |
| JSON Schema + JSON + 模型生成 | 接近当前 JSON，擅长 pattern、长度、范围、required、oneOf；quicktype 支持从 schema 生成 TS/Dart | 次选。模型生成和运行时 validator 需要另外组合、核对双端支持的 schema 方言；不把生成类型当作全部 schema 校验。[JSON Schema](https://json-schema.org/overview/what-is-jsonschema)、[quicktype](https://quicktype.io/)                                                          |
| OpenAPI + JSON                | 有成熟 Dart/TS HTTP client 生成器，适合独立 HTTP API 的文档与 SDK                              | 当前核心是 Worker/JS interop/WebView 消息，HTTP client 生成不能直接覆盖这些边界；不另建一套竞争性的控制 DTO 来源。[dart-dio](https://openapi-generator.tech/docs/generators/dart-dio/)、[typescript-fetch](https://openapi-generator.tech/docs/generators/typescript-fetch/) |
| FlatBuffers                   | 官方支持 TS/Dart，直接访问二进制 buffer 适合特定大结构                                         | 当前传输的是小控制消息，大正文另走流；现有 Native 控制通道仍是 JSON，无法据此获得端到端零复制。TS/Dart 的 verifier、JSON 等功能也须按语言核对，不选。[功能矩阵](https://flatbuffers.dev/support/)                                                                            |
| Bebop                         | `.bop` 生成二进制 codec，TS runtime 轻，提供 struct/message/union                              | 已发布线的 Dart 不支持 union，JSON-Over-Bebop 只支持 TS；无法直接生成当前所需的双端控制合同，不选。[union](https://docs.bebop.sh/reference/union/)、[JSON](https://docs.bebop.sh/reference/json-over-bebop/)                                                                 |
| MessagePack / CBOR            | 成熟、紧凑的通用二进制表示                                                                     | 单独换编码仍需额外定义统一模型、生成器与校验，不能解决当前主要问题。[MessagePack](https://msgpack.org/)、[CBOR RFC](https://www.rfc-editor.org/rfc/rfc8949.html)                                                                                                             |
| Cap’n Proto                   | 有 IDL、直接 buffer 访问与 RPC 路线                                                            | 官方列出的其它语言实现成熟度各异，未提供与本项目 TS/Dart 组合相当完整的参考工具链；收益不足以承担额外集成，不选。[官方语言说明](https://capnproto.org/otherlang.html)                                                                                                        |

## Protobuf、FlatBuffers 与 Bebop 的专项比较

本项目的首要要求是同一份定义能生成 Worker TypeScript 与 Flutter Dart 的消息和解析器，并表达不同操作的请求/结果。大图片与 HTTP 正文已经独立传输，因此控制消息 codec 的微基准速度不是当前瓶颈证据。项目不要求兼容旧协议；以下判断也不依赖向后兼容能力。

| 维度           | Protobuf                                                          | FlatBuffers                                                                                      | Bebop（已发布 v3 线）                                                           |
| -------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| 数据访问方式   | 解码为消息对象；同一 schema 支持 binary 与标准 ProtoJSON          | 通过 accessor 直接读取 buffer，可按需访问；也有 object API                                       | 生成专用二进制 encoder/decoder，struct 固定布局，message 使用带编号的可缺失字段 |
| TS / Dart      | Protobuf-ES 与 Google Dart 插件；均有正式模型和 codec             | 两端基础生成和 object API 均支持，但功能并不齐全                                                 | 两端均列为支持语言，但 Dart 的功能落后于 TS                                     |
| 请求/结果变体  | oneof：TS 可判别联合；Dart 有 case 枚举及 getter，仍需检查 notSet | schema 支持 union，但 Dart 生成 getter 为 dynamic，TS object API 的 tag/value 分离；需要额外收窄 | 官方明确 Dart 尚不支持 union；需要绕开 union 或另写适配层                       |
| 字段存在性     | 显式 optional / message presence；默认值与 null 按标准处理        | TS 支持 optional scalar，官方矩阵列 Dart 不支持；可通过包装结构表达但增加模型负担                | struct 字段齐全，message 字段可缺失；不能因此补齐 Dart 的 union 能力            |
| JSON 控制桥    | 两端有标准 ProtoJSON codec，适配现有 WebView 小消息               | 官方矩阵列 TS/Dart 无运行时 JSON parser；flatc 的 JSON 工具不能直接充当端上 codec                | JSON-Over-Bebop 官方只支持 TS，没有对应 Dart codec                              |
| 二进制结构验证 | 生成 codec 解析结构，业务合法性另行校验                           | 官方矩阵列 TS/Dart 无 Buffer verifier；accessor 不等于先验证整个 buffer                          | 解码不代替业务约束；不能用 TS 的 JSON 校验承诺 Dart 同样具备                    |
| Java / TeaVM   | Java 工具链成熟，TeaVM 的 runtime 可达性与 AOT 增量体积仍须实测   | 有 Java 支持，TeaVM 同样需要独立验证                                                             | 官方已发布线支持列表未列 Java，不能假设有可用 TeaVM 路径                        |
| 对本项目的判断 | **选用**：首先消除双端手写合同；编码可按边界选择                  | 大型只读结构与局部访问更有价值，当前小控制消息不足以抵消额外适配                                 | TS 更有吸引力；当前 Dart 功能缺口会把维护成本转回项目                           |

依据：[Protobuf-ES codec](https://protobufes.com/guides/serialization/)、[Dart 生成 API](https://protobuf.dev/reference/dart/dart-generated/)、[FlatBuffers 访问模型](https://flatbuffers.dev/)、[语言功能矩阵](https://flatbuffers.dev/support/)、[Bebop 支持语言](https://docs.bebop.sh/)、[union 限制](https://docs.bebop.sh/reference/union/)、[JSON 限制](https://docs.bebop.sh/reference/json-over-bebop/)。没有 Buffer verifier 不等于所有 accessor 都不做边界检查；也不能把有 accessor 当作已经完整验证业务消息。

FlatBuffers 的 union 能正确表达并跨语言传输，限制在生成 API 的类型表达：当前 [Dart 生成 fixture](https://github.com/google/flatbuffers/blob/f58d5768f1fd0df9f71aa6ae5f63645e2637c31f/tests/monster_test_my_game.example_generated.dart#L1060-L1068) 使用 tag 枚举与 dynamic getter；[TS object API](https://github.com/google/flatbuffers/blob/f58d5768f1fd0df9f71aa6ae5f63645e2637c31f/tests/ts/my-game/example/monster.ts#L1361-L1370) 把 tag 和联合值分别存储。不能把它们描述成完整的静态可判别联合。Protobuf 的 Dart getter 也需要 case 检查，选型并不意味着所有语言获得相同的静态穷尽保证。

**速度与体积没有通用赢家。** Protobuf varint 对小整数有利，也提供 fixed 类型；Bebop 整数按固定宽度编码，struct 与 message 的开销不同；FlatBuffers 的 offset、vtable 和对齐换取直接访问。具体大小取决于字段分布，运行时与生成代码体积取决于实际 bundle。不能将官网的性能宣传直接当作本项目 TS/Dart、WebView 或 TeaVM 的实测结果。[Protobuf encoding](https://protobuf.dev/programming-guides/encoding/)、[Bebop wire format](https://docs.bebop.sh/reference/wire-format/)、[FlatBuffers internals](https://flatbuffers.dev/internals/)

Bebop 的版本边界也需明确：当前发布仓库的 latest 为 [v3.2.3](https://github.com/6over3/bebop/releases/tag/v3.2.3)；另一个 [bebop-next / Bebop 2026](https://github.com/6over3/bebop-next) 是使用新 schema/wire 的 staging 重写，其状态表将其它语言生成器（含 TS）列为未开始。不能把旧版 Dart 支持与新版路线合并成已具备的完整能力。

结论仍为 **`.proto` + Buf + Protobuf-ES / Dart**，小控制消息先用 ProtoJSON；不引入 gRPC。选择 ProtoJSON 是当前小消息边界的工程取舍，不是旧版兼容要求，也不宣称获得 Protobuf binary 的体积收益。只有真实控制消息测量表明有必要，才切换相应边界的 binary codec；图片与 HTTP 正文继续使用有界二进制通道。

## 选定的工程边界

- `.proto` 放在独立协议目录，作为可交换消息的唯一结构来源；固定 Buf、ES generator、Dart generator 与两端 runtime 版本。生成物不手改，也不写自制 generator。
- TypeScript 采用 Protobuf-ES。生成 TS 后正常编译成 ESM 与声明，再供 Node 工具和浏览器使用；不依赖实验性的 erasable syntax，也不启用 ts-nocheck。默认 TS enum 不能直接交给 Node 24 的 strip-types 执行。[生成选项](https://protobufes.com/reference/plugin-options/)
- Dart 采用 Google `protoc_plugin` / `protobuf`。控制边界使用 `toProto3Json` / `mergeFromProto3Json`，TS 使用 `toJson` / `fromJson`；不能混用 Dart 按字段编号编码的旧 `writeToJson`。[Dart ProtoJSON](https://pub.dev/documentation/protobuf/latest/protobuf/GeneratedMessage/toProto3Json.html)、[旧 JSON 区别](https://pub.dev/documentation/protobuf/latest/protobuf/GeneratedMessage/writeToJson.html)
- 第一批覆盖 envelope、hello/session/error、Source 请求与结果、Page/image 控制消息，以及 Flutter 实际消费的 API/静态目录 DTO。已有 `operation + args: unknown`、`result: unknown` 要改为有明确类型的消息与 oneof；不能用 Struct/Any 原样搬运弱类型。
- Worker 使用生成 codec 处理可序列化控制信息。MessagePort / transferable ArrayBuffer 保持独立附件；图片与 HTTP 正文保留现有有界二进制流、ACK、取消和资源所有权，不进入 ProtoJSON 的 bytes 字段，不编码成整图 Base64。
- 不引入 gRPC、Connect 服务框架或第二个 HTTP transport；当前选择只统一数据合同。以后只有测量证明必要，才在已支持二进制的边界使用同一 schema 的 binary codec。
- Java 生成模型不放入第一批强制范围。其 protobuf runtime 在 TeaVM 的可达代码和每包 AOT 体积需要单独实测；第一批先在 TS 宿主校验 Java 结果，再转换为生成消息。不能把 JVM 库可用当作 TeaVM 已通过。

## 同步优先的业务合同

书架、分类、进度、书签和非敏感设置的 HTTP 请求/响应继续由同一 Protobuf + Buf 体系定义，TS/Dart 使用生成 codec；HTTP 方法、鉴权和状态码不能成为第二套业务模型来源。当前阶段先实现有界的当前状态查询与确认写入，前台重新读取后收敛；增量日志/cursor、DO 通知、持久本地 outbox 或离线合并只有在真实需求与测量成立后再规划。

业务消息须表达 mutationId、服务端 revision、预期 revision 的条件更新、阅读 epoch、确认后的完整状态或受影响字段，以及标准错误。明确 revision/epoch 的数值范围与精确跨端表示；不依赖设备时间或隐式 JS Number 转换决定顺序。幂等重试保留原 mutationId，服务端提交但响应丢失时不得再执行一次 reset；不同消息不能因为复用幂等 ID 而被误认成同一操作。调用方身份来自通过验证的 Access 上下文，正文中的客户端标识只用于协议与去重。

CAS 冲突、旧 epoch、非法业务输入、鉴权失败与暂时故障必须分别返回标准结果；客户端按结果重新读取、提示冲突或有限重试，不能把全部错误都重放为新写入。生成模型只负责结构解析，D1 条件 SQL/唯一约束/事务边界仍须落实并验收。原始正文、条目/字段长度、分页和写入批次均有明确预算；状态查询在分页期间不能因并发变更悄悄漏项。业务缓存在客户端可丢弃，收到服务端确认才标记已保存；未确认草稿限当前会话，不承诺关闭后恢复。

## 类型和验证规则

1. Source ID、build/resource/session ID 是不透明标识；Source 的十进制 Long ID 继续建模为 string，避免 JS 安全整数限制。真正需要计算的 int64 才使用对应生成类型，并通过 ProtoJSON 的十进制字符串映射跨端。[ProtoJSON 数字映射](https://protobuf.dev/programming-guides/json/)
2. 需要区分缺失与默认值的 scalar 使用显式 presence；必须有 payload 的消息检查 oneof 不能为 notSet。TS 的 oneof 是可判别联合，Dart 是 `whichX()` 枚举及 getter，不能把后者描述成 sealed union 的静态穷尽保证。[Dart oneof](https://protobuf.dev/reference/dart/dart-generated/#oneof)
3. 标准 ProtoJSON 有默认值省略、null 与枚举映射规则。两端统一使用标准 codec，明确拒绝错误类型、未知字段/枚举，交叉测试这些边界。标准允许某些重复字段/oneof 取后值，不能把 codec 当作“恰好一个请求分支”的校验；非法操作组合须在边界显式检查。Dart 的 enum 处理也不能假定与 TS 一样保留所有未知值。不保留旧手写 wire 格式的兼容分支。[标准 JSON 规则](https://protobuf.dev/programming-guides/json/)
4. 非空 ID、路径/hash 绑定、数组唯一性、字节/像素/队列预算、requestId/generation、超时及状态转移属于业务规则，仍在正式边界验证。生成 codec 不会验证这些要求。Protovalidate 当前官方实现未包含 Dart，不能声称注解已经自动覆盖双端所有约束，也不为此自行实现 CEL/通用验证器。[Protovalidate 支持语言](https://protovalidate.com/)
5. 在双方 codec 前先限制原始消息大小；生成类型和解析成功不代替运行时状态验证。旧 generation 与迟到资源仍按现有资源所有权规则丢弃、清理。

## 工具与验收

生成和格式入口继续使用项目自有 TypeScript 编排，领域工具不能反向依赖 scripts。Buf 负责 `.proto` 格式、lint、schema build 与标准插件调用；CI 校验生成结果无漂移，分别执行严格 TS/Dart 检查和跨语言 golden round-trip/非法输入测试。[Buf 生成](https://buf.build/docs/generate/)

原型阶段允许破坏性变化，直接同步更新当前协议、生成代码、测试和 ABI；不添加旧格式回退，也不把 `buf breaking` 设为必须维护兼容的门禁。协议定义、codec、调用方和真实 Web/Native 控制链均通过后，才将实施状态改为完成。
