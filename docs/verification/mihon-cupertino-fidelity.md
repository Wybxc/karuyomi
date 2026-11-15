# Mihon 布局与配色对照验证

2026-11-15，进行中。范围见[30 组页面矩阵](../design/mihon-cupertino-fidelity.md)，待办见[实施计划](../plan/mihon-cupertino-fidelity.md)。本轮尚未通过逐页像素、最终 Cupertino 或生产验收。

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

复验另发现：离开已编辑的源目录后，可访问树仍包含零尺寸的旧搜索框及“提交”，重开目录出现重复搜索标签。固定Flutter 3.50的Web引擎会为默认启用自动填充的文本框保存dormant form，`autofillHints:null`的输入则不创建该表单。修复在九个检索字段直接禁用自动填充；长选项查询改用可明确传入该参数的官方CupertinoTextField，并保留清空/搜索操作和主题表面。25项导航/选择定向回归与十个改动Dart文件严格分析通过，验证平台输入配置不含autofill及离页释放连接。

`ebcba1b`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43607632739)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43607635941)完整通过。39个Flutter清单条目经长度/哈希校验，Vite组装仍为64个公开文件、两个当前扩展；官方harness、临时D1、acceptance-owner、无fixture。内置浏览器360×800下分别确认浅色与深色，再各执行输入“草稿”→书架→重开源目录→输入“再次”→书架。两主题每次离页后DOM输入数均为0，实际AX树也没有旧搜索或提交；重开时精确标签的搜索框均只有1个。原始画面`karuyomi-ebcba1b-search-{editing,left}-{light,dark}.jpg`与`karuyomi-ebcba1b-search-cleanup.json`保留在忽略目录，控制台无warn/error，视口恢复且harness正常关闭。这是源目录离页/重进的实际Web证据，不外推为九个调用点、长选项、配置字段或移动IME全部验收通过。

### 设置目录与平板分栏

已把全局设置的内联展开改为五项目录和独立详情，平板同时保留目录与当前栏目；漫画覆盖仍使用原编辑面板。中间实现的低优先级、单并发48项回归通过，包含双主题的栏目/尺寸切换、草稿与连接输入元素/光标/焦点保留、主题确认后应用、CAS冲突、响应丢失后的原操作重试、身份切换，以及原阅读设置继承/覆盖与Source收藏保留。首轮发现Access原因被隐藏，已在当前栏目补回恢复入口并复验；宽屏不重复展示重试操作。随后按用户要求改用最终Cupertino语义颜色、标签栏、官方设置列表和正式详情路由；中间48项不代表这批新代码已完成验收，完整CI及正式Web仍待，不能用旧设置截图填表。

### 最终 Cupertino 配色、导航与设置路由

2026-11-14，最终代码删除Mihon固定palette、80dp窄侧栏/选中胶囊及阅读工具的Material elevation混色，改为官方Cupertino动态语义颜色、三入口标签栏、不透明系统工具表面与标准绿色开关。设置目录直接使用官方分组列表，窄屏使用同一减少动态策略的Cupertino页面路由，宽屏保留目录/详情。声明式页面更新读取当前Page，避免保留路由时显示旧栏目；详情身份跨尺寸保持。

低优先级、单并发运行`test/settings/settings_widgets_test.dart`、`settings_navigation_test.dart`、`test/data/source_favorites_repository_test.dart`、`test/widget_test.dart`、`test/theme/app_theme_test.dart`、`test/reader/reader_screen_test.dart`，**90项通过**。覆盖双主题、高对比度语义色、显式主题优先、各窗口标签栏选中语义、跨尺寸输入元素/文字/光标/焦点、草稿与原revision、导航/系统返回、减少动态淡化/禁用动画、CAS/精确重试/身份隔离，以及黑/白/主题阅读画布的页位、对比与资源驻留。15个改动Dart文件严格分析零问题。此处为组件/类型结果，完整CI、正式Web与全页视觉仍待。

2026-11-15 复查其它调用点，服务地址冷启动恢复测试仍使用旧的连接展开入口，已改为通过设置目录打开连接详情；该测试单项通过。它使用`TestPlatform`，没有启动原生应用，不计原生现场验收。

`f0aad3b`的完整push/PR CI在Flutter检查失败：除上述旧测试入口外，扩展“未确认原操作”面板仍把整个全局设置编辑器放入展开正文，新目录的viewport因此得到无界高度。已删除这处重复编辑器，保留原操作只读摘要、同一操作重试与独立重新读取；没有为旧嵌套形式增加兼容布局。原失败日志保留在忽略目录，后续修复的定向与完整CI结果另记，不能将首轮90项通过表述为完整工程通过。

修复提交`d600711`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43614259945)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43614270295)完整通过；push包含783项Dart、531项Vitest检查、正式Web构建与候选Wasm构建，部署跳过。扩展面板/服务地址恢复的23项定向回归也通过。正式Web artifact的39个Flutter清单条目经长度/哈希校验，Vite组装64个公开文件和两个当前扩展，未在本机编译Flutter或AOT。

在官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture下，用内置浏览器打开360×800设置目录与五个详情，并核对768×1024服务连接双栏。浅色草稿保持原深色，服务端确认后切浅，再保存深色；独立`GET /api/settings`确认`global.revision=2`、`accountRevision=2`、主题DARK。未安装/执行Source，也没有生产Access或续读验收。截图为`karuyomi-d600711-settings-*-{light,dark}.jpg`，两张初始跟随系统图另标`system-dark`。部分深色截图截到路由转场，排除稳定目标画面；原始JPEG不作精确色值或一像素叠图证据。

该次Web实看发现两项缺口：平板目录可见但未进入无障碍树；聚焦Web只读服务地址后，离开栏目仍残留旧地址/“提交”的自动填充表单。现已分别为内层Navigator建立独立语义容器、在服务地址字段禁用自动填充。新增回归从根语义树验证五个目录动作与详情在平板/窄屏切换后可达，并验证离页释放输入连接、重开保留原生地址草稿；修复前实际失败日志保留。阅读调暗合并为一项内容，点击区/快捷键说明移至官方分组页脚。低优先级单并发运行`widget_test.dart`与三个设置测试文件，49项通过；这批后续修改的严格分析、完整CI及稳定双主题Web复验另记。浏览器无warn/error，视口已恢复，harness已停止。

`d9fad79`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43617551512)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43617554296)完整通过，含787项Dart、531项Vitest及Web/候选Wasm构建；三个改动Dart文件严格分析、完整格式/依赖检查和标准prek通过。复用正式Web artifact并校验39个Flutter清单条目，在同一官方隔离流程中复验：浅/深平板五个栏目动作各有唯一可访问节点，目录与连接详情同时进入AX树；聚焦只读地址再离开后，两主题的DOM输入数与“提交”数均为0。保留`karuyomi-d9fad79-browser-checks.json`与两主题AX快照，独立API确认两次主题保存后revision均为2、主题DARK。未执行Source或生产Access；控制台无warn/error，视口恢复且harness退出0。

设置目录/五个详情及平板连接已采双主题JPEG并实看联系表；部分详情截图仍有返回/标签栏未稳定绘制的帧，不作为整页最终画面。实看还发现`CupertinoListSection.insetGrouped`的footer沿用17px正文样式；官方固定版本的`CupertinoFormSection`自带13px/secondaryLabel辅助样式。现已直接采用后者，同时删除重复背景、圆角和分隔配置，未自行复制其样式值。相同49项回归再次通过。

表单收敛提交`729cbe3`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43620115529)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43620120739)完整通过，含787项Dart（22 + 87 + 678）、531项Vitest及正式Web/候选Wasm构建，部署跳过。唯一改动Dart文件严格分析零问题，完整格式及标准prek通过。

校验该提交正式Web artifact的39个Flutter清单条目后，复用官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture，在内置浏览器实看360×800目录与五个详情，以及768×1024连接双栏的浅/深主图。阅读调暗与点击区/快捷键说明使用官方13px次级文字；分组背景、正文/辅助文字、系统蓝操作和标签栏随主题解析。两张联系表`karuyomi-729cbe3-settings-{pages,nav}-pairs.jpg`已实看。此前曾取得缺副标题、返回文字或底栏的帧；独立重载后重新导航、逐页观察并重拍，当前保存主图完整。原因尚未确定，不能把缺项帧直接归因于动画或截图工具，也不以重拍代替全部转场验收。

保留`karuyomi-729cbe3-browser-checks.json`：浅/深平板五项目录按钮各有一个可访问节点；聚焦Web同源只读地址后离页，DOM输入与“提交”数均为0。Web地址不可编辑，原生地址草稿/焦点只有组件证据。独立`GET /api/settings`确认两次主题保存后的`global.revision=2`、`accountRevision=2`与主题DARK。控制台无warn/error，视口与浏览器可见性已恢复，临时标签关闭，harness退出0。未安装或执行Source，未做生产Access/续读或原生现场验收；该批主图不覆盖草稿、失败、减少动态、大字号与全页面变体。

### 扩展列表与详情的 Cupertino 分组

继续核对08–09组。固定Mihon的双主题`s0803-extensions-installed-{light,dark}`原始PNG/XML中，已安装标题为`(32,496,688,536)`，xkcd整行`(0,680,720,808)`、名称`(160,706,221,746)`、语言/版本`(160,746,313,782)`，即64dp行高、80dp文字起点；参考为xkcd 1.6.2。Karuyomi当前隔离快照的xkcd为1.6.1，不能把版本或数据差异算作同条件像素通过。

正式代码将扩展分组改为官方inset grouped列表，删除包住列表行的按钮，保留独立的安装/管理动作；名称与状态允许换行，版本来自精确构建。详情的控制、漫画源和诊断各用官方分组；维护说明采用表单页脚，卸载与错误采用系统红。Source导航不再套外层按钮，保持原来的精确仓库/构建与生命周期。两主题×1x/2x、360×800下的尾部安装不误开详情、安装只写一次、随后行导航不追加写入已有新增回归。

低优先级、单并发运行两份扩展测试，42项通过；对应严格分析的两处空值元素语法提示已修复。新代码最终严格分析零问题。

`5d8bd71`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43624376767)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43624383501)完整通过，含791项Dart（22 + 87 + 682）、531项Vitest及Web/候选Wasm构建。校验39个Flutter清单条目后，用官方Vite组装64个静态文件和两包扩展，在官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture下打开360×800浅色可安装列表。`karuyomi-5d8bd71-extensions-available-light.jpg`实看分组/版本/状态，但行的AX角色为group、无tabindex，仅尾部安装有按钮节点；Enter无法聚焦该行并打开详情。保留`karuyomi-5d8bd71-extension-keyboard-gap.json`，该图不计为最终交互通过，不能用触屏回归掩盖键盘缺口。

后续修复把行内容导航与尾部操作改为并列的官方按钮，内容按钮内的列表行不再有第二个操作；源清单的单一导航仍直接使用官方onTap。新增浅/深真实Tab遍历及Enter打开详情且零账户写入的回归，同批44项扩展测试与严格分析通过；后续完整CI及正式Web双主题复验另记。上述浏览器控制环境已恢复，harness退出0，未执行Source或生产Access。

此前Source偏好toggle尚无真实浏览器证据。已只读核对现网190包索引和MangaDex 1.6.1清单：907135B编码包、61个Source、宿主ABI与共享材料身份与当前两包快照相同，官方源码提供多个SwitchPreferenceCompat；可通过隔离账户的额外仓库登记尝试真实验证，不需重新AOT。材料匹配不是初始化或偏好运行通过，尚未执行该包。

`5ed6dd6`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43626496683)完整成功，含793项Dart（22 + 87 + 684）、531项Vitest及Web/候选Wasm构建。其正式Web产物在隔离harness中确认行已是`role=button, tabindex=0`，实际Tab可在详情和安装之间移动；Enter仍未激活，空格才进入候选详情。独立`GET /api/settings`确认导航前后`global.revision=1`、`accountRevision=1`，未写安装选择。`karuyomi-5ed6dd6-extensions-available-light.jpg`与`extension-candidate-space-light`仅为当前布局及空格激活证据，不能标为Enter验收通过。

真实MangaDex的61语言摘要在列表/详情中占满三行，版本和状态被截断；原始画面保留为`mangadex-enabled-light-before-summary-fix`。后续修复缩短语言摘要并优先显示精确版本，同时在应用入口修正Web Enter intent；新增模拟Web默认映射的Enter/小键盘Enter、输入不误激活及Tab跳过禁用操作回归，61语言的列表/详情双主题回归也已加入。该批57项定向测试通过，完整CI与后续正式Web证据另记。

`5d8bd71`的额外仓库预览实际失败，未登记或执行Source；现网公开索引响应未提供跨源CORS，且其`keiyoushi`身份与默认仓库重复。随后仅为隔离验收，从现有公开发布中提取MangaDex清单和编码包，传输时验证编码/原文长度及哈希，确认共享材料身份一致，与原两包组成三包临时静态输入；其派生build-state绑定该子集，不是发布baseline，不重新AOT或修改上游业务。`5ed6dd6`已通过正式UI安装MangaDex并取得账户确认；首次打开英文Source和一次正式重试均出现“运行容器已中断”，偏好入口不可用，未取得toggle证据。保存`karuyomi-5ed6dd6-browser-findings.json`及失败主图；控制台无warn/error，视口已恢复、临时标签已关闭、harness退出0。初始化、偏好开关与在线阅读仍须分别验收，不能由安装成功推断兼容。

### 最新正式 Web 与 Source 会话偏好

`9a09331`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43629513501)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43629652977)完整成功，含797项Dart（22 + 87 + 688）、531项Vitest及Web/候选Wasm构建，未部署。正式Web artifact的39个Flutter清单条目已验证长度与哈希，仅本机低优先级Vite组装，无Flutter/AOT编译。

在官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture、四个现有已发布包中，以360×800内置浏览器核对系统深色和服务端已确认浅色：扩展列表、候选详情、无匹配、语言页、选项菜单，以及动漫屋已安装/停用详情均已实看。版本、语言数量、状态完整可见；Enter打开候选详情，两主题均成功；实际Tab从MangaDex详情按钮移至独立安装按钮。用尾部Enter安装动漫屋后仍留在列表，并显示账户已确认；两主题启停均有确认文字，开关保持标准绿/灰，卸载危险文字为系统红。

`karuyomi-9a09331-browser-findings.json`及同前缀JPEG/AX保留实际范围。独立GET在深色候选导航前后完全相同，缺省revision为0、未安装；安装/停用/启用和浅色主题确认后revision为4，浅色两次启停后为6，与六次明确写入相符。语言、菜单、检索和详情不额外写账户。深色诊断截图截到展开中的标题缺失帧，排除稳定目标主图；准备和等待确认仅观察到AX瞬态，没有主截图。Source行和诊断入口的tabindex仍为null、详情状态组还合并无关操作，因此不计整组最终交互通过。控制台无warn/error，视口恢复、临时标签关闭、harness退出0。未执行该版本Source阅读、卸载、生产Access或原生现场验收。

此前`5ed6dd6`中，现有公开动漫屋1.6.3包经传输验证后纳入隔离静态子集（Source 293789630396851172）；其真实热门目录有海贼王、青之芦苇等结果。真实“章末吐槽页”在系统深色和已确认浅色均完成关闭→开启→同会话关闭/重开仍开启，深色随后恢复关闭。该包无账户偏好同步规则；独立GET确认开关修改前后账户/全局revision分别保持1和2，Source账户entries为空。`karuyomi-5ed6dd6-dm5-{preferences-*,toggle-checks.json}`保留画面与检查。另留新文档浅色关闭图，但旧检查文件未确认该转换，继续待最新版本重放；不将会话内保存解释为跨文档同步。原“清除Cookie”缺少storage key，仍显示unsupported且未执行。MangaDex初次/重试中断和额外仓库预览失败保持原记录，不能被动漫屋成功覆盖。

后续实现修正Source/设置目录/展开入口的键盘焦点，拆分独立操作语义，并将Source偏好改为官方表单分组、次级说明与系统红错误。66项定向回归和8文件严格分析通过，覆盖双主题键盘、独立操作、偏好会话/账户及既有恢复流程；新增测试首轮因语义句柄释放时机失败，修正测试生命周期后通过，原日志保留。完整工程与新正式Web的后续结果如下，不以本地回归外推最终画面。

该修改提交`2df0551`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43654041595)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43654046926)均完整成功，含805项Dart（22 + 87 + 696）、531项Vitest和正式Web/候选Wasm构建，未部署。完整format、format:check及标准prek已通过。39项Flutter静态清单长度/哈希验证后，仅本机低优先级Vite组装，复用官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture和四个已发布扩展包；没有Flutter/AOT编译。

在360×800内置浏览器中，系统实际浅色，随后由UI确认深色再确认浅色。两主题均实际Tab到Source/诊断并Enter打开，卸载、源与状态信息各有独立语义；诊断滚动至最后一行完整构建哈希。最新Source表单的镜像选择、两个开关、unsupported说明互相独立，辅助说明使用次级文字。动漫屋真实“章末吐槽页”两主题完成0→1、关闭/同会话重开仍1，深色恢复0；镜像菜单均只查看并Escape取消。浅色跨源范围Tab/Enter收起及展开、深色设置目录Tab/Enter进入外观详情也已实测。

浅色实际reload后重新打开同一Source，开关为0；安装关系与LIGHT主题从服务端恢复。随后用独立卸载按钮Enter操作，页面显示账户卸载已确认。`karuyomi-2df0551-api-checks.json`独立核对：导航前后账户JSON相同；深色主题保存/安装后revision=2，切浅色后=3；两主题会话修改/重开/菜单、reload与范围导航均不增加revision，账户Source entries为空；卸载后revision=4且安装列表为空。这是会话边界与隔离账户确认，不是跨端偏好同步或生产读写。`karuyomi-2df0551-browser-findings.json`及同前缀JPEG/AX保留范围，控制台无warn/error；视口恢复、临时标签关闭、harness退出0。未执行unsupported Cookie或动漫屋图片阅读，MangaDex容器中断继续保留。

深色Sheet内部颜色正确，但顶部露出浅灰宿主背景；DOM检查html/body/Flutter容器背景均透明。新增`app_backdrop_test.dart`用实际Sheet和根RepaintBoundary采样，在系统与显式主题相反时，两主题的外露像素均只有alpha=24，先复现失败。根应用builder增加按当前Cupertino主题绘制的背景后，外露像素不透明、颜色符合相应主题及官方转场遮罩，两项回归通过；连同原主题共7项通过，2文件严格分析零问题。Web manifest静态颜色也从模板蓝改为默认浅色分组背景。完整格式/标准hook、CI及该修复的新Web画面另验；这些本机渲染证据不替代正式浏览器复验。

诊断展开后的首张深色图仍出现标题/部分内容缺项，滚动后恢复完整；失败图`extension-diagnostics-dark`保留且排除主图，不能无证据归因于动画，根背景修复也不声称解决此问题。全页、全状态/转换和生产验收继续待办。

根背景修复提交`16baf47`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43662020089)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43662143831)完整成功：807项Dart（22 + 87 + 698）、531项Vitest、正式Web与候选Wasm构建通过，未部署。完整格式、format:check与标准prek通过。下载产物并验证39项Flutter清单后，仍仅以低优先级Vite组装、本机不编译Flutter/AOT；复用官方隔离harness、临时D1、acceptance-owner、无fixture及四个已发布扩展。

该正式Web在360×800内置浏览器中完成系统浅色与显式深色的Source表单实看。系统仍为浅色且html/body透明，深色Sheet外露顶部现为黑色，正文/分组表面、辅助文字、标准绿/灰开关正常；`karuyomi-16baf47-source-preferences-{off,on}-{light,dark}.jpg`与`source-preferences-pair.png`已实看。浅色开关0→1，同会话返回设置确认深色后再进Source仍1；深色实际Tab至开关并Space恢复0、重开仍0。深色跨源范围实际Tab/Enter收起/展开，最终DOM的aria-expanded=true，成对状态图保留；浅色范围键盘证据仍对应`2df0551`。

独立`karuyomi-16baf47-api-checks.json`确认浅色会话操作前后账户完全相同（revision=1），主题保存后为DARK/revision=2，深色开关与范围导航前后同样完全相同，Source账户entries为空。匿名manifest读回的两项静态颜色均为`#F2F2F7`；未验安装后启动画面或动态浏览器chrome。`browser-findings.json`保留精确范围；控制台无warn/error，视口恢复、临时标签关闭、harness退出0。未做该版本新文档续读、动漫屋图片、生产Access或原生现场验收。两种颜色截图仍是JPEG，不把采样当作无损色值或全页面完成。

### 源目录、仓库与本机存储的分组收敛

后续实现直接采用官方CupertinoListSection，延用systemGroupedBackground/secondarySystemGroupedBackground、label/secondaryLabel和官方页脚；仓库添加/刷新采用actionTextStyle，移除采用系统危险红。源列表主动作与收藏改为并列按钮并标记已收藏语义，保留原确认链路；原嵌套结构的两项新增键盘用例本身已通过，因此不把此次结构调整描述为已复现的键盘故障修复。仓库输入恢复官方文本框装饰、禁用自动填充和URL自动更正。无自身State的仓库页面改为HookWidget，控制器订阅与展开生命周期仍由Hooks管理。

本机低优先级、单并发运行源收藏/语言/目录及扩展/仓库回归，首轮65项通过；新增仓库双主题/双倍字号、移除确认/取消和存储Tab/Enter/Space、清理后账户安装与revision保持的用例后，扩展/仓库55项通过。两轮去重合计72项不同用例。严格分析先发现一项if缺大括号，修正后5文件严格分析通过；完整格式、format:check和标准prek通过。

`7fddb0e`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43666151805)完整成功，含816项Dart（22 + 87 + 707）、531项Vitest及正式Web/候选Wasm构建。校验39项Flutter清单后，仅低优先级Vite组装，在官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture下用内置浏览器核对360×800浅色画面。安装xkcd 1.6.1和Komiic 1.6.11后显示两副本/6.1MiB；源分组、收藏、语言、无匹配实看，实际Tab/Space收藏英文xkcd，再Return打开真实目录。普通封面仍为占位，未验读图。

仓库列表、空白/填写输入、取消及非法`987654321`已操作；取消后DOM输入为0。存储逐个清至零副本/0.0MiB，完整空缓存诊断已实看。初始SYSTEM/revision=0，经两次安装与收藏为revision=3；源导航、菜单筛选、仓库输入/取消/非法预览、诊断和清理前后账户JSON字节完全相同。证据前缀`karuyomi-7fddb0e-`，`api-checks.json`及`browser-findings.json`保留范围；控制台无warn/error，视口恢复、临时标签关闭、harness退出0。该版未做深色、额外仓库添加/移除、生产Access或原生验收。

实拍发现菜单虽然显示首项聚焦，直接Return却未执行，Down后Return才进入仓库。新增双主题组件回归复现首项实际未获得Flutter焦点，保留失败日志；在菜单项指定官方autofocus，短选择优先当前可用项并回退首个可用项，扩展、书架、详情和阅读菜单采用同一规则。仓库/存储原ListSection的说明实为17px正文，改用官方FormSection页脚以获得13px次级文字；地址占位缩短并补中文纠错。选择/扩展45项、仓库/书架/详情/阅读42项定向回归、9文件严格分析及完整format/format:check通过，包含双主题页脚颜色及键盘、非法地址零读写；完整CI及新正式Web复验待续。旧仓库诊断图处于展开早期且正文未完整，排除主图；此缺帧不直接归因于动画，也不覆盖此前诊断首次深色缺项问题。

### 菜单焦点与分组说明的双主题复验

`76309ed`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43669338716)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43669344083)完整成功：820项Dart（22 + 87 + 711）、531项Vitest及正式Web/候选Wasm构建通过，未部署。39项Flutter产物清单校验后，仍只在本机低优先级Vite组装；正式Web使用官方Wrangler隔离harness、临时D1、acceptance-owner、无应用fixture、360×800和同一已发布扩展子集。本轮额外启动一个官方静态资源harness，公开提供标明用途的合成空目录`cupertino-ui-acceptance`，仅验证额外仓库的预览与账户确认，不作为真实第三方仓库或Source兼容证据。

源分组、已确认收藏/取消、无匹配与语言菜单取得双主题主图；浅色实际Tab/Space收藏，深色实际键盘Return打开英文xkcd并返回真实目录。语言菜单当前项直接Return关闭、Escape取消及扩展菜单连续两次Return进入仓库均已操作。仓库/存储说明呈现为官方13px次级层级，分组表面、正文、系统蓝动作、系统红错误/危险确认随浅深主题解析。输入空白/已填写、中文非法地址、只读预览和二次确认均有双主题图；浅色预览取消后账户保持，明确确认后登记合成仓库，深色确认移除后再预览并取消。清理从两副本/6.1MiB到零副本/0.0MiB，诊断与收起分别保留。

独立`karuyomi-76309ed-api-checks.json`核对revision从0到8，八次明确操作为两次安装、合成仓库添加、收藏、深色主题、取消收藏、仓库移除和浅色主题。预览/取消、深色导航/源打开与关闭、诊断和清理没有额外写入；清理前后账户JSON字节相同，最终仍有两个安装选择、无额外仓库。`console-tab18.json`无warn/error；原临时标签17中途不可用，保留同一浏览器新建18后继续并重新设定窄屏，不能声称原标签完整控制台已验。主harness退出0；空目录harness收到关闭请求后仍未退出，随后中断该专用进程，退出1，不计正常关闭通过。视口恢复，临时标签关闭。

新增合成仓库暴露移除动作的AX名称合并了默认行和整段页脚，存储多副本的清理名称也未区分对象；当前截图保留为视觉基线，不计为对应动作语义已通过。四项组件用例复现仓库问题后，以局部Semantics容器隔离动作，清理文本提供对象名称，空影响列表明确“无”。中间实验及测试语义句柄释放失败留在忽略日志；最终58项相关回归和3文件严格分析通过，完整CI及新Web另验。深色存储诊断收起后的`storage-empty-dark.jpg`缺少顶部内容，排除主图；`storage-empty-stable-dark.jpg`实看完整，但原因未定，不把重拍算作缺帧已修复。源打开图实际已完成，使用`source-opened-dark.jpg`，不计打开中的加载证据。全范围状态、变体、生产Access/续读和原生现场验收仍未通过。

### 局部操作名称与确认弹窗

`1e50a82`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43677719725)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43677725162)完整成功，含820项Dart（22 + 87 + 711）、531项Vitest及正式Web/候选Wasm构建。校验39项Flutter清单后，只低优先级Vite组装；仍在官方Wrangler隔离harness、临时D1、acceptance-owner、360×800内置浏览器验收，额外仓库仍为明确标记的合成空目录。

该版取得源空态、带额外仓库的列表/移除确认、单副本和双副本列表、清零后列表的双主题画面。两主题的仓库移除按钮名称精确为“移除仓库：空目录验收”，实际Tab/Return可打开确认；影响为空时明确显示“无”。副本按钮分别叫“清理副本：Komiic”和“清理副本：xkcd”，两主题均真实Tab可达，深色分别以Return与Space从两副本/6.1MiB清至零。取消前后、清理前后账户JSON字节相同；最终revision=8，保留两安装且无额外仓库。八次明确写入为四次主题保存、两次安装、一次仓库添加及一次移除；详见`karuyomi-1e50a82-api-checks.json`。

浅色首次通过Playwright定位器点击确认移除后，账户仍为revision=4、仓库仍在，后续Komiic安装只推进至5，不能声称浅色移除成功。深色重新用AX操作确认后，界面明确显示“仓库已移除”，API为revision=7、额外仓库为空。确认框中真实Tab始终未进入两个动作，独立保存失败AX；随后四项组件用例复现此缺口，14个弹窗动作改用官方CupertinoButton，四项先失败后通过，连同扩展/仓库、Source偏好、跨源错误和迁移的95项不同定向回归与6文件严格分析通过，后续完整检查及新Web另验。初次测试缺少键盘导入的加载失败与真实四项失败分别保留。

`storage-empty-diagnostics-dark.jpg`仍缺顶部标题与摘要，AX含有这些内容；该帧排除主图，原因未定。初次深色移除确认偏透明，完整稳定帧作为主图，早期帧保留；不把重拍算作缺帧根因已解决。全部截图为JPEG，不能用于无损像素/颜色结论。`console-tab19.json`无warn/error；两harness正常退出0，视口恢复且临时标签关闭。本轮未打开实际Source目录或图片，未执行生产Access、续读或原生现场验收。

### 确认弹窗的双主题键盘复验

`4467ceb`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43680418792)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43680529738)完整成功，包含820项Dart（22 + 87 + 711）、531项Vitest及正式Web/候选Wasm构建。39项Flutter清单长度/哈希通过后，仅低优先级Vite组装；官方Wrangler隔离harness、临时D1、acceptance-owner、360×800内置浏览器继续使用，无应用fixture、无扩展安装。空仓库由独立官方Static Assets harness提供，仅验证预览和账户确认，不代表第三方兼容性。

两主题的空白/已填写仓库输入、添加确认、已添加列表、取消焦点、移除确认与已移除列表均已保存AX/JPEG。真实Tab依次到达地址、名称、取消与只读预览；浅色Return取消预览，Space确认添加/移除，Return取消移除；深色Return确认添加/移除，Space取消移除。弹窗内部按钮名称独立，默认强调、系统蓝/危险红和焦点圈已实看。浅/深移除确认与结果联系表也已实看；JPEG原图不能作无损颜色或像素结论。

`karuyomi-4467ceb-api-checks.json`断言只读预览、预览取消和两主题移除取消前后账户JSON字节相同；五次明确写入为浅色添加/移除、DARK主题、深色添加/移除，revision依次0→1→2→3→4→5。最终DARK、零扩展安装、零额外仓库。`karuyomi-4467ceb-browser-findings.json`记录环境与范围，tab20无warn/error；视口恢复、临时标签关闭，两harness正常退出0。此次仅对仓库的添加/移除确认完成正式Web复验，其余弹窗保留95项组件回归的证据边界；未执行Source、真实图片、生产Access、续读或原生现场验收。`1e50a82`的浅色失败和诊断缺帧保留，不以新版本成功覆盖旧事实。

### typed Source 筛选的 Cupertino 分组

后续将筛选的header/separator/group映射为官方同层表单分组，移除24px实色分隔、每字段额外底边距及手工表面。独立说明保留为仅标题ListSection；布尔条件改为系统开关，单选/三态/排序采用完整列表行，排序方向单独成行。加载、重置、应用显示各自操作，错误用系统红、取消影响用13px次级文字。源协议的snapshotId、原始path、草稿、取消退役和原列表保留链未改。

四项浅/深×1x/2x窄屏用例在旧实现复现没有正式表单及排序行溢出；改动后验证无嵌套圆角表单、嵌套路径6.1.0与后续6.2准确提交、描述读取后编辑不调用Source，以及实际输入配置禁用autofill。加载/应用延迟及失败重试、错误/说明颜色、重置取消和晚结果另有双主题用例。筛选组件10项、筛选控制器/源目录/选择控件20项，共30项不同定向回归通过，低优先级单并发执行。完整检查、CI和正式Web画面继续；这些组件证据不填入目标状态机的浏览器主图。

### Source 偏好的空内容与首项分组

筛选等待CI期间，以两个双主题用例复现偏好描述的有效边界：首项为分组、空分组或全空描述，会把空children交给CupertinoFormSection并触发`children.length > 0`断言。仅标题部分改用官方CupertinoListSection，含字段部分继续使用FormSection，保留原path和父级禁用。中间实现的外层DefaultTextStyle被ListSection内部重新覆盖，说明仍为17px；改为在header/footer传入点设置13px/secondaryLabel后，两个用例和原偏好组件/控制器共19项通过，确认嵌套0.1.0不可编辑、刷新为空态、无回调或账户写入。完整格式、严格分析与新CI另记；`86e7925`的Web产物不包含这项后续修复，正式浏览器证据不能混用。

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
