# 全端统一 Cupertino UI

2026-11-13，用户确定 Web、iOS、Android 使用一套 Cupertino 界面。采用 Flutter 官方独立包 `cupertino_ui`，沿用已固定的 Flutter 3.50 / Dart 3.14、Riverpod generator、flutter_hooks 与 riverpod_lint。实施状态、范围与验收维护在[迁移计划](../plan/cupertino-ui.md)。

2026-11-13，Liquid Glass 曾发布到 Web；用户随后决定撤下该视觉方案，恢复本文的统一 Cupertino 风格。移除玻璃依赖、初始化、专用主题、着色器资源和实色选项，不保留两套外观实现。[库评估](liquid-glass-evaluation.md)与[终止记录](../plan/liquid-glass.md)作为历史依据；恢复交付见[迁移计划](../plan/cupertino-ui.md#恢复-cupertino)。这项决定基于用户对效果成本的取舍，不能描述为已完成严格能耗对照。

2026-11-13，用户进一步要求对照 Mihon 全部界面的布局与配色，先取得像素对照，再按 Cupertino 自然度量自适应；范围覆盖全部已有功能，缺失功能留作后续。[逐页对照设计](mihon-cupertino-fidelity.md)固定参考版本、30 组页面和色彩角色，实施状态见[计划](../plan/mihon-cupertino-fidelity.md)。本文继续约束正式交付的组件、路由和反馈。业务状态及最小必要信息沿用[扩展与浏览状态流程](extension-browse-ui-flow.md)，视觉调整不增加新的业务状态或第二套同步机制。

## 应用、主题与导航

- 应用根改为 `CupertinoApp`，中文及英文 delegates 使用 `GlobalCupertinoLocalizations.delegates`。主题使用 `CupertinoThemeData`、`CupertinoColors` 和在当前上下文解析的 `CupertinoDynamicColor`，统一替换 Material 的 `ThemeData` / `ColorScheme`。
- 服务端 `AppTheme` 继续表达跟随系统、浅色、深色；客户端分别映射到未指定 `brightness`、`Brightness.light`、`Brightness.dark`。主题切换仍由已确认设置驱动，未确认草稿单独展示，不引入平台分支或更改协议枚举。
- 保留书架、浏览、设置三个入口、一个根 Navigator，以及按当前入口挂载业务页的策略。窄屏使用 `CupertinoTabBar`；宽度达到 840 时，用 Flutter 布局和 `CupertinoButton` 组成带文字标签的侧栏，直接放在现有应用壳中。
- 不引入每个 tab 的嵌套 Navigator 或隐藏业务树。`CupertinoTabScaffold` / `CupertinoTabView` 会保留已访问的 tab；直接套用会改变当前退订与 Source 生命周期，不能只为导航外观采用。
- 普通页面使用 `CupertinoPageRoute`；`AppPageRoute` 仅集中实现系统减少动态效果时淡化、禁用动画时直接切换的既有无障碍策略。弹层直接使用官方 Cupertino 路由与返回值，不扩展为自建路由或设计系统。

## 控件与信息呈现

Cupertino 缺少某种组件时，先检查原交互是否仍有必要。可以通过调整页面结构和操作流程直接使用官方组件时，删除这项组件需求；仍有必要的交互再寻找成熟第三方库，核对维护状态、许可证、全端支持、键盘/无障碍与主题耦合后精确锁定依赖。两条路径以任务完成所需的最小信息与操作为判断依据，不逐个复刻 Material 组件，也不因控件缺失而丢掉业务状态或正确性约束。

当前选择：下拉改成少量选项菜单或可搜索选择页；复杂编辑进入 Sheet；临时通知改为操作附近的持续业务状态；分类与章节筛选用选择控件表达当前范围。`ChoiceField` 只组合这些实际复用的选择流程，`EditSheet` 只复用服务端编辑的滚动正文与可见操作栏，各页面仍持有自己的草稿和关闭策略。现阶段无需为这些场景增加第三方 UI 包。

| 场景                    | 采用的组件与操作                                                                                 | 必须保留的信息或行为                                                                |
| ----------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| 页面与标题栏            | `CupertinoPageScaffold` / `CupertinoNavigationBar`                                               | 标题、明确返回、主要操作；安全区和正文可用高度                                      |
| 普通按钮与图标          | `CupertinoButton` / `CupertinoIcons`                                                             | 可见标签或语义名称、忙碌与停用状态                                                  |
| 源、扩展、设置列表      | `CupertinoListSection` / `CupertinoListTile`，表单用 `CupertinoFormSection` / `CupertinoFormRow` | 既有分组、当前值、异常说明和恢复操作；作品网格与章节列表继续使用合适的 Flutter 列表 |
| 输入与搜索              | `CupertinoTextField` / `CupertinoTextFormFieldRow` / `CupertinoSearchTextField`                  | 标签、校验原因、提交/清空、中文输入、焦点与草稿                                     |
| 开关、勾选、数值        | `CupertinoSwitch` / `CupertinoCheckbox` / `CupertinoSlider`                                      | 当前值、适用范围、停用原因；分类多选和范围操作语义                                  |
| 少量互斥选项            | `CupertinoSlidingSegmentedControl` 或选择行                                                      | 清晰的当前选项和可操作状态                                                          |
| 下拉与更多操作          | `CupertinoMenuAnchor` / `CupertinoMenuItem`；少量触屏操作可用 `CupertinoActionSheet`             | 菜单位置、危险操作标识、键盘操作及关闭后的焦点返回                                  |
| 大量选择项              | 可搜索的 Cupertino 选择页                                                                        | 当前选择、搜索、结果或空状态；不把大量 Source/分类塞进动作表                        |
| 确认与复杂编辑          | `CupertinoAlertDialog` / `CupertinoDialogAction`；编辑用独立页或 `showCupertinoSheet`            | 明确保存、取消、提交中、失败和未确认草稿；滑动关闭不提交                            |
| 加载与刷新              | `CupertinoActivityIndicator`，适合列表时使用 `CupertinoSliverRefreshControl`                     | 首次加载、已有内容刷新和局部失败分别呈现，保留可用内容                              |
| 保存结果、冲突与 Access | 操作附近的状态文字、操作行或页面提示                                                             | 已确认/未确认、失败原因、重试/重登/重新读取入口；结果未知和未保存持续可见           |

`SnackBar` / `MaterialBanner` 没有需要逐个仿制的 Cupertino 等价物。按业务需要将反馈放在原操作附近；已有未保存、冲突与 Access 恢复入口必须一直可达，瞬时提示不能承担业务确认。仅为重复业务状态提供必要的小组件，优先直接使用官方控件。

## 阅读、返回与资源生命周期

阅读器只替换界面控件与布局，继续由既有持有者管理图片、进度、书签与 Source。页位锚点、缩放、裁白、连续滚动、键盘、手势和图片字节通道沿用现有合同；标题栏、安全区与底部控件改变后，重新核对正文视口和手势冲突。

所有阅读退出入口汇入现有 `_exit()` 流程：先尝试确认阅读进度，再退出阅读路由；页面销毁启动图片释放，持有该路由的上层等待 `route.completed` 并执行 `catalog.closeChapter`，在必要关闭/释放 ACK 完成前不打开新的互斥 Source 活动。保留 `PopScope` 和重复退出防护；未确认进度保留当前会话草稿，失败显示状态与允许的恢复操作。

阅读与图片查看页的导航栏关闭自动背景融合，使用应用主题的导航栏颜色，避免浅色主题标题与黑色阅读背景混为一色。本漫画设置使用已有 `EditSheet`，正文滚动、保存/关闭常驻底部；保存中禁止关闭，未提交修改与服务端已确认值分别提示。

官方 [PopScope 说明](https://api.flutter.dev/flutter/widgets/PopScope-class.html)明确：iOS 的 Cupertino 路由在 `canPop=false` 时不检测边缘返回手势，也不会触发 `onPopInvokedWithResult`。因此阅读页提供显式返回按钮并直接调用既有退出流程，不能只依赖该回调；仅在允许安全退出的状态启用边缘返回。Android 系统返回、Web 页面内返回、取消和显式返回分别回归。浏览器关闭文档不具备可靠等待异步 ACK 的保证，继续遵守未确认草稿的既有限制。

弹层关闭与切 tab 也遵守既有所有权，不因路由动画或隐藏页面保活重复创建运行时。身份/服务地址变化后清除旧视图和旧草稿，迟到结果继续按 requestId / generation 丢弃。

## 多端输入与可访问性

统一 Cupertino 外观，同时保留触屏、鼠标和键盘操作。核心操作不依赖长按或滑动发现；Tab、Enter、Escape、滚动、中文输入与文本选择可用，菜单/弹层关闭后焦点回到触发位置。窄屏从 360px 起验证，宽屏保留侧栏与合理内容宽度；控件有语义名称、足够触控区域，状态不只靠颜色表达。

浅色、深色、跟随系统、文字缩放和减少动态效果纳入组件回归。桌面视口模拟只能作为 Web 布局证据，实际设备安全区、原生 Access 和三端读写继续单独验收。

## 依赖边界与依据

2026-11-13 核对的官方 [`cupertino_ui` 1.1.6](https://pub.dev/packages/cupertino_ui/versions/1.1.6)支持当前固定 SDK，其最低要求是 Dart `^3.13.0` / Flutter `>=3.47.0`。应用直接精确固定该包和已有 `cupertino_icons` 版本，通过正式 pub 命令维护 lock；删除应用直接 Material 依赖与自有 Material 控件、图标字体配置。

`hooks_riverpod` 当前导入 `material_ui`，`flutter_hooks` 和 `flutter_inappwebview` 仍有旧 Material 导入。导入本身不证明运行时需要 Material 主题：实施时检查实际调用与本地化/类型依赖，严格分析与正式组件回归验证。保留 generator 与 Hooks；不复制第三方实现、不为清空传递依赖破坏类型或更换状态架构。需要处理实际耦合时，优先更新正式依赖或修改集成调用，不默认添加兼容桥。若仍有 Material 传递依赖，交付记录其来源；包体与性能变化依据实际构建和测量报告。

当前固定 `cupertino_ui` 的返回箭头通过 `Text.rich` 绘制 `CupertinoIcons.back`，release 图标扫描没有保留实际字形。正式 Web 构建使用官方 `--no-tree-shake-icons`；原生 release 同样须保留字体，未来构建入口见[客户端说明](../../apps/reader/README.md)。不修改 SDK、不放置不可见图标来影响裁剪；实际构建与字形证据见验证记录。

官方[设计包迁移指引](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)与[组件目录](https://docs.flutter.dev/ui/widgets/cupertino)用于核对 API。`migrate_design_widgets` 处理旧 SDK 导入到独立包的迁移；本次 Material 控件与交互转换按上述设计逐处实施。
