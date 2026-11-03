# P0 运行时与真实在线阅读

## 目标与状态

在已确定的 Flutter + TeaVM 路线上，使未修改的原版 Source 经真实网络、图片处理和资源通道进入可交互阅读器，并完成 Web、优先 iOS 的产品验收。状态：**进行中，P0 未通过**。

P0-F、P0-R、P0-A 可并行，P0-B 收齐二进制网络门后在 P0-C 汇合。工程发布另见[工程计划](engineering-and-release.md)，分项证据和复验命令见 [VERIFICATION](../VERIFICATION.md)。

## 已完成与边界

| 分项           | 已有实现或证据                                                                                                                                      | 尚不能据此认定的能力                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| P0-A 宿主      | release9 项目实现已内化；真正上游由 submodule/补丁追踪；按包 AOT、完整 DTO、显式漫画/章节引用、命名空间和私有交付已实现                             | 多源在线等价、文件/HTTP Cache 重启/取消/切换及完整 Access 交付        |
| P0-F1 Web      | 串行 Worker、requestId/generation、清单/预算校验、取消/超时、Source ID 一致性和 Dart Web interop 已实现；真实 Chromium 初始化通过                   | 六项操作全部在线成功和图片阅读                                        |
| P0-F2 Native   | Dart 受管 WebView、可见登录、内置 host/Blob Worker 已实现；iOS 26.4 Simulator 本地受信 HTTPS 下初始化、cookie 携带及容器重建已有证据                | Cloudflare 生产 Access 正向会话、物理 iPhone、Android 真机与后台恢复  |
| P0-F3 图片机制 | 独立字节/fiber 探针，以及模拟器 Worker → Blob → WKDownload → 文件的字节、取消和释放机制已验证                                                       | Flutter 产品图片插件、任意阶段取消、真实图片链与合计峰值              |
| P0-R 阅读核心  | Dart 逻辑锚、单双页/LTR/RTL、封面/横图独占、竖向/Webtoon、缩放、旋转恢复及有界 PageProvider 已实现                                                  | ReaderScreen 尚未接真实 Source 导航；无产品首图、超长图或真机性能结论 |
| P0-B v2        | 帧协议、按需 Worker 流、operation/generation handle、Java Okio Source/有界上传 Sink 已实现；当前生产代码与构建清单统一为 v2，模拟 supplier 回归通过 | 真实 HTTP 压缩、Source/cache、Access、浏览器与移动内存门仍需分别验收  |

Java 的 `popular/latest/search/details/chapters/pages` 边界已返回完整 DTO，Long ID/日期跨语言使用字符串。真实 MangaDraft 网络探针中热门/最新/搜索返回列表；原 Source 的普通文本搜索未把关键词传入 catalog，不能称为搜索匹配通过。详情/章节遇到源站 Human Verification 并明确失败，未伪造 pages 引用。产品 `acquireImage` 仍明确不支持，章节暂不可读。

`karuyomi.wybxc.cc` 已部署并验证公开入口及匿名 Access 拦截；生产登录后的正向 bootstrap/私有交付仍待验收。具体部署版本和历史浏览器环境只在验证记录维护。

## 下一步

1. **收齐 P0-B。** 真实 workerd 与受控 origin 的压缩、重定向、Cookie、HEAD/206、流式上传、截断上传和三类取消门已通过。继续固定输入比较原 JVM 基线与当前 v2 的响应字节、原 Source 输出和异常，补实际 Source/cache、204/304、Range、表单/multipart 及半途失败回归。当前只维护 v2，旧包需要重新构建。
2. **验证缓冲与取消。** META/DATA 最多 64 KiB，正文请求最多 8 MiB、响应最多 64 MiB，适配队列最多四块。检查慢消费者、背压、迟到响应和 generation 销毁能终止上游并释放 handle；整体请求预算和两次读取之间的 idle timeout 分别验证。协议细节见 [HTTP bridge](../HTTP-BRIDGE.md)。
3. **接通产品图片。** 实现 Java 图片入口及可取消/释放的 JS 资源 handle；保持原 Source 请求头、拦截器、解密/重排语义。连接 Dart PageProvider、Web 显示资源和原生受管临时文件；在现有 WebView 插件补 iOS 所需薄扩展，不绕过插件直接读取原图 URL，不用整图 JSON/Base64。
4. **汇合 P0-R / F4 / P0-C。** 从真实章节导航进入 ReaderScreen，补下一章、有界邻章准备和进度落盘。完成超长图降采样/分片验证、触控与缩放冲突、位置恢复、内存和首图测量。
5. **完成实际部署与恢复。** 在真实 Access、Web 和移动容器验证登录/过期/回跳、Cookie 恢复、执行槽/文件恢复、跨包切换和后台重建；不自动重发无幂等保证的副作用请求。

## 验收

- P0-A：原输入/工具链/ABI/实际执行身份一致；Source IDs 与清单吻合；文件与 HTTP Cache 在重启、取消和版本切换后语义正确。
- P0-B：Workers↔浏览器、浏览器↔Java 两段正文均无整段 Gson/Base64；固定输入字节/异常一致；慢消费缓冲有界，上游取消与 Access 通过。
- P0-F / P0-R：Web 与声明支持的 iOS/Android 真机完成 DTO、取消、容器恢复及图片释放；翻页、惯性滚动与缩放不争抢，旋转和布局切换保持逻辑锚。
- P0-C：3–5 个未修改原版源覆盖直图、特殊请求头、图片处理；完整章首中末页和下一章可交互阅读，进度落盘。记录手机/重包首图分布及进程/GPU 合计峰值，不用桌面或模拟器机制数字替代。

只在以上门槛汇合后标记 P0 通过；独立探针、编译、完整性或初始化成功分别保留其证据层级。
