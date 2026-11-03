# 文字布局与 TextInterceptor

## 目标

由项目宿主实现扩展实际使用的 Android 普通文字布局接口，让未经修改的 TextInterceptor 通过原请求链生成第二张 PNG。换行和双向文本规则使用固定第三方库，绘字与测量使用真实 Canvas；不得用原图绕过插件处理。

## 当前状态

- 已实现 `TextPaint`、`Layout.Alignment`、旧构造器 `StaticLayout` 和 `Paint.FontMetrics`，包括 UTF-16 范围偏移、padding、行距、原始/可见行宽、段落方向和普通文本绘制。
- Unicode 换行使用 `linebreak@1.1.0`，段落方向使用 `bidi-js@1.0.3`；grapheme 边界交给 `Intl.Segmenter`。两库规则基于 Unicode 13，不声明与每版 Android Unicode 数据完全等价。
- `Html.fromHtml(...).toString()` 使用已有 Jsoup 解析器，补齐已激活 TextInterceptor 所需的换行、段落、实体和空白投影；不实现 styled spans 或完整 HTML 渲染器。
- 每次布局/绘字检查 8192 UTF-16 units、512 行、16384px 尺寸、4096px 字号和 64 倍横向缩放；控制/结果保持 64KiB，布局临时工作区计入图形预算并在终态释放。HTML 输入/输出与嵌套深度另有上限。该预算不代表整个 Java 堆已有统一限额。
- 正式 Android NATIVE oracle 与同份 TeaVM Java 场景覆盖 plain TextPaint 状态、范围构造、换行/emoji/RTL、padding、行宽和 HTML 投影，包含 xkcd 3319 的真实标题/alt。实际结果见 [验证记录](../verification/text-layout-runtime.md)。

## 后续阶段与验收

1. 在新 host 构建身份下重建未修改的 xkcd 原包，保留旧 `15a3900` host 在第二页 `TextPaint` stub 失败的证据。
2. 经真实 Source 请求、原 TextInterceptor 和正式二进制图片通道取得两页；第二页必须是包含可见文字的有效 PNG，并验证释放/撤销后图形账本归零。构建成功和独立 Java 场景均不代替此门。
3. 更新 Source 在线验证记录，再推进生产 Access 和实际客户端阅读；Android oracle 不等于 Native 应用或真机通过。

当前支持普通文本及 HTML 字符串投影。styled spans、StaticLayout.Builder、ellipsize、复杂制表位/富文本、所有 HTML 容错情形和各平台字体一致性未验收。系统默认字体可改变断行、尺寸和 PNG 字节；不能把不同字体的图片声称为像素等价，也不能用这一点掩盖接口契约错误。
