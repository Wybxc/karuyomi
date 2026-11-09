# P3 扩展管理与源迁移

## 目标与状态

将正式 AOT 工具链提供的当前构建变成可用的仓库/扩展管理、Source 设置与用户确认的源迁移流程。状态：**收藏源与快捷打开、包内语言筛选已实现待独立运行验收；静态目录语言筛选已实现、集中工程检查通过，实际 Source/平台待验收；typed Source 筛选已实现，两包 v5 AOT 与 CuuTruyen Web 分项通过；typed preferences v6 正式链、Komiic AOT 与 Web 设置/新文档恢复分项通过，其它 Source/平台待验收；默认仓库扩展管理的工程检查、Web 安装和 iOS 模拟器同版本构建替换分项已过，完整生命周期待验；源迁移已通过真实 Web 与 iOS、Android 模拟器的热门选目标、章节映射、确认和独立读回，混合平台、故障及生产待验；额外仓库正式链、当前三包 AOT、Web 管理及默认 xkcd 安装/阅读分项已通过，剩余实际外仓与平台门见[子计划](additional-repositories.md)**。构建注册和浏览中的包/Source 选择属于工程基础。依赖 [P0](p0-runtime-and-reading.md) 运行边界和 [P1](p1-library-and-progress.md) 书架状态；发布流水线由[工程计划](engineering-and-release.md)维护。

## 已有基础

- 官方上游 submodule、按包 builder、manifest/provenance、失败隔离与最新版 Static Assets 工程入口已有实现。
- manifest 记录包/版本、Source IDs、完整 `CatalogSource` 名称/语言、ABI、storage schema 与资源身份；静态索引投影相同资料，运行时按构建/代次隔离并检查实际 Source IDs。
- 默认仓库的账户安装、启用、精确构建选择、手动更新和卸载链路已接入，功能与独立集中工程检查通过，实际平台待验收；静态索引仅提供构建，D1 确认清单决定使用意图。额外仓库正式链已接入，验收见[子计划](additional-repositories.md)；[源迁移](source-migration.md)的正式合同、原子 API、数据层与向导已接入；真实 Web 与 iOS、Android 模拟器的 xkcd 英文到中文迁移及独立读回通过，混合平台、故障与生产待验。
- 收藏源复用生成全局设置、D1、CAS 与原请求幂等，正式浏览中可收藏/取消并快捷打开；设计见[收藏源](../design/source-favorites.md)，工程与独立客户端门见[验证记录](../verification/source-favorites.md)。

## 待办

1. 按[扩展管理子计划](extension-management.md)推进默认仓库里程碑的实际客户端验收。D1 的 `InstalledExtension` 确认意图、不执行扩展的准备、单层有界缓存、手动更新/启停/卸载与精确选择已实现，独立集中工程检查、完整 Flutter 回归与构建通过；默认仓库的 Web 安装与 [iOS 同版本构建替换](../verification/extension-version-native.md)已实测，继续剩余平台和完整生命周期。额外仓库的账户登记、预览、刷新/移除、身份冲突、完整来源隔离及通用 Source 中继已按[子计划](additional-repositories.md)接入；实际平台验收另行推进。无 AOT 产物时明确待构建/不支持，不从网页启动远程编译。
2. 验收已接入的精确 `closeBuild(buildId,generation)`：调用方先处理请求、阅读资源和存储写锁，manager 等待 shutdown ACK 与 namespace/产物引用释放；旧代不影响新槽，失败显示并显式恢复。定向受控测试不是实际 Source 关闭证据。
3. 服务器仅保留每包最新可用构建。客户端检查索引、明确切换构建并通过受管缓存清理旧副本；iOS 模拟器已验证同版本替换时的旧代码缓存清理，跨进程缓存持久性和其它平台的清理继续验收。下架构建的 `404 build_not_found` 与 Access 登录/权限错误分开；不承诺远端历史版本回滚，不维护旧协议或旧材料兼容层。卸载保留书架、分类、进度、书签、收藏源及 Source 数据。
4. Source 自定义筛选已接入 typed 链路，两包 v5 AOT 与 CuuTruyen Web 分项已过，继续其余真实 Source/平台验收；typed Source preferences 已按[子计划](source-preferences.md)接入 v6 正式合同、开关、文本/密码、单/多选、分组、依赖项与刷新，并通过 Komiic Web 设置/新文档恢复分项，继续其它控件与跨端验收。保留原 Preference 对象、监听器及实际存储变化；D1 确认可同步非敏感值，敏感值留当前客户端，不整体同步 SharedPreferences。不把 Android 自定义 Activity 设置页当成已支持。
5. 收藏源与快捷打开已实现，补实际独立客户端及索引更新验收；包内与当前可用静态目录语言筛选已实现，新增目录集中工程检查通过，实际 Source/平台待验收；[能力提示与有界跨源搜索](cross-source-search.md)已接入双槽、逐源结果和正式 UI，独立工程与 Web 真实 Source 的交接、隔离、分页、停止和详情/阅读分项通过，其余平台门继续验收。仅声明实际验证的登录/验证码/脚本能力。
6. 按[源迁移子计划](source-migration.md)完成“搜索或浏览目标源热门作品 → 用户确认作品 → 预览一对一章节映射 → 原子补充目标收藏/分类/已读/书签”。正式协议与 D1 三 CAS 原子写、Flutter 数据层、书架/详情入口和向导已实现，独立集中工程检查与构建通过。模糊项须手动确认，原条目与目标已有状态保留，不跨源复制页面位置，不把工程检查当作实际 Source/多端完成。

## 收藏源里程碑

**可跨端同步的收藏源与快捷打开：已实现待独立客户端验收。** 收藏项以 `packageName + sourceId` 为稳定身份，名称和语言作显示快照；不保存 buildId/generation。列表复用全局设置权威路径，校验字段、128 项限额和组合身份唯一性；全局设置修改保留主题、阅读偏好和收藏，丢响应复用原请求，冲突后由用户重新确认。

正式浏览中可收藏/取消，快捷入口按当前会话已读取的静态索引打开构建，再确认原 Source ID；缺包或缺源明确提示并保留记录，不任意打开其它源。各阶段共用 busy 与身份/页面检查，未确认原操作有独立展示和显式重试。实现及证据分别见[设计](../design/source-favorites.md)与[验证](../verification/source-favorites.md)。独立客户端、构建更新后的稳定身份与打开期间切页/换身份继续验收，组件通过不等于 P3 整体完成。

## 包内语言筛选里程碑

**当前已加载包内的 Source 语言筛选：已实现待实际 Source/平台验收。** 复用正式运行时返回的 `SourceInfo.lang`，在现有包内来源列表提供语言选择、匹配数量和清除入口；只投影已取得的 Source 列表，不为筛选发 Source 请求或写业务状态，隐藏条目不改变当前已打开来源。切换包或 generation 后重置为“全部”；未加载包不显示筛选，正式空 `sources` 仍由运行时加载错误路径拒绝；验收多语言、隐藏当前选中来源和切换会话后的筛选状态。设计见[语言筛选](../design/source-language-filter.md)，实际工程与平台结果见[验证记录](../verification/source-language-filter.md)。

## 静态目录语言筛选里程碑

**当前可用静态目录的 Source 语言筛选：已实现，集中工程检查通过，实际 Source/平台待验收。** 正式 `CatalogSource{id,name,lang}` 来自官方 Gradle `metadata.sources`，写入 manifest 并投影到 index；ID 与 `sourceIds` 完整一一匹配，保留 signed int64 字符串。manifest/index 分别限 64KiB / 2MiB，装配、注册及客户端打开前核对资料与构建身份；缺少新字段的旧目录直接拒绝，不维护 fallback。

浏览页在未加载扩展前展示目录 Source 名称/语言，提供语言选择、扩展/Source 计数和清除；只使用当前索引，不下载或执行其它包，不含 pending/unavailable 上游。当前来源被隐藏仍保留上下文，包内筛选保持独立；资料只作展示，不宣称网络或运行能力。设计与历史证据分别见[语言筛选](../design/source-language-filter.md)和[验证记录](../verification/source-language-filter.md)。

本轮合同、正式组件、完整检查与空目录工程构建通过，实际 Source 静态装配、Codex 内置浏览器与 Native 门另验。当前 host 指纹包含业务协议与生成代码，其变化进入正式增量构建判定；后续 AOT 须使用当前固定输入，不复用旧格式清单。账户安装/卸载、迁移与[能力提示及跨源搜索](cross-source-search.md)的当前状态分别维护在子计划，工程检查不能代替其实际 Source/平台验收。

## typed Source 筛选里程碑

**typed Source 筛选：已实现，两包 v5 AOT 与 CuuTruyen Web 动态标签、空 query 和分页分项通过，其余 Source/平台待验收。** 具体合同与生命周期见[设计](../design/source-filters.md)。 从原 Source 的 `getFilterList` 枚举有界 Filter 子类树，通过正式协议描述可编辑状态；应用时按绑定的列表快照与有界路径回写原具体子类的 `state`，保留扩展业务中的 `filterIsInstance` 语义，不能用通用替代对象冒充原 Filter。筛选状态绑定当前 Source、generation 与清单快照，切换会话后旧引用失效。

显式应用后调用正式 `search`，空 query 也必须走搜索，不能自动退为热门；后续分页复用同一份已应用状态。类型与路径/大小/数量校验、嵌套状态处理、取消和迟到结果边界已接入并通过集中工程检查；CuuTruyen 已通过真实动态标签、非默认已完结、空 query、后续页，以及重置草稿关闭后继续原查询分页；其它类型与平台继续验收。工程结果和剩余真实运行门维护在[筛选验证记录](../verification/source-filters.md)；组件或 JVM/宿主适配测试不替代实际在线筛选验收。CuuTruyen 上游使用 `Group<TagCheckBox>` 与远端动态标签，本轮记录绑定修复后 v5 AOT；历史默认浏览与图片证据仍不自动覆盖新构建。

typed preferences 已接入正式设置入口并通过 Komiic v6 AOT、Web 设置与新文档恢复分项，按[独立子计划](source-preferences.md)继续其它 Source 与跨端验收。[扩展管理](extension-management.md)、[能力提示与跨源搜索](cross-source-search.md)和[用户确认迁移](source-migration.md)按各子计划推进独立验收；不以零散界面改动代替这些流程。

## 扩展管理里程碑

**默认仓库的集中工程检查、Web 安装和 iOS 模拟器同版本构建替换分项已过；额外仓库正式来源链已接入，工程与实际平台分别验收。** [子计划](extension-management.md)维护完整范围，[设计](../design/extension-management.md)确定 `InstalledExtension`、全局 CAS/pending、准备/取消、代码缓存与关闭合同，[验证记录](../verification/extension-management.md)区分已过集中工程与实际平台门。

D1 保存账户清单、enabled 和精确 build/hash，缺记录不自动安装；本机准备只下载/验证代码，不执行 Source。缓存直接使用 idb，128 项/256MiB，shared pin 保护使用中产物；运行槽精确关闭并等待 ACK/释放。安装和更新先准备后按原 CAS 确认，检查更新不自动换版；四打开路径、实际调用和图片 provider 共用确认门禁。停用/卸载以账户确认驱动，关闭/清理失败单独展示，保留业务、Source 数据与 HTTP Cache。

[iOS 实测](../verification/extension-version-native.md)通过手动替换 xkcd 1.6.1 构建、清除旧代码缓存及新进程续读；Native 上游版本升级、Android 换版、真机、生产和完整生命周期继续验收。历史固定 `ad869d2` 三包 AOT 候选通过，仅 `compiled_unverified`，未部署或写正式 checkpoint，见[候选证据](../verification/extension-management.md#固定-ad869d2-三包-aot-候选)。额外仓库的添加、验证、刷新/移除、身份冲突和通用 Source 中继已按[子计划](additional-repositories.md)接入，实际外仓、Source/平台与独立客户端继续验收；[能力提示与有界跨源搜索](cross-source-search.md)已接入，独立服务回归已过，实际运行门待验收，不将本里程碑当作完整 P3 完成。

## 源迁移里程碑

**已实现，工程与真实 Web、iOS 和 Android 模拟器的顺序迁移和独立读回已通过。** [子计划](source-migration.md)维护目标与待办，[设计](../design/source-migration.md)确定三 CAS、保留源/目标状态、一对一章节身份及显式原请求恢复，[验证记录](../verification/source-migration.md)区分定向合同/D1、跨语言、受控客户端与真实平台门。

预览按源、目标及分类目录 revision 冻结，只在用户独立确认后原子写入目标收藏、分类并集和缺失正向已读/书签；原作品不改，目标已有 progress、封面与续读保留，原页位不跨源复制。未知 ACK 只显式重试原 UUID/body/CAS，最多 256 组映射且不隐式截断/拆批。正式 Web 与 iOS、Android 模拟器均使用 xkcd 英文和中文源，验证热门列表选目标、手动映射、确认前状态不变及独立读回；更多 Source、故障、混合平台和生产继续验收。

## typed Source preferences 里程碑

**已实现，集中工程检查、固定 Komiic v6 AOT 与 Web 设置/新文档恢复分项通过；其它控件、Native 与生产待验收。** [子计划](source-preferences.md)和[设计](../design/source-preferences.md)记录正式 v6 IDL、限额、敏感分类、实际存储分区与原 Preference 适配。开关、文本/密码、单/多选、分组、依赖、动作及确认后重开刷新已接入。

运行时保留原 Preference 对象和回调语义，处理拒绝、别名写入与动态描述；非敏感值由 D1 条件写入确认并在构造 Source 前注入，秘密值留当前客户端。待确认业务请求只显式重试原 UUID/body，不重跑 Source listener；冲突或未知运行结果经回收重开恢复。工程与真实运行证据分别维护在[记录](../verification/source-preferences.md)，已有筛选证据不覆盖设置能力。

## 能力提示与有界跨源搜索里程碑

**已实现，Web 真实 Source 分项通过，其余门继续验收。** [子计划](cross-source-search.md)维护范围与验收，[设计](../design/cross-source-search.md)确定两个物理槽、无活动阅读时独占、完整包 namespace 分组和同包串行。用户明确选择已确认 Source，各源独立返回、手动分页和取消；结束、离页与进入正式详情均需关闭或 reset 确认后交还主线。数量预算不截断或隐式分批，身份退休不自动恢复旧查询。

能力说明复用实际 `supportsLatest`、宿主能力和当前操作错误，不新增人工能力矩阵或推断登录/验证码。独立工程检查与 Web 三包真实 Source 的交接、空结果/原错误隔离、分页、活动停止和详情/图片阅读分项通过；物理双 Worker 独立观测、更多 Source、Native 和生产继续验收。精确层级见[跨源搜索验证](../verification/cross-source-search.md)。

## 验收

- 安装/手动升级/卸载与旧缓存清理流程有真实构建用例；中断、拒绝、存储冲突或缺失材料均明确失败，不能以隐式旧版本 fallback 掩盖问题。
- 已开放的筛选和设置逐项有真实 Source 证据；敏感项不泄漏到公开资源或多设备同步。
- 源迁移预览与最终写入一致，原条目完整保留，用户另行决定移除；不自动快照、不依赖备份/追踪模块。
- Source URL/ID 保持稳定；换域和来源变化走显式规则，不用全局解码或按标题去重制造新身份。
