# Liquid Glass 库评估与界面方向

评估日期：2026-11-13。对应[实施计划](../plan/liquid-glass.md)。本次完成依赖元数据、发布源码和官方设计/引擎能力的静态评估，尚未引入依赖、运行候选库或测量 Karuyomi 性能。

## 结论

**优先验证 `liquid_glass_widgets: 1.17.2`，作为一轮完整界面重构的导航与操作浮层库。** 保留 `CupertinoApp`、`cupertino_ui` 和现有业务控制器，直接使用库的导航栏、底栏、侧栏、工具条及必要的表面组件。内容区继续使用清晰的 Cupertino 列表、表单和漫画画布。该库的组件覆盖最接近项目需要，较有机会同时删掉重复布局；是否真的减少代码和保持流畅，仍须通过项目验收。

这个推荐接受明确的效果差异：**默认 Web 使用实时背景模糊、着色和镜面边缘的轻量玻璃；支持 Impeller 的原生端可以使用完整折射。** Web 上的轻量着色器不等于对滚动漫画进行实时背景折射。库另有采样背景的路径，但不能据静态墙纸示例声称动态漫画已经达到同样效果。

若产品要求升级为“Web 也必须真实折射当前滚动内容”，优先改验 `liquid_glass_easy: 5.2.0`，而不是叠加第二套库。它有明确的 Web 背景捕获路径，但需要处理持续捕获、纹理释放与业务树布局，现有源码还有生命周期疑点。`g1455` 的捕获架构完整、测试材料较充分，但其作者明确报告 CanvasKit 捕获成本高，不适合作当前默认 Web 的首选。不能为玻璃效果直接切换整个产品的 Web 渲染器。

## 项目约束与效果边界

当前基线为 Flutter 3.50.0 / Dart 3.14.0、`cupertino_ui: 1.1.6`、`cupertino_icons: 1.0.9`；默认 Web 是 dart2js + CanvasKit。Wasm/Skwasm 候选能编译，尚无项目性能对照。三个正式入口是书架、浏览、设置，宽度 840px 起使用侧栏；只有当前业务页挂载，一个根 Navigator。阅读、图片资源、Source 与服务端状态各有明确所有者。

苹果的 [Materials 指引](https://developer.apple.com/design/human-interface-guidelines/materials)把 Liquid Glass 放在导航与控制层，并要求避免抢占内容、核对复杂背景下的可读性。应用于本项目时，重点是浮动导航、返回/主要操作和阅读工具条，不把扩展列表、长表单或漫画页变成多层透明卡片。

[Flutter `ImageFilter.shader`](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html)只支持 Impeller；CanvasKit 和 Skwasm 都不能因为能运行普通 FragmentShader，就直接获得这个背景过滤 API。Web 真实折射通常还需要可采样的背景纹理。包的平台标签只表示声明/分析层面的可用性，不能证明三端效果一致、性能达标或采用原生系统材质。

减少动态效果、高对比、减少透明度和引擎能力是当前运行条件，不是旧版兼容需求。Flutter 没有专用的系统 Reduce Transparency 标志；不能把 `highContrast` 当作完全等价的系统开关。需要明确的应用内实色选择，或经过验证的正式平台桥，不能宣称已经自动支持全部系统设置。

## 主要候选比较

版本来自 pub.dev 官方 API 的当日快照，排序只表示对本项目的推荐程度。A 表示核对过对应发布 archive 的 SHA-256，并阅读关键源码、README、pubspec 与许可证；B 表示官方包文档/元数据评估。A 也不表示已经执行测试或完成全面代码审计。

| 库与精确版本                                                                                                 | Web 路径                                                                    | iOS / Android 的完整效果条件                                                      | 覆盖与集成成本                                                       | 对本项目的判断                                                 |
| ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------- |
| [liquid_glass_widgets 1.17.2](https://pub.dev/packages/liquid_glass_widgets/versions/1.17.2) · A             | 常规路径是实时 blur、饱和度及轻量边缘光；另有显式背景采样                   | Impeller + premium；PlatformView 背景要走库的专用路径                             | 导航、侧栏、工具条、菜单/表面较完整；可接 CupertinoApp               | **首选技术验证**，统一控制层，默认不捕获滚动漫画               |
| [liquid_glass_easy 5.2.0](https://pub.dev/packages/liquid_glass_easy/versions/5.2.0) · A                     | `LiquidGlassView` 捕获 `backgroundWidget` 后供透镜采样；也有无折射 lite     | Impeller 可直接过滤实时背景，不需要相同捕获管线                                   | 透镜、融合、控件、导航较丰富；必须明确背景与前景布局、启停和资源成本 | **Web 真折射的条件备选**，先解决生命周期疑点并测 CanvasKit     |
| [cupertino_liquid_glass 0.9.0](https://pub.dev/packages/cupertino_liquid_glass/versions/0.9.0) · A           | BackdropFilter + 高光/边缘绘制，无非线性背景折射                            | 同样以模糊和光照近似为主                                                          | Cupertino 主题、导航及常用控件；仅 Flutter 运行依赖                  | **轻量近似备选**，不能把效果称为完整折射                       |
| [glass 2.4.0](https://pub.dev/packages/glass/versions/2.4.0) · A                                             | 普通 blur + tint                                                            | Impeller 才有实验性的液态折射与边缘光                                             | `asGlass()` 表面 API 很小；没有完整导航/交互套件                     | **局部表面备选**，全界面仍需自己维护较多布局                   |
| [fluid_glass 0.5.6](https://pub.dev/packages/fluid_glass/versions/0.5.6) · A                                 | 无 shader-filter 能力时跳过折射，保留 blur/tint                             | Impeller；`LayerBackdrop` 引入纹理捕获；`nativeBackdrop` 本身是无折射的合成器模糊 | 有较完整控件，但背景句柄、主题及多种效果路径需集成                   | **次选**；没有解决当前 Web 真折射要求，收益不优于首选          |
| [liquid_glass_shader 0.4.1](https://pub.dev/packages/liquid_glass_shader/versions/0.4.1) · A                 | 磨砂/高对比实色                                                             | Impeller 折射                                                                     | 表面 + 横/竖 tab bar；内部透明 Material 会改变默认文字样式           | **窄范围备选**；需显式 Cupertino 字体/主题集成，覆盖较少       |
| [liquid_glass_toolkit 1.0.0](https://pub.dev/packages/liquid_glass_toolkit/versions/1.0.0) · A               | standard 模糊、色彩与光照，无完整折射                                       | premium 需要 Impeller                                                             | UI 套件较全，可用独立主题；不是必须改成 MaterialApp                  | **不进入首轮**；同样有平台效果差异，暂未显示比首选更直接的收益 |
| [g1455 0.4.0](https://pub.dev/packages/g1455/versions/0.4.0) · A                                             | 单 GlassHost 捕获 atlas 后折射；CanvasKit 建议 cheap 档，无捕获也无完整效果 | 捕获 + 着色器；与引擎/捕获路径相关                                                | 控件、分档、诊断较完整；接入点在 Navigator 之上                      | **暂不采用**；当前 CanvasKit 主线与其完整效果成本冲突          |
| [liquid_glass_navigation 0.1.1](https://pub.dev/packages/liquid_glass_navigation/versions/0.1.1) · A         | 磨砂导航表面                                                                | 以现有表面/导航实现为准，未证明完整折射                                           | 主要是底栏、侧栏和 Scaffold                                          | **覆盖不足**；单独选它还要为阅读工具条再引入方案               |
| [liquid_glass_renderer 1.0.0-dev.2](https://pub.dev/packages/liquid_glass_renderer/versions/1.0.0-dev.2) · B | FakeGlass 近似                                                              | 完整路径涉及 Impeller、Flutter GPU 预览能力                                       | 底层 renderer，依赖与新 API 集成面较大，版本为预发布                 | **不采用为产品主方案**                                         |
| [liquid_glass_plus 0.3.2](https://pub.dev/packages/liquid_glass_plus/versions/0.3.2) · A                     | FakeGlass 近似                                                              | renderer 派生实现，完整能力依赖其支持的引擎                                       | 需要自行组合上层组件                                                 | **不采用**；没有提供本项目所需的 Web/控件优势                  |
| [apple_liquid_glass 1.0.0-dev.2](https://pub.dev/packages/apple_liquid_glass/versions/1.0.0-dev.2) · A       | 随其重导出的 renderer                                                       | 同 renderer                                                                       | 发布的 Dart 入口只 export `liquid_glass_renderer`                    | **排除重复包装**，需要时直接选实际实现                         |

## 影响选型的源码发现

### liquid_glass_widgets

对应发布源码的 `widgets/shared/adaptive_glass.dart`、`adaptive_liquid_glass_layer.dart` 与 `lightweight_liquid_glass.dart` 把完整 Impeller 路径和标准轻量路径分开。标准路径使用实时 BackdropFilter；显式接入 `GlassBackgroundSource` 时才存在供部分交互指示器使用的采样纹理。

采样路径的 `_handleTick` 主要依据背景尺寸、位置和首次采样判断更新，稳定数帧后停 ticker。这不能证明同一位置内不断滚动或换图的漫画会持续更新折射纹理。本轮默认不接该路径，不以“加一个 RepaintBoundary”替代真实动态背景验收。

包的 pubspec 只有 Flutter 运行依赖，但发布内容包含衍生 renderer、motor 等实现及 `THIRD_PARTY_NOTICES`，也注册了读取 iOS 系统保留区域的 Swift 插件；不能描述为完全无原生代码或无第三方实现。该插件不等于使用原生 UIKit Liquid Glass。现有 Xcode 的编译检查与原生现场验收要分别记录。

维护记录从 2025-12 开始，最近发布仍在修正导航、焦点语义和标准质量视觉。活跃度是正面因素，也意味着要精确锁版本、集中回归。发布 archive 未附带 test 目录，不能据此断言上游仓库没有测试，也不能假定其交互已被本项目验证。

`LiquidGlassWidgets.wrap()` 支持 CupertinoApp；直接用现成组件，避免引入其整套 navigation stack、每 tab Navigator 或隐藏业务树。保持 `AppPageRoute`、阅读退出和关闭 ACK。关闭实验性的 `adaptiveQuality` 自动跑分以及不需要的性能监控，先用固定质量取得项目数据。

库承认高对比只能近似减少透明度；`platformViewBackdrop` 则专门处理 UIKitView 背景。原生 Access 页不能盲目套用完整 shader。导入旧 SDK Cupertino/Material 也不等于必须有 MaterialApp，需以当前固定 SDK 的实际类型/祖先依赖检查为准。

### liquid_glass_easy

5.2.0 的 `LiquidGlassView` 让背景业务子树只挂载一次，前景透镜采样该背景，**不必复制一份业务页面**；但当前应用壳和阅读布局必须相应拆成内容与浮层。独立 `LiquidGlassTabBar` 在 Web 不会凭空获得整页捕获。

Web 的实时捕获开启后存在主动 frame pump，静止页面也不能仅凭“内容没变”认定无额外工作。已有 controller 的启停 API，接入时须按滚动/显隐/前后台停止，关闭自适应亮度采样等非必要功能。不要为此自建另一套截图调度器。

在发布源码 `src/widgets/liquid_glass_view.dart` 的背景替换与 `dispose()` 路径中，未看到 `_image` / `_imagesPerLens` 对应的显式 `ui.Image.dispose()`，异步结果离开页面后的释放也需核对。这里记录的是源码疑点，**尚未证明实际内存泄漏**；要用反复打开/关闭与滚动的纹理内存证据排除，或等待正式上游修复，再考虑生产采用。仅凭作者 demo 流畅不能通过这个门槛。

### g1455、fluid_glass 与小型表面库

`g1455` 的单 Host、按背景变化捕获和测试/诊断值得肯定。其 README 明确报告 CanvasKit 的 `Picture.toImageSync` 读回代价，并建议当前此类客户端使用无捕获 cheap 档。作者给出的 15–30ms / 4–10ms 是其设备、旧版本和场景的数据，**不是 Karuyomi 测量结果**；这里用作筛选风险依据，不据此预测本项目帧率。见[官方性能说明](https://g1455.plugfox.dev/foundations/performance)。

`fluid_glass` 发布的 `effects/lens.dart` 在不支持 shader-filter 时直接跳过透镜效果；`backdrops/native_backdrop.dart` 明确声明 nativeBackdrop 不提供折射。不能把这里的 native 理解成 Apple 系统原生玻璃。其默认主题回落到 Material Theme，Cupertino 应显式提供自己的颜色，且需要区分 LayerBackdrop 捕获与无捕获表面。

`glass` 2.4.0 的 LiquidGlass 为实验功能，Web 为 blur/tint；形状边缘与融合能力有限，但适合只需要少量表面的应用。BSD-3-Clause 许可证与其噪声资源需随正式依赖保留。`cupertino_liquid_glass` 的关键实现是 BackdropFilter、绘制高光及弹簧；没有非线性背景采样着色器，不把宣传中的玻璃感等同于真实折射。`liquid_glass_shader` 的 `GlassSurface` / `LiquidTabBar` 确实嵌入 Material，文字样式变化是实际集成点，不能只看依赖名字判断。

已核对的 widgets、easy、g1455、cupertino、shader、toolkit、navigation 和 plus 为 MIT；fluid 为 Apache-2.0，apple 包本身为 Apache-2.0 且还重导出其它实现。采用时保留相应第三方声明；这里没有把许可证宽松视为性能或维护质量证明。

## 本项目的视觉分工

| 区域                 | 计划呈现                                               | 最小必要信息与操作                                                |
| -------------------- | ------------------------------------------------------ | ----------------------------------------------------------------- |
| 三入口导航           | 窄屏浮动底栏；宽屏带标签玻璃侧栏                       | 书架/浏览/设置、当前项、键盘焦点；只有当前页挂载                  |
| 标题与主要操作       | 轻量标题、返回与主要操作胶囊；内容滚到其下方时仍可读   | 页面身份、明确返回、搜索/筛选/批量操作入口及活动范围              |
| 书架、浏览、扩展     | 稳定的实色内容与列表；浮层只承载导航和少量操作         | 保留既定流程中的加载、空、刷新、局部失败、已安装/可更新及来源信息 |
| 阅读                 | 画布占主要面积；短浮动工具条，次要选项进章节/设置面板  | 当前页/总页、前后翻页、章节/设置、退出；保存与恢复状态持续可达    |
| 表单、选择、复杂编辑 | 清晰的内容面板与常驻确认区；少量浮层表面与全局风格一致 | 当前值、草稿、保存/取消、提交中/失败、作用范围；关闭不隐式提交    |
| 诊断与 Access        | 跟随统一主题，优先保证文本/登录控件清晰                | 错误、恢复、服务与身份状态；PlatformView 使用正确渲染路径         |

玻璃隐藏不能隐藏未保存或冲突，也不能把服务端确认变成短暂 toast。UI 不为装饰重复解码漫画、不改图片字节通道、不引入新的业务数据库或同步机制。实施范围、结构图和验收见[计划](../plan/liquid-glass.md)。

## 搜索覆盖与其余包的筛选

完整跟随用户给定[搜索](https://pub.dev/packages?q=liquid+glass+platform%3Aweb+platform%3Aios+platform%3Aandroid)的官方 API 分页，当日返回 100 个结果。以上 12 个进入重点比较，其余 88 个逐项做元数据初筛（C）；未读实现的包，不断言其一定是纯 blur、一定有泄漏或无法编译。

以下“暂不选”表示其声明的用途、集成面或证据不足以优先于短名单，并非所有包都已运行失败。导航专用包覆盖不了全局浮层，额外 UI 套件与本项目已有 Cupertino 能力重叠；预发布或 0.x 版本本身不作为质量的唯一结论。全体版本只是当日快照，实施前只复核最终候选，不随搜索结果升级整个依赖树。

| 库与当日版本（均为 C 级初筛）                                                                                                  | 声明定位/范围    | 本项目的初筛判断                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------ | ---------------- | -------------------------------------------------------------------------------- |
| [flutter_mmcalendar 4.1.0](https://pub.dev/packages/flutter_mmcalendar/versions/4.1.0)                                         | 日历             | 用途不覆盖本轮导航与阅读浮层                                                     |
| [liquid_glass_bottom_bar 0.0.6](https://pub.dev/packages/liquid_glass_bottom_bar/versions/0.0.6)                               | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_ui 0.4.0](https://pub.dev/packages/liquid_glass_ui/versions/0.4.0)                                               | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glass_bottom_navbar_plus 0.0.1](https://pub.dev/packages/liquid_glass_bottom_navbar_plus/versions/0.0.1)               | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [frosted_ui_kit 2.0.3](https://pub.dev/packages/frosted_ui_kit/versions/2.0.3)                                                 | 综合 UI 套件     | 与 Cupertino 重叠，并引入 Material/Lottie 等依赖，暂不优先                       |
| [liquid_glass_bottom_nav_water_effect 1.3.0](https://pub.dev/packages/liquid_glass_bottom_nav_water_effect/versions/1.3.0)     | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass 0.0.2](https://pub.dev/packages/liquid_glass/versions/0.0.2)                                                     | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_snackbar 0.1.3](https://pub.dev/packages/liquid_snackbar/versions/0.1.3)                                               | 临时通知         | 不能承载持续的保存/冲突确认，无需为此引入                                        |
| [liquid_glass_ui_design 1.0.5](https://pub.dev/packages/liquid_glass_ui_design/versions/1.0.5)                                 | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glass_animation 0.0.1](https://pub.dev/packages/liquid_glass_animation/versions/0.0.1)                                 | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [flutter_liquid_gooey 0.0.4](https://pub.dev/packages/flutter_liquid_gooey/versions/0.0.4)                                     | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [fresnel 0.1.0](https://pub.dev/packages/fresnel/versions/0.1.0)                                                               | 原生 + shader    | 声明 iOS SwiftUI PlatformView、其它端 shader；增加两条集成路径，暂不优先         |
| [liquid_bottom_nav_bar 0.1.0](https://pub.dev/packages/liquid_bottom_nav_bar/versions/0.1.0)                                   | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_effect 1.0.1](https://pub.dev/packages/liquid_glass_effect/versions/1.0.1)                                       | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [floatica 1.2.1](https://pub.dev/packages/floatica/versions/1.2.1)                                                             | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_floating_nav 0.1.0](https://pub.dev/packages/liquid_glass_floating_nav/versions/0.1.0)                           | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [glass_liquid_navbar 0.2.0](https://pub.dev/packages/glass_liquid_navbar/versions/0.2.0)                                       | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_nav 1.0.1](https://pub.dev/packages/liquid_glass_nav/versions/1.0.1)                                             | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [firstsplashscreenview 1.0.2](https://pub.dev/packages/firstsplashscreenview/versions/1.0.2)                                   | 启动页           | 不属于本轮核心界面重构                                                           |
| [glassy_real_navbar 1.0.4](https://pub.dev/packages/glassy_real_navbar/versions/1.0.4)                                         | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquidglass_container 1.0.2](https://pub.dev/packages/liquidglass_container/versions/1.0.2)                                   | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glass_navigation_bar 1.0.0](https://pub.dev/packages/liquid_glass_navigation_bar/versions/1.0.0)                       | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_navbar 1.0.5](https://pub.dev/packages/liquid_glass_navbar/versions/1.0.5)                                       | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_shell_platform_interface 0.1.0-dev.12](https://pub.dev/packages/liquid_shell_platform_interface/versions/0.1.0-dev.12) | 平台接口         | 不是完整效果或控件库                                                             |
| [liquid_tab_bar 2.0.0](https://pub.dev/packages/liquid_tab_bar/versions/2.0.0)                                                 | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [flutter_liquid_glasses 0.1.3](https://pub.dev/packages/flutter_liquid_glasses/versions/0.1.3)                                 | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [liquid_glacier 0.0.2](https://pub.dev/packages/liquid_glacier/versions/0.0.2)                                                 | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [glassy_blob_nav 1.0.0](https://pub.dev/packages/glassy_blob_nav/versions/1.0.0)                                               | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [simple_dialogs_flutter 2.2.2](https://pub.dev/packages/simple_dialogs_flutter/versions/2.2.2)                                 | 对话框           | 现有 Cupertino 确认流程已覆盖，暂不新增依赖                                      |
| [camouflage_skin_cupertino 0.1.1](https://pub.dev/packages/camouflage_skin_cupertino/versions/0.1.1)                           | 第三方主题皮肤   | 项目已有官方 Cupertino 基础，无需增加另一套皮肤系统                              |
| [generative_shader_ui 1.1.0](https://pub.dev/packages/generative_shader_ui/versions/1.1.0)                                     | 通用 shader UI   | 定位超出 Liquid Glass 导航，缺少优于短名单的依据                                 |
| [liquid_glass_fx 0.0.2](https://pub.dev/packages/liquid_glass_fx/versions/0.0.2)                                               | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [flutter_sea_glass 0.1.0-dev.2](https://pub.dev/packages/flutter_sea_glass/versions/0.1.0-dev.2)                               | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [glass_of_litchi 0.0.1](https://pub.dev/packages/glass_of_litchi/versions/0.0.1)                                               | 风格化 UI        | 果色/装饰预设不是本项目的主要选型依据                                            |
| [neo_glass 1.0.1+3](https://pub.dev/packages/neo_glass/versions/1.0.1+3)                                                       | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [animated_multi_dropdown 1.0.7](https://pub.dev/packages/animated_multi_dropdown/versions/1.0.7)                               | 多选下拉         | 既有搜索选择页已满足业务，无需恢复旧式下拉需求                                   |
| [liquid_glass_floating_tab_bar 0.1.0](https://pub.dev/packages/liquid_glass_floating_tab_bar/versions/0.1.0)                   | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [tahoea_liquid_glass 0.0.9](https://pub.dev/packages/tahoea_liquid_glass/versions/0.0.9)                                       | 装饰效果         | 以波纹、渐变和高光为卖点，未见优于短名单的项目证据                               |
| [liquid_glass_texture 0.0.4](https://pub.dev/packages/liquid_glass_texture/versions/0.0.4)                                     | 综合视觉套件     | 声明 Rive/Lottie/Shimmer 等依赖，本轮不需要额外动画体系                          |
| [liquid_glassy_container 0.0.4](https://pub.dev/packages/liquid_glassy_container/versions/0.0.4)                               | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_design 0.4.1](https://pub.dev/packages/liquid_design/versions/0.4.1)                                                   | 原生 + 跨端降级  | iOS 原生而其它端效果不同，未显示统一控件收益                                     |
| [liquid_segmented_bar 0.2.0](https://pub.dev/packages/liquid_segmented_bar/versions/0.2.0)                                     | 分段选择         | 局部控件覆盖不足，随选定库或官方组件统一解决                                     |
| [glovex_liquid_ui 1.2.2](https://pub.dev/packages/glovex_liquid_ui/versions/1.2.2)                                             | UI/路由套件      | 声明依赖 go_router，集成面大于本轮所需                                           |
| [fresnel_shader 0.1.0](https://pub.dev/packages/fresnel_shader/versions/0.1.0)                                                 | 底层 shader 组件 | fresnel 的效果实现组件，不作为独立全界面方案                                     |
| [onboarding_view 1.0.1](https://pub.dev/packages/onboarding_view/versions/1.0.1)                                               | 引导页           | 不属于本轮核心界面                                                               |
| [flutter_liquid_glass 1.0.0+1](https://pub.dev/packages/flutter_liquid_glass/versions/1.0.0+1)                                 | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glass_easy_ios_android 1.1.1](https://pub.dev/packages/liquid_glass_easy_ios_android/versions/1.1.1)                   | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [rehoboam_neural_ui 1.1.0](https://pub.dev/packages/rehoboam_neural_ui/versions/1.1.0)                                         | 额外 UI 套件     | 用途与漫画阅读控制层不匹配，暂不扩张                                             |
| [perfect_liquid_glass 1.0.1+1](https://pub.dev/packages/perfect_liquid_glass/versions/1.0.1+1)                                 | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [liqkit_ui 0.4.0](https://pub.dev/packages/liqkit_ui/versions/0.4.0)                                                           | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [fresnel_platform_interface 0.1.0](https://pub.dev/packages/fresnel_platform_interface/versions/0.1.0)                         | 平台接口         | 不是直接供业务使用的视觉实现                                                     |
| [liquid_glass_ui_kit 0.1.2](https://pub.dev/packages/liquid_glass_ui_kit/versions/0.1.2)                                       | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [glass_menu 1.1.0](https://pub.dev/packages/glass_menu/versions/1.1.0)                                                         | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [vikum_buttons 0.1.0](https://pub.dev/packages/vikum_buttons/versions/0.1.0)                                                   | 按钮             | 局部覆盖不足，无需再增加按钮依赖                                                 |
| [liquid_glass_components 1.0.1](https://pub.dev/packages/liquid_glass_components/versions/1.0.1)                               | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [glass_mt 1.0.0](https://pub.dev/packages/glass_mt/versions/1.0.0)                                                             | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [bidoro 0.0.0](https://pub.dev/packages/bidoro/versions/0.0.0)                                                                 | 0.0.0 元数据     | 当前发布信息不足以支持主选，未深入源码                                           |
| [liquid_morph_ui 1.0.5](https://pub.dev/packages/liquid_morph_ui/versions/1.0.5)                                               | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [glass_wave_navbar 0.0.6](https://pub.dev/packages/glass_wave_navbar/versions/0.0.6)                                           | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [cupertino_glass 0.0.0](https://pub.dev/packages/cupertino_glass/versions/0.0.0)                                               | 0.0.0 元数据     | 当前发布信息不足以支持主选，未深入源码                                           |
| [glassx_ios 1.1.0](https://pub.dev/packages/glassx_ios/versions/1.1.0)                                                         | 原生 + 跨端降级  | UIVisualEffectView / PlatformView 与 Web 回退并行，和统一 Flutter 控制层目标较弱 |
| [flutter_liquid_glass_nav_bar 1.0.1](https://pub.dev/packages/flutter_liquid_glass_nav_bar/versions/1.0.1)                     | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [smart_tab_scroll 1.0.0](https://pub.dev/packages/smart_tab_scroll/versions/1.0.0)                                             | 滚动/tab 联动    | 容易扩大滚动所有权改造，当前不需要独立联动库                                     |
| [slide_glass_nav_bar 0.1.0](https://pub.dev/packages/slide_glass_nav_bar/versions/0.1.0)                                       | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_bottom_navigator 1.1.0](https://pub.dev/packages/liquid_glass_bottom_navigator/versions/1.1.0)                   | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [flutter_liquid_glass_widgets 0.0.1](https://pub.dev/packages/flutter_liquid_glass_widgets/versions/0.0.1)                     | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [retcore_liquid_glass 0.0.2](https://pub.dev/packages/retcore_liquid_glass/versions/0.0.2)                                     | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glassmorphism 0.0.1](https://pub.dev/packages/liquid_glassmorphism/versions/0.0.1)                                     | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [quick_action_default 0.0.1](https://pub.dev/packages/quick_action_default/versions/0.0.1)                                     | 快捷操作         | 局部覆盖不足，未进入效果库短名单                                                 |
| [just_liquid_glass 0.8.0](https://pub.dev/packages/just_liquid_glass/versions/0.8.0)                                           | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [tf_framework 0.3.2](https://pub.dev/packages/tf_framework/versions/0.3.2)                                                     | 框架套件         | 范围远超视觉重构，暂不引入                                                       |
| [liquid_glass_pro 0.1.0](https://pub.dev/packages/liquid_glass_pro/versions/0.1.0)                                             | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [fluid_glass_nav_bar 1.0.0](https://pub.dev/packages/fluid_glass_nav_bar/versions/1.0.0)                                       | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquor_glass_nav_bar 0.3.0](https://pub.dev/packages/liquor_glass_nav_bar/versions/0.3.0)                                     | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_dock 1.0.0](https://pub.dev/packages/liquid_glass_dock/versions/1.0.0)                                           | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_bottom_bar 0.3.0](https://pub.dev/packages/liquid_bottom_bar/versions/0.3.0)                                           | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_kit 1.0.0](https://pub.dev/packages/liquid_glass_kit/versions/1.0.0)                                             | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquidglass_light 0.0.3](https://pub.dev/packages/liquidglass_light/versions/0.0.3)                                           | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [pip_glass_nav 0.1.0](https://pub.dev/packages/pip_glass_nav/versions/0.1.0)                                                   | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [liquid_glass_lts 0.1.0](https://pub.dev/packages/liquid_glass_lts/versions/0.1.0)                                             | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [glassmorphic_ui 0.1.0](https://pub.dev/packages/glassmorphic_ui/versions/0.1.0)                                               | 额外 UI/效果库   | 与已有 Cupertino 及短名单重叠；元数据未形成优先采用依据                          |
| [liquid_glass_toast 1.0.0](https://pub.dev/packages/liquid_glass_toast/versions/1.0.0)                                         | 临时通知         | 持续业务状态不能仅由 toast 表达                                                  |
| [glassfx 0.0.0](https://pub.dev/packages/glassfx/versions/0.0.0)                                                               | 0.0.0 元数据     | 当前发布信息不足以支持主选，未深入源码                                           |
| [liquid_glass_flutter 0.0.1+1](https://pub.dev/packages/liquid_glass_flutter/versions/0.0.1+1)                                 | 效果/renderer    | 未确认当前 Web 路径优于短名单，控件覆盖证据不足                                  |
| [pin_code_fields_liquid_glass 0.1.0-dev.3](https://pub.dev/packages/pin_code_fields_liquid_glass/versions/0.1.0-dev.3)         | 验证码输入       | Access 使用既有登录链路，无自建验证码流程需求                                    |
| [liquid_glass_miracle 0.1.0](https://pub.dev/packages/liquid_glass_miracle/versions/0.1.0)                                     | 导航/菜单专用    | 覆盖局部；还需解决标题与阅读工具条，暂不另选                                     |
| [refraction 0.0.0](https://pub.dev/packages/refraction/versions/0.0.0)                                                         | 0.0.0 元数据     | 当前发布信息不足以支持主选，未深入源码                                           |
| [garasu 0.0.0](https://pub.dev/packages/garasu/versions/0.0.0)                                                                 | 0.0.0 元数据     | 当前发布信息不足以支持主选，未深入源码                                           |

## 可复核方法与证据限制

- 元数据入口为 `https://pub.dev/api/search?q=liquid%20glass%20platform%3Aweb%20platform%3Aios%20platform%3Aandroid`，跟随响应的 `next`；逐包版本与 archive 哈希来自 `https://pub.dev/api/packages/<name>`。页面缓存有时显示旧版，本次以 API 精确版本和对应发布 archive 为准。
- 源码从 API 的 `latest.archive_url` 获取，校验 `latest.archive_sha256` 后解包阅读；未执行下载的第三方代码。原始 JSON、下载、源码与临时日志留在忽略目录 `.local/liquid-glass-evaluation/`，不复制进正式源码。
- 本次没有运行候选 demo、Flutter 编译、模拟器、浏览器视觉/帧率测试或 AOT；没有重新启动已停止的原生验证。本评估支持选型和任务范围，不构成三端性能或上线证据。
- 最终依赖需经固定 SDK 的严格分析、交互回归和正式 Web 产物验收；上游截图、作者 FPS、下载量与编译成功均不能代替项目测量。
