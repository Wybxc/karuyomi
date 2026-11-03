# Karuyomi 实施计划总览

当前计划统一维护在 [docs/plan/ 目录与索引](plan/README.md)。各阶段的状态、待办与验收以对应分项计划为准；实际验证环境和证据见 [VERIFICATION](VERIFICATION.md)。P0 尚未通过，不将分项测试、独立机制探针或 AOT 发布等同于完整阅读能力。

## 已确定的方向与范围

- Flutter / Dart 负责 UI 和独立阅读核心；iOS、Android 原生优先，桌面使用 Flutter Web。
- TeaVM 0.16.0 JavaScript backend / release9 是运行基线。Web 通过 JS interop 连接 Worker；原生通过系统 WebView 控制同版 Worker。不重选框架或执行引擎。
- 单 hostname、单 Cloudflare Worker：公开 Flutter shell 和 `/runtime/`，全部后端、私有 AOT 与个人数据放在 Access 保护的 `/api`、`/api/*`，Worker 再校验 JWT。
- 共享桥/WASM 在 Web 静态交付、Native 随应用打包；扩展 AOT 独立私有交付。Java/Maven、原 JAR 与 seed 只用于构建。
- 首版保留浏览、书架、在线阅读、基本进度、同步和源管理；暂缓模块及各阶段完整范围见[计划索引](plan/README.md)。原型阶段不维护旧协议、旧材料或旧发布格式兼容。

## 冻结设计依据

来源：[设计 Cloudflare 漫画阅读应用](codex://threads/01a19624-4303-7c91-b3fb-3bc110136ca9)。2026-11-03 将该聊天采用的设计迁入本仓库，保留以下历史副本：

1. [主设计](design/mihon-web-design.md)：范围、部署、运行时、数据、P0–P4 和验收。
2. [Flutter + TeaVM 接入](design/flutter-teavm-integration.md)：采用路线的接入与原生资源边界。
3. [技术栈与阅读器](design/technology-stack-and-reader.md)：保留通用要求；React/RN 选型已被 Flutter 替代。
4. [跨端框架评估](design/cross-platform-framework-evaluation.md)：历史决策记录。
5. [运行时历史评估](design/runtime-evaluation-history-2026-11-02.md)：历史研究证据。

副本只调整过五份文档之间的绝对链接；本机路径和历史状态保留原样，摘要见[设计来源](verification/design-provenance.md)。这些副本不随实现改写；其中“未创建工程”等叙述对应原聊天当时状态，当前进展只在[计划目录](plan/README.md)与验证记录维护。
