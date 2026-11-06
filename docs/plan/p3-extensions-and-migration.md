# P3 扩展管理与源迁移

## 目标与状态

将正式 AOT 工具链提供的当前构建变成可用的仓库/扩展管理、Source 设置与用户确认的源迁移流程。状态：**收藏源与快捷打开、包内语言筛选已实现待独立运行验收；静态目录语言筛选已实现、集中工程检查通过，实际 Source/平台待验收；typed Source 筛选已实现，两包 v5 AOT 与 CuuTruyen Web 分项通过；typed preferences v6 正式链、Komiic AOT 与 Web 设置/新文档恢复分项通过，其它 Source/平台待验收；扩展管理未实现、正式合同待定，迁移待实现**。构建注册和浏览中的包/Source 选择属于工程基础。依赖 [P0](p0-runtime-and-reading.md) 运行边界和 [P1](p1-library-and-progress.md) 书架状态；发布流水线由[工程计划](engineering-and-release.md)维护。

## 已有基础

- 官方上游 submodule、按包 builder、manifest/provenance、失败隔离与最新版 Static Assets 工程入口已有实现。
- manifest 记录包/版本、Source IDs、完整 `CatalogSource` 名称/语言、ABI、storage schema 与资源身份；静态索引投影相同资料，运行时按构建/代次隔离并检查实际 Source IDs。
- 浏览入口能够从静态索引选择当前构建；这不等于账户安装、启用、手动更新、卸载或迁移已完成。
- 收藏源复用生成全局设置、D1、CAS 与原请求幂等，正式浏览中可收藏/取消并快捷打开；设计见[收藏源](../design/source-favorites.md)，工程与独立客户端门见[验证记录](../verification/source-favorites.md)。

## 待办

1. 按[扩展管理子计划](extension-management.md)实现仓库添加、账户扩展安装成员关系、启用/停用、卸载、手动更新、精确当前构建选择及用户可见错误。D1 保存账户已确认意图，本机准备状态和可丢弃产物缓存单独呈现；安装准备不执行扩展。额外仓库的登记、验证、更新/移除、身份冲突，以及接入 Static Assets 权威和 Source 网络政策的设计仍待落实，不缩为只有默认仓库。无 AOT 产物时明确待构建/不支持，不从网页启动远程编译。
2. 补齐切换前带预期 build/generation 的执行槽关闭与排空 ACK，处理取消、阅读资源和存储写锁，避免跨标签页/实例同时写相同可变 namespace；失败时提供准确状态和显式恢复。现有强制失效不等于可复用关闭完成。
3. 服务器仅保留每包最新可用构建。客户端检查索引、明确切换所选版本并通过受管缓存清理旧副本；当前尚缺可枚举、可删除的产物缓存和占用状态。下架构建的 `404 build_not_found` 与 Access 登录/权限错误分开；不承诺远端历史版本回滚，不维护旧协议或旧材料兼容层。卸载保留书架、分类、进度、书签、收藏源及 Source 数据。
4. Source 自定义筛选已接入 typed 链路，两包 v5 AOT 与 CuuTruyen Web 分项已过，继续其余真实 Source/平台验收；typed Source preferences 已按[子计划](source-preferences.md)接入 v6 正式合同、开关、文本/密码、单/多选、分组、依赖项与刷新，并通过 Komiic Web 设置/新文档恢复分项，继续其它控件与跨端验收。保留原 Preference 对象、监听器及实际存储变化；D1 确认可同步非敏感值，敏感值留当前客户端，不整体同步 SharedPreferences。不把 Android 自定义 Activity 设置页当成已支持。
5. 收藏源与快捷打开已实现，补实际独立客户端及索引更新验收；包内与当前可用静态目录语言筛选已实现，新增目录集中工程检查通过，实际 Source/平台待验收；继续能力提示及有界跨源搜索，各源独立返回、可取消，一个慢源不阻塞全部结果。仅声明实际验证的登录/验证码/脚本能力。
6. 实现源迁移：搜索候选 → 用户确认作品 → 预览章节映射 → 创建目标收藏 → 复制明确匹配的分类/已读/书签。章节号、标题、扫描组辅助匹配；模糊项不自动标已读。

## 收藏源里程碑

**可跨端同步的收藏源与快捷打开：已实现待独立客户端验收。** 收藏项以 `packageName + sourceId` 为稳定身份，名称和语言作显示快照；不保存 buildId/generation。列表复用全局设置权威路径，校验字段、128 项限额和组合身份唯一性；全局设置修改保留主题、阅读偏好和收藏，丢响应复用原请求，冲突后由用户重新确认。

正式浏览中可收藏/取消，快捷入口按当前会话已读取的静态索引打开构建，再确认原 Source ID；缺包或缺源明确提示并保留记录，不任意打开其它源。各阶段共用 busy 与身份/页面检查，未确认原操作有独立展示和显式重试。实现及证据分别见[设计](../design/source-favorites.md)与[验证](../verification/source-favorites.md)。独立客户端、构建更新后的稳定身份与打开期间切页/换身份继续验收，组件通过不等于 P3 整体完成。

## 包内语言筛选里程碑

**当前已加载包内的 Source 语言筛选：已实现待实际 Source/平台验收。** 复用正式运行时返回的 `SourceInfo.lang`，在现有包内来源列表提供语言选择、匹配数量和清除入口；只投影已取得的 Source 列表，不为筛选发 Source 请求或写业务状态，隐藏条目不改变当前已打开来源。切换包或 generation 后重置为“全部”；未加载包不显示筛选，正式空 `sources` 仍由运行时加载错误路径拒绝；验收多语言、隐藏当前选中来源和切换会话后的筛选状态。设计见[语言筛选](../design/source-language-filter.md)，实际工程与平台结果见[验证记录](../verification/source-language-filter.md)。

## 静态目录语言筛选里程碑

**当前可用静态目录的 Source 语言筛选：已实现，集中工程检查通过，实际 Source/平台待验收。** 正式 `CatalogSource{id,name,lang}` 来自官方 Gradle `metadata.sources`，写入 manifest 并投影到 index；ID 与 `sourceIds` 完整一一匹配，保留 signed int64 字符串。manifest/index 分别限 64KiB / 2MiB，装配、注册及客户端打开前核对资料与构建身份；缺少新字段的旧目录直接拒绝，不维护 fallback。

浏览页在未加载扩展前展示目录 Source 名称/语言，提供语言选择、扩展/Source 计数和清除；只使用当前索引，不下载或执行其它包，不含 pending/unavailable 上游。当前来源被隐藏仍保留上下文，包内筛选保持独立；资料只作展示，不宣称网络或运行能力。设计与历史证据分别见[语言筛选](../design/source-language-filter.md)和[验证记录](../verification/source-language-filter.md)。

本轮合同、正式组件、完整检查与空目录工程构建通过，实际 Source 静态装配、Codex 内置浏览器与 Native 门另验。当前 host 指纹包含业务协议与生成代码，其变化进入正式增量构建判定；后续 AOT 须使用当前固定输入，不复用旧格式清单。能力目录、有界跨源搜索、账户安装/卸载与迁移继续保留原待办。

## typed Source 筛选里程碑

**typed Source 筛选：已实现，两包 v5 AOT 与 CuuTruyen Web 动态标签、空 query 和分页分项通过，其余 Source/平台待验收。** 具体合同与生命周期见[设计](../design/source-filters.md)。 从原 Source 的 `getFilterList` 枚举有界 Filter 子类树，通过正式协议描述可编辑状态；应用时按绑定的列表快照与有界路径回写原具体子类的 `state`，保留扩展业务中的 `filterIsInstance` 语义，不能用通用替代对象冒充原 Filter。筛选状态绑定当前 Source、generation 与清单快照，切换会话后旧引用失效。

显式应用后调用正式 `search`，空 query 也必须走搜索，不能自动退为热门；后续分页复用同一份已应用状态。类型与路径/大小/数量校验、嵌套状态处理、取消和迟到结果边界已接入并通过集中工程检查；CuuTruyen 已通过真实动态标签、非默认已完结、空 query、后续页，以及重置草稿关闭后继续原查询分页；其它类型与平台继续验收。工程结果和剩余真实运行门维护在[筛选验证记录](../verification/source-filters.md)；组件或 JVM/宿主适配测试不替代实际在线筛选验收。CuuTruyen 上游使用 `Group<TagCheckBox>` 与远端动态标签，本轮记录绑定修复后 v5 AOT；历史默认浏览与图片证据仍不自动覆盖新构建。

typed preferences 已接入正式设置入口并通过 Komiic v6 AOT、Web 设置与新文档恢复分项，按[独立子计划](source-preferences.md)继续其它 Source 与跨端验收。[扩展管理](extension-management.md)、能力目录、有界跨源搜索和用户确认迁移继续保留完整待办；不以零散界面改动代替这些流程。

## 扩展管理里程碑

**未实现，正式合同待定。** [子计划](extension-management.md)细化账户清单、额外仓库接入、本机准备、运行槽关闭和正式管理入口。账户安装成员关系、启用状态与精确构建选择以 D1 为权威，沿用全局设置 CAS、原 UUID/body 显式重试及跨端确认；正在运行的 build/generation 不因索引或账户刷新静默替换。本机下载、验证、占用和清理只描述该设备的可丢弃副本。

现有加载器和浏览选择不是独立安装流程，当前尚缺不执行扩展的准备、受管缓存，以及可复用且等待 namespace 释放的关闭 ACK。手动更新和卸载必须覆盖真实资源收尾、迟到结果、失败恢复与缓存删除；卸载保留业务状态和 Source 数据。额外仓库的完整接入仍在范围内，其与 Static Assets 权威及网络政策的合同须先确定；候选库不写成已接入能力。任务与独立客户端验收条件统一在子计划维护。

## typed Source preferences 里程碑

**已实现，集中工程检查、固定 Komiic v6 AOT 与 Web 设置/新文档恢复分项通过；其它控件、Native 与生产待验收。** [子计划](source-preferences.md)和[设计](../design/source-preferences.md)记录正式 v6 IDL、限额、敏感分类、实际存储分区与原 Preference 适配。开关、文本/密码、单/多选、分组、依赖、动作及确认后重开刷新已接入。

运行时保留原 Preference 对象和回调语义，处理拒绝、别名写入与动态描述；非敏感值由 D1 条件写入确认并在构造 Source 前注入，秘密值留当前客户端。待确认业务请求只显式重试原 UUID/body，不重跑 Source listener；冲突或未知运行结果经回收重开恢复。工程与真实运行证据分别维护在[记录](../verification/source-preferences.md)，已有筛选证据不覆盖设置能力。

## 验收

- 安装/手动升级/卸载与旧缓存清理流程有真实构建用例；中断、拒绝、存储冲突或缺失材料均明确失败，不能以隐式旧版本 fallback 掩盖问题。
- 已开放的筛选和设置逐项有真实 Source 证据；敏感项不泄漏到公开资源或多设备同步。
- 源迁移预览与最终写入一致，原条目完整保留，用户另行决定移除；不自动快照、不依赖备份/追踪模块。
- Source URL/ID 保持稳定；换域和来源变化走显式规则，不用全局解码或按标题去重制造新身份。
