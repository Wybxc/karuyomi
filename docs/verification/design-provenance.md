# 设计文档来源

五份设计文档最初于 2026-11-03 从[原计划对话](codex://threads/01a19624-4303-7c91-b3fb-3bc110136ca9)导入，当时仅将文档间链接改为相对路径。原聊天和当时的外部研究路径保留为来源记录。

用户现已取消设计目录冻结：这些文档可以正常修订并格式化，当前文件不再声称与导入副本逐字节相同。现行架构为 Flutter + TeaVM，扩展以 Static Assets 为所有客户端的最终权威来源，每扩展只发布最新 build，客户端或 Service Worker 按 index/catalog 管更新与缓存；不再要求扩展 Release 发布，已有 Release 仅历史存储，其余通用资源使用 Web Static Assets / Native 内置；旧 R2/Worker 扩展正文代理提案已被覆盖。实际交付和验收状态以[计划目录](../plan/README.md)与[验证记录](../VERIFICATION.md)为准，交付方案不等于完整链路已验证；此前内置浏览器 Release 直下/Range 的 CORS 门未通过，用户随后选定全客户端 Static Assets 权威源；最新发布与完整加载仍待实现验收，具体限制见主设计。

下列 SHA-256 **仅标识初次导入时的原始资料和复制快照**，不用于校验当前文件，也不构成禁止修改的要求。后续设计修订通过 Git 历史追踪；引用历史快照时应同时说明其日期与当时状态。

| 文档                                                                                           | 初始原文 SHA-256                                                   | 初次复制快照 SHA-256                                               |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| [cross-platform-framework-evaluation.md](../design/cross-platform-framework-evaluation.md)     | `a88756bcf1f3a26b3b17a0d43acb1caca5572b6341438bceade4a7ca01d89cb5` | `8c4484a59a583d5db43335e3db495ff27a64f5f9efab27e64cbcfbab922cd647` |
| [flutter-teavm-integration.md](../design/flutter-teavm-integration.md)                         | `c55206d1f651a5efad36577f6a3ea9381359787f8f979fea08d84f954b4952e8` | `c55206d1f651a5efad36577f6a3ea9381359787f8f979fea08d84f954b4952e8` |
| [mihon-web-design.md](../design/mihon-web-design.md)                                           | `e20398e44ccd405dc5645fdbf51b1b6b428963da679052f36ed7c2a7864ff252` | `f9c8130ebe42e48466b59b098beba2ad53ea94e2a15e068f33ed790568cdb04d` |
| [runtime-evaluation-history-2026-11-02.md](../design/runtime-evaluation-history-2026-11-02.md) | `def38a5cddff15b5da0406a4c83aafeadae30054cd0dfa484dc0336ee59e9bd0` | `e85ade406b0c278515ec5289f1517bb783a7af756ab7aaa82216e7ac5cd70451` |
| [technology-stack-and-reader.md](../design/technology-stack-and-reader.md)                     | `f8c7d5dfba200faa9ed72fb188d82577185d875215facab8e6aabc2ac6542091` | `9f6926e2a679962869276e0e4e023c6ea20dd1b6b63a72027a02cc591427379a` |

各文档的职责：

- [主设计](../design/mihon-web-design.md)与[Flutter 接入设计](../design/flutter-teavm-integration.md)：现行架构和待验收约束。
- [技术栈与阅读器](../design/technology-stack-and-reader.md)：通用阅读规范加历史 React/RN 工具链背景，历史目录和命令不作为当前 Flutter 工程要求。
- [跨端框架评估](../design/cross-platform-framework-evaluation.md)与[运行时评估历史](../design/runtime-evaluation-history-2026-11-02.md)：保留选择依据与实测边界，不重新开启选型，不把原研究数据当作当前产品通过记录。
