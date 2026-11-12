# Karuyomi 实施计划总览

当前计划统一维护在 [docs/plan/ 目录与索引](plan/README.md)。各阶段的状态、待办与验收以对应分项计划为准；实际验证环境和证据见 [VERIFICATION](VERIFICATION.md)。P0 尚未通过，不将分项测试、独立机制探针或 AOT 发布等同于完整阅读能力。

## 已确定的方向与范围

- **多端同步是首要设计目标。** 同一部署、同一 Access 身份在 Web、iOS、Android 共享书架、分类、进度、书签和非敏感设置；Worker API + D1 是唯一业务权威。客户端只维护当前会话状态、未确认草稿及可丢弃缓存，保存以服务端确认结果为准。先完成跨端在线闭环，再扩展完整书架和阅读设置；同步计划沿用 [P2](plan/p2-sync.md) 文件名，但已提升为当前主线，不再等待 P1 全部完成。
- Flutter / Dart 负责 UI 和独立阅读核心；iOS、Android 原生优先，桌面使用 Flutter Web。
- Web / iOS / Android [全端统一 Cupertino UI](plan/cupertino-ui.md)，采用官方 `cupertino_ui` 并集中迁移全部界面；Mihon 保留信息架构与业务流程参考。当前已完成规划，尚未实施。
- TeaVM 0.16.0 JavaScript backend / release9 是运行基线。Web 通过 JS interop 连接 Worker；原生通过系统 WebView 控制同版 Worker。不重选框架或执行引擎。
- 单 hostname、单 Cloudflare Worker：公开 Flutter shell 和 `/runtime/`，后端与个人数据放在 Access 保护的 `/api`、`/api/*`，Worker 再校验 JWT。
- Static Assets 是所有客户端的扩展分发权威源，每包只部署最新可用构建，由客户端或 Service Worker 管理更新与缓存。扩展不再发布到 GitHub Release，Worker/R2 不代理正文。共享桥/WASM 在 Web 作为 Static Assets、Native 随应用打包；Java/Maven、原 JAR 与 seed 只用于构建。
- [能力提示与有界跨源搜索](plan/cross-source-search.md)复用已确认安装和最多两个独立槽；Source 结果逐组返回，搜索与活动阅读互斥，取消/关闭确认后才交还主线。功能已接线，独立服务与 UI 回归、完整工程和构建通过，实际平台验收继续推进。
- 首版保留浏览、书架、在线阅读、基本进度、同步和源管理；暂缓模块及各阶段完整范围见[计划索引](plan/README.md)。原型阶段不维护旧协议、旧材料或旧发布格式兼容。
- 初版 Web 交付后，[Riverpod + generator + flutter_hooks 状态管理重构](plan/post-prototype-flutter-state.md)已通过工程与 Web 验收，并启用 riverpod_lint；[Flutter 3.50 / Dart 3.14 更新](plan/flutter-3.50.md)首批已部署，通过完整 CI、真实生产读图、跨发布保存及新文档续读。Wasm 候选已编译、性能对照待测，默认继续 JavaScript；原生现场验证仍停止。

收藏、进度与分类已接入 Worker API + D1、双端生成协议与幂等确认路径，本地业务 SQLite 已移除；工程和实际跨平台验收分别推进，历史本地恢复证据不能作为多端同步完成的证据。初版通过幂等写入、服务端 revision/冲突语义及前台重新读取收敛，不要求持久 outbox、离线冲突合并、增量日志或实时通知先行。P0 的真实阅读、生产 Access 和设备验收继续推进，不能因同步优先而跳过。

## 设计依据

来源：[设计 Cloudflare 漫画阅读应用](codex://threads/01a19624-4303-7c91-b3fb-3bc110136ca9)。2026-11-03 将该聊天采用的设计迁入本仓库；以下文档现已解除冻结，随决策持续维护：

1. [主设计](design/mihon-web-design.md)：范围、部署、运行时、数据、P0–P4 和验收。
2. [Flutter + TeaVM 接入](design/flutter-teavm-integration.md)：采用路线的接入与原生资源边界。
3. [技术栈与阅读器](design/technology-stack-and-reader.md)：保留通用要求；React/RN 选型已被 Flutter 替代。
4. [跨端框架评估](design/cross-platform-framework-evaluation.md)：历史决策记录。
5. [运行时历史评估](design/runtime-evaluation-history-2026-11-02.md)：历史研究证据。

初次导入记录见[设计来源](verification/design-provenance.md)，其摘要只证明当时的导入状态。设计文档已解除冻结，用户新决策直接更新相应设计；历史评估保留其当时背景。实施进展统一在[计划目录](plan/README.md)与验证记录维护。扩展改用最新版静态快照，保留依赖指纹做有界 CI 增量，首次全量仍在本地完成。
