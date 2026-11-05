# Reader 帧调度修复与 Native Source 重启复验

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，Reader 修复 `5267181` 已提交；从 Cache v3 基线 `31555e8` cherry-pick 后，独立验证树实际提交为 `19b65f5258e9097e92cf52f40f59f17728c8ad62`。Android 和 iOS 模拟器均完成原版 xkcd 的正式 Catalog → ReaderScreen 两页阅读、已保存 UI、进程重启恢复及最终清理。输入和操作仍由 ignored 夹具驱动，不代表生产 Access、人工物理手势、真机或性能验收。

## 固定输入

受管树为 `/Users/wybxc/.codex/worktrees/native-reader-frame-validation/karuyomi`，跟踪源码保持干净，三项上游 submodule pin 未变。使用仓库锁定的 Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4、`flutter_inappwebview 6.2.0-beta.3`。

- materialVersion：`63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`。
- 复用固定 `31555e8` 构建的 `ext-all.xkcd-f7321a31dcfdb9d61c08decb2b525d28`，未重编或修改 Source / 原 JAR。
- 原 JAR SHA-256：`4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d`。
- bundle SHA-256：`9d3e21523c568bc178bcea8bb81c9833ce4edbd63cd0ec87e167e60b97ffc809`；原始 4,035,206 B / gzip 852,496 B。
- 英语 Source ID：`1538249443376436084`；实际章节列表中的 `3319: Elevators`，两页。

正式 catalog、AOT provenance / manifest 与 Native 内置清单的六项材料引用逐项一致。复用的 Native host / worker 分别为 `168a20f474ad1448f98ddac7ad733a00f1ff1ceaf12b6ac9f0cd158a7533a444`、`d74b5fb8ac476af64b8b1df8d6dfcda5c93f1e8b2852dc2e92d76c084cbbbeb8`。本地复制复用已验证的字节，正式 loader 仍执行自己的传输边界校验。

独立 App ID 为 `dev.karuyomi.karuyomi.nativeReaderFrameFixture`。受信 `https://localhost:63324` 连接真实 workerd、独立 D1 与 RS256 测试身份 `probe-owner`，仅允许 `xkcd.com` / `imgs.xkcd.com`。共享材料的远端路径故意返回 503；终态 `forbiddenRequests:[]`，未发生 Native 网络回退。

iOS 为 iPhone 17 Pro Simulator / iOS 26.4；Android 为 Android 16 / API 36 Google APIs ARM64 r7，实际 WebView `133.0.6943.137`。iOS 使用系统正常信任与官方默认 TLS 处理；Android 仅在可丢弃的 debug App 中保留系统 CA，并对 exact `localhost` 配置专用 CA、`includeSubdomains=false`、`overridePins=false`、禁止明文。APK 内实际配置和证书已核对，证书执行时仍在有效期内。未修改产品信任或忽略 TLS 错误。

## 真实失败与修复边界

原 `31555e8` Android 首轮已显示漫画图，UI 显示本地已保存，但 `furthest` 始终为空；90 秒后以 `TimeoutException: observed first frame saved` 失败。此结果没有被后续成功覆盖。只在 ignored 驱动请求一次额外帧后，同一路径能够推进，确认了回调调度缺口；该次报告标明 `diagnosticExtraFrame:true`，不作为正式验收。

正式修复在 Reader 的 viewport、尺寸学习与位置恢复三个 `addPostFrameCallback` 登记点调用 Flutter 官方 `ensureVisualUpdate()`。新增测试在 post-frame 解码通知后直接检查 `hasScheduledFrame`，旧码实际失败、修复后通过，再以单个后续帧检查 observed；关键断言没有依靠 `pumpAndSettle` 补帧。正式 Native 复验驱动没有额外补帧代码。

新输入的 iOS 早期重启报告虽为 `passed:true`，但其 Flutter 截图的图片区全黑，因此派生的 `capturedVisualVerification` 明确为 false。原图、原报告与此判定均保留，不能只凭 `RawImage` 非空、`2 / 2` 或保存文字宣称视觉通过。

随后仅调整 ignored 驱动的截图同步：等待实际 `MaterialPageRoute.animation` 到 completed，保持页面以获取 OS 系统截图，并与 Flutter `toImage` 并列核对。没有改产品、Source、页码、布局或可见性，也没有添加补帧。两个截图均显示真实文字图及完整控制区。此等待属于测试捕获时机，不是新的产品能力或另一项产品修复。

## 最终结果

两端均经正式 `CatalogController → ChapterReaderRoute → ReaderScreen`、原 Source 图片处理、Native 文件通道和 Drift SQLite。原漫画响应为 106,037 B PNG；末页由原 `TextInterceptor` 生成文字图，没有改用原图 URL 绕过处理。

首轮使用合成 Pointer 触发正式下一页与启用后的“读完本章”。保存依据实际 observed frame；截图可见 `2 / 2`、文字内容、本地进度已保存和本章已读完。恢复分支不翻页，直接检查原数据库的 current / furthest / completed。

| 最终同安装重启                       | 真实进程变化  | 结果                                                                     |
| ------------------------------------ | ------------- | ------------------------------------------------------------------------ |
| Android `am force-stop` → `am start` | 9671 → 9842   | OS / Flutter 截图均直接显示末页、完整标题与已保存 / 已读完；全部清理成功 |
| iOS `simctl terminate` → `launch`    | 91852 → 98545 | OS / Flutter 截图均直接显示末页、完整标题与已保存 / 已读完；全部清理成功 |

上述两次最终重启之间没有重装、清数据或替换 SQLite。截图同步驱动安装后的首次运行和随后的真正重启分别保留；最终报告的 generation 与对应 capture stage 一致，且与前一进程不同，避免误读尚未被覆盖的旧成功报告。

最终报告在 route / provider 清理 ACK、进度 flush、platform dispose 和数据库关闭之后生成，任何相关异常均将 `passed` 置为 false。两端均为 true，未吞 dispose 错误。正常关闭本轮两个服务并移除 adb 63324 映射，保留模拟器与 App 数据。

这证明该固定输入下原 Source 的正常完整重读及 UI / 持久化 / 退出链路，不证明 Java HTTP Cache 命中、上游取消连接、当前 main 后续 API 改动、生产 Access、后台恢复或内存峰值。Cache v3 的独立移动引擎 39 组机制证据见 [cache-v3-native.md](cache-v3-native.md)。

## 复验与本地记录

夹具、服务编排与大产物只保留在新树 `.local/native-reader-frame/`。正式构建命令在其 `app/apps/reader` 执行，移除 `GH_TOKEN`、`GITHUB_TOKEN`、`CLOUDFLARE_API_TOKEN`，使用仓库固定 SDK 和 PUB_CACHE：

```sh
flutter pub get --enforce-lockfile
flutter build apk --debug --no-pub --target lib/fixture/main.dart
flutter build ios --simulator --debug --no-codesign --no-pub \
  --target lib/fixture/main.dart

# 安装完成后，重启两步之间不得再次 install 或清数据
adb -s emulator-5556 shell am force-stop \
  dev.karuyomi.karuyomi.nativeReaderFrameFixture
adb -s emulator-5556 shell am start -n \
  dev.karuyomi.karuyomi.nativeReaderFrameFixture/dev.karuyomi.karuyomi.MainActivity
xcrun simctl terminate <SIMULATOR_ID> \
  dev.karuyomi.karuyomi.nativeReaderFrameFixture
xcrun simctl launch <SIMULATOR_ID> \
  dev.karuyomi.karuyomi.nativeReaderFrameFixture
```

服务使用新随机 loopback 端口；本轮为 HTTP 63148 / HTTPS 63324，同一轮重启必须维持相同 origin。TLS 证书过期应正常更新和建立测试信任，不能跳过校验。正式 Source 服务由固定树 `apps/api/test/source-metadata-probe.ts` 驱动，测试配置及输入在 `input.json` / `materials-check.json`。

关键记录：

- `{android,ios}-reader-first-report.json`：新输入原首轮；`ios-reader-restart-visual-review.json` 保留早期黑图的视觉失败判定。
- `{android,ios}-reader-final-relaunch-report.json`：最终同安装重启及所有清理；同名前缀的 `stage.json` 可核对 generation。
- `{android,ios}-reader-final-relaunch-{system,flutter}.png`：最终系统与 Flutter 原图，未通过裁切或隐藏状态文字修正。
- `main.unsettled.dart` 与 `app/apps/reader/lib/fixture/main.dart`：截图同步前后驱动；`xkcd-network.json`、`native-resource-network.json` 为脱敏网络记录。

旧 `31555e8` 失败和单次补帧诊断仍在 `native-cache-v3-validation/karuyomi/.local/source-cache-v3/`；旧 `80c9…` App / 证据保持独立。
