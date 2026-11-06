# 扩展目录与当前包的 Source 语言筛选

浏览页提供两个独立的语言投影：静态目录在加载扩展前展示当前可用构建的 Source 名称和语言；包内列表在加载后使用运行时 `SourceInfo`。实施状态见 [P3](../plan/p3-extensions-and-migration.md#静态目录语言筛选里程碑)，历史与当前验证分别见[记录](../verification/source-language-filter.md)。收藏源和 typed Source filters/preferences 保持各自边界。

## 静态目录与构建来源

正式协议的 `CatalogSource{id,name,lang}` 同时写入 `BuildManifest.sources` 和 `ExtensionIndex.builds[].sources`。数据来自锁定 Keiyoushi 上游官方 Gradle 的 `keiyoushi-source-info.json`：`ExtensionPlugin` 解析扩展声明的 Source，官方任务生成 `metadata.sources`，项目 builder 校验后写入 manifest；`staticIndex` 再从 manifest 原样投影，不为目录逐包下载或执行扩展，也不从收藏快照补资料。

每包必须包含 1–500 个 Source，`sources` 与 `sourceIds` 的字符串 ID 集合完整一一匹配，拒绝重复或缺失。ID 保留 signed int64 的十进制字符串，不能经 JS Number 转换；名称去空白后非空且最多 500 个 UTF-16 code units，语言最多 64 个，允许空值。静态名称和语言仅供展示与筛选，不声明运行时能力、网络可用性或 `runtimeReady`。实际加载仍校验原 Source ID，能力由正式运行时返回。

manifest 上限 64KiB，完整 index 上限 2MiB、5,000 包。builder、快照、静态装配、登记和正式加载均维护结构、身份与预算边界；装配/登记核对索引与 manifest，客户端打开前再次核对 build、包、仓库、版本及每个 Source 的名称/语言。资料不一致时要求重新连接刷新目录，不先注入设置或执行扩展。原型不为缺少 `sources` 的旧目录增加兼容分支，须用当前输入重建快照。操作合同见[扩展分发](../EXTENSIONS.md#静态快照与传输合同)。

“扩展目录”只覆盖当前索引中最新可用的构建，不等于上游全部扩展；尚未构建、失败且无可用构建或不兼容的 pending/unavailable 包不在其中，也不代表账户已安装清单。

## 目录投影与状态

目录语言取索引全部 `CatalogSource.lang`，去重排序；提供“全部语言”、单个语言、匹配扩展/Source 数量和清除入口。真实 `all` 与“全部语言”分开，空语言显示“未标注语言”。扩展包含任一匹配 Source 即显示，并仅列出其中匹配的 Source；只有显式点击构建才走正式加载。

选择与清除仅改变本页状态，不发 Source 请求、下载其它扩展或写业务状态。被隐藏的已打开扩展仍保留当前 Source、漫画列表和阅读上下文，并显示说明。目录筛选与包内筛选互不覆盖；目录状态绑定 controller 与 subject，身份变化重置，刷新后所选语言已不存在也重置。切包或 generation 变化不重置仍有效的目录选择；busy 时禁用相关操作。空目录明确提示重新连接刷新，不显示“已安装”含义。

## 包内投影与状态

包内选项直接取当前运行时 `SourceInfo.lang`，保留返回顺序。尚未加载包时不显示包内筛选；正式运行时拒绝空 `sources`，继续沿加载错误路径提示，不引入空包可加载状态。选择、计数与清除保持和目录相同的语言值语义。

选择或清除包内语言不发 Source 请求、不写全局设置、不改变 `activeSource`。已选 Source 即使被隐藏也保持当前漫画与阅读上下文；只有明确选择另一 Source 才走正式 `selectSource`。收藏源列表仍展示服务器确认的记录。

包内筛选会话键包括 controller、subject、packageName/buildId、workerInstanceId 与 generation；键变化或运行时关闭后恢复“全部语言”。同会话切换来源保持筛选，busy 期间禁用筛选和来源切换。两类筛选均是可丢弃界面状态，不进入 D1、Source preferences 或持久客户端存储。

## 范围与验收

当前只完成可用静态目录与已加载包的语言投影。能力目录、有界跨源搜索、账户扩展安装/卸载、额外仓库与用户确认迁移继续按 [P3](../plan/p3-extensions-and-migration.md) 推进。typed filters/preferences 已有独立正式链，不能将语言投影或工程测试算作其真实 Source 验收；本轮集中工程检查通过，实际 Source 静态快照、浏览器、Native 和生产门仍单独验收。
