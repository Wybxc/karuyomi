# Liquid Glass 界面重构验证

2026-11-13，历史试验记录。Liquid Glass 曾随 PR #6 合入主线并自动发布；用户随后决定撤下该视觉方案、恢复统一 Cupertino，玻璃验收与性能采集到此终止。恢复交付见[Cupertino 计划](../plan/cupertino-ui.md#恢复-cupertino)和[验证记录](cupertino-ui.md)。原生现场验证继续停止，以下工程及部分在线证据不代表完整性能验收。

## 依赖与策略

试验期间固定 `liquid_glass_widgets: 1.17.2`，正式 pub 命令维护 reader 依赖锁。使用唯一公开入口，初始化关闭性能监控，不启用自动跑分、背景采样或内容亮度读回。Flutter 3.50 的独立 `cupertino_ui` 与库内部 SDK Cupertino 类型不同，因此采用 `GlassScaffold`，显式对齐玻璃主题亮度，并补入官方 SDK 中文本地化 delegate。恢复 Cupertino 时一并移除这些集成和专用设置。

设置 `reduce_transparency` 进入正式 Protobuf 协议与全局设置，按 Worker API + D1 保存并收到确认后应用，不增加本地独立业务存储。客户端确认值比较包含该字段，错误 ACK 保留原草稿。

Web 默认使用标准质量，支持 shader filter 的引擎选择完整效果；实色与高对比使用零 blur 的 minimal 策略。库的 Reduce Transparency fallback 仍可能半透明，项目使用显式不透明材质。减少动态效果及禁用动画进入玻璃无障碍作用域。实际视觉和运行成本仍需正式浏览器产物验收。

## 试验工程证据

固定 Flutter 3.50.0 / Dart 3.14.0。正式 `pnpm flutter:check --concurrency=1 --reporter=expanded` 通过，包含三项目严格分析、Riverpod 生成一致性与 lint，以及 22 + 87 + 639 = 748 项测试。关键回归包含高对比/实色无 BackdropFilter、亮暗主题、材质切换保留焦点和草稿、隐藏工具仍显示待确认状态、Escape 回焦及资源释放。

实色设置回归覆盖草稿不提前应用、错误 ACK 拒绝、保留原操作重试与独立会话读回。Cloudflare 官方 Vitest 插件下 `state-workerd.test.ts` 的 46 项 Worker/D1 回归通过，覆盖跨会话读回、相同回执重放、旧写 CAS 冲突及切回玻璃。状态文字变化曾触发画布重排，已改为稳定状态槽位，恢复内容叠在其上；完整最终回归已包含阅读保存、Access 恢复及应用壳路径。

原始输出留在 ignored `.local/liquid-glass-evaluation/`。当前未运行本机完整 Flutter 编译、AOT、模拟器或真机；完整 Web 构建交给既有 CI。

## 代码量

原基线 `d7416f0ab5981b405dd5d8998158d3868b53971c` 为 30,296 行 / 91 文件。当前统计为 30,554 行 / 92 文件，净增 258 行，计入全部新增生产组件，排除 `.g.dart` 与 `/src/pb/`。用户明确选择本轮先完成视觉与交互，代码削减[另立重构](../plan/ui-code-consolidation.md)；不将此轮描述成代码量减少。

删去了详情单项更多菜单及宽屏手写侧栏，阅读主工具简化为翻页、页码和面板入口；全页导航、确认后的实色策略和持续恢复状态增加了集成代码。最终格式化后重新统计，测试、文档与生成模型单列。

## 分支 CI 与隔离 Web

`7f0565928549f0ca22aba3bf3cf73fdd786ffb58` 的[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/43388946481)通过完整工程、Flutter、Web 构建、本地迁移以及 JavaScript/Wasm 测量候选构建。复用其正式产物，经既有 Vite 配置装配两份已有扩展，以官方 Wrangler harness 的隔离 D1 和 `acceptance-owner` 验收；没有本机 Flutter 完整编译。

内置浏览器在 1280×720 和 360×800 中确认三入口浮动导航、扩展安装、管理与返回。深色和实色选择仍为草稿时，独立 GET 与选择前的响应字节一致；确认后 API 的全局 revision 为 2，`APP_THEME_DARK/reduceTransparency=true`，页面才应用外观。

首次浏览器验收发现 `GlassMenu` 无法用 Escape 关闭。详情菜单只有迁移一个动作，曾改为直接的“迁移到其他漫画源”导航按钮，保留原资格条件，删除弹出菜单需求。15 项迁移入口、原章节快照和身份隔离定向回归通过；`fa32475c8c097bf6f0f38ea3c0cd984cd34fee98` 的[完整 CI](https://github.com/Wybxc/karuyomi/actions/runs/43392199022)通过，生产内置浏览器随后确认直接进入迁移向导并返回。

普通候选的隔离 Web 已用 xkcd `2978: Stranded` 真实两页验证：窄屏实色阅读、面板展开与 Escape 收起、翻页后隐藏工具仍显示待确认及已保存、显式恢复工具和阅读退出。关闭旧标签后，新文档正确读回深色实色与第 2 页；独立进度 API 前后响应字节一致，续读未附带写入。

## 曾完成的生产发布

[PR #6](https://github.com/Wybxc/karuyomi/pull/6) 合入提交 `2923b8250fc96f0b71a19fde8bf2c734a018f3df` 的[主线 CI](https://github.com/Wybxc/karuyomi/actions/runs/43394265986)全部成功，包含 check、wasm 和 deploy。2026-11-13 08:44 UTC 发布检查核对 51 份公开资源和匿名 API 的 Access 302 门禁，复用当时 190 包扩展快照，没有重建 AOT。

Codex 内置浏览器恢复真实测试账号 Access 登录后，已打开漫画详情、迁移向导及 `3322: Dragonfly` 两页图片；翻页出现待确认后获服务端确认，独立 D1 读到第 1 页及漫画 revision 30。退出后一度出现阅读位置、书签和章节状态读取失败，显式重试恢复阅读位置；其余故障恢复及完整生产外观/新文档续读在终止时未完成，不记为通过。

## 未形成最终性能结论

同一 release / CanvasKit、1280×720、DPR 2、60Hz 环境取得旧基线 `d7416f0` 和最终候选 `fa32475` 的可解析原始报告。候选首份报告只有打开章节及静止阶段，没有录入随后翻页；补采面板显示 53 个事件和 335 帧，但第二份 JSON 自动下载多次超时，终止时尚未落盘。不能据第一份报告给出完整跳页/滚动性能或能耗结论。

CPU、RSS、GPU 内存、后台耗电及原生真机仍未采集；框架 FrameTiming 不等于物理呈现或 GPU 执行时间。原始文件和截图保留在 ignored `.local/liquid-glass-evaluation/`。恢复 Cupertino 是用户对视觉与成本的明确取舍，不把该决定包装为已证明的性能回归。
