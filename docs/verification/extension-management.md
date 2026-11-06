# 扩展管理验证

设计见[账户扩展与本机准备](../design/extension-management.md)，待办与验收条件见[计划](../plan/extension-management.md)。当前状态为**默认仓库功能和集中工程检查通过，实际平台验收继续进行**；以下区分定向、独立集中检查与实际 Source、独立客户端及 Native 层级。

## 定向 TypeScript、D1 与协议

2026-11-06，本地 macOS，主树基于 `830161c` 的未提交扩展管理变更。使用固定 Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4 和项目工具链；测试没有部署或改动正式 baseline/checkpoint。

- 四个 contracts/runtime 文件共 72 项通过：新控制合同、真实 Node Web Locks 配合 `fake-indexeddb@6.2.7` 的产物缓存、正式 manager 与 loader。
- 业务合同与官方 workerd/D1 两文件共 50 项通过：账户 installed 清单读写、替换、移除、CAS、原 UUID 重试，以及其它全局设置保留。API 与 contracts 严格类型检查通过。
- `pnpm typecheck` 全部通过，包含协议/contracts/API/runtime-host、工具和桥。
- `pnpm test:protocol` 10 项通过，生成 TS↔Dart 的 ProtoJSON/二进制 golden 包含新管理控制与 enabled true/false 的账户记录。首轮遗漏 `FLUTTER_ROOT` 导致 Dart ENOENT，保留失败后按正确环境重跑通过；不将其写成产品行为失败或跳过项。

定向复验入口：

```sh
pnpm exec vitest run packages/contracts/test/extension-management.test.ts packages/runtime-host/test/extension-artifact-cache.test.ts packages/runtime-host/test/manager.test.ts packages/runtime-host/test/verified-loader.test.ts
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
pnpm typecheck
pnpm test:protocol
```

实际检查范围：

- 账户 URL、字段、128 项限额和 package 唯一约束；新控制请求/响应的 descriptor、digest、预算与结果语义。D1 保存的是账户意图，本机缓存不作为业务权威。
- 缓存 metadata/bytes 原子预算、跨实例读写、复制后存储、重开、重复准备不重复计费、事务 abort、shared pin 和排他删除。受控 IndexedDB 不等同于实际浏览器/WebView 持久性或系统磁盘压力。
- 准备只用正式静态加载路径，不创建 Source Worker 或调用 Source；验证后缓存命中不重复 hash，失败不终止已活动 Source；清理取消并等待准备，迟到下载不能重新写回已删除副本。
- 精确 close 等待 Worker ACK，关闭期间拒绝 open；活动请求下拒绝关闭，shutdown 失败不伪报成功；新槽建立后旧代 close 不会关闭新代。测试使用受控 Worker supplier，不能据此声称官方 Source 已排空。

临时日志分别保留在 `/private/tmp/karuyomi-extension-management-*.log` 和 `/private/tmp/karuyomi-extension-intents-validation-20261106/`，不将原始机器输出入库。上述计数属于已执行批次；之后新增回归与最终检查以实际补录为准。

## 独立审查与恢复回归

独立验收发现并修复了清理失败 Future 永久阻止重试、承接未保存进度后安装订阅漏重绑、关闭期间继续接收新请求，以及真实 Worker shutdown 失败后仅重试 close 无法恢复的问题。组件回归保留原资源身份和占用直至 ACK，不通过丢弃资源或伪造 shutdown 成功绕过失败。

新增正式 manager/loader 回归通过：准备的真实停滞 stream 在 60 秒超时取消，活动 Source 保持可用；dispose 排空期间拒新调用、迟到准备结果被拒；Native 准备只检查内置材料身份，缺失不网络回退；跨 loader 的已验证产物命中不重新 hash。shutdown 失败后的旧 close 继续失败，独立 rebuild 返回 completed 后可清理缓存并打开新代，未将 reset 说成 closed ACK。manager 与 loader 两文件最终定向 69 项通过，日志在 `/private/tmp/karuyomi-extension-runtime-lifecycle-tests-green.log`。

## 独立集中工程检查

2026-11-07，全库格式通过后，独立验收代理在冻结代码上顺序完成正式检查与构建；本轮结果如下：

- 全库 `pnpm format` → 完整 macOS `pnpm format:check` 通过，包含全部项目自有语言。
- 完整 `pnpm check` exit 0：生成一致性、portable 格式、严格类型、依赖层级、正式测试构建、32 文件 445 项 Vitest、10 项跨语言 golden，以及全部注册、扩展、工具链、完整性、上游 patch 和 Cloudflare 工具测试通过。
- 完整 `pnpm flutter:check` exit 0：三包严格分析无问题，reader_core 22、source_runtime 63、Reader 470 项测试全部通过，151 个 Dart 文件格式无变动。管理页、四打开路径的未安装/停用门禁、原请求失 ACK 恢复、更新/取消、订阅重绑、精确清理重试和 Native 文件占用均有回归。
- 完整 `pnpm build` exit 0：Web/Native 运行时 JS 与内置资源、Flutter Web 和 API Static Assets 均构建成功；实际装配 57 静态文件、0 current extensions。这是空扩展目录的工程构建，不是 Source 或原生 App/设备验收。
- 独立审查确认原全局 UUID/body/CAS、缺记录不自动安装、取消与迟到结果、精确关闭与显式 reset、跨实例缓存引用和已确认停用的调用门禁。`git diff --check` 通过。

首轮完整检查保留两类失败：Native 直接 import 测试漏设新增 Vite define；五项旧 Flutter 夹具没有为新身份/新构建明确安装。补齐夹具后重跑完整检查通过，未在产品自动安装、弱化原业务断言或跳过检查。独立验收本轮再次检查到 IAB inventory 为空，未尝试其它浏览器。

最终日志为 `/private/tmp/karuyomi-extension-management-acceptance-{check,flutter,build}-green.log`；定向管理/Native 45 项与四个旧夹具文件 39 项的日志留在同目录 `karuyomi-extension-ui-*` / `karuyomi-extension-fixtures-final.log`。临时机器输出不提交。

## 待实际运行验收

当前 Codex 内置浏览器 provider 不可用：可用 browser 清单为空，创建 IAB 标签返回 `Browser is not available`，`open_in_codex` 仅 queued；未操作其它桌面浏览器。生产 Access 用户选择稍后登录，该会话不作为本轮已完成证据。

尚待在符合当前元数据/协议的新固定 AOT 与正式客户端完成：

- Web / iOS / Android 的安装准备、明确更新、启停、卸载、占用/清理，以及真实 Source 打开和阅读。
- 两个独立客户端同身份读回相同账户选择；空缓存客户端准确显示未准备。并发改全局设置、ACK 丢失、旧 CAS 冲突与原请求重试不覆盖其它已确认值。
- 活动章节、请求与跨实例 namespace/产物占用下，关闭、取消、迟到结果及清理失败恢复；卸载保留全部业务、Source 数据与 HTTP Cache。
- 下架构建提示与 `build_not_found` 分层，不自动换版，也不把缓存命中当在线能力。
- 生产 Access 和真机门；当前没有新 AOT、Native App 构建/运行、部署或 checkpoint 变更。

额外仓库添加、移除与网络政策接入仍未实现，须依完整 P3 另做真实用例；默认仓库管理入口不计为这项能力通过。
