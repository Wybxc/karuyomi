# Native 服务端同步集成测试

> 入口状态（2026-11-05）：Flutter 官方测试驱动保留；原 Source HTTP/HTTPS 配套服务已退役。下列命令是驱动使用模板，当前源码不能再按旧服务说明直接复验。新的官方 Workers/Browser fixture 尚未提供同等 Source + Native 完整在线链路，不能据工程测试将此门标为通过。当前重构见 [Vite 计划](../../../docs/plan/vite-build-and-testing.md)。

`server_sync_test.dart` 通过 Flutter 官方 `integration_test` 启动正式 `app.main()`，使用真正的 Native WebView、内置运行时材料、Source、阅读 UI 和业务 API。它不注入测试 PlatformRuntime、内存业务服务或图片 supplier。

## 前置条件

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
