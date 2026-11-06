# typed Source preferences

## 目标与状态

状态：**未实现；已完成固定上游与锁定 seed 的只读调查，正式合同待确定。** 本计划细化 [P3](p3-extensions-and-migration.md) 的 Source 设置待办。沿用[跨语言协议设计](../design/cross-language-protocol.md)与[同步计划](p2-sync.md)，完成同一身份在 Web/iOS/Android 的非敏感 Source 设置在线读写、运行时生效和失败恢复；敏感凭证留在当前客户端，不进入普通同步。

交付范围是开关、文本/密码、单选、多选、分组、依赖项与修改后刷新。保留 Source 原 Preference 对象和回调语义，不修改官方扩展业务源码。Android 自定义 Activity、任意自定义对话框或 WebView 登录不因出现设置入口而视为已支持。下述消息名、字段、数据表与流程细节均为实施建议，尚未写入正式 IDL 或产品代码。

## 已核实的基础与缺口

- 正式 `TeaHost.hostInvoke` 已有浏览、详情、图片和 typed filters 调用，尚无 preferences 操作；Flutter、TS/Dart 控制合同和 API 也没有 Source 设置链路。
- 固定 Suwayomi 的 `ConfigurableSource.setupPreferenceScreen` 与 Keiyoushi 的 `getPreferences` 均使用 `source_$id` SharedPreferences。Source ID 保持原十进制字符串，不能转成 JS Number。
- 锁定 seed 的实际 ABI 不等于当前 Suwayomi 兼容源码：seed 已保留 click/change listeners、开关/单选/多选/文本的状态访问器；Preference 默认值 getter 为 protected。可用项目自有同包访问器取得默认值，不必为此引入反射。
- seed 的 SharedPreferences 是按文件名保存的内存 Map，已有 Editor、commit/apply、remove/clear 和变更监听；没有 D1 或磁盘权威存储。不能把现有内存能力报告成设置同步。
- seed 没有 `PreferenceGroup/PreferenceCategory` 和声明式 dependency API；现有 PreferenceScreen 可持子项。实际扩展已有通过 change listener 修改其它控件 enabled、summary 的依赖。
- 锁定 Android JAR 的 EditText 构造会抛 `Stub!`。直接执行 onBindEditTextListener 不能获得可用编辑器；password/inputType、TextWatcher 等需要单独实现并验证有界 headless 适配。

## 合同待定点

实施前统一以下决定，再修改 `.proto`、生成模型与调用方，不在各层独立定名。

1. **描述与操作。** 候选是 `getPreferences` 返回绑定 Source/generation 的 `PreferenceSnapshot(snapshotId, nodes)`；`changePreference(snapshotId, path, typedValue)` 与 `clickPreference(snapshotId, path)` 分开，返回操作结果和更新后的描述。一个当前设置树足够；是否在失败后保留原快照须明确。节点覆盖开关、文本、单选、多选、递归分组、动作及明确不支持的项，描述 key、title、summary、enabled、visible 和必要 dialog 信息。默认值、缺省值、空字符串、false、空集合和删除分别定义，不能靠转换补齐非法输入。
2. **选项与限额。** 单/多选使用真实 entryValues，标签和索引不代替存储值；同一组选项值唯一。确定树深度、节点数、选项数、键/标签/文本长度、快照和集合预算。可参考[筛选合同](../design/source-filters.md)的有界模式，但数值尚未选定。现有控制请求的整体 128KiB 预算仍须落实，bootstrap 也不能按每个 Source 分别合规后无界拼接。
3. **同步身份与存储。** 候选为按已验证 subject、packageName、sourceId 保存独立 revision 和 typed values，不把 buildId/generation 写成业务身份，不把整包设置塞入全局阅读设置。明确 SharedPreferences 文件名、控件 key 与实际存储 key 的映射；跨 key 写入不能被静默丢弃。API 路径、单源/整包读取方式、CAS 范围与删除语义待定。
4. **敏感值策略。** 必须显式区分可同步值与当前客户端值，不能仅依赖 password inputType 或 key 名猜测。建议未声明文本、未知存储键和回调产生的未知值先留会话，经核对的非敏感文本/别名由宿主元数据声明；具体分类规则、用户提示和普通 API 的拒绝规则待确定。不得整体上传 SharedPreferences.getAll()。首版可只保留会话内敏感值；不据此建立持久业务数据库或云端凭证同步。
5. **兼容能力与 ABI。** 明确支持的分组/依赖 ABI、onBindEditTextListener 的 headless 方法子集、未知 Preference 子类/Activity 的呈现方式，以及是否需要提升 host ABI。Source 原子类可按已支持基类描述，不能用通用对象替换原对象；不为旧协议或旧 AOT 增加兼容回退。

## 按完整链路实施

### 1. 正式合同与运行时适配

- [ ] 在 `control.proto` 定义描述、typed 编辑/点击请求与结果，在 `business.proto` 定义非敏感设置的确认状态、条件写入和错误；统一生成 TS/Dart，接入运行时校验、预算及跨语言 golden。
- [ ] 新增项目自有 HostPreferences，保留原 PreferenceScreen、原具体子类和 listener；快照绑定原 Source 实例、Source ID、generation。先验证路径、类型、选项和 enabled/visible，再调用原对象，不接受旧快照或重复/非法更新。
- [ ] change listener 返回 true 后才做该控件的默认保存；返回 false 不默认持久化输入，但仍重读原树和实际存储变化。click listener 独立执行，保留其消费点击的返回值；不把显示动作自动变成普通设置写入。
- [ ] 分别处理默认值、已存值和控件当前状态，使 getter、summary、选项和 Source 实际读取一致。支持回调修改其它控件及实际别名存储键，避免只实现 UI key → 输入值。
- [ ] 补必要的分组、依赖和 headless 编辑 ABI；支持范围内执行原 bind/change 回调，超出范围明确不支持，不以吞异常或伪造 Android Activity 成功掩盖缺口。
- [ ] 经现有 driver/manager 与 Dart transport 接入正式控制链；遵守 requestId/generation、超时、取消、active cancel 回收和迟到结果处理。修改 owned Java 类使用现有隔离依赖适配，保持原 JAR 不变。

### 2. D1 权威与确认顺序

- [ ] 新增独立 Source 设置表及正式 API，使用既有 Drizzle 生成迁移路径；复用已验证身份、account revision、CAS 和 mutation UUID/请求摘要/持久确认记录。确认读取不得隐式重放未确认写入。
- [ ] 打开扩展时先有界读取该包所需的 D1 确认设置，在 hostLoad/createSources 之前注入 `source_$id`，覆盖构造函数、lazy client 和 headers 的读取。不能先构造 Source，再仅更新界面或依赖下一次读值碰巧生效。
- [ ] 一次编辑调用原 Source 回调，取得有界存储变化与更新后描述，再按明确同步策略形成业务草稿。确认前不显示已保存；不得用运行时内存中的新值冒充服务端确认。宿主编辑响应丢失时不自动重放回调，明确未知状态并重开读取确认值，不承诺 Source 任意外部副作用的恰好一次执行。
- [ ] 等待写入确认期间阻止继续使用受影响的 Source。丢 ACK 保留冻结 UUID/body/CAS，显式重试只重发业务请求，不能重跑 Source listener 或点击动作；另一客户端新 revision、旧 ACK 和重复 mutation 均按已有确认语义处理。
- [ ] 冲突、放弃或无法确定回调收尾时回收受影响运行时，从 D1 当前状态重新注入并构造；不尝试通用回滚 Source 任意对象或外部网络副作用。哪些失败保留可重试草稿、哪些只允许读回/重开，在合同中明确。
- [ ] 非敏感设置刷新先走简单的排空/重开路径，清理旧 filters、分页和资源引用，避免旧 lazy 状态继续生效；复用现有阅读关闭与运行槽生命周期，处理仍在使用该 Source 的阅读页面。

### 3. Flutter 产品入口与恢复

- [ ] 在正式浏览 Source 入口提供设置页，保留已确认值和当前草稿的区别；按生成模型呈现开关、文本/密码、单/多选、分组、依赖和动作，显示客户端专属值及不支持项。
- [ ] 编辑、取消表单、提交、拒绝、CAS 冲突、丢响应、显式重试和只读刷新均有明确路径；不把“重新打开”变成重复执行任意回调的隐藏重试。
- [ ] 修改生效后刷新描述及受影响浏览结果；依赖项 enabled/visible、动态 summary 与原 Source 一致。密码/token 不出现在普通同步正文或日志中，原 Source summary 可能回显凭证时也需遵守显示策略。
- [ ] 切换部署、身份、包、Source 或 generation 后关闭旧表单、清理其草稿和敏感会话值，拒绝迟到结果；未确认草稿不承诺关闭后恢复。

## 证据与真实候选

调查基于固定 submodule：Keiyoushi `efa93f5a3537856fe830450bbe33f69d21d28167`、Suwayomi `6b481e8b62938b9c060eb210b934e0fbfdfa466b`。seed 身份见[工具链锁](../../runtime/teavm/toolchain-lock.json)：`teavm-runtime-release9-v1` 中 `host-44fb93b22828.jar`。已用该锁定 JAR 的 javap 字节码核对，而非假定当前上游源码就是 seed 行为；忽略目录中的研究源码不作为新正式模块的依赖。

| 证据/候选                                                                                                                                                                                                                                                                | 已核实事实与用途                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| [ConfigurableSource](../../vendor/suwayomi-server/server/src/main/kotlin/eu/kanade/tachiyomi/source/ConfigurableSource.kt)、[Keiyoushi Preferences](../../vendor/extensions-source/core/src/main/kotlin/keiyoushi/utils/Preferences.kt)                                  | setupPreferenceScreen 与 `source_$id` 存储约定；Source ID 不能丢 Long 精度。                                  |
| [TeaHost](../../runtime/teavm/java/src/main/java/prototype/TeaHost.java)、[driver](../../packages/runtime-host/src/teavm-driver.ts)                                                                                                                                      | 当前 init → load → Source 调用顺序；需在构造原 Source 前引入确认设置。                                        |
| [现有依赖适配](../../tools/teavm/build.ts)、[上游 Preference](../../vendor/suwayomi-server/AndroidCompat/src/main/java/androidx/preference/Preference.java)、[上游设置调用](../../vendor/suwayomi-server/server/src/main/kotlin/suwayomi/tachidesk/manga/impl/Source.kt) | owned 类由构建隔离替换依赖同名类；上游 stub 与 seed 存在差别，不直接套用上游先保存后回调的行为。              |
| [AsuraScans](../../vendor/extensions-source/src/en/asurascans/src/eu/kanade/tachiyomi/extension/en/asurascans/AsuraScans.kt)                                                                                                                                             | 单开关隐藏付费章节，适合首个非敏感设置在线闭环。                                                              |
| [MangaFire](../../vendor/extensions-source/src/all/mangafire/src/eu/kanade/tachiyomi/extension/all/mangafire/MangaFire.kt)                                                                                                                                               | 多选、summary 和 mergeChapters → preferOfficial 的 enabled 依赖，要求保留原回调与原对象。                     |
| [MangaKatana](../../vendor/extensions-source/src/en/mangakatana/src/eu/kanade/tachiyomi/extension/en/mangakatana/MangaKatana.kt)                                                                                                                                         | 控件 key 为 `server_preference`，listener 实际写 `SERVER_PREFERENCE`，验证别名写入与重开生效。                |
| [ClownCorps](../../vendor/extensions-source/src/en/clowncorps/src/eu/kanade/tachiyomi/extension/en/clowncorps/ClownCorps.kt)                                                                                                                                             | 多选确认后清缓存并返回 false，不能先保存再忽略 veto。                                                         |
| [Mangamo](../../vendor/extensions-source/src/en/mangamo/src/eu/kanade/tachiyomi/extension/en/mangamo/Mangamo.kt)、[CoronaEx](../../vendor/extensions-source/src/ja/coronaex/src/eu/kanade/tachiyomi/extension/ja/coronaex/CoronaEx.kt)                                   | 普通文本 token 与 password/email 编辑；凭证修改回调会清 token，验证敏感分类和回调写入边界。                   |
| [KomgaUtils](../../vendor/extensions-source/src/all/komga/src/eu/kanade/tachiyomi/extension/all/komga/KomgaUtils.kt)                                                                                                                                                     | bind 回调还使用 TextWatcher、error、rootView/Button；仅有 inputType 适配不能宣称任意 Android 编辑行为已支持。 |

这些是源码候选，不是运行可用名单。编译后仍按 `compiled_unverified` / `runtimeReady=false` 管理，直到相应真实链路通过；筛选或默认浏览的既有证据不能覆盖 preferences。

## 验收门

- [ ] TS/Dart 合同与 Java oracle：原子类保留、默认值/false/空集合、合法选项、重复/非法路径、整体预算、listener-veto、click、别名写入、依赖与 summary 刷新；SharedPreferences Editor 和监听器语义有实际断言。
- [ ] 官方 workerd + 真实 D1：同身份另一客户端读回、不同身份隔离、CAS 冲突、原 UUID/body 重试只应用一次、旧 ACK 不覆盖新值；普通 API 明确拒绝不属于同步策略的值，不能靠日志脱敏掩盖正文泄漏。
- [ ] 正式 Dart/Flutter 控制与业务链：D1 值在 Source 构造前生效；丢 ACK 不重跑回调；只读刷新不重放 pending；关闭/取消/换身份及迟到响应不复活旧状态；未确认草稿有明确可恢复路径。
- [ ] 按确定后的 ABI 本地重建固定候选 AOT，通过正式入口验证开关、单/多选、文本/密码、veto、别名、依赖及刷新；如源站不可用，记录具体失败和未通过门，不用 supplier 结果替代。
- [ ] 同一身份的 Web 与独立 Native 客户端读取并修改非敏感值后收敛，重开 Source 使用服务端确认值；敏感凭证不随另一端设置同步。Web/iOS/Android 分别记录实际通过范围。
- [ ] 扩展自定义 Activity/不支持的 bind 行为明确提示，受影响项失败不冒充保存成功，也不破坏其余可用浏览路径。

实现后的设计、可复验命令、构建身份及分项实际结果另行维护；本计划的调查与任务勾选不代替运行证据。
