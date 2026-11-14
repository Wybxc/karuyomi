# Mihon 布局与配色对照验证

2026-11-14，进行中。范围见[30 组页面矩阵](../design/mihon-cupertino-fidelity.md)，待办见[实施计划](../plan/mihon-cupertino-fidelity.md)。本轮尚未通过逐页像素、最终 Cupertino 或生产验收。

[逐状态截图状态机](mihon-state-coverage.md)现为参考采集进度入口，分别记录每个状态的浅/深图和缺口；本记录继续汇总实际工程与运行证据。`f0f648b` 的测试辅助代码大括号提示及 `44fa79d` 的两项旧色值断言已修复；`a894832` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43541437961)与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43541443714)均完整通过，分支未部署。这项工程结果不替代逐页视觉验收。

## 已取得的依据

- Karuyomi 从 `33dfb2ec51d8e0ad787a90f1146da59cdafecfc4` 起步；已有恢复发布证据不重复计为本轮视觉对齐通过。
- GitHub 官方 release API 与发布页确认当前稳定版为 Mihon v0.21.3；submodule 实际 HEAD 为 `feadad5e1e2bf638be6e2ca317d11657b09d4596`。
- 已查看同一提交 fastlane 中四张 864 × 1920 官方截图，分别为书架、阅读器、更新、历史。后两者属于当前缺失功能对照；现有其余页面暂为源码依据，不能称有逐像素实拍对照。
- 固定 `TachiyomiColorScheme.kt` 与 `UiPreferences.kt` 确认 DEFAULT 浅/深角色和 Monet 的设备依赖。已提取颜色表，尚未据此宣布应用全部表面和状态完成迁移。
- `LazyLibraryGrid.kt` 的自适应最小列宽为 128dp、额外内容 padding 为 8dp；`CommonMangaItem.kt` 的格间距为 4dp、封面标题区渐变占高度的 0.33、标题 padding 为 8dp。上游截图采用的具体列数和密度须与实际画面核对，不能直接把这些 dp 当作 PNG 物理像素。
- `flutter test --no-pub --concurrency=1 test/theme/app_theme_test.dart`：本机 Flutter 3.50 / Dart 3.14 的 3 项主题测试通过。覆盖系统浅/深、已确认主题覆盖系统、实际导航标题/实色按钮和各文字角色的至少 4.5:1 对比；这项结果不覆盖尚未接入的页面表面。
- 用户已允许本机参考模拟器；复用仓库 Android SDK 与 API 36 arm64 镜像，单实例 `mihon-reference` 已启动完成，720×1600、320dpi，即 360×800 逻辑视口，2 核/2GB。官方 arm64 APK 的 SHA-256 与发布页一致：`0026bd25ce5b1c6bdc5bd2c9589a08a811ddc4fa7c994cf937729d5b7010619d`。早期采集仍为 Monet，不能算固定主题证据；随后在外观页明确选中第一张 DEFAULT 卡，`settings-appearance-default-dark` 确认卡片选中及背景采样 `#1B1B1F`。后续带 `default-dark` 的有效截图据此采集。系统顶部 68dp、底部约 24dp 单独计量。
- 书架与源内作品已从行列表改为惰性封面网格，保持 2:3 封面、底部标题、独立续读、选择与菜单。普通 Source 缩略图尚无正式资源通道，仍为占位；仅已有账户自定义封面读取已验证字节，不能将占位图称为真实封面验收。
- 本机单并发运行 `flutter test --no-pub --concurrency=1 test/library test/browse/source_browse_page_test.dart test/browse/manga_cover_tile_test.dart test/migration/migration_controller_test.dart test/theme/app_theme_test.dart`：**70 项通过**，无命中警告。覆盖分类/CAS/确认、隐藏选择与部分提交、续读和身份变化、源查询失败/取消/迟到丢弃、迁移入口、主题，以及双倍字号下封面的打开/长按与独立续读触控范围。改动文件严格分析通过；完整工程检查仍由分支 CI 验证。
- 首个里程碑 `b138967` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43523374793) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43524983955) 均通过；包含 747 项 Dart、531 项 TypeScript/Workers、严格分析、格式、生成和 Web 构建。分支未部署。
- 参考模拟器已采集固定深色的书架有内容/选择/选项、分类管理/创建、作品详情/章节选项、扩展列表/信任/详情、MangaDex 偏好/单选及空仓库列表。`cover-view-default-dark` 实际仍为详情页、`extension-details-selected-default-dark` 实际仍为扩展列表，不能按文件名计为对应证据；后者另有真实的 `mangadex-details-default-dark`。Source 扩展只用于 Mihon 参考，不计为 Karuyomi 兼容性验收。
- Codex 内置浏览器在官方 Wrangler 隔离 harness、真实临时 D1、`categories` fixture 下采集 `b138967` 的 360×800 浅色书架和设置基准。书架工具约占首屏 300px，封面从约 y350 开始；设置字段全部纵排。当前紧凑工具和分组实现据此修正，尚待新 CI 产物渲染。fixture 不代表生产 Access 或真实 Source。
- 后续定向 `test/settings/settings_widgets_test.dart test/browse/chapter_list_navigation_test.dart test/browse/chapter_read_navigation_test.dart` **22 项通过**。覆盖设置草稿与原始 CAS、章节搜索清空、重复章节定位、选择范围、部分确认、身份退役及迟到 Source 页关闭；Sliver 搜索布局断言和未匹配选择被隐藏均已修复后复验。
- `test/settings/settings_navigation_test.dart test/data/source_favorites_repository_test.dart test/library/library_resume_test.dart` **25 项通过**。设置在身份/服务替换后重新展开正确草稿，源收藏与阅读偏好不受主题保存影响；包含响应丢失后原命令重试、独立续读及元数据说明与对应作品关联。
- `test/sources/source_filters_widget_test.dart test/reader/reader_screen_test.dart` 在修正旧色值断言后 **37 项通过**。继续检查 typed 筛选草稿、应用/取消、失败恢复，以及阅读背景改变时的页位、已解码观察和资源驻留；不以降低断言要求修复 CI。
- 使用 `a894832` 的真实 CI Web 产物，在同一官方 Wrangler 隔离 harness、临时 D1、`categories` fixture 及内置浏览器下采集 360×800 浅/深书架与设置。封面起点已从旧基准约 y350 压至约 y175；外观草稿保持原主题，收到服务端确认后切换深色，实际观察通过。图为 `karuyomi-a894832-library-{light,dark}.jpg`、`karuyomi-a894832-settings-{light,dark}.jpg`、`karuyomi-a894832-theme-draft-light.jpg`。尚无逐元素叠图或真实 Source 证据。
- 上述深色实看发现扩展搜索占位文字对比不足、展开箭头仍为系统蓝。当前改动逐处接入输入框占位/表面/图标颜色；展开处直接组合 Flutter 官方 `Expansible` 与 `CupertinoListTile`，显式使用强调色、展开语义及减少动态设置，通过 Hooks 释放控制器。没有修改依赖缓存或新增通用组件包装；实际新产物的浏览器复验仍待完成。
- `flutter test --no-pub --concurrency=1 test/settings/settings_widgets_test.dart test/extensions/extensions_controller_test.dart test/search/cross_source_search_page_test.dart test/settings/settings_navigation_test.dart test/settings/native_service_origin_test.dart`：**49 项通过**。新增双主题用例在系统亮度与确认主题相反的条件下检查实际搜索占位文字/背景至少 4.5:1 对比、清空恢复、展开箭头颜色、减少动态效果和折叠后草稿保留；既有 CAS、结果未知、身份替换及资源释放回归保留。此为本机组件测试，不是原生现场或全状态视觉证据。
- 已核对固定主题的书架/分类双主题联系表，以及深色章节筛选/排序/显示/多选/已读与未读、阅读工具/模式/书签/设置/滤镜及图片操作/封面确认的实际 PNG。分类空态、空重命名和无分类提示已补齐浅色。状态机已纠正“封面确认取消返回图片操作面板”，新增实际发现的章节更多、亮度与色彩滤镜参考节点；附加参考不自动扩大本轮产品功能范围。单侧截图、设置下方未滚动段、章节书签及未确认的转换保持待办。
- 配色修复 `a55bc5f` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43545660729) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43545668341) 均完整通过，分支未部署。已取其真实 Web artifact，通过同一官方隔离 harness、临时 D1、`categories` fixture，在内置浏览器复验 360×800 浅/深扩展搜索占位、输入、无匹配及清空恢复；设置草稿保持原主题，服务端确认后切换深色，设置分组、服务连接及扩展诊断展开箭头采用强调色。证据为 `karuyomi-a55bc5f-extensions-{light,dark}.jpg`、`karuyomi-a55bc5f-settings-{light,dark}.jpg`、`karuyomi-a55bc5f-theme-draft-light.jpg`、`karuyomi-a55bc5f-extensions-empty-dark.jpg`、`karuyomi-a55bc5f-connection-dark.jpg` 和 `karuyomi-a55bc5f-extension-diagnostics-dark.jpg`。该产物不包含后续紧凑阅读工具。
- 阅读器将正常刷新、重新阅读、完成、书签刷新和章节排序收拢至选项菜单，保留相邻章节、书签和设置主操作；错误、待确认及重试入口仍外露。阅读模式与单双页选择在窄屏和大字号下换行，保持原视口观测与恢复链。普通长选择列表补齐搜索颜色角色。这些实现尚待新 CI 产物的实际双主题复验。
- 本机低优先级、单并发定向回归分别通过：阅读路由/进度导航/Access 恢复/书签导航/设置导航 **38 项**，`reader_screen_test.dart` **34 项**，`choice_field_test.dart` **6 项**，合计 **78 项不同用例**。新增浅/深 × 1x/2x、360×800 和长中文用例核对画布空间、菜单可达及打开菜单不触发业务写入。精确重试仍先断言原请求体与应用次数；恢复提示收起后新增的真实视口观测按正常 debounce 另行确认，使用新 mutationId。没有修改业务写入控制器来规避测试。
- `eda0531` 的完整 CI 暴露两处仍查找旧章节排序控件的测试：书架直接续读及详情状态迟到恢复。两处均改为实际打开阅读选项菜单、核对唯一选中的排序并关闭菜单；原页位、Source occurrence、身份和资源关闭断言保留。对应 `library_resume_test.dart`、`chapter_list_navigation_test.dart` **10 项通过**。修复提交 `4474318` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43549899282) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43549903312) 均完整通过；首轮失败仍按失败保留，分支未部署。
- 新增并实际核对章节多选/已读/未读/书签增删、图片操作与设置封面确认的浅深色联系表，以及阅读设置模式和常规的滚动末端。图片动作底层工具显示条件已统一；取消封面确认返回图片操作面板。源列表/置顶/语言启用/源操作、已安装扩展及 xkcd 热门新增深色实拍，单主题仍待补齐；全部缺口继续见状态机。
- 后续补齐并实看源列表/置顶/语言上段/源操作、已安装与可安装扩展、扩展搜索空态/清空恢复/更多/筛选空目录、xkcd 热门/搜索无结果的双主题主图。仓库空态、空/有效地址、scheme 校验错误、真实“处理中…”、成功列表和移除确认/取消/完成也均有双主题主图。08.05 的语言启用条件尚不一致，键盘存在拼音/English 系统变体，未记作同条件完成；新发现的筛选独立空态已加入 08.12 节点，瞬时加载以实际 PNG 为准。
- 使用 `4474318` 的真实 CI Web 产物，在官方 Wrangler 隔离 harness、临时 D1、`acceptance-owner`、无 fixture 数据下，从扩展安装 xkcd 1.6.1，经真实 Source 热门、详情打开 `/3319/`（Elevators）并展示插件处理后的实际图片。360×800 浅/深主画布、阅读选项菜单和本漫画设置已成对实看；菜单切换反向排序再恢复来源顺序后仍在第 1 页。实际翻到第 2 页时截到等待确认，随后显示已保存；从菜单完成本章后重载独立文档，详情显示已读，重进同章恢复第 2 页。随后重新阅读回到第 1 页以统一主图条件。主题草稿保持浅色、服务端确认后切深色。另核对 720×800 深色阅读画布，宽屏截图时因视口重新观测短暂显示待确认。全部为隔离 Web 证据，不代表生产 Access 或真机性能。
- 上述截图为 `karuyomi-4474318-reader-{light,dark}.jpg`、`karuyomi-4474318-reader-menu-{light,dark}.jpg`、`karuyomi-4474318-reader-settings-{light,dark}.jpg`、`karuyomi-4474318-reader-pending-light.jpg`、`karuyomi-4474318-reader-last-{light,dark}.jpg`、`karuyomi-4474318-reader-reverse-light.jpg`、`karuyomi-4474318-chapter-read-dark.jpg` 与 `karuyomi-4474318-reader-wide-dark.jpg`。对应主画布和菜单联系表已实看；设置图发现调暗继承开关仍用系统绿色，不能将该图记为配色完成。
- 开关修复 `f8b7bc5` 通过官方主题参数启用强调色，并在现有四个开关调用点指定选中滑块/开启标签的对比色；保留关闭态白色滑块和业务回调。低优先级、单并发运行主题、设置、Source 偏好、扩展与章节导航 **42 项通过**；[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43553468108) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43553472010) 均通过，分支未部署。
- 复用 `f8b7bc5` 的真实 CI Web 产物，在官方 Wrangler 隔离 harness、临时 D1、`acceptance-owner`、无 fixture 数据下，以内置浏览器核对 360×800 浅/深扩展启用及停用、章节仅书签开关/空结果、漫画调暗继承及未保存草稿。扩展停用/重新启用均获服务端确认；浅色为蓝轨道/白滑块，深色为浅蓝轨道/深蓝滑块，关闭为白滑块。全局深色草稿保持原浅色，保存确认后切换深色；xkcd `/3319/` 真实图片、独立文档书架读回和同章续读仍正常。未实际提供开关的 xkcd Source 偏好不计为 Source toggle 浏览器验收；该调用点当前仅有组件回归。
- 开关证据为 `karuyomi-f8b7bc5-extension-{enabled,disabled}-{light,dark}.jpg`、`karuyomi-f8b7bc5-chapter-switch-{light,dark}.jpg`、`karuyomi-f8b7bc5-reader-settings-draft-{light,dark}.jpg` 及 `karuyomi-f8b7bc5-reader-settings-restored-dark.jpg`，对应联系表已实看。扩展启用截图顶部操作回执不同，章节图存在收藏/续读与滚动位置差异，当前只计颜色/状态核对，不计同数据同位置像素叠图。初次 `reader-settings-dark` 截到打开动画，排除稳定弹层基准；后续恢复继承的深色图已实看。视口已恢复，本轮 harness 已停止，参考模拟器已暂停。
- Mihon 参考补齐 MangaDex 扩展详情启用分项、内容警告、Source 偏好上下段/单选/多选/文本的双主题图。多选修改后取消重开未选、确认重开已选；非法 UUID 显示真实错误且确定禁用，合法值确认重开保留，空值合法且可确定。测试后恢复原偏好。Android Preference/View 的浅色弹层容器与 Compose 不同，系统键盘也单独记录；不修改上游来统一截图。
- MangaDex 真实热门、最新、精确搜索 `one piece` 的成功结果，以及 typed filter 的 group/check/select/sort/tri-state 已补双主题并实看。三态不限制/包含/排除和文本空值/非法/有效已在状态机拆成独立节点。筛选收起后保留未应用草稿、重开仍选中，点击筛选才查询；图中的“取消”已改为真实收起转换，Karuyomi 的显式取消仍按合同丢弃。冷启动浅色图仅截到路由动画、text filter 未提供、分页/错误等仍待补；不因其他双主题主图已取得而涂绿整组。
- 后续仅在 Mihon 参考模拟器断网，补齐 12.07 首次失败/离线重试/联网恢复，以及 12.09 追加失败保留列表/底部持久错误条/恢复重试的双主题 PNG；12.01 的重试加载也实际截到旋转指示。错误为连接参考代理失败，不是生产故障；12.08 的追加加载指示仍未截到。网络设置已恢复，模拟器再次暂停。
- 跨源搜索的双主题查询/范围、真实加载旋转帧、MangaDex 成功及 Local source/xkcd 空结果、仅显示有结果和网络错误已实看；联系表为 `global-search-reference-pairs.jpg` 与 `global-search-filter-pair.jpg`。加载使用 PNG 先拍、XML 后采，不能以 XML 后续成功结果冒充加载布局。Mihon 没有独立重试按钮且同查询重复提交未重发，状态图已纠正；混合成功/失败、打开作品和联网恢复等转换仍待。参考模拟器网络已恢复并暂停。
- Karuyomi 跨源结果区去除重复内缩卡片，源名/语言/状态集中展示，作品改为 96dp 横向卡片、标题在封面下方且随字号增高；开始有效查询后收键盘，原控制器、限额、显式重试、取消与资源关闭链未变。低优先级、单并发运行 `flutter test --no-pub --concurrency=1 test/search/cross_source_search_page_test.dart test/search/cross_source_search_controller_test.dart test/theme/app_theme_test.dart`，**24 项通过**，其中新增浅/深 × 1x/2x 的 360×800 混合成功/空/错误布局及精确作品打开；测试先等待输入焦点布局稳定，再滚动到按钮，无命中警告。严格分析、完整 CI 和新产物的浏览器复验另记，不能将组件通过当成像素对齐。
- 后续将卡片标题空间改按实际 12px 字体的缩放计算三行高度，避免 Android 非线性缩放下按 54px 大字估计而少留空间；同组新增浅/深非线性缩放用例后 **26 项通过**。`33b8cb0` 两个改动 Dart 文件严格分析、完整格式、依赖检查及标准 prek hook 通过；该提交已推送，新高度修正的 CI/渲染另记。
- `b826249` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43569548608) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43569554520) 均完整通过，分支未部署。复用该 Web artifact，在官方 Wrangler 隔离 harness、临时 D1、`acceptance-owner`、无 fixture 数据下，以内置浏览器核对 360×800 浅/深空书架、跨源范围、真实旋转帧、xkcd 空结果与 Komiic 局部失败；浅色只重试 Komiic 后，xkcd 已返回状态保留。主题草稿保持原浅色，服务端确认后切深色。
- Komiic 默认 `komiic.com` 在两主题均返回原始 HTTP 500，页面长堆栈挤走重试，且单操作源分组的无障碍名称混入错误正文。随后沿原 Source 偏好正式选择已有 `komiic.cc`，实际显示设置已确认及热门作品；再以同样的 xkcd en/Komiic 和查询 `航海王`，两主题均返回 xkcd 0 项、Komiic 3 项。打开《ONE PIECE航海王》得到作者尾田榮一郎及 238 章，返回后原查询和三项结果保留。未修改上游业务、JAR 或正式网络边界，备用镜像的成功不覆盖默认镜像失败记录。
- 证据为 `karuyomi-b826249-library-empty-{light,dark}.jpg`、`karuyomi-b826249-cross-{scope,start,results,mixed-error,open,return}-{light,dark}.jpg`，另有浅色 `cross-error-retry` 和 `theme-draft-light`。加载和成功联系表已实看。两主题首张作品按钮 DOM 矩形相同：`x=8,y=462,width=96,height=202`；封面比例和内边距另有组件断言，普通封面仍占位。内置浏览器截图实际编码为 JPEG，已按真实格式命名，压缩色值不作为精确配色采样或 1 物理像素叠图证据。视口已恢复，隔离 harness 已停止。
- 后续按正式 `RuntimeException.code` 映射简短错误，原始 `toString()` 保留在“错误详情”弹层；源分组采用显式子节点，每个动作/作品分别合并自己的语义，避免源正文被并入按钮。全局停止获确认后清除旧停止失败及诊断。低优先级、单并发运行搜索页面/控制器/主题 **29 项通过**，含浅深色各 100 行堆栈、重试在 360×800 内可达、按钮名称、完整诊断和关闭不请求、原目标/查询/页重试、停止失败后全局停止恢复。四个改动文件严格分析通过；新修复产物的完整 CI 与浏览器验收仍待，不用旧产物成功图替代。

- 错误呈现修复 `07342fb` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43572665095) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43572669079) 均完整通过，含完整工程检查与 Web/候选 Wasm 构建，分支未部署。复用其正式 Web artifact，在同一官方 Wrangler 隔离 harness、临时 D1、`acceptance-owner`、无 fixture 数据、360×800 下，以 xkcd en / Komiic 和 `航海王` 取得双主题真实加载、HTTP 500 短说明、完整诊断与关闭、单源重试和全局停止确认。两主题重试按钮 DOM 均为 `x=8,y=588,width=106.359375,height=57`，名称只含自身动作；单源重试画面保留 xkcd 已返回的空结果。主题草稿仍保持浅色、保存确认后切深色。
- 最新证据为 `karuyomi-07342fb-cross-{start,error,diagnostic,retry,stopped}-{light,dark}.jpg` 及 `theme-draft-light.jpg`，三张 `cross-{start,errors,operations}-pairs.jpg` 联系表均已实看。完整堆栈保留 HTTP 500 与全部原始 frame；关闭后仍在原失败，未因查看自动重试。超长诊断的实际浏览器滚动、无请求的独立网络审计、停止 ACK 失败恢复和非空结果保留仍待分项；组件与控制器的 29 项回归独立保留。浏览器视口已恢复，harness 已停止；此轮未重放备用镜像成功或生产 Access，不覆盖 `b826249` 的既有证据与默认镜像失败。
- 参考模拟器补齐全局阅读设置六段滚动、默认阅读模式/取消、高级首屏、应用/设备诊断及 Android 后台任务诊断的浅深主图；`settings-reference-pairs-0.jpg` 至 `settings-reference-pairs-5.jpg` 均实看。首屏、末段、诊断与选择弹层两主题 XML 布局一致，中间阅读设置段约有 3–15 物理像素滚动差。Worker info 的横向正文滚动已有双主题图；复制浅色只截到空容器，深色为含测试任务 ID 开头的系统预览，完整内容仍待独立校验。状态机拆分 28.02/28.03/28.04，未将 Mihon 的 WorkManager 当作 Cloudflare Worker。模拟器保持暂停。
- 参考后续补齐未加载/信任/取消、来源关闭/排序/恢复、系统卸载确认/取消、存储首屏/占用/清理后及高级三段的双主题图，`extension-storage-pairs-0.jpg` 至 `extension-storage-pairs-6.jpg` 均实看。关闭来源实际排到末尾，重新启用回首行；清理前两侧均 165 kB、稳定清理后均 1.37 kB。系统卸载框两侧都是 Android English 浅色，且调用点底层不同；深色取消后首次 PNG 仍为旧帧，已排除并重拍稳定返回图。中段高级设置约有 14 物理像素滚动差，末段相同。未改变安装权限、网络/日志保护或执行卸载，原信任和来源启用均恢复。其它未加载原因、加载失败诊断、下载/安装/更新、确认卸载及清理失败继续待采；两端都没有独立清理确认，已按实际调用点删除假设节点。细分证据与文件名见状态机；模拟器暂停在深色 MangaDex 详情。

原始 XML、PNG、下载及临时日志位于忽略目录 `.local/mihon-reference/`；参考采集命令使用固定模拟器 `adb -s emulator-5574 shell uiautomator dump` 与 `exec-out screencap -p`。终端访问 GitHub 发布附件需使用本机已配置的网络代理；最初的部分下载均未通过完整性门槛，不作为参考安装输入。

## 导航、混合分类与阅读的后续分项

- `514640a` 的 [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43577545653) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43577549234) 均完整通过；该次仅更新参考记录，不重下载和编译相同 Web。分支仍未部署。
- 手机横屏 800×360dp、平板 768×1024dp 的书架/浏览/更多，以及设置双栏取得浅深主图，四张导航/设置联系表均实看。横屏手机仍为底部导航，平板才进入侧栏；横屏浏览正文滚动位置不同、设置深色多出纯黑模式行，分别排除整页同位置叠图。尺寸/旋转已恢复原值。
- 混合分类清空草稿的确认已取得双主题图，确认后退出多选，a 为空、默认包含两部作品；只为 One Piece 恢复 a 后，默认仅 xkcd、a 仅 One Piece，b 保持空。`categories-transition-pairs-0.jpg` 至 `categories-transition-pairs-2.jpg` 均实看，未修改混合值直接确认仍待。
- 同一 xkcd 3322 Dragonfly 的初始载入、断网失败返回/toast、联网重开成功、页码 1→2→1、真实图片双击放大/复位均取得双主题图。源码确认初始失败会退出阅读器，不能与画布内图片错误合并；新增章节过渡加载/失败、首尾无相邻章、工具切章等待等独立待办。连续瞬态 PNG 有采样时间，稍后的 XML 不当作同帧几何。单页失败、空页、拖动中反馈及章节过渡仍未实测；网络已恢复，模拟器已暂停。
- 据实拍接入独立侧栏表面，并让 768×1024dp 平板使用侧栏、800×360dp 手机横屏保留底栏。阅读上下工具按固定 3dp 表面及原浅深透明度，在已确认画布上预先合成不透明颜色；保留黑/白/跟随主题背景及资源链路。低优先级、单并发 **15 项**导航/配色/阅读回归通过，六个改动 Dart 文件严格分析无问题。`27476c0` 的完整 CI 与正式 Web 分项复验已完成，范围和限制见下一节。

### 27476c0 正式 Web 的双主题分项

- [push CI](https://github.com/Wybxc/karuyomi/actions/runs/43582163732) 与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43582170931) 均完整成功；push 的候选 Wasm 构建也成功。复用其正式 Web artifact，逐项校验39个 Flutter 清单条目的长度和哈希，未在本机重新编译 Flutter/AOT。正式 Vite/Static Assets 组装核对64个公开文件和两个当前扩展，再经官方 Wrangler harness、临时 D1、acceptance-owner、无 fixture 验收。分支未部署。
- 内置浏览器核对800×360横屏底栏、768×1024平板侧栏与切换尺寸后保留设置入口，两主题均有真实画面。横屏书架导航按钮的 DOM 矩形为 x=0,y=310,width=266.6640625,height=50；平板书架按钮为 x=0,y=44,width=148,height=57。书架与浏览的同数据深色图在收藏/安装后重拍；更早空书架或无源图不与有内容浅色图作全页叠图。侧栏148dp与参考80dp、设置分栏以及标题位置仍未通过像素门槛。
- 同一真实 xkcd 3322 Dragonfly 第一页，在两主题分别确认黑/白/跟随应用主题背景；上下工具使用同一表面，页码始终1/2、进度显示服务端已保存。六张图在 x=12,y=180,width=330,height=330 的实际图片区域解码后相同，区域 SHA-256 为 `5767c70e5bb3682923463f1998037a4b19e2141d097b3a56430891851027f6da`；这只证明截图范围的图片内容与位置未变，不替代资源释放、真机或性能证据。
- 全局主题选择浅色时，草稿仍显示深色，保存获服务端确认后才变浅；随后确认切回深色。漫画背景修改也先保存确认再关闭。确认后的三类画布各有成对图：`karuyomi-27476c0-reader-{black,white-stable,theme}-{light,dark}.jpg`；联系表 `karuyomi-27476c0-reader-pairs-{0,1}.jpg`、导航的 `karuyomi-27476c0-navigation-{landscape,tablet}-pairs.jpg` 均已实看。过渡关闭帧不当稳定主图，采用 white-stable；原始截图字节实际为 JPEG 4:2:0，已只修正后缀，没有重新编码原图。纯色采样约有1–2级通道差，不能据此宣称无损色值或1像素叠图通过；颜色常量、合成与对比另有组件检查。
- 首次打开 Source 曾显示“运行容器已中断，请重新连接”，显式重试后得到真实作品、元数据与图片。中断和恢复分别保留为 `karuyomi-27476c0-source-{interrupted,recovered}-dark.jpg`，未查明首次中断原因；不得记为首次打开稳定成功。视口已恢复默认，harness已正常关闭，参考模拟器保持暂停。此轮不重放生产 Access 或新文档续读，不覆盖旧版本的对应证据。

迁移与作品参考本轮补齐20.03–20.08/20.10、21.01以及16.02/16.04/16.06/17.01的双主题主图，详细文件、取消/返回与未通过转换见[状态机](mihon-state-coverage.md)。这不表示 Karuyomi 的迁移页面已完成渲染对照或迁移提交验收。

### 侧栏几何与内容保留的后续修复

`27476c0` Web 中的148dp文字行已改为80dp侧栏，采用24dp图标、图标选中容器及下方标签、60dp常规触控行及4dp间距；保留三个真实入口并垂直居中，不为复刻参考的五项增加空入口。侧栏从窗口顶部延伸，标题栏限定在正文区；文字放大自然增高，超过高度时可滚动。

低优先级单并发20项导航与主题回归及两个改动Dart文件的严格分析通过：两种亮度、五类尺寸、侧栏宽度/图文相对位置/选中语义、双倍字号，以及尺寸与系统亮度变化后的输入值/光标/焦点和字段元素身份保持。原导航到阅读、迟到章节关闭和认证恢复用例也通过。补充两主题大字复验，确保侧栏不共享正文主滚动控制器。

`a9538f1` 的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43586898652)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43587055996)完整成功。正式Web artifact的39个Flutter清单条目经长度/哈希校验，Vite组装核对64个公开文件及两个当前扩展；复用官方Wrangler harness、临时D1、acceptance-owner、无fixture，在内置浏览器核对三入口的双主题平板/手机横屏画面。两主题平板按钮均为x=0、width=80、height=60，三个y依次418/482/546，活动项的`aria-current=true`；横屏设置按钮为x=533.3333,y=310,width=266.6641,height=50。浅色草稿经过平板→横屏→平板仍保留，保存确认后才切浅；再次确认深色。浅色源目录输入“草稿”的值、末尾光标2/2和焦点跨两次尺寸变化保留。这项实际桌面Web输入证据不代替移动IME或真机验收。

三入口联系表`karuyomi-a9538f1-navigation-{tablet,landscape}-pairs.jpg`均已实看，原图为JPEG，只作有损画面证据，不计无损色值或一像素叠图。设置两侧的已确认主题字段值不同，限定对照导航区域；设置分栏及其它页面几何仍待。本轮没有安装或执行Source，也未重放生产Access/新文档续读；视口恢复，harness已关闭。

复验另发现：离开已编辑的源目录后，可访问树仍包含零尺寸的旧搜索框及“提交”，重开目录出现重复搜索标签。固定Flutter 3.50的Web引擎会为默认启用自动填充的文本框保存dormant form，`autofillHints:null`的输入则不创建该表单。当前修复在九个检索字段直接禁用自动填充；长选项查询改用可明确传入该参数的官方CupertinoTextField，并保留清空/搜索操作和主题表面。25项导航/选择定向回归与十个改动Dart文件严格分析通过，验证平台输入配置不含autofill及离页释放连接。该修复的完整CI与新Web可访问树复验仍待，不因旧画面正常而记作已修复验收。

### 实拍布局与颜色锚点

以下为实际 PNG/XML 的物理像素，两主题的列举矩形相同；320dpi 下除以 2 得逻辑单位。导航手机横屏为 1600×720，平板为 1536×2048，分类/阅读为 720×1600，不能把不同尺寸叠成同一视口。

| 场景与元素           | 布局矩形 `(left, top, right, bottom)` |
| -------------------- | ------------------------------------- |
| 手机横屏书架标题     | `(168,80,256,144)`                    |
| 手机横屏底栏书架标签 | `(253,620,311,660)`                   |
| 平板侧栏书架标签     | `(51,855,109,895)`                    |
| 平板正文书架标题     | `(192,206,280,270)`                   |
| 平板首作品标题       | `(200,741,415,777)`                   |
| 混合分类草稿标题     | `(88,617,280,687)`                    |
| 阅读工具 xkcd 标题   | `(112,152,204,208)`                   |
| 阅读页码滑杆         | `(154,1332,566,1420)`                 |

平板侧栏背景 `(10,500)` 为浅 `#E9EEFB` / 深 `#272931`，手机横屏底栏 `(400,610)` 为 `#F3EDF7` / `#211F26`；正文仍为 `#FEFBFF` / `#1B1B1F`。黑色阅读画布上，稳定上下工具背景主要色为 `#DDE2EE` / `#23252C`；上游 `ReaderAppBars.kt` 是 3dp 表面再叠加浅 0.95 / 深 0.9 的 alpha，不能当作任意画布上的原始角色。白色/跟随主题背景目前仅有源码计算与组件验证，原生参考另待。此节只建立对应基准，尚未与本次 Karuyomi 正式产物叠图。

## 08–11 扩展与存储参考基准

以下来自固定 DEFAULT、720×1600/320dpi 的实际 PNG/XML，两主题对应布局矩形一致；只计 Mihon 基准，还未与 Karuyomi 同状态叠图。系统卸载弹层不是应用配色证据，且浅色由未信任列表、深色由详情打开，背景差异单列。

| 元素                      | 物理像素布局矩形 `(left, top, right, bottom)` |
| ------------------------- | --------------------------------------------- |
| Android 安装权限横幅      | `(0,376,720,480)`                             |
| 未加载分组标题            | `(32,496,688,536)`                            |
| 未加载 MangaDex 名称      | `(160,576,296,616)`                           |
| 信任弹层标题              | `(88,641,376,711)`                            |
| 信任弹层说明              | `(88,743,632,903)`                            |
| 信任动作                  | `(545,979,603,1019)`                          |
| 末尾关闭的 Afrikaans 名称 | `(32,1464,168,1520)`                          |
| 存储占用组标题            | `(32,816,147,856)`                            |
| 清理章节缓存标题          | `(32,1080,224,1136)`                          |
| 清理前缓存值              | `(32,1136,209,1172)`                          |

安装权限横幅实测为浅 `#BA1A1A` / 深 `#FFB4AB`；信任弹层容器为 `#FCF7FF` / `#292730`。关闭来源的开关轨道实色为 `#FCF7FF` / `#302E38`、滑块/描边主要色为 `#757780` / `#8F9099`。这些是具体控件的角色，不等于页面背景或任意错误文字；最终 Cupertino 开关保留白色关闭滑块的差异见设计说明。清理 toast 截到淡入，不用于稳定合成色测量。

## 12.07 参考像素基准

对 `s1207-source-network-error-{light,dark}.png/.xml` 的实际测量。两图均为 720×1600、320dpi；下表是物理像素，除以 2 得逻辑单位。布局矩形取实际 XML 文字节点；字形矩形由 PNG 在该区域内与已知纯色背景作差，右/下边界不包含在内。五个锚点在两种主题下相同；随机表情和系统栏不参与。这里只确立 Mihon 基准，未与 Karuyomi 对应状态叠图。

| 元素          | 两主题布局矩形 `(left, top, right, bottom)` | 两主题字形矩形           |
| ------------- | ------------------------------------------- | ------------------------ |
| MangaDex 标题 | `(112, 172, 321, 228)`                      | `(115, 183, 320, 225)`   |
| 错误说明      | `(135, 884, 586, 924)`                      | `(138, 892, 585, 915)`   |
| 重试标签      | `(118, 1044, 176, 1084)`                    | `(120, 1051, 175, 1079)` |
| WebView 标签  | `(286, 1044, 435, 1164)`                    | `(302, 1051, 420, 1159)` |
| 帮助标签      | `(545, 1044, 603, 1084)`                    | `(547, 1051, 601, 1079)` |

背景 `(10, 800)` 实测为浅色 `#FEFBFF` / 深色 `#1B1B1F`；标题字形主要实色为 `#1B1B1F` / `#E3E2E6`，重试标签为 `#0058CA` / `#B0C6FF`，与固定角色一致。此分支错误说明的合成后主要字色为 `#4E4D51` / `#B6B6BA`，不等于通用次级文字或错误红色；须保留控件透明度/语义差异，不能只凭全局色值宣布对应状态配色完成。

## 15 跨源搜索参考像素基准

`s1503-global-top-{light,dark}.png/.xml` 均为固定 DEFAULT、720×1600/320dpi、`one piece`，滚动至内容顶部。实际 XML 中首组源名矩形为 `(32,370,188,418)`，语言为 `(32,418,63,450)`，首封面为 `(24,482,200,746)`，首作品标题为 `(32,754,144,826)`。两主题矩形相同；封面 176×264 物理像素，即 88×132dp，外层卡片 96dp、列表间距 4dp；首三张封面起点分别为 x24/224/424。标题最少两行、最多三行，不能用源内叠图标题替代。

源名背景及实色字形实测为浅色 `#FEFBFF` / `#1B1B1F`、深色 `#1B1B1F` / `#E3E2E6`。上述是 Mihon 参考基准；Karuyomi 的额外状态行、显式提交/停止/分页和 Cupertino 字体度量须分别核对，尚未完成同状态叠图。

## 26–29 设置与诊断参考基准

以下均为固定 DEFAULT、720×1600/320dpi 的实际 PNG/XML，两主题布局矩形一致。表中为物理像素；全局阅读设置中间段须先对齐滚动位置，不能套用首屏一致的结论。

| 元素                 | 布局矩形 `(left, top, right, bottom)` |
| -------------------- | ------------------------------------- |
| 全局默认阅读模式标题 | `(32,296,224,352)`                    |
| 当前右到左模式值     | `(32,352,256,388)`                    |
| 模式选择弹层标题     | `(88,481,376,551)`                    |
| 模式选择第一项       | `(184,607,481,655)`                   |
| 模式选择当前第二项   | `(184,703,481,751)`                   |
| 模式选择取消         | `(545,1139,603,1179)`                 |
| Worker info 标题     | `(112,172,336,228)`                   |
| Enqueued 标题        | `(32,280,178,328)`                    |

全局阅读设置的背景实测为浅 `#FEFBFF` / 深 `#1B1B1F`，标题实色为 `#1B1B1F` / `#E3E2E6`，当前值的合成后字色为 `#4E4D51` / `#B6B6BA`。开启轨道为 `#0058CA` / `#B0C6FF`，开启滑块为白色 / `#002D6E`。模式选择弹层容器为 `#FCF7FF` / `#292730`，选项字形为 `#44464F` / `#C5C6D0`，选中指示为强调色；不能拿页面表面或反转颜色替代弹层角色。此处仅建立 Mihon 参考，还没有对应 Karuyomi 同状态叠图。

## 仍需的证据

全部 ID 的参考画面和像素基准、布局复刻前后叠图、配色对比、自然 Cupertino 调整、最终多视口/亮暗/文字/输入核对、完整工程检查和真实业务验收仍待完成。Mihon 参考模拟器与 Karuyomi 原生现场验收分开记录；不使用已停止的真机流程填补本轮 Web 证据。
