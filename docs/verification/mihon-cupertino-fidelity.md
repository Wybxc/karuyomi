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

四项浅/深×1x/2x窄屏用例在旧实现复现没有正式表单及排序行溢出；改动后验证无嵌套圆角表单、嵌套路径6.1.0与后续6.2准确提交、描述读取后编辑不调用Source，以及实际输入配置禁用autofill。加载/应用延迟及失败重试、错误/说明颜色、重置取消和晚结果另有双主题用例。筛选组件10项、筛选控制器/源目录/选择控件20项，共30项不同定向回归通过，低优先级单并发执行。`86e7925`完整格式、两文件严格分析、标准prek及[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43684076159)/[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43684079790)通过，含827项Dart（22+87+718）、531项Vitest及Web/Wasm构建。

其正式Web的39项Flutter清单长度/hash核验后，使用官方Wrangler隔离harness、临时D1和360×800内置浏览器，无故障fixture。双主题已实看真实xkcd的“无额外筛选”弹层：浅色Tab/Return取消、深色Tab/Space取消，均保留原列表；两主题执行重置和默认条件应用，浅色点击、深色Tab/Return后获得已应用的空搜索结果。稳定空态与落点联系表已实看；最后一次深色应用截图缺文字，排除主图，采用此前稳定的同状态画面。瞬时读取/重置/应用未截到，不以操作完成替代主图。

独立API确认浅/深筛选的取消、重置与应用前后账户JSON逐字节相同。全程四次明确写入为Komiic安装、镜像偏好、xkcd安装及DARK外观，accountRevision为0→1→2→3→4；镜像偏好独立GET确认为revision1/text1。Komiic默认热门返回请求失败；镜像保存虽已确认，随后容器中断，重新连接及新文档仍中断，typed字段没有取得本轮正式Web证据，不记运行兼容通过。tab21警告/错误为0，viewport恢复且临时标签已关闭，harness正常exit0。原始记录在忽略目录的`karuyomi-86e7925-api-checks.json`、`karuyomi-86e7925-console.json`与两张`filters-*-pair.png`。

验收中浅/深两次成功应用后的AX均短暂出现“漫画源会话已变化”，实际搜索随后成功；这是正常路由退出时把isActive=false当成会话失效的呈现缺口，不能记为真实Source故障。两个定向用例先复现误报，再区分会话身份与路由可接受操作状态；退出保留内容、冻结动作，真正容器丢失仍显示错误并隐藏旧字段。新增两项与原筛选/控制器/目录/选择共32项回归通过。`c353604`的两文件严格分析、完整格式、标准prek及[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43687285256)/[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43687290796)通过，含831项Dart（22+87+722）、531项Vitest和Web/Wasm；正常转场的正式Web双主题复验也已完成。

`c353604`的39项Flutter资产长度/hash核验后，在官方Wrangler临时D1、无fixture、360×800内置浏览器中，两主题真实xkcd默认条件应用均成功；同一工具调用在点击后取得AX和实际反向转场画面，保留原筛选内容且没有会话失效误报，随后进入已应用的空结果。浅深画面在动画的不同位置，仅证明实际取到的两个时刻，不外推全部帧或减少动态效果。双主题联系表已实看，独立API确认应用前后账户字节相同（浅色revision1、深色revision2），仅安装与主题保存写入。tab23警告/错误为0，viewport恢复、临时标签关闭、harness正常exit0。忽略目录保存`karuyomi-c353604-api-checks.json`、`karuyomi-c353604-browser-findings.json`及`karuyomi-c353604-filters-closing-pair.png`。

随后仍用`86e7925`正式产物，在新的官方harness和空D1取得Komiic默认站点的双主题实际select字段（排序/状态/分级）、初始值和应用失败保留状态；浅色指针及深色真实Tab/Return完成排序菜单与草稿操作，取消重开后恢复默认排序，两主题重置后继续保留字段。默认站点实际查询均失败，应用失败时状态“完結”草稿仍可编辑，取消回到原热门错误，不记为成功查询或运行兼容。无镜像保存及故障fixture，独立API确认所有筛选操作零附写；全程仅安装和DARK外观两次明确写入，accountRevision为0→1→2。真实字段就绪与失败的两张联系表完整实看；菜单与草稿的两张联系表缺少标题/底部动作，保留AX操作证据，不能作为完整主图。tab22警告/错误为0，临时标签关闭、viewport恢复、harness正常exit0。原始记录为忽略目录的`karuyomi-86e7925-clean-api-checks.json`、`karuyomi-86e7925-clean-browser-findings.json`及`clean-filters-*-pair.png`。

这轮实际画面另发现独立说明标题仍被ListSection改为17px主文字。原四项浅/深×1x/2x回归增加独立标题的实际继承文字检查，均先复现；在header传入点设置13px/secondaryLabel后，同文件12项通过，两文件严格分析通过。修复提交`75c618a`的完整格式、标准prek及[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43688775242)/[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43688860048)均通过，含831项Dart（22+87+722）、531项Vitest和Web/Wasm构建；未部署。旧17px画面继续作为历史缺口，未加载的类型checkbox、text、tri-state及SortFilter方向仍只具组件证据。

`75c618a`正式Web的39项Flutter清单经长度/hash核验，只在本机低优先级Vite组装；复用官方Wrangler隔离harness、临时D1、acceptance-owner、无fixture和现成Komiic包。在360×800分别取得系统浅色及服务端确认深色的实际select表单，独立标题和说明呈次级层级。两主题均在菜单展开时调整到390×844：菜单收起、值不变；重新展开后保存含完整标题/内容/底部动作的主图，再选择“喜愛數”，返回360×800仍保留草稿。浅色指针选择，深色从“更新”用三次Tab和Return选定；深色草稿图保留真实键盘焦点圈。两主题取消返回原热门错误，重开均恢复“更新”。就绪、菜单和草稿三张双主题联系表已实看；JPEG只能证明实际显示，不能作无损像素或精确色值结论。

`karuyomi-75c618a-api-checks.json`确认浅/深全部筛选、菜单、调整视口及取消操作前后账户JSON各自字节相同；浅色revision1、深色revision2，唯一两次写入为安装和DARK主题确认。默认Komiic热门请求仍失败，未保存镜像，也未声称筛选查询成功或运行兼容。`karuyomi-75c618a-browser-findings.json`保存环境和边界，console无warn/error；viewport已恢复、临时标签关闭、harness正常exit0。最终全页、其它控件/状态、生产Access/续读和原生现场验收仍未通过。

### Source 偏好的空内容与首项分组

筛选等待CI期间，以两个双主题用例复现偏好描述的有效边界：首项为分组、空分组或全空描述，会把空children交给CupertinoFormSection并触发`children.length > 0`断言。仅标题部分改用官方CupertinoListSection，含字段部分继续使用FormSection，保留原path和父级禁用。中间实现的外层DefaultTextStyle被ListSection内部重新覆盖，说明仍为17px；改为在header/footer传入点设置13px/secondaryLabel后，两个用例和原偏好组件/控制器共19项通过，确认嵌套0.1.0不可编辑、刷新为空态、无回调或账户写入。`8a3abbe`完整格式、两文件严格分析、标准prek及[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43685070980)/[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43685166442)通过，含829项Dart（22+87+720）、531项Vitest及Web/Wasm构建；`86e7925`的Web产物不包含这项后续修复，正式浏览器证据不能混用。空描述、空分组及继承禁用仍仅有组件证据。

### 分类管理与批量确认的 Cupertino 分组

2026-11-15，分类管理的名称/四动作纵排改为官方inset grouped列表，名称直接进入重命名，更多菜单提供上移/下移/删除；行ID稳定，两个操作分别有官方键盘入口。新建/重命名输入禁用自动填充，分类选择与批量选择直接使用官方表单，说明交给官方次级页脚；删除菜单与确认、批量移出及原操作重试采用系统危险红。批量清单的来源、分类变化、逐项状态及错误分别换行，解除ListTile默认单行副标题对业务结果的裁切，确认/未确认仍有明确文字。

八项浅/深×1x/2x窄屏用例先复现没有正式分组，再通过修复；分类用例覆盖长名称、菜单边界和危险标记、Escape取消、编辑草稿尺寸变化后保留、全部预览/取消零写入。批量用例实际模拟写入后503确认丢失，验证未确认逐项文字不截断、系统红、精确恢复入口和仅一次明确写入。全部`test/library`低优先级单并发52项通过，含CAS拒绝、部分提交、精确重试、迟到确认、身份更换、键盘上方保存和续读；四个改动文件严格分析零问题。首次分析的三项测试lint已修正。`a9fb310`完整格式、标准prek、[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43692329444)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43692481926)通过，含839项Dart（22+87+730）、531项Vitest与Web/Wasm构建。模拟ACK失败不算真实Source或生产故障验收。

正式`75c618a`改造前基准另已在官方Wrangler临时D1、`categories`夹具、360×800内置浏览器取得双主题实拍。通过UI建立与固定Mihon主图相同的“ReadingReadingreading”“ZZZZZ”两项分类；旧列表首名称约y310，四动作常驻名称下方。固定Mihon实际XML的两名称矩形均为`(160,336,464,368)`与`(160,496,464,528)`物理像素（320dpi，除2为逻辑单位），名称左侧保留拖动和图标区域，不能把其80dp文字起点直接套进没有同类图标的Cupertino行。两平台系统栏和弹层也不同，未将其称为同像素对照通过。`karuyomi-75c618a-category-baseline-list-pair.png`已实看；JPEG不用于精确色值结论。

基准独立API确认分类目录revision2，两个名称和顺序在主题导航前后相同；accountRevision4→5仅为明确DARK保存。夹具先创建两收藏，UI另创建两分类及保存主题，共五次写入。`karuyomi-75c618a-category-baseline-findings.json`保留原始XML锚点、API结果和范围；console无warn/error，视口恢复、标签关闭、harness退出0。此基准不填入最终05.K2，也不代表Source或生产验收。

正式`a9fb310`Web的39个Flutter资源条目经manifest核验后，复用官方Wrangler harness、临时D1与`categories`夹具，在360×800内置浏览器取得浅深分类列表、更多菜单、空名称/错误、重命名草稿、删除预览、单作品当前选择/草稿、批量分类与移出预览及全部确认画面。菜单初始焦点、Escape取消、浅色Tab/Return取消删除、上/下移确认及恢复原顺序实际通过；重命名草稿在360→390→360保留后取消。未提交重命名或删除。浅色分类空态另有主图，深色空态继续待。保存、批量进行中、部分未确认、暂停、拒绝及身份失效尚未分别截到正式Web状态，不以组件证据补齐。

独立API快照确认accountRevision2→12：两次夹具收藏，UI两次建分类、两次排序、一次单作品分类保存、两项批量添加、一次DARK主题保存及两项批量移出分类，共十次UI写入。一次本拟取消的单作品选择实际点击保存，已按写入计数，后续独立重做取消并确认零附写。名称/菜单/删除预览取消、单作品选择取消、批量两类预览取消、深色输入校验与取消均在对应区间保持完整API对象相同；跨主题区间单独核对确认写入，不笼统宣称全程零写入。console无warn/error，视口恢复、标签关闭、harness退出0，详见`karuyomi-a9fb310-category-findings.json`。

`category-mihon-before-cupertino-contact.png`及11张双主题联系表已实看。新版行从表单顶部自然展开，首名称按钮实际语义矩形为`(20,153.2,259.59,44)`，更多按钮为`(279.6,149,60.4,52.4)`（x/y/width/height，逻辑像素）；这只是Web语义/触控边界，不冒充Mihon字形矩形。官方分组取代旧居中四动作，保留Mihon名称/顺序参照，最终采用Cupertino系统蓝、分组表面和次级文字。

实拍发现浅色批量确认的绿色正文偏淡，另发现“新建分类”语义吸收分组标题/说明；八项已有主题/字号用例已分别复现这两处缺口。`bbf69d7`以系统正文色表达明确确认，并给新建操作独立语义边界；重试后确认文字在页面/分组表面的对比度≥4.5，原请求完全相同。书架与主题共57项回归、五文件严格分析、完整格式与标准prek通过；测试语义句柄的清理问题也已修正。[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43695907436)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43696038700)完整通过，含839项Dart、531项Vitest和Web/Wasm构建。

正式`bbf69d7`的39个Flutter资源条目核验后，同样在官方Wrangler临时D1、`categories`夹具和360×800内置浏览器取得双主题空分类、相同两名称列表和全部批量确认主图，三张`karuyomi-bbf69d7-{category-empty,category-list,batch-confirmed}-pair.png`均已实看。空态/列表的浅深四个状态各只有一个精确“新建分类”按钮，分组标题/说明保留在独立容器；两主题实际Tab/Return打开新建，浅色空输入取消、两主题有名称列表的新建草稿取消均无附写。批量浅色添加/深色移出均明确2/2获确认，摘要和逐项正文可读，未用旧绿色画面代替修复证据。

独立API确认accountRevision2→11：两次夹具收藏之外，UI两次建分类、三次主题保存和四项批量分类写入，共九次。两主题列表新建取消的前后完整API对象相同；最终两收藏均保留、分类关联清空、各漫画revision3，目录revision2、全局设置revision3且主题DARK。`karuyomi-bbf69d7-palette-findings.json`记录范围与原始文件；console无warn/error，视口恢复、标签关闭、harness退出0。本轮只复验实际主图和上述转换，未补齐原状态图的保存瞬态、部分未确认/暂停/拒绝/身份失效或生产Access，不宣布全页或生产验收完成。

### 章节文字与书架资料确认的 Cupertino 呈现

2026-11-15，按现有Mihon章节列表参考继续核对Karuyomi。六项浅/深用例先复现：360×800下重复章节的扫描组、来源序号及读态被CupertinoListTile默认单行省略；书架资料丢确认后精确重试获确认，后续书架读失败时确认正文仍继承错误红。修复解除章节标题/副标题的默认单行约束，保留官方文字样式和12px次级资料；资料确认独立于打开错误和刷新失败，以正文色呈现。

低优先级单并发运行章节导航、章节读态、书签导航、书架续读和主题共33项回归通过，四个改动Dart文件严格分析及依赖分层同样通过。四项窄屏浅/深×1x/2x测试实际使用Tab/Enter标记精确的重复章节，再Shift/Tab返回并打开该条目；打开与书签已有独立语义，不把此前嵌套按钮的源码观察描述为已复现的键盘故障。资料重试两项继续核对原请求完全相同、D1仅应用一次、确认后读失败不变成待确认。新增测试的语义句柄清理时机已修正；资料丢确认及后续读取失败仍仅为组件证据，未在正式Web注入故障复验。

`b6bc240`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43699361327)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43699368999)完整通过，包含22+87+735=844项Dart、531项Vitest、严格分析、格式、生成、Web及Wasm构建。39个Flutter资源条目核验后，Vite组装68个公开文件和四个现有扩展，本机没有Flutter或AOT编译。官方Wrangler临时D1、acceptance-owner、无fixture、360×800内置浏览器，在双主题下打开同一英文xkcd及3323章，核对未收藏详情、两行完整长标题、搜索无匹配/清空、章节选项、排序菜单、零选择、范围起止列表和两章只读确认。两张`karuyomi-b6bc240-chapter-{text,options}-pairs.jpg`联系表已实看；搜索匹配和范围已选图的滚动锚点有差异，不计同位置像素叠图。退出范围确认保留原两章选择，明确退出才清空。

两主题实际Tab聚焦首章独立书签按钮，再Return仅标记该章，随后明确移除；未进入阅读器。独立API的正式Protobuf解析核对首章精确chapterKey、两次标记各只有一条书签、进度始终为空且无后续分页。最终accountRevision=8：三次主题保存、一次扩展安装及四次书签增删；global.revision=4，主题LIGHT，漫画revision=4，无收藏或书签/进度。深色范围预览取消的完整漫画快照相同，浅色预览前后完整账户与漫画快照也相同；搜索、菜单和预览没有附写。原始证据、独立快照及`karuyomi-b6bc240-api-checks.json`留在忽略目录。console无warn/error，视口恢复、标签关闭，harness退出0。

实拍另发现：长范围选项仍被ListTile单行省略，来源序号可能不可见；已选择的起止按钮也省略长名称。此缺口不属于已修复的章节正文，长选项完整资料、无匹配/清空、取消及更大字号继续待验。章节读态提交、等待/未知/拒绝/失效、普通Source封面、全部变体和生产Access/续读同样未验；分支仍为草稿，未合并或部署。

### 长选项与范围表单的自然尺寸

2026-11-15，新增八项360×800、浅/深×1x/2x组件用例先复现长选项与已选值被单行省略，产品详情在双倍字号另复现排序横排溢出26px。完整选择行、短菜单项及长列表的调用点解除DefaultTextStyle行数限制，保留官方字号与配色；紧凑工具按钮继续保持原布局。范围起止改用官方CupertinoFormSection中的完整行，删除280dp宽度，范围说明放入官方页脚；排序删除重复标题和横排约束。未更改来源key、选中集合或提交协议。

新八项修复后通过，实际核对RenderParagraph未省略完整来源序号、无匹配/语义清空、Tab/Enter打开与精确选择、返回恢复焦点及取消零回调。产品用例选择同名来源第1→3项、预览三章并取消，保留三章选择，POST始终为空且不获取Source图片页。双倍字号取消后摘要在惰性列表的屏幕之外，用真实滚动回到摘要核对；没有放松选中数或零写入断言。章节列表原测试把新排序行也算成章节，已改为枚举具有来源key的章节行，保留完整顺序及精确身份断言。

共享选择、章节读态/列表、Source筛选/偏好、设置和主题共73项不同定向回归通过，五个改动Dart文件严格分析及依赖分层通过，均为本机低优先级单并发检查。日志留在忽略目录`long-choice-{verified,regression,chapter-list,analyze,dependencies}.log`；完整格式、标准hook、CI和新正式Web主图按后续结果记录。18.K2及29.K1/K2仍不填入已通过浏览器证据，保留`b6bc240`的历史省略缺口；尚未验证生产或Karuyomi原生。

`0c4da11`随后通过完整格式、校验及标准prek，[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43707665730)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43707791195)完整通过，包含22+87+743=852项Dart、531项Vitest、严格分析、生成、Web及Wasm构建。CI Web的39条Flutter资源核验后，Vite组装68个公开文件和四个现有扩展；本机未运行Flutter/AOT编译。官方Wrangler临时D1、acceptance-owner、无fixture、360×800内置浏览器，在浅/深明确保存的主题中均打开真实英文xkcd及相同3323章，取得完整长选项、当前来源第8项勾选、查询命中/无匹配/清空、范围表单及六章只读清单的主图。`karuyomi-0c4da11-range-{form-pair,query-pairs,preview-pair}.jpg`三张联系表已实看。

两主题实际Tab/Return打开范围起点，清空和取消回到零选择并恢复原按钮焦点；浅色另从查询输入Tab到唯一命中的来源第8项，再Return精确选择。两主题均选择来源第8→13项，完整起止名称与来源序号可见，确认清单为六章；重开起点、输入无匹配后取消仍保留两个端点与六章选择。清单中Shift/Tab回到实际取消按钮，深色Return、浅色Space取消均保留原范围，明确退出才清空；未提交章节读态或进入阅读器。

正式Protobuf解析的独立API核对两主题各自完整账户和作品快照前后相同。最终accountRevision和global.revision均3，仅两次主题保存与一次扩展安装；主题LIGHT，漫画revision0，无收藏、资料、书签、进度或续读位置，分页游标为空。结果为`karuyomi-0c4da11-api-checks.json`，可复验脚本和原始快照留在忽略目录。Source正常返回目录，console无warn/error，视口恢复、标签关闭，harness退出0。第一次深色当前项图拍在水平转场中，另存`range-current-choice-dark-transition.jpg`并排除主图，稳定重拍已核对；两张章节选项图的滚动锚点不同，不能计同位置叠图。JPEG不作无损像素或精确颜色结论，双倍字号仍仅为组件证据；生产Access、资料故障、重复条目实拍、全部转换与变体继续待。

### 选择状态的辅助语义

2026-11-15，`0c4da11`正式Web的可见勾选没有选中语义。新增浅/深×1x/2x、短菜单/可查询长列表共八项用例全部复现；修复直接使用Flutter官方Semantics保留菜单和按钮原有动作，补选中/未选中及互斥组标记。长列表另明确禁用状态，并用blockUserActions阻断禁用项的辅助点击，不替换控件或增加自定义手势。

八项修复后通过，覆盖命名动作的选中、未选中、禁用/点击边界，查询命中和清空后的标记保留，以及取消零回调；连同既有选择用例共19项通过。语言、Source偏好/筛选、章节列表和迁移相关共73项不同回归通过，使用固定Flutter/Dart、低优先级单并发。测试采用当前isSemantics API，保留最初八项失败日志及修复记录于忽略目录`choice-semantics-{before,after,related,analyze}.log`。完整格式、标准hook、CI及修复后的正式Web辅助树按后续结果记录；本段不声称读屏软件、Native或生产验收。

`10379e5`随后通过两文件严格分析、依赖分层、完整`pnpm format`→`pnpm format:check`及标准prek，[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43718242063)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43718246916)均完整通过。日志明确记录22+87+751=860项Dart、531项Vitest，以及生成、Web和Wasm构建。120秒watcher退出0，完整日志为`ci-10379e5-completed.log`。本机只运行定向检查，用户原有锁文件改动未纳入提交。

修复后正式Web仍待输入获取：GitHub REST确认artifact `14163870898`（16,294,863字节）存在、未过期且属于该精确提交。原`gh run download`无产物后已结束；随后同一artifact的90秒CLI请求超时，独立Node HTTP取得GitHub重定向后，在`productionresultssa9.blob.core.windows.net`的45秒下载仍超时，尚未取得可核验ZIP或Flutter清单。凭据和临时签名URL没有输出或落盘。未重启harness或打开验收标签，预备的API脚本没有产生新业务结果；已有`0c4da11`双主题主图不能填作本次正式Web语义通过。此处仅记录实际下载限制，不推断GitHub或整个网络不可用。

另按当前封面编辑器、CoverRepository及CustomCover分支补[19.K1–K12目标状态图](mihon-state-coverage.md#19karuyomi-自定义封面的目标状态)，分别列首次读取、已确认有/无封面、选图、两种草稿、等待确认、未知、拒绝、失效及图片读取失败的最小信息。全部新主图保留待验。

### 自定义封面的读取、草稿与确认

2026-11-15，封面编辑器将同一忙碌标记细化为读取、选图、保存三种操作，分别显示实际进度。首次读取成功前不再显示“服务端已确认”，读取失败明确显示尚未取得快照；成功无封面明确说明未设置自定义封面。已确认内容与替换/清除草稿分别采用官方CupertinoFormSection，说明交给官方页脚，错误为独立live region及系统危险色，清除动作只在可编辑时采用危险色，禁用时沿用官方颜色。等待确认或保留原请求时标为“上次服务端确认”，不声称未知结果未改变远端。

浅/深×1x/2x、360×800的四项组件流程覆盖首次读取阻塞/503/重读、取消选图、非法文件、选图阻塞、草稿零上传、上传阻塞及丢确认、稍后处理后重开又读取失败、精确重试原mutation与相同字节、清除草稿取消选图/关闭零提交，以及清除等待确认时保留旧封面。两种提交仅各应用一次，Source调用不增且无图片控制请求。既有封面/CAS/身份变化、repository、transport和封面组件合计26项回归通过，两文件严格分析通过；本机固定Flutter/Dart、低优先级单并发，没有Flutter/AOT构建。

原实现已在新增用例中复现读取失败仍显示已确认；早期测试未识别请求末尾的问号，不据此声称复现阻塞加载。修正URI路径匹配并在首次失败后移除已完成的阻塞回调，新增流程全部通过；原始失败、诊断与最终日志留在忽略目录`cover-states-{before,probe,related,analyze}.log`。该结果属于组件和数据/传输测试，不是系统文件选择器、Web辅助树或生产验收；19.K1–K12的浅深主图、拒绝/失效的全部触发阶段和图片失败实拍继续待办。

`69db369`已提交推送，完整格式、校验及标准prek通过；[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43722877234)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43722995910)均在reader静态分析失败，未运行reader测试和Web构建。原因是格式化把新增测试的清除阻塞条件分行后触发`curly_braces_in_flow_control_structures`，此前两文件分析在格式化前通过，不能代替最终格式的检查。后续补齐该条件的大括号，完整格式化/校验后两文件严格分析通过，不降低lint级别。完整日志留在`ci-69db369-failed.log`和`cover-lint-{format,format-check,analyze}.log`，后续CI及Web结果另记。

迁移向导同时补[20.K1–K18、21.K1–K6目标状态](mihon-state-coverage.md)，区分输入、原章节、目标源/列表/预览、映射/超限、确认与原请求恢复的最小信息。当前迁移呈现尚未修改，全部新主图保留待验。

另尝试已全绿的`a39248c`正式Web artifact（14164452592、16,294,861字节），GitHub重定向成功，但新的`productionresultssa17.blob.core.windows.net`节点仍在45秒内未完成下载；没有取得ZIP，也未启动harness。此提交包含选择语义修复、尚不含封面调整，未把本次输入获取尝试记作任何新界面通过。

### 封面与选择语义的正式 Web 分项

2026-11-15至16，修复格式化后lint的`c5f6759`通过[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43724361658)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43724368162)，包含22+87+755=864项Dart、531项Vitest、严格分析、生成及Web/Wasm构建。完整日志保留在忽略目录`ci-c5f6759-check.log`；120秒watcher均退出0，不抹去前述`69db369`的真实失败。

同一CI artifact `14166380004`经有界断点续传取得16,295,437字节ZIP，在传输边界核对GitHub的SHA-256 `3b908b51d9a0e4fe483817668c74ecc820ee01d5b2c536d1804f09705fb2cd96`。随后核验39条Flutter清单，使用现有Vite配置和四扩展快照组装，未在本机编译Flutter或AOT。官方Wrangler harness使用临时D1/R2、`acceptance-owner`和空fixture；Codex内置浏览器360×800，深色跟随系统，浅色经实际UI保存。真实英文xkcd返回3323章，首项为`3324: Ultimate Movie Series`。

两主题均通过真实文件选择器提交本地生成的非法文件、橙色PNG和紫色PNG，取得无封面、非法图片错误、首次选图草稿、保存确认、替换草稿/确认、清除草稿、取消后重开及清除确认的成对主图。已确认封面与待保存图片分别分区，说明采用次级色，错误和可编辑的清除采用系统红。未把空文件列表冒充手动系统取消；选图等待和服务端等待确认未截到完整主图，仍待。截图为`karuyomi-c5f6759-cover-{none,invalid,draft,confirmed,replace-draft,replaced,clear-draft,reopened,cleared}-{light,dark}.jpg`，已逐张实看。

每个阶段另以六份只读API响应和正式Protobuf解析核对：选图/替换草稿、取消清除和章节范围/菜单/返回均不改变完整账户及作品快照。每主题保存、替换和清除各推进一次账户与作品revision，且只改变封面；设置、分类、收藏、作品元数据、书签、进度及续读保持。四次已确认图片下载在各自传输边界核对类型、长度和SHA-256，橙/紫JPEG分别为1959/1957字节，替换后的摘要不同。最终accountRevision=9、global.revision=2、作品revision=7，恰含一次安装、一次收藏、一次主题和六次封面提交；无封面、书签或阅读进度。浅色最后实际重载新文档，从服务端恢复主题和收藏，再打开编辑器读回“未设置自定义封面”；前后完整快照相同。

同份产物的短排序菜单和可查询长列表在两主题分别读取实际DOM：当前项`aria-current=true`，另一项`false`，与画面勾选对应；浅色短菜单另用Return保留当前排序并关闭。长列表选择首项为范围起点后重开，完整名称/来源序号与选中标记保留。证据为`karuyomi-c5f6759-choice-{short,long}-{light,dark}.{jpg,dom.json}`，不把AX摘要省略状态误报为DOM缺失，也不据此声称真实读屏软件或禁用选项验收；禁用项本轮没有在正式UI触发。

浅色清除后的首张截图缺少标题和底部动作，已另存`cover-cleared-light-incomplete.jpg`并排除主图，重载后取得完整读回图；原因未定，不计所有转场或变体通过。新文档首次等待详情定位超时，随后真实页面成功打开，保留这一限制。浏览器视口恢复、标签关闭，harness退出0；未检查console，不声明零警告。19.K3/K4/K6/K7的正常双主题主图已有，K5仅补非法输入变体；K1/K2、等待/未知/拒绝/失效、图片失败、手动系统取消及生产/原生继续待验。迁移页面尚未改造，分支仍为草稿，未合并或部署。

### 迁移向导的 Cupertino 状态呈现

2026-11-16，MigrationPage 改用官方 CupertinoFormSection、CupertinoFormRow、标准绿色开关与自然增高的选择行。原作品、目标源、查询/候选、只读预览、复制选项、章节映射和提交各自分组；原作品与目标已有数据的保留说明交给官方次级页脚。错误采用独立 live region 和系统红，映射分页允许换行。原请求的 mutationId、内部键与 CAS 版本移入只读诊断弹窗，待确认主流程只显示原目标、复制范围、精确重试与返回。身份变化后隐藏旧操作，旧向导永久停用。

Controller 区分首次输入未就绪与已确认无目标源，并为读取输入、原章节、打开精确目标源、目标列表、预览和服务端确认提供实际进度。未确认操作重开时只读加载仍显示“读取迁移输入”，不误称正在等待写入确认；只有明确重试才再次发送原请求。精确重试成功保留原请求的目标名称；完成后不再重新读取输入并清空确认结果。原有三 CAS、generation、取消、映射上限和相同字节重试链保持。

新增浅/深×1x/2x、360×800 四项完整组件流程，实际复现并修复首次输入误报无目标源；前两份尝试日志因缺导入/不可用组件而未加载，不算界面复现。最终流程覆盖首次读取阻塞/503/明确重读、精确目标选择、预览次级色、打开确认零写、保存阻塞、丢确认、只读诊断/关闭、同会话重开只读等待、原请求精确重试和确认目标。测试通过真实滚动与点击等待转场，未用直接调用按钮回调替代操作；两次发送只应用一次，原请求正文相同。身份失效入口、原章节不可用、256 条上限、目标已有标记、取消和热门分页等既有回归保留。

迁移 controller、repository、matching、选择与主题合计65项不同定向回归通过；补充重开只读阻塞后19项迁移回归再次通过。完整格式化/校验后，三个改动文件严格分析无问题。固定 Flutter 3.50 / Dart 3.14，低优先级单并发，无本机 Flutter/AOT 构建。原始失败、滚动/转场诊断和最终结果留在忽略目录 `migration-states-{before-ui,after,after-fixes,pending-diagnostic,settled}.log`、`migration-cupertino-{related,reopen,analyze,final-format,format-check}.log`。这是组件与数据链证据；后续 CI 和正式 Web 分项见下文，不以组件流程替代全部状态、实际浏览器或生产验收。

后续按状态机复核发现：目标详情成功但权威预览失败时，原页面没有独立的只读重读入口。四种主题/文字组合再次实际复现后，新增“迁移预览尚未取得”分组，保留精确目标、未提交说明与只读重读；取得预览前不显示确认按钮。确认框同时列出原作品与目标的实际名称/源、分类复制选择及选中映射范围，不只依赖底层预览说明。19项迁移回归通过，原始失败/修复日志为 `migration-preview-retry-{before,after}.log`；预览失败的正式 Web 主图仍待。

### 迁移正常流程的正式 Web 分项

2026-11-16，`d19b69c`与`8c398d3`的完整 push/PR CI 均通过；后者的[push](https://github.com/Wybxc/karuyomi/actions/runs/43741507244)和[PR](https://github.com/Wybxc/karuyomi/actions/runs/43741513427)包含868项 Dart（22+87+759）、531项 Vitest、完整 Web 与 Wasm 构建。日志为 `ci-8c398d3-check.log`。采用该提交的 CI artifact `14173310464`（16,296,945字节），在下载边界核对 GitHub SHA-256 `333fb2938ea8dc8096aca90434d00035d1f0a6bb761c2d7d54324d8de5d45db5`，再核对39条 Flutter 资源；本机只通过官方 Vite 组装 Static Assets 与 acceptance entry，没有 Flutter/AOT 编译。

Codex 内置浏览器以360×800视口运行正式 Web，官方 `pnpm acceptance:serve` 使用临时 D1/R2、空 fixture 和 `acceptance-owner`。静态快照包含真实 xkcd、Komiic 两包，本轮仅操作 xkcd。深色跟随当前系统，浅色由 UI 明确保存后生效；这不是生产 Access 或原生验收。

深色由真实英文 xkcd 详情取得3,323章，收藏作品后，将 `2978: Stranded` 明确设为已读并添加书签。分别验证详情入口携带章节快照、书架入口先选范围、仅收藏/分类草稿、目标源菜单与 `xkcd · zh`。真实搜索 `xkcd` 成功为空，改浏览热门取得 `xkcd / SINGLE`，读取中文详情与权威预览。初始没有自动复制有歧义的标记；手动映射至中文 `2978: 困住` 后再明确勾选，确认框列出1条映射。返回检查保留草稿，随后重新确认；服务端结果为新增已读1章、书签1个，原作品保留。

浅色改由中文作品开始，实际读取697章，选择英文源，补齐范围、源菜单、搜索就绪/空态、热门结果、只读预览和目标章节查询。手动反向映射 `2978: 困住 → 2978: Stranded` 时，目标已有标记得到保留说明，复制勾选禁用。返回检查后重新明确提交，服务端结果为新增已读0章、书签0个，没有重复标记。两主题是同一账户的顺序验证，源方向和章节数不同，不算同数据像素叠图。

独立读取 settings、library、categories、双方 manga、bookmarks、progress 共九份响应，通过正式 Protobuf 模型核对：

- 深色从进入向导到目标列表，再到映射/确认取消，九份完整对象均与 `baseline-dark` 相同；提交只推进 accountRevision4→5、目标 revision0→1，并新增同一章的已读和书签各1项，不复制 current/furthest 页位。原作品及其标记、分类和全局设置保留。
- 浅色保存主题后的 `baseline-light-reverse` 到确认框和取消同样九份对象相同；反向提交只推进 accountRevision6→7、目标 revision3→4，双方已有标记保留，新增均为0。主题保存本身为 accountRevision5→6，未混入迁移结果。

原图为 `karuyomi-8c398d3-migration-{scope,categories-only,original-snapshot,source-choices,search-ready,search-empty,target-list,confirm,completed}-{light,dark}.jpg`，以及深色 `{preview,mapping,selected,chapter-choice}`、浅色 `{preview,preview-summary,existing-mapping,chapter-choice}`。九路快照、相等性/提交检查为同前缀 JSON，留在忽略目录。瞬态加载未取得稳定主图，不能把随后成功画面填作加载；浅色章节选择只取得查询变体，其余取消、占用和无匹配仍待。视口已恢复、临时标签已关闭，harness正常退出。

本次实拍保留三个未通过点：候选按钮缩成约80px宽窄卡片；同名源的原/目标摘要和确认没有语言；预览说明与50章文本合成巨大辅助描述。后续已直接让候选官方按钮填满分组，并在各阶段源摘要加语言，预览用官方 Semantics 分开子信息。四项浅/深×1x/2x回归先复现行宽，再复现说明合并；最终19项迁移回归核对行右侧点击、独立原/目标及保留说明语义、不同源语言、预览重读、等待/丢确认及精确重试全部通过，两文件最终格式的严格分析无问题。测试初版的语义句柄释放位置另已修正，不把该测试自身失败当产品缺陷。日志为 `migration-row-semantics-{before,after-width,after,final}.log` 与 `migration-row-analyze.log`。修复后的CI与正式Web见下文，`8c398d3`问题图仍保留。

### 迁移行宽、语言与语义的正式 Web 复验

2026-11-16，`9228c116aa7ca7587fc733adb9e607a80edce9a4`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43746307671)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43746312402)均成功，含868项Dart（22+87+759）、531项Vitest、完整Web及Wasm构建，分支部署跳过。日志为`ci-9228c11-check.log`。下载正式Web artifact `14174658196`（16,297,023字节），在传输边界核对GitHub归档SHA-256 `2a46df111d12724b5761ef6f76fdf1a9d8a6a53033b502c36a1c0c7e6f351bf6`，再核对39条Flutter资源。本机仅通过官方Vite组装静态资源和acceptance入口，没有Flutter或AOT编译。

Codex内置浏览器以360×800视口操作官方Wrangler临时D1/R2、空fixture和`acceptance-owner`；静态快照含xkcd和Komiic，仅使用xkcd。启动时Wrangler写用户目录日志受到沙箱限制，但正式harness正常服务，退出码0；不将这次启动记为零错误。深色跟随系统，浅色由UI保存。两主题均以真实英文xkcd的3,323章为原快照、中文xkcd为目标，原作没有已读或书签。

浅/深实拍均确认候选官方按钮填满320px分组，实际点击行右侧`(323,604)`打开正确目标；原作、目标、确认与完成摘要分别包含`en`和`zh`。预览DOM中标题、原作、目标、保留说明、复制选项和章节信息分别可读，不再合成50章的大段辅助描述。实际映射翻页至51–100/3323，打开`3274: Arthurian Connector`的章节选择，当前“不映射此章节”报告`aria-current=true`，`3062: Off by one（已占用）`确为禁用。输入“没有这个章节”取得无匹配画面，清空恢复当前项与禁用态，取消不改变原映射或页码。过滤仅有标记章节后，显示“原作品没有已读或有书签的章节。”。

确认框与取消、再次明确提交及完成均成对实拍。独立读取九路完整ProtoJSON对象核对：两主题预览、查询、分页、映射取消和确认取消均与各自baseline相同；两次明确确认均新增已读0、书签0，只推进一次账户与目标作品revision。深色账户2→3、中文目标0→1，浅色主题保存3→4后建立baseline，浅色迁移账户4→5、中文目标1→2；英文原作revision1及双方标记、分类和其它设置保留。快照与检查结果为`karuyomi-9228c11-migration-{baseline,preview-cancel,confirmed}-{light,dark}.json`及同前缀`*-check.json`，留在忽略目录。

原图前缀`karuyomi-9228c11-migration-`，两主题均有`{original-snapshot,search-ready,target-list,mapping-page2,chapter-choice,chapter-no-match,no-marks,confirm,completed}`；浅色另有`{scope,categories-only,search-empty}`，预览独立语义保存为`preview-{light,dark}.dom.txt`。源范围深色与搜索空态深色仍只有旧版问题图，加载/故障未取得主图，不用正常结果填补。已恢复浏览器视口、关闭临时标签并正常退出harness；不是生产Access或原生验收。

本轮新发现取消章节选择或确认后，画面可能先保持原处，再延迟向页面前段滚动，浅/深均观察到；分页、映射和复制草稿仍保留。证据为`choice-return-position-{light,dark}.jpg`及`delayed-return-position-light.jpg`，不将转场第一帧当稳定位置。带输入焦点的四种主题/字号组件流程中，滚动本身未复现，分别先复现章节选择和确认取消未恢复原按钮焦点；因此仅认定焦点缺陷已在组件复现，不声称已确定Web延迟滚动的唯一原因。后续直接以Hooks管理按钮FocusNode、保留原章节键，并在弹层前后恢复触发按钮焦点。19项迁移回归通过，核对取消后的原按钮焦点、滚动位置、键盘关闭及零写入；日志为`migration-return-{position-before,focus-before,focus-after-choice,focus-after}.log`。后续完整CI及正式Web实际点击证据见下项，原问题图保留。

### 迁移返回焦点与位置的正式 Web 复验

2026-11-16，`86d27e76198bda65e0d19261414759ab39f2a63e`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43750349677)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43750355450)均成功，含868项Dart（22+87+759）、531项Vitest、完整Web与Wasm，分支部署跳过。完整日志`ci-86d27e7-check.log`已取得。正式Web artifact `14176770930`为16,297,151字节，传输边界归档SHA-256核对为`cbea07f1835e72fe7a20ef2c7ebf0be52e714d341f0b1578719b22989a5428f5`，另核对39条Flutter资源；不重复计算已验证的归档摘要。本机只组装Vite静态资源及官方acceptance入口，没有Flutter或AOT编译。

Codex内置浏览器以360×800操作官方Wrangler临时D1/R2、空fixture和`acceptance-owner`。浅色跟随系统；深色由UI明确保存并获服务端确认。真实英文xkcd的3,323章快照与中文目标相同，原作没有已读或书签。深色另补范围未选、明确仅收藏/分类、读取原章节成功及搜索成功为空的完整主图，替换相应旧版问题图；瞬时读取画面没有稳定截图，不填入加载节点。

本轮刻意分开两种操作：使用语义定位点击的浅色一次记录中，按钮由y547变为393.5；后续定位开关曾报未匹配，再次观察已在页面前段。这些原图和DOM继续保留，工具自动滚动是可能影响，不据此认定唯一产品原因。全程以截图坐标实际点击打开章节页及导航返回箭头后，两主题的原按钮均保持位置并恢复`:focus`；章节页取消时保留“无匹配章节”查询焦点，以覆盖原失焦触发条件。第二页51–100、原章节3274及原映射不变。当前“不映射此章节”为`aria-current=true`，3062占用项仍禁用。

| 实际点击场景 | 打开前触发按钮y / 高度 | 返回后及跨工具延迟观测y / 高度 | 返回焦点 |
| ------------ | ---------------------- | ------------------------------ | -------- |
| 浅色章节选择 | 733 / 57               | 733 / 57                       | 原按钮   |
| 深色章节选择 | 731 / 57               | 731 / 57                       | 原按钮   |
| 浅色迁移确认 | 684 / 57               | 684 / 57                       | 原按钮   |
| 深色迁移确认 | 684 / 57               | 684 / 57                       | 原按钮   |

两主题均在无标记过滤后实际打开确认框，再点“返回检查”；焦点恢复和位置保持见上表。每次返回后先独立读取九路完整ProtoJSON，再检查按钮矩形，并在后续工具调用再次只读观测，不使用退场首帧作为稳定结果。`native-choice-cancel-{light,dark}`及`confirm-cancel-{light,dark}`与各主题baseline九路对象完全相同。浅色账户revision保持2，保存深色主题后为3并保持；原作revision1、目标未收藏，双方章节标记和书签仍为空。本轮没有提交迁移，不重复计入前版两次明确写入。

忽略目录原图前缀`karuyomi-86d27e7-migration-`，双主题有`{original-snapshot,search-empty,preview-summary,native-before,native-return,confirm,confirm-return}`；深色另有`{scope,categories-only,chapter-choice,chapter-no-match}`。`return-dom.json`记录按钮前后矩形、焦点、延迟观测和当前/禁用语义，`*-check.json`记录九路相等检查。`return-pair.jpg`及`confirm-return-pair.jpg`两份联系表已实看。语义定位动作的浅色问题图另存`choice-{trigger-before,trigger-return,coordinate-return,delayed-observation}-light.jpg`，不删除或当作实际点击通过证据。已恢复视口并关闭临时标签，官方harness正常退出0。全部输入方式、状态变体、加载/故障、真实读屏、生产及原生仍未完成；这些分项不因本轮返回流程通过而清零。

### 本漫画阅读设置的阶段与确认

2026-11-16，共用设置编辑器的四项浅/深×1x/2x组件流程，在360×800下均先复现首次读取没有文字说明，且误显示“连接并确认身份后可读取和保存同步设置。”。当时身份已确认，仅漫画设置的只读请求尚未返回；不能把尚无快照解释为尚无身份。日志为`settings-state-before.log`。

实现以`SettingsActivity.reading/saving`替代独立busy字段，busy由活动推导；保存和读取的禁用条件继续沿用原控制器。明确显示“正在读取服务端设置”或“正在等待服务端确认设置修改”，进度与待确认说明采用13px次级文字。保存等待时不再显示尚未提交草稿，正在只读重取时仍保留未提交草稿提示；继承说明移入阅读显示的官方Cupertino分组页脚。首次失败、原提交未知、版本冲突、明确拒绝与身份变化的既有业务分支和恢复动作保留，不增加兼容层或新保存通道。

四项完整流程分别核对：阻塞首次读取→失败→明确重读；本漫画从左到右→从右到左草稿；提交后阻塞确认、禁止关闭与重复修改；已提交丢确认→再次读取失败→精确重试。两次POST正文相同且只应用一次。另核对带本地草稿的阻塞只读重取，读取说明与未保存提示共存，零附写；明确重取成功才丢弃该草稿并恢复已确认值。之后由第二客户端真实发出协议写入制造CAS冲突，原编辑器保持冻结且无精确重试入口，明确重读只读回远端双页设置，不自动重基或重发。最后模拟Access返回登录HTML，旧字段与旧确认消失，没有额外POST。

随后在源目录和阅读器工具实际调用点发现，外层条件仍只在无快照、错误或未知结果时显示共享状态。阻塞源收藏确认及浅/深阅读模式修改的三项回归在旧条件下均失败，见`settings-consumers-before-valid.log`；将活动期间纳入呈现条件后，确认到达前保留原快照、禁用重复动作并显示等待说明，确认后更新快照且原提交只有一条。测试最初的菜单计时与异步屏障问题另存日志，不能作为产品缺口依据。

最终五个相关测试文件的50项不同回归通过：`settings_controller_test`、`settings_widgets_test`、`settings_navigation_test`、`source_favorites_navigation_test`和`chapter_reader_route_test`，日志为`settings-state-regressions-final.log`。七个修改Dart文件严格分析零问题，完整格式化/校验、依赖分层和标准prek通过；迁移24节点及本漫画设置11节点的图表ID一致性检查通过，后者不代表截图验收。新增四种主题/文字组合在同一流程覆盖读取、保存、未知、冲突和身份失效；明确非冲突拒绝、全部字段、真实键盘及减少动态仍单列。测试使用生成协议与组件测试supplier，不是正式D1、Source在线、浏览器或生产证据。Riverpod代码已用固定generator重生；完整CI与正式Web各状态双主题继续待验，24.K1–K11主图不填入组件结果。

### 正式 Web 浅色故障流程与关闭反馈修复

2026-11-16，`42bc9bb92b5dca0f57974cc64821a6f559484b3f`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43788163867)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43788287368)完整成功，push正式Web及Wasm构建均通过，部署未触发。正式客户端归档artifact `14191277471`在传输边界核对GitHub摘要`8861d4c0053abd3af6850ad7449cc540b7d984269605fb617bc01983b06ed67e`，39项Flutter资源复用既有核验收据，不重复计算归档摘要；本机没有编译Flutter或AOT。

通过官方Vite acceptance入口、Wrangler harness、临时D1与内置浏览器360×800执行，正式客户端没有插桩。配套测试入口随本次修改增加`settings-ui`夹具，生产入口不启用；stdin选择读取阻塞/失败、提交后阻塞/丢确认、明确拒绝和登录HTML。阻塞最长30秒且检查取消，审计最多256条；12项官方Workers/D1集成回归及API/test严格类型检查通过，命令见[工具说明](../TOOLING.md)。fixture的503、400与401不是生产故障或真实Access证据；CAS冲突由第二独立客户端使用正式协议修改产生。

使用真实xkcd扩展与3323 Meteor Fear的两页内容，先通过UI确认浅色、安装并收藏英文源。漫画key为`62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f`。随后执行首次读取/读取失败、已确认继承、草稿、等待提交、丢确认、未知命令下重读失败/重读等待、精确重试、第二客户端竞争、冲突后明确重读、明确拒绝和身份失效。源收藏等待另有浅色图。所有画面与AX分开保留；未取得深色，不提升双主题主图计数。

独立脚本使用生成的ProtoJSON模型读取global/manga settings、library/categories、manga state/progress/bookmarks七路。最终解析完整harness日志中的43条设置审计，漫画POST六次，包含三条不同成功原命令、一次同UUID/CAS/精确正文重试、一次409与一次派发前400。七阶段账户revision为5→6→7→7→8→8→8，漫画设置revision为0→1→2→2→3→3→3，全局revision保持3。确认门阻塞时D1已提交；未知→精确重试的七路对象完全相同，远端获胜→冲突重读→拒绝后的七路对象也完全相同。其余业务快照除账户revision外全程不变，没有因读取、拒绝或重试增加附带提交。

原始材料前缀为`.local/mihon-reference/karuyomi-42bc9bb-settings-`：`{baseline,waiting,unknown,retried,remote-won,conflict-reloaded,rejected}-light.json`、`audit.json`和`evidence-receipt.json`记录独立审计；`states-light-{0,1}.jpg`两张联系表已实看。`initial-reading-light`是尚未完成呈现的过渡画面，首次hold-read门后来超过30秒，sequence13没有完成响应状态；该次不算释放成功，后续`initial-read-error-light`记录实际失败。`draft-light`的AX选值与JPEG旧字段不一致，保留且排除主图；`draft-status-light`只证明滚到底可见未保存提示。不得根据AX或文件名替代稳定画面验收。

实拍和组件共同确认两个缺口：读取时`busy`错误地禁止返回；长表单的反馈位于滚动末端，却有独立固定保存按钮，导致用户在首屏保存时看不到确认状态。新增浅/深×1x/2x八项流程在旧实现均失败：四项读取关闭检查失败，另四项已确认反馈在视口外。修复仅在保存活动时禁止关闭，漫画表单继续独立滚动，原共享反馈固定在操作区上方；全局设置继续复用同一反馈，不复制状态分支或新增保存通道。八项流程修复后通过，另检查草稿/等待/未知/重读反馈实际可命中，读取中关闭后迟到结果不跳回编辑面且零写入，保存等待仍禁止返回，精确重试和冲突规则保持。

最终五文件54项定向回归通过，见`settings-footer-regressions-final.log`，两文件严格分析零问题；新增fixture的12项回归见`settings-ui-fixture-regressions-final.log`。新修复完整格式/CI与正式Web双主题继续待验，不以组件通过或旧浅色图填写新最终主图。临时标签已关闭，视口已恢复，官方harness正常退出0；本轮没有生产Access或原生现场验收。

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

## 编辑面顶部操作收敛

2026-11-16，将既有9个EditSheet调用点集中改为官方CupertinoNavigationBar：Source筛选、Source偏好及多选、漫画阅读设置、分类管理及编辑、书架批量、章节批量和封面编辑。编辑时关闭/取消在起始侧、保存/应用在末尾侧；分类管理与已结束批次的“完成”在末尾侧。长操作使用简短可见标签及完整辅助语义，危险提交采用系统红文字；刷新、重置、暂停和结束原批次进入滚动内容。本漫画反馈固定在导航下方，不随长表单离开视口。

- 新增4项浅/深×1x/2x布局用例。在320×640、240px键盘遮挡下，顶部操作保持可点击，正文末端可滚动到达，输入和零自动提交保持。旧实现四项均先失败，动作底边为628px而要求顶部64px内；新实现四项通过，完整保存语义也单独匹配实际语义节点。
- 定向验证覆盖9份文件的115个不同用例，改动收敛后按影响范围分组通过；最后调整完成按钮位置后重跑对应45项业务用例及4项布局用例。包含读取可关闭、保存期间禁用、未确认原操作保留、精确重试、CAS冲突、部分批次、身份更替、迟到回复与封面资源生命周期；未改业务控制器、协议或服务端。
- 可复验命令为`flutter test --no-pub --concurrency=1`，文件：`test/widgets/edit_sheet_test.dart`、`test/sources/source_preferences_widget_test.dart`、`test/sources/source_filters_widget_test.dart`、`test/settings/settings_widgets_test.dart`、`test/settings/settings_navigation_test.dart`、`test/library/category_page_test.dart`、`test/library/library_batch_page_test.dart`、`test/browse/chapter_read_navigation_test.dart`、`test/covers/cover_navigation_test.dart`。日志保存在忽略目录的`edit-sheet-regressions-final.log`、`edit-sheet-completion-regressions.log`和`edit-sheet-layout-final.log`；前两者中间失败属于测试语义选择/释放的修正，最终布局用例已通过，不把中间失败说成整轮成功。

最近的正式版本`f015956`已通过[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43794985695)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43794994599)，包含Web/Wasm，分支未部署。该版隔离正式Web补得浅色完整设置故障流程和深色读取关闭、等待、未知重开、精确重试、真实409及重读；共74条原始设置审计保存在`karuyomi-f015956-settings-harness.log`，独立API快照与JPG/AX以`karuyomi-f015956-settings-`为前缀。初始挂起门超时记录保留；深色拒绝/失效、逐图复核和快照汇总未完成，不填最终主图。为避免继续验收即将替换的布局，已收存证据、恢复视口并关闭临时标签，harness正常退出。

顶部导航提交`bcac70481a7d7cd8a7cc0c80d66090a8d21a98e6`已通过[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43800842514)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43800848771)，包含完整检查和Web/Wasm。正式Web分项如下；全部编辑面、真实Access和生产读写仍待。原始日志不提交，用户的pnpm锁文件保持原样且不纳入本次提交。

## 顶部导航正式 Web 的设置状态复验

2026-11-16，复用`bcac704`的CI Web artifact `14195694580`（16,297,509字节，下载边界核对GitHub SHA-256 `20b479a149d2e331a4c75afe058e5d1da5e41dce01e4415913cc105fbcf20c97`），再核对39条Flutter资源清单。通过正式Vite入口组装既有xkcd/Komiic扩展快照与runtime，官方Wrangler harness的`settings-ui`夹具、临时D1和内置浏览器360×800执行；未本机重编Flutter或AOT。真实源为xkcd英文，指定3323章Meteor Fear的2页中第1页。

24.K1–K10各取得浅/深主图，文件为`karuyomi-bcac704-settings-k{1..10}-{light,dark}.jpg`，同名TXT保留AX；三张`karuyomi-bcac704-settings-paired-{1,2,3}.png`已逐图实看。导航标题及关闭/保存保持顶部，读取、确认、草稿、未知、冲突、拒绝与后续读取错误分别呈现，反馈固定在长表单上方。浅色初始全继承，深色继承前一流程的已确认覆盖值；只计状态与颜色角色，不计同数据像素叠图。

两主题分别执行首次读取失败→挂起重读→关闭→迟到响应、草稿→关闭、保存等待→确认、实际写入后丢确认→失败重读→挂起重读关闭→重开原命令→精确重试、独立第二客户端修改→真实409→只读恢复、合法ProtoJSON明确拒绝及401 HTML失效。深色等待确认时另实际点按关闭，编辑器保持打开；关闭读取后迟到响应均未重新导航。401、503及提交交付502为隔离故障注入，不是生产Access或生产故障证据。

`karuyomi-bcac704-settings-harness.log`保存81条请求审计，18组API快照各核对global/manga settings、library、categories、state、progress与bookmarks；复验脚本为`node .local/mihon-reference/verify-bcac704-settings-evidence.ts`。结果：

- 浅色账户revision为3→4→5→6，漫画0→1→2→3；深色账户8→9→10→11，漫画3→4→5→6。各主题内global设置及其它五路业务数据保持不变，只有明确漫画命令推进版本。
- 共12次漫画设置POST，其中4次UI明确成功写入、2次第二客户端写入、2次原命令精确重试、2次409和2次400；两次重试的请求正文/UUID与各自丢确认原命令完全相同，全部七路快照不变。冲突及拒绝后的快照与远端获胜快照完全相同，草稿取消前后也完全相同。
- 四次挂起读取全部正常释放，无超时或未完成审计。其余3次global写入是明确安装、主题保存及源收藏。全局浅色等待、确认后深色、深色源收藏等待及双主题阅读工具不可用/待确认提示只计这些实际分项，不外推共享控件全部状态。

24.K11的两个旧画面保留但不填通过：浅色截图缺完整导航，深色失效时应用因已确认账户不可用而跟随系统浅色（`main.dart`按`state.available`取主题），需补稳定帧及系统深色外观。AX已确认旧字段、旧确认和保存入口隐藏，独立快照确认失效区间零写入；这些行为结果不代替完整双主题画面。其余8处EditSheet正式Web、各阶段身份变化、所有字段/字号/键盘/减少动态变体与生产闭环仍待。

本轮新增10对主图，Karuyomi跨版本已登记主图从79增至89/169；该计数不代表最新HEAD的全范围验收。临时标签已关闭、视口已恢复，harness正常退出0；没有新增真机或真实生产Access结论。

## 顶部导航其余编辑面的正式 Web 复验

2026-11-16，继续复用同一`bcac704`CI artifact和既有扩展，不重新下载、重复哈希或本机重编Flutter/AOT。官方Wrangler harness使用`categories`夹具、临时D1、测试身份`acceptance-owner`，入口`http://127.0.0.1:50003/`；Codex内置浏览器360×800分别执行浅/深流程。该夹具没有`settings-ui`请求审计控制，本轮不复用上一节81条审计或18组快照的数量。

| 编辑范围                       | 实际执行与证据边界                                                                                                                                                                                                                              |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 分类管理、名称编辑与单作品选择 | 空态/列表、新建草稿取消、重命名/空名称校验、菜单和危险删除预览均双主题复验；真实删除最后两分类后，06.K1保留作品名、无分类指引及顶部取消，取消零附写。                                                                                           |
| 书架批量                       | 两主题分别明确添加同一分类至两部fixture作品，均获2/2确认；中间独立API复位两项以建立相同输入，另保存receipt。移出书架只预览和取消，没有移除收藏。                                                                                                |
| 封面                           | 两主题分别选图草稿→保存确认→清除草稿→清除确认。120×180测试PNG经正式客户端转换为4,428字节JPEG；草稿均零权威写入，四次明确保存各推进一次作品revision。                                                                                            |
| 章节批量                       | 真实xkcd当前首项为3324，实际选来源第2/3项的3323: Meteor Fear和3322: Dragonfly。深色标已读2/2→标未读复位2/2，浅色再标已读2/2；没有创建续读位置或书签。不替换原六章范围主图。                                                                     |
| Source偏好主面                 | 动漫屋1.6.3镜像菜单Escape取消、真实会话开关及独立新文档默认值恢复双主题通过；共5次会话开关修改，均零账户写入。unsupported Cookie保留原storage key限制，没有执行动作。14.K4仅取得修改确认后重开/重取描述的处理中变体，不代表账户未知或保存等待。 |
| Source筛选与多选子面           | xkcd无额外筛选的取消、内容重置及真实应用双主题通过，返回搜索空结果，七路API零附写。MangaDex af仅尝试一次，运行容器中断，未进入真实多选子面；英文Source历史失败同样保留，不记兼容通过。                                                          |

正常状态图/JPG与AX共同前缀为`karuyomi-bcac704-editors-`；27对集中联系表为`bcac704-editors-category-pairs-{1..7}.png`和`bcac704-editors-other-pairs-{1..7}.png`，已逐图实看，必要时回看原始360×800图核对导航。深色分类删除及批量移出初次残帧另存`dark-incomplete.jpg`，稳定重拍完整后才计该分项；首次Source processing图实际已完成，未填14.K4，改用两主题真实0→1后的`source-preference-writing-on`图。JPEG不作为Mihon原始PNG或精确颜色采样。

独立快照为31组七路global/manga settings、library、categories、state、progress、bookmarks，以及21组三路categories/library/settings。`node .local/mihon-reference/verify-bcac704-editors-evidence.ts`使用生成的Protobuf模型严格解析并比较，严格TypeScript检查通过，receipt为`bcac704-editors-evidence-receipt.json`：

- 最终accountRevision30、globalRevision7、xkcd业务mangaRevision11；独立漫画阅读设置revision仍0，不与业务作品revision混用。
- 版本算术为2次初始fixture应用、2次独立复位、26次已确认UI账户应用；UI应用包括创建/删除分类、两次各两作品的批量、4扩展安装、xkcd收藏、4封面、6章节标记及3次主题。该结果不是HTTP请求尝试次数，本轮无请求审计。
- 名称草稿/校验/危险预览取消、单作品选择取消及无分类指引、批量移出取消、封面选图/清除草稿、Source会话与筛选区间均零附写；删分类保留收藏、章节标记和续读状态。临时复位工具最初缺catalog revision的409没有写入，不算产品UI冲突验收。

新增06.K1、14.K4、14.K9三对主图，跨版本已登记主图89→92/169（54.4%）；其余旧节点重拍不增加分子。结合上一节本漫画设置，9处编辑面中8处已有正常主流程的正式产物分项；多选子面、24.K11、共享30.K各业务范围、故障、键盘/大字/减少动态、全部转换及真实生产仍待，不外推8组全状态通过。`bd2d33b`两条文档CI（43805049596、43805042557）也已成功；本轮未修改产品源码，PR继续草稿、未部署。临时标签已关闭、视口恢复，harness正常退出0。

## 短编辑内容的导航起点修复

2026-11-16，复核上一节正式封面JPG时确认导航与首个表单之间有大段空白。共享`EditSheet`使用`Center`，短`SingleChildScrollView`按内容高度垂直居中，读取、已确认值和选图草稿切换也改变正文起点。四项实际封面组件流程（浅/深×1x/2x）新增位置断言后均先失败：导航底为108px，正文顶为366px（1x）或318.5px（2x），分别空出258px和210.5px。原图保留为历史，不能据其称最终布局已通过。

共享编辑面改用顶部水平居中排列，继续保留原640px最大阅读宽度和安全区；空分类指引与作品说明统一16px水平边距。未修改提交、取消、CAS、原请求或资源生命周期。`flutter test --no-pub --concurrency=1 test/widgets/edit_sheet_test.dart test/covers/cover_navigation_test.dart`全部14项通过，原四项流程在读取、无封面和选图草稿阶段的正文顶均与导航底相接；其余用例继续核对键盘遮挡下顶部动作、确认/丢确认、精确重试、拒绝、身份更替及迟到选图。三个改动Dart文件严格分析通过；日志为`edit-sheet-top-content-{before,after,analysis}.log`。

修复提交`0e605c5743b0c30bf2c5f91c09c300760af32b2a`已通过[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43814852391)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43815059269)，包含完整检查及Web/Wasm；分支未部署。CI Web artifact `14202372551`为16,297,491字节，下载边界核对GitHub SHA-256 `42f9e78846290b6f2790c4d842d21339ad5aa8f720bb8b5fdaa0ee33db2be09d`及35条公开Flutter资源清单，再通过正式Vite入口组装既有四源快照与runtime。未在本机重编Flutter或AOT。

官方Wrangler harness的`categories`夹具、临时D1、`acceptance-owner`与内置浏览器360×800完成双主题复验：无分类指引左右边距正确；无封面、已确认封面和清除草稿始终从导航下方开始排列，未再出现随内容高度变化的大段顶部留白。浅色执行选图草稿→保存确认→清除草稿→关闭取消，深色读回该封面→清除草稿→保存确认。正常主图/JPG与AX前缀为`karuyomi-0e605c5-editors-`，均已实看；浅色另有选图处理中图，深色选图、首次/替换图片草稿与手动系统取消未补验，不新增成对状态计数。

`node .local/mihon-reference/verify-0e605c5-editors-evidence.ts`以生成的Protobuf模型严格解析16组六路API快照，脚本严格TypeScript检查通过，receipt为`0e605c5-editors-evidence-receipt.json`。两次初始fixture写入及两次独立API安装/收藏预置后accountRevision为4；三次已确认UI应用仅为浅色封面保存、主题保存和深色清除，最终accountRevision7、globalRevision2、作品revision3。分类查看/取消、选图/清除草稿、取消清除及关闭浏览器均无额外写入，其他作品、分类、章节进度及书签保持不变。此夹具没有请求审计，不能据版本算术外推POST尝试次数；API预置不计UI安装验收。

06.K1、19.K3/K4/K7主图更新到本次正式产物，旧图保留作历史；19.K5仅补浅色候选，覆盖保持92/169。遵照新增的文件传输指引，深色复用已保存的测试封面，未再次通过浏览器传文件。临时标签已关闭、视口恢复，harness正常退出0。其余编辑面状态、全部变体及真实生产闭环仍待。

## 封面读取关闭与故障验收入口

2026-11-16，按剩余19.K分支准备正式Web复验时，发现封面将所有busy阶段一并禁止关闭，纯读取也会困住用户。浅/深×1x/2x四项组件流程先复现关闭按钮禁用；改为读取期间允许关闭，选图和保存继续禁用，身份失效后允许退出。四项流程用实际点按关闭，释放迟到读回后编辑面没有重新出现、Source调用和服务端写入均无增加。完整封面/共享编辑面18项回归通过，其中原四项状态流程另断言选图和保存期间的关闭动作仍禁用。日志为`cover-read-close-{before,targeted,after}.log`；测试最初的夹具/转场同步修正不计产品缺陷，before日志保留最终四项真实禁用失败。

原设置故障夹具直接收敛为`editor-ui`，共享有界控制和请求审计，增加cover范围的真实作品读取、JSON清除及私有图片字节；没有另建一套故障框架。12项官方Workers/D1/R2回归通过，含读取等待/取消、实际提交后等待确认、丢确认后的同正文重试零重复、旧版本真实409、明确拒绝/登录HTML零覆盖，以及字节503后重取同一资源且记录不变。multipart预置沿用正式API，审计不保留图片字节，当前命令见[工具说明](../TOOLING.md)。API/test严格类型检查通过；完整CI与新版本正式Web画面仍待，状态主图暂不增加。

## 封面故障状态的正式 Web 复验

2026-11-16，`a9d880abf2aad9769c567184873ddfcfa4bf53f0`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43842802780)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43843112755)完整成功，包含Web/Wasm。正式Web归档artifact14213699093为16,297,569字节，下载边界核对GitHub SHA-256 `186583228e69fb0ed52b24aa136f364d4ab132958103867c869af1660b058409`，再核对39条Flutter资源。只复制CI生成目录并经正式Vite配置组装，复用四源快照，没有本机Flutter编译或AOT。

官方Wrangler `editor-ui`、临时D1/R2、`acceptance-owner`、`http://127.0.0.1:64292`与Codex内置浏览器360×800执行双主题验收。浅色由API预置，深色通过UI明确保存并获确认。图片通过CLI调用正式multipart API预置，不经浏览器传文件；这不是UI选图或上传验收。

| 分项  | 实际结果与边界                                                                                                                                     |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| K1/K2 | 读取进度、允许关闭、未确认状态与失败重读分别呈现；两主题实际关闭后，迟到读回未重开窗口。三次读取挂起均释放为200，六次受控读取失败返回503。         |
| K8    | 两主题取得保留原封面、原清除命令和等待确认主图。深色在等待中实际点击稍后处理，窗口未关闭；随后释放回执并显示已确认无封面。仅验清除，替换等待仍待。 |
| K9    | 两次真实提交后返回502；关闭重开并再遇读取失败，原清除命令仍保留。明确重试复用同UUID及完整正文，确认后账户/作品revision没有再次增加。               |
| K10   | 两次明确400及独立API更新后的两次真实409均无覆盖。明确重读可恢复权威封面，冲突后再次读取失败仍保留上次确认快照。                                    |
| K12   | 两主题的详情与编辑器分别遇到私有图片503，共四条失败响应；编辑器重试同一路径后返回200并恢复图片。六路业务快照不变，未上传或清除记录。               |

`verify-a9d880a-cover-evidence.ts`使用生成Protobuf模型解析32组六路API快照，并核对154条真实请求审计。11次UI封面JSON尝试对应四条成功清除原命令、三次原命令重试、两次409与两次400；其中两次重试针对502，另一次恢复首次未完成的浅色挂起。9次独立multipart封面预置及初始设置/收藏共11次API准备，与UI清除四次及主题一次分开记录。最终accountRevision16、globalRevision2、作品revision14；分类、资料、收藏关系、阅读进度与书签均无额外变化。

浅色首次等待虽取得有效主图，但释放前已转为结果未知，审计sequence20的Worker/client状态均未完成；不把该门计为释放成功，也不据此声称首次HTTP状态。其同正文精确重试与前后独立快照确认没有重复应用。深色挂起正常完成。自动化`isEnabled()`曾将视觉禁用按钮报告为true，未采用该值作为禁用证据；组件回归及深色实际点击结果分别保留。深色K1首次截图为转场中间帧，保存为`cover-k1-transition-dark.jpg`并排除主图，稳定重拍后才登记。

原始JPG与同名完整AX以`karuyomi-a9d880a-cover-`为前缀，主图`k{1,2,8,9,10,12}-{light,dark}`及恢复、读取失败、真实冲突变体均已实看；三张`a9d880a-cover-{reading,save,errors}-pairs.jpg`联系表已实看。独立快照、API准备回执、`harness.log`、`audit.json`、`evidence-receipt.json`与校验日志保存在忽略目录。读取、提交、拒绝、恢复及图片失败的主图信息分别完整；明确拒绝后的辅助说明仍引用不存在的重试动作，登记为实际文案缺口，未宣称该分支全部交互说明已收敛。

新增六对主图使跨版本覆盖92→98/169（58.0%），不是PR整体或当前HEAD全部状态完成率。K5深色处理中、手动系统取消、替换提交/故障、K11全部失效阶段、原生及真实生产继续待验。临时标签已关闭、视口恢复，harness正常退出0；PR继续草稿、分支未部署。

## 明确拒绝状态与迁移故障验收入口

2026-11-16，依据封面正式双主题拒绝画面，修正页脚仍建议不可用重试的缺口：已拒绝状态引导重新读取后再修改；结果未知继续保留精确重试说明。迁移控制器也有同类问题，新增真实组件supplier的400拒绝流程先复现错误提示，再修正为明确重读。核对原请求保留、提交与重试均无新POST、读取后才能恢复编辑，原作品/目标及应用次数不变。

低优先级单并发运行`flutter test --no-pub --concurrency=1 test/covers/cover_navigation_test.dart test/widgets/edit_sheet_test.dart test/migration/migration_controller_test.dart test/data/source_migration_repository_test.dart`，52项通过，含浅/深×1x/2x、读取关闭、CAS与丢确认精确重试。三份改动Dart严格分析、API/test严格类型及依赖分层通过；本机未执行完整Flutter或AOT编译。

现有editor-ui只新增migration范围，控制命令见[工具说明](../TOOLING.md)。正式`migrateFrom`仍执行真实D1事务，等待与丢确认发生在成功提交之后；明确拒绝在提交前返回类型正确的400，不伪造成功。17项官方Workers/D1/R2回归通过，含挂起释放与取消、迁移原作品保留、目标仅应用一次、相同正文重试及新旧请求真实409。分页和Source调用保持实际链路。尚未取得本次正式Web双主题证据，不增加98/169主图计数，也不以受控登录响应代替真实Access。

## 仍需的证据

全部 ID 的参考画面和像素基准、布局复刻前后叠图、配色对比、自然 Cupertino 调整、最终多视口/亮暗/文字/输入核对、完整工程检查和真实业务验收仍待完成。Mihon 参考模拟器与 Karuyomi 原生现场验收分开记录；不使用已停止的真机流程填补本轮 Web 证据。
