# 扩展管理

## 目标与状态

**状态：已实现待实际平台验收。默认 Static Assets 仓库的账户合同、准备与缓存、关闭协议及正式管理入口已实现，独立集中工程检查、完整 Flutter 回归与构建通过；当前 AOT 的 Web 准备/安装、双标签精确选择与 xkcd 两页阅读分项通过，其余平台及完整生命周期待验收。** 设计见[账户扩展与本机准备](../design/extension-management.md)，实际通过层级见[验证记录](../verification/extension-management.md)。额外仓库的正式来源链与管理入口也已接入，独立工程和实际平台门按[额外仓库子计划](additional-repositories.md)验收；不以工程通过代替完整 P3。上级计划见 [P3](p3-extensions-and-migration.md)。

目标是让同一身份在 Web、iOS、Android 使用同一份账户扩展清单，区分账户已确认的使用意图、本机准备情况和正在运行的精确构建。安装准备不执行扩展，更新由用户明确发起，切换前关闭原运行槽，卸载后清理不再使用的本机扩展副本。

服务器继续仅提供每包最新可用构建，不增加历史版本、旧协议兼容或隐式回退。功能提交后，固定 `ad869d2` 的三包后台 AOT 与完整性/快照通过，仅为 `compiled_unverified` 候选，详见[验证记录](../verification/extension-management.md#固定-ad869d2-三包-aot-候选)；未部署或写正式 checkpoint，baseline 未完成。

## 当前实现

- `InstalledExtension` 保存 `catalogUrl/repoId/packageName/buildId/bundleSha256/enabled`，位于生成协议的全局设置，最多 128 项，同一个包只能选择一个仓库与构建。没有记录就是未安装，不从静态索引自动生成账户成员。
- D1 保存账户已确认意图，沿用全局设置 CAS、原 mutation UUID/body 和确认后重取。准备开始时复制完整全局值并固定 revision；准备结束不重读一个新 CAS 覆盖并发修改。任意未知 ACK 的全局 pending 阻止新编辑，只能显式重试整份原请求；只读刷新不重放写入。
- 默认仓库使用当前部署 origin 的 `/extensions/index.json`。已确认清单和当前目录分别呈现；检查更新只重读目录，不自动切换。安装、更新先 `prepareBuild`，再确认账户选择；本机缺副本可独立准备，不写账户选择。
- 准备重新核对当前索引与 manifest，沿正式有界下载、解压和完整性路径取得代码，不创建 Source Worker 或调用 Source。manager 仅允许一个准备任务，关联 preparation ID，设置 60 秒取消信号，取消完成前等待下载与缓存操作收尾。
- 扩展代码直接使用 `idb@8.0.4` 的单层可丢弃 IndexedDB 缓存；metadata 与 canonical JS bytes 原子写入，最多 128 项 / 256MiB。下载验证收据在本地复用，不再次 hash；占用可以查询，单副本可以删除。Web Locks 的 shared pin 保护准备与活动构建，删除须取得排他锁；不全清 IndexedDB 或 WebView 数据。
- `closeBuild(buildId,generation)` 要求调用方先收尾活动请求、队列和图片资源。关闭期间拒绝新 open/调用，等待 Worker shutdown ACK（5 秒期限）以及 namespace 与产物引用释放；失败回收运行槽并报告失败，不能将 terminate 当成成功 ACK。旧代关闭不能影响新代。关闭失败后保留原错误；显式“重建运行时并恢复清理”是独立 reset，先成功收尾 provider，再等待重建确认与引用释放，不将强制回收伪报为 shutdown ACK。
- 浏览开包、目录 Source、收藏源与书架打开共同遵守已确认安装、enabled、仓库、精确 build 和 bundle hash；实际调用与章节图片 provider 同样有门禁。下架构建需手动更新，不因索引刷新静默换版。
- 停用、改选或卸载先确认账户意图，再关闭对应章节/provider 和精确运行槽；关闭或副本删除失败单独显示、可重试。卸载保留书架、分类、进度、书签、收藏源、Source 数据与 HTTP Cache；共享 materials 仍走 Web Static Assets / Native 内置材料，不按扩展重复缓存。

以上是默认仓库的接入范围；额外仓库的添加、移除、同包替换及来源隔离见[独立子计划](additional-repositories.md)。集中工程与真实客户端验收分别记录。

## 下一步

### 默认仓库里程碑

- [x] Dart 管理 UI、transport、四打开路径与正式夹具已接入，保持缺记录不自动安装。
- [x] 独立审查原 CAS、未知 ACK、取消与迟到结果、关闭失败恢复、跨实例缓存引用和已确认停用门禁，已修复发现的问题并补回归。
- [x] 生成一致性、严格分析、依赖检查、正式测试、完整格式及客户端/API 构建通过；实际结果统一见验证记录，后续代码变更另验。
- 在 Codex 内置浏览器和 Native 正式入口验收安装、更新、停用与卸载，使用符合当前元数据和协议的真实 AOT；不能向旧清单补字段来冒充新构建。
- 两个独立客户端以同一身份读回相同账户意图，分别检查本机空缓存、关闭收尾、CAS 冲突与丢响应的原请求恢复；生产 Access、真机分别记录。

### 额外仓库与完整 P3

- [额外仓库](additional-repositories.md)的登记、预览、刷新与移除已接入；空外仓 Web 元数据管理与双标签顺序收敛已过，继续真实外仓代码、Native 和独立设备验收。
- 同包跨仓明确确认、URL/repoId 冲突、准备/会话来源回显和按来源网络登记已落实。账户合同保持 package 唯一；实际运行证据另验。
- 没有当前 AOT 产物时展示待构建或不支持，不从客户端启动远程编译。未知仓库或下架构建保留账户记录并显示不可用，不在只读刷新时删除。
- 迁移、能力目录和有界跨源搜索继续按上级 P3 推进；本里程碑不缩减这些待办。

## 验收条件

- 同一身份的独立客户端读回相同清单、enabled 与精确构建；本机空缓存准确显示未准备，不伪报另一设备已下载。
- 安装准备零 Source Worker/Source 请求；候选准备失败、超限、缺材料、CAS 冲突或 ACK 未知均不伪报账户保存。原全局请求不被其它设置编辑覆盖。
- 检查更新无账户写入；明确确认前不替换当前构建。下架与 `build_not_found`、Access 失效/权限拒绝分别呈现，无历史版本或协议 fallback。
- 活动请求、阅读资源和 namespace 竞争下，关闭 ACK、迟到结果隔离与失败恢复成立；资源未释放不宣称清理成功。
- 本机占用与删除有实际证据，使用中的副本不能误删；卸载保留其它包、共享材料和业务/Source 数据，另一端读回移除后执行本机收敛。
- 额外仓库有正式操作入口和独立证据；默认目录浏览不计作已完成添加仓库。
- 区分组件、受控 supplier、下载、AOT、实际 Source、独立客户端、生产 Access 与真机层级，只报告实际执行环境。
