# 工程、AOT 与发布

## 目标与状态

维护可重复准备、按包隔离失败、可恢复发布的正式构建工具；首次全量在本地完成，之后 CI 只做有界增量。状态：**进行中**，当前 host 的首次 baseline 尚未完成。本轮 TS 整合的 198 项测试、完整回归与 Flutter 检查已通过；发布器审查修补仍待最终验证和真实发布。旧全量队列已经停止，不再恢复为当前产品发布。

操作命令、Release 资产契约及恢复流程只在 [EXTENSIONS](../EXTENSIONS.md) 维护；材料契约见 [RUNTIME-MATERIALS](../RUNTIME-MATERIALS.md)，包体测量与采用方案见 [AOT-SIZE](../AOT-SIZE.md)。本计划不重复维护实时发布数或日志。

## 已完成

- 官方 Keiyoushi、TeaVM、Suwayomi 通过固定提交的 submodule 引入；研究交付中的项目代码已内化。上游适配使用正式补丁生成，依赖/JAR/seed/大产物留在忽略目录，保留来源与许可。
- generalized builder 可从当前上游源码发现扩展、准备固定 Java/Maven/Android 依赖、构建原版 JAR、按包 AOT 并输出 manifest/hash/provenance；无法解析或构建的包独立记录失败。
- 包体方案已经少量真实 A/B 确认：保留 `ADVANCED` 和现有服务，五桥/WASM 共享交付，每包私有 AOT 确定性 gzip；低收益服务裁剪不合入，额外字典或档位研究不阻塞发布。
- 初始代表包曾从本地发布；固定 `7f54463` 的旧全量队列已停止，历史 checkpoint 和日志保留。其五个桥摘要不在当前 material catalog 中，原型不提供兼容集合，旧批次不能作为当前 host 的可用发布基线。
- 全项目自有代码已接统一多语言格式化与 prek；自有 Node 脚本、宿主材料工具和五个桥已完成严格 TS 迁移，整合回归与 Flutter 检查通过，产品执行字节由构建生成。
- 通用 CI 已限定分支 push/PR；Release tag 不触发项目检查。扩展 CI 有缺失本地 baseline 的保护、增量限额和单发布者约束。

## 待办

1. 完成发布器恢复引用、唯一 publisher 取消和产物边界的审查修补；复跑完整格式、类型与对应回归，完成当前格式的真实发布验证，及时按可审阅里程碑提交并推送。
2. 完成当前格式的真实 GitHub 发布、下载恢复、中断续传与索引更新验证。索引定位固定 `extensions-index`，单包按包名/版本定位；内部源码/host 指纹继续用于增量和 provenance，不重复放进 tag/title。
3. 上传/下载边界各校验对应字节域；传递已验证的进程内 owned bytes/metadata，避免相邻阶段反复读取同一大文件计算摘要。压缩与 canonical 是不同字节域；D1/R2 注册仍是独立交付边界。
4. 当前 host/工具链稳定并提交后，新建隔离 checkout、完整 plan 和 checkpoint，重新运行当前输入的本地首次全量。先确认旧调度器及子进程全部停止、publisher 锁已释放；不恢复旧 `7f54463` 队列，不将其 published 标记或旧材料当作当前结果。新队列保留逐包诊断，全部发现项有 published/明确 failed 后再 finalize。
5. 完成 baseline 后启用日常增量验收：跟进上游固定提交，只构建变化依赖闭包，失败逐包记录；没有 baseline 不退化为 CI 首次全量。

当前包默认可发布为 `compiled_unverified`、`runtimeReady=false`。真实浏览器初始化通过也不自动成为 Source 在线、图片或真机支持声明。原型仅维护当前格式，不实现旧 tag、旧材料、旧清单或 raw 传输的兼容层；历史 Release 不改写为新格式。

## 验收

- 干净 checkout 与固定依赖能准备工具链并重建代表包；业务源码/输入 JAR 未修改，来源和构建身份可追踪。
- AOT bundle 私有交付；共享材料只由 Web 静态资源或 Native 内置提供，Native 缺失材料明确失败且无网络回退。
- 当前 Release 定位、gzip 双字节域校验、有界恢复、失败续传与索引单写者均有回归；远端实际结果与本地模拟证据区分。
- 本地 baseline 包含所有发现项及明确结果，可中断/恢复且磁盘增长受控；CI 只处理有界增量，tag 不触发通用 CI。
- 提交前运行 `pnpm format`、`pnpm format:check` 及对应回归，prek 不跳过；变更及时提交推送，源码库不夹带临时工程或机器输出。
