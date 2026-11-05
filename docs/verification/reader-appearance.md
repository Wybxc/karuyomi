# 阅读外观与输入设置验证

2026-11-06，正式设置链路新增阅读背景、应用内调暗、点击区和键盘预设。全局默认与逐漫画覆盖沿用 Worker API + D1，字段 presence、CAS、原请求重试和读回确认共用已有机制，未建立客户端业务存储。具体范围见[设置设计](../design/reader-settings.md)。

## 协议与真实 D1

- 合同测试 9 项及官方 Cloudflare Vitest / workerd 状态测试 31 项通过；新增一个 D1 组合覆盖四字段默认、覆盖、清空继承、显式调暗 0、原 ACK、无进度/漫画旁改及非法值无写入。
- 调暗范围是 0–80 整数。默认 0 在全局 ProtoJSON 中可以省略；D1 合并最终取 0，漫画 optional 的显式 0 则保持 presence，不误用全局非零值。背景和输入枚举拒绝未指定或未知值，响应有效值必须逐字段等于默认/覆盖的合并结果。
- 10 项协议 golden 通过；矩阵新增三类设置消息，使用正式 Protobuf-ES / Google Dart codec 完成双向 ProtoJSON 往返，包含完整偏好、显式 0、空覆盖与有效值合并。
- Dart 设置仓储 11 项通过；新增继承/显式 0 组合，既有丢 ACK、固定 UUID/正文/CAS 与非法回复用例扩展到四个新字段。客户端使用受控 supplier，和真实 D1 证据分别计算。

## 正式表单与阅读器

全局表单和漫画编辑窗提供黑/白/跟随主题背景、0–80% 调暗，以及标准/反向/关闭的点击区和键盘预设。漫画字段逐项继承，调暗开关和滑杆区分继承与显式 0。编辑基线、待确认原命令和身份失效行为沿用现有设置控制器；mode/layout 快捷选择合并整份覆盖，保留其它字段。

阅读器应用已确认值时保留原章节叶、逻辑锚和图片资源。调暗使用 Flutter 内容遮罩，工具栏、设置与显式导航保持可操作；连续模式的放大窗口随当前背景/调暗更新。分页点击区反向不改变滑动方向；中央工具栏保持可用。键盘反向只反转相对翻页，Home/End 仍到绝对首末，关闭时消费这些导航键。

全部设置测试 11 项通过，其中正式导航 3 项覆盖：

- 四字段全局提交前保持旧值，确认后 Reader 继承并应用；漫画逐字段清覆盖，显式调暗 0，mode/layout 快捷选择保留其它字段。
- 同一 Reader 叶收到确认后更新偏好，切章与退出重开保持已确认设置。
- 480×800 视口下真实滚动表单，API ACK 正文被截断后，同身份重开编辑器显示原命令，使用原 UUID/正文/CAS 重试，仅提交一次。

受控平台直接抛出 API supplier 错误会触发运行时容器丢失，不能冒充单次 API ACK 丢失；最后一个用例使用提交后截断 API 正文，保留控制通道。产品错误路径未为该测试放宽。`reader_screen_test.dart` 19 项通过，其中新增 4 项组合回归覆盖 LTR/RTL 点击区三种预设、中央工具栏与原滑动、键盘相对反转/绝对首末/关闭、80% 遮罩的输入穿透，以及连续模式滚动与放大窗口。外观更新保持逻辑锚，不伪造 observed、不重复获取或释放图片；放大窗口跟随当前设置，控件可用且退出后资源全部释放。相关严格静态分析和定向格式检查通过。测试采用受控图片组件，不是实际图片解码、浏览器或设备证据。

## 集中工程检查

- `pnpm format` 与完整 `pnpm format:check` 通过，覆盖所有项目自有语言和结构化配置。
- `pnpm check` 完整通过：生成一致性、portable 格式、严格类型与依赖层级、382 项 Vitest、10 项协议 golden 和全部工具回归。
- `pnpm flutter:check` 完整通过：reader_core 21、source_runtime 42、客户端 343 项，三个项目静态分析无问题。
- `pnpm build` 通过：正式 Web/Native runtime 资源、Flutter Web 与 Worker/Static Assets 构建成功；没有构建或运行新的 iOS/Android App。

本轮未部署生产；工程检查、受控组件与实际独立客户端验收分别计证据。

## 复验与剩余门槛

```sh
pnpm test:protocol
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
cd apps/reader
flutter test test/data/settings_repository_test.dart test/settings/ test/reader/reader_screen_test.dart
```

完整工程入口：`pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check`、`pnpm build`。使用仓库固定工具链；临时日志保留在忽略的 `.local/appearance-*.log`。

尚待两个独立客户端经真实 D1 验收四字段双向读回、继承/清空、并发、丢响应恢复与进程重启；Web/iOS/Android、生产 Access 和真机分别记录。本轮没有新增实际浏览器或 Native 运行证据。适宽/适高与裁白继续按 [P1](../plan/p1-library-and-progress.md) 推进，完整 P1/P2 保持未验收。
