# 实施计划目录

这里维护当前可执行计划；[总览](../PLAN.md)只保留架构与范围。各主题的已完成、待办和验收只在对应计划维护，测试命令与实际环境证据统一引用 [VERIFICATION](../VERIFICATION.md)，操作契约引用主题文档，避免复制实时测试数、发布数量和日志。

**首要设计目标是多端同步。** [P2](p2-sync.md) 提升为当前主线，与 [P1](p1-library-and-progress.md) 的数据模型、API 和客户端读写一起推进；阶段编号保留，不代表同步必须等完整本地书架之后才开始。Worker API + D1 为唯一业务权威，先打通同身份跨 Web/iOS/Android 的在线保存与恢复，再扩展外围功能。

2026-11-05：P0 已补齐本轮确认的四项功能缺口并通过集中工程回归；v4 三源 Web 元数据/图片、xkcd 正式阅读、跨标签写入门及实际 TeaVM enqueue 分项已通过。v4 三包初次部署与三包网络政策见[记录](../verification/v4-production.md)；当前客户端/API `466acdd` 已部署，扩展快照不变，匿名检查通过，见[同步生产部署](../verification/server-state-production.md)；Access 会话已失效，用户稍后登录，生产正向与真机仍待验收，完整 P0 未通过。收藏与进度已接入业务协议和 D1 权威 API，已移除本地业务数据库；真实 Web 独立会话及测试身份下 Web↔iOS 正式入口的双向非默认页续读已通过，见[跨端证据](../verification/native-server-state.md)。Android 配对、生产正向及分类/书签/设置继续按[P1](p1-library-and-progress.md)和[P2](p2-sync.md)推进。原型阶段直接维护当前协议和材料，不建设旧版本兼容层。

## 优先级与状态

| 优先级                  | 计划                                                          | 当前状态与依赖                                                                                                                                           |
| ----------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 当前主线 / 首要设计目标 | [P2 多设备同步](p2-sync.md)                                   | 收藏与进度的 Worker API + D1 和幂等读写已接入；真实 Web 独立会话及测试身份 Web↔iOS 双向续读已过；继续 Android/生产验收，再扩分类/书签/设置               |
| 并行基础验收            | [P0 运行时与真实阅读](p0-runtime-and-reading.md)              | 四项功能已补齐；v4 Web 及 iOS 正式入口 xkcd 阅读/同步分项已过；当前 Android 主入口、生产 Access 与真机待验收                                             |
| 并行工程                | [工程、AOT 与发布](engineering-and-release.md)                | v4 三包已部署，匿名静态交付与网络政策核对通过；baseline 未完成，CI 仍 disabled_manually；v1/v3 checkpoint 仅保留历史冻结证据                             |
| 与同步共同交付          | [P1 书架与进度](p1-library-and-progress.md)                   | 数据模型先按跨端权威状态设计；已切换收藏/进度读写入口；补跨端验收、分类/设置及完整日用流程                                                               |
| 基础运行与书架具备后    | [P3 扩展管理与源迁移](p3-extensions-and-migration.md)         | AOT 工程流水线已有实现；用户安装/设置/迁移流程待实现                                                                                                     |
| 持续推进                | [P4 Source 覆盖与性能](p4-source-coverage-and-performance.md) | 少量编译/初始化及网络证据；完整源覆盖和移动性能未验收                                                                                                    |
| 已实现待完整运行验收    | [跨语言协议方案](cross-language-protocol.md)                  | Protobuf + Buf 正式双端控制已接入；v4 Web/iOS 正式入口与业务协议分项通过；当前 Android 与生产正向仍待验收                                                |
| P0 存储子计划           | [运行时文件与 HTTP Cache](runtime-storage.md)                 | 有界组合存储、xkcd Web/Native Cache 与 Web A→B→A 后 304 正文复用通过；版本更新、更多 Source 与生产取消待验收                                             |
| P0 文字布局子计划       | [普通文本与 TextInterceptor](text-layout.md)                  | 普通文本、xkcd 两页/可见文字、原 Source 重复处理及编码取消分项通过；空闲 GC 与测试压力分开记录，长期/Native 生命周期待验收                               |
| P0 图片解码子计划       | [阅读器图片解码与长图评估](reader-image-decoding.md)          | 默认 UI 直接解码，候选 codec 退出默认打包；xkcd 阅读/下载、Arknights/CuuTruyen 完整章/限定续读三源 Web 分项通过；多次 baseline、长图/EXIF/LOD 与真机待验 |
| 已验收                  | [执行器与公共工具收敛](tooling-processes.md)                  | tools/lib 已删除并直接使用成熟库；日志、凭据隔离、进程树、状态锁和完整工程检查通过                                                                       |

P0-F（Web/原生接入）、P0-R（阅读器）与 P0-A（宿主）可并行；P0-B 先完成真实二进制链路，再在 P0-C 汇合成完整在线阅读。工程发布可以并行推进，不能用编译或发布成功替代 P0、Source 在线语义或移动验收。

## 维护约定

- 状态使用“未开始、进行中、已实现待验收、已验收、讨论待定”，只有对应验收证据成立才标为已验收。
- 实现变化更新所属计划；影响优先级或依赖时再更新本索引。详细证据保留实际平台、浏览器和执行环境，历史 Safari 验证不能改称 Codex 内置浏览器验证。
- 未来浏览器交互按 [AGENTS](../../AGENTS.md) 使用 Codex 内置浏览器；历史证据保持原环境。
- [设计依据](../PLAN.md#设计依据)保留来源和决策背景，并随新决策更新。`docs/design/` 已解除冻结；当前计划沿用已确定的 Flutter + TeaVM 架构。
- 暂缓模块不预建页面、表或接口：自动/批量更新、离线下载、历史统计、tracker、本地漫画、备份恢复、应用内账号与隐私模块。
