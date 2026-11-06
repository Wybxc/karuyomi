# 当前包的 Source 语言筛选

浏览页的语言筛选只作用于当前已加载扩展返回的 `SourceInfo` 列表。它帮助用户在同一包的多个 Source 中选择语言；全目录检索、收藏源同步和 Source 业务筛选各有独立边界。实施状态见 [P3](../plan/p3-extensions-and-migration.md#包内语言筛选里程碑)，工程与实际运行证据见[验证记录](../verification/source-language-filter.md)。

## 列表投影与状态

语言选项直接取当前运行时 `SourceInfo.lang`，保留 Source 的真实语言值。提供“全部语言”、单个语言、匹配数量和清除入口；实际语言值 `all` 与“全部语言”分别处理，空语言显示为“未标注语言”。选项去重排序，来源顺序仍沿用运行时返回顺序。尚未加载包时不显示筛选；正式运行时拒绝空 `sources`，继续沿现有加载错误路径提示，不引入空包可加载状态。

选择或清除语言仅改变客户端本页列表投影，不发 Source 请求、不写全局设置、不改变 `activeSource`。已经打开的 Source 即使被筛选隐藏，也保持当前漫画列表与阅读上下文；只有用户明确选择另一来源时，才走正式 `selectSource`。收藏源列表仍展示服务器确认的记录，不受当前包筛选影响。

筛选是可丢弃的界面状态，不进入业务协议、D1、Source preferences 或持久客户端存储。筛选会话键包括 controller、subject、packageName/buildId、workerInstanceId 与 generation；键变化或运行时关闭后恢复“全部语言”，避免旧会话语言造成新来源隐藏。同一会话里切换来源保持当前筛选，busy 期间禁用筛选和来源切换。

## 范围

当前 Static Assets 索引只有构建层目录，缺少每包完整的 Source 名称/语言；加载一个包后才能得到实际来源。此处不为了筛选加载其它包，也不把收藏中的显示快照当作全目录数据。全目录语言筛选、能力目录、有界跨源搜索与 typed Source filters/preferences 继续属于 [P3](../plan/p3-extensions-and-migration.md) 后续工作。
