# Liquid Glass 界面重构验证

2026-11-13，当前为实施中的工程证据，尚未完成 CI、真实浏览器及生产发布。原生现场验证继续按用户要求停止。[实施计划](../plan/liquid-glass.md)维护范围与剩余门槛。

## 依赖与策略

固定 `liquid_glass_widgets: 1.17.2`，正式 pub 命令维护 reader 依赖锁。使用唯一公开入口，初始化关闭性能监控，不启用自动跑分、背景采样或内容亮度读回。Flutter 3.50 的独立 `cupertino_ui` 与库内部 SDK Cupertino 类型不同，因此采用 `GlassScaffold`，显式对齐玻璃主题亮度，并补入官方 SDK 中文本地化 delegate。

设置 `reduce_transparency` 进入正式 Protobuf 协议与全局设置，按 Worker API + D1 保存并收到确认后应用，不增加本地独立业务存储。客户端确认值比较包含该字段，错误 ACK 保留原草稿。

Web 默认使用标准质量，支持 shader filter 的引擎选择完整效果；实色与高对比使用零 blur 的 minimal 策略。库的 Reduce Transparency fallback 仍可能半透明，项目使用显式不透明材质。减少动态效果及禁用动画进入玻璃无障碍作用域。实际视觉和运行成本仍需正式浏览器产物验收。

## 当前工程证据

固定 Flutter 3.50.0 / Dart 3.14.0。正式 `pnpm flutter:check --concurrency=1 --reporter=expanded` 通过，包含三项目严格分析、Riverpod 生成一致性与 lint，以及 22 + 87 + 639 = 748 项测试。关键回归包含高对比/实色无 BackdropFilter、亮暗主题、材质切换保留焦点和草稿、隐藏工具仍显示待确认状态、Escape 回焦及资源释放。

实色设置回归覆盖草稿不提前应用、错误 ACK 拒绝、保留原操作重试与独立会话读回。Cloudflare 官方 Vitest 插件下 `state-workerd.test.ts` 的 46 项 Worker/D1 回归通过，覆盖跨会话读回、相同回执重放、旧写 CAS 冲突及切回玻璃。状态文字变化曾触发画布重排，已改为稳定状态槽位，恢复内容叠在其上；完整最终回归已包含阅读保存、Access 恢复及应用壳路径。

原始输出留在 ignored `.local/liquid-glass-evaluation/`。当前未运行本机完整 Flutter 编译、AOT、模拟器或真机；完整 Web 构建交给既有 CI。

## 代码量

原基线 `d7416f0ab5981b405dd5d8998158d3868b53971c` 为 30,296 行 / 91 文件。当前统计为 30,560 行 / 92 文件，净增 264 行，计入全部新增生产组件，排除 `.g.dart` 与 `/src/pb/`。用户明确选择本轮先完成视觉与交互，代码削减[另立重构](../plan/ui-code-consolidation.md)；不将此轮描述成代码量减少。

删去了详情更多菜单的重复树及宽屏手写侧栏，阅读主工具简化为翻页、页码和面板入口；全页导航、确认后的实色策略和持续恢复状态增加了集成代码。最终格式化后重新统计，测试、文档与生成模型单列。
