# Reader 帧调度修复后的 Web 恢复验证

2026-11-04，固定 `31555e8` 加阅读器修复 `5267181`，实际独立 checkout 为 `19b65f5258e9097e92cf52f40f59f17728c8ad62`。主代理在 Codex 内置 Chromium 156 通过正式 Flutter 主入口、原 xkcd 两章阅读及关标签页后的首次末页显示。旧输入的首次黑屏报告保持失败，见[旧 Cache v3 Source 记录](cache-v3-sources.md)，没有用本轮通过覆盖历史结果。

## 修复与输入

Android 正式阅读曾在首图已显示后一直无法推进 observed；ignored 驱动只请求一次后续帧便恢复，作为诊断保留。产品 `ReaderScreen` 现于尺寸、位置恢复和 viewport 三处 post-frame 回调登记后调用 Flutter 官方 `ensureVisualUpdate()`。`addPostFrameCallback` 只登记回调，本身不请求帧；在帧尾收到解码通知时，需要正常调度后续帧。回归在旧码的 `hasScheduledFrame` 断言明确失败，新码通过并实际观测到 page 0，不以 `pumpAndSettle` 额外强制帧掩盖关键断言。

同轮全库格式化、完整 `pnpm check`、`pnpm flutter:check` 与真实 prek 均通过；Reader 应用为 90 项测试。修复后的双端模拟器结果另见[Native 记录](reader-frame-native.md)。Web 本轮通过说明该固定输入恢复正常，不把旧黑屏的所有可能原因认定为同一根因。

工作树为 `/Users/wybxc/.codex/worktrees/native-reader-frame-validation/karuyomi`，受跟踪文件干净。使用 Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4，正式 release 构建；没有测试专用 Flutter 页面或输入代码。原扩展与 runtime materials 保持原固定输入：

| 输入                    | 身份                                                               |
| ----------------------- | ------------------------------------------------------------------ |
| xkcd                    | `ext-all.xkcd-f7321a31dcfdb9d61c08decb2b525d28`                    |
| 原 JAR                  | `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d` |
| canonical 扩展 JS       | `9d3e21523c568bc178bcea8bb81c9833ce4edbd63cd0ec87e167e60b97ffc809` |
| runtime materials       | `63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d` |
| main.dart.js，3604376 B | `f66f896a8a9e9fef7ef325fe25c4b2c294b58a751078aa65c38989615e437027` |
| 实际 host.js            | `dcb101ab53b5359fb7c1ad32e622b0f3db119a9b5b0a2b0aea75e495d219a598` |
| 实际 worker.js          | `6a4774a2fd97464c0a986258ff8f89a3c064f494a33d34a25a5e903762145e3f` |

SQLite WASM 与 Drift worker 的实际文件摘要均符合固定官方资源清单。此输入尚未包含随后 `b4f72f7` 的默认 Source Cache 配置，不能据此声明正式 Source 缓存命中。

## 实际操作与结果

隔离 origin 为 `http://127.0.0.1:8927/`，实际 workerd / D1 使用受控 RS256 测试身份，允许 host 仅为 `xkcd.com,imgs.xkcd.com`。它不是生产 Access。主入口从“浏览→扩展→英文 xkcd→详情→3319: Elevators”进入正式 ReaderScreen，首张漫画与第二页原 TextInterceptor 文字图均实际可见，末页显式完成后显示“本地进度已保存／本章已读完”。同一路由下一章进入 3318: Earth Sized Planets，首图、文字图和显式完成同样通过。

关闭标签页 57 后，新开标签页 59，同 origin 重新连接原扩展与英文 Source，从详情点击“继续阅读”。直接恢复 3318 第 2/2 页、最远第 2 页及已读完状态，首次截图即可看到完整文字图与已保存状态。截图前未翻页、缩放、改布局、补帧或改变浏览器可见性；保持后台验证。该结果是标签页关闭重开，不是浏览器进程退出、设备重启或 Service Worker 更新验收。

## 复验与材料

```sh
# 固定 checkout，使用锁定 Node 与 Flutter SDK
pnpm install --frozen-lockfile
pnpm flutter:setup
pnpm --filter @karuyomi/runtime-host build
node scripts/flutter.ts build

# 原 xkcd 产物路径来自固定 31555 Source 验证树，不能替换成不同 seed 的同名包
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_IMAGES=1 SOURCE_PROBE_PORT=8927 \
SOURCE_PROBE_READER_DIR="$PWD/apps/reader/build/web" \
SOURCE_PROBE_EVIDENCE="$PWD/.local/reader-frame-web/network.json" \
node apps/api/test/source-metadata-probe.ts Xkcd_MANIFEST Xkcd_ARTIFACT_DIRECTORY
```

内置浏览器打开正式入口，按上述真实 UI 流程复验。需先构建 runtime-host，否则新 checkout 缺少 `dist/host.js` 无法连接；本轮首次测试树遗漏已记录在 ignored `server.log`，补齐后重载，未更改产品来规避错误。官方 Drift 首次下载遇到 HTTP/2 错误，保留 `build-download-failed.log`；随后预热既有、逐项摘要匹配的官方缓存，由未修改的构建器再次验证并生成。

本轮材料在固定树 ignored `.local/reader-frame-web/`：`input.json`、`ui-report.json`、`network.json`、构建日志与 `first.png`、`completed.png`、`next-first.png`、`next-completed.png`、`restored-first.png`。旧 main `.local/cache-v3-reader/xkcd-ui-report.json` 的失败和旧截图不改。临时材料不提交，也不把桌面分项扩展为生产 Access、Source Cache、Native 真机或性能通过。
