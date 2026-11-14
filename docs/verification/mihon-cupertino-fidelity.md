# Mihon 布局与配色对照验证

2026-11-14，进行中。范围见[30 组页面矩阵](../design/mihon-cupertino-fidelity.md)，待办见[实施计划](../plan/mihon-cupertino-fidelity.md)。本轮尚未通过逐页像素、最终 Cupertino 或生产验收。

[逐状态截图状态机](mihon-state-coverage.md)现为参考采集进度入口，分别记录每个状态的浅/深图和缺口；本记录继续汇总实际工程与运行证据。`f0f648b` CI 的测试辅助代码大括号提示已在 `44fa79d` 修复；后者的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/43539865176)通过格式/严格分析，但 Flutter 测试有 2 项仍断言旧 Cupertino 颜色，636 项通过。已修正为当前 Mihon 颜色角色，待新 CI 复验；不能沿用 `b138967` 的成功结果代表后续提交通过。

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

原始 XML、PNG、下载及临时日志位于忽略目录 `.local/mihon-reference/`；参考采集命令使用固定模拟器 `adb -s emulator-5574 shell uiautomator dump` 与 `exec-out screencap -p`。终端访问 GitHub 发布附件需使用本机已配置的网络代理；最初的部分下载均未通过完整性门槛，不作为参考安装输入。

## 仍需的证据

全部 ID 的参考画面和像素基准、布局复刻前后叠图、配色对比、自然 Cupertino 调整、最终多视口/亮暗/文字/输入核对、完整工程检查和真实业务验收仍待完成。远端参考应用与 Karuyomi 原生现场验收分开记录；不使用已停止的真机流程填补本轮 Web 证据。
