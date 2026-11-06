# typed Source preferences 工程与运行验收

当前实现使用 `karuyomi-source-host-v6`，设计见[Source 设置](../design/source-preferences.md)，任务与完整验收门见[计划](../plan/source-preferences.md)。本记录区分工程检查、固定 AOT、真实 Source 与独立客户端结果。

## 已取得的工程证据

2026-11-06，main 的 Source 设置里程碑：

- `pnpm format` 后完整 `pnpm format:check` 通过，包含 macOS/Xcode 原生格式检查；`pnpm check` 完整通过，含生成一致性、依赖层级、类型、官方测试与工具回归。
- `pnpm flutter:check`：reader_core 22、source_runtime 58、reader 443 项全部通过，三个包严格分析无问题；新增产品数据/控制器/480×800 正式组件共 16 项通过，相邻浏览与筛选回归亦通过。
- `pnpm build`：声明式 Vite 的运行时与 Native assets、Flutter Web、Cloudflare Worker/API 构建通过；未据此宣称 Native 应用或真实 Source 设置已验收。
- `pnpm typecheck`：contracts、API 源码及测试、runtime-host、tools 和产品桥的严格 TypeScript 检查通过。
- `pnpm test`：声明式 Vite 构建通过，官方 Vitest 共 30 文件 / 418 项通过，包括 workerd 和真实 D1。测试关闭时的 pipe abort 诊断不改变退出结果。
- Node 定向合同/宿主回归 82 项通过：typed 值宽度、默认值与缺省、秘密分区、整体预算、get/edit 映射、driver 构造配置与可信策略、manager BigInt bootstrap、成功/veto/异常后的代次门及队列清理；包含旧 image/verified loader 回归。
- `pnpm test:protocol` 10 项通过，增加设置 bootstrap、描述、change、click、veto 及业务读写的 TS → Dart → TS / Dart → TS → Dart golden，保留标准 ProtoJSON 和 Protobuf 二进制一致性。
- `packages/source_runtime` 新增 11 项正式 Dart 测试通过，含生成 codec 的 int64 越界预拒绝、合法正负边界无损、嵌套 bootstrap、调用方变更隔离、编辑发送一次、成功/veto/异常后阻止 Source 与图片工作、保留 cleanup、新代恢复与旧响应丢弃。严格测试文件分析通过。
- `pnpm teavm:check` 的 HostPreferences oracle 125 断言通过，并通过完整现有 DTO、filters、HTTP、图片、enqueue、文件与网络检查；全部 owned Java 以锁定依赖执行 `javac --release 17` 通过。这是 JVM/oracle 与编译证据，不是 TeaVM AOT 或真实 Source。

统一预算覆盖最多 64 Sources、每源 128 entries / 32KiB、entries 数组总计 64KiB、完整 bootstrap 128KiB，以及树/选项/控制封装上限。未知文本、密码及未批准别名不得进入 API；真实 workerd/D1 的同步许可、幂等旧 ACK、独立 CAS、身份隔离和并发包配额共 5 个定向场景通过。

首轮完整 Flutter 检查发现一处 Dart 括号样式和旧测试第二包的非法身份；修正样式与真实包身份夹具后完整复验通过，未放宽产品校验。格式首轮还遇到并行文档草稿移出导致文件列表失效，冻结文件集后完整重跑通过。原失败日志保留。

详细临时日志位于 main 忽略目录 `.local/source-preferences-*.log`；Java oracle 和全源编译的临时日志在 `/private/tmp/karuyomi-source-preferences-*.log`。不提交机器输出或临时工程。

## 尚未通过的运行门

- [ ] v6 固定候选 AOT；不能复用 v5 的 CuuTruyen 筛选/分页证据。
- [ ] 真实 Source 设置入口：构造前偏好生效、原 change/click、veto、实际别名、动态依赖及重新浏览。Komiic 镜像必须通过原 `preferred_mirror` 控件选择，不能改 URL/JAR。
- [ ] 同一身份 Web 与独立 Native 读取/修改非敏感设置后收敛，确认旧 ACK 不回退 Source 构造基线。
- [ ] Web/iOS/Android 各自正式入口、取消/身份切换及秘密值仅当前会话的实际运行。
- [ ] 生产 Access 正向和目标真机门。

本次未部署生产、未修改扩展 baseline，也未把包标为 `runtimeReady=true`。AOT 编译、工程检查和真实阅读是独立验收层级。
