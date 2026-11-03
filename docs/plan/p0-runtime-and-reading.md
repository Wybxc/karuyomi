# P0 运行时与真实在线阅读

## 目标与状态

在已确定的 Flutter + TeaVM 路线上，使未修改的原版 Source 经真实网络、图片处理和资源通道进入可交互阅读器，并完成 Web、优先 iOS 的产品验收。状态：**进行中，P0 未通过**。

P0-F、P0-R、P0-A 可并行，P0-B 收齐二进制网络门后在 P0-C 汇合。工程发布另见[工程计划](engineering-and-release.md)，分项证据和复验命令见 [VERIFICATION](../VERIFICATION.md)。

## 已完成与边界

| 分项           | 已有实现或证据                                                                                                                                                                 | 尚不能据此认定的能力                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| P0-A 宿主      | release9 项目实现已内化；真正上游由 submodule/补丁追踪；按包 AOT、完整 DTO、显式漫画/章节引用、命名空间和静态交付已实现                                                        | 多源在线等价、文件/HTTP Cache 重启/取消/切换及完整 Access 动态请求                       |
| P0-F1 Web      | 串行 Worker、requestId/generation、清单/预算校验、取消/超时、Source ID 一致性和 Dart Web interop 已实现；真实 Chromium 初始化通过                                              | 六项操作全部在线成功和图片阅读                                                           |
| P0-F2 Native   | Dart 受管 WebView、可见登录、内置 host/Blob Worker 已实现；iOS 26.4 Simulator 本地受信 HTTPS 下初始化、cookie 携带及容器重建已有证据                                           | Cloudflare 生产 Access 正向会话、物理 iPhone、Android 真机与后台恢复                     |
| P0-F3 图片机制 | Web 产品已接原始 Page 会话、Source 图片链、64 KiB/ACK、Blob 资源及释放；真实章节首中末页解码通过；双端正式受管文件机制及进程重启、iOS 原 Source ReaderScreen 与进度恢复已验证  | Android 原 Source ReaderScreen、处理/解密源覆盖、任意阶段取消与合计峰值                  |
| P0-R 阅读核心  | 逻辑锚、单双页/LTR/RTL、竖向/Webtoon、缩放和有界 Provider 已实现；同路由切章、自动有界邻章准备、Drift 产品进度与 SQLite 文件/Web 关标签页及 iOS 原 Source 进程重启恢复分项通过 | 多源连续切章、浏览器进程/Android Source 重启、超长图、物理设备与性能分布                 |
| P0-B v2        | 帧协议、按需 Worker 流、operation/generation handle、Java Okio Source/有界上传 Sink 已实现；当前生产代码与构建清单统一为 v2，模拟 supplier 回归通过                            | 受控 HTTP、文件/Cache 同版分项已通过；真实 Source 缓存、Access、移动与合计资源门仍需验收 |

Java 的 `popular/latest/search/details/chapters/pages` 边界已返回完整 DTO，Long ID/日期跨语言使用字符串。当时 host ABI v2 的 Arknights Comics 在内置浏览器经真实 workerd/HTTP v2 通过热门、标题搜索、详情、章节与 51 页列表；首、中、末页经原 Source 解码和释放通过，实际 Flutter 已能打开章节阅读。latest 按源声明跳过。该证据使用显式本地政策与测试 JWT，不是生产 Access；详情见 [VERIFICATION](../VERIFICATION.md#web-产品图片通道)。当前 Protobuf 控制已升为 host ABI v3 / protocolVersion 2；固定 `6e08ec9` 后已重新构建并通过内置浏览器的同类 Source/图片分项，见 [v3 运行证据](../verification/protocol-v3-runtime.md)，Native 与剩余运行门继续验收。历史 MangaDraft 的文本搜索与挑战失败不因另一源的成功而变为通过。

`karuyomi.wybxc.cc` 已部署并验证公开入口、匿名 Access 拦截与生产登录后的正向 bootstrap；该生产版本仍为 protocolVersion 1，不能替代当前协议的 Source 请求验收。具体部署版本和历史浏览器环境只在验证记录维护。固定 `b6b5f47` Cache2 材料的 Arknights/CuuTruyen 元数据与首中末图片已重新通过；此前 Little Tyrant/Philia 列表为真实 403。三至五源完整覆盖、真实 Source 冷/热 Cache 命中对照仍未齐，见[实际 Source 记录](../verification/graphics-source-runtime.md)。

## 下一步

阅读连续性三个实现里程碑已接通：保留 Source 原序/反序与重复章节，用包含漫画/Source 作用域的章节键在同一 route 切章；新叶等旧调度、图片 pin、provider 清理确认后才安装。路由退出时，迟到 pages 与尚未挂载的新 provider 均有明确关闭者。有界下一章在真实末页 frame、窗口与 Source 空闲后自动准备，邻章不取图片；清理失败保留 owner 并阻止继续占用会话。正式目录/详情/Reader 已注入受信身份与 Drift 进度，SQLite 文件关闭重开回归通过；真实 Arknights 连续切章及关标签页重开的章节/页码/顺序恢复已通过，见[Web 产品进度](../verification/reader-progress-web.md)；iOS 原 xkcd 的正式 ReaderScreen 已通过受控入口下真实进程重启恢复章节、末页和完成状态；浏览器进程退出、Android Source 与完整日用流程仍待验收，另见[阅读记录](../verification/reader-continuity.md)与[进度记录](../verification/local-progress.md)。

存储细分推进见[运行时文件与 HTTP Cache](runtime-storage.md)，editor 生命周期机制门与原 JVM/正文语义门分别记录。

1. **收齐 P0-B。** 真实 workerd 与受控 origin 已通过压缩、重定向、Cookie、HEAD/206、204/205/304、精确 Range、urlencoded/multipart、流式上传、截断上传/响应和三类取消门。继续固定输入比较原 JVM 基线与当前 v2 的响应字节、原 Source 输出和异常；这些 Worker 分项不代替正式 Source/cache 或 Java 同版全部语义对照。当前只维护 v2，旧包需要重新构建。
2. **验证缓冲与取消。** META/DATA 最多 64 KiB，正文请求最多 8 MiB、响应最多 64 MiB，适配队列最多四块。检查慢消费者、背压、迟到响应和 generation 销毁能终止上游并释放 handle；整体请求预算和两次读取之间的 idle timeout 分别验证。协议细节见 [HTTP bridge](../HTTP-BRIDGE.md)。
3. **完成图片剩余门槛。** Web 单页及真实 Flutter 阅读闭环已通过分项门，合同见[图片资源通道](../IMAGE-RESOURCES.md)。正式 Native 文件通道已实现：Android 采用锁定插件的六个常驻 ArrayBuffer 槽位，iOS 使用受管 WKDownload 薄扩展；iOS 模拟器实际 Flutter Headless/受信 HTTPS、文件解码与清理通过，见 [Native 文件证据](../NATIVE-IMAGE-FILES.md)。iOS 原 xkcd 经正式 ReaderScreen 显示及进度重启已通过分项，继续用一致材料验收 Android 原 Source→Reader 与真机；机制分项不能代替这些门。内部 Bitmap/ImageDecoder 已改为二进制 handle、≤64 KiB 像素/字节块、解码前头部校验和 surface/decoder/font 合计账本；只查 bounds 不完整解码。JVM、受控时序、实际 TeaVM→Canvas 分项通过；取消仍等待 Java 退出，不扫描删除 Source 持有对象。详见 [graphics 合同](../IMAGE-RESOURCES.md#source-内部图形桥)。继续固定新 host 重新 AOT 并验收实际处理源；Cache/File 有界正文与共享 JVM/TeaVM 分项已通过，跨目录与合计存储预算、正式 Source 和移动环境继续按存储计划验收，终端与图形账本均不代表进程/GPU 实际峰值。不绕过插件直接读取原图 URL。
4. **汇合 P0-R / F4 / P0-C（章序、切章、有界准备与产品本地进度已实现，实际环境门继续验收）。** 保留 Source 原序/反序与重复章节，在同一阅读路由等待旧资源 ACK 后切章。末页由 Flutter 实际解码显示、图片窗口含清理均空闲且 Source 元数据槽空闲时，自动准备至多一个下一章页面会话；邻章不取图片，不推进进度。普通活动 Source 调用不冒充可抢占取消，过期准备结果等待返回后关闭。Drift/SQLite 分开保存当前位置、最远位置、阅读 epoch 与显式完成状态；节流写入，切章/退出/后台切换提交，写入失败保留可重试草稿。正式产品路由的 SQLite 文件关闭重开已覆盖章节、方向和页内偏移；继续验证浏览器进程、Android Source 和完整 Native 产品流程恢复。Web 数据库 WASM/worker 随静态资源交付，Native 使用正式 SQLite；内存与不安全多窗口模式明确提示，不冒称已保存。随后完成超长图降采样/分片验证、触控与缩放冲突、位置恢复、内存和首图测量。
5. **完成实际部署与恢复。** 在真实 Access、Web 和移动容器验证登录/过期/回跳、Cookie 恢复、执行槽/文件恢复、跨包切换和后台重建；不自动重发无幂等保证的副作用请求。

## 验收

- P0-A：原输入/工具链/ABI/实际执行身份一致；Source IDs 与清单吻合；文件与 HTTP Cache 在重启、取消和版本切换后语义正确。
- P0-B：Workers↔浏览器、浏览器↔Java 两段正文均无整段 Gson/Base64；固定输入字节/异常一致；慢消费缓冲有界，上游取消与 Access 通过。
- P0-F / P0-R：Web 与声明支持的 iOS/Android 真机完成 DTO、取消、容器恢复及图片释放；翻页、惯性滚动与缩放不争抢，旋转和布局切换保持逻辑锚。
- P0-C：3–5 个未修改原版源覆盖直图、特殊请求头、图片处理；完整章首中末页和下一章可交互阅读，进度落盘。记录手机/重包首图分布及进程/GPU 合计峰值，不用桌面或模拟器机制数字替代。

只在以上门槛汇合后标记 P0 通过；独立探针、编译、完整性或初始化成功分别保留其证据层级。
