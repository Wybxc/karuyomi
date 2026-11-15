# Mihon 逐页布局与配色对照

2026-11-13，用户要求逐一对照 Mihon 与 Karuyomi 的界面，先按像素核对布局，再放松复刻中的硬编码尺寸，采用 Cupertino 的自然设计规范；随后补充配色系统同样需要参考。2026-11-14 进一步明确：两阶段计划不变，最终导航、控件、颜色角色和转场均须自然 Cupertino，配色方案也改为 Cupertino 版本。用户确认本轮改造全部现有界面，Mihon 中缺失的功能列入后续计划，不为它们添加空入口。

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

### 最终 Cupertino 语义配色

最终交付直接采用固定 `cupertino_ui` 中的官方语义颜色，在当前已确认主题、对比度和界面层级中解析；不把 Mihon 的 Material DEFAULT 色值套入 Cupertino 组件。依据 Apple 的[颜色](https://developer.apple.com/design/human-interface-guidelines/color)、[列表](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)与[标签栏](https://developer.apple.com/design/human-interface-guidelines/tab-bars)规范，信息层级仍完整保留，视觉角色使用以下映射。

| 角色           | Cupertino 来源                         | 用途                             |
| -------------- | -------------------------------------- | -------------------------------- |
| tint           | `activeBlue` / 默认主题 `primaryColor` | 可操作文字、活动图标、进度       |
| 强调色上的文字 | `white`                                | 官方实色主按钮与强调徽标         |
| 选中容器与文字 | `tertiarySystemFill` / `label`         | 设置双栏的当前栏目及已有选择区域 |
| 页面基底       | `systemGroupedBackground`              | 分组界面与滚动正文               |
| 正文与辅助文字 | `label` / `secondaryLabel`             | 标题、作者、语言与说明           |
| 分组表面       | `secondarySystemGroupedBackground`     | 官方列表组、封面占位             |
| 导航与工具表面 | 不透明 `systemBackground`              | 页面导航、标签栏、阅读上下工具   |
| 分隔           | `separator`                            | 列表和内容层次                   |
| 危险与错误     | `destructiveRed`                       | 失败文字、危险操作               |
| 成功与开关开启 | `activeGreen` / 官方开关默认值         | 可用标记、标准绿色开关           |

普通浅/深色下，系统蓝分别为 `#007AFF` / `#0A84FF`，分组背景为 `#F2F2F7` / `#000000`，分组表面为白色 / `#1C1C1E`；这些只是默认解析值，源码不复制常量。提高对比度与弹层层级仍由官方动态颜色解析。`CupertinoThemeData` 保留默认文字样式与 `applyThemeToAll=false`，删除四处强制轨道/滑块色，恢复官方开关配色。颜色不能承担唯一状态信号，保存、失败与选中仍有文字或语义。

用户选择的黑/白阅读背景保持业务值，“跟随应用主题”使用对应应用语义表面与文字。上下工具独立使用不透明系统背景，不再按 Material elevation 或画布混色；封面叠图保留必要的黑色渐变和白字对比，不给内容图片染色。不恢复 Liquid Glass、模糊或额外渲染采样。

应用根节点在Navigator之外同样绘制已确认主题的分组背景，覆盖Sheet缩放底层页面后露出的区域；不依赖浏览器/原生宿主底色，也不禁用官方Sheet转场。Web manifest的静态启动背景与主题色采用默认浅色分组背景`#F2F2F7`，替换Flutter模板蓝；它是安装元数据，不代表运行时已确认主题或深色启动画面验收。

### 第一阶段 Mihon 参考色值

下表保留已采集的像素对照依据，不能用作最终产品配色。Mihon `TachiyomiColorScheme.kt` 的固定 DEFAULT 主题作为第一阶段参考；支持设备上的 Monet 依赖 Android 壁纸和系统，不增加跨端壁纸采集。

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

第一阶段曾用上述色值及 `applyThemeToAll` 对齐控件，历史提交和截图保留。双主题实拍确认 Mihon 侧栏使用 `surfaceColorAtElevation(3.dp)`，底部导航使用 `surfaceContainer`；阅读工具再按浅色 0.95、深色 0.9 合成，默认黑色画布上的最终色为 `#DDE2EE` / `#23252C`。这些是特定背景上的参考合成色，不能当作全局原始角色或最终 Cupertino 目标。白色/跟随主题背景的最终 Mihon 参考仍待采，源码计算与组件验证单列。

内置浏览器当前返回 JPEG 4:2:0 截图，纯色采样可能有约1–2级通道差。原始字节和格式如实保留，色值常量/合成检查与有损画面证据分开；不能把有损截图采样称作无损色值对齐。Mihon ADB 的无损PNG与Web JPEG也不直接混作同精度像素比较。

## 当前布局落点

第一阶段 `a9538f1` 的80dp侧栏几何与双主题正式Web证据保留。最终三个入口统一使用官方 `CupertinoTabBar`，移除 Material 风格的窄侧栏、图标胶囊与 elevation 表面；平板空间由页面内部的目录/详情分栏使用。标签栏和当前项语义采用官方实现，保持一个根业务 Navigator 与当前入口挂载策略；内容身份稳定，尺寸或主题变化保留入口、草稿、光标与焦点。设置内部只管理目录/详情层级，不为每个标签保留隐藏的 Source 业务树。

书架和源内作品按可用宽度采用最小 128dp 封面列宽、4dp 间距、8dp 外边距及 2:3 比例；列数随容器自然变化。书架搜索、排序和选择在同一工具行，管理分类及刷新在更多菜单，多选操作固定在底部。隐藏选择、未确认和部分提交信息继续单独可见。

作品详情采用 100×150 的封面参考锚点，将标题、作者、画师及源名与封面并排；主操作随后显示，简介默认三行并可展开。章节选项默认收起，选择、待确认、错误和未匹配选择会强制显示，章节搜索始终可达。Cupertino 标题、触控和表单按内容增高，不固定整页坐标。

设置选择使用“标题＋当前值＋尾部指示”的官方列表行。全局设置以外观、阅读显示、翻页与快捷键、服务连接和关于为目录；窄屏由正式 Cupertino 页面路由进入详情，可用导航返回和系统返回回到目录，沿用减少动态效果的淡化/禁用动画策略。平板在内容宽度与窗口短边均至少600dp时同时展示目录和详情。目录宽度采用可用宽度的一半、最多384dp，详情保持自然内容高度；判断不使用键盘压缩后的高度，避免软键盘改变平板分栏。目录直接使用官方 inset grouped 列表、行和 chevron，不加入未实现功能。

所有栏目共用一个内存草稿及其原始revision，切栏目、返回目录或切尺寸不隐式提交；保存/冲突/结果未知与精确重试继续走同一个控制器。Access失效原因和“服务连接与登录”在当前栏目可见，不能藏进另一栏目。目录和详情不重复显示同一重试操作；稳定的详情子树保留连接输入的焦点和光标。内层导航有独立语义容器，目录和详情均须从根无障碍树可达。设置说明放在官方分组页脚，调暗标签与滑块保持一组内容，避免说明、留白和控件之间出现多余分隔线。漫画覆盖仍在编辑面板中分组。配色分别使用正文、次级文字、强调、分组表面、按下容器和错误角色，两主题单独验收。此设计落点及组件回归不替代正式Web的画面与交互证据。

惰性Sliver中的搜索采用CupertinoTextField的官方前缀/清空能力，避免CupertinoSearchTextField在滚动重布局时读取dirty RenderObject的问题。固定Mihon的`ListPreferenceWidget.kt`采用可滚动单选列表，不提供查询；语言筛选的`SourcesFilterScreen.kt`和`ExtensionFilterScreen.kt`采用开关列表。Karuyomi的可搜索长选项和无匹配状态因此单列为产品独有状态29.K1/29.K2，不能伪造对应的Mihon参考图。

短选项使用官方菜单，打开时以autofocus将键盘焦点落到当前可用项；当前值不可用时选择首个可用项。操作菜单聚焦首个可执行动作，Enter可直接执行，Escape取消后返回触发按钮；不能只凭无障碍树显示focused推断真实Flutter焦点。仓库与本机存储的辅助说明采用官方CupertinoFormSection页脚获得13px次级文字，普通导航分组继续使用CupertinoListSection，不能假定后者会替footer设置说明层级。

当前固定的cupertino_ui中，CupertinoDialogAction没有键盘焦点入口，实际Web确认框及组件回归均已复现。保留CupertinoAlertDialog的内容、分隔与原始确认合同，动作直接使用官方CupertinoButton，以取得Tab、Enter和Space支持；危险动作使用系统红，默认动作仍加粗。沿用官方文字度量与自然按钮高度，不自制焦点包装或复制上游组件。确认前不能因导航或焦点变化提交操作。

检索输入显式设置`autofillHints:null`，避免Flutter Web为检索词保留离页后的自动填充合成表单。长选项查询同样直接使用官方CupertinoTextField及前缀/清空能力，不新增输入控件包装；编辑值、焦点、光标和输入连接分别验收。服务地址同样禁用自动填充，Web继续只读，Native保持可编辑；不把此项外推为其它配置/凭据编辑已验收。

Mihon 的 Source 筛选实测在返回收起后保留未应用草稿，重新展开恢复该值，点击筛选才查询。Karuyomi 的显式“取消”按已有合同丢弃草稿，应用成功才更改目录；这是操作语义差异，不能为了外观复刻静默改变。Source 偏好的单选、多选、文本与筛选分别对照；文本是否允许空值由实际偏好约束确定，不一律把空输入禁用。

跨源搜索按源展示紧凑标题、语言/状态/数量及横向作品，去掉结果区的重复内缩卡片。参考卡片宽 96dp、内边距 4dp，封面实际为 88×132dp；标题置于封面下方，最多三行，行高随文字缩放增加，完整标题仍作为打开按钮语义。源名和状态行按内容增高，加载、失败、空结果分别保留；已有单源重试/分页、停止确认及清理失败入口继续可见。普通 Source 封面仍为占位，不绕过宿主直接读取缩略图 URL。Mihon 的已置顶/全部和有结果筛选属于参考流程，Karuyomi 继续使用明确选源及语言范围，不增加尚无业务需要的筛选入口。

跨源运行时失败按正式错误码给出简短说明，完整原始诊断保存在独立的“错误详情”弹层；不让 Java/JavaScript 堆栈挤走单源重试。源分组信息与作品、停止、重试操作分别建立无障碍节点；查看诊断本身不触发请求。停止确认后清除之前的停止失败提示，原查询及其它源的结果继续保留。

迁移参考已细分源列表、作品选择、目标选源、无选源、快捷菜单、实际搜索加载/结果/空/失败及迁移确认。Mihon 的确认弹层仅显示可迁移的数据选项与显示作品/共存/迁移，原/目标身份来自调用上下文；Karuyomi 继续明确展示原作品、目标作品、只读章节映射及提交影响。其当前流程先确定原章节范围，再选择单个目标Source，不为复制参考的多源配置而改变业务合同。

扩展列表用官方`CupertinoListSection.insetGrouped`表达需要处理、已安装与可安装分组，行内容与尾部主操作采用两个并列的官方`CupertinoButton`，分别导航详情和安装、更新或管理；内容按钮中使用无独立操作的`CupertinoListTile`，避免嵌套按钮。仅给带尾部按钮的列表行设置`onTap`时，Web无障碍树会把该行变成不可聚焦的group，不能以触屏可点击代替键盘可达。名称和状态按内容换行，版本仅取当前精确构建或未安装候选，不把目录新版本误标为已安装版本。详情按扩展状态/启用与维护、包含的漫画源、按需诊断分组；卸载影响放在官方表单页脚，危险动作与错误采用Cupertino系统红。漫画源行与诊断展开项直接使用官方CupertinoButton包裹无onTap的列表行，并保留chevron；设置目录和跨源搜索范围同样提供真实键盘入口。独立操作与组标题建立各自语义边界，避免整组信息并入某个按钮。启停仍只响应开关，服务端确认和资源清理语义不变。官方边距、分隔与文字度量替代第一阶段的Material组标题及行包裹，不增加另一套列表组件。

源目录以官方inset grouped列表区分收藏与语言分组。打开源和收藏为并列官方按钮，收藏语义包含当前开关状态；不为拦截父级手势保留空GestureDetector。仓库与本机存储同样用官方分组表面、次级摘要与页脚说明，添加/刷新采用actionTextStyle，仓库移除用系统危险红。行内独立操作使用局部语义容器，名称只包含动作和对象，不能把其它行及页脚并入按钮；副本清理名称明确扩展，空的仓库影响列表显示“无”。仓库输入直接使用官方文本框动态装饰并禁用自动填充；仍先只读预览，再经明确确认写入账户。清理只删除可重新下载的本机副本，账户安装与阅读记录不变。

漫画源设置按原偏好树的顺序使用官方CupertinoFormSection分组；嵌套分组在外层分组结束后展开，不把圆角表单再嵌套进另一圆角表单。隐藏节点不改变原始操作路径，父级禁用继续传递。辅助说明采用次级文字和13px度量，错误使用系统红；每个开关、选项和动作保持独立语义，密码及会话设置仍不上传。

多语言扩展在摘要中显示语言数量，最多三种时直接列语言；精确版本和当前状态始终优先于完整语言列表，全部语言仍在语言筛选和漫画源清单可查。排序继续按完整语言资料，不因摘要缩短改变分组顺序。固定工具链的Web默认Enter派发`ButtonActivateIntent`，而当前`cupertino_ui`按钮只处理`ActivateIntent`；应用入口仅将Enter/小键盘Enter映射为后者，其余默认快捷键保留。真实Web键盘激活、文字输入与禁用操作继续分别验收，不能用原生组件测试的默认快捷键推断Web通过。

扩展参考中，未信任风险提示、其他未加载原因和加载失败诊断是不同弹层；Android 安装权限横幅、系统卸载框及复制反馈也分别记录。系统窗口不由 Mihon 应用主题控制，不将其默认配色直接搬进共享 Cupertino 页面。Mihon 关闭单个来源后按启用状态将其排到末尾，重新启用回到启用分组；Karuyomi 的账户确认状态和 Source 生命周期继续按自身合同呈现，不能由行移动推断已保存。

存储清理两端都直接操作可丢弃缓存，没有独立确认弹层。布局包含明确范围、占用和就地反馈，使用中/失败/取消与释放确认继续分别展示；不为对齐参考增加无业务需要的确认流程。Mihon 清理后保留 cache journal，参考占用非零不能当作失败；Karuyomi 的扩展副本与 Mihon 章节图片缓存也不是同一种材料，只比较同类信息结构。

## 两个实施阶段与证据

先为每个 ID 固定相同视口、数据和状态，记录参考截图或源码依据、密度、内容边界、主要元素矩形、行间距、基线和颜色采样。布局复刻阶段逐个核对锚点，归一化后固定锚点误差目标不超过 1 个物理像素；对同状态叠图核对，内容、字体及图标差异单列，不能用总体近似掩盖关键控件错位。缺少参考截图时标为“源码对照”，不能称像素验收通过。

再在各页已取得的对照上完成 Cupertino 自然化：封面保留内容比例、网格按可用宽度排布、工具/表单按内容自然增高、普通行与标题使用 Cupertino 文本度量及触控区域、弹层尊重键盘和安全区。复查导航、控件、颜色角色与转场，保留必要信息和清晰的操作分组，最终采用上述 Cupertino 配色；不能只改尺寸而留下 Material 与 Cupertino 混杂的结果。只交付一套正式界面，不维护旧布局回退或永久“复刻模式”。

最终逐页覆盖 360px、参考窄屏、宽屏、浅/深色、长标题/中文、双倍文字、键盘占位和减少动态效果。原始参考、阶段布局和最终 Cupertino 截图分别保留，以可见证据说明哪些尺寸自然化以及原因。书架/设置/阅读的状态、CAS、身份隔离、取消、迟到结果、资源关闭和独立新文档续读仍用原正式链路验证。
