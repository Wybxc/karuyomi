# 跨语言数据交换边界与方案评估

2026-11-04 按当前实现盘点。本文是选型评估，除已接入的 Protobuf 控制合同外，quicktype、OpenAPI、Pigeon 等建议尚未实施；不以生成类型、库的宣传或微基准替代真实边界和 TeaVM/AOT 验证。当前原型不考虑旧版兼容。

2026-11-05，多端同步成为首要设计目标。Worker API + D1 的收藏与阅读进度查询/变更已接入 `business.proto`，使用已有 Protobuf + Buf 双端生成模型；分类、书签和非敏感设置按同一路径逐项扩展。先完成在线权威读写及实际跨端验收，再评估其它生成器与可选 HTTP 文档工具，实施合同见[P2](../plan/p2-sync.md)。

## 先区分工具层次

- quicktype 是模型、codec 和部分运行时检查的生成器；稳定契约应来自人工审阅并维护的 JSON Schema，不能只从几个样例推断。各语言 renderer/选项能力不同。[官方流程](https://github.com/glideapps/quicktype#generating-code-from-json-schema)
- Protobuf 和 FlatBuffers 同时提供 schema 与编码体系；前者支持 binary 和标准 ProtoJSON，后者主要面向直接读取二进制 buffer。两者都不是资源调度器。[ProtoJSON](https://protobuf.dev/programming-guides/json/)、[FlatBuffers](https://flatbuffers.dev/)
- OpenAPI 描述 HTTP 的路径、参数、正文、响应和安全方案，本身不限定用某种 JSON serializer；可生成 HTTP 客户端。[规范](https://spec.openapis.org/oas/v3.2.1.html)、[Dart Dio generator](https://openapi-generator.tech/docs/generators/dart-dio/)
- GraphQL 定义 schema、操作及执行语义，适合客户端选择字段的业务查询；客户端代码生成来自另选的工具链。[操作校验](https://graphql.org/learn/validation/)、[响应](https://graphql.org/learn/response/)、[Ferry](https://ferrygraphql.com/docs/)

## 当前边界与推荐

| 实际边界                                                               | 当前实现与数据                                                                                                                      | 推荐及判断                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flutter Dart ↔ Web TS host / Native WebView TS host                    | JS interop / callAsyncJavaScript，标准 ProtoJSON；request/result oneof、错误、会话、取消、资源描述；Native 结果先转 JSON 文本再解析 | **继续 Protobuf + Buf**，同一合同覆盖两端。小控制消息保持 ProtoJSON，是否切 binary 由实际测量决定；OpenAPI/GraphQL 不对应这里的 transport                                                                                                       |
| TS host ↔ TS Source Worker                                             | postMessage 的 WorkerCommand/WorkerResponse、图片控制描述与独立 MessagePort                                                         | 两端虽同为 TS，也继续共享 **Protobuf**。没有必要为同一链路再引第二套 schema                                                                                                                                                                     |
| Source Java ↔ TeaVM JS 宿主                                            | JSExport/JSBody、HostDto/Gson JSON，TS 用生成合同解析；HTTP/图片/graphics 还包含 typed-array ABI                                    | **消息结构继续以现有 Protobuf 为目标合同，Java 生成模型尚待验证**。Java protobuf/javalite 与 quicktype 候选都须同 DTO 的 TeaVM 编译、输出、启动和包大小对照，不能直接宣称某个更轻；当前 Gson 树适配仍是实际实现                                 |
| Worker HTTP API ↔ Flutter                                              | /api/bootstrap、fetchApi 信封；收藏与进度权威查询/变更已接入 business.proto，分类/书签/设置待扩展                                   | **业务 DTO 继续 Protobuf + Buf**：查询、mutation ID、revision/CAS、epoch 和错误使用同一生成合同。OpenAPI 可补路径/鉴权/状态码与 SDK，但须复用已有模型，不阻塞基础同步或形成竞争 schema                                                          |
| 扩展静态索引/BuildManifest ↔ Dart/TS                                   | 静态 JSON，已经从 .proto 生成两端模型                                                                                               | **继续 Protobuf/ProtoJSON**；这是静态数据文件，不需要 GraphQL 服务或 OpenAPI 客户端生成                                                                                                                                                         |
| TS 构建 → Native Dart 的内置 runtime manifest，以及 Dart → TS 注入配置 | NativeRuntimeAssets 手写解析 JSON；文件 path/hash/size、ABI、materialVersion，注入 workerSource/imageFiles                          | **JSON Schema + quicktype 是贴合文件格式的候选**，用于消除当前 shape 的重复；schema 要作为权威输入，生成器和检查选项固定。若只为这一份很小的 manifest 引入工具成本过大，也可将其加入现有 .proto。无论选哪条，都只维护一个结构来源，不能两份手写 |
| Dart ↔ 自有 Swift 文件桥                                               | MethodChannel：bind/acquire/cancel/release/clear，小字典、文件 URI 和 ACK                                                           | **五者之外优先 Pigeon**。它直接生成 Dart/Swift 平台通道，比在平台通道外再套网络 IDL 更贴切；图片正文仍不进入 MethodChannel                                                                                                                      |
| 图片/HTTP 正文跨 Worker、WebView、Dart/Native                          | ArrayBuffer/Uint8List、64 KiB 分块/ACK、WKDownload 文件；Source 正文不透明                                                          | **五者都不替代正文通道**。小描述可用 Protobuf；正文保持独立有界流/受管文件，不转整段 JSON/Base64，也不为“零复制”包装 FlatBuffer                                                                                                                 |
| 候选 TS ↔ C/WASM                                                       | Emscripten scalar/pointer/HEAP ABI，严格函数形状和内存边界检查                                                                      | **保留类型化 C ABI**。当前没有需要跨端随机访问的大型结构化 buffer，给函数调用包一层通用 serializer 没有明确收益。候选 codec 不在默认 Reader 链路                                                                                                |

运行代码入口：`apps/reader/lib/runtime/platform_runtime_web.dart`、`platform_runtime_native.dart`、`native_image_files.dart`、`native_runtime_assets.dart`；`packages/source_runtime/lib/src/transport_runtime.dart`；`packages/runtime-host/src/worker-runtime.ts`、`teavm-driver.ts`；`runtime/teavm/java/src/main/java/prototype/HostDto.java`；`apps/api/src/app.ts`；`protocol/karuyomi/v1/control.proto`。

当前 Android MainActivity 仅继承 FlutterActivity，没有自有 Dart↔Kotlin DTO 通道。Android 图片使用锁定 flutter_inappwebview 的 WebMessagePort/ArrayBuffer；不为统一选型重写成熟插件内部通道。Pigeon 的正式平台通道可以生成 Swift/Kotlin/Java 等宿主代码，仍需同版本生成两端。[官方说明](https://pub.dev/packages/pigeon)

## 五种方案在本项目中的边界

**quicktype** 最适合已有自然 JSON 文件/外部格式的多语言模型生成，Native manifest 是实际缺口；它不是 HTTP 接口定义，也不自动提供请求路由、generation 和资源生命周期。不能说 quicktype 只有类型而没有校验，实际 codec/约束能力取决于目标语言、输入 schema 和选项。其 Java 默认走 Jackson，`--just-types` 只生成模型；官方没有 Gson renderer。仅生成 POJO 不等于现有 Gson 树 API 已能在 TeaVM 中反射序列化这些模型。[Java 选项](https://github.com/glideapps/quicktype/blob/master/packages/quicktype-core/src/language/Java/language.ts)、[Java renderer](https://github.com/glideapps/quicktype/blob/master/packages/quicktype-core/src/language/Java/JavaRenderer.ts)、[Gson 说明](https://google.github.io/gson/Troubleshooting.html)

**Protobuf** 是当前控制消息的首选，既有生成/codec/golden/非法输入链已经接入。采用它并不等于引入 gRPC，也不等于产品已经全面采用 binary；Java runtime 在 TeaVM 中的成本与可达性仍须单独验证。枚举、oneof/presence 的跨语言 API 不完全相同，业务与状态约束仍要校验。[生成模型](https://protobuf.dev/programming-guides/proto3/)、[ES runtime](https://github.com/bufbuild/protobuf-es)

**OpenAPI** 是 HTTP 层的首选；不用于 Worker postMessage、JSBody 或 MethodChannel。现有 Protobuf DTO 和后续 HTTP 描述不能成为两份竞争性的权威结构。schema 的复用/生成和目标 generator 的实际支持须先验证，不能假定把任意 .proto 一键转换就完全保真。

**FlatBuffers** 官方支持 Dart、TypeScript、Java 和 Swift；不能以“不支持 Dart”为由排除。它擅长通过 accessor 直接读取大型结构化二进制数据；当前主控消息小，图片已经压缩且独立传输，未发现需要它的正式场景。官方功能矩阵显示各语言 verifier/JSON 能力不一致，固定版本时仍须检查生成代码和运行时，不能把 accessor 当作完整验证或端到端零复制。[Dart](https://flatbuffers.dev/languages/dart/)、[TS](https://flatbuffers.dev/languages/typescript/)、[功能矩阵](https://flatbuffers.dev/support/)

**GraphQL** 适合未来独立、多实体、多客户端且需要字段裁剪的书架/目录查询 API；本项目目前没有该服务，Source 查询仍由原插件负责，宿主主控是命令/取消/租约，新增执行器与查询缓存没有明确收益。GraphQL 规范不附送各语言 SDK；Flutter 可用 Ferry 或 graphql_flutter 等成熟方案。图片仍应使用独立二进制交付，GraphQL 也不代替同步冲突或取消协议。[Ferry](https://ferrygraphql.com/docs/)、[graphql_flutter](https://github.com/zino-hofmann/graphql-flutter)、[二进制限制](https://graphql.org/learn/file-uploads/)

Source `memo_json` 是扩展私有、不透明且有界的 JSON，不从样本推断固定业务模型。第三方上游 HTTP 格式不由本项目掌控，不能为了选择 IDL 修改官方 Source。收藏与阅读进度通过 `business.proto` 的生成模型跨 Dart/Worker 交换；客户端业务 SQLite 已移除。仅同一 Dart 应用使用的临时页面恢复状态不算需要跨语言生成的自有协议。

## 后续顺序

1. 完成已接入的收藏/进度合同的三端一致性验收，按分类、书签、非敏感设置逐项扩展 Worker API + D1 的 Protobuf 查询/幂等变更合同，每项包含 TS/Dart 实际跨端读写；保持现行主控和独立二进制正文。
2. 为自有 iOS 文件桥评估并接入 Pigeon；保留现有 HTTPS、绑定、期限、清理 ACK 和资源配额检查。
3. Native runtime manifest 选择单一 schema/codegen 入口：优先对比 JSON Schema + quicktype 与新增 .proto 的维护成本，不保留双份手写 shape。
4. Java 边界以真实 Manga/PageList/图片描述为固定输入，对比生成路径的 TeaVM 编译兼容、序列化正确性、AOT 增量体积与启动/解析成本，再决定引入哪一种 runtime。
5. HTTP 业务端点增长时补 OpenAPI；没有明确大型结构化 buffer/查询图需求前，不引入 FlatBuffers 或 GraphQL。

实施状态归入[协议计划](../plan/cross-language-protocol.md)，当前控制协议决策仍见[跨语言协议设计](cross-language-protocol.md)。
