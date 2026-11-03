# Karuyomi 实施计划

来源：[设计 Cloudflare 漫画阅读应用](codex://threads/01a19624-4303-7c91-b3fb-3bc110136ca9)。2026-11-03 将该聊天最终采用的设计迁入本仓库。

## 已确定的方向

- Flutter / Dart 负责 UI 与阅读核心；iOS、Android 原生优先，桌面使用 Flutter Web。
- TeaVM 0.16.0 JavaScript backend / release9 是冻结基线。Web 通过 JS interop 直连 Web Worker；原生通过系统 WebView 控制页连接同版 Worker。
- Dart `SourceRuntime`、版本化协议和公共 JS 宿主共享；图片使用可获取、取消、释放的独立资源通道。先验证 iOS，不以整图 Base64 或 JSON 代替图片桥。
- 单 hostname、单 Cloudflare Worker。公开 Flutter shell 与 `/runtime/`；全部后端、私有产物和个人数据位于 Access 保护的 `/api`、`/api/*`，Worker 再校验 JWT。
- 后端沿用 pnpm、TypeScript、Hono、Zod、jose、D1/Drizzle、私有 R2、SQLite Durable Objects。Pub 管 Dart 依赖；Java/Maven 工具链随冻结宿主导入。
- 首版只保留书架、浏览、在线阅读、基本进度、同步和源管理。更新、离线下载、历史统计、追踪、本地漫画、备份、应用内账号与隐私模块不预建。

## 工程起点

本次交付为脚手架：应用空态、平台工程、纯 Dart 包、共享版本常量、JS 容器握手、API 鉴权边界、Cloudflare bindings、数据库迁移和本地/CI 构建入口。

运行容器的 `sourceReady` 明确为 `false`。未导入 TeaVM 研究 ZIP、扩展 JAR、私有 AOT 包、原型测试服务或诊断响应。尚未接入业务存储、真实源、原生图片桥和部署环境。脚手架通过不等于 P0 通过。

## 后续顺序与验收

| 阶段 | 工作                                          | 验收重点                                                                                |
| ---- | --------------------------------------------- | --------------------------------------------------------------------------------------- |
| P0-F | Web interop、原生 WebView、统一协议与图片通道 | F1 Web DTO；F2 Access 与容器恢复；F3 优先 iOS 字节正确、有界内存、取消释放；F4 真实阅读 |
| P0-R | 独立 Dart 阅读核心与 Flutter 阅读器           | 分页/长条、单双页、RTL、缩放、逻辑位置、旋转恢复、图片窗口与真机交互                    |
| P0-A | 从 release9 建立只读基线的工作副本            | 完整 DTO、显式引用、按包 AOT、哈希/ABI、私有交付、执行槽、文件与 HTTP Cache             |
| P0-B | 二进制网络桥                                  | 同版固定输入对照、无整段 JSON/Base64、流控、取消、缓存与异常语义                        |
| P0-C | 汇合完整在线阅读                              | 3–5 原版源、请求头/图片处理、完整章与下一章、真实 Workers/Access、移动首图与合计峰值    |
| P1   | 可日用核心                                    | 书架/详情/分类/阅读设置/进度/书签、重启恢复、网络错误与移动交互                         |
| P2   | 基本多设备同步                                | 幂等增量、revision、reset epoch、断网并发不倒退                                         |
| P3   | 扩展管理与迁移                                | 手动安装/升级/回滚、筛选/preferences、迁移预览与保留原条目                              |
| P4   | 覆盖与优化                                    | 按源/版本/平台/出口记录兼容性、性能和可访问性                                           |

P0-F / P0-R / P0-A 可以独立推进，在 P0-C 合流；不重新比选 UI 框架或执行引擎。

## 完整设计副本

1. [主设计](design/mihon-web-design.md)：范围、部署、运行时、API/Access、数据与发布门槛。
2. [Flutter + TeaVM 接入](design/flutter-teavm-integration.md)：当前采用路线的实施依据。
3. [技术栈与阅读器](design/technology-stack-and-reader.md)：保留通用要求；其中 React/RN 选型已被 Flutter 替代。
4. [跨端框架评估](design/cross-platform-framework-evaluation.md)：历史决策记录。
5. [运行时历史评估](design/runtime-evaluation-history-2026-11-02.md)：历史研究证据。

副本仅将五份文档之间的绝对链接改为仓库内相对链接；研究材料的本机路径和历史状态原样保留。原文与副本 SHA-256 记录在 [provenance.json](design/provenance.json)。当前工程状态以本页和仓库 README 为准；历史“未创建工程”描述对应原聊天当时状态。
