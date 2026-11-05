# 非敏感阅读设置验证

2026-11-06，本轮优先完成现有三项设置的同步功能：全局应用主题、四种阅读模式、AUTO/SINGLE/DOUBLE 页组，以及阅读模式/页组的逐字段漫画覆盖。设计和继承语义见[设置设计](../design/reader-settings.md)。工程检查、受控组件与独立客户端验收分别计证据。

## 已取得的后端证据

- `pnpm generate:check` 通过，TypeScript/Dart 模型与 `business.proto` 一致；API 类型检查与依赖层级检查通过。
- contracts 业务边界测试 7 项通过，包含设置的枚举、完整默认值、optional 覆盖 presence、有效值合并与响应 revision 校验。
- 官方 Cloudflare Vitest / workerd / 真实 D1 状态测试 24 项通过。其中新增 5 项设置测试覆盖无副作用默认读取、逐字段继承、显式 AUTO、清空覆盖保留 revision 和旧写拒绝。
- 同一测试入口还覆盖 global/manga 并发的独立 CAS 与提交后确认快照、进度与设置互不改动业务 revision、幂等重试和 UUID 跨作用域/消息冲突、subject/请求头隔离、正文预算及 D1 batch 失败回滚。

## 客户端与集中工程结果

正式设置页和阅读页已接入同一身份绑定的设置仓储。全局表单显式保存，主题在读回服务端确认值后应用；阅读页快捷选择写漫画覆盖，弹窗可逐字段恢复继承。只读刷新不重发未确认操作；重新打开编辑器显示原命令值，冲突后明确重读，身份或仓储变化使旧编辑永久失效。

- 新增设置仓储 10 项、完整数据层 72 项通过：默认值、presence、独立作用域、固定 UUID/正文/CAS、ACK 后当前值读回及旧 ACK 冲突。
- 设置控制器/表单 8 项通过：确认前状态、原操作重试、身份变化后的迟到 ACK、全局继承、未编辑表单刷新、编辑后固定 CAS、逐字段继承/显式 AUTO，以及全局/漫画 pending 重开。
- 正式 `KaruyomiApp` 组件导航 2 项通过：保存前主题不变，确认后 MaterialApp 使用主题；详情进入阅读继承全局，阅读选择写漫画覆盖；弹窗逐字段恢复继承，AUTO 在切章和退出重开后保持，程序应用不产生额外设置写入。
- `pnpm check` 完整通过：372 项 Vitest、协议 golden 与全部工具测试通过，157 模块 / 509 依赖无违规。
- `pnpm flutter:check` 完整通过：reader_core 21、source_runtime 42、客户端 291 项，静态检查无问题。现有进度导航回归通过正式设置命令选择布局，并验证迟到 viewport 报告不能覆盖已确认偏好；更新测试未移除原进度、远端重开和来源顺序断言。
- `pnpm format`、完整 `pnpm format:check` 与 `pnpm build` 通过；正式 Web/Native runtime 资源、Flutter Web 和 Worker/Static Assets 构建成功。

这些客户端结果使用受控 Source/业务 supplier，不是独立浏览器、模拟器、生产 Access 或真机验收。官方 workerd/D1 证据与组件导航分开计算。详细临时输出保留在忽略的 `.local/settings-*.log`。

## 可复验入口

```sh
pnpm generate:check
pnpm --filter @karuyomi/api typecheck
pnpm check:dependencies
pnpm exec vitest run --project node packages/contracts/test/business-state.test.ts
pnpm exec vitest run --project workers apps/api/test/state-workerd.test.ts
```

完整工程复验：`pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check`、`pnpm build`。组件可定向运行 `flutter test test/settings/`；使用仓库固定的 Flutter SDK。

## 尚待验收与完整范围

- 两个独立客户端的 A→B / B→A 设置读回、继承/覆盖/清空、并发与丢响应恢复，以及新进程从 D1 恢复。
- Web/iOS/Android 实际组合、前台恢复、生产 Access、Native 触控与真机。
- 该轮三项设置之后，阅读背景、应用内调暗与点击区/键盘预设已继续接入，结果分别见[后续记录](reader-appearance.md)；适宽/适高与裁白仍待实现。

当前交付顺序见 [P1](../plan/p1-library-and-progress.md) 与 [P2](../plan/p2-sync.md)。生产、跨端和真机门未因上述工程与组件测试通过。
