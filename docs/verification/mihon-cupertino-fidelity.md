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

原始 XML、PNG、下载及临时日志位于忽略目录 `.local/mihon-reference/`；参考采集命令使用固定模拟器 `adb -s emulator-5574 shell uiautomator dump` 与 `exec-out screencap -p`。终端访问 GitHub 发布附件需使用本机已配置的网络代理；最初的部分下载均未通过完整性门槛，不作为参考安装输入。

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

## 仍需的证据

全部 ID 的参考画面和像素基准、布局复刻前后叠图、配色对比、自然 Cupertino 调整、最终多视口/亮暗/文字/输入核对、完整工程检查和真实业务验收仍待完成。Mihon 参考模拟器与 Karuyomi 原生现场验收分开记录；不使用已停止的真机流程填补本轮 Web 证据。
