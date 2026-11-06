# 跨源搜索验证

2026-11-07，本地 macOS，Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。实现范围见[设计](../design/cross-source-search.md)，剩余验收见[计划](../plan/cross-source-search.md)。主代理实现正式搜索服务与运行槽接入，独立验收代理维护正式服务测试并只读审查；界面与控制器由另一子代理实现。

## 独立服务与界面回归

`apps/reader/test/search/catalog_source_search_test.dart` 的 10 项独立回归通过。它走真实 `CatalogController`、业务状态客户端、`TransportSourceRuntime` 和两个控制 transport，Source 返回与网络时序受控；没有执行官方扩展 AOT 或真实上游请求。

覆盖不同包两个槽并行与第三包等待、同包多 Source 串行、排队与启动取消、活动取消的真实 `runtimeLost` 合同、启动/活动重置 ACK 丢失后保留清理门和显式重试、账户精确来源替换后丢弃旧结果、活动阅读拒绝搜索，以及打开结果前等待旧槽关闭。搜索服务的物理清理确认与结果 epoch 检查分别断言，不能用拒绝迟到结果替代 Worker 已关闭。

验收中修复了三类问题：活动取消以 `runtimeLost` 结束时仍等待显式 reset ACK；启动取消的 reset ACK 丢失后，即使尚无 session 也登记待清理槽；取消与关闭按包单飞，避免两个并发 reset 使对方 ACK 失效。取消先发生时关闭等待该清理，关闭先发生时后续取消只等待关闭。

界面侧 12 项控制器与 5 项 Widget 回归通过，覆盖冻结查询与 Source 选择、分组结果、分页/重试/取消、明确限额、不自动复活旧身份、关闭失败重试、生命周期停止和正式详情导航。另有 Native 图片门回归确保 SEARCH / UNSPECIFIED 的 acquire、cancel、release 不影响前台图片。

宿主侧独立审查另发现同一 turn 并发 SEARCH dispose/open 会误用已退休 manager；先等待关闭并持续复查关闭状态后才选择 manager。新增正式 manager 回归已验证修复前失败、修复后通过，51 项该文件测试通过。

临时日志保留在 `/private/tmp/karuyomi-cross-source-search-*`，不提交机器输出。

## 集中工程检查

独立代理运行完整 `pnpm check`，退出 0：生成一致性、portable 格式、严格 TypeScript / tools / bridge 类型及依赖层级通过；33 文件 478 项 Vitest、10 项跨语言 golden、34 项登记/网络政策、50 项扩展工具、14 项构建、15 项完整性、4 项 TeaVM 与 9 项 Cloudflare 回归全部通过，共 614 项。

最终完整 `pnpm flutter:check` 退出 0：三个项目严格分析均无问题，Reader Core 22 项、Source Runtime 78 项、Reader 573 项测试通过，171 份自有 Dart 格式零变化。首次完整运行在测试后因尚未统一格式化而退出非零；统一格式后暴露的 13 处大括号 lint 已通过官方 `dart fix` 修复，再完整格式化与重跑上述检查，未降低分析门槛。

全库 `pnpm format` → 完整 `pnpm format:check` 通过，含 Java、Dart、TypeScript、配置和原生语言。`pnpm build` 通过 runtime-host、Native runtime 资源复制、Flutter Web release 与 API/Cloudflare Vite 构建；本次 Static Assets 为 57 文件、0 个 current extensions，因此只是工程构建，没有据此宣称官方 Source 在线能力。没有跳过正常 prek hook。

## 尚未通过的层级

本记录暂不证明当前固定输入 AOT、Codex 内置浏览器真实跨源搜索、真实网络错误隔离、Native、生产 Access、独立设备或真机性能。测试中的两个 transport 不能当作真实双 Worker 运行证据；Source 能力说明仅使用目录事实，不推断登录、验证码或脚本支持。
