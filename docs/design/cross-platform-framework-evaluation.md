# Flutter、RN/RNW 与纯 PWA 历史评估

日期：2026-11-03。**后续决定：用户已选定 Flutter + TeaVM，当前实施方案见[接入设计](./flutter-teavm-integration.md)。** 本文其余内容保留选型前的比较与理由，关于待定、候选、RN/PWA 对照实施或 UI 约束未调整的表述均不再作为当前实施要求。目标继续是移动端原生优先、桌面端浏览器优先，允许用一定桌面性能换取移动性能。尚未建立产品客户端，也没有三条路线的性能实测。

**当时建议：以 Flutter 为第一性能验证候选，RN/RNW 为主要备选，纯 PWA 为低成本方案和性能对照。** 原因是移动端阅读性能及定制 UI 复用的权重高于桌面框架开销；这不是 Flutter 已经快于 RN/PWA 的结论。此次确定 Flutter 后，前端改用 Flutter widgets / Pub；pnpm 保留 TS/JS 管理与编排。

## 1. 比较对象与优先级

PWA 是 Web 应用的交付形态，不是与 Flutter/RN 同层的 UI 框架；Flutter Web 和 RNW 也可配置为 PWA。这里比较三个完整组合：

| 路线 | 移动端 | 桌面端 |
|---|---|---|
| Flutter | Flutter 原生 App + 系统 WebView 中的 TeaVM | Flutter Web + 浏览器 TeaVM Worker，可另加 PWA 安装能力 |
| RN/RNW | RN 原生 App + 系统 WebView 中的 TeaVM | RNW / 必要的 React DOM 视图 + TeaVM Worker，可另加 PWA |
| 纯 PWA | React DOM + TeaVM Worker，同一 Web 应用安装到主屏幕 | 同一 React DOM 应用 |

RNW 使用 React DOM，Expo Web 可添加 Service Worker；RNW 的浏览器产物不使用 Hermes。[RNW 文档](https://necolas.github.io/react-native-web/docs/)、[Expo PWA](https://docs.expo.dev/guides/progressive-web-apps/)。Flutter Web 支持独立浏览器构建，但需另配安装和缓存策略。[Flutter Web](https://docs.flutter.dev/platform-integration/web)。

选择采用以下顺序，不给未经测量的框架打性能分：

1. 功能正确、原版图片处理链正确、阅读位置不丢失，是所有平台共同的硬门槛。
2. 移动端优先：连续阅读的交互帧耗时、长图峰值内存、热量/能耗、首图与切章、前后台恢复。
3. 桌面端达到日用门槛：正常滚动/翻页/缩放、键盘和触控板、稳定内存、可接受的启动；不要求框架开销与纯 DOM 相等。
4. 在上述条件下，比较跨端复用、个人维护成本和现有工具链约束。

桌面较强的 CPU/GPU 允许一定额外工作量，却不能消除网络下载、超大图片尺寸限制、浏览器兼容问题或无界内存增长。可以接受较高但有界的成本，不能以“桌面更强”代替这些验证。当前已暂缓下载、后台更新、本地漫画等功能，原生路线主要须以阅读交互、资源控制和恢复能力体现价值。

## 2. 与当前项目直接相关的比较

以下是基于架构的工程判断，均不构成本项目性能实测结果。

| 维度 | Flutter | RN/RNW | 纯 PWA |
|---|---|---|---|
| 移动阅读 UI | 一套自绘布局、手势与渲染模型，适合高度定制阅读画布；Dart release AOT | 原生视图/滚动，手势与动画可放 UI 线程；React/JS 状态更新需控制 | 浏览器图片、滚动和合成；精细控制受 Web API 与引擎行为约束 |
| 原生端与桌面 UI 复用 | 潜力较高，仍需图片/输入/平台适配 | 状态和规则可共享，阅读视图可按平台分支 | 整套 Web UI 共用，但没有原生阅读视图 |
| 桌面浏览器 | 额外框架渲染与启动成本，在当前权重下可接受一定差距 | DOM 路径，容易结合浏览器输入和专用 Web 视图 | DOM 路径，直接使用浏览器能力 |
| TeaVM 宿主 | 原生端经 WebView；Web 经 JS interop | 原生端经 WebView；Web 直接接 JS 宿主 | 直接延续已验证的浏览器宿主路径 |
| 图片数据路径 | 原生端增加 WebView → 资源桥 → Flutter 图片 | 原生端增加 WebView → 资源桥 → 原生图片 | Worker → 浏览器图片资源，无新增原生资源交接 |
| 移动总内存 | Flutter 引擎、WebKit、TeaVM、解码图片，须合并计量 | Hermes、原生视图、WebKit、TeaVM、解码图片，须合并计量 | 浏览器、TeaVM 和解码图片；结构较少不保证实际峰值一定最低 |
| Access/恢复 | 新增原生会话与 WebView 生命周期适配 | 同左 | 沿用 Web 路径，仍须真实 Access 与已安装 PWA 验证 |
| 日常维护 | Dart/Pub + TS/pnpm + 原生桥 | 主要 TS/pnpm + 原生桥及平台视图 | 主要 TS/pnpm，单套前端发布，链路最少 |
| 原有 UI 约束 | 需要改用 Flutter widgets | Web 可保留 shadcn，原生控件另实现 | 可直接保留 shadcn |
| 当前定位 | 第一性能验证候选 | 原生主备选、保留 TS 的稳健路线 | 最短可用路径与性能基线；采用为主路线需接受移动 Web |

已有可复用资产主要是 Java/TeaVM/JS 宿主和测试证据；React 阅读器尚未实现。RN 的优势主要在后续类型、规则和应用代码的统一，不应虚构为已有整套 React 产品可直接迁移。

## 3. Flutter：移动优先后，优势与待证之处

Flutter 自行布局和绘制控件，移动 release 的 Dart 编译成机器码。漫画阅读器的大量工作是自定义分页、缩放、裁切、页组和工具栏，统一绘制模型有利于让优化后的阅读 UI 跨端共用。这是本项目优先验证 Flutter 的主要理由。[架构说明](https://docs.flutter.dev/resources/architectural-overview)。

移动端性能仍需有意识地控制：只保留有限图片窗口，避免手势逐帧重建整个组件树，布局和昂贵处理不挤占交互线程，解码尺寸随显示需求选择，切章后释放不再使用的资源。AOT 不会使大布局、重复解码或图片复制自动变便宜。[性能建议](https://docs.flutter.dev/perf/best-practices)。

Flutter Web 的 CanvasKit/Skwasm 等路径带来额外下载、初始化和渲染工作。当前可以接受其桌面资源成本高于 DOM，条件是长条滚动、缩放、键盘/触控板和首图仍达日用门槛。Wasm/JS 回退必须实际验证；多线程渲染相关 COOP/COEP 不默认全站启用，要先与 Access 和局部脚本能力联调。[Web 支持](https://docs.flutter.dev/platform-integration/web)、[Wasm](https://docs.flutter.dev/platform-integration/web/wasm)。

相同组件仍可能存在平台差异：Image.network 的 cacheWidth/cacheHeight 在 Web 被忽略，ImageCache 限额也不是 App/GPU 总内存上限。原生端针对图片做的优化，不应宣称已经同步改善 Web。若为了让桌面可用而被迫维护完整 DOM 阅读器，则应重新核算 Flutter 的复用收益。[图片 API](https://api.flutter.dev/flutter/widgets/Image/Image.network.html)、[ImageCache](https://api.flutter.dev/flutter/painting/ImageCache-class.html)。

候选技术组成：Flutter/Dart 共享阅读核心、UI、设置和同步规则；Web 用 dart:js_interop 连接 JS SourceRuntime；原生用 webview_flutter 承载宿主，另加图片资源通道；平台存储通过 repository 接口隔离。官方 WebView 插件的 iOS/Android 实现不能直接当作 Web 端实现。[WebView 插件](https://pub.dev/packages/webview_flutter)、[JS interop](https://dart.dev/interop/js-interop)。

## 4. RN/RNW：原生性能也可以成为强项

RN 的阅读画面由原生视图呈现，不能用“Hermes 解释执行”直接推断翻页和缩放必然落后。原生滚动不需要 JS 每帧参与；Reanimated 的 UI 线程 worklets 可以执行局部交互。页组、进度和工具栏状态更新留在应用层，高频手势不经整棵 React 树。[RN 性能说明](https://reactnative.dev/docs/performance)、[Reanimated 术语](https://docs.swmansion.com/react-native-reanimated/docs/fundamentals/glossary/)。

推荐共享 TypeScript reader-core、DTO、设置合并、页序/RTL/双页规则、逻辑锚点和同步协议。阅读视图允许 Reader.native.tsx 与 Reader.web.tsx：前者使用原生图片/滚动/手势，后者采用 RNW 或必要的 DOM 图片与输入实现。Web shadcn 与原生工具栏共享设置模型，不能直接共享其 DOM 组件。

这条路线的代价是优化可能需要维护两种图片、滚动和输入适配；不能以 RNW API 相同宣称每段视图都能共用。Reanimated Web 的实现使用 JavaScript，原生 UI 线程的执行特征不会原样带到浏览器。当前桌面性能权重降低后，这些平台差异可以接受，但仍需测试。[RNW](https://necolas.github.io/react-native-web/docs/)、[Reanimated Web](https://docs.swmansion.com/react-native-reanimated/docs/guides/web-support/)。

候选工具链：pnpm workspace + Expo/Metro + React Native/RNW；Web 外壳保留 shadcn；自定义原生资源桥采用 development build，不能依赖 Expo Go 已包含任意原生模块。Expo 支持 pnpm monorepo。[Monorepo](https://docs.expo.dev/guides/monorepos/)、[Development builds](https://docs.expo.dev/develop/development-builds/introduction/)。

若 RN 实测移动帧耗时、内存和恢复已满足要求，Flutter 的 AOT 或统一绘制不构成必然更换理由；应进一步比较实际减少的重复代码是否值得增加 Dart 工具链。

## 5. 纯 PWA：仍有机会在首图和总体成本上占优

纯 PWA 直接延续 TeaVM 浏览器宿主，图片在浏览器 Worker/页面之间传递，不新增 WebView 到原生视图的交接。这条更短的数据路径使它值得作为真实阅读基线；不应因为“原生”一词就预设另两条路线首图更快、内存更少。

移动端使用原生浏览器滚动、CSS transform/合成和有限图片窗口，同样可以实现流畅阅读；TeaVM 已在 WebWorker 中，不与页面 JS 共用执行线程。浏览器资源回收、存储和可用 API 由引擎管理，需要及时落盘逻辑位置和待同步变更。主屏幕安装不会把 UI 转成原生控件，也不会让扩展持续后台执行。

WebKit 支持请求持久存储，但默认 best-effort 数据可能被回收；不能绝对化为 PWA 必定丢数据，也不能假设安装后缓存永久保留。原生 WebView 内仍用 IndexedDB 的运行文件也要处理其存储策略。[WebKit 存储策略](https://webkit.org/blog/14403/updates-to-storage-policy/)。

当前不实现下载、后台更新、本地导入等功能，PWA 不会因这些暂缓能力被扣分。其主要取舍是接受移动浏览器的图片/输入控制范围，换取更少的平台适配、原生构建与个人安装维护工作。若它在用户实际手机上已达到阅读目标，可以作为低成本主方案；这需要明确接受移动 Web 交付，不能静默替代当前的原生优先目标。

## 6. 决定整条链路性能的共同问题

三条路线的后端均保留单 hostname、公开 Web 外壳、Access 保护 API、Workers/Hono、D1/R2/DO。TeaVM 0.16.0 JavaScript backend / release9、原版扩展不改、公共宿主 P0-A 与二进制桥 P0-B 均保持不变。没有服务端 JVM或容器，也不新增持续后台任务。

原生 Flutter/RN 均使用 WebView 内的 TeaVM；iOS 在相同 WebKit 与安全条件下，没有仅由 UI 框架带来的 TeaVM JIT 优势。Dart AOT 只影响 Dart 部分；Hermes 不是这里的 TeaVM 执行引擎。现有桌面 release9 结果与早期 CheerpJ 冷启动都不能直接替代这些组合的手机首图实测。

移动图片链为：TeaVM 原版请求/拦截/正文处理 → WebView 输出 → 有界资源传输 → 原生临时文件或受控资源 → 阅读视图。控制 RPC 只传 DTO、取消和句柄，图片不走整图 Base64/JSON。Flutter 的二进制 platform channel 与 RN 的 JSI 都不能自动解决 WebKit 内容进程的字节传输。[Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)、[RN WebView 通信](https://github.com/react-native-webview/react-native-webview/blob/master/docs/Guide.md)。

一张 1440×20000 的图片若完整展开为四通道 RGBA，单份约 110 MiB；这是像素规模示例，不是浏览器实测分配。压缩体积小不代表阅读内存小，额外副本、解码、GPU 纹理和并发页窗比 UI 语法更可能决定峰值。所有候选都应先限制活跃页、预取、取消和释放，再评估缩小解码或分块需求。

所有候选保留原扩展 headers、Cookie、拦截器、解密和重排。原生端不能只拿图片 URL 后另行下载来绕过处理链。WebView 内 runtime 回收、Access 过期、原生网络与 WebView 的会话归属、App + WebKit 合计内存都进入验收；P0-B 之外的原生图片资源通道目前仍未实现。

## 7. 工具链要求与复用目标

| 要求 | Flutter | RN/RNW | 纯 PWA |
|---|---|---|---|
| pnpm | 继续管理 TS 后端/JS 宿主和任务编排；Dart 依赖使用 Pub | 管理 JS/TS；原生 SDK/构建仍独立 | 管理前后端 JS/TS |
| 原 UI 三选一 | 需明确改为 Flutter widgets；Material widgets 不等于 React MUI | Web 保留 shadcn，原生 UI 另实现 | 保留 shadcn |
| 跨语言契约 | 版本化 schema 生成 Dart/TS 类型，共用测试向量 | 共享纯 TS 类型与规则，隔离浏览器/原生 API | 同一套 TS 实现 |
| 阅读 UI 复用 | 优先共享布局/交互，平台资源适配 | 优先共享规则和状态，按需要分视图 | 全 Web 复用 |

Flutter 的包管理使用 Pub。[官方文档](https://docs.flutter.dev/packages-and-plugins/using-packages)。当前只评估更改成本，没有把原 UI 要求视为已取消。若三选一仍覆盖整个前端，所有原生路线都需要调整适用范围；若仅约束 Web，RN/React 和纯 PWA 可保留，Flutter Web 仍需改要求。

## 8. P0-F 的验证与采用门槛

先验证阅读切片和真实图片链，再建设完整外围页面。无需为了选型完成三套产品。

| 阶段 | 验证内容 | 用于判断 |
|---|---|---|
| Web 对照切片 | React DOM：分页/Webtoon、缩放、RTL/双页、位置恢复；同版 TeaVM 的 3–5 个源 | 建立最短图片路径和手机实际体验基线；可独立于框架候选推进 |
| Flutter 优先切片 | 同等阅读行为；iPhone/Android 真机与桌面 Web；原生资源桥与 Access | 移动体验是否达目标；桌面增加的成本是否仍可日用；UI 实际能共享到哪里 |
| RN 对照切片 | 当 Flutter 桥接、移动内存或工具链成本不理想，或 RN 仍可能改善结果时，复用相同样例和原生通道协议验证 | 避免只凭 AOT/生态口号选择；确认原生滚动/手势及平台视图的实际效果 |
| 决策 | 原版源语义与阅读行为一致后比较实测 | 移动体验优先，桌面过门槛，再比较维护与依赖要求 |

使用固定版本和 release/profile 配置、同设备、同章节、同网络、相同产物缓存及 Access 状态；不能拿 Flutter debug 与 RN release 或热 PWA 对比。冷启动、缓存后新 runtime、同 runtime 热调用分别记录；交互登录时间独立统计。[Flutter 性能建议](https://docs.flutter.dev/perf/best-practices)、[RN release 测量](https://reactnative.dev/docs/performance)。

移动端记录首屏/首图/切章分布、持续滚动与缩放帧耗时、完整 App + WebKit 峰值、长时间阅读能耗，以及旋转/后台回收恢复。桌面覆盖 Chrome/Firefox/Safari、长图和多章、键盘/滚轮/触控板/返回；允许框架带来的可接受性能差距，资源不得持续增长或崩溃。数据由实测决定，不先承诺某框架 60/120 fps 或固定百分比收益。

若 Flutter 移动表现通过、桌面达到日用门槛、平台适配仍较少且工具链调整被接受，则提升为主方案。若 RN 达到相同移动目标且维护成本明显更低，选择 RN/RNW。若纯 PWA 已满足实际阅读目标且用户接受移动 Web，采用 PWA；原生优先目标在此决定前继续保留。

本轮仅修改计划和评估，未创建客户端、安装依赖、改写扩展、执行新性能基准或部署。更新、下载、历史统计、追踪、本地漫画、备份恢复和私密使用继续暂缓。
