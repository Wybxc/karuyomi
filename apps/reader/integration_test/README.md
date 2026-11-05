# Native 服务端同步集成测试

`category_sync_test.dart` 使用正式 `app.main()`、`NativePlatformRuntime` 和业务 repository 验证分类；独立于 Source 阅读。`server_sync_test.dart` 保留原阅读驱动，其旧配套服务状态单独见下节。普通无设备 `flutter test` 不执行本目录；`flutter analyze` 与仓库格式检查仍覆盖它。

## 分类同步

在仓库根目录构建正式产品与官方 HTTPS harness：

```sh
pnpm acceptance:build:native
NODE_EXTRA_CA_CERTS=/absolute/path/rootCA.pem \
WRANGLER_HTTPS_KEY_PATH=/absolute/path/key.pem \
WRANGLER_HTTPS_CERT_PATH=/absolute/path/cert.pem \
ACCEPTANCE_FIXTURE=categories pnpm acceptance:serve
```

证书必须包含 harness 实际 loopback hostname（当前为 `127.0.0.1`），由本轮可丢弃设备正常信任。iOS 可使用 `xcrun simctl keychain UUID add-root-cert /absolute/path/rootCA.pem`。Android 使用隔离 debug 副本的精确主机 Network Security Config，仅加入本轮 CA，并保留系统 CA、证书/hostname 检查与明文禁用；release 不加入测试 CA。不要修改系统全局信任或接受证书错误。Android 通过 `adb -s SERIAL reverse tcp:PORT tcp:PORT` 访问官方实际端口，不制造不同 APP_ORIGIN 别名。

官方 `createTestHarness()` 应用正式 D1 迁移，以临时 RS256 测试身份运行正式 API；可选 `ACCEPTANCE_FIXTURE=categories` 在就绪前经同一 API 创建“分类同步·甲”“分类同步·乙”两部受控收藏，初始无分类。它们只用于业务元数据测试，不可进入 Source 阅读；默认未设置 fixture 时仍为空 D1。测试不注入假 PlatformRuntime、业务服务或 Source supplier。

在 `apps/reader` 执行以下模板，`APP_ORIGIN` 使用服务实际输出，依次运行 A `create` → B `update` → A `verify` → B `delete` → A `verify-deleted`；A/B 是独立客户端安装，每个命令启动新进程。阶段严格核对前置状态，不要在已提交后盲目重跑写阶段。

```sh
flutter test integration_test/category_sync_test.dart --no-pub \
  -d DEVICE_ID \
  --dart-define=APP_ORIGIN=https://127.0.0.1:PORT \
  --dart-define=CATEGORY_PHASE=create \
  --reporter expanded
```

五阶段分别验证创建并关联甲、第二端读回后改名并关联乙、第一端重启读回两关系、删除分类保留收藏、第一端重启确认两部未分类。实际操作经过分类 UI，并由 repository 正常 API 重新读取已确认快照；每个阶段有操作预算和最终运行时释放，输出 `CATEGORY_SYNC_RESULT` 和 binding `reportData`。Web 双会话使用单独 HTTP 模式入口，证据与 Native 分别记录；同一 HTTPS 的混合会话须另行取得正常浏览器信任和实测结果。

本入口只证明实际执行的平台组合和操作，不代表 Source、生产 Access、同时写竞争、网络故障、物理触控或真机性能。当前证据见[分类同步记录](../../../docs/verification/category-ui-sync.md)。完成后按 Enter 关闭 harness，停止测试进程并删除本轮专用设备。

## Source 阅读驱动（旧服务已退役）

> 入口状态（2026-11-05）：`server_sync_test.dart` 的原 Source HTTP/HTTPS 配套服务已退役。以下阅读命令是驱动使用模板，当前源码不能再按旧服务说明直接复验。新的官方 Workers/Browser fixture 尚未提供同等 Source + Native 完整在线链路，不能据工程测试或分类验收将此门标为通过。当前重构见 [Vite 计划](../../../docs/plan/vite-build-and-testing.md)。

`server_sync_test.dart` 通过 Flutter 官方 `integration_test` 启动正式 `app.main()`，使用真正的 Native WebView、内置运行时材料、Source、阅读 UI 和业务 API。它不注入测试 PlatformRuntime、内存业务服务或图片 supplier。

### 前置条件

1. 准备当前 xkcd v4 构建、Native 内置材料与正式 Web 构建，入口见仓库构建说明。
2. 准备支持当前 Source HTTP、业务 API、同一身份和同一 D1 的测试后端，Web 与 Native 均需正常访问。原[Source 测试服务](../../api/test/source-metadata-probe.md)曾在同一进程提供 HTTP/HTTPS 代理别名，现仅保留历史说明；当前官方 fixture 不自动替代它，也不证明生产 Access/Cookie 行为。后端恢复前，本目录完整在线验收保持未完成。
3. Native 必须正常信任 HTTPS 证书。建议创建可丢弃模拟器，只向该设备添加本轮测试 CA；不修改产品 TLS、Mac 全局信任或已有设备信任，不接受证书错误。
4. 从内置浏览器的正式 UI 收藏英文 xkcd。初次运行测试前保留第 1 页进度或尚无进度；测试从服务端书架进入该作品。

在 `apps/reader` 使用固定 Flutter SDK 执行：

```sh
flutter test integration_test/server_sync_test.dart \
  -d IOS_SIMULATOR_UUID \
  --dart-define=APP_ORIGIN=https://localhost:8898 \
  '--dart-define=SYNC_CHAPTER_LABEL=3319: Elevators' \
  --dart-define=SYNC_START_PAGE=1 \
  --dart-define=SYNC_TARGET_PAGE=2 \
  --reporter expanded
```

测试等待真实图片 frame，使用正式上一页/下一页按钮导航，等待服务端已保存，再读取同一业务 API 核对 current/furthest。它输出 `SYNC_RESULT` 与 integration binding reportData，包含作品、章节、清单和已确认锚点，不输出 Cookie 或凭据。返回详情并等待章节入口恢复后，再关闭运行时，确保资源清理 ACK 已完成。

Native 成功保存后，在内置浏览器刷新并从书架继续阅读，核对恢复位置；反向验收时先从 Web 保存非默认位置（例如第 2 页），再使用全新 Native 安装和 `SYNC_START_PAGE=2` / `SYNC_TARGET_PAGE=1` 运行测试，排除默认首页掩盖恢复错误。回看后最远进度仍须不低于起始页和目标页。普通无设备 `flutter test` 不执行本目录；`flutter analyze` 与仓库格式检查仍覆盖它。

只有实际成功的测试才能登记平台门。测试驱动的模拟器 UI、生产 Access、物理触控和真机性能分别记录；结束后停止测试服务、关闭并删除本轮可丢弃设备，保留忽略目录中的必要报告。
