# 文本布局运行证据

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

## 范围与正式入口

本阶段针对未经修改的 TextInterceptor 使用的 `Html.fromHtml(...).toString()`、`TextPaint`、旧构造器 `StaticLayout` 和 `draw`。正式共同场景为 `tools/teavm/TextLayoutScenarios.java`；真实 Canvas 机制场景为 `packages/runtime-host/test/text-layout-browser-suite.ts`。

原 Android 对照入口：

```sh
node tools/teavm/check-text-layout.ts
```

默认复用 `runtime/teavm/toolchain-lock.json` 固定的 JDK/Maven 路径，依赖与生成工程在忽略的 `runtime/teavm/.local/`。无需 seed 或项目 owned Android 类。可用 `--maven PATH --java-home PATH --repository PATH` 指定已准备工具与 Maven 缓存；官方测试依赖初次下载体积较大，不接入日常 CI。

```sh
pnpm typecheck:tools
pnpm typecheck:bridges
pnpm exec vitest run packages/runtime-host/test/text-layout.test.ts
```

TeaVM 浏览器侧沿用正式 `prepareSources`/`compileExtension` 流程，保留 owned class strip、当前 compat 和官方 TeaVM 0.16.0 插件；独立入口在线程中调用同份 `TextLayoutScenarios.run`。Canvas 侧由正式 `compileBridge('graphics')` 加测试 driver 组成 Worker，在 Codex 内置浏览器执行。临时 HTML/Maven 工程与机器报告留在忽略目录，不作为维护源码或对外接口。

## Android NATIVE 与浏览器证据

Android oracle 固定 Robolectric 4.17、API 35、`android-all:15-robolectric-13954326`、instrumented `15-robolectric-13954326-i7` 和 native runtime 1.0.19；JUnit 4.13.2、Gson 2.13.2 以及两项官方 AndroidX AAR 版本在正式 POM 固定。runner 校验框架/native/AAR 五个关键产物 SHA-256，再使用 offline SDK 目录，避免运行时另选框架 JAR。

在 macOS arm64/JDK 25 实跑通过 101 项共享检查。launcher 同时断言 API 35、`ShadowNativePaint`、`ShadowNativeBitmap`，以及 `TextPaint.class` 来自固定 instrumented SDK 资源 URL；没有以 SDK stub 或 AWT 替身充当原 Android。共同图片场景输出 1000×140 PNG、12820 字节、9536 个非白像素。

共同契约包括：HTML `<br>`、legacy/compact 段落、实体、ASCII 空白/换行与 tab、xkcd 3319 实际标题/alt；`TextPaint(Paint)` 与 `set(TextPaint)` 的复制差异；范围构造保留原 source/offset；空串/末尾空行、grapheme 不拆分、RTL/居中、行宽及 padding/baseline 恒等式。

反向检查也保留原 Android 的行为：Layout 构造会清零传入 TextPaint 的 `bgColor`/`baselineShift`；plain String 绘制快路径即便随后重设这两个 span 字段仍不应用它们。不能根据理想复制行为另造 Android 契约。

Codex 内置浏览器 Chrome 156 实际通过最新 Canvas 5 组及 TeaVM 同场景 101 项：Canvas 测量/多行绘字、段落方向、文本/行数/尺寸及独立 drawText 预算拒绝均通过；TeaVM 包含相同的 HTML、范围和行指标断言。两门结束后图形账本的 total/raster/surfaces/decoders/fonts/handles 全部归零。TeaVM 共同图片为 1000×190、22876 字节和 10468 个非白像素。两端默认字体不同，只证明约定语义及真实绘字，不声称高度、字体或 PNG 字节等价。

新增 HTML CRLF 场景最初在真实 TeaVM 失败，修复为解析前规范原始 CRLF/CR，再由 Jsoup 解码实体与生成文本投影；复验同份 101 项通过。原始失败记录留在忽略目录，不用先前 76 项结果覆盖新增场景。

## 限制与 Source 门

固定 `926b93d` 后，已通过正式 Source/Worker/HTTP v2 和原 TextInterceptor 复验 xkcd 3319 章两页：直图 106037 字节/607×716，文字 PNG 49246 字节/1000×286；两次 Blob 释放/撤销及 Page session 关闭均通过。原 JAR SHA 与旧门完全一致，未修改 Source/JAR；实际使用的材料、构建身份和复验命令见[Source 记录](graphics-source-runtime.md#新文字材料与-xkcd)。旧 host `15a3900` 的第二页 stub 失败仍保留，不能混用两个 host 的证据。

随后使用同一 `926b93d` xkcd AOT、材料和原 JAR，配合固定 `80841b` 的真实 Flutter Web 构建，在 Codex 内置浏览器的正式产品界面选择英文 Source、xkcd 与 3319 章。直图正常显示，切换到 2/2 后可见原 TextInterceptor 绘制的标题和完整 alt 文字，本地阅读进度保存；继续下一章进入 3318 正常。截图保留于本地 `/tmp/karuyomi-xkcd-text-page.jpg`。这是实际 Flutter 显示与单次跨章检查，不是生产 Access、Native 或连续负载验收。

独立 Canvas/Java 场景显式 recycle 后的图形账本归零，不能推广为实际 Source 的内部账本归零：原 TextInterceptor 创建 Bitmap 后没有 recycle，该 `926b93d` bridge End 仅关闭 byte handles 和 scratch，surface Map 仍需显式回收或 Worker 销毁。Source probe 只验证产品图片资源释放/撤销，没有采集内部 graphics ledger；长时间重复文字页可能耗尽 surface/内存预算，后续 typed lease 已通过独立 [Bitmap 所有权门](bitmap-lifetime-runtime.md)，之后已固定 `5148c60` 新材料重建同SHA原JAR，正式两页、原TextInterceptor80次处理和受控PNG编码取消分项通过，内部账本的空闲未回收与有界测试分配后回收见[新Source记录](graphics-source-runtime.md#新生命周期材料的原-xkcd-source)。这不改变926b93d的历史局限；生产Access和长期负载须另外验收。

styled spans、Builder/ellipsize、复杂富文本/制表位、所有 HTML 容错分支、Native 应用与真机字体/性能尚未验收。库规则版本与系统字体差异会影响输出；受控场景不能替代生产 Access、实际阅读、取消和长章节负载门。

依据：[linebreak 官方文档](https://github.com/foliojs/linebreak)、[bidi-js 官方 API](https://github.com/lojjic/bidi-js)、[Android 15 StaticLayout](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-15.0.0_r1/core/java/android/text/StaticLayout.java)、[Android 15 Layout](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-15.0.0_r1/core/java/android/text/Layout.java)、[Android 15 Html](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-15.0.0_r1/core/java/android/text/Html.java)、[Robolectric NATIVE 模式](https://robolectric.org/javadoc/4.17/org/robolectric/annotation/GraphicsMode.Mode.html)。
