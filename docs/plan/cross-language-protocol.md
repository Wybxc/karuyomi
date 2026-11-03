# 跨语言协议统一

## 目标与状态

消除 TS schema 与 Dart wire DTO 手写重复，让 Worker、宿主与 Flutter 从同一份协议生成模型和标准 codec。**方案已确定，实施未开始。** 选定 Protobuf `.proto` + Buf + Protobuf-ES / Google Dart 插件；小型控制消息使用 ProtoJSON，图片/HTTP 大正文仍走独立二进制通道。决策比较与限制见[设计文档](../design/cross-language-protocol.md)。

当前 Zod + 手写 Dart 仍是实际实现，图片 ABI v2 仅是图片功能合同，不能作为本计划完成的证据。Java protobuf/TeaVM 适配不是第一批前置要求。

## 待办

1. 固定标准生成器与 runtime；接入 Buf format/lint/build/generate 和项目 TS 编排，明确生成 TS 的正规 ESM 编译步骤，禁止 ts-nocheck 或实验语法捷径。
2. 定义 envelope、session/error、Source 请求/结果 oneof、Page/image 控制与实际跨端 API/静态目录 DTO；opaque ID 使用 string，明确 presence、默认值、未知字段及 enum 行为。
3. 先用双端真实 codec 运行 golden 与非法输入测试，包括超过 JS 安全范围的 ID、缺失 oneof、错误类型、null/default、非整数、未知字段/枚举；随后替换产品调用边界，不长期维护两套 wire schema。
4. 保留并测试 generation、预算、路径绑定、取消与资源释放等业务规则；保持 MessagePort 和大正文传输独立，不能以 Struct/Any 或 Base64 逃避类型与流控要求。
5. 严格检查、生成无漂移、实际 Web interop 与 Native 小控制消息通过后更新验证记录，按当前原型协议同步更新 ABI 并及时提交推送。不加旧版兼容门禁。

## 验收

- 改一份 `.proto` 能稳定重建两端模型和 codec，CI 能发现未提交的生成变化；生成物无手改。
- 产品边界不再维护同一消息结构的 TS Zod 与手写 Dart 解析副本；业务与资源状态校验仍真实执行。
- 双端传输字段、presence、oneof 和错误解释一致；真实 Worker/WebView 控制链可用。
- 图片和 HTTP 流仍保持有界分块、背压、取消与所有权；没有新增大正文 JSON/Base64 通道。
