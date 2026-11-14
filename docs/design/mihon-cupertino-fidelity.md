# Mihon 逐页布局与配色对照

2026-11-13，用户要求逐一对照 Mihon 与 Karuyomi 的界面，先按像素核对布局，再放松复刻中的硬编码尺寸，采用 Cupertino 的自然设计规范；随后补充配色系统同样需要参考。用户确认本轮改造全部现有界面，Mihon 中缺失的功能列入后续计划，不为它们添加空入口。

实施及验收分别维护在[计划](../plan/mihon-cupertino-fidelity.md)与[验证记录](../verification/mihon-cupertino-fidelity.md)。本文件记录对照依据和设计，不将源码推导或计划当作实际渲染通过。

页面矩阵进一步展开为[逐状态截图流程图](../verification/mihon-state-coverage.md)。每个状态分别跟踪浅色与深色，所有状态及取消/重试/确认转换都纳入；Karuyomi 独有的服务端状态单列验收。两种主题不共用一个“已截图”标记。

## 固定参考

Mihon 采用官方稳定版 **v0.21.3 / `feadad5e1e2bf638be6e2ca317d11657b09d4596`**，通过只读参考 submodule [vendor/mihon](../../vendor/mihon) 固定。所有下述 Kotlin 文件均以该提交为准；不编译或修改上游业务实现。官方[发布页](https://github.com/mihonapp/mihon/releases/tag/v0.21.3)与[使用指南](https://mihon.app/docs/guides/getting-started)作为入口依据。

官方仓库的 `fastlane/metadata/android/en-US/images/phoneScreenshots/` 提供书架、阅读器、更新和历史四张 864 × 1920 PNG。它们证明对应画面的像素外观，不能当作所有页面的截图；未有截图的页面继续从固定源码提取结构、布局参数和颜色角色，并另行取得渲染证据。截图中的系统留白、字体比例和应用内容分别记录，不将物理像素直接当作 Flutter 逻辑像素。

Karuyomi 起点是已恢复 Cupertino 的生产提交 `33dfb2ec51d8e0ad787a90f1146da59cdafecfc4`，源码与先前已验收的 `d7416f0` 相同。现有交互和服务端状态是功能基线，所有页面都纳入，不能仅重做书架或浏览入口便宣布完成。

## 页面对应关系

Mihon 的展示源码根为 `app/src/main/java/eu/kanade/presentation/`；表中按这个根写相对路径。阅读路由和设置中原有的业务能力继续保留。

| ID  | Karuyomi 现有页面或独立操作面        | Mihon 对照                                                                                              | 布局和状态核对重点                                               |
| --- | ------------------------------------ | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 01  | 应用导航、三入口及宽屏侧栏           | `ui/home/HomeScreen.kt`、`more/MoreScreen.kt`                                                           | 标题/操作靠近顶部，活动入口与正文层次；只保留已有三个入口        |
| 02  | 书架、空态、加载/失败                | `library/components/LibraryContent.kt`、`LibraryCompactGrid.kt`、`LazyLibraryGrid.kt`                   | 封面网格、标题叠层、续读、初次空态和局部失败                     |
| 03  | 书架搜索、排序、分类范围             | `LibraryToolbar.kt`、`LibraryTabs.kt`、`library/LibrarySettingsDialog.kt`                               | 顶部工具与范围紧邻内容，避免大段纵向操作挤走首屏                 |
| 04  | 书架多选、批量分类/移出及部分提交    | `LibraryToolbar.kt`、`manga/components/MangaBottomActionMenu.kt`、`library/DeleteLibraryMangaDialog.kt` | 选择栏、数量和底部操作；隐藏选择、结果未知和部分失败继续可见     |
| 05  | 分类管理、创建/重命名/排序/删除      | `category/CategoryScreen.kt`、`category/components/CategoryDialogs.kt`                                  | 紧凑列表、行操作与编辑确认；忙碌和未确认草稿                     |
| 06  | 单作品分类选择                       | `manga/components/MangaDialogs.kt`                                                                      | 当前多选、取消/保存和范围；不在列表常驻每项操作                  |
| 07  | 漫画源目录、收藏源、语言筛选         | `browse/SourcesScreen.kt`、`SourcesFilterScreen.kt`、`browse/components/BaseSourceItem.kt`              | 分组列表、源名/语言和单个尾部操作，搜索与筛选入口                |
| 08  | 扩展分组列表、搜索、语言筛选         | `browse/ExtensionsScreen.kt`、`ExtensionFilterScreen.kt`                                                | 需处理/已安装/可安装，图标、名称、元数据和主操作同一行           |
| 09  | 扩展详情、安装/更新/启停/卸载        | `browse/ExtensionDetailsScreen.kt`                                                                      | 扩展摘要、源列表、操作和进行/失败状态；账户与本机状态分开        |
| 10  | 仓库列表、添加预览、移除确认         | `more/settings/screen/browse/components/ExtensionStoresScreen.kt`、`ExtensionStoresDialogs.kt`          | 列表、地址输入/预览和明确确认；不暴露构建诊断细节                |
| 11  | 本机扩展存储与清理                   | `more/settings/screen/SettingsDataScreen.kt`                                                            | 名称/占用/清理，使用中和失败就地提示；账户安装关系保留           |
| 12  | 源内热门/最新/搜索、分页、空态       | `browse/BrowseSourceScreen.kt`                                                                          | 搜索/模式工具、封面网格、首屏/追加/刷新分别反馈                  |
| 13  | typed Source 筛选、重置/取消/应用    | `browse/components/BrowseSourceDialogs.kt`、`ui/browse/source/browse/SourceFilterDialog.kt`             | 可滚动字段、固定操作区、草稿与已应用条件                         |
| 14  | Source 偏好及文本/多选编辑           | `ui/browse/extension/details/SourcePreferencesScreen.kt`                                                | 设置分组、行内当前值、选择或编辑页、确认状态                     |
| 15  | 跨源搜索准备、选择范围、分源结果     | `browse/GlobalSearchScreen.kt`                                                                          | 搜索在顶、每源标题与横向预览，局部状态和停止入口                 |
| 16  | 作品详情、收藏/续读/元数据           | `manga/MangaScreen.kt`、`manga/components/MangaInfoHeader.kt`                                           | 封面与标题/作者同区、主操作、简介与标签层级                      |
| 17  | 章节列表、搜索/筛选/排序、局部失败   | `manga/components/MangaChapterListItem.kt`、`MangaToolbar.kt`                                           | 章节标题、次级资料、已读/书签与紧凑操作                          |
| 18  | 章节书签、范围已读/未读              | `manga/components/MangaBottomActionMenu.kt`、`MangaDialogs.kt`                                          | 选择与确认、部分成功和原操作恢复；状态不能只靠颜色               |
| 19  | 自定义封面、预览/恢复默认/上传确认   | `manga/components/MangaCoverDialog.kt`                                                                  | 大图预览、明确动作、上传/保存/失败区分                           |
| 20  | 迁移目标、目标搜索与选择             | `browse/MigrateSourceScreen.kt`、`MigrateSearchScreen.kt`                                               | 从原作品到目标源/作品的连续导航，保留原选择                      |
| 21  | 迁移只读预览、章节映射和确认         | `ui/browse/migration/manga/MigrateMangaScreen.kt`                                                       | 原/目标对应信息、映射选择、提交摘要与冲突                        |
| 22  | 阅读画布、工具显隐、页码与跳转       | `reader/appbars/ReaderTopBar.kt`、`ReaderBottomBar.kt`、`ReaderAppBars.kt`                              | 画布占主面积，工具贴近上下边界，不用长表单压缩图片               |
| 23  | 阅读章节/模式/缩放工具、书签         | `reader/ReaderPageActionsDialog.kt`、`reader/appbars/`                                                  | 主操作常驻，次操作入面板；键盘、触屏和鼠标可达                   |
| 24  | 本作品阅读设置、覆盖/继承            | `reader/settings/ReaderSettingsDialog.kt`、`ReadingModePage.kt`、`GeneralSettingsPage.kt`               | 设置分组、当前范围、固定保存/关闭，确认前不应用                  |
| 25  | 图片查看/放大、失败/重试             | `manga/components/MangaCoverDialog.kt`、`reader/ReaderContentOverlay.kt`                                | 内容自适应、操作不遮图、独立失败与退出                           |
| 26  | 全局设置、外观、阅读布局与输入偏好   | `more/settings/screen/SettingsMainScreen.kt`、`SettingsAppearanceScreen.kt`、`SettingsReaderScreen.kt`  | 分类入口/分组行、当前值和说明；不把所有字段纵向铺在根页          |
| 27  | 服务连接、登录与失效/无权限恢复      | `webview/WebViewScreenContent.kt`、通用错误状态                                                         | Karuyomi 特有业务；对齐页面骨架与颜色，不仿制不存在的 Mihon 登录 |
| 28  | 诊断、运行时恢复、性能记录工具       | `more/settings/screen/debug/DebugInfoScreen.kt`、`WorkerInfoScreen.kt`                                  | 次级入口、分组信息和明确动作；主流程不暴露内部字段               |
| 29  | 少量选择菜单、长选项搜索页           | 通用 `AppBarActions`、`components/`、设置选择控件                                                       | 当前选择、搜索/取消、键盘焦点、长中文与双倍字号                  |
| 30  | 全部编辑 Sheet、确认框与业务状态提示 | `category/components/CategoryDialogs.kt`、`manga/components/MangaDialogs.kt`                            | 正文可滚动、底部操作可达、未确认/冲突/结果未知持续可见           |

以上路径中的 `ui/` 指 `app/src/main/java/eu/kanade/tachiyomi/` 下的路由实现。所有 ID 均须分别记录常态与相关状态，不用根页面的截图代替二级页面。

Mihon 的更新/日历、历史、下载队列及下载设置、统计、tracker 绑定/搜索/状态/章节/评分/日期选择与移除、笔记、备份创建/恢复、安全/隐私设置、本地漫画、应用语言、设置全局搜索、引导/版本更新、开源许可及数据库清理/备份 schema 等独立界面，Karuyomi 当前没有相应业务入口。它们已纳入差异清单，本轮按用户选择列作后续能力；不向已有设置页复制无效开关或假数据。通用 WebView 不代表 Karuyomi 已有站点登录，原生 Access 只覆盖自身服务认证。

## 配色系统

采用 Mihon `TachiyomiColorScheme.kt` 的固定 DEFAULT 主题作为跨平台参考。Mihon 在支持设备上默认可能使用 Monet，其结果依赖 Android 壁纸和系统，不将某台设备的动态颜色当作所有平台唯一默认，也不增加跨端壁纸采集。

| 角色                         | 浅色      | 深色      | 用途                                       |
| ---------------------------- | --------- | --------- | ------------------------------------------ |
| 强调色 primary               | `#0058CA` | `#B0C6FF` | 可操作文字、活动图标、进度与未读标记       |
| 强调色上的文字 onPrimary     | `#FFFFFF` | `#002D6E` | 实色主按钮和强调徽标                       |
| 选中容器 primaryContainer    | `#D9E2FF` | `#00429B` | 活动导航、已选项目背景                     |
| 选中容器上的文字             | `#001945` | `#D9E2FF` | 选中图标与标签                             |
| 基底 background/surface      | `#FEFBFF` | `#1B1B1F` | 页面与普通滚动正文                         |
| 正文 onSurface               | `#1B1B1F` | `#E3E2E6` | 标题与主文本                               |
| 次级文字 onSurfaceVariant    | `#44464F` | `#C5C6D0` | 作者、语言、辅助说明与未选导航             |
| 分组表面 surfaceContainerLow | `#F7F2FA` | `#1E1C22` | 轻量分组与封面占位                         |
| 工具表面 surfaceContainer    | `#F3EDF7` | `#211F26` | 导航与工具区域                             |
| 侧栏表面（3dp）              | `#E9EEFB` | `#272931` | 平板导航，区别于底部导航表面               |
| 分隔 outlineVariant          | `#C5C6D0` | `#44464F` | 行边界和内容层次                           |
| 错误 error                   | `#BA1A1A` | `#FFB4AB` | 失败信息和危险操作                         |
| 成功/可用 tertiary           | `#006E1B` | `#7ADC77` | 已有业务所需的成功标记，不能代替服务端确认 |

应用持有的页面、文字和状态按语义角色使用动态颜色，不能仅替换主按钮色。阅读中用户明确选择的黑/白背景保持其业务值，“跟随应用主题”使用上述表面与文字；封面文字渐变继续保证叠图对比，不把图片本身染色。主/次文字、强调控件、选中态和错误态分别检验对比度；颜色不作为唯一状态信号。

Cupertino 开关通过官方 `applyThemeToAll` 使用强调色轨道，四处业务调用直接设置选中滑块和开启标签为 `onAccent`，关闭滑块保留 Cupertino 白色。深色的浅蓝轨道搭配深蓝滑块，避免默认白色滑块与轨道对比不足；不为这些参数新增通用开关包装。

最终使用官方 Cupertino 控件的文字、路由、触控和无障碍习惯。保留上述 Mihon 色系及层次，将每种状态映射到 Cupertino 的背景、tint、label 和分隔语义，不恢复玻璃、模糊或额外渲染采样。系统弹层允许采用自然的 Cupertino 分组表面；差异逐项记录，不能将平台默认纯黑/绿色混入而不说明。

双主题实拍确认 Mihon 的侧栏使用 `surfaceColorAtElevation(3.dp)`，底部导航使用 `surfaceContainer`。阅读工具也取 3dp 表面，但 `ReaderAppBars.kt` 再按浅色 0.95、深色 0.9 的透明度合成；在默认黑色阅读背景上的最终色为 `#DDE2EE` / `#23252C`。这些是特定背景上的合成色，不能当作全局原始角色。Karuyomi 根据已确认的黑/白/跟随主题阅读背景，预先计算上下工具栏的不透明合成色，避免 Cupertino 因半透明背景启用额外的模糊；图片和阅读背景仍按各自设置呈现。白色/跟随主题背景的最终原生参考仍待采，源码计算与组件验证单列。

内置浏览器当前返回 JPEG 4:2:0 截图，纯色采样可能有约1–2级通道差。原始字节和格式如实保留，色值常量/合成检查与有损画面证据分开；不能把有损截图采样称作无损色值对齐。Mihon ADB 的无损PNG与Web JPEG也不直接混作同精度像素比较。

## 当前布局落点

导航根据窗口形状适配：竖屏宽度至少 700dp、横屏短边至少 600dp 才进入侧栏；800×360dp 的手机横屏继续使用底栏，768×1024dp 的平板使用侧栏。布局切换保留当前入口，浅深色均检查。Mihon 的三种入口分别取得手机横屏与平板参考，设置双栏另列状态；Karuyomi 侧栏仍采用现有 148dp 的文字行，参考的 80dp 图标/标签侧栏尚未完成几何对照，不能由配色和分支接入推断像素验收通过。

书架和源内作品按可用宽度采用最小 128dp 封面列宽、4dp 间距、8dp 外边距及 2:3 比例；列数随容器自然变化。书架搜索、排序和选择在同一工具行，管理分类及刷新在更多菜单，多选操作固定在底部。隐藏选择、未确认和部分提交信息继续单独可见。

作品详情采用 100×150 的封面参考锚点，将标题、作者、画师及源名与封面并排；主操作随后显示，简介默认三行并可展开。章节选项默认收起，选择、待确认、错误和未匹配选择会强制显示，章节搜索始终可达。Cupertino 标题、触控和表单按内容增高，不固定整页坐标。

设置选择使用“标题＋当前值＋尾部指示”的官方列表行；全局设置按外观、阅读显示和输入分组展开，漫画覆盖仍在编辑面板中分组。分组共用同一个草稿及其原始 revision；保存结果、未确认和冲突提示放在分组外，避免收起后隐藏。惰性 Sliver 中的搜索采用 CupertinoTextField 的官方前缀/清空能力，避免 CupertinoSearchTextField 在滚动重布局时读取 dirty RenderObject 的问题。

Mihon 的 Source 筛选实测在返回收起后保留未应用草稿，重新展开恢复该值，点击筛选才查询。Karuyomi 的显式“取消”按已有合同丢弃草稿，应用成功才更改目录；这是操作语义差异，不能为了外观复刻静默改变。Source 偏好的单选、多选、文本与筛选分别对照；文本是否允许空值由实际偏好约束确定，不一律把空输入禁用。

跨源搜索按源展示紧凑标题、语言/状态/数量及横向作品，去掉结果区的重复内缩卡片。参考卡片宽 96dp、内边距 4dp，封面实际为 88×132dp；标题置于封面下方，最多三行，行高随文字缩放增加，完整标题仍作为打开按钮语义。源名和状态行按内容增高，加载、失败、空结果分别保留；已有单源重试/分页、停止确认及清理失败入口继续可见。普通 Source 封面仍为占位，不绕过宿主直接读取缩略图 URL。Mihon 的已置顶/全部和有结果筛选属于参考流程，Karuyomi 继续使用明确选源及语言范围，不增加尚无业务需要的筛选入口。

跨源运行时失败按正式错误码给出简短说明，完整原始诊断保存在独立的“错误详情”弹层；不让 Java/JavaScript 堆栈挤走单源重试。源分组信息与作品、停止、重试操作分别建立无障碍节点；查看诊断本身不触发请求。停止确认后清除之前的停止失败提示，原查询及其它源的结果继续保留。

迁移参考已细分源列表、作品选择、目标选源、无选源、快捷菜单、实际搜索加载/结果/空/失败及迁移确认。Mihon 的确认弹层仅显示可迁移的数据选项与显示作品/共存/迁移，原/目标身份来自调用上下文；Karuyomi 继续明确展示原作品、目标作品、只读章节映射及提交影响。其当前流程先确定原章节范围，再选择单个目标Source，不为复制参考的多源配置而改变业务合同。

扩展参考中，未信任风险提示、其他未加载原因和加载失败诊断是不同弹层；Android 安装权限横幅、系统卸载框及复制反馈也分别记录。系统窗口不由 Mihon 应用主题控制，不将其默认配色直接搬进共享 Cupertino 页面。Mihon 关闭单个来源后按启用状态将其排到末尾，重新启用回到启用分组；Karuyomi 的账户确认状态和 Source 生命周期继续按自身合同呈现，不能由行移动推断已保存。

存储清理两端都直接操作可丢弃缓存，没有独立确认弹层。布局包含明确范围、占用和就地反馈，使用中/失败/取消与释放确认继续分别展示；不为对齐参考增加无业务需要的确认流程。Mihon 清理后保留 cache journal，参考占用非零不能当作失败；Karuyomi 的扩展副本与 Mihon 章节图片缓存也不是同一种材料，只比较同类信息结构。

## 两个实施阶段与证据

先为每个 ID 固定相同视口、数据和状态，记录参考截图或源码依据、密度、内容边界、主要元素矩形、行间距、基线和颜色采样。布局复刻阶段逐个核对锚点，归一化后固定锚点误差目标不超过 1 个物理像素；对同状态叠图核对，内容、字体及图标差异单列，不能用总体近似掩盖关键控件错位。缺少参考截图时标为“源码对照”，不能称像素验收通过。

再在已对齐的布局上放松硬编码尺寸：封面保留内容比例、网格按可用宽度排布、工具/表单按内容自然增高、普通行与标题使用 Cupertino 文本度量及触控区域、弹层尊重键盘和安全区。保留 Mihon 的区域顺序、视觉重心、颜色层次和操作分组；不用固定整页高度或绝对坐标维持截图。只交付一套正式界面，不维护旧布局回退或永久“复刻模式”。

最终逐页覆盖 360px、参考窄屏、宽屏、浅/深色、长标题/中文、双倍文字、键盘占位和减少动态效果。原始参考、阶段布局和最终 Cupertino 截图分别保留，以可见证据说明哪些尺寸自然化以及原因。书架/设置/阅读的状态、CAS、身份隔离、取消、迟到结果、资源关闭和独立新文档续读仍用原正式链路验证。
