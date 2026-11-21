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
- 用户已允许本机参考模拟器；复用仓库 Android SDK 与 API 36 arm64 镜像，单实例 `mihon-reference` 已启动完成，720×1600、320dpi，即 360×800 逻辑视口。AVD配置2核/2048MB，但启动日志记录上调至2560MB，不能称作实际2GB内存验收；Guest内存和宿主RSS未独立测量。官方 arm64 APK 的 SHA-256 与发布页一致：`0026bd25ce5b1c6bdc5bd2c9589a08a811ddc4fa7c994cf937729d5b7010619d`。早期采集仍为 Monet，不能算固定主题证据；随后在外观页明确选中第一张 DEFAULT 卡，`settings-appearance-default-dark` 确认卡片选中及背景采样 `#1B1B1F`。后续带 `default-dark` 的有效截图据此采集。系统顶部 68dp、底部约 24dp 单独计量。
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

参考采集命令使用固定模拟器 `adb -s emulator-5574 shell uiautomator dump` 与 `exec-out screencap -p`。终端访问 GitHub 发布附件需使用本机已配置的网络代理；最初的部分下载均未通过完整性门槛，不作为参考安装输入。

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

随后对历史 `2512c51` 双主题安装确认后的 xkcd 行测量。相同 360×800 逻辑视口下，Mihon 行宽 360、高 64，Karuyomi 的 Cupertino 分组卡片约宽 320、高 57，卡片各侧内收 20，名称墨迹左沿约 x=84。两端版本、图标、上方操作反馈和环境不同，纵向绝对位置不做匹配判定。Web 浅色背景与白色表面、深色黑色背景与深灰表面以历史 JPEG 近似样本记录。测量文件为 `extension-installed-xkcd-layout-measurement.json`。

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

`states-light-{0,1}.jpg`两张联系表已实看。`initial-reading-light`是尚未完成呈现的过渡画面，首次hold-read门后来超过30秒，sequence13没有完成响应状态；该次不算释放成功，后续`initial-read-error-light`记录实际失败。`draft-light`的AX选值与JPEG旧字段不一致，保留且排除主图；`draft-status-light`只证明滚到底可见未保存提示。不得根据AX或文件名替代稳定画面验收。

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

当轮记录了 81 条请求审计，18组API快照各核对global/manga settings、library、categories、state、progress与bookmarks；结果：

- 浅色账户revision为3→4→5→6，漫画0→1→2→3；深色账户8→9→10→11，漫画3→4→5→6。各主题内global设置及其它五路业务数据保持不变，只有明确漫画命令推进版本。
- 共12次漫画设置POST，其中4次UI明确成功写入、2次第二客户端写入、2次原命令精确重试、2次409和2次400；两次重试的请求正文/UUID与各自丢确认原命令完全相同，全部七路快照不变。冲突及拒绝后的快照与远端获胜快照完全相同，草稿取消前后也完全相同。
- 四次挂起读取全部正常释放，无超时或未完成审计。其余3次global写入是明确安装、主题保存及源收藏。全局浅色等待、确认后深色、深色源收藏等待及双主题阅读工具不可用/待确认提示只计这些实际分项，不外推共享控件全部状态。

24.K11的两个旧画面保留但不填通过：浅色截图缺完整导航，深色失效时应用因已确认账户不可用而跟随系统浅色（`main.dart`按`state.available`取主题），需补稳定帧及系统深色外观。AX已确认旧字段、旧确认和保存入口隐藏，独立快照确认失效区间零写入；这些行为结果不代替完整双主题画面。其余8处EditSheet正式Web、各阶段身份变化、所有字段/字号/键盘/减少动态变体与生产闭环仍待。

本轮新增10对主图，Karuyomi跨版本已登记主图从79增至89/169；该计数不代表最新HEAD的全范围验收。临时标签已关闭、视口已恢复，harness正常退出0；没有新增真机或真实生产Access结论。

## 设置分栏切换与键盘焦点

2026-11-21，复核固定 Mihon 0.21.3 的 26.04 浅深原图和 UI 树。1536×2048、2× 画面归一为 768×1024，两栏分界为 x=384，左栏外观项名称位于 `[72,167,104,195)`，右栏「外观」标题位于 `[400,103,444,135)`。Karuyomi 保留相同的分栏位置，使用 Cupertino 居中导航标题和 inset grouped 目录。在 768×1024 的两色 Web 中，目录外观整行和详情标题的辅助范围分别为 `[20,64,364,112)` 和 `[535,10,617,35)`。选中行与普通行的 JPEG 采样分别为浅色 `#EFEFEF`、`#FFFFFF`，深色 `#323136`、`#1C1C1E`。[原样参考与范围](mihon-state-coverage.md)

基准 `83351b0` 中，已聚焦的「返回」因进入双栏而消失，浏览器焦点落到应用根部。中间版复验确认进入双栏可交接焦点，缩回单栏仍需再按 Tab。最终 `3e25459` 使用独立焦点域，只在当前焦点控件因换栏被移除时交接。浅深两色均从 599×820 的「关于」详情用真实 Tab 聚焦「返回」，改到 600×820 后焦点落到目录的「关于」。再换到 844×390，仍显示同一详情，焦点直接落到「返回」，Enter 可回到目录。

`3e25459` 的两套正式 Web 验收入口与正常构建的客户端入口逐字节相等，入口 SHA-256 为 `d6ac543a5fa05880d142b6941d3bf5f1b415403daa89cbc9b882d921a70138e8`。在两个独立 Wrangler 和 D1 测试账号的 Codex 内置浏览器中，五个栏目均用键盘打开，取得 360×800 与 768×1024 的浅深画面。宽屏五个目录动作各自唯一，仅当前项报告 `aria-current=true`。外观、阅读背景、阅读快捷键和只读服务地址在换宽后保留焦点，离开连接详情后无旧文本框语义。[界面实现](../../apps/reader/lib/features/settings/settings_widgets.dart) · [官方验收入口](../../apps/api/test/README.md)

两色将阅读背景设为白色草稿，换栏、跨栏目和返回后重进均保留草稿。设置、书架和分类三路权威快照在上述阶段逐字节相等。深色用 `editor hold-confirm global` 暂扣已提交的原回执，等待中改为双栏仍标记「阅读显示」为当前项，保存报告禁用。放行后只确认原操作。审计每色各一次 UI 设置 POST，账户与全局设置 revision 从 1 到 2，准确变更阅读背景。两个新文档均读回已确认值，新文档前后的三路快照逐字节相等。

浅深各一项 Flutter 回归先后复现两个方向的缺口，最终双向通过。994 项 Flutter 测试、两文件严格分析、正式 Web release 构建和完整格式、依赖分层检查通过。验收服务与标签已关闭。浏览器复验使用默认字号，系统大字、原生可编辑地址及其余变体继续验收。[焦点回归](../../apps/reader/test/settings/settings_widgets_test.dart)

## 跨源搜索短屏与重新选源

2026-11-21，复核固定 Mihon 0.21.3 的 15.01 与 15.03 浅深原图和 UI 树。原图为 720×1600、320dpi。归一到 360×800 后，输入 `one piece` 的查询框为 `[56,72,304,128)`，紧接其下的是「已置顶」「全部」「有结果」。15.03 的 MangaDex All 首幅封面从 y=241 开始。Karuyomi 的选源和提交由用户明确触发，使用 Cupertino 查询框、按钮和分组。以下 Karuyomi 量测为桌面 Web 的逻辑像素和无障碍边界，Mihon 原图另含 Android 系统区域。[Mihon 参考像素](#15-跨源搜索参考像素基准)

使用两个独立 Wrangler acceptance harness 和临时 D1 账户，安装现有 MangaDex 1.6.1 与 xkcd 1.6.1，合计 66 个 Source。基线 `70715f4` 中，360×480 浅色点选英语 xkcd 后，查询仍在顶部，刷新和提交需滚至第一组 50 项的末尾。此时提交在 `[16,407,172,464)`，查询已离开视口。最终 `872a121` 在两色的量测如下。

| 操作或状态              | 查询框           | 搜索所选漫画源    |
| ----------------------- | ---------------- | ----------------- |
| 360×480，范围展开顶部   | `[16,52,352,97)` | `[16,99,172,156)` |
| 360×480，滚至首组末尾   | `[16,52,352,97)` | `[16,99,172,156)` |
| 844×390，深色保持在末尾 | `[16,52,836,97)` | `[16,99,172,156)` |

两色均能在语言和名称筛选之前实际点按刷新，按钮边界为 `[180,224,304,268)`。勾选英语 xkcd 后改用名称筛选显示 MangaDex，名单末尾显示 1–50 / 61。原处提交空词，两色均回到可见的校验提示。再次滚至末尾后，浅色点按提交，深色旋至 844×390 后按 Enter。实际 xkcd 英语组均显示 `one piece`、1/1 源完成和 0 项。回到 360×800 后，范围行可点开，再次筛出 xkcd 时保留原勾选。

中间构建的长列表缩短后，范围行画在顶部，语义边界一度报告 y=2592。最终每次接受新搜索时重建结果滚动视口，范围行两色均回到 `[16,164,344,208)` 并经实际点按验证。另测从已有结果重开范围、筛出长名单、滚至末尾再滚回顶部时，语言行语义上缘曾从 274 偏到 2702。该重复滚动与焦点变体继续验收。另一个浅色新文档经英语语言选项提交 `one piece` 到两源，活动期间「停止全部」在 360×480 内边界为 `[180,99,286,156)`。xkcd 已返回 0 项，MangaDex 响应超时。当前构建的非空作品组像素继续待验。[搜索界面](../../apps/reader/lib/features/search/cross_source_search_page.dart)

Flutter Web release 与验收实际服务的入口和运行时 Host 逐字节相同，客户端入口 SHA-256 为 `080f02d83fc3fbcc446283ad34a791df787e17ebacf502e31df860b3ef8c7a6a`。两色测试账户的设置、书架、分类三路读回逐字节一致。47 条审计均有回执，每个账户只有初始化的种子 POST，浏览器操作零账户写入。两项新增浅深组件回归在旧版先因提交不可点而失败，最终通过。组件使用 360×480、2 倍文字，核对滚到第 25 项后的提交、校验、键盘提交和重开范围。996 项 Flutter 测试、改动文件严格 Dart 分析、完整格式和依赖分层均通过。两套验收服务已关闭。正式 Web 实拍采用默认字号，原生系统字体及输入继续待验。[组件回归](../../apps/reader/test/search/cross_source_search_page_test.dart) · [官方验收入口](../../apps/api/test/README.md)

## 语言选择页返回时的跨源搜索回执

2026-11-21，沿用 15.03 的按源结果层级检查 Karuyomi「搜索范围 → 语言」的返回。两色 Flutter 组件都使用 360×800、九种语言，并从同一个跨源搜索页面为两个 Source 提交「测试作品」。在 Cupertino 语言选择页显示期间，让一源返回一项及下一页，另一源返回失败。基线 `f02c741` 选择 **zh** 并返回后，显示「0 / 2 源完成 · 0 项」，两条已交付回执均未进入分组。[参考结果布局](#15-跨源搜索参考像素基准)

`e39b5ef` 按原搜索会话和请求接受这两条回执。同样的返回流程中，语言行重新取得键盘焦点，两个原选源均保留。收起范围后显示「2 / 2 源完成 · 1 项」，作品及下一页和失败原因及重试分别挂在原分组。整个查询只向每个源发送一次。另通过原有生命周期回归核对取消、新查询、离页打开详情及身份失效的结果处理。69 项定向测试及三个改动文件的严格 Dart 分析通过。[语言返回回归](../../apps/reader/test/search/cross_source_search_page_test.dart) · [搜索会话实现](../../apps/reader/lib/features/search/cross_source_search_controller.dart)

另在浅深两色 Flutter 组件中使用 66 项源，提交后重新展开范围并输入名称筛选。基线和修复版分别做两次向下到底、再向上回顶的滚轮模拟。两版每次回顶时「语言」动作的视觉与 Flutter 语义边界均为 `[16,258,344,306)`，筛选仍保留，首次 Web 观察到的 DOM 偏移在该环境没有复现。现有桌面内置浏览器面板请求排队，两次连接均超时；隔离 Wrangler 服务的账户、书架、分类前后读回一致，审计只含初始化和直接读取，服务已关闭。语言返回与重复滚动的正式 Web 复验仍待完成。

全量 998 项 Flutter 测试、全库格式和依赖分层检查通过。Flutter Web release 和正式 Vite 打包通过，生产配置与验收配置的客户端入口和运行时 Host 逐字节一致。入口 SHA-256 为 `1e432cfafc9f4913531f809034850d8b06cca980048cd84d0e4e4bf5836525a1`。

## 跨源搜索的语言返回与筛选保留

2026-11-21，复看固定 Mihon 0.21.3 的 15.01、15.02、15.03 双主题参考。两端都用 `one piece` 复核导航下的输入和按源显示的结果。Karuyomi 的「搜索范围 → 语言」使用可搜索的 Cupertino 选择页，Mihon 的已置顶、全部和有结果筛选留作各自路径的参考。[Mihon 量测](#15-跨源搜索参考像素基准)

用锁定 Flutter 3.50.0 构建 `d9f3e5b`。Codex 内置浏览器在 360×800 的深色结果中重开搜索范围，用坐标点击后键入 `MangaDex`。列表末尾显示「1–50 / 61」。源名输入仍有焦点时，滚到底再回顶后筛选变空，已勾选的英文 xkcd 又出现在列表首行。先按 Tab 把焦点交给复选框，同样滚动后筛选继续生效。两次回顶的语言行坐标均为 `[16,227,344,275)`，历史记录的语义偏移未在此复现。[历史复现条件](#跨源搜索短屏与重新选源)

`b3b2db7` 在外层滚动开始或收起搜索范围时结束源名编辑。实际 360×800 的两色用同样坐标键入后，连续两次都能看到原「1–50 / 61」页脚，回顶语言行均为 `[16,227,344,275)`。用坐标 `(160,251)` 打开语言，选英文并清除名字筛选后，两处原复选框都已勾选。深色另复验在源名框有焦点时收起再打开搜索范围，重新聚焦后读回 `MangaDex`。浅色在 360×480 滚到首组末尾及结果区，再沿外侧回顶，重新聚焦同样读回 `MangaDex`，语言行可按原坐标打开。

使用两套独立 Wrangler/D1 和已安装的英文 MangaDex、xkcd 1.6.1。`search-choices` 夹具暂扣两条实际宿主响应，xkcd 首次交付受控 `SOURCE_ERROR`，MangaDex 原样交付 20 项。两主题均在显示 0/2 时打开语言页，两个交付日志时刻均晚于打开，接收期间仍显示语言页。选「全部语言」返回后，实际焦点落到该行，直接按 Enter 能再次打开。收起范围后显示「2 / 2 源完成 · 20 项」，MangaDex 显示作品及独立下一页，xkcd 显示原因和重试。两色明确读取 MangaDex 第 2 页各新增 14 项，随后原源重试让 xkcd 返回空结果，MangaDex 的 34 项继续可见。每轮的设置、书架、分类和两个源偏好五路读回逐字节一致。视口已恢复，测试标签和服务已关闭。[可复验入口](../../apps/api/test/README.md)

新回归在旧版先因滚动后编辑焦点持续而失败，修正后核对纵向滚动和收起保留筛选。53 项定向测试、1018 项 Flutter 全量测试、改动文件严格 Dart 分析、验收桥 TypeScript 检查、依赖规则与全仓格式均通过。Web JS/Wasm release 构建通过。正式浏览器使用 JS 和默认系统字号，正常产品和验收 Vite 产物的客户端入口及原宿主分别逐字相同，SHA-256 为 `d9d65a69a61b31750f42b1dad98ecb7ed1c8b7e57d148ca2b5377e6e859559a9` 与 `b44b4d4b9b3023aab37071633e8551efb1a0d61f303938aa4a0353871188c177`。正式系统双倍字号和原生现场继续验收。[回归用例](../../apps/reader/test/search/cross_source_search_page_test.dart)

## 跨源搜索首排作品量测

2026-11-21，对照 Mihon 0.21.3 的 15.03 双主题原图与 UI 树，使用相同的 `one piece`、MangaDex 标签和前四个作品名运行 Karuyomi 跨源搜索组件。Karuyomi 使用 Flutter 3.50.0、Arial Unicode 测试字体、Cupertino 图标和本地 Source 夹具，输出 2× PNG。下表为各自 360×800 视口的逻辑坐标，两色结果相同。Mihon 的画面含 Android 系统区域，Karuyomi 的作品封面使用产品原有占位。[Mihon 参考像素](#15-跨源搜索参考像素基准)

| 第一组锚点 | Mihon 15.03 | Karuyomi `30a8543` | Karuyomi `da3ca05` |
| ---------- | ----------- | ------------------ | ------------------ |
| 源标题左上 | (16, 185)   | (16, 301)          | (16, 188)          |
| 语言行左上 | (16, 209)   | (16, 326)          | (16, 213)          |
| 首封面左上 | (12, 241)   | (12, 355)          | (12, 242)          |
| 首标题左上 | (16, 377)   | (12, 491)          | (16, 378)          |

首三张封面仍为 88×132，x 起点为 12、112、212。查询和「搜索」并排，全局停止移到导航栏末端，已提交词及完成数采用次级文字。浅深两色从等待切换到已返回时，查询框和源标题位置保持稳定。浅色页面和占位表面为 `#F2F2F7`、`#FFFFFF`，深色为 `#000000`、`#1C1C1E`。360×480、两倍字号时，输入和提交仍同排，作用域和摘要随文字换行。正常、两倍及非线性缩放的定向回归核对了固定入口、完整提交语义、来源状态及封面和标题对齐。[跨源结果实现](../../apps/reader/lib/features/search/cross_source_search_page.dart) · [排版回归](../../apps/reader/test/search/cross_source_search_page_test.dart)

双源夹具中两组结果均返回。第一组显示明确分页，第二组源标题的上缘为 y=511，Mihon 对应上缘为 y=433。源间间距、真实来源与浏览器中的排版继续验收。本次内置浏览器连接超时。48 项定向回归和全量 998 项 Flutter 测试通过，改动文件严格分析、全库格式与依赖分层检查通过。正式 Web release 和 Vite 打包通过，生产与验收配置的客户端入口和运行时 Host 逐字节一致。入口 SHA-256 为 `7aca0993b6544dde0285e8bc1a7a64d830bf097970b3a0c8d19d4f9de20ad6bc`。

## 源内浏览紧凑网格与短屏搜索

2026-11-21，对照 Mihon 0.21.3 的 12.02 双主题原图与界面树。`s1202-xkcd-popular-{light,dark}` 为 720×1600、320dpi，首封面实测边界为 `[24,386,348,872)`，除以 2 得 `[12,193,174,436)`。参考图的导航标题节点中心为 y=100。基线 `3bc99bf` 的两个 360×800 Flutter 组件用例显示搜索框常驻，首封面距离导航栏中心 204 逻辑像素。`72cf9ac` 收起默认搜索框，按可用宽度排列 2:3 封面，空反馈不占空间。[源内浏览实现](../../apps/reader/lib/features/browse/source_browse_page.dart)

在恢复控制的 Codex 内置浏览器中，使用 `f30a345` 的本地 Flutter Web release、官方 Wrangler `editor-ui` 隔离 harness、真实 D1 与安装确认后的英文 xkcd 1.6.1。两色的首封面为 `[12,116,174,359)`，导航栏中心为 y=22，归一后的上缘 94，Mihon 为 93。使用当前产品的普通 Source 封面占位，图像内容、导航标题横向位置及同版其余状态继续按各自门槛验收。

第一次实拍发现单模式的深色「热门」采用了浅色字色。两色回归比较实际标签样式，深色修正前得到 `#000000`，主题预期为 `#FFFFFF`。`f30a345` 在当前主题下解析选中字色，等待时沿用 Cupertino 的禁用字色。最终深色 Web 实拍中「热门」可读，浅色外观和封面边界保持原位置。[选中字色与网格回归](../../apps/reader/test/browse/source_browse_page_test.dart)

最终浅色在 360×480 点标题栏打开搜索，输入草稿后关闭，再打开时为空，随后用 Enter 提交 `987654321`。深色在 844×390 点「提交搜索」，稳定显示同一空态，再切到 360×480。两色都在收起搜索后仍显示 `当前查询：987654321`，明确清除才回到 xkcd 热门。各轮前后的 bootstrap、设置、书架与分类读回一致，仅每次签发的会话有效期变化。24 条夹具审计均到达终态，两次 POST 分别是安装 xkcd 和保存深色主题，均已确认。测试标签已关闭、视口恢复、harness 退出 0。

两色组件补充 360×480、双倍字号、220 逻辑像素模拟键盘区域。输入、提交及关闭可达，关闭后键盘焦点返回标题栏。受控失败后改写输入，重试仍发送原关键词。两色的首三张占位分别核对列数、横向起点和下一排间距。全量 1013 项 Flutter 测试、四个改动文件严格 Dart 分析、全库格式与依赖检查通过。发布与验收 Vite 构建中的客户端入口和 Host 逐字节相同，入口 SHA-256 为 `fb674a3c2d84e6183b0336f0fe41a59fa81ff0db63397432069213d1c3f49690`。正式 Web 的最新、追加与故障变体、真实系统软键盘、原生及生产继续验收。

## 源内浏览的最新等待与分页重试

2026-11-21，复看 Mihon 0.21.3 的 12.01、12.03、12.08 与 12.09 浅深原图及 Android 界面树。切到「最近更新」后立即高亮新分段，旋转指示的边界归一为 `[160,458.5,200,498.5)`，居于工具栏下的内容区。追加等待保留原封面，底部指示边界为 `[160,712,200,752)`。追加失败仍保留已有作品，原因和重试并列停在底部。参考为 360×800 逻辑视口，包含 Android 系统区；动态目录的作品与封面素材随时间变化。[逐状态清单](mihon-state-coverage.md)

在 Codex 内置浏览器打开 `35d7a71` 的 GitHub CI Web 归档 `14697080926`。下载校验为 16,341,773 字节，SHA-256 为 `8b77c2edf926d444d1b29e06760cfc211b9f57ba61cf9163bd8eb66ef1631473`。使用官方 Wrangler `runtime-control` 与真实英文 MangaDex 1.6.1。深色切到「最新」后，画面仍高亮「热门」，加载正文上缘为 y=132。360×480 热门页触发第 2 页后，原末排左卡由 `[12,136,174,379)` 下移至 `[12,144,174,387)`；受控失败后的重试纵向范围为 `[496,553)`，需要再滚动才能激活。[基线分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44876702963)

`efd402a` 将首次和切换列表的等待置于内容区中央。两色 360×800 的等待区域均为 `[105.6,421.5,254.4,482.5)`，中心 y=452。「最新」在等待时选中且报告禁用，使用当前主题的选中文字色。实际返回的两色最新列表包含 `Kohva`、`Non-Human` 和 `Blue Orchestra`，使用常规 Source 封面占位。产品与验收 Vite 产物的 JS 入口和原宿主逐字节相同，SHA-256 分别为 `dbed49bdf6286a29517fa716f1e6ce48ebe4c54c0a1865ce5af4c4d3569755b5` 和 `b44b4d4b9b3023aab37071633e8551efb1a0d61f303938aa4a0353871188c177`。

两色各在独立 D1 将模式切回热门，再以 360×480 滚到第 1 页末尾。复用 `runtime-control` 的 `migration` 场景，并以英文 MangaDex 的 Source ID 作为只读列表目标。原宿主照常取得实际响应，夹具首次只拒绝交付热门第 2 页。等待、失败和成功追加后的同一末排始终为 `[12,149,174,392)`、`[186,149,348,392)`。等待时两张卡报告禁用。失败原因和重试出现在内容区底边，重试边界约为 `[286.8,417,344,461)`。深色使用 Enter，浅色用点按。每色同一代次的热门请求依次为第 1、1、2、2 页，每次读取 20 项；明确重试有新 requestId，仍读取第 2 页并新增 20 项。各自的设置、书架、分类和四个源偏好共七路权威响应逐字节相同。内置浏览器视口已恢复，两套 Wrangler 正常退出。[验收入口](../../apps/api/test/README.md)

新增四项 Flutter 用例先复现旧版模式和禁用语义，再覆盖最新失败后的原列表、原请求重试和 360×480 双倍字号分页。一次并行 Web 编译时已有封面测试 `pumpAndSettle` 超时，编译结束后复跑全部 1017 项通过。两个改动文件严格 Dart 分析、依赖规则、全仓格式和 Web JS/Wasm 构建通过。浏览器实测使用 JS 产物与默认系统字号。最新失败的正式 Web、热门以外的分页、系统双倍字号和原生仍待验。[组件回归](../../apps/reader/test/browse/source_browse_page_test.dart)

## 阅读页码工具区在大字号下的布局

2026-11-21，对照 Mihon 0.21.3 的 22.03 两色原图和 Android 界面树。从右到左时，左侧下一章与右侧上一章的图标中心归一为 x=32 和 x=328。Flutter 3.50.0 经测试 Source、账户与详情页进入实际阅读器，以 Arial Unicode 和 Cupertino 图标实拍工具区。两主题同为三页夹具的第 2 页，先确认从右到左模式，再按实拍视口量测滑杆控件，两色读数一致。

| 视口与系统字号 | 量测项             | Karuyomi `53656a9` | Karuyomi `12eeb56` |
| -------------- | ------------------ | ------------------ | ------------------ |
| 360×800、1×    | 滑杆控件宽度       | 114.7              | 208                |
| 360×480、2×    | 滑杆控件宽度       | 114.7              | 175                |
| 360×480、2×    | 页码所在工具行高度 | 146                | 46                 |
| 360×480、2×    | 「2 / 3」行数      | 2                  | 1                  |

新版章间按钮中心为 x=30 与 x=330，标准与双倍字号一致。按钮分别保留 44 逻辑像素触控宽度和随阅读方向镜像的图标。禁用按钮仍有完整辅助名称，长按可读到缺少相邻章的文字，浮层可见时允许指针继续命中下方工具。章间等待、失败与返回继续走原 Source 路径。

2048 页的组件回归核对系统双倍字号、页码另行放置、页码由个位变化到四位后的相同滑杆边界，以及从 360 调到 720 逻辑像素宽度后的滑杆焦点和 End 到末页请求。原有拖动预览、指针取消、点击轨道、RTL 方向键和辅助增减页测试通过。全量 1007 项 Flutter 测试、改动文件严格分析（含更新入口的原生集成测试源码）、全库格式和依赖分层检查通过。Web release 与常规、验收两套 Vite 打包通过，两套配置的客户端入口和运行时 Host 分别逐字节一致，客户端入口 SHA-256 为 `e504991ab62796c73df49fa648ac062396c6eb836dd89af64c22c114219f1960`。同版正式 Web 与原生触屏待验。[阅读器组件回归](../../apps/reader/test/reader/reader_screen_test.dart) · [章间入口回归](../../apps/reader/test/reader/chapter_reader_route_test.dart)

## 正式 Web 的页码滑杆与章间按钮复验

2026-11-21，从 `62646c7` 用锁定 Flutter 3.50.0 构建 Web release。产品与验收两套 Vite 产物的客户端入口和 Host 字节相同，入口 SHA-256 为 `fb674a3c2d84e6183b0336f0fe41a59fa81ff0db63397432069213d1c3f49690`。在 Codex 内置浏览器使用两套独立 Wrangler `editor-ui` 与 D1，依照真实 API 分别确认浅、深色，安装官方英文 xkcd 1.6.1 并收藏作品。分支 check/Wasm 与 PR check 均通过。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44871062541) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44871065933)

22.03 两端使用相同的 3324 章、第 1 页和从右到左模式。下表将 Mihon 720×1600 画面减半至 360×800，保留 Android 系统区。图片纵向范围沿用六个横坐标采样法，按钮中心取 Android 节点与浏览器辅助控件矩形。Karuyomi 两色的点击尺寸为 44×44，深色对照图含实际键盘焦点边框。

| 360×800 对照锚点 | Mihon v0.21.3                  | Karuyomi `62646c7` |
| ---------------- | ------------------------------ | ------------------ |
| 漫画图片纵向范围 | 浅 `[132,673)`，深 `[133,673)` | 两色 `[128,673)`   |
| 下一章中心       | `(32,696)`                     | `(30,715)`         |
| 上一章中心       | `(328,696)`                    | `(330,715)`        |

360×480 中，两色滑杆辅助边界宽 207、高 40，章间按钮仍在 x=30、330。暂停方向设置的真实回执时，「从左到右」仍为当前值，下一章留在 x=330。深色可继续翻到已解码的第 2 页。放行后下一章才移至 x=30，浅色留在第 1 页，深色留在第 2 页。两次对应的 `setManga` 都只有一次已确认请求。实际章节操作从浅色左端先后打开 3323、3322，深色右端先打开 3325，再到 3327。3327 的右端按钮以「没有上一章」报告禁用，悬停可读说明，点按保持原章。

22.06 两色使用与 Mihon 同一 3322 章《Dragonfly》。浅色拖动滑杆到真实第 2 页，用 Tab 与 RTL 向右键回首图。深色点按轨道左端到第 2 页，用 Tab 与 Home 回首图。两色用 End 到第 2 页并得到服务端确认，关闭原文档后从新标签书架继续读到同一章第 2 页。各轮新文档前后的六路 API 响应逐字一致，当前进度的 `pageIndexHint` 都为 1。浅色 54 条、深色 75 条夹具审计均到达终态，含每色两条预置命令、一次方向确认及分别 13、29 次正常进度确认。各次视口、翻页和章节检查范围内的进度保存均计入审计。

深色 3324 的浏览器焦点在 360×480 调至 844×390、以及保持 844 宽度从 480 缩至 390 时重复回到页面根节点。滑杆的辅助节点 ID 保持相同。仅变宽时滑杆焦点保留。同一次缩高的对照中，顶部阅读选项和同排章间按钮都保留焦点，浅色 3322 的滑杆也保留焦点。首轮标准 HTML 范围输入与同工具链单独构建的 `CupertinoSlider` 未复现失焦。深色缩高后可 Tab 回滑杆，Home 和 End 实际从第 2 页到第 1 页、再到第 2 页。Flutter Web 的原生范围输入使用内部增减值，真实页码由 `aria-valuetext` 提供。这里量测的是 Web 默认系统字号，双倍字号源于前节组件回归。两套 Wrangler 正常退出，内置浏览器视口已恢复，临时标签已关闭。[后续指针对照与修复](#缩高时页码滑杆的键盘焦点)

## 缩高时页码滑杆的键盘焦点

2026-11-21，在 Codex 内置浏览器复现 `f117973` 深色英语 xkcd 3324。以从右到左模式在 360×480 拖动轨道，把指针留在 y=395，并在缩屏前用 Tab 聚焦实际范围输入。缩至 844×390 后，原输入短暂禁用，焦点落到页面正文，Flutter 随后收到失焦，输入重新启用时没有恢复。仅把指针留在标题栏 y=24，同样的焦点、章节和视口转换保留焦点。锁定 Flutter 3.50.0 的独立 `CupertinoSlider` 在指针留于 y=395 的条件下同样观察到 `mouseleave`、输入禁用和失焦。Flutter Web 切入指针模式时会暂时禁用该无障碍范围输入。[Flutter 3.50.0 的范围输入实现](https://github.com/flutter/flutter/blob/3.50.0/engine/src/flutter/lib/web_ui/lib/src/engine/semantics/incrementable.dart)

`e95e712` 只在缩高时跟踪已聚焦并短暂禁用的页码范围输入。原输入重新启用、仍连接且可用、焦点仍留在正文时恢复。若用户主动交互、焦点转移或窗口失焦则取消。Web 的蓝色焦点环跟随滑杆实际焦点。产品和验收 Vite 构建的 JS 客户端入口与 Host 逐字节相同，SHA-256 分别为 `07ccfa187c7303066534c47d454365a6bb71dcf1774c085f8cd61057079dbeda` 和 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。

在两套独立 Wrangler `editor-ui` 与 D1，用实际英文 xkcd 1.6.1 的 3324 章复验。两色以原位置缩屏均抓到同一范围输入短暂禁用，随后自动恢复焦点。恢复后的第 2 页先截图，再直接用 Home 到第 1 页、End 到第 2 页。两张截图均可看到外圈蓝色焦点环。再次在禁用期间主动操作，深色按 Tab 转到「上一章」，浅色点开「阅读选项」并聚焦「刷新进度」。原滑杆重新启用后，新控件仍为实际焦点。每色 30 条审计均返回 200，包括两条测试预置写入和九条阅读进度保存。独立 API 读回两色从 revision 2 到 11，当前第 1 页、最远第 2 页。内置浏览器视口已恢复，两套 Wrangler 正常退出。

1013 项 Flutter 测试、改动文件严格 Dart 分析、依赖规则、全仓格式以及 Web release JS/Wasm 构建通过。浏览器验收使用正式 JS 客户端和默认系统字号。Wasm 浏览器交互、Web 系统双倍字号和原生现场仍待验。

## 阅读快捷设置的确认布局与短屏反馈

2026-11-21，对照 Mihon 0.21.3 的两色 23.01 和 24.01。23.01 的模式选择在底部弹层显示「阅读模式」与「应用」，参考界面树将两处文字归一到 y=520 和 y=726。Karuyomi 使用底部工具区的 Cupertino 选择菜单，应用边界由服务端确认决定。用测试 Source 和测试账户经实际详情页进入阅读器，分别在 360×480 竖屏和 844×390 横屏、双倍字号下重现。

在 360×480 双主题组件中，暂扣「从右到左」回执后，`f1f1dab` 的「下一章」从右侧提前移到中心 x=51，菜单也已切到从右到左。`6b424c5` 等待时菜单和翻页仍从左到右，「下一章」中心 x=309。横屏等待时用实际控件翻到第 2 页，回到短竖屏后释放回执，第 2 页保持，「下一章」的中心才移到 x=51。已确认漫画 revision 仅推进一次。

原工具布局在 Arial Unicode 和两倍字号下将双页未知回执的说明与重试裁出视口。新版状态固定于工具区上缘，原操作重试优先，其余恢复操作可在反馈区内滚动查看。两色在 360×480 的重试按钮范围均为 `[8,250,283.1,328)`，可直接点按。故障通过截断测试服务已处理的设置回执触发，客户端保持「自动」。精确重试与原请求正文逐字节一致，确认后菜单显示「双页」，同一操作仅推进一次漫画 revision。

另在 Flutter 3.50.0 组件中，经临时受管文件通道交付三张测试 PNG 并核对实际解码。两色等待方向确认、确认方向和双页未确认时均在第 2 页，画布只有一张图。精确重试成功后，第 2、3 页按从右到左并排，第 2 页仍是当前页。完整 1006 项 Flutter 测试、改动文件严格分析、全库格式与依赖分层检查通过。Web release 和常规、验收两套 Vite 打包通过，两套配置的客户端入口及运行时 Host 逐字节一致，客户端入口 SHA-256 为 `c6797b694d5e0049ff7999d2534629ade0fd84761afb7c06cd6598022c692ab5`。新版正式 Web 的真实 Source 操作和原生现场待验。[阅读设置回归](../../apps/reader/test/settings/settings_navigation_test.dart)

## 章节多选的固定操作栏

2026-11-21，对照 Mihon 0.21.3 的 18.01 双主题原图与 Android 界面树。Flutter 3.50.0 使用测试 Source、账户服务、Arial Unicode 和 Cupertino 图标，从图源条目进入实际作品详情。在 360×800 标准字号选取与参考相同的第 3324 章，滚动对齐该行上缘后量测。两色读取一致。

| 选中行锚点   | Mihon 18.01 | Karuyomi `a11591a` | Karuyomi `6df9704` |
| ------------ | ----------- | ------------------ | ------------------ |
| 横向布局边界 | [0, 360)    | [16, 344)          | [0, 360)           |
| 未读标题左缘 | 30          | 60                 | 30                 |
| 选中行高度   | 68          | 68                 | 68                 |

选中态使用 Cupertino `tertiarySystemFill` 和右侧勾选，整行提供单一可激活的选中语义。从截图行内 x=4 取样，浅色选中行与相邻行分别为 `#E3E3E9` 和 `#F2F2F7`，深色为 `#1C1C1F` 和 `#000000`。上栏保留退出、已选和隐藏数量、全选与取消当前显示项。现有的范围选择及清空入口随章节选项滚动。

360×480 两倍字号下，滚到末章时，旧版的退出、计数和两个标记动作都滑出视口。新版退出按钮边界为 `[8,28,52,72)`，已读和未读按钮分别为 `[8,414,180,476)`、`[180,414,352,476)`，始末滚动位置的按钮边界相同。简短按钮文案把同一底栏的两倍字号按钮高度从 108 降为 62 逻辑像素。两色实际点按末章和标为已读会打开同一条目的确认清单。取消后保持滚动位置和已选章。点按退出或系统返回会结束选择，末章仍在详情内可见。确认前、取消和退出期间，测试账户零写入，也没有章节页请求。

最终版本全量 1006 项 Flutter 测试、改动文件严格 Dart 分析与全库格式、依赖分层检查通过。Web release 与常规及验收 Vite 打包通过，两套配置的客户端入口和运行时 Host 逐字节一致，客户端入口 SHA-256 为 `f0681528f4c63138f7bcca458226253ad76c3e12b47e86815a8007503675d161`。两主题正式 Web 画面、系统字号和原生触屏继续验收。[章节多选回归](../../apps/reader/test/browse/chapter_read_navigation_test.dart)

## 章节发布日期和刷新回执

2026-11-21，沿用 17.01 的四个 xkcd 章节名和第三项已读状态。固定测试时钟为 2026-11-14、时区为 Asia/Shanghai，由测试 Source 注入各章节时间戳，经图源条目打开实际详情组件。Flutter 3.50.0 在 360×800 使用 Arial Unicode 与 Cupertino 图标，按第一条章节标题对齐两色截图。Mihon 原界面树的四个日期依次为「1 天前」「3 天前」「5 天前」和「2026/11/6」。

`fdddc75` 的章节次级资料只显示章号及读态，`7e4fc47` 的两色组件在首位呈现同样四个日期。日期左缘均为 x=16，与对应标题上缘相隔 26 逻辑像素，相邻章节标题相隔 68。次级资料同时保留章号、读态、可用的扫描组及重复条目身份。360 逻辑像素宽度下，两倍字号的长资料可换行，Tab 与 Enter 仍能分别激活打开和书签。

本地日历的边界用例覆盖不到 24 小时的跨午夜、今天、过去第六和第七天、未来第七和第八天，以及 Unix 纪元前、缺失、零值和超出可呈现范围的时间戳。日期用例在 Asia/Shanghai 与 America/New_York 均通过。受控刷新失败后重试，原列表保留至资料与章节都读完，成功后显示新增章节的「2012/11/2」。测试账户的提交数未增加。52 项定向回归和全量 1004 项 Flutter 测试、改动文件严格分析、全库格式与依赖检查通过。Web release 与常规及验收 Vite 打包通过，客户端入口与运行时 Host 分别逐字节一致，客户端入口 SHA-256 为 `be17eb098ee453ef287aa744f42f08fab08a2aea12614536d4eec87908378f8c`。内置浏览器连接超时，真实 Source 的新版正式 Web 画面继续待验。[日期边界](../../apps/reader/test/browse/chapter_list_navigation_test.dart) · [刷新回归](../../apps/reader/test/browse/details_recovery_test.dart)

## 章节列表的对齐与独立书签

2026-11-21，以 Mihon 0.21.3 的 17.01 双主题原图和 Android 界面树作为锚点。以相同的 xkcd 3324、3323、3322、3321 章节名和第三项已读状态，经 Karuyomi 的图源条目进入作品详情。Flutter 3.50.0 组件使用测试 Source 和账户服务、Arial Unicode 及 Cupertino 图标，视口 360×800，首行滚动到同一位置后抓取浅深截图。Mihon 720×1600 的界面树坐标折算为逻辑像素。下表记录布局边界，两种主题读数一致。

| 锚点                     | Mihon 17.01 | Karuyomi `0f231b5` | Karuyomi `11c1ed1` |
| ------------------------ | ----------- | ------------------ | ------------------ |
| 未读标题左缘             | 30          | 80                 | 30                 |
| 已读标题左缘             | 16          | 80                 | 16                 |
| 次级资料左缘             | 16          | 80                 | 16                 |
| 相邻标题上缘间距         | 68          | 48                 | 68                 |
| 标题到次级资料的上缘间距 | 26          | 26                 | 26                 |

组件里未读圆点随账户确认出现，第三项已读标题采用次级文字色并退出圆点缩进。行高由内容与留白决定。浅深及 1×、2× 字号回归覆盖重复章节资料换行、Tab 切换到书签、Enter 激活和回到打开章节的独立焦点。图片只截取章节区域。两端的字体、资料内容及尾部动作各自按平台和当前功能呈现。

暂扣详情书签读取时，`0f231b5` 点按灰色书签实际向测试 Source 发出了一次章节页请求。`11c1ed1` 同一动作保持详情且请求数为零。释放读取后，点击已启用的书签仅在测试账户写入该重复条目的书签。全量 1003 项 Flutter 测试、改动文件严格 Dart 分析和全库格式、依赖检查通过。Web release 与常规和验收 Vite 打包通过，两个配置的客户端入口及运行时 Host 逐字节一致，客户端入口 SHA-256 为 `d206ba85bd4bcf2a6fe67a5233e2a5294136ae2042a29de1fbfab0de90761571`。内置浏览器连接超时，本版双主题正式 Web 画面与点击继续待验。[章节布局及导航回归](../../apps/reader/test/browse/chapter_list_navigation_test.dart)

## 作品详情的章节筛选与短屏六章确认

2026-11-21，对照 Mihon 0.21.3 的 17.01 和 18.01 双主题原图。Mihon 章节行及选中背景为全宽，正常字形下相邻章间距为 68 逻辑像素。使用 Flutter 3.50.0 的本地 Web release 和真实英文 xkcd 1.6.1，两色在 360×800 的正常未读行上缘为 y=547、613、679、745，步距 66。实际 3327、3326、3325 显示「1 天前」「3 天前」「5 天前」，与 Mihon 原图重合的 3324 至 3321 在本轮日期分别为 11 月 13 日、11 日、9 日和 6 日。两次拍摄使用各自的系统日期。360×480 的浅色选中行在 x=3、356 的同高像素均为 `#E5E4E9`，相邻未选行抽样为 `#F3F2F7`。[固定参考](#章节列表的对齐与独立书签)

`63f216f` 的深色详情中，键入 `332` 得到 11/3326 项。保持编辑焦点滚到末尾后回顶，输入清空，显示恢复为 3326/3326。`e013fb2` 在用户滚动详情时结束编辑，程序滚动定位保留焦点。两主题用相同动作回顶后继续显示原查询和 11 项。浏览器回顶后有一次输入框的 DOM 语义矩形位于 y=960，画面在 y=471，章节选项也偏移 489。按画面坐标可展开选项。一次按角色定位并点击范围终点时找不到节点。从范围起点用 Tab 聚焦终点后，可用 Enter 打开并完成选择。坐标差异待查。

两色选择从 Source 索引 3 的 3325 到索引 8 的 3320，包含两端共六章。360×480 从筛选末行「332: Gyroscopes」打开确认，固定退出、已读、未读按钮的边界分别为 `[8,4,52,48)`、`[8,432,180,476)`、`[180,432,352,476)`。确认清单可滚到第六项，取消和开始保持可达。滚动稳定后，两色取消前后的末行边界都是 `[0,346,360,412)`，原六项勾选保留。各自预览和取消后的七路权威响应与基线逐字节相等。

两色均明确开始标记。深色暂扣首项的已提交回执时，短屏显示「已确认 0 / 6 章 · 未开始 5 章」，独立 D1 读回只有第 3325 章已读。放行后两主题各确认 6/6。深色 37 条、浅色 42 条审计均到终态。各包含一次主题和扩展预置，以及按 3325 至 3320 顺序执行的六条 `setChapterRead`，Worker 与客户端状态均为 200。两套独立 D1 的账户 revision 都由 1 变为 7，精确对应六个章节键。读取位置、最远位置、继续阅读及书签均为空。浅色新文档经真实详情路由读回同一组六章。两套 Wrangler 正常退出。[受控回执入口](../../apps/api/test/README.md)

组件回归在旧版因滚动后编辑焦点持续而失败，修正后验证程序定位及滚轮事件各自的焦点处理。40 项定向、1019 项完整 Flutter 测试、改动文件严格分析、全仓格式及 Web JS/Wasm 构建通过。产品和验收 Vite 产物的客户端入口和运行时宿主分别逐字节相同，SHA-256 为 `3f474edb525b8e886ee1819c75e811d64572db0dd15ce00312dbe532897bfa92` 和 `b44b4d4b9b3023aab37071633e8551efb1a0d61f303938aa4a0353871188c177`。浏览器实测采用 JS 和默认系统字号。系统双倍字号及原生触控待验。[列表回归](../../apps/reader/test/browse/chapter_list_navigation_test.dart)

## 作品详情的章节筛选语义与滚动偏移

2026-11-21，使用 Flutter 3.50.0 本地 Web release、内置浏览器默认字号和 360×800 视口。`1ec1129` 的英文 xkcd 1.6.1 完整清单有 3326 章，滚两页再回顶部，章节选项的 DOM 上缘都为 y=415。筛选 `332` 后显示 11 项，此时滚动 DOM 高度仍为 220035。从 x=170、y=690 下滚三页，待末行稳定后从同一点上滚三页。第一次快速滚到底时内层滚动语义节点重建，外层保留原节点。高度变为 1245，756 高的滚动容器多带 489 的纵向变换。回顶后 `scrollTop` 为 0，变换仍在，章节选项落在 y=904。先用 Tab 移开搜索焦点也能复现。独立的标准 Cupertino `CustomScrollView` 固定 14 项对照页在同一视口回顶前后按钮均为 y=396，点击生效。

组件修订为 `CustomScrollView` 提供可见章节数。资料和操作区保留各项语义，章节索引只计章节行。回归用 50→34 项验证计数、当前滚动上限、用户滚动与程序定位的焦点行为，以及返回后筛选框的「筛选章节」名称和原值。旧代码先因滚动计数为空而失败。正式 Web 浅深两色打开同一英文源，输入 `332` 后按 Tab 进入 3327 首章，两色在失焦时仍提供筛选名称和 `332`，清空搜索仍为独立按钮。[Flutter 滚动语义说明](https://api.flutter.dev/flutter/widgets/CustomScrollView-class.html#accessibility) · [组件回归](../../apps/reader/test/browse/chapter_list_navigation_test.dart)

修订版两色从 11 项末行「332: Gyroscopes」回顶后仍显示 11/3326。此时章节选项 DOM 上缘仍为 y=904，筛选框为 y=960，画面在各自的 y=415 和 y=471。两色重建的输入框仍有名称，DOM 值为空，画面和实际筛选保留 `332`。浅色按角色点章节选项找不到命中节点，按画面位置点则正常展开。仅补计数及约束程序滚动目标的隔离对照均复现 489 偏移。上游案例记录了滚动语义保留旧补偿的相近路径，升级后的引擎仍须用本流程复验。真实读屏、系统字号与原生待验。[Flutter 上游案例](https://github.com/flutter/flutter/issues/195469) · [上游修订](https://github.com/flutter/flutter/pull/195578)

基线 22 条终态审计只有一次主题与扩展预置。修订版 28 条终态审计只有两次显式主题预置，均由正式设置接口确认，详情交互零写入。改动文件严格 Dart 分析及 Web JS/Wasm 构建通过。与编译并行时两项封面用例等待超时，独立复跑全部 1019 项 Flutter 测试通过。正式 Vite 与独立验收的客户端入口逐字节相等，SHA-256 为 `53334ebb1a93146efa35b69d1ea486c9a57504e6866a788cc080d5441e332043`。两版复用同一个 Source 宿主，实测浏览器运行 JS 产物。

## 跨源搜索源间距与分页回执

2026-11-21，沿用 15.03 的双源、`one piece` 和四个相同作品名，在 Flutter 3.50.0、Arial Unicode 测试字体和 Cupertino 图标下各用浅色、深色组件实拍。第一组夹具提供下一页，第二组返回当前页。下表为 360×800 视口的逻辑纵坐标，两色一致。Karuyomi 使用占位封面，Mihon 原图含 Android 系统区域。[Mihon 参考像素](#15-跨源搜索参考像素基准)

| 锚点             | Mihon 15.03 | Karuyomi `437897b` | Karuyomi `0d7b34d` |
| ---------------- | ----------- | ------------------ | ------------------ |
| 第一组标题上缘   | 185         | 188                | 189                |
| 第一组首封面上缘 | 241         | 242                | 242                |
| 第二组标题上缘   | 433         | 511                | 439                |
| 第二组首封面上缘 | 489         | 565                | 492                |

第一组卡片从 198 缩至 180 逻辑像素。短标题组按两行排版预留高度，较长标题组在实际需要时用三行，继续保留完整标题语义。分页移入源标题末端，继续使用 44 逻辑像素的触控高度。第一组的分页、等待和重试复用同一位置，普通字号的实际动作边界为 `[283.7,188,344,232)`。两倍字号短屏中，使用较短的可见状态并保留完整无障碍文案，等待及失败前后的动作边界均为 `[238.7,331.5,344,375.5)`，首排占位封面上缘保持 y=405。[分源实现](../../apps/reader/lib/features/search/cross_source_search_page.dart)

两色、两种字号的回归从源标题请求第 2 页，等待中继续保留单源停止。失败原因在已有作品之后，标题处原位可重试。重试继续发出同一个源、已提交的 `one piece` 和第 2 页，收到结果后保留原作品并追加。失败原因在常规字号和 360×480 两倍字号下的上缘分别为 y=454 和 y=689，短屏仅重试动作处于首屏。52 项定向回归和全量 1002 项 Flutter 测试通过，改动文件严格分析、全库格式与依赖分层检查通过。Web release 和 Vite 打包通过，正常发布和验收配置的客户端入口与运行时 Host 逐字节相等，入口 SHA-256 为 `0005da3dfe404adca4d04515ade7de97cc954009a30067e1a4d3164af1cc4bb1`。内置浏览器连接超时，真实来源及正式 Web 的分页复验继续待验。[分页回归](../../apps/reader/test/search/cross_source_search_page_test.dart)

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

独立快照为31组七路global/manga settings、library、categories、state、progress、bookmarks，以及21组三路categories/library/settings。本轮使用生成的 Protobuf 模型严格解析并比较，TypeScript 严格检查通过。

- 最终accountRevision30、globalRevision7、xkcd业务mangaRevision11；独立漫画阅读设置revision仍0，不与业务作品revision混用。
- 版本算术为2次初始fixture应用、2次独立复位、26次已确认UI账户应用；UI应用包括创建/删除分类、两次各两作品的批量、4扩展安装、xkcd收藏、4封面、6章节标记及3次主题。该结果不是HTTP请求尝试次数，本轮无请求审计。
- 名称草稿/校验/危险预览取消、单作品选择取消及无分类指引、批量移出取消、封面选图/清除草稿、Source会话与筛选区间均零附写；删分类保留收藏、章节标记和续读状态。临时复位工具最初缺catalog revision的409没有写入，不算产品UI冲突验收。

新增06.K1、14.K4、14.K9三对主图，跨版本已登记主图89→92/169（54.4%）；其余旧节点重拍不增加分子。结合上一节本漫画设置，9处编辑面中8处已有正常主流程的正式产物分项；多选子面、24.K11、共享30.K各业务范围、故障、键盘/大字/减少动态、全部转换及真实生产仍待，不外推8组全状态通过。`bd2d33b`两条文档CI（43805049596、43805042557）也已成功；本轮未修改产品源码，PR继续草稿、未部署。临时标签已关闭、视口恢复，harness正常退出0。

## 短编辑内容的导航起点修复

2026-11-16，复核上一节正式封面JPG时确认导航与首个表单之间有大段空白。共享`EditSheet`使用`Center`，短`SingleChildScrollView`按内容高度垂直居中，读取、已确认值和选图草稿切换也改变正文起点。四项实际封面组件流程（浅/深×1x/2x）新增位置断言后均先失败：导航底为108px，正文顶为366px（1x）或318.5px（2x），分别空出258px和210.5px。原图保留为历史，不能据其称最终布局已通过。

共享编辑面改用顶部水平居中排列，继续保留原640px最大阅读宽度和安全区；空分类指引与作品说明统一16px水平边距。未修改提交、取消、CAS、原请求或资源生命周期。`flutter test --no-pub --concurrency=1 test/widgets/edit_sheet_test.dart test/covers/cover_navigation_test.dart`全部14项通过，原四项流程在读取、无封面和选图草稿阶段的正文顶均与导航底相接；其余用例继续核对键盘遮挡下顶部动作、确认/丢确认、精确重试、拒绝、身份更替及迟到选图。三个改动Dart文件严格分析通过；日志为`edit-sheet-top-content-{before,after,analysis}.log`。

修复提交`0e605c5743b0c30bf2c5f91c09c300760af32b2a`已通过[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43814852391)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43815059269)，包含完整检查及Web/Wasm；分支未部署。CI Web artifact `14202372551`为16,297,491字节，下载边界核对GitHub SHA-256 `42f9e78846290b6f2790c4d842d21339ad5aa8f720bb8b5fdaa0ee33db2be09d`及35条公开Flutter资源清单，再通过正式Vite入口组装既有四源快照与runtime。未在本机重编Flutter或AOT。

官方Wrangler harness的`categories`夹具、临时D1、`acceptance-owner`与内置浏览器360×800完成双主题复验：无分类指引左右边距正确；无封面、已确认封面和清除草稿始终从导航下方开始排列，未再出现随内容高度变化的大段顶部留白。浅色执行选图草稿→保存确认→清除草稿→关闭取消，深色读回该封面→清除草稿→保存确认。正常主图/JPG与AX前缀为`karuyomi-0e605c5-editors-`，均已实看；浅色另有选图处理中图，深色选图、首次/替换图片草稿与手动系统取消未补验，不新增成对状态计数。

本轮使用生成的 Protobuf 模型解析 16 组六路 API 快照，TypeScript 严格检查通过。两次初始fixture写入及两次独立API安装/收藏预置后accountRevision为4；三次已确认UI应用仅为浅色封面保存、主题保存和深色清除，最终accountRevision7、globalRevision2、作品revision3。分类查看/取消、选图/清除草稿、取消清除及关闭浏览器均无额外写入，其他作品、分类、章节进度及书签保持不变。此夹具没有请求审计，不能据版本算术外推POST尝试次数；API预置不计UI安装验收。

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

现有editor-ui只新增migration范围，控制命令见[工具说明](../TOOLING.md)。正式`migrateFrom`仍执行真实D1事务，等待与丢确认发生在成功提交之后；明确拒绝在提交前返回类型正确的400，不伪造成功。17项官方Workers/D1/R2回归通过，含挂起释放与取消、迁移原作品保留、目标仅应用一次、相同正文重试及新旧请求真实409。分页和Source调用保持实际链路。`3a57cdf`的完整push/PR CI及Web/Wasm随后通过，正式Web分项见下节；受控登录响应不代替真实Access。

## 迁移加载与故障的正式 Web 复验

2026-11-16，产品提交`3a57cdff317e4c664c07609341e6dc2613aa91c9`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43853233381)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43853248940)通过，含正式Web和push Wasm。CLI下载官方artifact `14220350937`，传输边界一次核对归档SHA256及39条Flutter资源；复用此产物经正式Vite组装，未在本机编译Flutter或AOT。官方Wrangler `editor-ui` harness使用临时D1/R2、`acceptance-owner`及四源静态快照，内置浏览器以360×800核对已确认浅/深主题。Source打开、热门、详情与3,323章读取保持真实链路；故障只控制正式作品快照及迁移确认交付。

新增九对主图，将Karuyomi跨版本主图覆盖从98推进至107/169（63.3%）。这只表示主图成对取得，不代表PR整体、当前HEAD全部状态或全部转换验收通过。

| 状态       | 实际核对范围                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 20.K1/K2   | 首次输入读取的实际旋转指示、原作品、写入禁用；首次503后可只读重读，未误报无目标源。两主题恢复成功。                                                      |
| 20.K4      | 实际读取原Source章节时的进度、原作品与操作禁用，随后均取得3,323章；未以完成画面替代加载图。                                                              |
| 20.K7      | API准备分别清空已安装扩展后，UI只读刷新确认无目标源，保留扩展管理指引。浅色原章节尚未读取，深色保留已捕获章节；准备和恢复属于独立API写入。               |
| 20.K14/K15 | 精确中文目标、详情/权威预览的实际加载、提交禁用；首次503与再次只读重取失败均实拍，恢复成功后才出现复制范围及确认入口。失败目标和重读动作的下段另图保留。 |
| 21.K2      | 固定原目标与复制范围、等待指示、禁用重复操作。深色及时释放并正常确认；浅色在释放前已超时转未知，不计正常释放。                                           |
| 21.K3      | 浅色超时、深色实际提交后交付502均保留原请求；两次明确精确重试的UUID和正文分别完全一致，均零重复应用。深色另验同会话重开与只读读取失败，期间没有新POST。  |
| 21.K4      | 两主题各一次明确400及一次真实旧source revision的409，均无覆盖。保留原目标、范围、拒绝原因与明确重读，不再建议重试被拒绝请求。                            |

19.K10同时用该正式产物复验双主题封面拒绝说明，当前页脚明确要求重新读取；一张通过正式multipart API准备的图片供两主题复用，两次UI清除都在dispatch前收到400，权威封面保留。这是拒绝说明与清除流程的证据，不计UI选图或上传能力通过；深色明确重读恢复已确认封面，浅色最后重读发生在夹具审计满额之后，不能记恢复成功。

`verify-3a57cdf-migration-evidence.ts`以生成Protobuf模型解析33组九路快照（297条有效响应），核对20个零附写区间及256条有界请求审计。9次UI迁移尝试包括3条成功原命令、2次精确重试、2次400与2次真实409；3条原命令各推进一次目标revision，新增已读/书签均0，原作品及其它数据保留。11次API准备与2次UI主题保存单独计数，最终accountRevision16、globalRevision7、原作品revision6、目标revision3。封面2次拒绝同样零写入。校验脚本严格TypeScript检查通过，原始快照、准备回执、审计及证据摘要留在忽略目录。

浅色初次挂起sequence49的Worker/client状态未完成，唯独此条排除正常释放；其精确重试sequence53成功且前后快照没有重复应用。深色挂起sequence149正常200/200；sequence165实际200提交后交付502，sequence176重试成功且版本不再增长。审计在最后有效快照之后达到256条上限，后续浅色封面重读失败单独保存为`excluded-audit-limit-read-light.jpg`，不作为产品缺陷或恢复证据。首次未知重开与提交转场帧另存且排除；20.K8/K10截图已经完成打开/列表，未截到旋转指示，仍保持待验。

实际发现待确认/已拒绝期间的新GET失败会被原迁移提示遮蔽：操作标题已经是读取输入，错误仍只说迁移未确认或被拒绝。两类原请求均正确保留，但本次读取失败没有明确呈现。随后在正式组件supplier先复现，再显式区分提交与读取的失败反馈；读取失败说明原操作保持不变，提交拒绝、CAS和精确重试规则保留。低优先级单并发运行`flutter test --no-pub --concurrency=1 test/migration/migration_controller_test.dart test/data/source_migration_repository_test.dart`，34项通过，包括浅/深×1x/2x的实际错误呈现、原请求保留、零附写与精确重试。两文件严格Dart分析、依赖分层、完整格式化及校验通过。该新修复的完整CI和正式产物双主题复验仍待，不用旧图宣称修复已在Web通过。确认后反馈仍需手动上滚才能完整取图，自动保持可见尚未验证。

原始JPG和完整AX共同前缀为`karuyomi-3a57cdf-migration-`；五张`3a57cdf-migration-{input,preview,confirmation,recovery,preview-retry}-pairs.jpg`联系表已逐图实看，必要时核对360×800原图。浅/深分别检查官方表单表面、次级文字、蓝色操作、禁用和系统错误色；JPEG不作为精确颜色采样。临时标签已关闭、视口恢复，harness正常退出0。Mihon参考缺口、20.K8/K10/K13/K18、21.K6、全部其它变体与真实生产继续待验，PR仍为草稿且分支未部署。

## 迁移读取提示及失效状态的正式 Web 复验

2026-11-16，`e8646f55608b3d9a80bf4f2caca3df6a471ce150`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43863811341)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43864088500)成功，含正式Web与push Wasm。官方artifact `14225590650`在传输边界校验归档和39条Flutter资源后复用，正式Vite组装68个公开文件和4个扩展；没有本机Flutter/AOT编译。官方Wrangler `editor-ui`临时D1/R2、`acceptance-owner`、360×800及四源快照保持与上一轮相同的验收边界，受控401不是实际Access登录。

两种已确认主题分别完成真实xkcd英文→中文、仅收藏/分类的原迁移提交后丢确认、只读重取失败、查看原请求、明确精确重试，以及独立新请求明确400拒绝后再只读失败。新读取反馈清楚显示“本次读取未完成，请重新读取。原迁移操作保持不变。”，原目标、范围和UUID保留；未知请求仍可精确重试，明确拒绝没有精确重试入口。两次精确重试均复用原正文，目标各只推进一次revision；诊断和只读失败不附写。浅色明确结束拒绝后重读也不写。

`verify-e8646f5-migration-evidence.ts`使用生成Protobuf模型核对33组九路快照（297条响应）、16个完全相等区间和202条有界请求审计，全部审计已有完成状态。6次迁移尝试为2条已应用原命令、2次精确重试和2次dispatch前400拒绝；4次503只读失败与6次受控401分别核对。2次独立API准备、2次UI主题确认单列。最终accountRevision7、globalRevision3、原作品revision2、目标revision2，原作品与目标均保留。审计只覆盖设置、封面及迁移指定路径；收藏和阅读进度的POST不在其范围，不据此推算全部请求数。

本轮实际触发21.K6的预览/已拒绝后身份失效、19.K11的首次读取失效和24.K11的确认后重读失效。旧操作、字段或确认被隐藏，关闭/返回仍可用；恢复夹具后旧迁移向导仍停用，九路快照均零附写。但逐图复核发现三张以`light`结尾的失效截图实际均为系统深色，不能作为浅色图。只登记有效深色图，主图成对覆盖仍为**107/169（63.3%）**，没有新增三个双主题节点。设置重读显示禁用灰色、实际点击无变化，但工具`isEnabled()`返回true，此差异不作为禁用语义已通过的证据。其它异步阶段及迟到结果仍待。

真实xkcd 3,323章目录和`3323: Meteor Fear`第1/2页已实际显示。首次阅读被同会话中仍保留的拒绝迁移正确阻止保存，客户端却只显示通用“尚未获服务器确认”，没有说明须先处理迁移。通过UI返回原迁移并明确结束被拒绝请求，九路快照不变；再明确“重试保存所有进度”后，账户5→6、原作品1→2，新增唯一章节进度与续读锚。随后保存浅色并从书架继续同章，显示服务端已保存，最终快照没有额外进度增长。该恢复验证保留门控；通用错误提示缺口仍须产品修复和新产物验收，不能通过自动结束迁移解决。服务连接页同时缺少连接中与身份已确认的阶段提示，已列入下一项修改。

原始JPG、完整AX、快照、审计与证据摘要共同前缀为`karuyomi-e8646f5-migration-`。`e8646f5-read-results-review.jpg`、`e8646f5-rejected-original-review.jpg`和`e8646f5-expired-review.jpg`已逐图实看；最后一张明确暴露浅色证据不成立。打开Source与列表的候选图没有截到真实旋转指示，20.K8/K10仍待。临时标签已关闭、视口已恢复，harness退出0。PR继续草稿、未合并、未部署；生产Access、全部变体及剩余62个主状态继续待验。

## 服务连接与进度阻塞的状态反馈

2026-11-16，前一节真实Web发现的两个缺口已写入产品修复。服务连接采用官方Cupertino分组呈现实际服务、明确状态和已确认账号；读取地址、重建运行容器和bootstrap连接阶段分别显示进度，连接中及身份失效/拒绝不再显示旧账号为已确认。普通Source工作不会仅因`busy`被判为正在连接。切服务期间地址只读，登录与重复连接禁用，原有身份核对和待确认命令保留。

阅读进度保存与重新阅读分别捕获真实`BusinessPendingMutationException`，显示阻塞原因和“处理原操作后再显式重试；草稿仅保留在当前会话”。不移除迁移写入门、不自动结束请求、不丢弃进度草稿。真实业务客户端supplier回归分别构造未知/明确拒绝迁移，证明进度和重新阅读都不附写；原迁移明确精确重试或结束后，阅读仍须显式重试才能保存。

先复现原通用错误和缺少连接状态，再修复。单并发执行`reading_progress_controller_test.dart`、`reading_progress_refresh_test.dart`、`reading_progress_navigation_test.dart`和`settings_navigation_test.dart`共58项通过；包括浅/深×1x/2x的窄屏连接流程、重建及bootstrap等待、401/403/503、保留旧email但隐藏旧确认、未配置地址、同服务原请求精确重试与跨服务/身份隔离。测试挂起门明确释放；早先两次未正常推进的测试运行已中止，不计通过。此为正式组件/控制器回归；完整CI、正式Web双主题与生产另验，不填27.K1–K5主图格，也不提高107/169的成对覆盖率。

## 连接状态的正式 Web 复验

2026-11-16，客户端`19c2260e6d38408b5438f94d850ed6c2eb8908b7`的push `43874740432`、PR `43874940251`完整CI通过，含正式Web和同提交Wasm候选。Web artifact `14230367928`已在下载边界核对GitHub归档长度与SHA-256，再按Flutter官方清单核验39条资源；复用该产物，经正式API Vite装配四源快照和官方harness，在Codex内置浏览器360×800验收，本机没有重编Flutter或AOT。

为稳定截取连接等待，在测试专用editor-ui增加`connection`范围，仅拦截无query的`GET /api/bootstrap`；stdin控制挂起/释放及503/401/403，沿用30秒有界等待、取消和256条审计。生产与普通无fixture入口不启用。测试先出现3项失败，再实现并通过20项官方Workers/D1/R2回归；API/test严格类型、依赖分层和完整格式检查通过。验收用的是19c2260客户端加未提交的测试夹具增量，精确补丁保留为`19c2260-connection-fixture.patch`，不把夹具称为该客户端提交的一部分。

正式浅色与深色均核对27.K5的服务、身份已确认、账号和连接/登录入口。连接等待时实际显示旋转指示并隐藏旧账号；受控403和401分别显示拒绝原因与登录失效提示，普通503显示“连接未完成”，显式连接恢复后重新确认原身份。27.K2/K3/K4在设置不可用时回到真实系统深色，只登记有效深色图；没有伪造浅色主题，也不以503失败替代27.K1未配置地址。登录按钮的实际认证流程、带进度草稿及其它变体本轮未执行。

`verify-19c2260-connection-evidence.ts`用生成Protobuf模型核对7组六路快照（42条响应）、5个完全相等区间及29条完成审计。6次bootstrap分别为正常、挂起释放200、受控403/401/503和显式恢复200；全部是GET。连接、故障、恢复与主题草稿均零业务写入。2次独立API准备（安装/浅色与收藏）单列；1次明确UI深色保存使账户revision2→3、global1→2，漫画revision仍1，书架/分类/书签/进度保持不变。editor审计不包含收藏准备POST，不从审计推算全部写入。

原图及完整AX前缀为`karuyomi-19c2260-connection-`，已逐图实看`ready-{light,dark}`、`pending-system`、`denied-dark`、`expired-dark`及`failed-dark`。27.K5新增1对主图，跨版本双主题覆盖107→108/169（63.9%），剩余61个主状态；其它三状态为partial，不增加成对分子。测试标签已关闭、视口恢复，harness正常退出0。受控Access故障不代替生产Access；阅读进度阻塞新提示、全部变体与最终生产闭环仍待。PR #8继续草稿、未合并、未部署。

## 阅读进度阻塞的正式 Web 复验与重开修复

2026-11-16，复用已验证的`19c2260`正式CI Web，配合`35559fb`的官方editor-ui harness、临时D1及四源静态快照，在Codex内置浏览器360×800验证真实xkcd英文版`3323: Meteor Fear`两页图片。独立API仅准备安装/浅色设置与原作品收藏，两次准备写入单列；深色由一次明确UI主题保存启用。本机未重编Flutter或AOT，未执行原生和生产Access验收。

浅色、深色均实际提交仅收藏/分类的英文→中文迁移；真实D1提交后测试夹具交付502，原操作保持未知。翻页产生的阅读草稿显示“源或目标漫画有未确认迁移”及“处理原操作后再显式重试；草稿仅保留在当前会话”。点击进度重试和重新阅读仍受阻，原页位、进度epoch与服务端值保持。两次原迁移重试的请求正文分别与原命令完全一致，目标各只推进一次revision，不重复迁移。

浅色返回详情后，明确重试原迁移，未保存阅读草稿仍保留；再次明确“重试保存进度”才使账户revision3→4、原作品1→2，随后续读恢复第2页。深色则发现真实失败转换：原迁移确认后，从书架“继续阅读（未保存）”重开阅读器，未点击进度重试便自动保存。快照核对账户6→8、原作品2→4，当前位置改为第1页、最远仍第2页。此处不能记为“显式恢复通过”，也不能用浅色从详情保存的另一条路径替代。

`verify-19c2260-progress-evidence.ts`用生成Protobuf模型核对19组九路快照（171条响应）与13个完全相等区间，确认阻塞期间、两次原迁移精确重试、浅色另行保存及深色意外写入的实际revision。121条editor审计均完成，只包含其范围内的作品/设置读取与迁移/设置POST，不包含进度及收藏POST，不能从这份审计推断全部写入次数。进度写入增量来自独立快照。原图与完整AX前缀为`karuyomi-19c2260-progress-`；`unknown-blocked-{light,dark}`和`unknown-reset-blocked-{light,dark}`已实看，深色缺口保留为`reopened-auto-saved-dark.jpg`。加载候选图不登记为成对主图，跨版本计数仍108/169（63.9%）。测试标签已关闭、视口恢复，harness正常退出0。

针对重开缺口，未知/拒绝×进度/重置四项正式supplier回归先在重开清空错误处失败。修复在当前会话保留受阻草稿的显式重试门控；原操作解除不授权自动提交，重开、前台刷新、返回flush和新viewport均不能绕过，新的可见位置仍可收集到内存草稿。明确重试成功后正常翻页恢复自动保存，身份、CAS和epoch边界继续保留。进度控制器、路由、刷新与书架续读45项回归通过；四项另补正常自动保存恢复检查后通过。新正式Web与完整CI仍待，不用组件结果覆盖旧Web失败记录。

同一正式Web还暴露书架同名身份缺失：迁移后英文和中文xkcd都只显示标题，更多/续读辅助名称也无法区分。书架补语言在前的源名说明，并将语言/源名纳入更多、分类和续读语义；源内浏览已有源上下文，不额外复制说明。四项浅/深×1x/2x、360×800的同名长标题/源名回归先在缺少说明处失败；修复后书架、续读和分类38项通过，核对完整合并语义、说明位于卡片内及打开菜单零业务POST/Source执行。新正式画面仍待。

## Source 偏好子编辑器的分组与失效

2026-11-17，续办时确认`3a3976d`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43888254204)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43888545574)成功，包含正式Web与push Wasm；上一节同名身份和受阻草稿修复的完整CI门已通过，正式Web闭环仍待。已有Web归档、传输摘要与39条Flutter资源核验记录保留。本轮内置浏览器的`getState`和创建IAB标签两次均在30秒超时，未取得新页面状态；未执行新的正式浏览器、生产或原生验收。

对照已核对的Mihon `s1403-source-multiple-{light,dark}`与正式Source偏好组件，新增20项360×800、浅/深×1x/2x回归。旧实现分别在多选没有官方分组，以及文本/多选身份变化后没有停用反馈处失败。修复后16项子面流程分别触发身份切换与403：隐藏旧输入、勾选项及应用入口，明确关闭，零Source编辑回调和业务POST。多选采用官方分组、13px/secondaryLabel页脚及完整选项行，文本恢复官方输入框装饰。

四项长选项流程随后复现另一缺口：点击选项文字没有切换勾选，实际提交只含原英文值。改为官方CupertinoListTile整行切换、勾选框共用同一草稿，长名称解除单行省略后通过。测试核对实际RenderParagraph没有截断、取消及重开保留原值、明确应用仅执行一次并移除不可用旧值；应用后两个退出转场时刻没有误报身份变化。正常秘密/会话字段不上传、丢确认精确重试及依赖禁用等既有回归同时通过。

`source_preferences_widget_test.dart`29项、`source_preferences_controller_test.dart`10项及`edit_sheet_test.dart`4项共43项单并发通过，两份改动Dart文件`dart analyze --fatal-infos`无问题。Flutter首次沙箱运行未能创建回环端口，不计产品失败；获准使用本机端口后才执行上述红绿回归。这是组件/控制器证据，未填正式Web主图或声称MangaDex运行通过，覆盖保持108/169。

审计夹具已提交为`88433e1`：补齐editor-ui进度与收藏等有界JSON命令的审计，仅原样转发这些命令，不注入编辑器故障；multipart仍沿真实通道且不记录图片。24项官方Workers/D1/R2回归、API/test严格类型及依赖分层通过，包括四种故障模式下进度重复请求的真实200、同一回执与原正文审计。全范围`pnpm format`、`pnpm format:check`及该提交的标准prek hook通过；新提交CI及正式Web另行记录。旧`19c2260`审计不含进度POST的范围限制保持不变。

## 选择行与搜索反馈的 Cupertino 收敛

2026-11-17，`39a55f7`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43986171905)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43986182834)完成，正式Web与push Wasm成功；这补齐上一节Source子编辑器的完整工程门，正式Web仍待。内置浏览器本轮`getState`又在30秒超时，备用的内置面板打开入口只返回`queued`，没有已打开页面或截图。故障发生于控制接口，不能记为Karuyomi页面失败，也不能从排队返回推断浏览器已恢复。

跨源选源还保留早期自绘圆角容器、手动输入框边框、正文级说明及仅勾选框可点击的选项。新增八项360×800、浅/深×1x/2x组件流程，旧实现分别在缺少官方表单分组和校验文字没有系统错误色处失败；初轮测试存在布局尚未稳定的点击，修正等待步骤后再复跑，八项均在上述产品断言失败，不把未命中点击计作产品缺陷。

选源现分成官方控制分组与选项分组，语言和名称查询分别采用完整选择行及官方表单输入行，上限说明与分页计数采用官方13px次级页脚。完整源名/扩展说明解除默认单行省略，整行点击和勾选框共用原选择，Tab定位勾选框后Space切换。回归核对真实RenderParagraph未截断、查询隐藏已选项后清空仍保留选择、选项语义不混入组标题或页脚、准备和筛选不启动Source任务。查询校验及清理失败采用系统错误色，清理反馈改用官方表单分组，失败后恢复入口可达，第二次明确返回才在清理确认后退出。

`cross_source_search_page_test.dart`23项，连同控制器和正式Catalog搜索服务共49项单并发回归通过；两份改动文件`dart analyze --fatal-infos`无问题。原有32源/查询/结果限额、两个独立槽、按包串行、迟到结果、单源分页/重试、停止/清理失败恢复及身份退役回归保持通过。正式业务与服务层未改。

核对同类选择行时，单作品及批量分类的现有业务回归改用实际文字点击，两项均先在权威分类关联不等于预期处失败：旧行只响应勾选框，名称点击没有修改草稿。两处改为官方CupertinoListTile完整行，整行与勾选框分别调用同一份选择动作；动作再次检查当前身份/窗口和原清单是否已冻结，长名称保留完整内容。分类和批量29项回归通过，仍先预览零写入、明确保存/开始才提交，未选关联、原命令重试、冲突和身份变化的边界保持通过。测试定位同时支持正式完整行，相关五个Dart文件严格分析无问题；日志为`category-selection-row-{red,green,analyze}.log`。

本轮合计78项不同定向回归、七文件严格分析通过；不把两项修改输入方式的既有用例当作新增测试，也不重复计算跨源页面23项。

本轮没有新的正式Web或生产图，15.K1等历史主图保留其原输入；不得把上述组件流程当作新版本主图、全部变体或真实Source验收。成对主图覆盖保持108/169，最终Web和生产继续待验。`83e32fd`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/43990204683)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43990217385)随后均成功，包含正式Web与push Wasm；分支未部署。

## 结果区字号角色与复制参考补图

2026-11-17，复核最终源码的Cupertino文字角色：跨源结果的源名取消16px硬编码，直接继承官方正文主题（默认17px）并保留半粗；状态由14px改为13px次级说明。复用既有`cross_source_search_page_test.dart`的23项页面回归，窄屏、浅/深、线性/非线性文字缩放、源名和状态自然增高、重试入口及清理路径均通过；单文件`dart analyze --fatal-infos`无问题，没有为这一低影响字号调整新增重复测试。这是源码与组件证据，新提交完整CI和正式Web另行验收。

同日复用既有官方Android SDK/AVD及Mihon 0.21.3（versionCode39），单实例AVD配置2核/2048MB、720×1600像素、320dpi，补齐[参考状态表](mihon-state-coverage.md)的28.04应用浅/深主图`s2804-worker-copy-readable-{light,dark}.png`。后续核对`20261117-emulator.log`发现启动器将RAM上调至2560MB，配置值不是实际内存证据，Guest内存和宿主RSS仍未测量。两张已逐图实看，系统复制预览实际显示可读任务ID/Tags开头；底层WorkManager诊断XML正文一致，只能确认可见片段，没有验证完整剪贴板内容。系统夜间模式始终为`no`，应用浅/深不等于系统复制容器浅/深。PNG在复制后先采，XML稍后采，不把它们称为同一瞬时；较早帧和旧的空浅色预览保留，空容器不计通过。

在线语言组关闭后仍显示Local source，不满足真正空列表；切换标签后的旧/过渡帧也不记作加载。已恢复原语言组和Source勾选、显式深色、DEFAULT及非纯黑，未变更网络、权限、扩展安装、日志或阅读设置。已向本次参考模拟器发送正常退出并确认ADB设备列表为空。原始图片与XML留在忽略目录，不提交测试实例任务ID等临时输出。

本轮内置浏览器控制仍未取得页面，已询问用户手动打开标签的实际结果；参考模拟器和组件回归均不能替代正式Karuyomi浏览器、原生或生产验证。Karuyomi跨版本主图仍108/169（63.9%），剩余61个主状态及全部变体/转换继续待验，PR #8保持草稿、未合并、未部署。

## 内置浏览器恢复后的 Source 实测与拒绝提示修复

2026-11-17，`0a02ee6ec13872592e1240586206a73793c25199`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44008902136)及[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44008910235)完整成功，包含正式Web和push Wasm，部署跳过。正式Web artifact `14295504068`长16,299,027字节，下载边界核对GitHub SHA-256 `6efe1596596396f8764083dcf6589763712ac5319d2ee784f05471e9dd1f3ea9`，再核验39项Flutter资源。本机仅通过官方Vite组装四包已发布静态快照与acceptance入口，没有Flutter或AOT编译。

内置浏览器控制随后实际恢复：IAB标签列表成功返回、空白标签成功打开，再以360×800打开上述正式客户端。恢复原因未确定，不把它归因于审批服务恢复。官方Wrangler临时D1/R2、`editor-ui`与`acceptance-owner`保持隔离；独立API只准备浅色、xkcd/Komiic/MangaDex三包精确安装及英文xkcd收藏，两次准备写入单列。首轮准备脚本的嵌套模型序列化曾在发出写入前失败，改用生成模型创建后通过，实际审计确认只有这两次准备POST。

浅色选源实际点击xkcd名称后勾选，输入MangaDex过滤后已选数仍1；改查xkcd后，Tab从输入框进入原英文源，Space取消并再次恢复。空查询显示系统错误色且没有分源结果，补15.K3浅色图`karuyomi-0a02ee6-cross-validation-empty-light.jpg`。实际查询`one piece`得到xkcd零项，结果标题/状态采用新的正文/13px角色。`cross-scope-stable-light`、`cross-selection-hidden-light`及`cross-xkcd-result-light`是分项图；首段未展示完整目录尾部的刷新/开始，不据此替换15.K1，未截到实际旋转图也不补加载格。首次选源入场残影保留并排除主图。

真实MangaDex英文源加载热门列表和完整偏好后，打开Default content rating多选子面。名称点击修改草稿，取消后Safe/Suggestive原值保持；明确关闭Suggestive并应用后，同会话重开仅Safe选中，再明确应用恢复原值。已逐图实看`source-multiple-{current,draft,applied}-light.jpg`。`source-multiple-apply-first-light`是退出转场，虽然含真实处理指示，仍有原子面残片，不计14.K4主图；`source-preferences-opening-light`已经是内容，不计14.K1读取态。文本子面`source-text-empty-light`使用官方输入装饰，真实提交`not-a-uuid`后Source拒绝并保留空值。

本次保留真实视觉失败：`source-text-rejected-light`的“漫画源未接受输入；设置未更改。”仍按普通正文显示，不是错误角色。控制器现将“拒绝且实际值未变”交给已有error通道，有真实回调副作用时仍提示核对实际值；每次新操作清除上次message，避免旧成功说明与本次拒绝并列。没有改变Source回调、原值恢复、账户/会话范围或精确重试规则。

新增四项浅/深×1x/2x、360×800组件流程，先在缺少错误色处失败；初轮双倍字号未滚到反馈处，修正滚动步骤后四项均在颜色断言失败，不把用例步骤问题算产品缺陷。修复后验证拒绝保留原会话值、继续编辑并明确修正、旧拒绝清除、零账户POST及无溢出；原控制器拒绝用例另核对旧成功说明清除和明确重读后反馈复位。33项组件、10项控制器和4项共享编辑面共47项单并发通过，三文件严格分析无问题。日志为`source-rejection-role-{red,red-visible,regressions,analyze}.log`。新提交完整CI与修复后正式双主题仍待。

独立核对三组六路快照（18条响应）完全相等；单独的MangaDex偏好响应经生成ProtoJSON模型确认sources为空、精确目录/包身份及accountRevision仍2。23条范围内审计均完成，只有与准备收据完全相同的两次POST，普通UI操作没有账户写入；审计不包括Source运行时调用和偏好API，后者由独立状态与单调账户revision核对，不把它当作完整网络日志。审计文件为`karuyomi-0a02ee6-ui-source-audit-light.json`。已导航离开客户端、恢复视口，harness正常退出0。

本轮仅浅色正式Web，不补深色，也不把Source多选/文本分项当作全部30.K业务范围。15.K3新增单侧，跨版本主图仍108/169（63.9%）、单侧9、双侧均缺52；拒绝颜色修复须新正式Web复验，全部变体、生产及原生门槛保持原记录。PR #8继续草稿、未合并、未部署。

## Source 与选源的正式 Web 双主题复验

2026-11-17，拒绝反馈修复`a12c779195e26a481ee868e7766c43b89155a472`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44014133238)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44014141353)均完成成功，Web及push Wasm通过，deploy跳过。正式Web归档`web-build-a12c779195e26a481ee868e7766c43b89155a472`的artifact ID为14297979259，大小16,299,039字节，传输边界SHA-256为`448c9b7e487530bfb75f71ba5a924500d8ac70d34f329cd6b8ca06a9ccbb74ba`；校验后复用并核验39条Flutter资源。客户端来自CI，本机只经官方Vite装配既有静态资源、Wrangler临时D1/R2和`editor-ui`，没有本地Flutter/AOT编译。内置浏览器360×800、`acceptance-owner`、独立验收地址`127.0.0.1:60414`，不等同生产或原生。

浅/深分别进入真实MangaDex英文热门与Source偏好。文本空值提交`not-a-uuid`后，Source拒绝、当前空值不变，提示采用系统错误角色；顶部原因与底部现值/明确重读各有主图。显式重新读取后回到顶部实看，旧拒绝与旧成功说明均清除。输入测试UUID `00000000-0000-4000-8000-000000000001`并明确应用，确认后同会话重开保留；随后明确清空并应用恢复原值。Default content rating点击Safe名称可改变草稿，取消后Safe/Suggestive仍原值；明确关闭Suggestive、应用与重开后只有Safe，最后应用恢复两项。`source-text-{empty,rejected-top,rejected-bottom,recovered-top,valid-draft,confirmed-top,applied}-{light,dark}`及`source-multiple-{current,draft,applied}-{light,dark}`保留实拍与完整AX；深色拒绝主图采用单独稳定后的`source-text-rejected-stable-top-dark`。旧`0a02ee6`普通正文拒绝图继续作为失败记录，不被新通过覆盖。

两主题选源主图`cross-scope-{light,dark}`均过滤xkcd五个语言源，未选源时查询、语言、0/32、刷新与开始在同屏。真实名称点击选择英文源，改查MangaDex后已选数仍1；返回xkcd后Tab进入勾选框、Space取消再恢复。空查询显示原输入及1–500字符错误，不创建分源任务。真实`one piece`查询xkcd返回零项，源名继承官方正文、状态为13px次级角色。两轮同包五源查询均先收起范围，`cross-five-start-candidate-{light,dark}`实际图像均显示0/5、英文源旋转及其余源等待，停止此源/全部入口可见；文件名的candidate不表示推测。随后取得的AX已推进至浅色1/5、深色2/5，不能当作截图同一瞬时；最终五源均返回零项，另存`cross-five-completed-{light,dark}`。没有用这些完成图替代正在停止、取消未确认或清理失败。

主题草稿分别选择DARK和LIGHT时，当前画面仍保持此前主题，独立API状态不变；各一次明确保存后才分别成为DARK和LIGHT。十组六路快照共60条响应按七个相等区间核对，主题区间之间仅accountRevision 2→3→4、全局revision 1→2→3及LIGHT→DARK→LIGHT变化；收藏、分类、书签、漫画设置和阅读进度等其余内容不变。三条独立MangaDex偏好响应经生成ProtoJSON模型核对精确包/目录身份、sources为空及对应账户revision。87条连续审计均完成且透传200，仅前两次独立准备POST和两次明确UI主题保存POST；原正文与独立收据/快照完全一致，没有其它业务写入。审计不包含Source运行时调用与偏好API，后者由独立状态及单调账户revision核对，不称为完整网络日志。

本轮核对了 38 张 360×800 JPEG 及对应 AX、十组快照和三条偏好响应。校验入口`verify-a12c779-source-scope-evidence.ts`复算上述响应、相等区间、四条写入边界及图像尺寸。截图和AX逐项实看后离开客户端、恢复视口，harness正常退出0。

后续新临时D1的进度复验误用同一准备文件名，覆盖了本轮原始准备收据；新收据已另存`migration-reopen-setup.json`。本轮两条准备命令从保留的完整审计恢复，`ui-setup.json`和复算回执明确标记`recoveredCommandsOnly`/`setupCommandsRecoveredFromAudit`，不重建原始响应，也不把恢复的命令记录当作独立证据。原始审计、60条独立API快照、三条偏好响应和38张截图未变；这些证据仍独立支持实际版本与四条写入边界。准备脚本改为必填运行系列，防止后续再次覆盖。

新增14.K6（Source拒绝输入这一失败分项）、15.K3及15.K4三组主图，跨版本成对主图108→111/169（65.7%），仅单侧8、双侧均缺50，剩余58个主状态。15.K1替换为新完整选源主图，15.K5补新真实加载主图并保留旧独立重试证据，不重复计数。多选/文本是14.03/14.04和共享编辑面的真实业务补充分项，不代表30.K全部范围通过；38张图不等于38个新状态，历史主图覆盖也不是当前HEAD全部验收或PR整体完成。受阻进度从书架重开、同名作品身份、全部剩余状态/变体、真实生产Access和原生门槛仍按原记录。PR #8继续草稿、未合并、未部署。

## 受阻草稿重开与同名书架的正式 Web 复验

2026-11-17，复用上一节已验证归档与39条资源的`a12c779`正式CI Web，在`d5a0bc8`的官方Wrangler `editor-ui`、临时D1/R2和`acceptance-owner`中复验。`d5a0bc8`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44024102037)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44024111846)亦已成功，Web及push Wasm通过、deploy跳过。客户端不在本地重编，验收地址`127.0.0.1:54112`，内置浏览器360×800。两条独立API准备写入仅设置浅色/三包安装和原英文xkcd收藏，原始新收据单独保存在`karuyomi-a12c779-migration-reopen-setup.json`。

真实中文xkcd目标搜索返回零项后，热门读取两次显示“运行容器已中断，请重新连接”；重选目标源后的第二次失败也保留。此时尚未提交迁移，没有据此认定浏览器控制故障或唯一根因。改选同包法文xkcd后，真实热门与迁移预览正常加载，下面流程只覆盖英文→法文；没有把中文失败记为恢复通过。英文阅读实际使用`3323: Meteor Fear`两页图片，第二页仍走Source的文本图片处理链，不以原图URL绕过宿主。

浅色从原作品、深色从书架明确提交仅收藏/分类的迁移；各次真实D1应用后，夹具交付502，客户端保持原操作未知。两主题翻页产生的草稿均显示未确认迁移原因、当前会话范围及明确重试；原迁移未处理时，进度重试仍不写入。随后重开原迁移，明确重试发送原UUID/CAS/正文并取回原确认，没有重复迁移或附带保存进度。

原迁移确认后，两主题均从书架“继续阅读（未保存）”重开。浅色恢复草稿第2页，深色恢复草稿第1页；未保存原因和重试入口仍在，刷新不清除门控，浅色另一次翻到第1页也只更新内存草稿。浅色未知至明确保存前七组九路状态相等；深色对应八组相等，服务端仍保留此前第2页。明确重试后，浅色账户3→4、原作品1→2，深色账户7→8、原作品3→4，当前均保存第1页且最远仍第2页；再普通翻到第2页，各仅自动推进一个版本。旧`19c2260`深色自动保存失败保留，当前结果不掩盖历史失败。

正常保存后，两主题分别reload成独立新文档，重新从API恢复主题、两部同名书架身份及续读入口，实际进入真实章节第2页并显示已保存。该读回以及返回均不增加业务版本。两次明确UI主题保存单列：LIGHT→DARK→LIGHT，仅全局revision 1→2→3；主题草稿不提前应用。新文档浅色测试在深色流程之后，读取的是当时最新已确认进度，不冒充早先浅色会话的独立数据副本。

`verify-a12c779-progress-reopen-evidence.ts`使用生成Protobuf模型核对30组九路快照（270条响应）、20个完全相等区间与172条连续完成审计。12条POST为两次准备、两次真实迁移及各一次精确重试、两次明确进度保存、两次恢复后的自动保存及两次UI主题保存；账户最终revision 10、原作品5、法文目标2。除两次受控丢确认的客户端502外，审计透传均200；进度命令始终pass，不注入迁移故障。四条进度原文与各次独立权威进度相同，epoch为0、最远保持第2页，分类/书签/目标阅读位置不变。新审计已包含有界进度JSON，不追溯补全旧121条审计，也不覆盖Source运行时调用或全部网络请求。

本轮核对了 33 张 360×800 实拍及完整 AX。`reader-reopened-still-unsaved-{light,dark}`、`before-explicit-save-{light,dark}`、`explicitly-saved-{light,dark}`、`auto-save-restored-{light,dark}`与`fresh-document-{library,resume}-{light,dark}`均逐图实看，截图前缀为`karuyomi-a12c779-reopen-`。`target-loading-candidate-dark`已经是结果，不登记20.K10；中文中断图不替代恢复通过。离开客户端并恢复视口后harness正常退出0。

同名书架卡片、更多/分类/续读辅助名称已双主题确认，但分类编辑面内仍只有“xkcd”，缺少源身份；深色从书架重开并确认迁移后，原作品页脚仍要求先读取章节或选择范围。两处失败实拍均保留。分类对象现使用官方Cupertino表单分组，完整标题与语言/源名次级页脚自然换行；迁移页脚按待确认与完成阶段显示固定范围/确认说明。八项既有浅/深×1x/2x流程先在缺少身份或阶段说明处失败，再通过；迁移用例从不携带章节快照的书架入口重开原命令，继续核对精确重试只应用一次。书架、分类与迁移相关51项回归及四文件严格分析通过，日志为`editor-object-context-{red-visible,regressions,analyze}.log`。新说明完整CI及修复后正式Web仍待。

本轮补的是现有阅读与书架转换，成对主图不增加，仍111/169（65.7%），剩余58个主状态及全部变体继续验收。没有据此通过拒绝/重置/Access等所有转换、生产Access、生产图片或原生性能；PR #8继续草稿、未合并、未部署。

## 分类对象与迁移页脚的正式 Web 双主题复验

2026-11-17，对象/阶段说明修复`25be6f5ec38c87e6ec4f6d873df0a364c655614f`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44033443457)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44033451647)完整成功，正式Web及push Wasm通过，deploy跳过。Web artifact 14306686562长16,299,145字节，下载边界SHA-256为`d8b4bbb3244e527bb5705cf0f785ec8da2320a1700202d699230fc3eecc72a6e`；校验归档和39条Flutter资源后复用，没有本地Flutter或AOT编译。

首次本地组装仅重建API产物，遗漏独立acceptance构建，因此旧验收目录仍向浏览器交付`a12c779`的`main.dart.863ad073.js`。这属于本地组装错误；原始截图、13条审计和快照改名保留为`25be6f5-stale-*`/`object-stale-*`，不计新版本通过。修正为依次运行官方`pnpm --filter @karuyomi/api build`与`pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts`，再启动`ACCEPTANCE_FIXTURE=editor-ui BROWSER=none pnpm acceptance:serve`。未运行会触发完整Flutter构建的`acceptance:build`。正式操作前，实际HTTP读取的`precache_manifest.json`经正式schema解析，与CI资源经官方Web过滤后的35条清单逐项相等，主入口为`main.dart.0d1c3cf3.js`；39条中的四条Native资源按既有合同排除。`25be6f5-served-client-check.json`保存完整校验结果，以后也先核对实际交付版本。

纠正后的验收使用官方Vite/Wrangler临时D1/R2、四包既有静态输入、`acceptance-owner`、`editor-ui`和内置浏览器360×800，地址为`127.0.0.1:49761`。四次独立API准备分别为浅色/三包安装、英文收藏、分类“待读”和法文收藏；分类目录准备接口不在editor-ui审计范围，另外三次准备POST在范围内。原始准备收据独立保存为`karuyomi-25be6f5-object-context-setup.json`，不把准备操作算普通UI操作。

浅色英文与深色法文的分类面均在官方“漫画”分组显示完整标题，次级页脚分别显示`en · xkcd`、`fr · xkcd`。实际点击分类名称修改草稿、取消及重开后恢复原值，再明确保存，各仅修改对应作品的分类并推进一次版本，另一部同名作品不变。`category-{current,draft,confirmed}-{light,dark}`已逐图实看；两个主题故意使用不同对象来核对身份，不称为同内容像素叠图。批量两作品浅色执行添加分类、深色执行移除分类；名称点击只改预览，取消零写入，明确开始各发两条命令并显示2/2确认。`batch-category-{current,draft,confirmed}-{light,dark}`是不同操作的业务分项，不替换既有同操作双主题主图。新对象分组的空分类变体仍待新正式Web。

两主题均从不携带章节快照的书架入口，明确选择仅收藏/分类，经真实法文Source热门、详情与权威预览后提交。D1各实际应用一次，夹具随后交付502；待确认页脚显示“原操作的复制范围已固定，原作品保留。”。返回书架并重开仍显示相同固定范围说明；明确精确重试原UUID/CAS/正文后，页脚显示“原作品已保留；迁移结果见下方服务端确认。”，没有重复应用。`migration-{pending-footer,reopened-pending-footer,confirmed-footer}-{light,dark}`均实看；旧正常请求和其余复制范围证据继续保留，不以本轮两次仅分类重试代表所有变体。

`verify-25be6f5-object-evidence.ts`经生成ProtoJSON模型核对21组九路快照（189条响应）、13个完全相等区间及107条连续完成审计。普通UI包括两次单作品分类、四条批量分类命令、两次迁移及两次精确重试、一次明确主题保存，没有其它业务POST。审计内另外三条POST为上述独立准备；第四条目录准备由原始收据及独立快照核对。除两次丢确认的客户端502外均透传200，审计无未完成项；精确重试不增加版本。账户最终revision 13、英文4、法文6、全局2；主题草稿不提前应用，明确保存才LIGHT→DARK。其余书架/元数据/分类目录/书签/进度/续读状态逐组保持，只有每个明确操作对应的版本、分类或主题改变。审计不含分类准备接口及Source运行时请求，不称为完整网络日志。

本轮记录了 25 张新版本的 360×800 JPEG、完整 AX 和对应审计快照。新版本图片统一前缀`karuyomi-25be6f5-object-`，排除含`stale-`的旧版本图。`migration-opening-candidate-light`虽有实际旋转指示但仍处转场，不登记20.K8；`migration-preview-loading-candidate-light`已是内容，不补加载格。`migration-listing-candidate-light`确有热门加载指示，但说明仍泛称“正在查找目标作品”，查询框还保留原文，未完整说明当前热门操作，不登记20.K10通过。观察确认按钮的短等待曾超时，实际预览已成功且按钮在视口下方，滚动后明确确认正常；不据此认定Source或浏览器连接失败。完成后离开客户端、恢复视口，harness正常退出0。

此次还保留两个实际呈现缺口：书架卡片辅助名称已含身份，独立勾选框却无名称；目标热门/搜索及追加提示缺少具体操作和原查询。四项既有浅/深×1x/2x书架流程与两个既有迁移流程共六项先复现，再直接给官方CupertinoCheckbox补完整标题/语言/源名，并按真实请求区分热门、搜索、追加及原查询。未提交的新输入不改变追加请求的说明。相关51项单并发回归和四文件严格分析通过，日志为`selection-listing-context-{red,regressions,analyze}.log`；新完整CI及修复后的正式Web仍待，不以组件结果替代浏览器证据。

本轮是已有分类与迁移状态的补充分项，成对主图仍111/169（65.7%），仅单侧8、双侧均缺50，剩余58个主状态及全部变体继续验收。Mihon参考环境另纠正为AVD配置2048MB、启动日志实际要求提升到2560MB，实际Guest/RSS未独立测量；未在本轮重启或把它当作2GB性能证据。关闭在线语言仍保留Local source，普通UI未取得07.03纯空态，源码说明不替代截图。PR #8继续草稿、未合并、未部署，生产及已停止的Karuyomi原生现场门槛保持原记录。

## 勾选身份与目标列表加载的正式 Web 双主题复验

2026-11-17，`ef5f3dd25c76cb6b41cea36f0d5150e12b0a4bef`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44049345683)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44049354273)完整成功，Web及push Wasm通过、deploy跳过。正式Web artifact 14313142954长16,299,212字节，下载边界SHA-256为`fe1de7e3228fe855f28534b3a07ecfd6fcae4dfdd2e95512e29ae25f4bee02ae`，随后核验39条Flutter资源。本机只依次运行官方API和独立acceptance Vite构建，实际HTTP的35条Web清单与CI逐项相等，主入口`main.dart.56c97092.js`；`ef5f3dd-served-client-check.json`保存完整结果。官方Wrangler临时D1/R2、四包既有材料、`editor-ui`、`acceptance-owner`及内置浏览器360×800，地址`127.0.0.1:64217`；没有本地Flutter/AOT构建或生产部署。

三次独立API准备为浅色/三包安装、英文收藏和法文收藏，分类目录保持revision 0且为空，收据独立保存为`karuyomi-ef5f3dd-selection-listing-setup.json`。浅/深均打开英文和法文同名作品的空分类面，官方对象分组、完整标题、语言/源名次级页脚及空分类指引均实看，随后取消；四张`category-empty-{en,fr}-{light,dark}`补齐新对象分组的空分类变体。浅色明确勾选英文、深色明确勾选法文时，另一项保持未选，独立AX勾选框各含完整标题/语言/源名；Tab/Shift-Tab回到该勾选框后按Space取消，数量从1回到0。`checkbox-{en-selected-light,fr-selected-dark,keyboard-cleared-light,keyboard-cleared-dark}`保留截图和完整AX，验证实际键盘操作，不以卡片按钮名称代替控件身份。

两主题均从英文书架入口明确选择仅分类，打开真实MangaDex英文目标源，执行热门、热门追加、`one piece`搜索与搜索追加。八张`migration-{popular,more-popular,search,more-search}-loading-candidate-{light,dark}`均实际截到旋转指示、准确操作、原作品与目标源；candidate文件名不表示推测。追加前分别把输入改为“尚未提交的新查询”及“尚未提交的搜索词”但不提交，热门追加仍说明热门，搜索追加仍说明原查询`one piece`，已有候选在等待期间保留且禁用。两种追加返回后均实看新的列表尾部，保存`migration-{popular,search}-page-two-{light,dark}`。MangaDex已提供真实分页，无需修改xkcd分组偏好；本轮未变更任何Source偏好。`migration-source-open-candidate-light`已经是搜索待用内容，不登记20.K8；没有用它冒充打开进度。

`verify-ef5f3dd-selection-evidence.ts`使用生成ProtoJSON模型核对九组九路快照（81条响应）、七个完全相等区间及43条连续完成审计。全部审计为pass/200，仅三次独立准备POST与一次明确UI主题保存；普通选择、取消、目标Source浏览、查询和分页没有其它业务POST。五组浅色状态完全相等、账户revision 3；主题草稿仍浅色且零附写，明确保存后账户4、全局2和DARK是唯一变化，四组深色状态相等。两部作品revision始终1，分类目录/元数据/收藏/书签/进度/续读均保持；独立最终MangaDex偏好响应的sources为空、accountRevision为4。审计不包含Source运行时请求或偏好API，不称为完整网络日志。

本轮记录了 23 张 360×800 JPEG、完整 AX、九组快照和偏好响应。上述八张实际加载图补20.K10一对主图及首次/追加、热门/搜索分项，跨版本成对主图111→112/169（66.3%），仅单侧8、双侧均缺49，剩余57个主状态。其余图为已存在节点的转换与空分类变体，不增加分子。静态扫描未发现正式客户端的Material导入或常见Material控件，仍不代替实际配色/导航/转场验收。完成后离开客户端、恢复视口，harness正常退出0；其余状态/变体、生产与已停止的Karuyomi原生门保持原记录，PR #8仍草稿、未合并、未部署。

## 分类目录与批量操作的故障验收入口

2026-11-17，现有官方`editor-ui`夹具增加`categories`及`classification`范围，分别覆盖正式分类目录命令和作品`setCategories`命令。分类目录读取、作品快照及两种范围内首段书架读回可明确挂起/失败；带查询的分页继续走原路径。仅stdin配置模式，既有30秒/每秒检查一次的有界等待、loopback及显式fixture限制和256条审计上限保留，普通验收和生产入口不启用。确认挂起与丢响应先运行正式D1事务；拒绝和身份HTML仍是明确测试故障，不代表真实Access。进度、收藏和其它范围继续原样通过，有界JSON原文与真实状态可核对，multipart图片不入审计正文。

42项既有及新增[官方Workers测试](https://developers.cloudflare.com/workers/testing/vitest-integration/test-apis/)通过，使用项目固定的Cloudflare Vitest插件与真实临时D1/R2。覆盖目录/作品分类/书架读取的等待和取消、实际事务提交后才挂起确认、丢确认时完全相同正文的精确重试零重复、全新旧版本请求的真实409，以及读取失败/400/401时目录和两部作品不被覆盖。初轮两个目录用例遗漏作品响应内同步返回的共享目录，修正预期后全部通过；没有把该测试预期错误记录成产品缺陷。API/test严格类型、全范围格式及依赖分层均通过；新提交完整CI和新范围正式Web仍待。日志为`categories-classification-fixture-{workers,typecheck,format,format-check,dependencies}.log`。

这一步提供05.K8–K11、04.K3–K6/K8的实际验收入口，尚未取得它们的新正式Web主图，不增加112/169计数。后续复用已核验的正式CI客户端时，分别记录客户端与夹具提交、核对实际交付清单，并以独立权威快照和原始审计验收UI转换；等待、未知、明确拒绝、暂停、失效及原命令重试不能相互替代。

## 批量等待与暂停的正式 Web 复验

2026-11-17，客户端复用已校验的`ef5f3dd`正式CI Web，产品客户端、协议、runtime及生产API源码相对该提交均无差异；夹具独立记录为`94b7b82825346e1b999b348be37e0fa461f0e977`。夹具的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44057865761)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44057876487)均完整成功，正式Web及push Wasm通过、deploy跳过。本机通过官方API和acceptance Vite装配，实际HTTP交付35条Web资源与原CI清单相等，入口仍`main.dart.56c97092.js`；回执`94b7b82-category-faults-served-client-check.json`同时标明两个提交。官方Wrangler临时D1/R2、`acceptance-owner`、四包既有输入、`editor-ui`及内置浏览器360×800，地址`127.0.0.1:55143`，没有本地Flutter/AOT编译或生产部署。

五次独立API准备为浅色/三包安装、英文与法文同名收藏、分类“待读”和“稍后”，原始收据为`karuyomi-94b7b82-category-faults-setup.json`；本版目录准备命令已在审计范围内。浅色首次重命名到“已读”实际应用后，确认交付没有完成，sequence 17的Worker/客户端终态均未记录；原因未确认，不计正常释放。UI显示尚未确认且保留原请求，明确重试原UUID/正文后没有重复应用。随后恢复“待读”的确认挂起正常释放。该正常等待实拍却显示灰色“重试”和未确认后的处理说明，缺少明确保存阶段，作为真实呈现缺口保留，不补05.K8主图。

浅/深均在相同的两个无分类作品、相同分类“待读”上明确开始批量添加。实际首项提交后挂起确认，`batch-waiting-{light,dark}`均显示0/2确认、1项未开始、英文项正在等待、法文项未开始及灰色忙碌关闭。明确请求暂停并正常释放后，`batch-paused-{light,dark}`显示1/2确认、1项未开始、完整原清单与继续/结束入口；独立重复读回均相等，第二项没有自动发送。浅色明确继续，仅第二项再推进一次版本并全部确认，随后明确批量移出恢复初始关联。深色明确结束，第二项始终原值，返回书架仍只选中未发送的法文项，另存`batch-ended-{dark,library-dark}`。这些结束后的不同路径是分项，不声称两主题全部继续/结束变体均通过。

`verify-94b7b82-category-evidence.ts`使用生成ProtoJSON模型核对13组九路快照（117条响应）、五个完全相等区间和94条连续审计，其中93条完成、仅sequence 17无终态且明确单列。14条POST为五次独立准备、两条分类原命令及一次原文精确重试、五条作品分类命令和一次明确UI主题保存；只有上述八个普通UI原操作各应用一次，精确重试零重复。分类目录最终revision 4、名称与顺序恢复；账户最终13、英文4/含待读、法文3/未分类、全局2/DARK，书签、阅读进度、续读和元数据保持。三个后续确认挂起均正常释放200，不把首次未完成交付改记正常释放；审计不代表Source运行时等全部网络请求。

本轮记录了 13 张 360×800 JPEG、完整 AX 和 13 组快照。四张实际批量等待/暂停图新增04.K3/K5两对主图，跨版本112→114/169（67.5%），仅单侧8、双侧均缺47，剩余55个主状态；其它图不重复计数。客户端已离开、视口恢复，harness正常退出0；未完成交付记录保留，不外推其请求生命周期全部通过。

分类保存阶段的缺口已在四项既有浅/深×1x/2x流程复现；初轮用例的异步释放与父页查找范围已修正，最终四项均在缺少等待说明处失败。现按原busy/blocked/confirmed推导保存、重读及已确认后的读取说明，等待期间隐藏未确认后的会话指引，动作显示“保存中”/“读取中”并保持冻结；说明与官方旋转指示共同呈现，辅助通知可读取。原请求、CAS、失效和迟到结果规则未改。四项流程继续核对名称和排序等待、实际关闭受阻、确认后无额外POST；分类和批量相关35项回归通过，日志为`category-confirmation-label-{red,regressions,analyze}.log`。新提示完整CI及新正式Web仍待，不把本轮旧提示图当作修复后通过；其它状态/变体与生产门保持原记录。

## 分类确认与读取失败的正式 Web 复验

2026-11-17，`61608c5088958239c70cd1fc38983087861ccb02`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44077550241)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44077561146)完整成功，Web与push Wasm通过，deploy跳过。正式Web artifact 14325368443共16,299,369字节，传输边界摘要`e5835153a8c3984962565c325cf7fd650ff2123cd63678371599d0fef9728682`及39条资源校验通过。官方API和acceptance Vite装配后，实际HTTP的35条Web资源与CI清单相等，入口`main.dart.e0813d2d.js`；`61608c5-category-confirmation-served-client-check.json`同时记录相同客户端/夹具提交。环境为官方Wrangler临时D1/R2、`acceptance-owner`、四包既有输入与三包安装、`editor-ui`、内置浏览器360×800，仅浅色，地址`127.0.0.1:58166`；未本地编译Flutter/AOT、未运行Source或原生、未部署生产。

五次独立准备为浅色/三包安装、英文/法文同名xkcd收藏、分类“待读”和“稍后”，原始收据`karuyomi-61608c5-category-confirmation-setup.json`逐项与审计原文相等。实际重命名“待读”至“已读”并挂起确认时，保存中与等待服务端确认文字正确，正常释放后列表读回成功。随后上移“稍后”的等待虽有正确通用阶段，却没有移动对象和目标位置；保留`reorder-waiting-light`作为缺口，不填05.K8。第三次重命名恢复“待读”，原POST正常交付200后仅下一次目录读取交付503；界面仍称“尚未确认保存，请原样重试”，动作仍为“重试保存”，`confirmed-readback-failure-light`保留失败。明确重试发送与原请求完全相同的UUID/CAS/正文，真实D1没有重复应用，但这是已收到有效ACK后的多余POST。最后明确恢复初始分类顺序并返回书架。

`verify-61608c5-category-confirmation-evidence.ts`用生成ProtoJSON模型核对七组九路快照（63条响应）、两个相等区间和64条连续完成审计。仅sequence36为受控目录读取503、无Worker响应，其余均Worker/客户端200；17、26、35三次确认挂起均正常释放。十条POST为五次独立准备、四条UI分类原命令及sequence42一次已知ACK后的额外精确重试；原命令各应用一次，重试没有增加revision。目录revision从2至6、账户5至9，最终名称/顺序恢复；两部作品始终revision1、已收藏、无分类/进度/书签/续读，全局1/LIGHT及其余内容不变。读失败/重试前后和恢复顺序/最终书架分别完全相等；没有UI主题或其它业务POST，审计不代表Source运行时等全部网络请求。

针对上述两个真实缺口，分类目录客户端仅在既有完整ACK校验后冻结本会话确认，读取失败时明确继续只重读；未知、无效和丢失ACK仍保留原命令精确重试，最新目录冲突仍阻止旧ACK恢复远端删除。编辑面、管理面及书架重开均保持已确认读取阶段，覆盖目录读取、首个书架读取和已发布书架读取三个失败点；排序增加冻结的完整名称与目标位置。八项最初失败、追加书架入口失败及后续已发布读取入口失败均先复现再修复。分类组件/仓库、书架、批量与迁移相关83项回归通过，同时覆盖旧ACK、身份关闭和原命令边界；日志`category-confirmed-readback-{red,shelf-red,published-red,regressions}.log`。新修复的完整CI和正式Web双主题仍待，不把旧失败图或组件结果当作新产物通过。

本轮记录了八张浅色 JPEG、完整 AX 和七组快照。本轮新增成对主图为0，仍114/169（67.5%），仅单侧8、双侧均缺47，剩余55个主状态及全部变体/最终产物；不外推分类全流程通过或PR整体完成。已离开客户端、恢复视口，harness正常退出0，原生停止及生产待验状态不变。

## 分类确认后读取阶段的即时反馈

2026-11-17，`500b5a35c62a335dba41fd97d690f2e6f56e3ec9`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44087677748)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44087693865)完整成功，Web及push Wasm通过，deploy跳过。准备正式双主题复验时，内置浏览器的视口设置/空白标签创建组合调用、库存查询、按原URL查找标签及稍后独立创建空白标签四次均约30秒超时并重置控制会话；不能判定组合调用中哪一步未返回，标签是否建立及视口是否改变也未确认。只读进程查询仍见Codex与SkyComputerUseService，进程存在不证明控制健康，根因未确认，不归因于审批额度或产品服务。原始事实单列于忽略文件`500b5a3-browser-unavailable.json`。本轮未进入产品页面、未启动Wrangler验收服务、未新下载/装配该Web，未改用其它浏览器；恢复控制后须先核对视口和标签状态，不声称已恢复默认视口。

在不依赖浏览器的分项中，四项既有浅/深×1x/2x分类流程增加两道独立响应门：先挂起已应用命令的ACK，再正常交付ACK而挂起后续目录读取。四项均在缺少已确认后的读取说明处失败，定位为确认已入客户端但编辑面未收到阶段更新，日志`category-ack-read-phase-red.log`。现沿原串行分类命令传递同步阶段通知，只有完整ACK校验并冻结本会话确认后才触发；输入/排序立即切换“读取中”和读取说明，最终目录/书架读回完成后才结束。通知不增加请求、持久化或协议字段，未知请求精确重试、有效ACK只重读及真实冲突规则保持。

继续按既有“读取可关闭”设计，以实际“稍后”按钮在四项流程复现确认后只读仍禁用关闭；`category-read-dismiss-red.log`四项均在按钮回调为空处失败。现只在等待确认时禁止关闭，已确认读取及冲突重读允许关闭，输入和重复提交仍冻结。关闭子面后管理面保留完整原操作摘要，再关闭并从书架重开复用同一次读取，POST及目录GET均不增加；释放原读取后只更新重开的管理面，不由旧窗口关闭新路由。四项输入/排序往返通过，保留无效ACK及身份关闭后迟到ACK不通知的边界。初轮Escape假设、按钮过渡帧和响应门时序已纠正并单列保留，不计产品缺陷；最终广度回归见下段。

既有真实CAS流程还复现冲突重读后，已重开的管理面继续保留旧分类且不能编辑，见`category-conflict-read-reopen-red.log`。现保存完整权威读回并交接到当前管理面，完成后解除冻结；旧窗口不导航。独立仓库用例先在`library-initial-read-freshness-red.log`复现：本次书架GET尚未完成，另一部漫画的已确认读取通知已使首次订阅返回旧列表。书架订阅现先等待自身刷新完成，再接收实时更新；初次失败后仍可恢复后续通知，没有增加请求。为核对共享语义，扩展到业务客户端、书架快照/收藏、书签、封面、章节标记、分类、批量、迁移及书架/续读共14个相关文件，154项单并发回归全部通过，日志`category-read-recovery-regressions.log`。界面层验证关闭/重开与快照交接，数据层独立验证并发首次结果；此前将两次读取等待同一挂起刷新的测试用例已中断并纠正，不计通过。新完整CI与正式Web双主题仍待。

本轮没有新的正式Web主图，仍114/169（67.5%）、仅单侧8、双侧均缺47，剩余55个主状态以及全部相关变体、转换和最终产物门槛。组件响应门不替代真实浏览器、Access或原生证据，PR #8仍草稿、未合并、未部署。

## 内置浏览器恢复后的分类浅色复验

2026-11-17，`49f34823503bfa63aae73d7fb2e69c5133e63e5e`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44096952683)和[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44096963798)完整成功，Web与push Wasm通过，deploy跳过。正式Web artifact 14335076593为16,299,923字节，传输边界摘要`52a11bcc89f19f8c272ce659f6d3c40415543f97ec551c9362971bde58a076e8`和39条CI资源校验通过。官方API与acceptance Vite分别构建后，实际HTTP交付35条Web资源与CI相等，入口`main.dart.2fab9a56.js`；`49f3482-category-recovery-served-client-check.json`分别记录相同客户端/夹具提交。官方Wrangler临时D1/R2、`acceptance-owner`、四包既有输入与三包安装、`editor-ui`、内置浏览器360×800，仅浅色，地址`127.0.0.1:64096`；未本地编译Flutter/AOT，未验Source、原生或生产。

刷新浏览器库存后，当次控制会话中ID1为内置浏览器、ID2为MCP Apps；选择实际内置浏览器后，新建空白页、读取UI和产品交互成功。数字ID不跨会话沿用。不能由这次库存差异推断先前四次超时的共同根因，先前包括显式`iab`创建的失败仍保留，也不归因于审批额度；本轮没有换用其它桌面浏览器。

五次独立API准备仍为浅色/三包安装、英文/法文同名收藏和“待读”/“稍后”两分类，原收据`karuyomi-49f3482-category-recovery-setup.json`保留。UI把“待读”重命名为“已读”，`rename-waiting-light`实际显示保存中、等待确认及冻结输入。人工释放后首次确认交付仍没有终态，审计sequence17的Worker/客户端状态均为空；原因未完整测量，不把工具往返延迟推断为产品超时，也不计正常释放。UI转为未知结果，独立读回已见目录revision3和“已读”。明确“重试保存”沿用同一UUID/CAS/完整正文，sequence23正常200，目录与账户均不再增长；随后稳定分类列表和书架均已实看。

`verify-49f3482-initial-category-probe.ts`以生成ProtoJSON模型核对四组九路快照（36条响应）、两个完全相等区间及36条连续审计，35条完成、仅sequence17未完成。七条POST为五次独立准备、一条UI原命令及一次精确重试；UI原命令只应用一次。账户5→6、目录2→3，最终“已读”/“稍后”；两作品始终revision1且已收藏，分类关联、书签、阅读进度、续读、资料与其它设置不变，全局1/LIGHT。没有UI主题或其它业务写入，审计仍不含Source运行时请求。

本轮取得四组 DOM 与 JPEG。辅助`library-baseline-light`为AX图，未当作新主状态。快照、初始及最终原审计、`initial-probe-evidence-receipt.json`与`49f3482-initial-category-probe-evidence-check.log`均保留。读取关闭/重开、排序、已确认读取失败、冲突、身份失效及深色尚未在本轮完成；不补05.K8/K9，仍114/169（67.5%）、仅单侧8、双侧均缺47。客户端已离开并恢复默认视口，harness正常退出0。

为避免瞬时确认状态依赖人工释放往返，既有官方夹具新增`delay-confirm`（2秒）、`delay-read`（5秒）和`confirm-read-failure`（真实提交与2秒后正常ACK，再令后续读取503）。等待仍逐秒检查取消和control generation，显式改模式优先；人工挂起仍30秒失败，不能静默当作成功。仅测试夹具生效，产品超时、生产入口、绑定和协议不变，256条审计上限保留。57项Workers/D1/R2回归及API/test严格类型通过，覆盖真实事务先完成、自动交付、原响应不变、取消、显式模式覆盖和无关进度透传，日志`editor-ui-automatic-delay-{workers,typecheck}.log`。新夹具完整CI与正式Web尚待，组件/夹具通过不算主状态完成。

## 分类保存与恢复的正式 Web 双主题复验

2026-11-17，夹具`59793615380310187723ac18f97ee9a075bb2c78`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44109445536)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44109464101)完整成功，Web与push Wasm通过、deploy跳过。复用此前已校验的`49f3482`正式CI Web，客户端、协议、runtime和生产API源码相对该提交均无差异；夹具版本单独记录。官方API和acceptance Vite依次构建，实际HTTP交付35条Web资源与CI相等，入口仍`main.dart.2fab9a56.js`，见`5979361-category-auto-recovery-served-client-check.json`。环境为官方Wrangler临时D1/R2、`acceptance-owner`、四包既有输入及三包安装、`editor-ui`、内置浏览器360×800，地址`127.0.0.1:52971`；未本地编译Flutter/AOT，未验Source、原生、真实Access或生产。

五次独立准备仍为浅色/三包安装、英文/法文同名收藏与“待读”/“稍后”两分类，原收据`karuyomi-49f3482-category-auto-recovery-setup.json`与审计逐字相等。浅/深均实拍“待读”→“已读”的正常保存等待，以及“稍后”上移第1位的完整冻结对象、目标位置和等待说明；实际点击忙碌“稍后”均未离开。8次短自动确认完整交付200；随后均读回真实目录。首次截图辅助函数仍绑定旧前缀，`wx`阻止覆盖，纠正后额外恢复/重做两次浅色UI命令均纳入审计，不从增量中隐去。两次确认后读取失败的ACK另记，不能混算未知或拒绝。

两主题均实际应用改名后仅丢确认，返回502，UI显示未知并保留原请求。关闭子面/管理面，从书架重开后仍为原命令；明确重试的UUID、CAS与完整正文逐字相同，零重复应用。另两次正常ACK后目录读取503，界面明确显示“修改已确认”及“重试读取”，不再称未保存。明确只读重试时实际关闭子面和管理面，从书架重开复用原读取；完成后更新新窗口的最新分类，不由旧窗口关闭新路由。两段已知ACK至后续明确改名之间全部为GET，各只有一次目录GET，重开没有新增目录请求；保留既有书架读回，不声称所有GET均只有一次。

明确400与真实CAS分别验收：每种主题先拒绝UI草稿，再明确重读并关闭；远端通过独立API把第二分类改为“远端稍后”，本端旧目录保存得到真实409，冻结原草稿。第二次独立远端改成“再次远端”后，在重读中关闭并从书架重开，结果交接最新名称并恢复编辑，随后由UI明确恢复“稍后”。四次独立远端原文及前后回执分别存`category-remote-auto-{light,dark}-{conflict,latest}.json`，不计UI写入。两主题拒绝/冲突的错误正文与重读入口正确，但辅助说明仍沿用未知请求的“关闭不会撤回、继续处理”，`{rejected,conflict}-{light,dark}`保留为呈现失败，不补05.K10。

05.K11仅取得实际深色图：受控401使旧窗口显示身份变化，原重试动作点击没有新增请求，子面和管理面均可明确关闭。在服务连接页重新连接同一身份后，书架/管理面仍保留原待确认命令，尚未明确重试便不自动提交；最终权威名称仍为“待读”/“稍后”。这是隔离身份故障与同身份恢复分项，不是实际Access登录或身份更换，未清除原命令也不把它记为已保存。浅色失效仍待，未改系统外观来补图。

`verify-49f3482-category-auto-evidence.ts`以生成ProtoJSON模型核对28组九路快照（252条响应）、九个完全相等区间及247条连续完成审计；没有无终态记录，审计仍低于原256上限。33条POST分为五次独立准备、四次独立远端、16条UI分类原命令、两次原文重试、两次400、两次真实409、一次401及一次明确UI主题保存。16条UI原命令各应用一次，两次原文重试零重复，已知ACK读取重试零额外POST，400/409/401不应用。账户最终26、目录22、全局2/DARK；两作品始终revision1且已收藏，无分类关联/书签/阅读进度/续读，资料及其余设置不变。该审计不包含Source运行时等所有网络请求。此前人工挂起系列的sequence17无终态继续保留，不能用新自动系列的完成行追溯补全。

本轮取得 31 组 DOM 与 JPEG。其中`unknown-reopened-light`、两主题`confirmed-reading-reopened`及`conflict-reading-reopened`五张仍是可见转场帧，排除主图，稳定结果图另外保留。`category-auto-ui-{audit-final,evidence-receipt}.json`与`49f3482-category-auto-evidence-check.log`记录完整核对。辅助脚本最初少算一次自动确认、图片元数据遗漏`type`，原失败日志保留并按真实原审计/图像纠正，不计产品缺陷。输入/排序等待及未知/已确认读取失败新增05.K8/K9两对主图；05.K11只增加深色。跨版本114→116/169（68.6%），仅单侧9、双侧均缺44，剩余53个主状态及全部相关变体、转换和最终产物；31张图不等于31个新增状态，覆盖率仍不代表PR整体完成。客户端已离开、默认视口已恢复，harness正常退出0。

上述拒绝辅助说明在四项既有浅/深×1x/2x流程先复现，日志`category-rejected-caption-red.log`均在缺少重新读取指引处失败；现按既有blocked阶段说明“原草稿不会自动提交”，引导重读关闭后按最新内容编辑。子面与管理面共用该反馈，未知原请求和已确认读取仍保持各自说明；未改命令、协议或生命周期。四项流程核对400零应用、关闭后说明保留、明确重读再开及零自动提交，既有真实CAS流程同样核对专用说明；分类组件/仓库、书架和批量五文件69项回归全部通过，日志`category-rejected-caption-regressions-corrected.log`。首轮测试命令另含不存在的批量路径，该次不计完整通过；纠正为真实文件后重跑通过。新提示完整CI与正式Web双主题仍待，不能用旧失败图填05.K10；PR #8仍草稿、未合并、未部署。

## 批量部分提交的确定性故障入口

2026-11-18，`d09212bf7e8c5e3c80557538015bc4781ac8bb85`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44120475013)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44120486889)完整成功，Web及push Wasm通过，deploy跳过。正式Web artifact 14345372682共16,299,975字节，传输边界摘要`25280c59aa0bef3bb63e6b19f215f637263ef44b0908ba87e2b9a9079547f441`和39条资源核对通过，原归档及收据保留，已替换本地生成Web/runtime输出；尚未把该客户端的新拒绝说明记为正式浏览器通过。

为实际取得04.K4的已确认/未确认/未开始并存状态，现有官方`editor-ui`增加`confirm-next-loss`。首个成功命令先运行真实D1事务，自动延迟2秒正常交付原回执，同时仅对原generation切换为`lose-confirm`；后项仍实际提交，只丢成功回执，明确`editor pass <scope>`后才能原样重试。与既有确认后读取失败共用受generation保护的模式切换，显式改模式优先；取消、30秒人工等待、256条审计上限、其它命令透传和生产隔离均保持，没有改产品超时或业务协议。

62项官方Workers/D1/R2回归通过，覆盖目录和作品分类的第一条200、第二条真实提交/502、同UUID/正文重试200且零重复，以及新增模式的取消和显式覆盖。初轮分类关联第二作品尚未收藏，实际API拒绝400，`editor-ui-partial-batch-workers.log`保留该测试准备错误；分类夹具补齐两部真实收藏后，`editor-ui-partial-batch-workers-corrected.log`全部通过，没有以假回执绕过校验。API/test严格类型与本轮完整检查另行执行，新夹具完整CI和对应正式Web仍待，116/169（68.6%）保持。这是验收入口，不是部分批量、拒绝、失效或Source运行能力已完成。

## 分类与部分批量的正式 Web 准备受阻

2026-11-18，夹具`c6f1ce6f3185e08bc88b98e48bd6f6e0fdaa3478`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44124744792)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44124760947)完整成功，Web及push Wasm通过、deploy跳过。API/test严格类型、完整格式/校验、依赖分层和标准prek hook通过。正式客户端复用已验证的`d09212b`，客户端、协议、runtime及生产API源码相对该提交均无差异；通过官方API和acceptance Vite分别装配，实际HTTP交付35条Web资源与CI相等，入口`main.dart.7733b8cd.js`，原收据`c6f1ce6-library-faults-served-client-check.json`保留。环境为官方Wrangler临时D1/R2、`acceptance-owner`、四包既有输入、`editor-ui`，地址`127.0.0.1:49790`；没有本地Flutter/AOT构建。

六次独立API准备为浅色/三包安装、英文/法文同名xkcd收藏、两分类以及西语xkcd测试收藏。西语Source身份来自已固定清单，资料为明确受控准备，未执行该Source或声称运行兼容。`verify-c6f1ce6-browser-unavailable.ts`以生成ProtoJSON模型核对十二路完整基线及18条连续完成审计，全部Worker/客户端200，六条POST与准备原正文逐字相等；UI业务写入为0。账户6、目录2、全局1/LIGHT，三作品各revision1且已收藏，无分类关联/书签/阅读进度/续读，资料与各自准备命令一致，书架完整三项。快照、准备、审计和`unavailable-evidence-receipt.json`使用前缀`karuyomi-d09212b-library-faults-`，校验日志为`c6f1ce6-browser-unavailable-evidence-check.log`。

内置浏览器先以同一调用设置360×800、创建隐藏标签并绑定现代接口，约30秒超时后重置；无法判定其中哪一步未返回。随后完整库存、显式`iab`的实际URL标签定位，以及再次显式`iab`选择三个独立调用也各约30秒超时并重置。此前只读标签库存曾正常返回空列表，不代表后续控制健康。没有可核验的新产品画面、AX/DOM或截图，标签是否建立及视口是否改变/恢复均未确认；根因仍未知，不归因于审批额度、产品服务或某一个组合步骤。原事实保存在`c6f1ce6-browser-unavailable.json`，未改用其它浏览器。恢复后先核对实际浏览器、标签和视口，再启动新的独立验收批次；本次harness由明确stop正常退出0，不把控制观察超时当成服务失败或重启依据。

同轮后续只读诊断在实际安装的ChatGPT 26.1111.21308桌面日志中，按当前聊天与当前turn筛出IAB `getInfo`的直接拒绝：`IAB browser belongs to another task.`，栈位于`prepareSessionRoute`。精简计数与时间范围保存在`c6f1ce6-browser-ownership-diagnostic.json`，未把完整桌面日志复制入库。官方`open_in_codex`为当前聊天打开内置浏览器面板返回queued；该入口只排队，不代表页面或控制恢复，已请求用户显示当前聊天的浏览器后继续。为什么桌面归属不一致仍未确定；同时出现的Local Work rendezvous WebSocket超时不是本次浏览器因果证据，不据此更改网络、审批或归属校验。

用户随后确认当前聊天的内置浏览器已打开。新的显式iab选择约33秒、完整库存约30秒后仍超时并重置，累计六次控制调用无画面。最新桌面owner sync的`ownerRoutePath`确实指向本持久聊天，而`conversationId`仍是`client-new-thread`临时身份；本聊天请求继续收到相同归属拒绝，官方面板入口再次queued。精简后续事实保存在`c6f1ce6-browser-ownership-after-handoff.json`，不能归因于用户切错聊天，也不能将普通打开面板记作恢复。更深桌面状态原因尚未证明，待重建桌面连接后再验；未改写浏览器owner或绕过控制路径，未重新启动已正常停止的harness。

没有新主图，仍116/169（68.6%）、仅单侧9、双侧均缺44，剩余53个主状态及全部相关变体、转换和最终产物门。05.K10修复后的双主题、04.K4/K6/K8及其它待办继续按原状态机推进；本次API准备不替代正式渲染、真实Access、Source、原生或生产证据，PR #8保持草稿、未合并、未部署。

## 单作品与批量确认后的读取恢复

2026-11-18，内置浏览器重建连接仍待用户操作时，组件供应端复现了目录以外的同类缺陷：移出收藏已收到有效 ACK，但补读分类书架失败时，下一次仍 POST；单作品分类先丢确认、原文重试收到有效 ACK、随后漫画读取503时，也再次 POST，界面仍提示尚未确认保存。三条定向回归先失败，批量分类/移出收藏与浅深色×普通/双倍文字的六条回归同样先失败；日志分别保存在忽略目录的`association-ack-read-red-corrected.log`和`batch-ack-read-red.log`。首次命令误用字面名称筛选导致0项，单独保留`association-ack-read-red.log`，不计作产品回归。

共享数据客户端仅在完整协议、身份、revision、目标字段及进度/书签/封面校验通过后冻结 ACK，原命令在当前会话继续保留。未知结果仍精确重试原 UUID/CAS/正文；有效确认后的重试只读最新权威状态，旧确认遇到较新远端修改仍冲突，格式错误的 ACK 不触发确认通知。单作品分类即时显示确认后的读取阶段，可关闭并从书架重开继续读；批量分别显示读取中、读取失败与未知结果，确认计数和整批完成分开，读回失败不自动发送后续项。

低优先级、单并发的十三个相关文件最终159项回归通过，范围包含共享业务客户端、分类/书架快照、进度、书签、封面、迁移仓库与分类/批量/书架/续读组件；`library-ack-read-targeted-final.log`保留，首轮158项记录单列。额外挂起真实组件回复的六项用例核对分类读取中的即时文案与关闭入口，并记录批量读取中阶段，见`library-ack-read-live-phase.log`；读取业务拒绝误报写入拒绝的用例先失败后修复，`batch-ack-read-rejection-red.log`保留。原文重试、读取零额外POST、较新远端分类冲突、无效ACK不确认、重开及剩余清单明确继续均分别检查。组件供应端使用生成协议，不等同于真实Worker/D1或正式Web业务审计。九文件严格分析、完整格式/校验与依赖检查通过，日志使用`library-ack-read-`前缀；首次严格分析因换行后的单行if缺少括号失败，补齐后重跑通过。新提交的完整CI见[PR #8检查](https://github.com/Wybxc/karuyomi/pull/8/checks)，正式Web继续待验。

本轮没有浏览器画面或新主图，覆盖仍116/169（68.6%）；05.K10、04.K4/K6/K8及这次读取反馈的正式Web双主题与剩余门继续待验。PR #8保持草稿，未合并、未部署，没有本地完整Flutter或AOT构建。

## 分类与部分批量的正式 Web 双主题验收

2026-11-18，客户端及夹具`9a1c03ca57b1e3bb07333f4ef0b6806fcce34e32`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44135811922)、[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44135829160)、Web和push Wasm全部通过，deploy跳过。归档在下载边界验证大小和SHA-256，39条资源清单校验后只复制生成的Web/runtime；官方API及acceptance Vite装配通过，没有本地Flutter或AOT构建。新隔离harness使用官方Wrangler临时D1/R2、`acceptance-owner`及既有静态快照，地址`127.0.0.1:51155`；实际HTTP交付清单的35条记录与CI相等，入口`main.dart.4c59c4ea.js`。

本轮库存返回当前聊天的IAB，选择实际ID后成功建立空白标签，随后实际页面、DOM和截图操作全部可用。此前六次归属失败及未确认的旧视口记录保留；恢复原因、用户是否重启仍未证明，不能把新回合或某次选择推断为修复原因。没有改写owner或改用其它浏览器。Flutter屏外语义入口以Enter启用；两次正常返回/退出选择后使用旧定位器未匹配，读取新DOM后继续，没有额外业务提交。精简恢复与操作记录保存在`9a1c03c-library-ack-read-browser-recovery.json`。

六次独立API准备为浅色与三包安装、英文/法文xkcd收藏、两分类和西语测试收藏；西语身份来自固定清单，资料为明确受控准备，未执行Source或声称运行兼容。随后只通过正式UI操作。单作品分类在真实D1提交后丢确认，原UUID/CAS/正文重试获得有效ACK，再遇到读取503；双主题均正确区分未知与已确认读取失败，明确再次读取、关闭/书架重开及恢复只读完成，未增加POST。三项批量分别显示首项已确认、第二项已提交但确认未知、第三项未发送；关闭重开保留冻结清单，原文重试零重复，最后一项直到明确继续才发送。全部分类恢复也通过明确UI完成。

分类目录与批量各在浅/深色执行一次受控400，原草稿冻结，分别提供“重新读取并关闭”和“重新读取并结束原批次”；四次拒绝与重读结束都不改变权威状态。05.K10已实看修复后的“原草稿不会自动提交”说明，先前错误画面保留。本轮没有新增真实CAS或身份失效证据，也不把受控400说成D1业务拒绝。

`verify-9a1c03c-library-ack-read.ts`使用生成ProtoJSON模型核对28组十二路完整快照（336份响应）和16个完全相等区间，仅允许明确的漫画/账户revision、分类关联及一次UI主题保存变化；目录恒为revision2，两分类名称/顺序、全部资料/收藏、书签、进度、续读和封面保持。224条连续审计均有客户端终态，未触及256上限；其中216条真实Worker返回200，四次读取503及四次拒绝400由入口在转发前产生。31条POST逐字核对：六次准备、17次UI原操作应用（含一次主题保存）、四次相同原请求重试零重复、四次拒绝零应用，没有额外POST或隐式剩余提交。最终账户23、目录2、全局2/DARK，英/法/西三作品revision为9/5/5且均未分类。

34张360×800 JPEG及对应完整DOM已核对。新增04.K4/K6与05.K10三对主图，跨版本双主题覆盖116→119/169（70.4%），仅单侧9、双侧均缺41，剩余50个主状态及全部变体、转换与最终产物门。浅色重开的一张进入转场单列为辅助，不补主图。校验收据为`karuyomi-9a1c03c-library-ack-read-evidence-receipt.json`；首轮校验器误把普通读取保留的故障mode标签当作错误，保留失败日志后按读写实际语义修正，最终校验与独立严格类型检查通过，日志为`9a1c03c-library-ack-read-evidence-check-corrected.log`和`9a1c03c-library-ack-read-evidence-typecheck.log`。

完成后实际导航到空白页、恢复默认视口、关闭临时标签并确认标签列表为空；harness由明确stop正常退出0。没有新增Source执行、原生或生产验收，PR #8保持草稿，未合并、未部署。全部相关变体、像素叠图和目标设备门槛继续按原计划推进。

## 源收藏恢复布局的浅色复现与修复

2026-11-18，复用完整CI已通过的客户端及夹具`9a1c03ca57b1e3bb07333f4ef0b6806fcce34e32`，官方API/acceptance Vite装配的隔离harness位于`127.0.0.1:60188`，实际HTTP交付清单35条记录与CI相等，入口仍为`main.dart.4c59c4ea.js`。内置浏览器360×800浅色实际操作源目录读取、筛选、收藏确认、取消收藏丢确认和原文重试。状态区贴到x=0，未知状态直接堆叠完整全局设置，且没有独立原取消对象说明；发现后停止补拍中间布局的深色主图。七张JPEG与完整DOM保留，语言菜单退出转场单列为辅助，不计新主图。

`verify-9a1c03c-source-favorites-faults.ts`使用生成ProtoJSON模型及固定清单核对五组六路完整快照（30份响应）、两个完全相等区间和26条连续终态审计。五条POST为两次独立准备、两次UI原操作应用、一次相同UUID/CAS/正文重试零重复；丢确认的真实Worker200、客户端502单列。最终账户4、全局3/LIGHT、收藏源为空，书架作品revision1，分类、书签、进度、续读及其它设置保持。校验日志和收据为`9a1c03c-source-favorites-faults-evidence-check.log`及`karuyomi-9a1c03c-source-favorites-faults-evidence-receipt.json`。目录只使用静态元数据，没有执行Source。临时标签、视口和harness已正常清理。

源目录现给状态横向16留白，以官方Cupertino列表独立显示原收藏/取消对象，完整原全局设置通过官方Expansible展开。首次提交仅在已确认全局快照revision等于原CAS时保留其冻结值；按包名和Source ID比较变化，刷新后的当前列表不能替代原基线。基线仅属于当前身份会话，不改变协议、请求正文、UUID/CAS、幂等或持久化；没有已知基线时不推测原增删。原值在只读刷新及页面重建后仍可查看，原请求仍由用户明确重试。

浅深色×普通/双倍文字的四项360×800组件回归先因x=0失败，再通过留白、原对象、刷新/重开、完整值展开与精确重试断言，日志为`source-pending-layout-red.log`、`source-pending-layout-green-initial.log`。八文件124项相关数据、设置、Source及扩展回归最终通过，见`source-pending-layout-targeted.log`；组件供应端不等同于真实D1或正式渲染。五文件严格分析、完整格式/校验、证据工具严格类型和依赖检查通过，日志使用`source-pending-layout-`前缀；新提交完整CI及新正式Web双主题仍待。覆盖保持119/169（70.4%），没有把修复前实拍计作Source读取/等待/未知三对完成，PR #8仍草稿，未合并、未部署，原生与生产门不变。

## 展开状态与滚动位置的存储隔离

2026-11-18，客户端及夹具`fe57f2cdcbd65bdcb4243d3f73aeedd8b5baa2de`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44154200070)、[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44154216791)、Web及push Wasm全部成功，deploy跳过。正式归档下载边界大小/SHA-256及39条资源校验通过，仅复制生成的Web/runtime；官方API与acceptance Vite顺序装配，HTTP交付清单35条与CI相同，入口`main.dart.c06e6c38.js`。官方Wrangler临时D1/R2、`acceptance-owner`、既有静态快照和内置浏览器360×800，地址`127.0.0.1:65316`，没有本地完整Flutter/AOT构建。

浅色实际核对读取与保存等待的留白、英文xkcd筛选、已确认收藏、取消已提交但丢确认、只读刷新、书架/源目录重开、完整原值展开/收起与明确原文重试。刷新后的当前列表已取消，原对象仍显示“取消收藏源：xkcd”，完整原值默认收起且可查看；浅色补取一次明确只读刷新并再次重开，分段快照均保持。正式UI保存深色主题后重开源目录，内容区持续空白/灰色，控制台报告`bool`不能读取为`double?`；两张深色图均为失败，不能解释为加载或转场。停止补拍该中间版本。

`verify-fe57f2c-source-render-failure.ts`通过生成ProtoJSON模型、固定清单、实际HTTP清单和图片尺寸核对十组六路完整快照（60份响应）、六个完全相等区间及49条连续终态审计。六条POST为两次独立准备、两次源原操作、一次明确UI主题保存及一次相同UUID/CAS/正文重试；三条UI原操作各应用一次，重试零重复。丢确认一条真实Worker200/客户端502，其余均200；最终账户5、全局4/DARK、收藏源为空，书架作品revision1，分类、书签、进度、续读、资料与其它设置保持。11张JPEG/完整DOM、控制台和收据使用`karuyomi-fe57f2c-source-pending-formal-`前缀；校验与严格类型日志为`fe57f2c-source-render-failure-evidence-check.log`及`fe57f2c-source-render-failure-typecheck.log`，收据为`interrupted-evidence-receipt.json`。未执行Source，标签、视口及harness均已正常清理，退出0。

正式产物堆栈落在`ScrollPosition.restoreScrollOffset`，与固定Flutter SDK的`Expansible`和`PageStorage`实现对应：普通ValueKey不参与存储身份，折叠组件向父列表同一标识写入bool，重开列表按double读取便失败。按官方要求，六处Expansible现分别使用独立PageStorageKey，包括源/扩展原值、扩展详情/仓库/存储诊断与跨源搜索范围，不关闭滚动恢复、不捕获类型错误或绕过检查，也不改变业务请求。

共享同一PageStorageBucket、双主题和展开/收起的源目录四项组件回归先复现；扩展首轮因本地tap helper声明顺序未编译，首轮日志保留，调整后扩展四项同样复现bool/double错误。八项修复后全部通过，日志为`expansion-page-storage-red.log`、`expansion-page-storage-extensions-red-corrected.log`及`expansion-page-storage-green.log`。用例继续验证原对象、完整原值、精确重试零重复，以及确认清除后切换主题重开；四文件100项源、扩展、仓库和跨源搜索相关回归通过，见`expansion-page-storage-targeted.log`。五文件严格分析、完整格式/校验、证据工具严格类型和依赖检查通过，日志使用`expansion-page-storage-`前缀；新提交完整CI与存储隔离修复后的正式Web双主题仍待。独立计数器再次核对119/169（70.4%）、单侧9、双侧均缺41，见`expansion-page-storage-state-coverage-count.json`，没有新增主图。PR #8仍草稿、未合并、未部署，原生及生产门不变。

## 源收藏与存储隔离的正式 Web 双主题验收

2026-11-18，客户端及夹具`1bc3c70816262b65deca1c7f23a5bb1f149eed3b`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44160170997)、[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44160183317)、Web及push Wasm全部成功，deploy跳过。正式归档在下载边界校验大小/SHA-256，39条资源校验后只复制生成的Web/runtime；官方API和acceptance Vite装配通过，没有本地完整Flutter或AOT构建。官方Wrangler临时D1/R2、`acceptance-owner`、既有静态快照和内置浏览器360×800，地址`127.0.0.1:54791`；实际HTTP交付清单35条与CI一致，入口`main.dart.3fd12e0d.js`。

两次独立API准备为浅色与三包安装、英文xkcd书架收藏。此后只经正式UI操作源目录读取、名称/英文筛选、收藏等待、已确认收藏、取消已提交但丢确认、只读刷新、书架/源目录重开、完整原值展开/收起及明确原文重试；另有一次明确UI主题保存。双主题原取消对象都在当前列表已更新后继续显示，原值默认收起且可完整核对。浅色展开/收起后确认原操作、切换深色并重开，正面复验此前失败路径；深色完成同样恢复后再次重开也正常。读取与等待均保存真实文案、指示器和当前列表，不以文件名推断加载状态。

`verify-source-pending-formal.ts`使用生成ProtoJSON模型、固定Source清单、HTTP资源清单与实际DOM核对16组六路完整快照（96份响应）、十个完全相等区间及73条连续终态审计。九条POST逐字核对为两次独立准备、五次UI原操作（四次源收藏变化与一次主题保存）、两次相同UUID/CAS/正文重试；五条UI原操作各应用一次，两次重试零重复，刷新、重开与查看原值没有额外POST。两条取消的真实Worker200/客户端502单列，其余均200；最终账户7、全局6/DARK、收藏源为空，书架作品revision1且仍收藏，无分类关联/书签/进度/续读/自定义封面，资料与其它设置保持。目录只使用静态元数据，没有主动打开或执行Source，书架无自定义封面；不据此声明Source在线兼容或阅读能力。

18张360×800 JPEG及对应完整DOM已核对，新增07.K1/K5/K9三对。源目录在主题切换及确认后的再次重开均正常，控制台错误/警告记录为空。校验日志与收据为`1bc3c70-source-pending-formal-evidence-check.log`及`karuyomi-1bc3c70-source-pending-formal-evidence-receipt.json`；控制台为同前缀`console-final.json`。全部旧失败保留，未覆盖`fe57f2c`文件。完成后导航空白页、恢复默认视口、关闭临时标签并确认列表为空；harness明确stop正常退出0。跨版本主图119→122/169（72.2%）、单侧9、双侧均缺38；独立计数见`source-pending-state-coverage-count.json`。Source受阻、真实CAS/身份、其它组件展开、全部相关变体和最终像素/产物门继续待验，PR #8仍草稿，未合并、未部署，Native与生产门不变。

## 扩展原操作与设置确认后的读取恢复

2026-11-18，组件与数据边界回归发现扩展/仓库结果未知时没有独立原对象，完整原全局值也遗漏安装选择和额外仓库；刷新已应用的卸载或移除后，当前列表无法说明原操作。十四项浅/深、普通/双倍文字及源目录共享恢复流程先失败后通过，日志为`extension-pending-original-red.log`与`extension-pending-original-green-initial.log`。现按冻结基线显示原操作，完整值保留包、启用、仓库、构建和产物身份；只读刷新与页面重建不替换原对象，也不猜测未知基线。两项真实组件供应端重试另复现发送写入时仍显示读取，修正为原响应抵达前显示保存，日志为`extension-pending-retry-phase-red.log`及下述通过记录。

共享设置边界另有有效 ACK 后 GET 失败仍重复 POST，并误报“未确认”的缺口；全局/漫画设置、显式刷新/原操作恢复及即时阶段反馈六项先复现，见`settings-ack-read-red.log`。现只在 ACK 完整校验后保留冻结确认，立即切为读取；补读失败显示已确认，重试和显式刷新都只读取。低 revision 继续有界重读，同 revision 不一致在缓存前拒绝，无效 ACK 不阻止必要的原命令重试；较新远端值不匹配仍为冲突，已知拒绝在重建后保留。`settings-ack-read-green-initial.log`八项通过，其中包含上述两项扩展写入阶段回归。

最终十文件189项相关数据、设置、扩展、仓库和源收藏组件回归通过，见`extension-settings-recovery-targeted-corrected.log`。首次广度回归186项通过、一项旧测试在展开完整值后未滚回被延迟构建的收藏按钮；补充显式滚动后通过，原日志`extension-settings-recovery-targeted.log`保留。最终还覆盖已确认读取失败的扩展页面重开、读取重试零额外POST、无效ACK和已知拒绝重建。十四文件严格分析与依赖检查通过，日志使用`extension-settings-recovery-`前缀；首轮两处缺少花括号已修正，`analyze-corrected.log`无问题。组件供应端不等同于真实Worker/D1或正式Web，新提交完整CI和正式双主题仍待；覆盖保持122/169（72.2%），PR #8草稿未部署，未新增Source运行、原生或生产证据。

`891029a`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44175170127)与[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44175183359)中，`pnpm check`通过，`pnpm flutter:check`在生成一致性阶段失败，未进入完整Dart回归或Web构建。遗漏的Riverpod控制器哈希现由官方`pnpm flutter:generate`更新，独立`pnpm flutter:generate:check`通过，不手工编辑生成文件；日志为`extension-settings-recovery-generate.log`及`extension-settings-recovery-generate-check.log`。本地仍不运行完整Flutter检查、构建或AOT，新提交完整CI及正式Web继续待验，覆盖不变。

## 扩展与共享设置恢复的正式 Web 双主题验收

2026-11-18，客户端及夹具`2512c51a4a021ccfa333ac682b2638ce4a878979`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44176813008)、[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44176825421)、Web及push Wasm全部成功，deploy跳过，补齐上一提交遗漏的Riverpod生成哈希。正式归档`14370652915`在下载边界核对大小`16304327`及GitHub SHA-256，39条资源校验后只复制生成的Web/runtime；官方API和acceptance Vite依次装配，没有本地完整Flutter或AOT构建。官方Wrangler临时D1/R2、`acceptance-owner`、既有四包静态快照与内置浏览器360×800，地址`127.0.0.1:53180`；实际HTTP清单35条与CI相等，入口`main.dart.913e5f50.js`。归档摘要和完整CI结果分别保存在`ci-web-2512c51-integrity.json`与`2512c51-final-checks.json`。

两次独立API准备为浅色、两个其它已安装包、保留但未安装的英文xkcd收藏源，以及一部xkcd书架收藏。正式UI在双主题核对受阻源显示身份/原因、实际转到扩展管理、安装确认等待与成功、卸载丢确认、原对象刷新/书架及源/扩展往返、未知卸载的完整原全局值展开/收起、Tab到末端和明确原文重试。完整值包括保留的两包启用、仓库、构建和产物身份及额外仓库空列表；卸载对象与已更新当前列表分开。默认DOM摘要省略长分组正文，精确文本/离屏字段定位未命中，另保存实际未隐藏的ARIA标签并核对全部内容，同一内置浏览器AX滚回操作区；不是产品缺字段，也未改用其它浏览器或外推真实读屏。

双主题有效ACK后读取503均明确显示“已确认”，原安装对象及读取阶段在书架、源目录和扩展重开后保持；故障下明确重试仍读取，解除故障后由用户明确恢复并清除原操作。浅色→深色先保留未保存草稿的浅色画布，确认保存后才应用深色；深色另完成正常已确认卸载及返回列表。等待时重复点击安装没有新增请求，但DOM未报告aria-disabled，只据此确认功能阻止重复，禁用辅助语义仍待验。准备阶段实际未截到，不能把已进入保存的`extension-install-start-light`计作准备图。

首次人工`hold-confirm`的sequence14没有客户端终态，原记录与未知安装画面保留，不能计正常释放或追补终态。该安装明确重试前后完整快照相同，重试复用原UUID/CAS/正文且不重复应用；后续等待改用既有两秒自动确认，正常交付真实200 ACK。此人工中断与受控502/503分别记录，不将harness正常退出或后续成功当作其原交付完成。

`verify-extension-recovery-formal.ts`使用生成ProtoJSON模型、静态清单、实际HTTP清单、DOM/ARIA和JPEG尺寸核对22组六路完整快照（132份响应）、14个完全相等区间及113条连续审计；112条有客户端终态，只有上述sequence14无终态。13条POST逐字核对为两次独立准备、八条UI原操作（含一次主题保存）与三次相同UUID/CAS/正文重试。八条原操作各应用一次，三次重试零重复，有效确认后读取/重开/恢复零额外POST；八次读取503与两次已提交后502单列。最终账户10、全局9/DARK、安装选择三包、收藏源一项；书架作品始终revision1且已收藏，无分类关联/书签/进度/续读/自定义封面，资料、目录及其它设置保持。审计不包含Source运行时等所有网络请求；本轮没有主动打开或执行Source，不提升任何包的运行兼容层级。

41张360×800 JPEG及对应DOM、两份完整ARIA已实看核对；校验日志和收据为`2512c51-extension-recovery-evidence-check.log`及`karuyomi-2512c51-extension-recovery-formal-evidence-receipt.json`。五个证据/计数工具严格类型通过；控制台最终错误/警告为空，确认清除后的再次重开正常。结束后导航空白页、恢复默认视口、关闭临时标签并确认列表为空；harness明确stop正常退出0。新增07.K8、08.K7/K8三对及09.K5深色，使跨版本主图122→126/169（74.6%），单侧8、双侧均缺35，独立计数见`extension-recovery-state-coverage-count.json`，剩余43个主状态及全部变体/转换/最终产物。08.K6、仓库正式恢复、真实CAS/身份、Mihon参考和最终像素门仍待，没有Native或生产增量；PR #8仍草稿、未合并、未部署。

### 已确认原值标题的残留修正

上述正式批次没有展开已确认操作的原值。提交前源码复核发现，共享内容标题仍固定为“未确认的原全局设置内容”，与已确认的外层提示矛盾；既有双主题恢复流程加入展开与不出现“未确认”的阶段约束，两项均先失败，见`confirmed-global-heading-red.log`。标题现改为中性的“原全局设置内容”，外层仍按有效ACK区分读取恢复与未知写入，不增加状态分支或改变请求。五文件134项扩展、仓库、源收藏及设置UI回归通过，见`confirmed-global-heading-targeted.log`；两文件严格分析和官方生成一致性通过，日志使用`confirmed-global-heading-`前缀。新完整CI见[PR #8检查](https://github.com/Wybxc/karuyomi/pull/8/checks)，中性标题的新正式Web复验仍待，不把组件通过追溯为上述正式产物已显示新标题，也不增加126/169计数。

## 仓库预览目标与保存后的读取阶段

2026-11-18，继续仓库10.K4/K7/K9前，挂起公开目录读取和真实设置确认的组件流程复现三类缺口：预览阶段没有明确名称和完整地址，首次添加提交在确认返回前丢失原对象，有效确认后的目录刷新仍显示等待写入；原设置重试等待期间也提前出现结果未知指引。浅/深色及普通/双倍字号的十二项仓库流程，加两项既有扩展重试流程，十四项均先失败，见`repository-operation-phase-red.log`。

仓库操作现在仅在当前会话操作期间保留名称与规范化目录地址，用官方Cupertino分组呈现完整文本；预览单独标识为只读，不创建账户草稿、不安装扩展。确认成功后的本机/目录刷新切到读取阶段，扩展安装、启停、卸载及原操作重试沿用同样的阶段约束。未知结果指引只在操作结束后出现，冻结原对象和完整提交值继续保留，身份退役、取消及释放仍按原生命周期执行。

十四项定向流程转绿，相关五文件136项回归及四文件严格分析通过；对应日志为`repository-operation-phase-green.log`、`repository-operation-phase-regressions.log`与`repository-operation-phase-analyze.log`。测试核对只读预览/取消零POST、首次提交确认前已保存列表不变、目录读取期间仅一次业务应用，以及重试复用原UUID/正文且零重复应用。内置浏览器新建空白标签、导航和DOM控制已成功返回，标签随后关闭；这仅证明控制恢复。新提交完整CI和正式Web双主题仍待，本节不增加126/169（74.6%），不替代10.K4/K7/K9主图或新增Source运行、Native、生产证据。

## 仓库预览与操作恢复的正式 Web 双主题验收

2026-11-18，客户端及夹具`270db05b7255916afbe731da87876fae1d0cf166`的[push CI](https://github.com/Wybxc/karuyomi/actions/runs/44204033012)、[PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44204042858)、正式Web与push Wasm全部通过，部署跳过。归档`14383695791`在下载边界核对`16304689`字节和GitHub摘要，再校验39条资源并仅复制生成产物；官方API及acceptance Vite装配后，实际HTTP清单35条与CI一致，入口`main.dart.95487273.js`。下载未完成时的首次装配在读取缺失清单处退出、没有替换产物，日志保留；完成下载校验后才成功装配，没有本地完整Flutter或AOT构建。

正式环境为官方Wrangler临时D1/R2、`acceptance-owner`、四包静态快照与内置浏览器360×800，应用地址`127.0.0.1:55379`。两次独立API准备为两个其它安装选择、保留但未安装的英文xkcd收藏源和一部书架收藏。公开空仓库另用官方harness提供五秒有界响应，实际延迟约5013ms、ProtoJSON目录解析与CORS通过；无业务绑定、不允许POST。项目锁定的workerd最高支持2026-11-08，首次使用当天日期启动失败的日志单独保留，改用受支持日期并重新生成类型；该夹具不是生产仓库或Source运行证据。

双主题实看只读预览、取消、明确添加等待与成功后的目录读取，完整名称和目录地址均保留。移除丢确认后，当前列表经只读刷新移除仓库，原对象仍在；书架/源/扩展往返后原对象继续保留，明确重试复用原请求。原请求重试等待时显示保存阶段，不再提前显示结果未知指引。另核对两主题有效ACK后读取503、故障下明确只读重试、展开中性“原全局设置内容”、真实Tab到完整值末端、收起及解除故障后的明确读取恢复；没有重复发送已确认写入。浅色主题草稿在明确保存前不改变画布，确认后才进入深色。最终确认清除、书架保留与再次重开正常，控制台错误/警告为空。

`verify-repository-phases-formal.ts`通过生成模型核对23组六路完整快照（138份响应）、13个完全相等区间及114条连续终态审计，收据为`karuyomi-270db05-repository-phases-formal-evidence-receipt.json`。13条POST逐字核对为两次准备、九次UI原操作（四次添加、四次移除、一次主题保存）和两次相同UUID/CAS/正文重试；九次各应用一次，重试零重复，已确认读取恢复零额外POST。最终账户11、全局10/DARK、额外仓库空列表；两个安装选择、收藏源、书架作品revision1、资料和其它设置均保持，无分类关联、书签、进度、续读或自定义封面。

五次读取503中，一次来自独立快照命令在故障仍开启时的失败探测；该命令未产出完整快照，失败日志与审计保留。其余四次为两主题确认后的首次读取与明确重试；两次已提交后502单列。故障解除后取得完整快照，此时界面仍保留失败与原操作，直到明确读取恢复。40张JPEG/DOM与两份完整ARIA分别保留：首次列表转场、预览退出中的叠影、已进入确认框的错过时刻、一次快速输入提交后的校验失败及深色读取/失败异步时刻不作对应主图；稳定主图另存。五秒预览期间的一次选择器等待超时后实际确认框已出现，不记为浏览器连接失败。不会用文件名代替画面时刻。

证据校验和严格类型通过；结束后导航空白页、恢复默认视口、关闭临时标签并确认列表为空，应用与公开仓库两个harness均正常退出0。新增10.K4/K7/K9三对，使跨版本双主题主图126→129/169（76.3%），单侧8、双侧均缺32；计数见`repository-phases-state-coverage-count.json`。40个主状态、全部变体/转换、真实CAS/身份、禁用辅助语义、Mihon参考和最终像素门仍待；没有新增Source运行兼容、Native或生产证据，PR #8保持草稿、未合并、未部署。

## Source 偏好的原提交值与确认读取

2026-11-18，在 Source 偏好恢复面复现两类缺口。原保存请求只显示条目数，无法查看原提交值。收到有效服务端确认后若整包读取失败，界面仍称写入结果未知，显式重试再次 POST。四项定向流程验证了失败现象，日志为`source-preferences-confirmed-read-red.log`。

恢复面采用 Cupertino 分组显示原漫画源、语言及基线版本，展开可核对完整原同步值。写入等待、有效确认后的读取和结果未知各有对应提示。业务客户端留存已校验确认，重新读取必须满足确认版本。相同版本下不一致的回读数据不能进入缓存。确认仍未知时保留原 UUID、版本和正文，明确重试不会重复执行 Source 回调。已确认但读取失败时，关闭再进入仍可仅重试读取。

六文件111项 Flutter 回归通过，覆盖丢确认重放、读回失败后只读恢复、窄屏双倍字号下重开、旧确认遇到远端新值、错误 ACK 以及失效隔离。六文件严格分析和官方生成一致性通过。隔离 Workers 夹具增加默认仓库 Source 偏好范围，使用真实 D1 写入与正式确认，可延迟读取、丢确认及确认后只失败整包读取。70 项相关 Workers 回归和 API 严格类型通过。

## Source 偏好读取与恢复的正式 Web 双主题验收

2026-11-18，客户端和 Wrangler `editor-ui` 夹具均使用 `92d4f93`。实际交付的 35 条清单与 CI 产物一致。分支和 PR 检查通过，分支 Web、Wasm 构建通过。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44214301563) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44214315490)

内置浏览器使用 360×800 视口，连接临时 D1/R2 中的 `acceptance-owner` 和四包静态目录。用原 Komiic 扩展加载实际热门列表，再操作 Source 偏好。浅色和深色均验证了以下流程。

- 整包设置读取时显示 Komiic、语言与等待反馈。点击关闭回到热门列表。同一账户的在途 GET 可继续完成。
- 选择「僅顯示章節」保存，Worker 提交后夹具给浏览器返回 502。关闭重开后仍可核对原 Source、基线版本、`CHAPTER_FILTER=chapter` 与 `preferred_mirror=1`。明确重试逐字复用原 UUID、基线版本及正文，账户版本只增加一次。等待期间显示正在保存，随后表单读回预期选项。
- 保存「同時顯示卷和章節」收到有效确认后，夹具令整包读取返回 503。关闭重开能展开原值。故障期间可明确尝试只读恢复，解除故障后再次点「重试读取最新设置」，读回两项设置。此分支共六次 503，只有最初两次保存产生 POST。

新的独立 Web 文档先遇到原标签占用 Source 运行槽。原标签退出 Source 后仍占用，关闭原标签后点击「重试」，实际重新加载 Komiic 热门并读回 `komiic.cc` 与「同時顯示卷和章節」。回到表单时两个单选项的选中值各出现两次。另一个缺口是运行槽提示与「重试」合并为一个可访问性节点，验收时对该节点发出 Enter 未激活重试，鼠标点击生效。

`verify-source-preferences-formal.ts` 使用生成的 ProtoJSON 模型核对 17 组七路完整快照、10 个完全相等区间及 137 条连续终态审计。11 条 POST 包括三次准备、六次界面原操作（四次 Source 保存和两次显式主题保存）及两次精确重试。最终账户版本 9、全局设置版本 3 且为浅色、Source 设置版本 5。收藏源、书架作品、分类、进度、书签及其余设置保持原值。证据与严格类型校验通过，收据为 `karuyomi-92d4f93-source-preferences-formal-evidence-receipt.json`。

本轮取得 31 张 JPEG 及对应 DOM。浅色三张进入转场，以及独立文档首张 1280×720 图只作辅助。双主题稳定读取及展开原保存请求补齐 14.K1/K5，跨版本主图从 129 增至 131/169（77.5%）。14.K4 另保留双主题账户保存等待的补图。最终控制台错误与警告为空，临时标签已关闭、视口恢复，隔离服务正常退出。

同字段的历史布局测量见 `source-text-dialog-layout-reference.json`。Mihon 的 `s1404-source-text-empty-{light,dark}` 与 Web `a12c779` 均为 MangaDex 的「Block groups by UUID」空输入。Mihon 面板为约 310×174.5 逻辑像素，历史 Web 的 Cupertino 面板约 270×156。Mihon 有 Android 输入法，Web 使用桌面输入，纵向位置和 JPEG 色值仅作环境内对照。

该轮后尚缺 38 个双主题主状态。此次业务验证限隔离 Web 下的 Komiic 偏好与热门。

## Source 单选值与运行槽重试

单选项的摘要恰好等于选中标签时只显示一次标签，继续显示同步范围。不同的 Source 摘要照常显示。运行槽冲突、读取失败等反馈中的说明与操作使用独立语义节点，「重试」可直接聚焦并用 Enter 激活。

三项组件流程先复现后通过。浅色与深色核对一次选中标签、不同帮助文本、实际改选和单次同步写入。运行槽测试核对独立按钮语义、Enter 触发再次准备及恢复热门。七文件 112 项定向回归和四文件分析通过。

正式 Web 复验使用 `dc6e3c9` 的 CI 客户端和 Wrangler 夹具，交付清单 35 条与 CI 一致。内置浏览器 360×800 的两种主题中，Komiic 镜像与章节显示的选中值各出现一次，同步范围仍可读。浅色的首次进入帧以 `controls-choices-entering-light` 单列，两主题的稳定图在标题到 y=73.5 后保存。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44234973920) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44234979205)

深色第二个标签实际遇到运行槽占用。错误说明与「重试」为独立节点。退出源并关闭第一个标签后，两次 Tab 聚焦「重试」，Enter 恢复 Komiic 实际热门，再打开设置读回 `komiic.cc` 和「同時顯示卷和章節」。焦点轮廓可见，卡片下缘有局部裁切，留待布局修正。

四组七路快照、两个完全相等区间和 43 条终态审计通过。四次 POST 包括三次准备和一次显式主题保存，重试与读回零额外写入。六张 360×800 JPEG/DOM 和一份键盘聚焦 AX 记录由 `verify-source-controls-formal.ts` 核对，收据为 `karuyomi-dc6e3c9-source-preferences-formal-controls-receipt.json`。控制台错误与警告为空，标签和夹具已关闭、视口已恢复。此轮复验完善已有状态的证据，未新增主图状态。

后续保留官方 Cupertino 焦点轮廓，取消错误分组对其外沿的裁剪。运行槽重试组件回归先复现默认 `Clip.hardEdge`，修正后独立语义、焦点与 Enter 恢复流程仍通过，三文件共 63 项回归和两文件分析通过。新版正式 Web 焦点画面待对照。

## 扩展准备的正式验收入口

独立 Wrangler 验收夹具新增 `extension-manifest` 控制范围。五秒延迟作用于同源标准清单 GET，释放后由真实 Static Assets 返回。取消后不会迟发到静态绑定。Workers Vitest 核对普通资源和带查询清单不受控制、释放后返回一致、取消后未转发。验收 Vite 首次生成出现重复路由，改为只提供新增路由，由官方插件与基线配置合并，构建通过。生产入口与配置保持原来的静态资源路由。08.K6 正式主图继续待验。

`fcf3632` 的分支和 PR CI 通过，分支 Web/Wasm 产物通过。用正式 Vite 和 Wrangler 交付，HTTP 清单 35 条与 CI 一致。xkcd 清单在延迟模式用时 5055ms，带查询的同一清单与索引分别用时 17ms 和 16ms，字节与快照一致。审计仅有一条最终为 200 的清单 GET，验收服务已正常退出。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44239122585) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44239126674)

上一个浏览器现场使用 `dc6e3c9` 的扩展客户端和 `fcf3632` 夹具，浅色实拍取得准备、取消落点和本机副本检查。取消后界面仍显示可安装。会话重建后原隔离服务端口已关闭，终态审计未取得，深色尚未执行。四次内置浏览器控制调用超时，其中用户确认面板已显示后仍有请求被桌面归属校验拒绝。当前聊天的面板路由已正确显示，控制会话仍保留临时聊天身份。浅色图保留供诊断，08.K6、11.K1 和新版焦点实拍继续待验。

## 本机存储检查的状态收敛

浅色现场的 `karuyomi-dc6e3c9-extension-preparation-storage-storage-checking-light.jpg` 同时出现两个读取指示，忙碌时重读仍显示操作蓝色。现由存储摘要独立显示首次检查，只有正在读取时显示指示。未读取的空快照有明确标签，重读使用全宽 Cupertino 按钮继承系统禁用颜色和可用状态。

360×800 浅深色组件用例先复现双指示，再核对一次进度、空快照、禁用颜色和真实点击读回。三个文件共 99 项回归通过，两文件分析通过，读取过程未写账户。新 Web 双主题与真实清理恢复仍待验收，跨版本主图计数维持 132/169（78.1%）。

## 扩展准备与本机副本清理

扩展列表的准备面板固定在滚动区域外，显示正在准备的扩展名称和版本。点击取消后显示取消中，直到准备流程退出并收到运行时取消确认。先收到准备结果的用例核对了账户仍未安装、按钮仍禁用，确认后恢复操作。

本机副本清理使用同一组 Cupertino 控件显示目标、SHA-256 和失败原因。副本被其它窗口占用时提示释放占用。重新读取后仍能按原 SHA-256 重试。更新及卸载在账户确认后清理原副本，回归用例核对卸载后的运行时关闭失败、原副本恢复及零额外账户写入。

360×800 浅深色的四项新用例先复现缺口再通过，扩展、跨源搜索及 Source 入口共 155 项定向回归通过，四文件分析通过。内置浏览器控制再次超时，按用户选择继续在当前桌面会话工作。08.K6、11.K3 和 11.K5 的正式 Web 主图与终态审计待验，跨版本双主题覆盖为 132/169（78.1%）。

## 跨源搜索空态直达扩展管理

搜索无可选漫画源时提供「打开扩展管理」。点击后等待原有搜索资源关闭，再由浏览页确认当前身份并切到现有扩展分段。筛选无结果时显示筛选提示，安装入口仅用于无可选源的场景。

两主题均通过 360×800 的浏览入口组件回归。从无扩展安装的隔离账户进入搜索，点击后退出搜索并进入扩展管理，零账户写入、零 Source 打开。测试允许真实事件循环完成订阅释放，正常返回与清理失败继续使用原有关闭路径。相关 110 项回归和三文件分析通过。15.K2 正式 Web 双主题主图待验。

## 扩展与选源的正式 Web 双主题验收

2026-11-18，`a8997fa` 的分支与 PR CI 通过，含 Web 及分支 Wasm 构建。Web 归档 16,307,243 字节，下载时核对 GitHub SHA-256 `5babe1496f425e789c6979464dacf50de5ed1d31f6f3e9c0fcfe03b2ab4ce62d`。核验 39 条 Flutter 归档资源后，用官方 Vite 配置和现有四扩展快照组装，实际 HTTP 清单 35 条和入口 `main.dart.63a65d27.js` 与 CI 对齐。服务使用临时 D1 和 `acceptance-owner`。无需本机 Flutter 或 AOT 构建。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44248539301) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44248545552)

当前桌面会话的内置浏览器恢复连接。360×800 两主题实际核对无可选源的原因、刷新和打开扩展管理的落点。安装前以 `editor delay-read extension-manifest` 取得 xkcd 1.6.1 准备主图，实际取消后仍可安装。首次进入存储时以 `editor delay-read global` 观察到单一进度指示、清理作用范围和重读的禁用色，随后读回零副本。[隔离夹具命令](../../apps/api/test/README.md#api-验证)

明示安装一次 xkcd 后，两次打开英文 Source 获得真实热门和运行槽。另一个标签清理时显示 xkcd、原 SHA-256 和占用原因，重读后仍能重试同一副本。深色仅返回浏览后仍占用，两主题均在关闭占用标签后重试成功，显示零副本。浅色另以 Tab 聚焦占用时的 Source 重试按钮，焦点轮廓完整。清理进行中的 11.K3 与深色焦点仍待验收。

八张主图及 DOM 已逐一核对。五组独立账户读取逐字节一致，70 条连续审计有 69 条终态。序号 13 的人工挂起读取缺终态，该次错过的画面单列排除。另排除深色选源转场与误读占用标签的中间截图，均重新采集到正确状态。两条延迟清单实际返回 200，取消和账户未写入由界面及独立读回核对。三次 POST 分别为深色保存、一次安装、浅色保存，最终账户与全局 revision 均为 3，仍安装同一 xkcd。正常关闭临时标签及验收服务。08.K6、11.K1/K5、15.K2 对应四对主图，跨版本覆盖增至 136/169（80.5%）。

## 跨源搜索的停止、清理与打开反馈

停止正在确认或确认失败时，搜索、翻页和打开作品等待原停止恢复。退出清理失败后重试继续原退出，保留返回或打开扩展管理的目的。作品打开期间在结果滚动区上方显示目标名称和来源，从开始释放旧搜索资源到取得详情均保留原查询和结果。

正式实拍还发现存储失败组与用量摘要紧贴，选源空态仍可触发无效搜索。存储采用一致内缩与组间距，选源空态禁用提交并保留刷新及安装入口。组件和控制器用例覆盖同一停止、原退出目的、后台切换、窄屏大字号及组间距。上述改动的正式 Web 画面继续待验。

## 连接状态与跨源详情的正式 Web 复验

2026-11-18 至 19，在系统临时目录从 `0a28f6a` 的 CI 归档组装隔离验收服务。归档 16,307,527 字节，SHA-256 为 `a6d36846d1cc6e369fde320e2c0ea650750528ac579ba0e19fa4a638d0731056`。核对归档 39 条 Flutter 资源，HTTP 实际交付 35 条清单记录，入口为 `main.dart.5d2fe532.js`。复用现有四扩展快照，使用官方 Vite、Wrangler harness 与临时 D1，验收身份为 `acceptance-owner`。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44276175058) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44276183226)

内置浏览器 360×800 的实际系统浅色补齐 27.K2–K4。等待有旋转指示，旧账号收起。401 和 403 分别显示重新登录和访问拒绝，恢复普通响应后明确连接读回原身份。深色主图沿用 `19c2260` 的真实系统深色证据。未配置地址、连接时的草稿和生产认证仍待验收。[连接旧版证据](#连接状态的正式-web-复验)

Komiic 经明确安装并选择 `komiic.cc`。用同一查询「航海王」实得三项。通过 `editor delay-read global` 延长打开详情前的读取，15.K14 两主题均显示顶部目标《ONE PIECE航海王》及来源，保留原查询、三项结果和禁用外观。早期深色首次打开及解除延迟后的重试均失败。同一作品从普通源页能打开。两主题各在新文档完成跨源打开及返回，作者为尾田榮一郎，详情显示 238 章，返回后仍有原查询与三项结果。浅色首次查询超时后只重试该源。深色键盘停止直接观察到「已停止」，15.K10 的待确认帧未取得。

另复验两主题的选源空态及真实双标签占用清理。空态可刷新或进入扩展，搜索按钮呈禁用外观。两个存储分组同边对齐且留有间距。占用时重读保留 Komiic 的同一 SHA-256，关闭占用标签后重试，副本数读回为零。独立读取确认仍安装原构建。深色 Source 重试的 Tab 焦点轮廓完整。11.K3 清理过程仍待截取。

核对了 16 张画面与对应 DOM，以及七组逐字节相同的账户快照。133 条审计均有客户端终态，其中两条 401/403 由夹具直接返回。五次 POST 为三次主动主题保存、一次安装和一次镜像偏好，最终账户 revision 5、全局 revision 4。临时标签已关闭，服务正常退出。27.K2–K4 的浅色和 15.K14 的双主题已补齐，跨版本覆盖为 140/169（82.8%）。

实拍发现 Web 无障碍树把不可操作的搜索按钮报告为可用。现为提交及打开过程中的结果按钮显式提供启用语义，并用 Cupertino 禁用字色区分提交。跨源打开保留底层已整理的具体失败原因，身份失效时仍按原边界退出。六项回归先失败再通过，扩展与相邻 Source 流程共 162 项定向回归通过。新改动的正式 Web 无障碍复验继续待验。

## 迁移打开目标源的正式 Web 双主题验收

2026-11-18，使用 `92d4f93` 的 CI Web 和官方 Wrangler 隔离夹具，实际交付清单 35 条与 CI 一致。迁移页面和控制器未受下一次 Source 控件修复影响。内置浏览器在 360×800 视口从书架 xkcd 打开迁移，选择仅复制收藏和分类，再选 Komiic 作为目标。

两主题分别制造整包偏好读取 503 和五秒延迟。失败仍显示原作品与未选目标，允许重新选择。重试等待主图显示目标 Komiic、语言、spinner、原作品 xkcd 及禁用的选择和刷新入口。成功后选中目标并出现「查找目标作品」。验收停在打开源与待查找状态。

四组六路完整快照、两个完全相等区间及 32 条连续终态审计通过。两次受控读取 503 后的重试各完成一次读取。三次 POST 是两次准备和一次显式主题保存，迁移流程零业务写入。七张 JPEG 与 DOM 保留，`karuyomi-92d4f93-migration-open-evidence-receipt.json` 可核对。两主题的稳定等待图补齐 20.K8，跨版本双主题主图升至 132/169（78.1%）。控制台错误与警告为空，临时标签与验收服务已关闭。

## 禁用语义与编辑身份失效的正式 Web 复验

2026-11-19，`b29c3bb` 的分支和 PR CI 均通过，分支含 Wasm。Web 归档在传输边界核对 16,307,633 字节和 SHA-256 `df64b47adc9b0c91462e4cbcee504170b9a6c2a95545350714ccbe2af99925b2`。复验归档内 39 条 Flutter 资源后，官方 Vite 和 Wrangler 隔离服务实际交付 35 条同清单记录，入口 `main.dart.3e408515.js`。服务使用临时 D1、`acceptance-owner` 与既有四扩展快照。内置浏览器视口为 360×800。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44357887206) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44357901798)

零安装账户的跨源搜索中，搜索提交实际报告 `aria-disabled="true"`，刷新和打开扩展管理仍可操作。从该入口进入扩展分段，安装 xkcd 1.6.1 后成功打开英文热门和详情。正式 Web 的已选源与打开作品期间的无障碍语义继续待验。

| 状态   | 实际触发与观察                                                                                                                                                        |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 05.K11 | 新分类原请求一次应用后交付 502。精确重试保留原正文，受控 401 时冻结原分类名、灰显重试并可关闭。恢复夹具响应后在旧按钮按 Enter，没有第三次请求，关闭两层窗口回到书架。 |
| 19.K11 | 首次读取原封面时受控 401，窗口停用，内容只保留身份变化说明及关闭。                                                                                                    |
| 21.K6  | 英文 xkcd 到中文 xkcd 的收藏与分类迁移已取得真实预览，再次只读预览时受控 401。旧动作撤去、返回仍可用，整段没有迁移 POST。                                             |
| 24.K11 | 真实打开 `3323: Meteor Fear` 后进入本漫画阅读设置。已确认的继承值只读重取遇受控 401 时撤下字段和保存，显示连接要求，仍可关闭并返回原章节。                            |

87 条审计均有客户端终态。四条 401 由夹具在 Worker 业务处理前返回。六次 POST 含一次扩展安装、一次收藏、两次进入阅读器时自动保存进度，以及首次分类创建和被 401 拒绝的精确重试。五组七路状态读回中，漫画设置重读前后、分类重试前后各七条响应逐字节一致。账户最终 revision 为 5。没有生产认证请求。临时标签已关闭、视口已恢复、隔离服务正常退出。[夹具命令](../../apps/api/test/README.md#api-验证)

独立读回确认初始主题为跟随系统。七张 JPEG 经逐张核对均以系统深色渲染，原暂定浅色标签已纠正，截图 ID 为 `karuyomi-b29c3bb-*-system-dark`。本轮补充了深色分项，05.K11、19.K11、21.K6、24.K11 的浅色仍待，跨版本双主题覆盖保持 **140/169（82.8%）**。检查当前 AppShell，身份不可用时主题随系统，账户主题须经服务端确认才应用。[主题入口](../../apps/reader/lib/main.dart)

实拍中的漫画设置重读和分类重试灰显，无障碍树仍报告操作可用。失效分类管理的新建入口和连接等待处有同类语义缺口。现为这些操作显式传递与回调一致的启用语义，禁用时的登录及新建分类使用 Cupertino 禁用字色。对应回归先复现再通过，设置、分类与搜索共 131 项通过，六文件分析通过。新修复继续等对应正式 Web 产物复验。

## 选图等待的正式 Web 双主题验收

2026-11-19，`1d29865` 分支及 PR CI 通过。正式 Web 归档校验 16,307,752 字节与 SHA-256 `ed099fe18f8f469ca347778d681ce1a457a35831fe6c602ab56e4fe6a900b497`。官方 Vite 与 Wrangler 隔离服务复用四扩展快照和临时 D1，归档 39 条 Flutter 资源校验通过，HTTP 清单的 35 条与 CI 对齐，入口为 `main.dart.907d13a3.js`。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44364644438) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44364657905)

内置浏览器的系统外观为深色。连接等待时，连接和登录均实际报告 `aria-disabled="true"`；释放 bootstrap 后回复 200，身份与两项动作一起恢复。隔离账户收藏英文 xkcd 后，通过正式 multipart API 预置仓库图标作为一次性封面。同一已确认封面在系统深色和服务端确认浅色分别打开文件选择器。两张稳定的 360×800 画面都保留原封面、旋转指示及灰显的关闭、替换和清除。深色在等待中按 Enter 未清除。选图测试结束时关闭临时文档；手动系统对话框取消仍待复验。排除一次在窄屏调整期间截到的缩放帧，采用从固定窄屏新文档重取的浅色图。

独立读回证实封面 revision 仍为 2、描述与原回执相同，图片长度及 SHA-256 相同。68 条审计有客户端终态。三条 POST 为一次安装、收藏和主题设置，另有审计范围之外的一次 API 封面预置。账户最终 revision 为 4；正式账户设置仍为浅色。此版本的封面读取遇受控 401，实际从已确认浅色回到系统深色，旧动作收起，关闭后回到原作品的登录提示。

19.K5 的同数据画面 `karuyomi-1d29865-cover-picking-confirmed-light-fixed.jpg` 与 `karuyomi-1d29865-cover-picking-system-dark.jpg` 补齐主图，跨版本覆盖为 **141/169（83.4%）**。选图期间三项灰显动作的辅助技术报告仍为可用，作为另行修正的实拍发现。[故障夹具](../../apps/api/test/README.md#api-验证)

封面编辑随后为关闭、选择或替换、清除同步传递启用语义。浅色、深色各测 1x 和 2x，四项回归先复现语义缺失，再验证首次选图、替换等待及选择器返回空值。取消后原封面和作品 revision 保留，三项操作恢复可用。设置与相邻编辑等 167 项定向回归及两文件 Dart 分析通过，新语义待正式 Web 复验。

## Access 暂停时延续已确认主题

2026-11-19，在 360×800 的实际 AppShell 组件流程中，先保存与系统相反的主题，再让只读设置请求返回 Access 失效或拒绝。两项回归先复现旧行为。收到 401 后确认浅色变为系统深色，收到 403 后确认深色变为系统浅色。

应用现在在原会话暂停期间沿用服务端已确认的全局配色。旧设置字段仍按身份状态收起。重新连接并切换账号后，新账号的设置读取即使也遭拒绝，界面按系统配色绘制，随后重连只接收该账号的当前设置。每个回归只有一次显式保存主题，草稿阶段仍保持先前配色。

设置、封面、分类、迁移与跨源搜索共 167 项定向回归通过，两个改动 Dart 文件分析通过。正式 Web 的双主题身份失效画面与真实 Access 待验，主状态计数沿用正式实拍。[暂停时主题设计](../design/mihon-cupertino-fidelity.md)

## 身份失效的正式 Web 浅色复验

2026-11-19，`138ccbd` 分支检查和 Wasm 均通过。Web 归档在传输时核对 16,307,823 字节与 SHA-256 `3da9ff6a3efe6ea954e43a9d5ff5bd0f01f73cc97b25ab3ee794c6e8b01695a4`。归档 39 条 Flutter 资源校验，隔离 Wrangler 的 HTTP 清单与 35 条公开记录一致，入口 `main.dart.04f37c39.js`。PR 的首次运行在下载固定 Maven formatter 时返回 404，已重跑该作业。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44366949167) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44366963323)

内置浏览器报告系统深色。360×800 内先通过正式设置保存浅色，独立读回 `APP_THEME_LIGHT`，随后从相同隔离账户的真实 xkcd 触发下列 401。四张主图逐张核对均为浅色，深色沿用 `b29c3bb` 的同阶段实拍。稳定画面标识见[逐状态清单](mihon-state-coverage.md)。

| 状态   | 本轮正式证据                                                                                                |
| ------ | ----------------------------------------------------------------------------------------------------------- |
| 05.K11 | 创建后交付 502，重试同一请求遇 401。冻结名称，重试与上层新建均报告禁用，两层窗口可关闭。                    |
| 19.K11 | 首次读取封面失效，撤下选择、替换和清除，保留身份说明及关闭。                                                |
| 21.K6  | 英文至中文 xkcd 的收藏和分类预览只读重取遇 401。失效后只保留说明及返回，无迁移 POST。                       |
| 24.K11 | `3323: Meteor Fear` 第 1 页已确认保存。漫画设置只读重取失效后隐藏旧字段和保存，重读报告禁用，可返回原章节。 |

101 条审计均有客户端终态，五条夹具 401 包括两次迁移预览重读。六条 POST 为设置主题、安装、收藏、保存进度、分类首次应用与被拒绝的精确重试。最后两次分类请求正文逐字节相同。漫画设置和分类重试分别有一次前后七路完全相同的独立读回，共四组 28 条响应；最终账户 revision 为 5。临时标签、视口与隔离服务均已收尾。合并选图等待的双主题，跨版本主状态覆盖为 **145/169（85.8%）**。

迁移旧滚动位置曾在切换后的首帧遮住提示上沿。两次候选转场帧单列，采用第二次拍摄的稳定浅色画面，标题、身份说明和返回完整。随后让退役页面首次绘制即使用新滚动位置。360×640 组件回归从已滚动的实际预览触发 Access 暂停，首帧校验提示位于导航下方，保存命令数一致。该回归先失败再通过，正式新产物的首帧复验待办。其余触发阶段、文字及输入变体和生产 Access 继续分别验收。

## 编辑复验与批量窗口失效

2026-11-19，`1ef627b` 的正式 Web 用 16,307,884 字节的 CI 归档复验。归档 SHA-256 为 `5de5c5d6573999aec3b63773cd5039284924a531dd2af149caa2c3da16c6926e`。39 条 Flutter 归档资源均校验，官方 Wrangler 隔离服务交付 35 条相同清单记录和 `main.dart.130383fd.js`，复用四扩展快照。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44372498478) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44372509373)

360×800 内置浏览器使用服务端确认浅色。正式封面选图等待时，关闭、替换图片、清除封面均实际报告 `aria-disabled="true"`。关闭临时测试文档后读回原封面、作品 revision 和图片 SHA-256 一致。单独打开系统选择器后，验收入口无法操作系统取消，仍由关闭测试文档结束。迁移在只读重取收到受控 401 后，首次观测帧已完整显示标题、失效说明和返回，正常返回原作品。收录 `karuyomi-1ef627b-cover-picking-disabled-confirmed-light` 与 `karuyomi-1ef627b-migration-expired-first-observed-light`，状态数沿用之前的成对证据。

同一正式版本用三部预置书目演练批量添加。受控挂起释放首项确认后，第二项返回 401，第三项从未发送。独立读回仅首部增加分类与作品 revision。窗口保留原清单、确认数和未开始数并可退出，但灰显的重试仍被辅助技术报告可用，正文同时提示旧窗口停用及原样重试。这张系统深色候选用于定位问题，04.K8 主图仍待正式修复。

批量窗口退役后现保留原清单、据实区分确认/未确认/未开始与关闭，移除原窗口重试、重读、继续及相关提示。当前窗口仍有效时的精确恢复仍走原业务链。受控第二项失效的测试先复现原文案，再通过修正；原迟到 ACK 回归仍验证不发送剩余项。书架、分类、批量、续接共 72 项通过，两文件 Dart 分析通过。[隔离夹具](../../apps/api/test/README.md#api-验证)

## 批量分类失效的正式 Web 双主题验收

2026-11-19，`5f5d287` 的正式 Web 通过分支与 PR CI，分支 Wasm 通过，部署跳过。CI 归档 16,307,959 字节，SHA-256 为 `4710206f9adccfbf65f5b1c33dbdc5c31a38f8e58db0d5cebbc00a3f3df1ac08`。官方 Wrangler 交付的 35 条清单记录与 39 条已校验 Flutter 资源的发布子集一致，入口为 `main.dart.d60527ae.js`。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44377596526) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44377610827)

360×800 内置浏览器分别用系统深色、应用已确认浅色复验同一三部批量。窗口失效后，两侧均显示 1 部已确认、1 部尚未确认和 1 部未开始，保留原分类提案及三部作品，只提供可用的关闭操作。关闭均返回书架。收录 `karuyomi-5f5d287-batch-expired-dark` 与 `karuyomi-5f5d287-batch-expired-light`。1280×720 浅色重复流程单列为宽屏补充。双主题主图累计 **146/169（86.4%）**。

三轮均在首项实际提交后暂扣回执，放行首项 200 后让次项收到夹具 401。68 条记录全部有客户端终态。13 条 POST 包含四次业务准备、两次独立清除分类关联、一次主题保存和三轮各两条批量请求，第三部从未发送。每轮前后的六路读回确认账户与首部作品 revision 各增加 1，另两部权威作品记录完全相同。切换身份后迟到的回执由组件回归另验。视口已复原，临时标签与验收服务均已关闭。[夹具操作](../../apps/api/test/README.md#api-验证)

## 书架选择栏与批量预览的短屏复验

2026-11-21，复核固定 Mihon 0.21.3 的 04.01 与 04.02 两色原图和 UI 树。720×1600、320dpi 归一为 360×800 后，04.01 顶部取消和单选计数的逻辑范围分别为 `[16,88,40,112)`、`[56,86,68.5,114)`，底部「设置分类」为 `[30.5,728,54.5,752)`。04.02 的取消和确定项在确认面板下部，上缘均为 497.5。Karuyomi 沿用顶部选择状态和底部批量动作的分布，确认清单以 Cupertino Sheet 的顶部取消和确认承接。[逐状态参考](mihon-state-coverage.md)

基准 `21dd837` 的 360×480 正式 Web 在滚到长书架末端后，退出和选中计数离开视口，底部批量动作仍可见。中间实现放在置顶 sliver，竖屏画面可用，改为 844×390 后画面仍在顶部，浏览器却把退出的辅助边界上缘报告为 876。最终 `a899954` 将退出和数量放到书架滚动容器上方，使用同一份筛选结果核对隐藏数量。两色 360×800 初始画面与 360×480 滚动后，退出均为 `[16,44,60,88)`。短竖屏内计数和添加按钮分别为 `[60,54,344,78)`、`[0,365,120,430)`。顶部栏 JPEG 采样浅色为 `#FFFFFF`、深色为 `#000000`。深色再旋转至 844×390，退出边界仍为 `[16,44,60,88)`，计数与底部动作同屏，并从此处用 Enter 实际退出。[书架实现](../../apps/reader/lib/features/library/library_page.dart)

两套正式 Flutter Web release 实际交付的客户端入口与正常构建逐字节相等，入口 SHA-256 为 `50cb8dec97b7cde16e68ddc12376ffe8b7778ac371e98447f6743ec52def6271`。各用隔离 Wrangler 和 D1 预置 25 部作品和两个分类。先在原分类中选一部，再切到未分类选一部并保留原选项。两色滚到末端仍显示「已选 2 部 · 当前隐藏 1 部」。在「移出书架」预览核对两部作品，取消后返回已滚动的书架，恢复原选择。两色取消前后全量分页与账户快照逐字节一致。

对同一范围明确添加分类，浅色用 `editor hold-confirm classification` 暂扣首笔已提交的回执，画面为 0/2 确认、1 部未开始，「稍后处理」禁用。放行后显示 2/2。深色使用 Enter 确认也达到 2/2。最终审计每色各两笔 UI 分类提交且均为 HTTP 200，账户 revision 从 29 到 31。全量分页逐项比对，只有两部原选中作品新增分类，隐藏作品保留原分类。两个新浏览器文档均在该分类读回这两部作品，确认后和新文档读回后的快照逐字节一致。[官方验收入口](../../apps/api/test/README.md)

浅深两色各一项两倍字号回归在基准版因滚动后计数离开视口而失败，最终版检验短竖屏、切换短横屏、退出和零写入均通过。992 项 Flutter 测试、改动文件严格 Dart 分析、正式 Web release 构建、格式和依赖分层检查通过。验收标签和服务已关闭。正式浏览器实拍使用默认文字比例，目标系统大字、触控与原生继续验收。[书架回归](../../apps/reader/test/library/library_batch_page_test.dart)

## 漫画源设置空态的正式 Web 双主题验收

2026-11-19，同一 `5f5d287` CI 客户端使用独立 Wrangler 和完整 Static Assets 快照，Vite 校验 190 个扩展，产物仍含相同的 35 条 Web 清单。英语 Commit Strip 1.6.1 使用清单的未改动 AOT 构建，bundle 编码体为 872,042 字节。这个真实 Source 能打开年份列表且没有额外偏好。英语 xkcd 具有 Organization Method，未用它替代空态。

360×800 下分别核对系统深色、账户确认浅色。空态稳定帧均有源名、无额外设置说明、重新读取和关闭。两种主题都能显式重读后返回空态，关闭回到同一源。43 条审计记录均有客户端终态，两次 POST 分别为安装及主题保存，无 Source 偏好 POST。两组前后四路读回一致。收录 `karuyomi-5f5d287-preferences-empty-light` 与 `karuyomi-5f5d287-preferences-empty-dark`，覆盖达到 **147/169（87.0%）**。有嵌套和空分组的 14.K11 继续待验。

## 章节映射超限的复现

2026-11-19，`1ef627b` 正式 Web 用真实英语、中文 xkcd 清单试验。英语作品的 320 项书签只有 4 项满足唯一匹配，前后独立读回一致。为验收 256 条上限，官方隔离入口提供两份各 257 条的唯一匹配上游响应，仍通过正式扩展、二进制 HTTP 中继和正常 API 预置书签。两次实验均无迁移提交。[上限夹具](../../apps/api/test/README.md#api-验证)

360×800 系统深色实拍选中 257 条时显示错误提示和灰色确认按钮，Web 辅助技术仍将确认报为可用。取消一条后，显示 256／256 及一项不复制，错误消失，可打开明确标注 256 条的二次确认。点击返回检查后，五路权威快照完全一致，257 条书签仍在。已补超限按钮的启停语义与 Cupertino 禁用前景色，21 项迁移测试和 104 项 HTTP 中继、Access 用例通过。20.K18 等待修正后正式双主题验收。

## 章节映射超限的正式 Web 双主题验收

2026-11-19，`78f4c4b` 分支及 PR CI 通过，分支 Wasm 通过，部署跳过。CI 归档 16,307,998 字节，SHA-256 为 `cf292f477b32682beb4d1dff54b52ac020715bb4b850125a216f103941c775a1`。核对 39 条归档资源，官方 Wrangler 实际交付 35 条对应记录，入口为 `main.dart.010d2ace.js`。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44381784668) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44382553139)

360×800 内置浏览器使用系统深色和账户已确认浅色。两份隔离章节上游响应各有 257 条唯一匹配，正式扩展照常解析。两种主题均实拍 257／256 计数、错误红和确认禁用前景，浏览器同时报告 `aria-disabled="true"`。取消首条映射后，警告消失，256／256 计数注明一项不复制，按钮恢复可用。二次确认明确列出 256 条，使用返回检查离开，未提交迁移。

两轮完整操作及第三次深色补拍的前后五路权威快照、全部 257 条书签均逐字相同。英语作品 revision 始终 258，三组账户 revision 分别保持 259、260、261。深色初次滚动截图未完整包含计数和提示，补拍主图后核对可见边界。内置浏览器在本轮短暂超时，恢复后继续原标签，全部临时标签、视口及隔离服务均已收尾。20.K18 的浅深各两图分别核对超限提示与确认区。累计 **148/169（87.6%）**。[章节夹具](../../apps/api/test/README.md#api-验证)

## 跨源停止确认丢失的复现与修正

2026-11-19，通过生产搜索控制器和双执行槽控制协议供应端丢失重置确认。旧版收到真实服务的清理通知时会先退役页面，导致故障组一直显示「正在停止」。修正后只有身份、服务或运行容器失效才退役原会话。单源停止未确认时保留该组的重试动作；未获确认的执行槽不回到空闲池，显式重试等待原资源释放。普通清理失败可从同页重试，仍拦截新的搜索、翻页和打开结果。

新增回归先复现一直等待，再核对首次故障只尝试一次重置、重试原执行槽后才恢复搜索、查询与调用数不变，以及迟到结果不出现。搜索及相邻浏览的 140 项定向回归通过。停止与退出的完整正式 Web 双主题仍待。

## 停止与本机清理的正式 Web 基线

2026-11-19，`78f4c4b` 正式 CI Web 使用隔离 Wrangler、完整已校验扩展快照及浏览器运行时回执夹具。实际 HTTP 交付的 35 条 Flutter 清单记录和加载的原 CI host 与归档一致。夹具在正常执行后暂扣或丢弃匹配的确认，所有业务请求仍取独立服务端权威状态。[复验入口](../../apps/api/test/README.md#api-验证)

360×800 系统深色对英语 Commit Strip 查询「2026」后停止。实际 host 已终止活动请求。受控停止和第一次重置确认丢失后，旧版自动再次重置并收到确认，界面仍停在「正在停止」且无法重试。该轮迟到的是取消错误响应。前后账户安装、书架和分类三路读回一致。

两种主题等待清理同一个 xkcd 本机副本，停留期间显示扩展名、摘要、进度和账户安装保留提示。独立读回及缓存数量确认只清理本机副本。浅色的清理和重读视觉上灰显，Web 辅助技术仍报告可用。两主题组件回归复现缺少禁用状态，改为由执行条件同时驱动按钮行为和禁用语义。旧截图用于问题定位，11.K3 主图等待新正式产物。

## 跨源单源停止的正式 Web 双主题验收

2026-11-19，`392273b` 的正式 Web 分支及 PR CI 通过，分支 Wasm 通过，部署跳过。CI 归档 16,308,580 字节，SHA-256 为 `7ca26b4564cc415d2a7a258fe15ee62a10c618e9e79aba44ca6bb42eab871c0c`。39 条归档资源均校验，隔离 Wrangler 实际交付 35 条记录、`main.dart.852be063.js` 和原 CI host。测试专用脚本控制回执交付。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44389099454) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44389110873)

360×800 的系统深色和账户确认浅色均显式选择英语 Commit Strip 查询「2026」。真实扩展各返回一项，验收脚本暂扣结果。点「停止此源」后，原查询、源名和「正在停止」同屏，提交实际报告 `aria-disabled="true"`。释放迟到的成功响应后保持零项，界面准确进入「停止尚未确认」，新搜索仍禁用，原「重试停止」可用。两次分别核对原请求 ID 和 generation、同一执行槽首个重置确认未交付、显式重试确认交付。停止完成后只有显式点「重试此源」才显示《Commit Strip (2026)》。两组前后账户安装、书架、分类三路相等。15.K10 与 15.K12 双主题通过，覆盖为 **150/169（88.8%）**。[运行时回执复验入口](../../apps/api/test/README.md#api-验证)

同一版本深色另演练返回时的两次重置确认丢失。页面停留，精确重试收到确认后返回原浏览；组状态却仍显示「正在搜索」，「停止全部」的辅助技术状态也不准确。原独立读回先于试验，复验后读回包含后来为浅色验收明确保存的主题。核对两组除主题和对应 revision 外相同。随后在整页清理开始时把活动组标为正在停止，未确认时显示真实状态并由页面提供重试，保留原退出目的。旧图留作故障证据，15.K13 的主图继续等待。

## 本机副本清理的正式 Web 双主题验收

2026-11-19，`ad41606` 正式 Web 分支及 PR CI 通过，分支 Wasm 通过，部署跳过。CI 归档 16,308,668 字节，SHA-256 为 `a76b601e50b8cd4dca84c16749e19ade7ba847f5bdd8028b68f98d16f8c5f653`。校验 39 条归档资源、实际 HTTP 35 条发布清单，入口为 `main.dart.bcf1afba.js`。浏览器的真实运行时 host 与 CI 归档字节一致。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44390887117) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44390897960)

360×800 系统深色和账户确认浅色均清理同一安装的 xkcd 本机副本。真实清除成功后，验收脚本暂扣该摘要的确认 7 秒，页面显示原对象、摘要、旋转指示和保留账户安装说明。两个主题的「清理副本」与「重新读取本机副本」均实际报告 `aria-disabled="true"`。原回执放行后，副本由一份降为零，重读恢复可用。浅色先从保留的安装重新下载同一份。每轮前后的账户、书架和分类三路读回逐字一致，实际调用的清理摘要也相同。补齐 11.K3，跨版本覆盖为 **151/169（89.3%）**。[运行时回执复验入口](../../apps/api/test/README.md#api-验证)

## 跨源退出清理的正式 Web 双主题验收

2026-11-19，`a251191` 分支、PR CI 与分支 Wasm 通过，部署跳过。CI 归档 16,308,939 字节，SHA-256 为 `f18bfd49811eff32e005d7d0ed4963d69eb92cebb6a87ac251f9aef3767a1db7`。归档 39 条资源校验通过，官方 Wrangler 实际交付 35 条对应记录、`main.dart.5b541f68.js` 和字节相同的原 CI host。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44393489669) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44393501920)

在 360×800 内置浏览器中，系统深色与账户确认浅色用同一个 Commit Strip 查询演练返回。真实结果有一项，暂扣后发起返回。在收到确认前，保留查询和源名，显示释放指示和「正在停止」。返回、搜索和停止全部实际禁用。受控丢失首次和关闭中的重置确认后，页面保留原返回目的，显示运行时未确认释放与单一清理重试。搜索和停止全部保持禁用，组状态为「停止尚未确认」，迟到结果未出现在界面。明确重试取得同一执行槽的释放确认后回到浏览页。

深色两次、浅色一次的重置确认交付顺序均为丢失、丢失、交付。两组前后账户、书架及分类三路逐字一致，账户 revision 分别保持 1 与 2。`karuyomi-a251191-search-release-failed-{light,dark}` 收录为 15.K13 正式双主题，等待帧单列为 `search-release-waiting`。已复原视口和关闭临时标签、验收服务。打开扩展管理的原退出目的另有组件证据，身份或 Source 失效触发的资源释放仍待实拍。跨版本主图 **152/169（89.9%）**。[运行时回执复验入口](../../apps/api/test/README.md#api-验证)

## 漫画源筛选过程与恢复的正式 Web 双主题验收

2026-11-19，`a251191` 在 360×800 实拍中复现两处缺口。读取时「应用」「重置」实际无法触发，辅助技术仍报告可用。Komiic 长表单滚到底后，重置提示留在滚动区最上方。读取失败还把说明、错误和重试合并成一个按钮名称。修正后，表单上方保留漫画源、查询与反馈，读取和重置各有独立重试，忙碌字段和按钮暴露真实禁用状态。213 项相关 Flutter 回归、三个 Dart 文件分析、运行时夹具严格类型和全库格式检查通过。

`7461850` 的分支与 PR CI、分支 Wasm 通过，部署跳过。正式归档 16,309,233 字节，SHA-256 为 `e848c9dbe2a833f4317e2b21dabf1b968b3f97ca5a9c119ebcf4285558a7113c`。校验归档 39 个资源、官方 Wrangler 实际交付的 35 条资源、`main.dart.5ff0279b.js` 和原 CI 运行时 host 字节。两个主题使用同一个现有 Komiic 构建，摘要为 `d20bfc19faa55099cd6573ee3769f89e45eb207e497a214cf73ff995eb13a582`。默认镜像请求失败，经正式漫画源设置选用 `komiic.cc` 后取得真实热门。深色跟随系统，浅色由账户确认。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44400283761) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44400299712)

验收夹具把真实筛选描述和带筛选的检索结果暂扣八秒。首次读取时应用和重置均禁用，关闭后可重新读取。选择「愛情」后应用，等待期间原草稿冻结，关闭会发出匹配代次与请求 ID 的取消。取消后，真实的 30 项迟到结果未替换原热门列表。再次明确应用才切到筛选结果。滚到表单末尾发起重置时，两主题均显示顶部进度和关闭后果，应用及可见选项暴露禁用语义；重置请求带原已应用的快照 ID。重置完成拿到默认草稿，取消后原查询标签及可见前八条筛选结果一致。

受控丢失首次描述和重置描述时，分别实拍「重试加载筛选」和「重试重置筛选」。两者均可重试成功并关闭回到原热门列表。实际通过 host 重建容器后，旧面板隐藏字段，只提供可用的关闭动作；回到来源执行重连，再打开筛选取得新代次且未继承旧的「愛情」选择。24 对请求和交付按 ID、代次匹配，四次取消也分别匹配。两次深色演练重接浏览器控制时未取得完整的正常首次读取日志，故未将它们计入审计配对；错误、换代与恢复请求均保留配对。

两组账户设置、书架、分类和漫画源偏好在验收前后逐字一致，账户 revision 分别保持 2 和 3，偏好 revision 均为 1。12 张 360×800 原图覆盖 13.K1、13.K5–K7、13.K9，其中 13.K7 有两种失败。浅色读取主图取自入场末段，所有必要文字可读；完整转场仍待。跨版本双主题主图达 **157/169（92.9%）**。隔离服务及临时标签已关闭，原生、其它筛选字段、扩展兼容和生产仍各有验收门。[逐状态清单](mihon-state-coverage.md) · [夹具复验](../../apps/api/test/README.md#api-验证)

## 迁移目标与分页失败的正式 Web 双主题验收

2026-11-19，`7461850` 的正式 Web 用受控打开失败复现原选择与候选仍在、但下一次读取却因旧会话已经关闭而报错。真实 Komiic 热门第二页到达后暂不交付，列表底部仍显示原候选和加载入口，错误留在视口上方。忙碌时搜索、热门及只读重取也未报告实际禁用。修正后，进度、错误与重试固定在可滚动候选的上方，读取动作报告真实可用性。198 项定向 Flutter 回归、三个 Dart 文件分析和严格桥接类型通过。

`517a73e` 的分支与 PR CI、分支 Wasm 通过，部署跳过。正式 Web 归档 16,310,280 字节，SHA-256 为 `113fb3426831d7a31486499a420d45cca8076227760aa20926a2c4000985ee14`。校验归档 39 个资源及官方 Wrangler 实际交付的 35 条对应记录，入口 `main.dart.3a55acf8.js`，原 runtime host 与归档字节一致。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44409068303) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44409081403)

两个 360×800 主题均从英文 xkcd 的书架入口选择仅收藏和分类，经 Komiic 的真实 `.cc` 镜像取得 30 项热门。输入框改为「未提交的新词」后仍按热门加载第二页。首次真实第二页 30 项由夹具拒绝交付，原候选和可恢复原因同屏。明确重试命中原 Source ID、原 generation 和第 2 页，交付新的 30 项。组件回归另核对搜索追加失败时的原查询及请求页码顺序 `[1, 2, 2]`，Web 实拍使用热门追加。

切换到英文 MangaDex 时注入一次打开失败，原 Komiic 选择和候选保持。明确重试打开原失败构建后取得真实会话。在另一独立文档用同一故障继续浏览原 Komiic，按同一 Source ID 重新打开不同 generation，返回 30 项。共核对 16 条定向运行时记录，两组账户、书架、分类、Komiic 偏好和原作品五路权威读回完全相等，账户 revision 分别保持 5 与 6。四张主图补齐 20.K13 的打开失败与追加失败，主图覆盖达到 158/169（93.5%）。其它搜索分页、失败触发阶段和完整转场继续验收。[正式夹具](../../apps/api/test/README.md#api-验证)

## 漫画源设置分组与禁用色的正式 Web 双主题验收

2026-11-19，`7461850` 的正式 Web 已显示真实 Komiic 设置的受控分组、子组与空分组。父组禁用时镜像选项确实不可用，但其字色仍像可编辑的行。修复后的共享选择控件使用 Cupertino 的 tertiaryLabel 显示禁用标签和当前值，保留长选项的完整换行。157 项相关 Flutter 回归、两个 Dart 文件分析和严格桥接类型通过。

`0e432ce` 的分支、PR CI 及分支 Wasm 通过，部署跳过。正式 Web 归档 16,310,332 字节，SHA-256 为 `35f3db642094d9e4266dea6da941dd1f225f24c435d3f06a89c9455b6ea50f88`。校验归档 39 项资源、正式 Wrangler 实际交付的 35 条记录、`main.dart.32970f6c.js` 及字节相同的原 CI host。内置浏览器报告系统浅色，首轮跟随系统的画面实际为浅色。最终主图使用服务端确认的显式深色及浅色，在面板标题位置稳定后取得，两主题均可见完整分组、禁用文字与独立关闭和重读入口。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44411213359) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44411222236)

分组由验收夹具构造，选项值、原监听器和保存均来自实际 Komiic。镜像行继承父组禁用，两个主题均报告 `aria-disabled="true"`。在独立页面选择章节显示值后，夹具收到客户端嵌套路径 `[0,1,0]`，交给原 Source 的路径为 `[1]`。每轮只有一次明确修改被接受，重新打开仍读到已确认值；镜像、书架、分类与全局设置保持原值。四路权威读回核对显式深色账户 revision 6→7、浅色 8→9，分别只保存 `CHAPTER_FILTER=chapter` 和 `CHAPTER_FILTER=all`。初轮跟随系统与入场画面排除。两张 360×800 图补齐 14.K11，跨版本双主题主图达到 **159/169（94.1%）**。[正式夹具](../../apps/api/test/README.md#api-验证)

## 失效后释放搜索资源的正式 Web 双主题验收

2026-11-19，`0e432ce` 深色基线的 Komiic 搜索真实返回三项，受控 Access 失效让运行时开始关闭。页面仍显示旧查询、旧选源和「正在搜索」，等待和失败时仍报告返回与停止可用。修正后，页面撤下旧会话内容，以 Cupertino 分组呈现失效原因、等待或失败。返回只在释放确认后可用。163 项定向 Flutter 回归、五个 Dart 文件分析、桥接类型和全库格式通过。组件回归另核对背景切换未触发自动重试。

`704d148` 的分支、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 16,311,046 字节，SHA-256 为 `c46961227532ac62e6f4c62ae2a76cc8fdd2a09f194e4bddb07098fdb9651c01`。校验归档 39 项资源、官方 Wrangler 实际交付的 35 条记录、入口 `main.dart.a5925f65.js` 以及原运行时 host 的字节。使用已确认的显式浅色与深色，同一个 Komiic 构建及 `komiic.cc` 镜像。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44417036400) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44417048948)

内置浏览器中，两轮真实搜索「航海王」各返回三项。隔离夹具随后交付 `ACCESS_REQUIRED`，将同一请求、generation、构建和槽位的真实关闭确认暂扣八秒，再模拟确认丢失和两次 reset 确认未到达。等待与失败时，页面均隐藏旧查询、来源和结果，返回报告禁用。失败提供「重试释放搜索资源」。两轮第三次 reset 均由此动作触发，等待期间再次禁用返回，原槽确认后回到「浏览」。明确连接同一服务后，搜索初始为空且没有自动重发。手动提交同一查询从新 generation 返回三项。两主题共核对 14 条运行时事件。账户设置、书架、分类、Source 偏好四路读回在每轮前后完全相等，账户 revision 分别保持深色 3、浅色 4，偏好 revision 均为 1。隔离服务和临时标签已关闭。[复验入口](../../apps/api/test/README.md#api-验证)

四张 360×800 主图补齐 28.K1、28.K2。另两张记录明确重试的等待，两张记录新查询。新查询两主题的结果卡宽 96 逻辑像素，封面占位实拍边界为 `x=[12,100)`、`[112,200)`、`[212,300)` 与 `y=[356,488)`。归一化 Mihon 参考的横向位置与 88×132 尺寸相同，参考首封面起点为 y=241。Karuyomi 的查询、选源、提交与进度放在卡片上方，正式图取自 Komiic，Mihon 参考首组来自 MangaDex。该测量覆盖结果条的局部几何。跨版本双主题主图达到 **161/169（95.3%）**，生产 Access、其它失效变体和完整转场继续验收。[参考像素基准](#15-跨源搜索参考像素基准) · [逐状态清单](mihon-state-coverage.md)

## 共享编辑对象与保存阶段的正式 Web 双主题验收

2026-11-19，`704d148` 正式 Web 浅色基线使用真实英文 xkcd。封面和本漫画阅读设置均只显示动作标题而缺少作品标识。两项保存的真实 D1 确认由夹具暂扣时，封面提前呈现「重试」，阅读设置的关闭和保存报告可用。基线保留六张画面和 36 条完整审计，两笔暂扣均正常放行。相关组新增断言在旧版正确复现 13 项失败。修正后 218 项 Flutter 回归、12 个 Dart 文件分析、全库格式及依赖检查通过，覆盖深浅色与双倍字号的定向流程。

`d0d963c` 分支、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 16,311,363 字节，SHA-256 为 `29045054c6c3764739f5e0a45b97f7404593c1444489895113d34b81db865ab5`。核对归档 39 项和官方 Wrangler 实际交付的 35 条资源、入口 `main.dart.0a83e8b1.js` 及原运行时 host 字节。两套隔离 D1/R2 使用相同的 xkcd、封面字节、分类与设置起始值，分别保存显式浅色和深色。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44423041121) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44423050156)

内置浏览器中单作品分类、封面和本漫画阅读设置都显示作品名及 `en · xkcd`。草稿取消恢复原选择。封面清除等待时保留上次已确认的封面及正在提交的操作，保存、关闭、替换和清除均报告禁用。阅读设置通过真实 `/3319/` 进入，暂扣确认期间保存、关闭、重读和修改均报告禁用，原适配草稿持续可读。设置确认丢失时，真实 D1 提交后客户端收到 502。明确重试复用同一 UUID、预期版本和逐字相同的正文，版本和七路权威数据一致。另一客户端以版本 2 成功保存适宽；旧窗口尝试提交完整显示收到真实 409，保留原草稿，只读重取后显示已确认的适宽。

20 组七路快照核对了八个完全相等区间。浅色 76 条、深色 75 条审计都有终态，每组 11 条审计内 POST。其中三条为 API 预置，另外的 multipart 封面预置有独立回执。开章各触发两次进度写入。每组封面清除确认一次，适宽与适高两个界面设置各应用一次，原请求重试及冲突均零额外应用。外部并发设置各应用一次，冲突重读取七路数据保持相等。两个隔离服务和临时标签已关闭。[夹具复验](../../apps/api/test/README.md#api-验证)

20 张 360×800 原图逐张核对。深色封面与分类首次确认各一张仍在入场，只作辅助。10 张稳定的本漫画阅读设置主图补齐 30.K1–K5，更新 24.K3–K7。封面清除草稿和等待也更新了 19.K7/K8。Mihon 24.01 的同类作用域标签「本作品」归一到 `[24,242,336,262]`。Karuyomi 已确认态的独立作品卡实拍边界为 `[44,267,316,299]`，两主题一致。浅色分组背景与卡片采样约 `#F3F2F7` / `#FFFFFF`，深色约 `#1C1C1E` / `#2C2C2E`。两端分别呈现作用域与当前对象，完整像素和转场继续核对。跨版本双主题主图达到 **166/169（98.2%）**，其它业务范围的触发变体、部分提交、编辑失效及未连接继续验收。[逐状态清单](mihon-state-coverage.md)

## 通用表单的分类参考复核

2026-11-19，使用固定 Mihon 0.21.3 的既有 DEFAULT 原图与 UI XML，按 720×1600 到 360×800 的比例复核空名称、有效名称及重名错误。两主题在键盘打开时都显示字段、辅助说明、取消和添加。添加动作父节点在空名称及重名时禁用，输入 `ZZZZZ` 时启用。重名保留了 `ReadingReadingreading` 并显示具体错误。归一化输入框与添加动作矩形在三种状态、两主题中分别为 `[44,231,316,317]` 与 `[258,341,316,389]`。删除对话框的同名 `ZZZZZ`、取消与确定另核对，证据继续归 05.08。参考表中 132/170 行有两主题，38 行均缺两侧。

历史 Karuyomi `a9fb310` 空分类图仍是底部动作及已聚焦的 Web 正文，截图中保存可用，源 Android 图的键盘与禁用动作现已精确定位。当前分类编辑器已把取消与保存放到 Cupertino 导航栏，空值格式由 `Form` 校验。最终产物中空输入、键盘可达性和保存语义继续复核。[参考状态](mihon-state-coverage.md#2630设置选择与通用弹层)

## 章节部分提交与编辑失效的正式 Web 双主题验收

2026-11-19，`d0d963c` 正式 Web 浅色基线通过真实 xkcd 复现缺口。第一章确认、第二章丢回执后，章节行只显示标题与来源序号，未确认数量和各章结果缺失。后续 401 让原窗口失效，旧窗口仍显示「重试」并报告可用。修复后，Cupertino 弹层保留原作品、来源、逐项结果和数量，行内标题及状态可换行。旧窗口提供关闭和重连说明。121 项 Flutter 回归、68 项 Workerd 用例、三个 Dart 文件分析、夹具类型及完整格式检查通过。

`f084467` 的分支、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 `14486886531` 共 16,312,138 字节，SHA-256 为 `cacf36660f3ef182e2f7ef9545b8b10f26a7e9e9396b9c0799dd77f788ea4c06`。校验归档 39 项资源。两套独立的 Wrangler D1/R2 实际 HTTP 清单均为 35 条，入口 `main.dart.6be1cacb.js`，运行时 host 与 CI 归档字节一致。内置浏览器使用 360×800 视口及两套账号状态中的已确认显式浅色与深色。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44429686613) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44429694429)

从书架打开 `xkcd · en · xkcd`，选定真实 3326、3325、3324 三章。首章的 200 正常交付，第二章已保存但客户端收到 502，第三章尚未发送。两主题都显示三种结果各一章。选择「稍后」再打开原窗口，先以相同 UUID、预期 revision 和逐字相同的正文重试第二章。六路数据完全相同，第三章仍未发送。明确「继续剩余原清单」后第三章才保存，最终三章均为已读。

随后三章标为未读。等待当前回执时，两主题均报告关闭禁用。深色首章的真实 200 经夹具放行，第二章在进入业务处理前收到受控 401。浅色首章挂起超时，审计第 28 条无终态。恢复时明确原文重试收回首章确认，然后明确继续，让第二章收到同样的受控 401。两主题的旧窗口均保留原三章状态和唯一的「关闭」。通过连接设置确认同一测试身份并打开原作品后，重开原清单本身零写入。原样重试只更新第二章，第三章随后由明确继续更新，最终三章均为未读。

两轮共核对 16 组六路快照及 106 条审计，其中 105 条有客户端终态。每轮六条原章节命令最终各生效一次，账户 revision 2→8，作品 revision 1→7。原文重试已生效的命令零重复应用，重连与重开期间六路完全相同。书签和续读位置保持空，流程中没有打开阅读器。等待时的「暂停剩余操作」和部分确认后的「结束剩余操作」在 Web 辅助树仍会连读相邻说明，独立动作名称继续复核。夹具用本机测试身份和受控 401 验证客户端恢复，真实生产 Access 登录另验。[复验入口](../../apps/api/test/README.md#api-验证)

固定 Mihon 18.01 双主题 XML 的选中数量归一化边界为 `[56,86,68.5,114]`，底部标记已读动作是 `[125,728,149,752]`。这对参考显示同类章节选择和动作位置。逐章服务端确认与失效恢复来自 Karuyomi。12 张 360×800 原图及辅助树保留在 `.local/mihon-reference/`，深浅背景采样分别为 `#1C1C1E` 与 `#F3F2F7`。登记 `karuyomi-f084467-chapter-{partial,expired}-{light,dark}.jpg` 四张主图后，跨版本双主题主图达到 **168/169（99.4%）**。[逐状态清单](mihon-state-coverage.md)

27.K1「尚未连接」仍缺双主题主图。正式 Web 使用当前 origin 作为只读服务地址，无法复现原生端未配置地址的稳定状态。设置组件回归已有未配置及编辑地址的证据，光靠 Web 连接失败无法证明原生初次设置画面。其它业务触发、完整转场、最终像素和生产实测继续验收。

## Mihon 章节过渡与空页的双主题参考

2026-11-19，在既有单实例 Android 参考模拟器运行 Mihon 0.21.3（versionCode 39）。视口 720×1600、密度 320dpi，按 360×800 逻辑坐标量测。通过正式本地图源打开两份自造作品，正常作品有两章、每章两张可区分的图片，另一作品的第二章没有图片。稳定过渡用相同的 DEFAULT、自动阅读背景及从右到左的单页模式。原图边缘采样显示浅色阅读背景 `#FFFFFF`、深色 `#202125`。

第一章以前出现「前面没有啦」与本章名称，翻回可读同一张第一页。继续越过第一章末页，画面同时显示已读完的第 1 章与下一章第 2 章，再翻一页进入第 2 章的实际图片。越过全书末页时显示「后面没有啦」、末章名称和工具栏。两色的正常过渡标签矩形均为 `[64,320,129.5,344]` 与 `[64,424,129.5,448]`，首尾提示文字分别为 `[164.5,350,236,370]` 与 `[164.5,430,236,450]`。这是原 Android 相邻章、首尾信息的布局基准。

通过正常章进入缺页下一章时，原两章名称与「图片加载失败：没有图片」同屏，重试矩形在两主题均为 `[136,466.5,224,514.5]`。保持缺页时深色重试后仍显示原错误。浅色给目标补入一张测试图片，点击同一入口后错误消失，再翻页显示该章实际图像。直接打开缺页章会回作品详情并显示「没有图片」系统提示。两主题同一未读章的可见 toast 原图在发起后约 2.05 秒采样，随后各自的详情 XML 核对其它两章已读及继续入口。这两份 XML 记录返回后的稳定画面。

登记 22.05、22.07、22.11–22.13 后，固定 Mihon 双主题参考为 **137/170（80.6%）**。原始 PNG、XML、toast 时间记录与联系表保留在 `.local/mihon-reference/`。截断 PNG 的试验仅取得带 `2 / 2` 的黑画布，单页错误与独立重试仍待；已知页位的加载、过渡加载、工具切章等待也仍待实拍。恢复了原应用显式深色及黑色阅读背景，返回原书架并移除两份测试作品文件，专用模拟器已关闭。[逐状态清单](mihon-state-coverage.md#2225阅读器与图片)

## 章节批量动作名称与焦点范围

2026-11-19，两个现有 Flutter 流程先复现「暂停剩余操作」和「结束剩余操作」的辅助名称拼接了前面的说明。`b5998b0` 让说明成为独立节点，59 项章节及阅读回归通过。分支、PR CI 与 Wasm 通过，部署跳过。正式 Web 归档 `14488998549` 为 16,312,144 字节，SHA-256 为 `f41f1a0e3ac534a93b46b18ac935a8e1d3783f41d8fbefea644b62da4a016508`。归档 39 项资源和 Wrangler 实际交付的 35 项清单已核验，入口 `main.dart.05069082.js`，原运行时 host 字节一致。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44435325685) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44435332389)

内置浏览器 360×800 深色使用真实英文 xkcd 的三章清单。暂停名称独立，回车可申请暂停。首章回执放行后，结束节点的可访问名称也已独立，焦点矩形仍覆盖整块说明 `[0,216,360,364]`。对该语义节点直接注入回车未触发，鼠标点可见按钮后批次结束。D1 六路读回与审计确认只有首章保存。随后把两个动作放进各自的辅助节点，定向用例确保动作范围与可见按钮一致、说明独立且无点击动作。两项尺寸断言先失败，修复后 59 项 Flutter 回归及两个 Dart 文件严格分析通过。

`4026db3` 的分支、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 `14491330831` 为 16,312,141 字节，SHA-256 为 `203cb058397d442d2a5f043480236b894124fe21fc2060d4169baa9330b0f369`。归档 39 项与两个 Wrangler 服务实际 HTTP 清单 35 项均校验，入口 `main.dart.b458a068.js`，运行时 host 字节一致。两主题的暂停和结束都报告独立名称并占用约 139.54×57 的实际按钮范围，说明是独立节点。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44439002939) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44439009836)

按回车暂停后，先在原地等待首章回执，再用 Tab 进入结束动作并按回车。两主题均结束批次，第二及第三章保持未发送。浅色对语义节点直接注入回车首次无效。深色确认后浏览器将旧暂停节点的焦点保留到结束动作，首次回车无效，重新 Tab 进入后通过。18 条浅色及 23 条深色键盘阶段审计全有终态，每组含两条准备写入和唯一一次章节写入。六路读回证实仅首章标已读，账户 revision 2→3，作品 revision 1→2。`21f23d6` 将暂停和结束分配给不同节点，回归先复现同一节点 ID。正式 Web 两色确认回执到达后结束使用新节点，首次 Tab 进入后按一次回车即可结束，D1 各仅确认首章。

## 阅读器同页与边界的正式 Web 双主题对照

同一 `4026db3` 在 360×800 内置浏览器读取英文 xkcd 的 3324 章《Ultimate Movie Series》。两主题均使用从右到左和第 1 页，对照固定 Mihon `s2203-reader-tools-{light,dark}` 的同一漫画图像。Mihon 原图为 720×1600，经 2:1 归一化保留顶部系统栏和底部手势区。六列近白像素采样中，漫画连续区间为 Mihon `y=[132,673)`、Karuyomi `y=[74,620)`，两主题相同。截图在切换模式后的待保存状态拍摄，独立读回确认两账户都保存到第 1 页。

Mihon 将作品和章节放在上下两行，用底部滑杆和左右端的章节按钮。相同方向下，Mihon「下一章」在左端，中心约 `(32,696)`，Karuyomi 在右端，中心约 `(298,778)`。Karuyomi 标题合并在高度 44 的 Cupertino 导航栏，画布的可操作范围是 `[0,44,360,649]`，阅读选项保留 44×44 的独立触控区。页码滑杆、方向排列与工具分组仍有结构差异。这组量测覆盖同章同页的当前布局与控件，完整像素对齐继续验收。

两色另从 3324 的第 2 页切至 3325 和 3326，核对来源顺序首端的灰色「上一章」。选择反向来源顺序，同一 3326 显示灰色「下一章」，点击不切换。再沿反向顺序回到 3324，真实恢复第 2 页，退出后 D1 读回同一章节位置。页尾「下一页」与章首尾的灰色按钮在此基线仍缺 `aria-disabled`。原图、辅助树、量测和读回保留在 `.local/mihon-reference/4026db3-reader-and-keyboard/`。[逐状态清单](mihon-state-coverage.md#2225阅读器与图片)

`21f23d6` 明示无相邻章，翻页及翻章的辅助状态与同一可用谓词一致。106 项 Flutter 回归和五个 Dart 文件分析通过，含浅深色与 1x/2x 字号。首次分支检查下载 `google-java-format` 收到 Maven 404，第二次分支检查、Wasm 和 PR CI 均已通过。部署跳过。正式 Web 归档 `14494662050` 共 16,312,227 字节，SHA-256 为 `eaffb467d186fbd4308bf5a8499c7d5748b50668360d6dcdfefb7099eee453ad`。核对归档 39 项、两个实际 HTTP 清单各 35 项、入口 `main.dart.bbe59b9d.js` 与原运行时 host 字节。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44446522403) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44446527613)

正式 Web 两主题均在 3326 第一页显示「没有上一章」，第二页反转来源顺序后显示「没有下一章」。首尾两页键与相应章节键均实际报告 `aria-disabled="true"`，另一章按钮保持可用。页方向触控区实测 44×44，章边界约 98.95×44。边界原图包含图片加载指示，截图记录可见控件和辅助状态。六组六路读回与浅色 27 条、深色 33 条终态审计核对每组两次准备、一次章节标记和三次阅读进度写入，退出后服务端保存的续读位置为 3326 第 2 页。新原图与读回保留在 `.local/mihon-reference/21f23d6-reader-boundaries/`，本轮隔离服务和临时标签均已关闭。Karuyomi 跨版本双主题主图为 168/169，Mihon 对照为 137/170。

## 阅读页码滑杆与方向排列

2026-11-19，根据固定 Mihon 的 `ChapterNavigator.kt` 及 22.03、22.06 的双主题参考，将上一章、下一章移至页码滑杆两端。从右到左时，下一章在左端，滑杆往左增加，页方向按钮和图标随之翻转。页码采用 Cupertino 原生滑杆及独立的当前页／总页数显示。空章和单页章仍显示固定页数。

本机固定 Flutter 3.50.0 通过 100 项回归。20 页夹具从第 1 页拖动到第 20 页时，预览改变页码，已观察画面和资源请求保持原页。取消回到原页，松手则加载并观察到第 20 页。另验证从右到左的轨道点选、Tab 和方向键、辅助树的页值和逐页增减。正式章路由覆盖双主题、360×800、1×／2× 字号及单页边界，画布和章操作保持可达。

```sh
cd apps/reader
flutter test --no-pub --concurrency=1 test/reader/reader_screen_test.dart test/reader/chapter_reader_route_test.dart test/reader/reader_access_recovery_test.dart test/reader/reading_progress_navigation_test.dart test/browse/chapter_read_navigation_test.dart test/settings/settings_navigation_test.dart
```

`7db8551` 的分支、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 `14502786895` 为 16,314,424 字节，SHA-256 为 `3ffd74aa65ec0bb66e9d9a1053864dee33f1d3182817ae43c94e836b6bccaeae`。核对归档资源 39 项、两个 Wrangler 实际 HTTP 清单各 35 项、入口 `main.dart.ae3a89d2.js` 和原运行时 host 字节。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44465797607) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44465803869)

在 360×800 的 Codex 内置浏览器打开真实英文 xkcd 3324 章。两个主题都从左到右选到从右到左，下一章从右端约 `(319,627)` 移到左端约 `(41,627)`，下一页也翻到左侧。滑杆辅助节点约 172×40，页值在操作后更新。两主题都从第一页向左拖到真实第二页，Tab 到「页码跳转」后按一次右键回第一页，再点按轨道左端到第二页。退出并关闭原标签后，新标签从书架「继续阅读」回到同章第二页。深色另在 844×390 验证了可见图片、滑杆及章方向，图片区域高 132，滑杆辅助节点宽 414。

每个主题在初始、首次读图、拖动、键盘、点按和新标签续读后分别从六个 API 独立读回。两色当下页位均为无 → 1 → 2 → 1 → 2 → 2，三个跳转各产生一次确认写入。浅色续读后版本不增，深色横屏额外保存一次第二页的横向锚点。52 条浅色、49 条深色审计均有终态，只有 3324 章记录页位。复验使用正式归档和 `editor-ui` Wrangler 验收入口，两套隔离 D1 分别设显式主题及收藏英文 xkcd。两组本机服务和临时标签均正常关闭。[验收入口](../../apps/api/test/README.md)

同页实拍按 360×800 重采样。每行在 `x=5,13,21,339,347,355` 采样，至少四点的三个 RGB 通道均达到 240 时计入连续图片区。固定 Mihon 两主题约为 `y=[132,673)`，旧 Karuyomi 约为 `y=[74,619)`，新两主题为 `y=[47,582)`。新版下一章横坐标已向 Mihon 的 `x≈32` 靠近，纵坐标比参考 `y≈696` 上移约 69 点。标题、工具区占高与画布位置仍待对照收敛。

## 阅读器工具区与画布

2026-11-19，固定 Mihon 的 `reader_activity.xml` 将 `viewer_container` 和 `compose_overlay` 分层。`ReaderTopBar.kt` 显示作品、章节、书签和更多，`ReaderAppBars.kt` 将章节滑杆与常用工具放在底部。Karuyomi 使用 Cupertino 导航栏分两行显示标题，书签和阅读选项移到顶部。页码进入滑杆所在行，翻页、模式、分页、缩放和设置归到下方工具区。

Flutter 3.50.0 的 122 项定向回归和 10 个文件的严格分析通过。360×844 含顶部和底部安全区的适屏图片在工具显隐时保持同一矩形，短屏图片仍全部位于可见画布。正式章节组件在 360×800 两主题、1×和 2×字号核对两行标题、顶部书签及更多、底部设置、边界禁用和原操作。原点按回归先发现当前页位数变化会横移滑杆，给计数分配稳定宽度后通过。

```sh
cd apps/reader
flutter test --no-pub --concurrency=1 test/reader/reader_screen_test.dart test/reader/chapter_reader_route_test.dart test/reader/reader_access_recovery_test.dart test/reader/reading_progress_navigation_test.dart test/browse/chapter_read_navigation_test.dart test/settings/settings_navigation_test.dart test/widgets/choice_field_test.dart
```

`313bbc9` 完整分支 CI、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 `14506020393` 为 16,315,637 字节，SHA-256 为 `41d51d935e504a4ccfbf36fcdeff232fc259088c06c0aaef077d91e4c984fe70`。核对归档 39 项资源、两个 Wrangler 实际 HTTP 清单各 35 项、入口 `main.dart.9d5d2b8b.js` 和原运行时 host 字节。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44472093411) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44472099788)

在 360×800 内置浏览器，用两套独立 `editor-ui` Wrangler/D1 分别设浅、深色并收藏英文 xkcd。用 3324 第 1 页、从右到左复用上节的六点采样。Karuyomi 工具栏显示、隐藏、再显示三次的连续图片范围均为 `y=[128,673)`。上版 `7db8551` 为 `y=[47,582)`，Mihon 浅色为 `y=[132,673)`，深色为 `y=[133,673)`。工具显示时可操作画布由 541 增至 649 高，隐藏后为 800 高。下一章辅助中心由 `(41,627)` 到 `(41,715)`，Mihon 参考为约 `(32,696)`。书签、阅读选项和齿轮入口均为 44×44，滑杆辅助范围约 115×40。深色 320×640 工具可换行，画布高 445，844×390 仍有 239 高画布。顶部系统区和底栏仍有可见差距。

两种主题都用 Tab 与回车进入顶部「阅读选项」及底部「分页布局」。焦点分别从「刷新进度」和当前「自动」开始，Escape 回到各自入口。齿轮打开「本漫画阅读设置」，关闭后保留第 1 页。两色均实按顶部添加和移除书签，再用滑杆拖到第 2 页，关闭原标签后从新标签续读第 2 页。

独立读回每个阶段的六个 API。显隐工具及打开、取消菜单前后快照相同；书签增、删与滑杆跳转各写一次，新标签续读快照相同。浅色 50 条、深色 52 条审计均有终态。深色响应式量测额外保存一次第 2 页的横向锚点。同章读回和实际图片在两主题均通过。验收标签及服务均关闭，恢复内置浏览器默认视口。[验收入口](../../apps/api/test/README.md)

## 阅读器显隐与页码

固定 Mihon 的 `ReaderAppBars.kt` 用 200 毫秒滑动和 150 毫秒淡入淡出显示上下工具栏。`ReaderActivity.kt` 在隐藏时保留底部页码，参考 22.02 两色的 `1 / 2` 辅助范围归一化后都是 `[165.5,786,194.5,800]`。Karuyomi 此前同页隐藏工具时没有可见页码，连续与条漫缺中央显隐入口。

Flutter 3.50.0 的 153 项定向回归和三个 Dart 文件的严格分析通过。组件测试在动画中间确认导航向上、底部工具向下、画布尺寸与适屏图片位置保持稳定，移动中的控件从触控与辅助树退出。测试覆盖隐藏页码的值和可点击范围、Tab 与回车恢复、快速反向切换、系统减弱动态与关闭动画。连续和条漫逐一核对单击显隐、双击查看及当前阅读锚点保持。旧连续模式用例暴露拆除图片的双击识别器时仍会交付待确认的单击。布局和拆除阶段忽略该迟到事件后复验通过。

```sh
cd apps/reader
flutter test --no-pub --concurrency=1 test/reader/reader_screen_test.dart test/reader/chapter_reader_route_test.dart test/reader/reader_access_recovery_test.dart test/reader/reading_progress_navigation_test.dart test/browse/chapter_read_navigation_test.dart test/settings/settings_navigation_test.dart test/widgets/choice_field_test.dart test/widget_test.dart
```

2026-11-20，`66be7cd` 的分支 CI、PR CI 和 Wasm 通过，部署跳过。正式 Web 归档 `14549702162` 为 16,317,639 字节，SHA-256 为 `af07f1f5a4fe37c86ee6d41683132106df64e2b8f496e4037b04fa08f601ba09`。核对归档资源 39 项、两套 Wrangler 各自交付的 35 项清单、入口 `main.dart.d8384f3e.js` 和原 host 字节。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44559854376) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44559874097)

在 360×800 内置浏览器，以两套独立 `editor-ui` Wrangler/D1 显式设定浅、深色，打开英文 xkcd 3324 章。浅色按 T 隐藏，再按 Tab、回车恢复。深色中央点按隐藏，再点按底部 `1 / 2` 恢复。隐藏页码的触控范围两色均约 54×44，辅助名称包含动作和页位。按前节的六点采样，Karuyomi 从右到左分页显示、隐藏、复显的图片范围均为 `y=[128,673)`，Mihon 同页隐藏参考为 `y=[127,673)`。在 `x=126–234`、`y=760–799` 的区域，逐点取三个 RGB 通道均不低于 150 的文字像素。Mihon 页码为 `[167,788,193,798)`，Karuyomi 为 `[170,786,191,796)`。系统减弱动态与关闭动画的证据来自上述组件测试。

两种主题的竖向连续和条漫均通过中央单击隐藏和复显，双击打开图片查看并返回原页。深色条漫另在 844×390 核对显示工具时图片高 239，隐藏时高 390，底部页码按钮可复显，图片恢复原尺寸。标签及验收服务正常关闭，浏览器默认视口已恢复。[验收入口](../../apps/api/test/README.md)

浅色 60 次、深色 66 次分阶段 API 读回验证 360×800 的分页、连续和条漫中 `current` 都保持第 1 页原锚点。分页和条漫的两次显隐各自零写入。连续隐藏工具后第 2 页末端实际进入画布，两色的最远位置从约 0.833 推进到 1，各有一次确认写入，本章仍为未完成。深色改为短横屏时另保存一次第 1 页在视口中的新位置。53 条浅色、57 条深色审计均有终态，只有该章产生阅读进度写入。

## 阅读单页与切章等待

固定 Mihon `PagerPageHolder.kt` 和 `WebtoonPageHolder.kt` 在页字节加载及解码时显示指示，解码失败后在该页提供重试。`ReaderActivity.kt` 的工具栏切章单独进入不可取消的等待弹层。画布内的相邻章过渡由 `ReaderTransitionView.kt` 呈现。22.01、22.04、22.10 和 22.14 的 Mihon 双主题实拍继续待采。[逐状态清单](mihon-state-coverage.md#2225阅读器与图片)

Karuyomi 单页读取时向辅助树提供页号，解码首帧期间继续显示旋转指示。错误和重试留在该页的范围内，重试使用新的资源请求。工具切章使用带目标名称的 Cupertino 弹层，等待期间阻挡遮罩点击、Escape 和系统返回。组件测试覆盖工具恢复、旧页会话确认关闭后才获取新章图片，以及强制卸载时清理迟到的目标会话。

2026-11-20，`b4aef11` 的分支、PR 主检查与 Wasm 通过，部署跳过。正式 Web 归档 `14558514997` 为 16,317,917 字节，SHA-256 为 `84f70e4d0351f0e7ff27a3b8d907d767525e1005b311374b74503fe186ede7f4`。归档 39 项资源，两套 Wrangler 实际交付各 35 项清单，入口 `main.dart.a529c948.js` 和原运行时 host 字节均与 CI 一致。两套隔离 D1 使用同一英文 xkcd，分别保存显式浅、深色。验收入口对明确匹配的控制请求等待 19 秒并返回一次受控 Source 错误，重试交给原 host。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44580568052) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44580578558)

360×800 内置浏览器两主题从 3324 进入第 2 页。画布显示进度指示，辅助树为「正在加载第 2 页」，滑杆的 `aria-valuetext` 为 2。失败后同一画布显示「第 2 页未能加载」和「重试」。明确重试保持同一 runtime generation 与页身份，使用新 requestId，并得到原 Source 的实际文字图片。关闭原标签后，两色均在独立新文档从书架「继续阅读」回到第 2 页。

两色点「上一章」时弹层列出 3325: Light-Day，等待中 Escape 保留弹层，后台工具从辅助树退出。受控失败均回到 3324 第 2 页。再次点击取得 3325 的实际页列表，首张图片显示并保存到服务端。八组六路独立读回表明单页失败时已保存续读坐标，第 2 页成功解码后才记录最远阅读位置。手动切章失败前后两组完整读回各自相等，成功切章后服务端指向 3325 第 1 页，3324 原记录仍可读取。两个临时服务与浏览器标签正常关闭。

两色首次切章失败后，实拍均缺少错误文案。组件回归在 `b4aef11` 复现同一情况，后台预取启动后清除了手动错误。`71d67ae` 独立维护手动错误和预取提示，回归确认预取开始和成功结束后均保留手动错误。Flutter 3.50.0 的 67 项阅读相关定向回归通过。

```sh
cd apps/reader
flutter test --no-pub --concurrency=1 test/reader/chapter_reader_route_test.dart test/reader/reader_access_recovery_test.dart test/reader/reading_progress_navigation_test.dart test/reader/reader_screen_test.dart
```

`71d67ae` 的分支、PR 和 Wasm 均通过，部署跳过。正式 Web 归档 `14562390257` 为 16,317,968 字节，SHA-256 为 `cdbfeaf881e82f096e93b94cb7159ca43977ceb642a41c4b99cb26eaef0569a6`。原归档 39 项资源与官方过滤出的 35 项公开清单均已核对。两个新隔离服务实际交付的入口 `main.dart.78cc3bd9.js` 和原运行时 host 字节与归档一致。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44585367157) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44585380779)

两主题各先读到 3324 第 2 页，再从新文档独立续读。受控的 3325 请求失败后约 0.91 秒，延迟的旧页资源答复放行，客户端向 3323 发起实际预取。两色在预取开始后仍显示「漫画源请求失败，请重试」，同页滑杆 `aria-valuetext` 保持为 2。再次点「上一章」，新的请求进入 3325 第 1 页，原错误收起。六组六路快照中，两套测试库各自的失败前后快照完全相等，重试后读到 3325 第 1 页及原 3324 第 2 页记录。临时服务和标签已关闭，视口已恢复。

Mihon 的临时参考模拟器已启动并连接。当前桌面控制无法定位其渲染窗口，本轮未取得新参考图，模拟器与独立设备服务已关闭。跨版本主图及 Mihon 成对参考计数沿用逐状态清单。

## 阅读画布内的章间过渡

复核固定 Mihon 的 22.07、22.11–22.13 原图。参考在画布中把前后章节按顺序分组，360 逻辑像素下首组横坐标约为 64，正常相邻章的标题标签纵坐标分别约为 320 和 424。失败提示、重试与章节信息同屏。首尾状态保留当前章并说明相应方向无相邻章。[Mihon 双主题参考](#mihon-章节过渡与空页的双主题参考)

Karuyomi 在现有章节顺序、预取及关闭流程上加画布内过渡。分页边缘输入和连续、条漫越界拖动使用同一状态。相邻章使用真实页列表，状态覆盖首尾、加载中、缺页、可重试与就绪。168 项定向回归覆盖双倍字号、连续与条漫的两端拖动、等待中回原页、空页会话关闭后重试、原章关闭确认后获取目标章图片，以及原工具栏切章。

2026-11-20，`e5ba265` 的分支、PR 和 Wasm 检查均通过，部署跳过。正式 Web 归档 `14565325042` 为 16,321,414 字节，SHA-256 为 `7a28fc6a6f28e3e95b20ad5b0ee9df1fe065271d52b9b195b23d4f080a82e0f5`。核对归档 39 项资源、实际 Wrangler 交付清单 35 项、入口 `main.dart.1a4c023b.js` 和原 host 字节。隔离账户显式浅色和深色，设置从右到左分页及跟随主题画布。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44592063166) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44592075443)

360×800 内置浏览器打开英文 xkcd 3324 第 2 页，继续翻页后在画布显示 3324 和 3323。验收入口持有真实 `/3323/` 页列表 24 秒，再用同一个真实页会话返回一次空列表。浅色等待中返回同一第 2 页，再进入过渡。两色缺页后明确重试，各自先收到空页会话的关闭确认，再用新的 requestId 和同一 generation 取得目标的两个实际页引用。就绪仍显示原章 `2 / 2`。浅色按钮、深色键盘继续分别打开目标第 1 页，切换时均收到原章会话的关闭确认。两色各五组六路快照中，进入前、空页及重试就绪完全相等。实际进入后，服务端将已读至末页的 3324 标为读完，并保存 3323 第 1 页。两色分别在新文档实际续读该页，六路读回与打开前一致。

两种主题都在 3326 首屏看到「前面没有章节」，反向来源顺序下的同章末页后看到「后面没有章节」。深色上一章画布改为 844×390 后，上一章信息仍在本章之前，「进入上一章」的矩形约为 `[417.7,232.5,540.7,289.5]`，点按显示 3325 第 1 页。连续与条漫的越界拖动证据来自 Flutter 定向回归。

隐藏工具的稳定缺页画面，两色的本章与下一章标签起点均为 `(64,286.5)` 和 `(64,360.5)`，Mihon 对应为 `(64,285.5)` 和 `(64,389.5)`。Karuyomi 的重试按钮约为 `[200.6,456.5,273.8,513.5]`，同排可返回原章。Mihon 的单重试按钮居中。就绪态标签纵坐标分别为 277 和 351，两个操作在窄屏换行。稳定画布浅、深采样约为 `#F3F2F7` 和 `#000000`。Mihon 的 22.10 瞬态与这些像素差异继续核对，成对主图计数沿用逐状态清单。

## Mihon 单页与切章等待的双主题参考

2026-11-20，固定 Mihon 0.21.3（versionCode 39）使用同一只读参考 AVD 顺序采集浅、深色。视口 720×1600，密度 320dpi，以下坐标按 360×800 归一。应用选用 DEFAULT，阅读画布保留原设置的黑色。每次只启动一个实例。临时中继在回环端口按域名暂扣英文 xkcd 的网页或图片 CONNECT，放行后转交原上游，TLS、官方 Source 与图片处理均照常运行。PNG 先采，随后在同一等待窗口获取 XML。

- 22.01 和 22.04 通过相同的 3321《Simulation》触发。两主题先拿到真实页列表，在 `1 / 2` 时等待来自 `imgs.xkcd.com` 的第一张图片。加载指示区域约为 `[160,380,200,420]`，深色主图还显示初入阅读的模式提示。拒绝这个连接后，两色保留页位、实际 502 错误、居中重试和来源提供的 WebView 操作。重试矩形约为 `[136,361.5,224,409.5]`。放行后点同一重试，浅色实拍同页图片，深色最早采样仍显示加载指示，随后同章第二页已显示。
- 22.10 从 3320《House Majority》第 1 页按从右到左模式翻向更早的 3319《Elevators》。两色的「上一章」和「本章」标签起点分别为 `(64,285.5)` 与 `(64,389.5)`。进度指示为 `[156,445.5,204,493.5]`，说明另起一行，边界为 `[133,493.5,226.5,514.5]`。放行后两色都先恢复有两组标题的就绪画面，再继续翻页看到 3319 第 2 页的真实文字图。
- 22.14 从同一 3321 章用工具栏的「上一章」等待 3320。弹层在画面中央偏下，进度指示和「正在加载…」同排。两色按系统返回键后面板保持，放行后都显示 3320 第 1 页的真实图片。浅色弹层后方为 3321 第 2 页，深色为第 1 页，主图用于量测弹层。

八张主图与对应 XML 已逐张检查。表内编号对应 `.local/mihon-reference/` 原图，跟进帧和联系表在同目录的 `reader-delays-20261120/`。参考达到 **141/170（82.9%）**。深色实例退出后，浅色实例从原代理设置和基线数据启动。采集结束已恢复代理并关闭模拟器、专用 ADB 服务和中继。[逐状态清单](mihon-state-coverage.md#2225阅读器与图片)

## 单页反馈与透明图片的调暗

2026-11-20，复核固定 Mihon 0.21.3 的 22.01、22.04 浅深原图及 UI 树。用隔离 Flutter 3.50.0 运行 Karuyomi 阅读器，采用从右到左的两页夹具和 360×800 逻辑视口，渲染以 2× 输出并使用 Arial Unicode 测试字体。两色各测黑画布 0% 和白画布 80% 调暗。首次第 1 页的资源取得由夹具暂扣，隐藏工具后相隔 160 毫秒的两张等待帧只在旋转指示区变化。随后交付受控失败并点按「重试」，实际解码三种透明度的本地 PNG，四组均保持 `1 / 2`，解码前尚无有效图片观察。[Mihon 同页参考](#mihon-单页与切章等待的双主题参考)

| 元素     | Mihon 双主题逻辑范围    | Karuyomi 双主题逻辑范围 |
| -------- | ----------------------- | ----------------------- |
| 加载指示 | `[160,380,200,420)`     | `[170,390,190,410)`     |
| 重试按钮 | `[136,361.5,224,409.5)` | `[143.4,388,216.6,443)` |

加载指示的中心均为 `(180,400)`。Mihon 的失败消息和来源 WebView 操作与重试上下相邻。Karuyomi 在失败消息下方保留居中的 Cupertino 重试。白画布调暗 80% 时，`e9981b4` 在 `#333333` 灰底绘出黑色失败文字，实测 1.66∶1。修正后灰底相同，失败文字为白色，实测 12.63∶1，重试按钮底色恢复为 `#0A84FF`。修正前后第 1 页的不透明红、半透明红和全透明处像素均为 `#330000`、`#331919`、`#333333`。

图片通过 Flutter 的绘制颜色缩放 RGB，保留 alpha。等待指示、解码提示、错误和动作按实际底色绘制。实测分页、连续模式和放大窗口得到相同透明像素。967 项 Flutter 测试通过，其中定向回归核对调暗切换不重新获取资源、重试使用同一页的新请求、解码后才发布观察。三种透明度取样来自组件、替代字体和本地 PNG 夹具，正式 Web 的原图复验见下节。[阅读器](../../apps/reader/lib/features/reader/reader_screen.dart) · [图片绘制](../../apps/reader/lib/features/reader/resource_image.dart) · [像素回归](../../apps/reader/test/reader/reader_screen_test.dart)

### 双主题正式 Web 的单页失败与图片查看

2026-11-21，从 `71bc54e` 构建 Flutter 3.50.0 release，内置浏览器实际取得的入口 `main.dart.5b32dd90.js` 与原 Vite Host 均与正常构建逐字节相等。两个 Wrangler 隔离 D1 分别设显式浅、深色，实际阅读与 Mihon 22.01、22.04 相同的英文 xkcd 3321《Simulation》。Karuyomi 采用从右到左单页、白画布调暗 80%。隔离验收构建在原 Host 返回此章页列表后，按同一 generation、页会话和首个 `pageKey` 暂扣首次 `acquireImage` 15 秒，再以原控制请求 ID 交付一次 `SOURCE_ERROR`。后续重试直接调用原 Host。浅色首次探查后从同一测试账户的新文档复拍稳定帧。[Mihon 同页参考](#mihon-单页与切章等待的双主题参考) · [官方验收脚本入口](../../apps/api/test/README.md)

360×800 隐藏工具后的两张等待 JPEG 相隔约 0.44 秒。任一 RGB 通道相差超过 3 的像素均在 `[168,384,192,416)`，范围中心同 Mihon 指示的 `(180,400)`。两色均保留 `1 / 2`。失败时灰底采样为 `#333333`，失败文字亮处为 `#FFFFFF`，采样对比约 12.63∶1，按钮底色采样为 `#3B82F6`。Karuyomi 重试按钮的语义边界为 `[143,388,217,445)`，Mihon 同状态为 `[136,361.5,224,409.5)`。844×390 时两色重试均在 `[385,183,459,240)`，浅色点按、深色 Enter 均成功。

同一页的重试使用新 requestId，保留原 generation、页会话和 `p-0`，两色各收到原 Source 处理后的 27,529 字节，实际画出第 1 页。七路独立 API 快照在等待与失败之间逐字节相同，服务端已保存续读页，实际解码后才出现同页最远阅读位置。分页放大、复位和新文档「继续阅读」保持页号。复位和续读的正文图像区与各自放大前、首次成功绘制的对应区域比较，超过 3 级的像素差均为 0。两色在复位后与续读后的七路快照也逐字节相同。

两色随后用原阅读模式菜单切到竖向连续，打开当前页的「查看图片」。放大、复位及 844×390 短屏关闭均通过。关闭按钮的语义边界在两个视口均为 `[16,0,60,44)`，图片画布在横屏仍采样为 `#333333`，导航栏随浅深主题采样为 `#FFFFFF`、`#000000`。关闭转场结束后焦点回到「放大当前图片」，页位仍为第 1 页。独立 API 读回同一页和作品的连续模式，全局读书设置保持原值。

73 项阅读相关 Flutter 回归和验收桥严格 TypeScript 检查通过，两套服务和验收标签已关闭。原生、系统大字、其余真实 Source 和透明原图样本继续验收。原应用提交的 GitHub 分支与 PR 检查均通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44834109888) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44834117392)

## 画布内等待的信息间距与按钮

根据 22.10 在竖屏约 104 的章节标签间距与纵排加载反馈，Karuyomi 让组间留白按可用高度和字号变化，进度指示居中放在说明上方。返回、重试和进入均用 Cupertino 中号按钮，保留 44×44 的最小触控区和可换行布局。

定向 Flutter 回归先在旧版复现进度指示与说明并排。修改后 169 项相关测试通过。新用例核对 360×800 的章节信息距离、状态纵排与同排操作，以及 844×390 时组间留白收缩、进入实际响应。既有流程同时覆盖双倍字号、目标空页重试、原页资源关闭和连续模式拖动。

`8dd507a` 的分支、PR 和 Wasm 检查通过，部署跳过。正式 Web 归档 `14568741807` 为 16,321,736 字节，SHA-256 为 `900bacd4c952178b398c4c7459db751c4e19e8d570d7a72bdbeb057935cbea17`。两个隔离 Wrangler 入口都核对归档 39 项清单、实际交付 35 项、入口 `main.dart.ae2958b2.js` 和原宿主脚本字节。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44601311175) · [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/44601325051)

浅色 Web 在 360×800 采用单页、从右到左、反向来源顺序和跟随主题画布。从 3320 第 1 页按 Page Up 进入 3319 的画布内过渡。验收入口暂扣原宿主的首份 3319 页列表 24 秒，以原会话返回一次空列表。实拍可见纵排加载指示、说明、原章页码与返回入口。空列表到达后实拍缺页和重试。正常重试恢复就绪，返回与进入按钮同排，各高 45。两组章节标签左缘为 64，间距为 102，Mihon 同状态为 104。缺页时两组标签纵坐标为 284.5、386.5，就绪时为 299.5、401.5。

预览前、缺页和重试就绪的六路独立读回完全相等。明确进入后实际显示并保存到 3319 第 1 页，3320 的独立进度记录保持逐字段一致。浅色原图、量测及快照保留在 `.local/mihon-reference/8dd507a-reader-spacing/`。准备深色标签时内置浏览器连接超时，重新打开面板的请求排队。两个隔离服务已关闭。深色与短横屏新布局的正式 Web 实拍继续待验。

随后复用同归档在新隔离 D1 启动深色验收，实际清单和客户端入口再次通过字节核对。内置浏览器在打开标签时仍超时。该隔离服务已关闭，深色及短横屏的正式实拍待补。

内置浏览器恢复后，继续用同一归档与独立深色账号。反向来源顺序下，实际从 3320 第 1 页按 Page Up 到 3319。深色 360×800 的缺页和就绪标签坐标与上面的浅色测量一致，两组都相距 102。深色等待截图可见上一章、原章和原画布正在淡出，留作转场入场帧，稳定等待画面待补。

缺页时切到 844×390，两组信息纵坐标约为 93.85、167.15，间距约 73.3。返回与重试高 45，点击重试后同排出现「进入上一章」。短横屏两个按钮均位于视区内，恢复竖屏后明确进入。夹具记录首次真实页列表含两页并按测试条件暂扣，旧空列表会话确认关闭，重试由新请求取得两页。等待、缺页和重试就绪的六路读回与进入前基线完全相同。实际进入后账户 revision 5→7，3319 第 1 页成为续读位置，3320 记录逐字段一致。正常入口的新文档续读同章第 1 页，六路状态与进入后完全相同。原图、辅助树、量测和路由快照在 `.local/mihon-reference/8dd507a-reader-spacing/dark-resumed-20261120/`。

## 章间稳定等待与调暗

2026-11-20，复核固定 Mihon 0.21.3 的 22.10 浅深主图。用隔离 Flutter 3.50.0 在 360×800 逻辑像素运行 Karuyomi 原章节阅读路由，两色用从右到左的同名 3320 与 3319 测试章节。组件输出为 720×1600，文字采用 Arial Unicode 测试字体。按 T 隐藏工具，Page Up 发起上一章页列表读取，夹具只暂扣目标结果。在入场的 60 毫秒和超过当前 180 毫秒转场的 260 毫秒、420 毫秒采样。两张稳定帧之间只有旋转指示区发生像素变化，仍显示 3320 第 1 页的 `1 / 2`。点按「返回本章」恢复同一页和同一图片提供者。[Mihon 参考](#mihon-单页与切章等待的双主题参考) · [读取入口](../../apps/reader/lib/features/reader/chapter_reader_route.dart)

| 稳定等待的元素 | Mihon 双主题逻辑范围    | Karuyomi 双主题逻辑范围 |
| -------------- | ----------------------- | ----------------------- |
| 上一章标签起点 | `(64,285.5)`            | `(64,271)`              |
| 本章标签起点   | `(64,389.5)`            | `(64,374)`              |
| 组间标签距离   | 104                     | 103                     |
| 加载指示       | `[156,445.5,204,493.5)` | `[170,429,190,449)`     |
| 加载说明上缘   | 493.5                   | 457                     |

在浅深两色、白画布调暗 80% 时，`a808c42` 的画布是 `#333333`，章节标题为 `#000000`，无损图实测标题对比度 1.66∶1。修正后保留相同灰底，标题使用 `#FFFFFF`，对比度 12.63∶1。Cupertino 动作、进度、文字单独绘制，必要时采用系统高对比色或正文色。回归覆盖黑白画布以及 0%、50%、80% 的选定组合，检查加载说明、缺页、可点按的返回和重试。调暗前后保留原章身份及布局。966 项 Flutter 测试与严格 Dart 分析通过。此处两色证据来自 Flutter 组件和受控页列表。[章间界面](../../apps/reader/lib/features/reader/reader_screen.dart) · [布局与对比度回归](../../apps/reader/test/reader/reader_screen_test.dart)

## 双主题正式 Web 的稳定章间等待

2026-11-21 从 `a9a21aa` 本地隔离构建 Flutter 3.50.0 release 与正式 Vite host，在 Codex 内置浏览器的 360×800 视口运行。两次 Wrangler 验收均逐字节核对 `main.dart.643d6f1c.js` 与 `runtime/host.js?acceptance-original=1`。原宿主 SHA-256 为 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。两色各用独立 D1，阅读设为单页、从右到左、白画布调暗 80%，来源顺序反向。经详情打开真实英文 xkcd 3320《House Majority》第 1 页，保存后隐藏工具，再按 Page Up 转向 3319《Elevators》。验收夹具只暂扣 3319 首份真实非空页列表 18 秒，同一 requestId、generation 和页会话原样收到两页。[复验入口](../../apps/api/test/README.md)

两色各在暂扣后约 0.6 和 1.1 秒实拍。每对 JPEG 解码后的像素变化仅在加载指示周围的 `[168,424,192,448)`。上一章和本章标签的可见像素上缘分别为 275 和 377，间距 102 像素，Mihon 的同状态标签间距约为 104。两色灰底均采样为 `#333333`，采样亮笔画相对灰底的对比度为标题约 12.1–12.6∶1、加载说明约 8.7∶1、返回约 12.6∶1。画面保留 `1 / 2` 和可点按的 Cupertino 返回。[Mihon 同状态参考](#mihon-单页与切章等待的双主题参考)

两色在交付前点「返回本章」，画布恢复同一张 3320 第 1 页，实际交付前后的恢复图逐字节一致。重新按 Page Up 后显示已就绪的上一章。等待前、等待中、迟到交付后，各自的全局设置、作品设置、书架、分类、作品、书签和章节进度七路读回相等。明确点「进入上一章」才显示并保存 3319 第 1 页，原章记录逐字段相等。随后在新文档从书架续读，两色都恢复同一张 3319 第 1 页，图像截图和七路读回都与进入后一致。

63 项阅读器定向 Flutter 回归和 TypeScript 桥类型检查通过。验收标签和服务均已关闭，视口恢复。原生、系统字号与其余转场状态继续按计划验收。[阅读器验收计划](../plan/mihon-cupertino-fidelity.md)

## Mihon 封面操作与阅读模式继承

2026-11-20，固定 Mihon 0.21.3 以同一只读参考设备顺序采集应用浅深两种主题。视口 720×1600、密度 320dpi。以下坐标按 360×800 逻辑像素归一。两色使用相同英文 xkcd 3322 章，并在阅读中确认用第 1 页作为测试封面。

- 19.02 两色实际作品详情均显示 Dragonfly 自定义封面。放大预览占满画面宽度，封面亮像素的纵向范围约为 `[211.5,579.5)`。编辑图标的辅助边界为 `[320,736,344,760]`，菜单「编辑」和「删除」的文字起点分别约为 `(176,570)` 和 `(176,618)`。操作集中在图下方。
- 19.03 两色「编辑」均进入 Android 系统照片选择器，取消后同一全幅封面及动作仍可见。「删除」直接回到默认 xkcd 封面，预览仍打开，并显示「封面已更新」。阅读器置图使用自己的确认框，见 25.02。系统选图另存，系统表面由 Android 控制。
- 24.04 两色选择本作品「条漫」，返回画布并收起点按区提示后，可见纵向连续内容和章间信息。恢复「默认」后实际回到从右到左的分页，第 2 页文字图片可见。条漫模式「下一章」在右侧，归一化边界为 `[316,684,340,708]`，继承分页后在左侧，边界为 `[20,684,44,708]`。两色的条漫画面滚动锚点不同，位置量测采用工具端点和选中值。

十四组 PNG 和对应 XML 已核对，其中四张为阅读设置选中态。主图文件按状态表保留，点按区提示、系统选择器和联系表在 `.local/mihon-reference/mode-cover-20261120/`。参考覆盖达到 **144/170（84.7%）**。本次参考修改在只读实例内，模拟器和专用 ADB 已关闭。[逐状态清单](mihon-state-coverage.md)

### Karuyomi 封面预览

旧正式 Web 的当前封面在表单行右侧显示，当前封面和草稿都采用 120×160 的固定裁切框。新组件利用表单宽度居中显示完整图片，已确认和草稿采用相同布局。预览高度随视口收缩，窄屏正文仍可滚动，替换、清除与顶栏保存走原确认路径。

新增断言先在旧组件复现草稿宽度为 120。修改后 61 项 Flutter 定向回归通过，覆盖双主题、1×/2× 字号、360×800 的居中与全幅适配，以及 844×390 的高度收缩。既有用例同时核对选图取消、读取失败、丢确认重试、清除保存和实际封面读回。`dd6c3da` 的分支、PR 和 Wasm 检查通过，新布局的正式 Web 实拍继续待验。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44610202549) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44610215114)

`4332503` 分支、PR 和 Wasm 检查通过。正式 Web 归档 `14574772224` 为 16,322,855 字节，SHA-256 为 `87c4c4b34eedc1846c95e56b49df8c27c5ddfbd41e80c2ee21622cbba9af5a84`。验收入口核对 39 项归档清单、35 项实际交付、`main.dart.f7158888.js` 及原宿主脚本字节，采用显式深色的独立 D1 账号。用正式 multipart API 预置一张 300×150 的四边彩色测试图，在内置浏览器由 xkcd 详情打开封面编辑器。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44615243815) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44615258161)

360×800 实拍中，约 288×144 的整张宽图居中，四边可见，固定占高留下了较大纵向空白。844×390 中图片上沿约在 `y=265`，首屏裁掉下沿，替换和清除的辅助边界均在可见底缘下方。随后浏览器控制两次超时，未完成横屏滚动。六路独立读回确认本次预览期间账户 revision 3、作品 revision 2，各响应逐字段相同。原图与量测保存在 `.local/mihon-reference/4332503-cover-web-20261120/`。两个 Web 验收服务已停止。

修正后的已确认封面和草稿均按实际显示高度占行，上限随弹层可用视区变化。新用例先复现 288 宽的草稿占高 288，修改后解码实际图片，占高为 144。切到 844×390 后确认预览下沿在视区内，滚动进入清除后关闭，服务端变更次数保持一致。封面、详情、书架和设置的 138 项 Flutter 定向回归通过。修正版本的正式 Web 双主题仍待复验。

封面修正提交 `e7523ea` 的分支、PR 和 Wasm 检查通过。正式 Web 归档 `14576959514` 校验为 16,322,637 字节，SHA-256 为 `283906f03623bc7f8efd0c934726eda3e903cbb4b36c51da731291da062428fa`，入口为 `main.dart.35bcc59d.js`。隔离目录内的 Vite 资源装配和验收配置生成通过。内置浏览器的列表查询和单独绑定均超时，未开启验收服务，修正后的 Web 画面继续待验。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44620095248) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44620107333)

### 正式 Web 宽封面双主题复验

2026-11-20，内置浏览器实际打开 `e7523ea`。两个独立 Wrangler 验收服务均核对了 CI 归档 39 项与实际交付 35 项清单、`main.dart.35bcc59d.js` 和原宿主脚本的字节。以各自的显式主题和相同 xkcd 样本验证，300×150 测试图由隔离 D1/R2 的 multipart API 预置。

两种主题中，360×800 的封面实测边界均为 `[36,298,324,442)`，宽高 288×144。844×390 的边界均为 `[312,266,532,376)`，宽高 220×110。两个视口都能看到四边色带，横屏继续下滚可触及「替换图片」和「清除封面」，关闭返回同一作品详情。六张实拍和读回保存在 `.local/mihon-reference/gallery-and-cover-20261120/`。

两次验收完成后，六路读回均为账户 revision 3、作品 revision 2，浅色查看前后的六路响应逐字节一致。审计分别为深色 18 条、浅色 21 条，范围内写入均为夹具准备。封面上传准备由独立 multipart 路径执行。已恢复内置浏览器视口、关闭临时标签和两个服务。此次实拍覆盖已确认的宽封面，Web 选图草稿、失败及其它封面比例继续验收。

### 替换封面后自动显示草稿

2026-11-21 复核 Mihon 19.02、19.03。Mihon 的全幅预览在图片下方提供编辑动作，退出选图回到原预览。Karuyomi 的编辑弹层在原封面下方分组展示未确认草稿。`b00397d` 的深色 844×390 实拍中，选择替换图片后顶栏出现保存，画面仍只显示已确认封面和替换、清除操作。组件回归测得新图下沿在 `y=543.18`，超过高度 390 的视口。向下滚动可找到草稿。[Mihon 封面参考](#mihon-封面操作与阅读模式继承)

选择有效图片后，先解码预览再用 Flutter 的滚动定位显示草稿组。清除草稿沿用同一定位，Cupertino 顶栏保留关闭和保存。回归在短横屏验证居中、预览和说明的下沿、清除草稿进入视口以及关闭零提交。[封面编辑](../../apps/reader/lib/features/covers/custom_cover_editor.dart) · [封面定向回归](../../apps/reader/test/covers/cover_navigation_test.dart)

在 `main.dart.81fca0cd.js` 的浅深两色实拍中，切回横屏并再次选图后取消，现有草稿只露出上边。回归将视口滚回已确认区再选图取消，测得草稿下沿约为 `y=470.28`。取消选图现在也会将已有的草稿组滚回可见区域。

同一隔离 Web 构建分别验证两色关闭并重开替换草稿，均读回原封面。随后点清除形成草稿，暂扣真实 JSON 清除的确认时显示「保存中」「正在等待服务端确认」与原清除意图。放行后显示「未设置自定义封面」，关闭返回 xkcd 详情，两色各在新文档读回。每个账号的 57 条审计内仅有一次真实清除，Worker 和客户端均返回 200。账户 revision 从 4 到 5，作品从 2 到 3。七路读回及原封面字节摘要在选图、取消、关闭和暂存清除期间相等，新文档读回与确认后一致。[验收入口](../../apps/api/test/README.md)

最终的正常 Web release 入口 `main.dart.032024c7.js` 编译通过。实拍使用同源码的临时受控选图入口 `main.dart.05a8a993.js`，由 `FileSelectorPlatform` 返回同一张 300×150 合成 PNG 或空值，实际应用负责图片归一化、Cupertino 弹层和滚动。两色分别采用独立 Wrangler D1/R2，原封面通过正式 multipart API 预置，内置浏览器逐字节核对交付入口和原 runtime host。

两色新图在 360×800 均为 `[36,590,324,734)`，在 844×390 均为 `[312,233,532,343)`。短横屏选图与转回横屏后取消，再现相同矩形、完整四边及会话提示。选图处理中，关闭、替换、清除均有禁用语义。关闭后重开原封面，各账号的七路读回和图片 SHA-256 与开始一致。31 项最终定向测试和改动 Dart 文件的严格分析通过。标签和验收服务已关闭，视口恢复。真实系统文件选择器、Web 替换上传的确认和故障变体继续单列验收。

## Mihon 详情刷新与章节空态

2026-11-20，固定 Mihon 0.21.3（versionCode 39）和英文 xkcd，在同一只读 Android 参考模拟器顺序测深、浅色两种 DEFAULT 主题。原图为 720×1600、320dpi，本节量测按 360×800 逻辑像素归一。临时回环中继暂扣并拒绝测试中的 xkcd CONNECT，放行后经原上游建立 TLS。官方 xkcd Source 的 `fetchMangaUpdate` 保留既有元数据并从归档取章节，因此该次 502 是章节侧失败。

- 16.07 已收藏作品下拉后，刷新指示在两主题的辅助边界均为 `[172,184,188,200]`。底层保持标题、作者、简介和章节清单。深色在刷新前及等待中均为 3323 章，浅色复用稍早已更新的 3325 章。
- 16.05 两主题在同一次被拒绝的请求后仍显示原清单。`Unexpected response code for CONNECT: 502` 的辅助边界均为 `[28,658,325,678]`。放行再下拉后，深色更新至 3325 章，浅色保留 3325 章，两色首条均为 `3326: Voyager Crash`。Mihon 的错误消息会消失，下一次刷新由下拉触发。
- 17.06 两主题选用「已下载」筛选，收起弹层后，同一个 xkcd 保留封面和简介，工具栏显示筛选已启用，章节数为 0。清除该条件后恢复 3325 章。
- 17.02 在临时实例的本地 Source 打开实际无章节的测试作品。两主题显示标题、本地图源、共 0 章与筛选及更多入口，浅色下拉重读仍为空。冷开录像中可见详情内加载，未截到 16.01 的独立全屏指示。单独的元数据失败也继续待采。

八张状态 PNG 与对应 XML 已核对，四组双主题主图入表，覆盖达到 **148/170（87.1%）**。刷新前后的画面、筛选操作、空作品打开录像和联系表保存在 `.local/mihon-reference/details-refresh-20261120/`。参考设备的代理已恢复，临时模拟器、中继和专用 ADB 均已关闭。[逐状态清单](mihon-state-coverage.md)

### Karuyomi 原位刷新

作品详情接入 Cupertino 下拉刷新和章节区刷新按钮。加载保留同一个作品和章节清单，两个读请求都成功后更新。请求失败继续显示原资料并提供重试。无结果筛选可一次清除，实际空清单仍有刷新入口。168 项定向 Flutter 回归通过，覆盖等待、失败、重试、返回后的晚到结果、双倍字号及实际下拉。测试账户未观察到刷新引发的业务写入。可在 `apps/reader` 用 `flutter test --no-pub --concurrency=1 test/browse/details_recovery_test.dart` 复验详情流程。本轮的新布局正式 Web 双主题继续待验，历史跨版本双主题主图为 168/169（99.4%）。

#### 详情刷新故障的双主题正式 Web

2026-11-21，内置浏览器在 `6458786` 的 360×800 正式 Web 中打开真实英文 xkcd，并用验收夹具拒绝一次已返回的章节结果。等待时滚到章节中段，失败后视口只剩章节列表，向上滚回才看到合并了错误正文和重试的按钮。组件回归量得旧版等待时章节标题下移 20 逻辑像素，并复现 360×480 双倍字号下滚动会失去反馈。Mihon 的同作品参考保留标题、简介和章节，错误出现在底部。修正后 Karuyomi 采用固定于滚动区下方的 Cupertino 反馈，原因和重试各自可达，章节工具保持原位置。[Mihon 参考](#mihon-详情刷新与章节空态) · [详情实现](../../apps/reader/lib/features/browse/manga_details_page.dart)

`1e6b1ba` 的本地 Flutter 3.50.0 release Web 由官方 Wrangler 验收入口交付。实际 HTTP 客户端 `main.dart.643d6f1c.js` 的 SHA-256 为 `643d6f1c67d10fc795b85951bebb1718c299443ae03b03a2d2ea6aa84cf9e322`，原宿主 SHA-256 为 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。浅深两色分别在独立文档各测一次资料阶段和章节阶段。夹具在原宿主成功读回后暂扣 2.4 秒并向客户端交付一次 `SOURCE_ERROR`。四轮均按原英文源、`SINGLE` 和原代次重试。资料阶段失败当次未发起章节读取，恢复时两阶段均成功，实际章节清单为 3,326 项。[可复验入口](../../apps/api/test/README.md)

两色章节故障均保留作者、简介和首章 `3327: Plate Maintenance`。相同主题的等待、失败和恢复稳定帧中，章节标题矩形 `[16,404,116,458)` 的灰度抽样逐像素一致。资料故障两轮在等待时实际滚到中段，失败与重试后仍保持当前章节位置。固定底部提供独立「重试刷新」，恢复后撤下反馈。每个主题的设置、漫画设置、书架、分类、作品、书签和进度七路响应在两轮刷新前后逐字节一致。随后从深色恢复画面点开首章，实拍第 1/2 页的真实图像和服务端确认，返回仍在原详情。独立读回确认进入阅读器后产生一条进度记录。

两项回归在旧版先复现缺陷，修正后相关 61 项 Flutter 测试、改动文件严格 Dart 分析及验收桥类型检查通过。16.K2 和 16.K3 已补登记为当前版的浅深主图，Karuyomi 跨版本主图覆盖为 **172/173（99.4%）**。实际触控下拉、原生和其它详情变体仍按原计划验收。[回归入口](../../apps/reader/test/browse/details_recovery_test.dart) · [逐状态清单](mihon-state-coverage.md)

#### 下拉刷新的双主题手势对照

2026-11-21，Codex 内置浏览器在 360×800 的 `03ce5ba` 正常 Web（`main.dart.c12df65e.js`）发出可信鼠标拖动，从 `(346,222)` 至 `(346,598)`。原 Cupertino 滚动配置未触发下拉，Source 保持首次资料和章节两次读取。经章节区按钮触发实际等待和失败，浏览器辅助树中按钮缺少 `aria-disabled`。给 Cupertino 刷新按钮补上与点击条件一致的启用语义。新增组件回归用 `PointerDeviceKind.touch` 暂扣章节读取，核对只显示一个进度指示、原章节继续可见、刷新按钮报告禁用，失败后独立重试可用。修正前回归因缺少禁用语义失败，修正后 51 项定向测试、988 项完整 Flutter 测试和改动文件严格 Dart 分析通过。[详情实现](../../apps/reader/lib/features/browse/manga_details_page.dart) · [触控组件回归](../../apps/reader/test/browse/details_recovery_test.dart)

正常 Flutter Web release 构建通过，入口 `main.dart.68b9fe5c.js` 的 SHA-256 为 `68b9fe5c3d67898eed2732504de7d991dea65f005a6da7415972271b660d5b68`。内置浏览器双主题实拍使用同源码的隔离入口，临时将鼠标加入 `CupertinoScrollBehavior.dragDevices`。实际交付的 `main.dart.d624032b.js` SHA-256 为 `d624032b60b203b2452cb654b8aea4ca6669a6e67c5d1d8900cb967b85099924`，实际使用与常规入口相同的原宿主 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。两色分别使用独立的 Wrangler D1 和显式主题。[验收入口](../../apps/api/test/README.md)

两色从真实英文 xkcd 的 `SINGLE` 详情开始，38 逻辑像素短拖未发出额外读取，376 逻辑像素长拖触发资料和章节刷新。夹具暂扣原宿主返回的 3,326 章列表 2.4 秒，再交付一次 `SOURCE_ERROR`。等待时仍显示原内容，章节区刷新报告 `aria-disabled="true"`。失败后底部「重试刷新」从同源、同版本和同代次读回 3,326 章，反馈随成功收起。两组设置、漫画设置、书架、分类、作品、书签和进度七路响应逐字节相同，账户 revision 均为 2。

双主题稳定等待时，首章从 `[16,547,344,595)` 下移到 `[16,607,344,655)`，来自 Cupertino 下拉控件的 60 逻辑像素占位，收起后回到原位置。截图抽样得到浅、深进度指示边界约为 `[165,60,194,88)`、`[165,59,194,88)`，位于导航栏下，Mihon 16.07 的辅助边界在封面区内 `[172,184,188,200]`。深色等待时实际滚到 `3305: Ground Effect`，该行在随后失败和重试恢复时均保持 `[16,99,344,147)`。这些数据记录了隔离 Web 的鼠标手势和模拟触控的组件结果，真机触屏与原生现场待验。[Mihon 下拉参考](#mihon-详情刷新与章节空态)

## Mihon 迁移搜索与共存

2026-11-20，同一只读参考模拟器运行 Mihon 0.21.3（versionCode 39），依次采集 DEFAULT 深、浅色并复验深色共存。原图为 720×1600、320dpi，以下坐标以 360×800 逻辑像素表示。限定的临时回环中继只暂扣或拒绝 MangaDex API 的 CONNECT，其它测试资源经原代理和 TLS 路径转发。

- 20.09 从原 xkcd 详情进入迁移，保留 MangaDex ALL、MangaDex EN 和 xkcd 三组。在两种主题输入实际的 `one piece`。两个 MangaDex 连接被暂扣。已完成的原 xkcd 组显示无结果，顶部线性指示与两组旋转指示同时可见。两个组内指示边界约为 `[172,245,188,261]` 和 `[172,341,188,357]`。
- 20.11 拒绝上述连接后，两组实际显示 `Unexpected response code for CONNECT: 502`，原 xkcd 仍显示无结果。放行后改用 `One Piece`，两组都返回有效作品。聚合页同一查询由 ViewModel 去重，修改大小写触发新的查询。
- 20.12 点 MangaDex ALL 分组进入单源查询。两色实际显示居中等待，随后显示两列结果。首行覆盖矩形约为 `[12,144,174,387]` 和 `[186,144,348,387]`，2:3 封面下沿叠加标题，行列间距均约 12。单源内改搜 `xkcd` 实际显示无结果。`one piece` 的 CONNECT 502 显示明确「重试」，放行后点同一按钮恢复真实结果。
- 21.02 从已在书架的 MangaDex 英文版《One Piece》选择未收藏的同名 ALL 版并点「共存」。确认选项收起，原源标记和候选仍在底层。两色进度指示边界均约为 `[160,380,200,420]`。本次截取目标作品读取期间的画面。
- 21.03 放行后自动打开 ALL 版，两色均显示「在书架中」及 849 章。浅色完成后，只在临时实例移除本轮新增的 ALL 收藏以重复相同条件。深色操作前读回 EN 版仍在书架，深色完成后实际返回 EN 版也确认仍在书架。替换原作、复制的各数据项及批量提交继续核对。

五组双主题主图和对应 XML 已逐项核对，Mihon 主图覆盖达到 **153/170（90.0%）**。补图、连接记录与联系表保存在 `.local/mihon-reference/migration-source-20261120/`。已恢复代理并关闭临时模拟器、回环中继和专用 ADB。[逐状态清单](mihon-state-coverage.md)

### Karuyomi 目标候选网格

既有 `ef5f3dd` 正式 Web 的候选结果为纵向文本行，并显示 Source 的内部地址。本次复用源内浏览的 Cupertino 封面卡片，把候选改为同一滚动区中的懒加载网格。原作、目标源、查询、分页与下方预览留在同一路由，候选卡自身负责精确选择。按 128 逻辑像素的最小卡宽和 12 的间距计算列数，普通 Source 封面仍用占位。

测试先在旧布局测到 320 宽的文本行。修改后两主题、1×/2× 字号的 360 宽画面均显示 162×243 的两个独立封面，间距为 12，点击卡片边缘可打开精确候选。115 项定向 Flutter 回归通过，覆盖长列表追加失败后按原查询重试、返回和身份失效后的首帧、业务确认与原命令恢复。

`2b3d4a5` 的分支、PR 和 Wasm 检查通过。正式 Web 归档 `14579756632` 校验为 16,322,792 字节，SHA-256 为 `c649862ec655683129ec47dbf0dfc3a61ab83b60a5059e5a3d996cd3307cdc56`，入口为 `main.dart.2e3cb35d.js`。隔离目录内的官方 Vite 资源装配和验收配置生成通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44625258990) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44625272180)

#### 正式深色网格与分页反馈

2026-11-20，使用上述正式 Web 归档、隔离 Workerd/D1 和内置浏览器，以显式深色、360×800 逻辑视口从英语 xkcd 选择仅迁移收藏和分类，读取 Komiic 热门。从网格滚到第一行完整可见，两张卡片的辅助边界分别为 `(12, 122, 162, 243)` 和 `(186, 122, 162, 243)`，横向间距为 12。点击卡片边缘打开「腦洞學生會」的只读预览，原作品 xkcd 与目标各自显示名称、源名和语言。

同一运行时代次的热门请求依次返回 30、30、30 项，验收夹具仅替换第一次第 2 页的响应，显式重试后成功追加。等待和失败均显示源与页号。失败时固定提示挤动已有封面，末行同一张卡片由 `y=480` 移到 `y=664`，可见高度由 243 缩为 136。全局设置、书架、分类、原作品、书签、进度和目标源设置七路前后读回逐字节一致，账户 revision 保持 3。复验可将该 Web 归档按 Worker 验收说明装配，启用 `runtime-control` 的 `migration` 场景，使用当前快照中的 Komiic Source ID 与 MangaDex 构建 ID，按运行时审计的代次和页号核对重试。[Worker 验收入口](../../apps/api/test/README.md)

Flutter 长列表回归在 360×640 下也复现了等待时的偏移，末张封面顶边从 `y=328.0` 移到 `y=448.3`。分页反馈移到候选末尾后，等待和失败时封面边界相同，重试在两倍字号下仍可滚动到并点击。输入另一条草稿后，目标查询仍以原查询执行第 1、2、2 页，期间零业务写入。热门第一页为空且还有下一页时，空态与追加进度可同时查看。迁移、章节匹配、存储库、源浏览与目录共 72 项定向 Flutter 回归通过。修正版正式 Web 的浅、深色画面继续待验，跨版本双主题主图计数仍为 168/169。[分页回归](../../apps/reader/test/migration/migration_controller_test.dart)

`9a38d7a` 的分支和 PR 检查已通过。修正版的正式画面仍待内置浏览器验收。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44664081688) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44664088152)

#### 修正版迁移网格的双主题正式 Web

2026-11-21，`07a2896` 的本地 Flutter 3.50.0 release Web 通过官方 Wrangler 验收入口交付，实际客户端与原运行时宿主均与构建逐字节一致。内置浏览器以 360×800 视口从英文 xkcd 选仅迁移收藏和分类，用真实 `komiic.cc` 热门目录。Mihon 20.12 参考的两列、2:3 封面和 12 逻辑像素间距在 Karuyomi 画面中对应 162×243 的卡片，两列左边缘为 12 与 186。Karuyomi 的卡片使用 Source 占位并保留底部标题，1280×720 时同一布局按宽度排成九列。[Mihon 单源参考](#mihon-迁移搜索与共存) · [分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44786398217) · [Worker 验收入口](../../apps/api/test/README.md)

两色均取得第一页 30 项。滚至下一页入口后用同一屏幕位置触发第 2 页。三种画面中末排左卡的顶边都在约 `y=480`，两列封面边缘的抽样像素相同。等待和失败反馈均在封面下方，失败原因和「重试读取第 2 页」在同一屏内可见，轻滚后可看见完整来源和页号。旧版 `2b3d4a5` 实拍的 184 逻辑像素下移在本次两色中均未出现。

每个主题各有三条热门运行时记录。同一个 Komiic 源和同一代次先取得第 1 页 30 项，再由夹具拒绝交付第 2 页的真实 30 项，明确重试仍请求第 2 页并交付 30 项。未提交的文本没有变成搜索请求，追加后原末排候选与新增候选可同时查看。两色均返回原作品或书架，七路账户响应在各自轮次前后逐字节一致。另试搜索「之」取得 100 项，但该实测结果没有下一页入口。非空查询的精确追加重试仍由组件回归覆盖，正式 Web 搜索分页留待支持该操作的 Source。[组件回归](../../apps/reader/test/migration/migration_controller_test.dart)

#### 长候选列表中的预览落点

同轮在 `07a2896` 从 100 项真实搜索候选的首排选「雨夜明月」。读取完成后视口仍停在网格起点，实际滚至列表末尾才看到该目标的预览。组件用同样的百项列表复现成功预览与失败重读区不可见。修复 `95bf156` 复用原滚动区和 Cupertino 分组，点选触发的读取完成后定位并聚焦对应标题。两个新回归与迁移、源浏览共 35 项定向测试通过，改动文件的严格 Dart 分析通过。[迁移页面](../../apps/reader/lib/features/migration/migration_page.dart) · [组件回归](../../apps/reader/test/migration/migration_controller_test.dart)

新构建经 HTTP 核对入口 `main.dart.089d81e7.js`，SHA-256 为 `089d81e7cfa15dbe2acc78128bfabd34bea51ab841c4e1ddbc0f7941a6813532`，原宿主 SHA-256 为 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。两色再次搜索「之」并点首排「雨夜明月」。预览直接可见，辅助树显示标题取得焦点。深色在官方夹具的迁移读取 503 时，视口落在「迁移预览尚未取得」，仍能看到原目标与只读重取。恢复后重取在同处显示同一目标，点「返回检查」可取消确认。两色返回后原 xkcd 仍在书架，各自七路读回逐字节一致。55 条终态审计包含一次受控 503、三次账户预置和一次显式主题保存，迁移提交为零。[Worker 验收入口](../../apps/api/test/README.md)

#### 搜索第二页的双主题恢复与禁用语义

2026-11-21，使用 `9d26313` 的本地 Web release。英文 MangaDex 实际打开目标源后，两次第 1 页 `one piece` 搜索分别在不同运行时代次返回容器中断。普通浏览的热门第 1 页也在独立代次中断。三次均发生在验收夹具的搜索第二页规则生效之前，八路账户读回与基线一致。MangaDex 的此轮在线分页待复验。

两次隔离验收改用当前静态快照中的动漫屋 1.6.3，从书架的英文 xkcd 明确选择仅迁移收藏和分类。在 360×800 内置浏览器搜索「龙」，两色都得到真实首批 22 项。输入「海贼王」作为未提交草稿，点「加载更多目标结果」。夹具只暂扣首份非空的真实第 2 页响应 3.5 秒，随后交付一次错误。明确重试取得真实的第 2 页 21 项。等待、失败和追加后原末排矩形一致；在等待窗口内，两色的辅助树仍把旧候选报告为可用按钮。[Mihon 单源参考](#mihon-迁移搜索与共存) · [验收入口](../../apps/api/test/README.md)

组件回归测得旧版候选的启用语义为 `Tristate.none`。迁移候选现在向 Cupertino 卡片显式传递同一启用状态，等待时禁用，失败或完成后恢复；列表继续复用原网格。[候选网格](../../apps/reader/lib/features/migration/migration_page.dart) · [分页回归](../../apps/reader/test/migration/migration_controller_test.dart)

修正后的正常 Web release 为 `main.dart.c12df65e.js`，SHA-256 为 `c12df65ec5fe9902724012a39d541c90f53248a52fa68e72ac73ffa282ce15b0`，原宿主与上次验收相同。浅、深各以独立 D1 在 Codex 内置浏览器复验，逐字节核对两个交付文件。等待时四张用于量测的候选卡均报告 `aria-disabled="true"`，失败与追加后恢复可用。原末排「李小龙」「猛龙星」在四个阶段的矩形分别为 `[12,480,174,723)`、`[186,480,348,723)`。失败和追加后左卡同一内区的 JPEG 解码像素与等待前相等。等待时图标等局部像素改变，卡片边界保持。12 像素列间距及 162×243 的卡片尺寸与 Mihon 20.12 的归一化量测相同。

用于量测的两轮各发起三次读取，页码为 1、2、2。同一主题的三个请求使用同一 Source ID、同一代次和原查询「龙」。暂扣和拒绝对应同一第 2 页请求，重试使用新的 requestId。明确重试后可继续下滚看到「龙俦纪」「龙宝宝」等新候选，回到顶部的画面仍显示未提交的「海贼王」。退出保留原 xkcd，设置、作品设置、书架、分类、作品、书签、进度和目标源偏好的八路权威响应与基线逐字节相等。44 项迁移和目录定向 Flutter 测试、严格 Dart 分析以及桥接类型检查通过。已关闭验收服务和标签，恢复视口。

## Mihon 扩展目录与仓库错误

2026-11-20，在只读隔离 Android API 36 参考模拟器运行固定 Mihon 0.21.3（versionCode 39）。两种主题均显式选择 DEFAULT 方案，原图为 720×1600、320dpi，以下坐标使用 360×800 逻辑像素。受控故障只在临时回环代理处理插件仓库或 APK 的 CONNECT。需要成功的操作沿原代理和 TLS 路径完成。

- 08.02 在临时数据层移除唯一测试仓库和两项已装测试插件，关闭查询后，浅深色均显示空目录和居中的「插件商店」。说明文字中心分别为 `(180,432.5)` 和 `(180,430.5)`，插件商店文字中心分别为 `(180,512.5)` 和 `(180,510.5)`。点入口抵达空仓库页。下拉时内容仍在，顶部出现实际刷新指示。首次进入插件标签未取得独立冷加载主图。
- 08.08、08.10 使用同一 Keiyoushi Komga 1.6.76 行。暂扣实际 GitHub APK 连接时，两色均显示环形进度、「下载中」和取消，状态文字边界为 `[126.5,322,161,338]`。拒绝新连接后，同一行显示「重试」。再点重试进入下载，取消后恢复「安装」。
- 08.09 放行后，两色原始视频均取得「安装中」短帧，系统安装权限提示随后覆盖该行。短帧已接近系统窗口转场，稳定权限提示另存成对 PNG/XML。系统窗口的 Cancel 与 Settings 和底层 Komga 已实看。均点 Cancel 返回扩展行，设备包列表未出现 Komga。排队画面和完成安装继续待验。
- 10.07 输入同一个 Keiyoushi 目录地址，拒绝实际仓库连接后，两色显示 `Unexpected response code for CONNECT: 502`。输入框完整保留原 URL，错误边界均为 `[60,429.5,300,461.5]`。恢复连接后在同一表单重新点「添加」，Keiyoushi 出现在插件商店列表。

五组双主题主图、对应 XML 和转换画面已核对，Mihon 主图覆盖为 **158/170（92.9%）**。下拉刷新、安装短帧、复验原图及日志保存在 `.local/mihon-reference/extension-directory-20261120/`。代理已恢复，隔离模拟器、专用 ADB 和回环中继已关闭。[逐状态清单](mihon-state-coverage.md)

### Karuyomi 扩展目录与仓库恢复

目录无行时，读取指示和确定为空后的「管理仓库」位于工具栏下方的剩余内容区。目录读取失败后保留先前加载的条目，并提供检查更新与管理仓库。等待期间检查按钮禁用，成功提示以读取结果为准。移除仓库时清理其错误并丢弃迟到的失败，重新连接时从本次目录读取建立状态。只读预览失败时恢复 Cupertino 表单及原地址和名称，允许直接重试和编辑。读取成功后仍经独立确认添加。

121 项定向 Flutter 回归通过，覆盖两色目录等待、空态、失败、已有条目保留、移除与重连，以及两倍字号的仓库失败与重试。测试核对只读读取、预览和取消期间账户零写入。可在 `apps/reader` 中运行 `flutter test --no-pub --concurrency=1 test/extensions test/browse/catalog_controller_test.dart`。六个改动 Dart 文件的严格分析通过。Karuyomi 跨版本主图为 **168/169（99.4%）**，新版正式 Web 双主题、最终像素与其余转换仍待验收。

## Mihon 插件无法加载的双主题复验

2026-11-20，固定 Mihon 0.21.3（`feadad5e`，versionCode 39）在隔离 Android API 36 参考实例中复验。原图为 720×1600、320dpi，应用显式选择 DEFAULT 浅色和深色。浅色使用宿主渲染，首次实例切到深色后以退出码 139 终止，深色使用新的只读副本和软件渲染。两次使用相同显示尺寸、安装包和原因分支。以下数值按 360×800 的辅助边界换算，两种主题的弹层标签边界逐项相等。面板取样为浅 `#FCF7FF`、深 `#292730`。

| 实测原因                | 触发与正文                                                                                                                  | 正文边界 `[左,上,右,下)` |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `UnsupportedLibVersion` | 无代码测试插件声明版本 8.8.1，应用说明库版本不支持。                                                                        | `[44,381.5,316,441.5)`   |
| `Malformed`             | 测试插件省略 `versionName`，应用说明缺少加载信息。                                                                          | `[64,401.5,263.5,421.5)` |
| `Filtered`              | 已安装的 MangaDex 1.6.4 保持混合标签，将内容筛选应用于已安装项并取消允许混合。MangaDex 留在未加载分组，仍可打开原因。       | `[44,391.5,316,431.5)`   |
| `Failed`                | 版本 1.6.1 的无代码测试插件声明一个不存在的 Source 类。按发行版的正常信任入口后，显示 `ClassNotFoundException` 及复制动作。 | `[44,279.5,316,319.5)`   |

类加载诊断的等宽正文边界为 `[44,327.5,316,487.5)`，复制动作边界为 `[44,509.5,129,529.5)`。两色点复制、关闭弹层，再把内容粘贴到 Mihon 的本地插件筛选框。均取得 3,381 字符和 17 个调用帧，归一化空白后与当次进程日志中的堆栈一致。浅色进入系统卸载确认后取消，测试项仍在。深色确认卸载无代码测试包，插件目录和 Android 包查询均确认它已移除，MangaDex 和 xkcd 仍在目录。

复验可用 Android SDK 生成三个仅含清单的测试 APK。声明 `tachiyomi.extension` 功能，使用独立测试密钥签名和安装。分别使用上表的版本、缺字段和缺类条件，按插件列表打开真实失败面。未签名副本的普通安装返回 `INSTALL_PARSE_FAILED_NO_CERTIFICATES`，08.13 的 `Unsigned` 面继续待验。08.14 成对通过后，Mihon 主图为 **162/170（95.3%）**。[逐状态清单](mihon-state-coverage.md)

随后在同一固定发行版的隔离 Android API 36 参考副本复验私有插件扫描。两份无代码归档均声明扩展功能和版本 1.6.1，有签名的测试项实际出现在「未加载」，标为「未信任」。未签名归档在 Android 的 `getPackageArchiveInfo` 解析处失败，应用日志记录对应文件，插件目录没有该项。`Unsigned` 提示仍待实拍。复验结束移除两份归档。[固定版本的扫描入口](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/extension/util/ExtensionLoader.kt)

Karuyomi 旧布局的失败提示只显示原因，并会在长列表滚动区顶部离开视口。准备失败后现保留原区域，显示扩展名、版本、仓库和原因，内容可独立滚动，并报告状态更新。两种主题、两倍字号下的组件回归确认，可看到提示并使用原安装入口重试同一构建，失败时零账户提交，明确重试成功后只提交一次。140 项扩展、目录、收藏源 Flutter 回归通过。准备失败独立登记为 08.K9，Karuyomi 跨版本主图为 **168/171（98.2%）**，正式 Web 双主题待验。[准备失败回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

`77ff240` 的分支和 PR 检查通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44676528286) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44676536593)

### Mihon 插件签名数据缺失的双主题实拍

2026-11-21，在 720×1600、320dpi 的只读 Android API 36 参考副本运行原版 Mihon 0.21.3（versionCode 39，源码 `feadad5e`）。已安装的 xkcd 1.6.2 在基线列于「已安装」。用 Frida 17.27.4 让 Mihon 的 `ExtensionLoader.getSignatures` 对这一个包返回缺少签名数据，其余包沿用原结果。基线样本有一个签名，原加载器记录该包 `isn't signed`，并将其移至「未加载」。这轮记录的是原 APK 在受控签名查询结果下的 08.13。普通未签名归档的 Android 安装和解析结果见前述复验。[加载器源码](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/extension/util/ExtensionLoader.kt) · [原面板](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/browse/ExtensionsScreen.kt) · [调试工具文档](https://frida.re/docs/android/)

两色从同一行的信息图标打开「无法加载」，正文为「此插件未签名，因此没有签名可供检查。」。按 360×800 逻辑像素换算，两色标题均为 `[52,350.5,148,385.5)`，正文为 `[52,401.5,308,421.5)`。「卸载」与「确定」的边界分别为 `[198.5,459.5,227.5,479.5)`、`[264.5,459.5,293.5,479.5)`。两色点「确定」关闭并保留原行。移除注入并正常重开后，xkcd 回到「已安装」，与 MangaDex 同时可见。xkcd APK 前后 SHA-256 均为 `5e43a5b5dc0da6088365b8431c0788017007ff06e7af9eb6b64c58eb40095e8a`，Mihon 原 APK 也复核为发布摘要。[双主题覆盖](mihon-state-coverage.md)

## 首次加载参考与 Cupertino 页面转场

2026-11-20，固定 Mihon 0.21.3（`feadad5e`，versionCode 39）在 Android API 36、软件渲染、720×1600 和 320dpi 的隔离参考副本中录屏。两种显式 DEFAULT 主题依次从冷启动的书架打开已有 xkcd，返回后首次进入「浏览 → 图源」，再切到「插件」及「迁移」。默认设备动画的两段录屏共解码 335 帧。能核对各内容页，未找到可归属的完整首次加载帧。

将隔离设备的窗口、转场和动画时长倍率设为 0，再用相同顺序重录。两个主题各解码 23 帧。下表记录可见加载环的逻辑像素边界及各次录屏的时间戳。同一行的环边界在两色一致。位置由有损原视频的连续蓝色像素量得。主图取已进入对应页的实拍帧，后续帧核对 xkcd 章节、图源列表及已安装扩展均正常出现。

| 状态  | 实拍帧中的界面                               | 指示边界 `[左,上,右,下)` | 浅色 / 深色时间     |
| ----- | -------------------------------------------- | ------------------------ | ------------------- |
| 16.01 | 作品详情首次读取，系统栏之间显示全屏进度     | `[160,380,200,420)`      | 1.132 秒 / 1.046 秒 |
| 07.01 | 「浏览」标题、「图源」选中及中央进度         | `[160,420,200,460)`      | 3.111 秒 / 3.130 秒 |
| 08.01 | 「插件」选中及中央进度，页签保留当次触控高亮 | `[160,420,200,460)`      | 4.512 秒 / 4.479 秒 |

插件页首次读取时禁用下拉刷新由对应渲染分支确认。详情按返回发生在内容已就绪之后。迁移页两次均取得选源列表，20.01 的独立加载画面仍待采。隔离模拟器和专用 ADB 已关闭。Mihon 的双主题主图为 **165/170（97.1%）**。[插件页渲染源码](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/browse/ExtensionsScreen.kt) · [逐状态清单](mihon-state-coverage.md)

Karuyomi 的页面回归复现关闭动画后仍在推进的路由计时和退出残留，以及减弱动态时无法触发的侧滑。共享 Cupertino 路由现将禁用动画的入栈和退出设为零时长，退出读取当前偏好。减弱动态时借用原生返回手势，页面在侧滑中保持原位并按手势进度淡出。组件测试覆盖普通页面入栈、侧滑、从运行中切换偏好、设置声明式详情的系统返回及零写入。279 项导航、设置、选项控件、源浏览、扩展、迁移与阅读器的 Flutter 回归通过。正式 Web 和原生实拍仍待，弹层和 Sheet 按各自路径继续验收。[页面路由回归](../../apps/reader/test/widget_test.dart) · [设置导航回归](../../apps/reader/test/settings/settings_widgets_test.dart)

`b7d5068` 的分支和 PR 检查通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44680561494) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44680570426)

## Cupertino 确认框与编辑 Sheet 转场

2026-11-20，固定 Flutter 3.50.0 从扩展详情点击「卸载」，从书架选项打开「管理分类」。在开启减弱动态的基线上，卸载确认的整屏容器在首帧及 60ms 时分别是 1.30 倍和约 1.18 倍，分类 Sheet 上沿在同一间隔从视口下缘移动至约 575 逻辑像素。两项原位回归均先失败。

正式调用现共用 Cupertino 路由的系统动画策略，常规转场沿用组件库实现，两类弹层在减弱动态时于各自最终位置淡入淡出。弹层打开后切换到关闭动画，键盘取消卸载和点击完成关闭分类在下一测试帧均移除弹层，模拟时间无需推进。关闭动画时重新打开卸载确认，首帧即到最终状态。取消确认无账户 POST，关闭分类无目录 revision 变化，重新打开并明确卸载后只写一次。浅深主题测试复查了 Sheet 顶部露出的背景色。Flutter 全套 957 项回归通过，入口为 `apps/reader` 中的 `flutter test`。[共享转场](../../apps/reader/lib/widgets/app_routes.dart) · [卸载回归](../../apps/reader/test/extensions/extensions_controller_test.dart) · [分类回归](../../apps/reader/test/library/category_page_test.dart) · [背景回归](../../apps/reader/test/theme/app_backdrop_test.dart)

同日用既有 Mihon 0.21.3 隔离参考环境将三项设备动画倍率设为 0。两色分别冷启动书架，进入「浏览」后直接点「迁移」。深色、浅色视频分别逐帧核对 12 帧及 14 帧。迁移列表在约 1.87 秒开始出现时已显示 MangaDex 和 xkcd，未拍到 20.01 单独加载帧。参考主图为 **165/170（97.1%）**，Karuyomi 跨版本双主题主图为 **168/171（98.2%）**。隔离模拟器和专用 ADB 已关闭。Codex 内置浏览器控制未取得当前聊天的活动页面，本轮正式 Web 与 Karuyomi 原生均未采图。[逐状态清单](mihon-state-coverage.md)

`39af158` 的分支、PR 与分支 Wasm 构建均通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44683066119) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44683070381)

## 本机存储的名称容量与清理反馈

2026-11-20，固定 Mihon 0.21.3（`feadad5e`）在 Android API 36、720×1600、320dpi 的隔离参考副本中打开「数据与存储」。浅深两色均使用 DEFAULT 主题。用调试 ADB 临时撤去已初始化的章节缓存目录的写权限，分别点击「清除章节缓存」。两个主题各记录六次文件删除 `IOException`，六个缓存文件的 SHA-256 在两次操作前后逐一相等。实拍均显示「已清除缓存，删除了 0 个文件」，用量仍是 134 kB。两色入口和用量的逻辑边界分别为 `[16,540,112,568)` 与 `[16,568,104.5,586)`。恢复原权限后，在浅色点击同一入口，实拍删除六个文件，占用降到 3.20 kB。

Mihon 的单文件删除函数记录异常并返回失败，清理入口按成功数显示完成提示。11.04 所列的外层异常提示仍待实拍。隔离模拟器及专用 ADB 已关闭。[缓存源码](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/data/cache/ChapterCache.kt) · [存储入口](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/more/settings/screen/SettingsDataScreen.kt) · [逐状态清单](mihon-state-coverage.md)

Karuyomi 从扩展菜单打开「本机存储」，360×800 和两倍字号下的两色组件回归均在旧版复现长名称截断和 256 字节显示为 `0.0 MiB`。Cupertino 列表行的标题随字号换行，总量、明细与诊断容量按实际大小选用单位。复验确认完整名称、`256 B`、可点击的清理按钮和浏览存储时的零账户写入。固定 Flutter 3.50.0 的 157 项定向回归、客户端严格 Dart 分析与本机 Web JavaScript／Wasm 编译通过。内置浏览器控制端仍无活动页面，最新正式 Web 的主图和转场待验。[存储界面](../../apps/reader/lib/features/extensions/extensions_page.dart) · [扩展回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

`a8ca2ba` 的分支、PR 与分支 Wasm 构建均通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44694184573) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44694192620)

### Mihon 外层清理失败与重试

2026-11-21，在 Android API 36、720×1600、320dpi 的只读参考副本使用固定 Mihon 0.21.3。安装的原 APK SHA-256 为 `0026bd25ce5b1c6bdc5bd2c9589a08a811ddc4fa7c994cf937729d5b7010619d`。浅深两次从同样的六个实际章节缓存文件及原索引开始，初始均显示 134 kB。页面加载后，只让 Mihon 进程对章节缓存目录的下一次 `File.listFiles()` 抛出 `SecurityException`。原应用日志同时给出 `ChapterCache.clear()` 与设置页清理调用，确定这次到达 11.04 的外层异常分支。[缓存源码](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/data/cache/ChapterCache.kt) · [设置入口](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/more/settings/screen/SettingsDataScreen.kt) · [调试工具文档](https://frida.re/docs/android/)

两色均实拍「清除时发生错误」。提示实色在 360×800 下约为 `[98,683,262,728)`，原操作和用量仍可见，六个文件及 `journal` 的 SHA-256 逐一相同。解除注入后在同一页重试，两色提示「已清除缓存，删除了 6 个文件」，实际仅剩 `journal`，占用降到 3.20 kB。两色的失败、重试画面、界面树、日志和缓存摘要均已核对。Mihon 用短时系统提示保留列表上下文，Karuyomi 在 Cupertino 分组中保留失败原因和精确重试入口。临时参考实例及专用调试连接已关闭。[Karuyomi 存储对照](#本机副本占用与恢复的双主题正式-web) · [逐状态清单](mihon-state-coverage.md)

### 本机副本占用与恢复的双主题正式 Web

2026-11-21，复看 Mihon 11.01 与 11.03 的浅深图。清理入口紧邻用量，完成时以底部短提示报告删除数，单文件受阻时保持用量。本次 Karuyomi 从「浏览 → 扩展 → 本机存储」实际进入 Cupertino 分组。在 `dc94b7a` 的 360×480 两倍字号组件回归中，从已滚动的列表清理长名称副本会使失败反馈留在视口外。修正将反馈单独布局，开始清理或收到失败后定位到该段。失败原因与重试在前，副本名称和完整 SHA-256 随宽度换行。重试与可用的重建动作在组内占整行并从前缘对齐。两色定向回归核对无需手动滚回即可重试、名称及摘要完整、两次命令指向同一副本。988 项 Flutter 测试和改动文件严格 Dart 分析通过。[本机存储实现](../../apps/reader/lib/features/extensions/extensions_page.dart) · [组件回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

修正版 Flutter 3.50.0 release 的 `main.dart.cdf5df95.js` SHA-256 为 `cdf5df955508abfb8f731f2598a14cf5aca11bf6b782652d47b6aa1e877cdc81`，同一源码重新构建的运行时宿主为 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。内置浏览器两色分别通过官方 Wrangler 隔离入口交付并核对 HTTP 字节。临时验收脚本记录真实宿主结果并暂扣成功回执 7 秒。每次先实际下载 xkcd 1.6.1 和 Komiic 1.6.11，在另一个同源标签打开英文 xkcd 热门以持有 Web Lock，再从存储展开诊断并滚动到清理入口。[验收入口](../../apps/api/test/README.md#api-验证)

两色短横屏 844×390 中，操作前 xkcd 清理按钮为 `[704,49,810,106)`。正式宿主返回 `STORAGE_BUSY`，两个副本仍为 6.068 MiB，页面自动定位到前缘对齐的重试，按钮边界均为 `[20,139,824,196)`。先前基线的同一重试按钮为 `[352,152,492,209)`。关闭占用标签后，两色均用新请求重试 xkcd 的同一 SHA-256（`d4c7fd8c83a3c5cdd43cb9de2a2a1ebcbbbb793e711794b4dfc13fbb21a60536`）。在 360×800 等待成功回执期间，两个清理动作和重新读取均报告 `aria-disabled="true"`，列表继续显示两份副本。确认后只剩 Komiic 的 1.790 MiB，在新文档独立读回。

随后明确清理 Komiic，两色均显示 `0 个副本 · 0 B`。再次从已安装的图源打开 xkcd 取得真实热门列表，另一文档读回仅 xkcd 的 4.278 MiB。每色设置、漫画设置、书架、分类、作品、书签和进度七路权威响应在全流程前后逐字节一致，账户 revision 均为 4，两个扩展仍为账户已安装。临时标签与回环服务已关闭，视口已复原。真机、Web 系统大字号、Mihon 11.04 的外层失败提示继续待验。[逐状态清单](mihon-state-coverage.md)

## Cupertino 转场的底页位置

2026-11-20，用固定 Flutter 3.50.0 的应用首页在 800×600 视口复现底页位移。开启减弱动态后，进入设置详情的第 60ms，旧版首页从 `[0,0,800,600)` 移到 `[-83,0,717,600)`。已打开的 Sheet 开启减弱动态后，首页仍为 `[33.4,42,766.6,591.9)`。从减弱动态切回常规设置时，原本静止的首页仍保持全宽。

底页现在在构建转场时读取系统偏好。首页在减弱动态的页面进入与返回中保持原位。Sheet 打开后，两种方向切换偏好均更新底页，Sheet 的位置保持稳定，减弱动态退出过程中底页保持原位。常规页面的底页过渡继续使用 Cupertino 组件，普通手势的底页位移与前景侧滑成比例。浅深色 Sheet 顶部空隙的背景色也通过复验。963 项 Flutter 回归与严格 Dart 分析通过。正式 Web 和 Karuyomi 原生的现场转场待验。[共享路由](../../apps/reader/lib/widgets/app_routes.dart) · [底页回归](../../apps/reader/test/theme/app_backdrop_test.dart)

## 作品详情导航栏的减弱动态

2026-11-20 至 21 日，在 macOS Flutter 3.50.0 的应用壳层，以 390×844 逻辑视口、顶部 24 和底部 20 的安全区运行浅深两色。用测试漫画源从「浏览」实际点开作品详情，再通过导航栏返回。组件截图采用 Arial Unicode 测试字形和应用打包的 Cupertino 图标。基线 `b189199` 在开启减弱动态时，正文原位淡入淡出，铺在转场叠层上的作品标题仍横向移动。

| 采样时刻          | 基线的叠层标题横坐标 | 修正后的标题横坐标 |
| ----------------- | -------------------- | ------------------ |
| 进入详情后 180 ms | `[224.8,351.0)`      | `[131.9,258.1)`    |
| 点按返回后 180 ms | `[234.0,360.2)`      | `[131.9,258.1)`    |

两色标题布局边界一致。修正后的坐标与详情稳定后相同，页面导航栏随正文淡入淡出。常规动效的进入、稳定、退出和返回四个采样点共八对 PNG 逐字节相同。回归通过两种设置下的原页面返回与零账户业务写入。动效设置在独立的转场层读取，章节批量面板打开时复用当前详情。已有丢确认用例核对面板重试发送同一请求原文，并保留原清单剩余项。正式 Web 和原生现场转场待验。[共享路由](../../apps/reader/lib/widgets/app_routes.dart) · [源到详情的回归](../../apps/reader/test/browse/source_browse_page_test.dart) · [章节恢复回归](../../apps/reader/test/browse/chapter_read_navigation_test.dart)

## 正式 Web 的常规 Cupertino 转场

2026-11-21，使用 `b7c581f` 的本地 Flutter 3.50.0 release Web、Vite 宿主及官方 Wrangler 验收入口。HTTP 交付的 `main.dart.4cd446c4.js` 和 `runtime/host.js` 均与本次构建逐字节一致，SHA-256 与 `423639a` 的复验相同。内置浏览器视口为 360×800，设备像素比为 2，页面报告 `prefers-reduced-motion: no-preference`。两色均以显式主题保存后验收。[构建字节](#扩展材料读取失败的正式-web-复验) · [验收入口](../../apps/api/test/README.md)

| 入口与返回                | 浅深双主题的正式 Web 观测                                                                                                                                                         |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 设置目录 ↔ 外观与主题     | 窄屏详情横向入场，返回原设置目录。底部三个标签保持可见，设置保持选中。                                                                                                            |
| 英文 xkcd 热门 ↔ 作品详情 | 两色均实拍正文和标题的滑入。分别用导航栏按钮和左缘拖动返回，落点均为原热门列表。两色实际刷新同一作品，章节数保持 3,325，首项仍为 3326。                                           |
| 书架 ↔ 管理分类           | Sheet 自下滑入，书架作为底页。可见阶段的上缘依次为浅色约 503、244、94、64，深色约 503、241、97、64 逻辑像素。点「完成」后两色上缘均从约 64 移到 361，随后离开视口，回到同一书架。 |
| 已安装 xkcd ↔ 卸载确认    | 两色均拍到系统确认框在扩展详情上出现和淡出。稳定框包含原版本、仓库、影响范围和动作。取消返回同一已启用构建。                                                                      |

采样按浏览器输入返回后的顺序记录，坐标从 JPEG 量测。浅色首次拖动的起始帧仍在详情进场中，画面停留在详情。待进场完成后从同一位置拖动，实际返回原列表。图组 `karuyomi-b7c581f-xkcd-page-transitions.png`、`karuyomi-b7c581f-category-sheet-transitions.png` 和 `karuyomi-b7c581f-uninstall-transitions.png` 各保留两色的过程帧和稳定帧。

两色取消卸载前后的设置、书架和分类，各自三路独立 HTTP 读回逐字节一致。验收审计的 56 条请求全部正常完成，五条业务写入对应四次显式主题保存和一次 xkcd 安装。六个文件的 164 项 Flutter 定向回归通过，含页面、导航栏和弹层的减弱动态及关闭动画。Flutter 3.50.0 的 Web 引擎将系统减弱动态同时映射到两个动画标志。系统开启该偏好时的 Web 实拍和原生现场转场仍待验收。[共享路由](../../apps/reader/lib/widgets/app_routes.dart) · [底页回归](../../apps/reader/test/theme/app_backdrop_test.dart) · [作品详情回归](../../apps/reader/test/browse/source_browse_page_test.dart)

### 正式 Web 的减弱动态媒体查询复验

2026-11-21，以 `539ec0c` 的 Flutter 3.50.0 release、官方 Vite 和 Wrangler 验收入口复验浅深两色。实际 HTTP 的 `main.dart.cdf5df95.js` 与 `runtime/host.js` 分别为 `cdf5df955508abfb8f731f2598a14cf5aca11bf6b782652d47b6aa1e877cdc81`、`e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`，与正常产物逐字相同。内置浏览器实际报告 `no-preference`。两种条件使用隔离页面在 Flutter 启动前控制原生 `MediaQueryList.matches`，运行切换时向同一查询分发标准 `MediaQueryListEvent`。每轮由 Flutter 的实际浏览器监听处理。浅深口径为 360×800 逻辑像素、可信浏览器输入、输入后针对语义节点采样约 570 ms，并核对捕获的画面。[共享路由](../../apps/reader/lib/widgets/app_routes.dart) · [验收入口](../../apps/api/test/README.md)

| 入口与标记                          | 常规模式的首个标记到稳定位置                                     | 减弱动态的首个标记与稳定位置                                  |
| ----------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------- |
| 设置 → 外观与主题，返回按钮         | 浅色从 `x=345`、深色从 `x=354` 滑到 `x=0`                        | 两色均固定为 `[0,0,66,44)`                                    |
| 英文 xkcd 热门 → 作品详情，章节工具 | 浅色从 `x=149`、深色从 `x=164` 滑到 `x=16`，常规标题也记录到移动 | 两色章节工具均固定为 `[16,415,344,459)`                       |
| 书架 → 管理分类，「完成」           | 两色均从 `y=768` 移到 `y=64`                                     | 两色均固定为 `[300,64,344,108)`                               |
| 已安装 xkcd → 卸载确认，「取消」    | 两色左缘从 `x=5` 移到 `x=45`，宽度从 175 收至 135                | 两色均固定为 `[45,457,180,514)`，每色的早期和稳定截图逐字相同 |

常规退出采到页面和 Sheet 的离场，以及卸载确认维持原位置的淡出。启用减弱动态后，四个入口均直接返回原页面，采样中旧界面没有离场位移。详情从左缘 `(4,300)` 拖到 `(328,300)` 也在两色返回同一英文图源热门，原 xkcd 仍在书架。分类 Sheet 和卸载确认各保持打开，从两种方向切换偏好，稳定标记坐标一致。切换到减弱动态后，关闭时旧控件只可能留在输入后的头一个采样点。切回常规后，Sheet 的「完成」滚出视口，最后采样约为浅色 509 ms、深色 511 ms。两个确认框的「取消」均保留约 379 ms 后返回同一已启用扩展。时间是浏览器采样值。[底页与弹层组件证据](#cupertino-转场的底页位置) · [导航标题组件证据](#作品详情导航栏的减弱动态)

测试前已确认每色各一次实际 xkcd 安装和同一收藏。七路设置、漫画设置、书架、分类、作品、书签及进度在全流程前后逐字节相同，账户 revision 均为 3。211 项定向 Flutter 测试通过。验收标签及服务已关闭，内置浏览器视口已复原。操作系统偏好开启后的 Web 与原生现场、其余转场变体仍待验收。[逐状态清单](mihon-state-coverage.md)

## Mihon 迁移源加载的双主题实拍

2026-11-20，固定 Mihon 0.21.3（`feadad5e`，versionCode 39）在 Android API 36、720×1600、320dpi 的隔离副本中使用显式 DEFAULT 浅深色，三项系统动画倍率均设为 0。在原有小书架连续点击「浏览」及「迁移」时，两色先拍到迁移帮助图标与短加载弧，当时选中线仍在「图源」。清除隔离系统的内核页缓存后，浅色还取得选中线和加载环同帧的画面。

为配齐同数据的两色主图，在停止应用后的隔离 SQLite 副本，用原有已收藏样本的源 ID、状态等字段生成 48,000 条唯一 URL 的测试收藏，全部放入同一个已有非默认分类。两个原收藏保留，`quick_check` 返回 `ok`。关闭隔离设备的 Wi-Fi 和移动数据。每次冷启动到书架后执行 `sync` 并清除隔离设备的内核页缓存，再用系统录屏和真实触控，从 `[504,1460]` 的浏览入口切到 `[600,312]` 的迁移标签。选中的浅色和深色录屏在两次输入命令间分别加入 25ms、65ms 的等待。

| 主题 | 录屏帧与相对时间 | 加载指示逻辑边界    | 空白内容背景与环色采样 |
| ---- | ---------------- | ------------------- | ---------------------- |
| 浅色 | 第 4 帧，0.572s  | `[160,420,200,460)` | `#FDFAFE` / `#0056C9`  |
| 深色 | 第 6 帧，0.702s  | `[160,420,200,460)` | `#191B1D` / `#B0C3FF`  |

两张主图均显示迁移标签选中、右上帮助和中间加载环。像素由原录屏解码量测，环色取有色区域内出现频率最高的 RGB。随后两色均出现 MangaDex 与 xkcd 列表，xkcd 的计数均为 48,001。20.01 登记为浅深主图，Mihon 覆盖达到 **166/170（97.6%）**。Karuyomi 跨版本主图为 **168/171（98.2%）**。隔离副本和专用 ADB 已关闭。当前内置浏览器控制端仍无活动页面，正式 Web 待验。[逐状态清单](mihon-state-coverage.md) · [迁移状态](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/ui/browse/migration/sources/MigrateSourceViewModel.kt) · [源计数查询](../../vendor/mihon/data/src/main/sqldelight/tachiyomi/data/manga.sq)

## 扩展排队与短屏取消

2026-11-20，用固定 Mihon 0.21.3（`feadad5e`，versionCode 39）的原 APK 和隔离 Android API 36 模拟器复验。画面为 720×1600、320dpi，三项系统动画倍率均为 0。通过应用原有入口登记 Keiyoushi 后，搜索并选择同一条 Komga 1.6.76。目录就绪后关闭隔离设备的 Wi-Fi 和移动数据。原应用先发布 `Pending`，检查缓存目录后发布 `Downloading`。直接重试时，该目录的存在检查耗时 71 微秒。为采到实际排队画面，在每轮点击重试时只延长应用进程的下一次缓存目录检查，观测耗时为浅色 4.000913 秒、深色 4.001311 秒。[Keiyoushi 仓库入口](https://github.com/keiyoushi/extensions#usage) · [Mihon 安装状态](../../vendor/mihon/app/src/main/java/eu/kanade/tachiyomi/extension/util/ExtensionInstaller.kt)

两张 08.07 主图及对应 UI 树均显示 Komga、Keiyoushi、1.6.76、图标上的旋转进度、「等待中」与「取消」。双主题的等待文字逻辑边界均为 `[126.5,322,161,338)`，取消节点为 `[308,300,332,324)`。两轮在检查完成前约 1.1 秒点第一次取消，同一行先恢复安装入口，检查返回后又显示「下载中」。第二次取消后，Komga 搜索行全部回到可安装，系统包列表无 Komga。该转换的证据来自受控延迟条件。隔离模拟器和专用 ADB 已关闭。Mihon 双主题主图为 **167/170（98.2%）**。[逐状态清单](mihon-state-coverage.md)

Karuyomi 的扩展目录组件回归在浅深两色、360×480 和两倍字号下复现长扩展名称被截断。修正后名称自然换行，名称和版本可在反馈区内滚动，滚动前后均可点取消。发出取消时回到阶段标题，准确反馈「正在取消准备」，同一构建的安装入口等到取消确认才恢复。测试核对原准备 ID、迟到的准备响应和零账户提交。292 项相关 Flutter 回归通过，最终改动文件通过严格 Dart 分析。Karuyomi 跨版本双主题主图为 **168/171（98.2%）**，正式 Web 待验。[扩展目录界面](../../apps/reader/lib/features/extensions/extensions_page.dart) · [准备与取消回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

## 图源空态与扩展入口

2026-11-20，在只读 Android API 36 参考副本运行原 Mihon 0.21.3 安装包（`feadad5e`，versionCode 39），720×1600、320dpi，系统动画倍率均设为 0。先把隔离应用的 `source_languages` 设为空集合，实际仍看到本地图源。再在同样数据的 `hidden_catalogues` 加入本地图源 ID 0，固定发行版在浅、深 DEFAULT 主题均从「浏览」进入真正的图源空态。两个 UI 树均只有一条「没有图源」，其逻辑边界均为 `[151.5,460.5,209,480.5)`，页面背景分别采样为 `#FEFBFF`、`#1B1B1F`。表情为该画面的原有装饰，位置比较使用固定文案。[图源分支](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/browse/SourcesScreen.kt) · [筛选顺序](../../vendor/mihon/app/src/main/java/eu/kanade/domain/source/interactor/GetEnabledSources.kt)

两种主题点按同一「插件」页签均实际进入含 MangaDex 与 xkcd 的目录，点回「图源」稳定返回空态。测试偏好逐字节还原后，原目录重新出现本地图源、MangaDex 和 xkcd。专用 ADB 与模拟器均已关闭。主图 07.03 登记成对，Mihon 参考覆盖为 **168/170（98.8%）**。[逐状态清单](mihon-state-coverage.md)

Karuyomi 的历史正式 Web `1e50a82` 已取得 07.K2 两色原图。用固定 Flutter 3.50.0、原 `CatalogPage` 和空安装夹具，在两种主题复现旧版说明紧接筛选区。360×800 组件中，语言筛选下缘为 200，原 `1beb148` 的空态标题上缘为 296。修正以可用内容区居中，标题上缘为 477.5，两色一致。量测使用 Arial Unicode 测试字体，组件窗口直接包含 Cupertino 页标题，Mihon 则包含 Android 系统区与底部标签栏。

360×480 和两倍字号的两色复验中，滚动后的「前往扩展」边界均为 `[92.8,370,267.2,448)`，实际点按进入扩展。组件回归核对安装后回到同一漫画源分段可看到新目录，筛选无匹配继续提供清除，未解析的已安装版本继续提供恢复入口。27 项相关 Flutter 回归通过。当时的 Karuyomi 跨版本主图覆盖为 **168/171（98.2%）**。[目录布局](../../apps/reader/lib/features/sources/source_directory.dart) · [入口与布局回归](../../apps/reader/test/sources/catalog_language_filter_test.dart)

2026-11-21，`b7c581f` 正式 Web 在同一尚未安装扩展的测试账户复拍 07.K2。360×800 下，「尚无漫画源」在两色的字形范围均约为 `[140,455,222,471)`，与 Mihon 的空态文案同处横向中轴，实际页面保留 Cupertino 的语言筛选和扩展动作。JPEG 背景采样为浅 `#F3F2F7`、深 `#000000`。两色均点「前往扩展」，再点「漫画源」返回。返回后空态中心采样区的亮度差超过 3 的像素数为 0。新版两色图替代 07.K2 的历史主图，计数维持 **170/171（99.4%）**。[逐状态清单](mihon-state-coverage.md) · [正式 Web 构建](#正式-web-的常规-cupertino-转场)

## Mihon 源浏览追加

2026-11-20，固定 Mihon 0.21.3 在 720×1600、320dpi 的只读参考模拟器中，两种显式主题均从相同 MangaDex 热门列表滑到第一页末尾。暂扣实际 MangaDex API 的下一页 CONNECT 时，「Bakebeta!」和「Kurenai-san wa Yoru wo Kurenai」等原封面留在列表内，旋转进度出现在最后一行下方。进度的双主题辅助边界均为 `[160,712,200,752)` 逻辑像素。放行后继续滚动，两色均出现新的「Seifuku Kanojo」与「Honey Creep」。原图/XML 成对登记在 12.08。[逐状态清单](mihon-state-coverage.md)

旧 Karuyomi 把追加指示放在固定工具区，组件回归复测发现等待时首张封面下移 53 逻辑像素。现在用滚动区底部的 Cupertino 指示及短说明承接追加，固定工具区保持高度，原网格及视口内封面位置继续可见。失败和重试也在列表底部。50 项源浏览、目录与迁移定向 Flutter 回归通过，覆盖同页等待位置、成功接续及失败后原页重试。新版正式 Web 追加流程继续验收。

## Mihon 迁移空书架

在同一只读参考实例依次移出 xkcd 和 One Piece 两项测试收藏。两色在「浏览」的「迁移」页签均显示「书架为空」，引导仍可见。空态说明的辅助边界同为 `[151.5,466.5,209,486.5)` 逻辑像素，随机表情只用于确认空态。切回「图源」实际返回有内容的目录。原图和 XML 登记为 20.02，冷启动与标签切换视频未观察到独立加载主画面，20.01 继续采集。Karuyomi 的迁移入口从已选作品进入，空书架路径已有独立状态记录。

源码复核确认，Mihon 的在线语言筛选只列在线源，本地图源也没有「禁用」动作。关闭在线语言后的目录仍含本地图源，07.03 继续保留为待验。两组新增参考将 Mihon 双主题主图覆盖推进至 **160/170（94.1%）**，附加原图和视频保存在 `.local/mihon-reference/gallery-and-cover-20261120/`。已恢复代理，关闭隔离模拟器、专用 ADB 和中继。[逐状态清单](mihon-state-coverage.md)

## 失败重试与卸载确认的短屏复验

2026-11-20，复看固定 Mihon 08.10 和 09.03 的浅深参考。下载失败后仍在原 Komga 1.6.76 行显示重试。MangaDex 的系统卸载框保留目标与两个动作，两色的框体逻辑范围均为 `[25,340.5,335,503.5)`。Karuyomi 在原反馈区保留精确构建的重试，并用 Cupertino 确认框呈现账户卸载。[逐状态清单](mihon-state-coverage.md)

在 macOS Flutter 3.50.0 组件测试中，以受控运行时拒绝和隔离账户复拍浅深主题，视口为 360×800 常规字号与 360×480 两倍字号。最后经实际的「浏览 → 扩展」进入，使用测试字形环境、本机 CJK 字体及顶部 24、底部 20 逻辑像素的安全区。量测以逻辑像素记录。

| 状态           | 360×480 两倍字号的旧版布局                                                                    | 修正后的两色量测                                                                                   |
| -------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 08.K9 准备失败 | 独立组件的原因首字在 `y≈466`，反馈区在 `y=262` 截止。首次修正从浏览入口进入时第二行仍被裁掉。 | 原因位于 `[32,123,328,193)`，重试位于 `[16,207.2,344,265.2)`。滚动至版本和仓库后按钮维持同一位置。 |
| 09.K6 卸载确认 | 长标题把账户影响推至 `y=614`，超出弹层内容区                                                  | 账户影响位于 `[60,130,300,200)`。取消与确认可在首屏及滚动后点击。                                  |

从完整导航进入后，失败原因直接排在反馈卡首行，重试按钮采用内容高度与 Cupertino 的最小点击尺寸。准备失败时账户零提交，点重试以同一仓库、包和构建再次准备，成功后只提交一次安装。本机副本重试成功后账户写入计数无增量。打开卸载框与取消均为零新增提交，取消回到原详情，明确确认只新增一次卸载。常规字号下，Cupertino 框体宽 270，两按钮并排，确认使用系统红。两倍字号下按钮由 Cupertino 弹层纵排。[扩展与卸载回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

两倍字号的完整页面组件截图另观察到底部标签文字与图标相叠。内置浏览器控制端未取得当前聊天的活动页面，底栏、正式 Web 字形、转场和这两组双主题主图待验。Mihon 参考为 **168/170（98.8%）**，Karuyomi 跨版本主图为 **168/171（98.2%）**。[交付进度](../plan/mihon-cupertino-fidelity.md)

## 底栏大字号的横竖屏复验

2026-11-20，复看固定 Mihon 0.21.3 的 01.01 与 01.02 浅深原图。在 360×800 竖屏，底栏「浏览」图标像素范围为 `y=[720,740)`，标签为 `y=[753.5,767.5)`。800×360 横屏的对应范围为 `y=[280,300)` 与 `y=[313.5,327.5)`。两种主题、横竖两向的图标与文字均间隔 13.5 逻辑像素，Android 系统手势区在底栏内容之下。[参考状态](mihon-state-coverage.md#0106导航书架分类)

Karuyomi 在 macOS Flutter 3.50.0 中从真实应用壳层点按书架、浏览和设置。组件以 360×480、800×360 双主题采样，顶部和底部安全区分别为 24、20 逻辑像素。使用应用打包的 Cupertino 图标和本机 Arial Unicode 测试字形。表中高度均不含系统安全区，像素间距取底栏「浏览」图标与标签的可见像素边缘。

| 字号 | 原底栏高度与图标布局高度 | 修正后底栏高度与图标布局高度 | 修正后图标到标签的像素间距 |
| ---- | ------------------------ | ---------------------------- | -------------------------- |
| 1×   | 50 / 30                  | 50 / 30                      | 6.5                        |
| 2×   | 50 / 19                  | 64 / 30                      | 8                          |
| 3×   | 50 / 6                   | 77 / 30                      | 10.5                       |

固定高度使图标仍按 30 绘制，原两倍与三倍字号的图标和文字在扫描行中相连。修正后，底栏随主题字体的实测行高增高，两倍和三倍字号均出现独立的图标与文字像素区。四组常规字号前后 PNG 逐字节一致。新增回归在手机竖屏、手机横屏和平板双主题核对完整图标、标签边界、选中状态和实际点按，也保留现有草稿与焦点回归。之前的扩展准备失败在完整浏览入口仍通过短屏两倍字号测试。[壳层布局](../../apps/reader/lib/main.dart) · [导航回归](../../apps/reader/test/widget_test.dart)

内置浏览器控制端仍未取得活动页面，本轮证据来自 Flutter 组件。正式 Web、真机呈现、未取得的主图与最终像素验收仍待完成。Mihon 双主题参考 **168/170（98.8%）**，Karuyomi 跨版本双主题主图 **168/171（98.2%）**。[逐状态清单](mihon-state-coverage.md)

## 底栏键盘焦点与切换

2026-11-20，在 macOS Flutter 3.50.0 组件中从真实应用壳层进入书架、浏览和设置。`b08d698` 在两倍字号、浅深主题下分别连续按 Tab 12 次，三页的任一底栏入口都未获得焦点。修正后可从正文 Tab 到带有名称、点击动作及选中语义的底栏项。焦点落在「浏览」而书架仍为当前页时，光环出现在浏览图标外，书架保留选中色。[应用壳层](../../apps/reader/lib/main.dart)

360×480 竖屏的浅深组件图使用 Arial Unicode 测试字形和应用打包的 Cupertino 图标。焦点环范围均为 `[158,396,202,429)`，图标布局为 30×30。实际按 Enter 进入浏览，按 Tab 前往设置，改为 800×360 后按空格打开设置，再以 Shift+Tab 和数字键盘 Enter 返回书架。焦点跨激活及视口变化保持可用。已聚焦时用鼠标点设置，焦点和选择一同移动，随后空格仍在设置。触屏点浏览后焦点环收起。正式 Web 键盘和画面待验。[键盘与触控回归](../../apps/reader/test/widget_test.dart)

## 扩展准备失败的 HTTP 复验

2026-11-20，取 `ba3b31f` 分支 CI 的正式 Web 归档 `14634052318`，在下载边界校验 16,328,071 字节和 SHA-256 `dd9c27c5e13da914051e6de084cbed6aa470f443565ebbe3f2fa49bcdabe68f6`。在临时目录用 Vite 装配既有扩展快照，启动官方 Wrangler harness 与独立 D1。HTTP 实际取得页面、扩展索引中的两个构建及 bootstrap JSON。交付的 `main.dart.59f3fcda.js` 与原 CI 归档逐字节相同。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44746445435) · [验收入口](../../apps/api/test/README.md)

同一 xkcd 构建清单先返回 200。由 harness 标准输入执行 `editor fail-read extension-manifest` 后返回 503，执行 `editor pass extension-manifest` 后恢复 200 且清单逐字节一致。服务正常退出，审计中的三条记录均为 GET。把仍可用的本地预览交给当前 Codex 聊天时，面板请求排队，控制端仍无活动页面。08.K9 和 09.K6 正式双主题主图待验。Mihon 双主题参考 **168/170（98.8%）**，Karuyomi 跨版本双主题主图 **168/171（98.2%）**。[逐状态清单](mihon-state-coverage.md)

## 正式 Web 的扩展准备失败与卸载确认

2026-11-21，使用 `b189199` 分支 CI 归档 `14644374062`，校验下载的 16,329,820 字节及 SHA-256 `c7147db7b1230bf68924af6bb8a19ee66c4d8ccc3de7fa89eb229da5594f06a9`。在临时目录通过正式 Vite 资产配置装配扩展快照，用官方 Wrangler harness 启动独立 D1。装配后的 `main.dart.e2536a91.js` 与 `runtime/host.js` 均与归档逐字节相同，运行时宿主另经 HTTP 交付复核。通过内置 Browser 插件建立临时标签页，设置 360×800 视口，在测试账户分别保存显式浅色和深色。[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/44766161584) · [验收入口](../../apps/api/test/README.md)

- 08.K9 在两色实际点击同一 xkcd 1.6.1 的安装，两次清单 GET 均返回 503。画面保留扩展、版本、默认仓库和「重试准备」。正文只有「操作未完成，请重试。」，静态材料的读取失败原因未显示，主图仍缺必要信息。恢复 200 后点原重试，产生一次安装写入并确认本机产物已准备。运行时把该 HTTP 失败编码为 `runtimeLost`，扩展界面落入通用文案。[逐状态清单](mihon-state-coverage.md) · [静态材料读取](../../packages/runtime-host/src/verified-loader.ts) · [扩展操作反馈](../../apps/reader/lib/features/extensions/extensions_controller.dart)
- 09.K6 在两色实际从已安装详情打开卸载确认。中心弹层同屏显示 xkcd 1.6.1、默认仓库、将从账户移除、保留数据的范围，以及系统红的「确认卸载」。浅色底页仍有安装回执，深色是重新进入的详情。浅色点「取消」、深色按 Enter 取消，均返回同一已启用详情。两次取消各用独立 API 读取设置、书架和分类，三路响应与操作前逐字节一致。[Mihon 确认参考](#mihon-确认面板与扩展卸载) · [逐状态清单](mihon-state-coverage.md)

四张 JPEG 核对了真实显示与语义。完成审计记录三次显式主题保存和一次安装，卸载写入为零。浏览器视口已恢复，临时标签和本机验收端已关闭。Karuyomi 跨版本双主题合格主图为 **169/171（98.8%）**，剩余 08.K9 的具体原因和 27.K1 原生未连接。Mihon 参考仍有两组待采。[逐状态清单](mihon-state-coverage.md)

## 扩展材料读取失败的正式 Web 复验

2026-11-21，使用 `423639a` 的 Flutter 3.50.0 release Web、Vite 宿主和资产构建，由官方 Wrangler harness 服务本地独立 D1。实际通过 HTTP 交付的文件与构建逐字节一致。`main.dart.4cd446c4.js` 的 SHA-256 为 `4cd446c49b3d314ebe8617159166db53f62162fa74b9ad797b0baec23d77f1ec`，`runtime/host.js` 为 `e7f51512c3993844d655b6d7c58d05fdc4cb9c40109a23a97d810b8537be6c32`。内置浏览器视口为 360×800，测试账户保存显式浅色和深色。[验收入口](../../apps/api/test/README.md)

对照 Mihon 下载失败后在原扩展上重试的流程。在 Karuyomi 两色分别点击安装 xkcd 1.6.1，受控故障让同一个构建清单两次返回 HTTP 503。画面都显示「无法从仓库读取扩展材料。」，并保留扩展、版本、默认仓库和「重试准备」。宿主用独立的 Protobuf 错误代码表示读取失败，并照常传递取消信号。[Mihon 失败重试](#失败重试与卸载确认的短屏复验) · [静态材料读取](../../packages/runtime-host/src/verified-loader.ts) · [扩展操作反馈](../../apps/reader/lib/features/extensions/extensions_controller.dart)

两次 503 后独立读回账户设置，xkcd 仍未安装。恢复响应后点击原「重试准备」，同一清单返回 200，账户读回为同一构建已启用，界面显示本机产物已准备。审计为三次显式主题保存和一次安装写入。取得 08.K9 两张主图后，Karuyomi 跨版本双主题合格主图为 **170/171（99.4%）**，剩余原生未连接 27.K1。浏览器视口已恢复，临时标签和本机验收端已关闭。[逐状态清单](mihon-state-coverage.md)

## 仓库录入与短屏键盘

2026-11-21，以 Mihon 10.02 的地址输入、取消和提交为对照，在 Flutter 3.50.0 的仓库管理组件里实际打开「添加仓库」。用两倍字号和模拟键盘占位核对浅深色。基线 `b2be740` 在 844×390 视口、底部占用 234 逻辑像素时，滚到「只读预览」仍无法点按。320×560 视口、底部占用 310 时，刚打开键盘便挤出预览动作，需另滚动动作区。[Mihon 与 Karuyomi 逐状态清单](mihon-state-coverage.md)

现在地址和名称通过共享 Cupertino 编辑 Sheet 的表单滚动区录入。按下表量测两色一致的按钮边界。横屏先在键盘上方编辑地址，滚到名称之后仍可直接预览。竖屏的两个字段均可点按。实际点「只读预览」进入独立确认步骤，取消后回到仓库列表，零账户写入和本机准备。模拟预览失败后保留原地址、名称和错误，修复读取后可以原样重试。[仓库界面](../../apps/reader/lib/features/extensions/extensions_page.dart) · [键盘与重试回归](../../apps/reader/test/extensions/additional_repositories_test.dart)

| 视口与键盘上沿 | 修正后的「只读预览」逻辑纵坐标 |
| -------------- | ------------------------------ |
| 844×390，156   | `[31.2,75.2)`                  |
| 320×560，250   | `[44.8,88.8)`                  |

983 项 Flutter 测试和严格 Dart 分析通过。[逐状态清单](mihon-state-coverage.md)

同日用 `423639a` 的本地正式 Web 补验仓库录入与地址校验。360×800 浅深两色均从仓库管理打开同一编辑 Sheet，输入 `http://example.invalid/` 后按 Tab，把焦点移到名称并输入「复验仓库」。点「只读预览」后显示 HTTPS 和目录路径要求，两项草稿仍可编辑。取消返回仓库管理，目录仍显示最近的校验错误。两色审计均无仓库写入，浅色取消前后账户设置逐字节一致。两张稳定错误帧为 `karuyomi-423639a-repository-url-rejected-light.jpg` 和 `karuyomi-423639a-repository-url-rejected-dark.jpg`。实机软键盘以及新版 Web 的有效地址确认转换继续验收。[逐状态清单](mihon-state-coverage.md)

## 首次连接的短屏复验

2026-11-20，复看固定 Mihon 0.21.3 的 02.01 空书架和 26.01 设置浅深原图。360×800 的空书架「书架为空」和「入门指南」逻辑纵坐标分别为 `[398.5,418.5)` 和 `[478.5,498.5)`，两色一致。Karuyomi 的书架空态把提示和前往浏览放在剩余内容区中央。常规字号组件量测下，提示为 `[367,390)`，入口为 `[419,463)`。首次服务连接借鉴设置主项与辅助说明的层级。[参考状态](mihon-state-coverage.md)

在 macOS Flutter 3.50.0 的真实应用壳层，以浅深主题、顶部 24 和底部 20 的逻辑像素安全区复拍。截图使用 Arial Unicode 测试字形与应用打包的 Cupertino 图标。修正前，两倍字号下三处入口需要先滚动。以下均为首屏纵坐标的逻辑像素范围。

| 视口与操作           | 旧版        | 修正后          |
| -------------------- | ----------- | --------------- |
| 360×480 书架去浏览   | `[530,608)` | `[281,343)`     |
| 360×480 浏览填写地址 | 首屏下方    | `[281,343)`     |
| 360×480 设置连接服务 | `[382,460)` | `[212,274)`     |
| 800×360 书架去浏览   | `[393,471)` | `[203.5,265.5)` |
| 800×360 浏览填写地址 | 首屏下方    | `[203.5,265.5)` |
| 800×360 设置连接服务 | `[290,368)` | `[212,274)`     |

两倍字号竖屏正文下缘为 396，横屏为 276。三个入口均实际点按通过。首次连接页可同时看到状态和地址，地址框有独立的辅助技术标签。输入不满足 HTTPS 要求的地址后，原生地址校验触发系统红提示，保留原输入，账户请求为零。改成隔离测试服务的 HTTPS 地址后打开服务连接栏目，核对已确认身份和账号，账户业务写入为零。27.K1 的原生双主题主图及本次 Web 呈现待验。[服务设置回归](../../apps/reader/test/settings/settings_navigation_test.dart)

## 首次连接的等待和恢复

2026-11-20，在 macOS Flutter 3.50.0 的应用壳层，沿用测试字体与两倍字号，以浅深主题和 360×480、800×360 两种视口暂扣测试服务的首个 `/api/bootstrap` 响应。在基线 `718a606` 中提交地址会立即回到设置目录，查看等待或 403 需要重新打开「服务连接」。修正后仍在详情，原地址可见且等待期间只读，连接动作同时禁用。服务返回 403 后，错误在同一位置出现，地址恢复可编辑。

| 视口    | 「正在连接服务」 | 「访问被拒绝」 | 重试后的「已连接，身份已确认」 |
| ------- | ---------------- | -------------- | ------------------------------ |
| 360×480 | `[195,241)`      | `[195,241)`    | `[74,166)`                     |
| 800×360 | `[149,195)`      | `[149,195)`    | `[74,120)`                     |

表中为两色一致的逻辑纵坐标。横屏滚动后点按重试，状态行重新进入可见范围。测试服务返回 200 后在同页核对已确认的账号，账户业务写入为零。切换至「浏览」再回「设置」时进入设置目录。正式 Web 和 27.K1 原生双主题主图待验。[服务设置回归](../../apps/reader/test/settings/settings_navigation_test.dart) · [逐状态清单](mihon-state-coverage.md)

## Mihon 确认面板与扩展卸载

2026-11-20，复核固定 Mihon 0.21.3（`feadad5e`，versionCode 39）的六组双主题参考原图和对应 UI 层级，补计通用确认节点 30.04。原图为 720×1600、320dpi，以下把面板连续纯色区域的边界归一为 360×800 逻辑坐标。每组两色边界相同。五种应用内面板的表面为浅 `#FCF7FF`、深 `#292730`，系统卸载框两色均为 `#EEEDF4`。[逐状态清单](mihon-state-coverage.md)

| 调用点         | 面板边界 `[左,上,右,下)` | 画面中的对象、影响和动作                                               |
| -------------- | ------------------------ | ---------------------------------------------------------------------- |
| 04.02 书架移出 | `[20,288.5,340,555.5)`   | 已选作品留在底层。两项删除范围均未选，取消可用，确定禁用。             |
| 05.08 删除分类 | `[40,326.5,320,517.5)`   | 分类名在询问正文中，取消和确定分别可见。                               |
| 09.03 系统卸载 | `[25,340.5,335,503.5)`   | 标题标识 MangaDex，正文说明卸载应用，提供 Cancel 和 OK。               |
| 10.06 移除仓库 | `[20,306.5,340,537.5)`   | Keiyoushi 名称和完整仓库地址出现在正文，提供取消和确定。               |
| 21.01 迁移数据 | `[20,284.5,340,551.5)`   | 对象来自底层搜索结果，章节和分类为独立选项，提供显示作品、共存和迁移。 |
| 25.02 设置封面 | `[40,364,320,504)`       | 当前阅读图片作为底层上下文，确认询问是否使用此页，提供取消和确定。     |

另用只读隔离 Android API 36 实例复验。两种显式 DEFAULT 主题均从「浏览 → 插件 → 已安装 MangaDex 1.6.4 → 卸载」进入同一系统确认。详情表面分别为 `#FEFBFF` 和 `#1B1B1F`，Android 系统处于浅色。两次点 Cancel 都回到含名称、版本和卸载入口的原详情，安装包路径查询前后一致。两种主题也从「更多 → 分类」打开删除分类 `b` 的确认框，点取消后均回到「编辑分类」，`a` 和 `b` 仍在。

Karuyomi 旧版在扩展详情点击卸载时立即发起账户写入。现在用 Cupertino 确认框展示扩展、仓库、可取得的精确版本以及保留数据，并提供正常取消和系统红确认。明确确认时核对原仓库、构建及产物摘要。138 项定向 Flutter 回归覆盖扩展、目录与收藏源。两倍字号下 Tab 到取消再按 Enter 返回，打开与取消均零提交，确认后仅提交一次。不同仓库的旧选择会被拒绝。Mihon 双主题 161/170（94.7%）。Karuyomi 新登记 09.K6 后跨版本为 168/170（98.8%），新确认框的正式 Web 两色待验。[卸载回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

`e0d34d6` 的分支和 PR 检查通过。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44669250299) · [PR 检查](https://github.com/Wybxc/karuyomi/actions/runs/44669256983)

## 扩展详情的身份与字号

2026-11-20，复核 Mihon 0.21.3（`feadad5e`）的 09.01 双主题原图和 UI 树。720×1600、320dpi 录得的两色坐标一致，顶部为「插件信息」，正文按扩展名、包名、版本与语言、卸载、源列表排列。Karuyomi 用隔离 Flutter 3.50.0 组件测试从扩展目录进入详情，夹具采用同名 MangaDex 1.6.4、同一包名与六种语言。窗口为 360×800 逻辑像素，组件以 2× 输出，测试选用 iOS 控件分支并加载 Arial Unicode 字体。下面为各自窗口内的渲染逻辑坐标，Mihon 窗口含 Android 系统区域。[逐状态清单](mihon-state-coverage.md) · [详情源码](../../vendor/mihon/app/src/main/java/eu/kanade/presentation/browse/ExtensionDetailsScreen.kt)

| 元素           | Mihon 09.01           | Karuyomi `4120fff` | 调整后的 Karuyomi     |
| -------------- | --------------------- | ------------------ | --------------------- |
| 名称顶部       | 260，正文             | 10.5，导航栏       | 68，正文首组          |
| 包名顶部       | 292                   | 收在诊断           | 94                    |
| 版本顶部       | 324                   | 112                | 110                   |
| 首个源标签顶部 | 521                   | 380                | 389                   |
| 页面背景       | `#FEFBFF` / `#1B1B1F` | 分组背景           | `#F2F2F7` / `#000000` |
| 扩展摘要表面   | 与页面相同            | Cupertino 分组表面 | `#FFFFFF` / `#1C1C1E` |

较短的 Cupertino 正文分组保留身份在操作之前。两色用标准扩展图标、正文名称、次级元数据和系统红卸载动作。首次自动读取成功后，分组上缘在标准字号从 83 上移到 60，在两倍字号从 152 上移到 60。手动检查成功仍有完成提示，失败后的恢复入口经过回归核对。

360×480、两倍字号的 62 字扩展与单源夹具在浅深色均复现正文缺少完整名称，源行两行截断。修正后标题和源行自然增高，滚动可读到名称末尾及后续版本，真实目录入口和返回仍可操作。定向回归核对已确认构建、仓库和本机状态，进入与返回零账户提交。全量 965 项 Flutter 测试与严格 Dart 分析通过。组件实拍覆盖 360×800 和 360×480，测试环境的表单页脚使用回退字形，当前提交的正式 Web、原生和平台字体继续验收。[详情与摘要](../../apps/reader/lib/features/extensions/extensions_page.dart) · [扩展回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

## 扩展详情短屏的准备、取消与重试

2026-11-21，重新对照固定 Mihon 0.21.3 的 09.01 与 08.07、08.10 两色原图。09.01 使用已安装的 MangaDex 1.6.4，扩展名、包名、版本的逻辑上缘分别为 260、292、324。08.07 与 08.10 使用 Komga 1.6.76，在目录行内提供取消和重试，重试边界为 `[308,298,332,322)`。Karuyomi 正式 Web 使用默认目录的 MangaDex 1.6.1、61 种语言。360×800 候选画面中，两色名称的语义上缘为 68，名称、包名、版本、操作和源列表依次排列。页面和分组的 JPEG 采样分别为浅色 `#F3F2F7`、`#FFFFFF`，深色 `#000000`、`#1C1C1E`。取消和重试采用 Cupertino 蓝色按钮，失败原因使用危险色。[详情参考](#扩展详情的身份与字号) · [等待与取消参考](#扩展排队与短屏取消)

在 Codex 内置浏览器的 844×390 视口中，`b1a4d42` 滚到源列表末端后，准备面板与后续的失败面板均离开视口。`7925a84` 复用目录页的固定准备和失败区，源列表可独立滚动。浅深两色滚动前后的「取消准备」语义边界均为 `[16,141,828,198)`，两色均从列表末端点按取消，回到顶部可读到取消回执。重新进入详情后再安装，滚动到列表末端，清单 503 返回时「重试准备」仍在可见范围 `[16,132,828,176)`，同区显示扩展名、版本、仓库和失败原因。两色均在原处点按重试，源行随后启用，重开详情显示已安装和本机就绪。[界面实现](../../apps/reader/lib/features/extensions/extensions_page.dart) · [浅深回归](../../apps/reader/test/extensions/extensions_controller_test.dart)

两轮使用独立 Wrangler acceptance harness、测试身份和 D1。隔离副本用 `editor hold-read extension-manifest` 暂扣清单，并在现有 `fail-read` 的 503 分支增加临时 `hold-read-error`，等待同一 `waitForRelease` 闸门后才交付失败。滚动后通过 stdin 输入 `editor pass extension-manifest` 释放。正式 Flutter Web 的入口 SHA-256 为 `5b32dd9067b028202f658045a283bef0689e45bf68a4f6d80c7f78ff19324264`，入口及运行时 Host 与正常构建逐字节相同。本机 Wrangler 审计中，两色均在同一构建清单路径依次记录释放后的 200、受控 503、重试后的 200。取消和失败时账户、书架和分类快照相等。每色只有一次 UI 安装 POST，确认同一构建及其 bundle 哈希 `14c64a5cd87ce8bcfdafd7e6c8e55c0b3674bc60e660bb36afa2996acf43c0dc`，账户 revision 从 1 到 2，书架和分类内容相等。两个新的浏览器文档均读回已确认安装与本机就绪。验收服务已关闭。[验收入口与故障控制](../../apps/api/test/README.md)

两项新回归在修复前均因滚动后取消控件不可点而失败，修复后通过，覆盖失败因由、原构建重试、滚动位置及写入次数。全量 990 项 Flutter 测试、改动文件严格 Dart 分析和正式 Web release 构建通过。此轮覆盖默认文字比例的桌面内置浏览器，短屏大字的历史组件证据见上文。Karuyomi 原生、系统输入及生产继续待验。

## 仍需的证据

全部 ID 的参考画面和像素基准、布局复刻前后叠图、配色对比、自然 Cupertino 调整、最终多视口/亮暗/文字/输入核对、完整工程检查和真实业务验收仍待完成。Mihon 参考模拟器与 Karuyomi 原生现场验收分开记录；不使用已停止的真机流程填补本轮 Web 证据。
