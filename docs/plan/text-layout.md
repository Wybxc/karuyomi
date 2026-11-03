# 文字布局与 TextInterceptor

## 目标

由项目宿主实现扩展实际使用的 Android 普通文字布局接口，让未经修改的 TextInterceptor 通过原请求链生成第二张 PNG。换行和双向文本规则使用固定第三方库，绘字与测量使用真实 Canvas；不得用原图绕过插件处理。

## 当前状态

- 已实现 `TextPaint`、`Layout.Alignment`、旧构造器 `StaticLayout` 和 `Paint.FontMetrics`，包括 UTF-16 范围偏移、padding、行距、原始/可见行宽、段落方向和普通文本绘制。
- Unicode 换行使用 `linebreak@1.1.0`，段落方向使用 `bidi-js@1.0.3`；grapheme 边界交给 `Intl.Segmenter`。两库规则基于 Unicode 13，不声明与每版 Android Unicode 数据完全等价。
- `Html.fromHtml(...).toString()` 使用已有 Jsoup 解析器，补齐已激活 TextInterceptor 所需的换行、段落、实体和空白投影；不实现 styled spans 或完整 HTML 渲染器。
- 每次布局/绘字检查 8192 UTF-16 units、512 行、16384px 尺寸、4096px 字号和 64 倍横向缩放；控制/结果保持 64KiB，布局临时工作区计入图形预算并在终态释放。HTML 输入/输出与嵌套深度另有上限。该预算不代表整个 Java 堆已有统一限额。
- 正式 Android NATIVE oracle 与同份 TeaVM Java 场景覆盖 plain TextPaint 状态、范围构造、换行/emoji/RTL、padding、行宽和 HTML 投影，包含 xkcd 3319 的真实标题/alt。实际结果见 [验证记录](../verification/text-layout-runtime.md)。

- 固定 `926b93d` 新 host 后，官方 Gradle 重建得到与旧门 SHA 完全一致的原 JAR；正式 Source probe 已通过 3319 章两页，包括原 TextInterceptor 生成的 1000×286 PNG，Blob 释放/撤销与 Page session 关闭通过。旧 `15a3900` 的 stub 失败证据仍保留，身份与结果见[Source 记录](../verification/graphics-source-runtime.md#新文字材料与-xkcd)。

- 配合同一原包/AOT 与固定 `80841b` Flutter Web 构建，已在正式产品界面看到 3319 章直图和 2/2 标题/完整 alt 文字，保存进度并正常进入下一章3318。截图与限制见验证记录。
- 已实现 Bitmap typed JSO lease 与标准 WeakRef/FinalizationRegistry 回收；Canvas 保留真实 Java 强引用，活 owner 不因 End 或预算压力被逐出。原 Android/TeaVM 共享 Bitmap13 与 Text101、真实 Canvas 五组及真实 Java 未显式 recycle 的自然 GC 分项通过，见 [所有权证据](../verification/bitmap-lifetime-runtime.md)。固定 `5148c60` 后已重建相同SHA的官方 xkcd 原 JAR，正式两页与80次原 TextInterceptor 处理通过；内部账本、空闲未回收、有界测试分配后回收及PNG编码取消分项见[Source记录](../verification/graphics-source-runtime.md#新生命周期材料的原-xkcd-source)。

## 后续阶段与验收

1. 扩展HTTP/解码等阶段的原Source取消与Worker终态验收；本轮已覆盖受控的真实PNG编码等待阶段，返回cancelled、无迟到发布且同generation恢复获取。不能将该门推广到所有阶段或所有Source。
2. 继续实际长章节和长期负载，分别记录活owner、reservation和进程/GPU实测。80次处理跨64成功且处理中自然回收，但空闲15秒未归零的原始观测已保留；有界普通JS对象分配后的回收也单独记录。标准GC没有固定触发时机，不能承诺外部画布内存及时回收或永不触及64-surface上限，不能逐出活owner。
3. 推进生产Access、Native Bitmap生命周期和实际连续阅读；Android oracle与Web内部账本不等于Native应用生命周期或真机性能通过。

当前支持普通文本及 HTML 字符串投影。styled spans、StaticLayout.Builder、ellipsize、复杂制表位/富文本、所有 HTML 容错情形和各平台字体一致性未验收。系统默认字体可改变断行、尺寸和 PNG 字节；不能把不同字体的图片声称为像素等价，也不能用这一点掩盖接口契约错误。
