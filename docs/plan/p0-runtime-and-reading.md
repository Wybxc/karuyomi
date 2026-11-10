# P0 运行时与真实在线阅读

## 目标与状态

在已确定的 Flutter + TeaVM 路线上，使未修改的原版 Source 经真实网络、图片处理和资源通道进入可交互阅读器，并完成 Web、优先 iOS 的产品验收。状态：**进行中，P0 未通过**。

P0 的实现选择以最简单直接的真实端到端路径为先：先完成可用阅读，再按实测瓶颈决定优化。当前保持 Flutter 直接解码；候选分片、LOD、多级缓存和额外抽象不因机制可行就进入默认路径。必要的类型、传输限额与资源生命周期保持有效。

P0-F、P0-R、P0-A 可并行，P0-B 收齐二进制网络门后在 P0-C 汇合。工程发布另见[工程计划](engineering-and-release.md)，分项证据和复验命令见 [VERIFICATION](../VERIFICATION.md)。

2026-11-05，项目将多端同步提升为首要设计目标。当前业务开发按 [P2](p2-sync.md)优先建立 Worker API + D1 权威状态与跨端确认语义，P1 的书架、进度和设置随该合同推进；P0 的真实阅读、生产 Access、Native 主入口和真机门继续保留，不作为推迟同步设计与实现的理由。收藏与进度现已切换到 D1；下述 Drift/SQLite 恢复结果仅记录历史实现，不能作为当前业务权威或跨端恢复的验收替代。

## 当前功能收尾（先实现，后集中验收）

2026-11-05 按用户要求先补齐静态审查发现的功能缺口，再集中验收。浏览/搜索、详情/章序、正式 Source 图片通道、阅读布局/翻页/缩放、切章/有界邻章准备与进度已有产品接线，业务进度随后已切换到服务端权威；以下四项现已补齐并通过集中工程回归；完整 P0 的实际环境验收仍未通过：

- [x] Access 失效进入阅读暂停：停止网络与预取，保留已交付图片和进度；用户手动认证后核对身份，重新打开当前章并恢复逻辑位置，不重放旧副作用请求。
- [x] 同身份/repo/package/schema 的运行 namespace 持有跨标签页独占写入槽；启动冲突明确提示，关闭、启动失败或 Worker 终止后释放。
- [x] 原 Source 的后台 `enqueue` 请求绑定发起 RPC，在主调用收尾前有界排空；取消、超时和迟到回调不能归入下一次 RPC，也不重试 POST。
- [x] Android 图片文件置于应用专属受管目录，新进程首次使用时清理崩溃遗留目录，正常关闭只删除当前 store 的文件。

本轮先完成四项功能，再集中运行回归、构建与实际环境验收。提交前格式化、静态类型与依赖检查继续执行。生产 Access、Native 主入口、真机与性能门是独立的待验收项，不通过重复采样代替缺失功能；候选分片、LOD 与性能优化不扩大本轮实现范围。

功能行为、集中工程回归和新 ABI 的交付限制见[功能收尾记录](../verification/p0-feature-completion.md)。随后固定 `1f599cd` 已重编三个 v4 官方扩展，并通过 Web 元数据/原处理图片、xkcd 正式阅读及跨标签占用/释放分项，见[v4 运行记录](../verification/v4-source-runtime.md)；实际 TeaVM 的 owner/嵌套 enqueue/取消分项见[回调记录](../verification/teavm-enqueue.md)。固定 `13494a0` 的正式客户端/API 与这三包已部署，匿名静态交付及远端网络政策核对通过，见[生产记录](../verification/v4-production.md)。生产 Access 会话曾失效，用户自行登录后已[确认 Web 恢复到正式书架](../verification/server-state-production.md#生产-web-恢复登录态)；同一生产会话已通过 [Arknights Comics 英文热门列表](../verification/server-state-production.md#生产-web-真实-source-列表)，详情、完整阅读与 Native 恢复仍待验收。历史三源证据仍按原提交保留。

当前 v4 正式 `lib/main.dart` 的 iOS Simulator App 与 Android arm64 调试 APK 已构建并核对实际包内材料、SQLite 映射和导出，见[Native 成品记录](../verification/v4-native-main.md)。该次因 CUA 无法连接 Simulator 而未安装/启动；随后已通过 Flutter 官方 `integration_test` 在独立 iOS/Android 模拟器启动正式 `app.main()`，以真实 xkcd 完成图片、服务端保存及三端组合双向非默认页续读，见[Web/iOS](../verification/native-server-state.md)和[Android 配对](../verification/android-server-state.md)。生产 Access、真机、Native 视觉/触控、后台恢复和性能仍待验收。

真实 TeaVM 的后续组合门已通过 64/65 pending callback 上限、约 30.05 秒 fatal drain、正式 manager 回收/排队拒绝/连接关闭及同 namespace 新 Worker 恢复，详见[回调组合记录](../verification/teavm-enqueue.md#实际-callback-上限fatal-drain-与-manager-回收)。产品常量未缩短，不能将受控 Source 成功推广为生产 Access 或 Native 通过。

当前 v6 MANGA Plus Creators 修复前的 iOS 第 3 页中途超时有[独立逐块对照](../verification/aot-current-pilot.md#manga-plus-creators-的-ios-图片超时对照)。源站读取空闲与整体预算已分开，[Workers 与 Host 回归](../verification/aot-current-pilot.md#http-读取空闲与总期限回归)通过。[iOS 实测](../verification/aot-current-pilot.md#manga-plus-creators-的-ios-完整章节与续读)保留修复后首轮第 33 页未解码及后续同页恢复；独立第二轮通过 Sense Life 完整首章、正式下一章与新进程从第 7 页恢复后读至第 35 页。[Android 模拟器](../verification/aot-current-pilot.md#manga-plus-creators-的-android-完整章节与续读)用同版本的冻结 AOT 构建复验，同样逐页读完首章 72 页，切至次章并从新进程续读。继续其它代表 Source、真机和生产 Access 验收；完整 P0 未通过。

ToonLook 的长图重排已通过 [Web 完整章节分项](../verification/aot-current-pilot.md#toonlook-的长图重排完整章节与续读)。[iOS 模拟器首图诊断](../verification/aot-current-pilot.md#toonlook-的-ios-首图失败)确认静态解码和重排成功，Canvas 请求 WebP 时回 PNG，原 Source 因而在图片交付前失败。[隔离编码探针](../verification/aot-current-pilot.md#toonlook-的-ios-webp-编码探针)用 libwebp 1.6.0 输出真正的 WebP，真实首章、切章和新进程续读通过。[正式共享图形桥与材料](../verification/aot-current-pilot.md#正式-webp-编码材料与图形桥)已接入固定工具链、有界堆、输出账本和既有取消机制。下一步用匹配的新材料与独立 AOT 候选复验 iOS 正式阅读及其它平台，不修改正在运行的冻结全量。iOS 正式阅读门仍未通过。

冻结 v6 [Arknights Comics Android 分项](../verification/aot-current-pilot.md#arknights-comics-的-android-完整章节与续读)已实际显示《DREAM》完整 51 页、完成、跨章及新进程非首页续读；[同库 Android↔iOS](../verification/aot-current-pilot.md#arknights-comics-的-android-与-ios-模拟器接力)的续读接力已通过。真机、生产 Access 与其余 P0 门另验。

同一冻结批次的 [CuuTruyen Native 分项](../verification/aot-current-pilot.md#cuutruyen-的-native-完整章节与跨端续读)已验证原 Source 处理后的第 142 章全部 23 页、显式完成、正常下一章，以及 Android → iOS → 新 Android 进程的同库续读。完整候选、生产 Access 和真机另验。

## 已完成与边界

固定 `2c012db` 已通过与冻结 v6 候选匹配的 [iOS arm64 发布构建及包内材料核对](../verification/native-main-entry.md#v6-ios-arm64-发布构建)。成品未签名；匹配部署、实际安装与真机阅读另验。

同一固定产品的 [Android arm64 发布构建与冷启动](../verification/native-main-entry.md#v6-android-arm64-发布构建与离线模拟器冷启动)通过。使用本地调试签名在专用模拟器侧载了实际 release APK；此次离线启动不覆盖连服务、实际阅读或真机。

Native 通用安装包已接入[本机服务地址恢复](../verification/native-main-entry.md#native-本机服务地址恢复)。用户手动选择有效的 HTTPS 地址后，下次启动以该地址连接；没有本机偏好时用构建默认值。业务状态仍以对应服务为准。

[Native 可见登录回跳](../verification/native-main-entry.md#native-可见-access-回跳)已改为消费精确的本次回跳地址，并由正式运行时重新确认身份。iOS 和 Android 模拟器的首次登录、会话失效后重登及保留 Cookie 的进程重启已通过真实操作和独立 D1 审计；生产 Access、阅读恢复和真机仍须另验。

[iOS Arknights 阅读性能基线](../verification/reader-baseline-ios.md)取得 debug 模拟器真实首图、翻页、滚动和跨章帧及 App RSS。此轮验证了采集方法，不替代物理设备的首图分布、合计峰值与触控验收。

| 分项           | 已有实现或证据                                                                                                                                                                    | 尚不能据此认定的能力                                                                                                 |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| P0-A 宿主      | release9 项目实现已内化；真正上游由 submodule/补丁追踪；按包 AOT、完整 DTO、显式漫画/章节引用、命名空间和静态交付已实现                                                           | 多源在线等价、文件/HTTP Cache 重启/取消/切换及完整 Access 动态请求                                                   |
| P0-F1 Web      | 串行 Worker、requestId/generation、清单/预算校验、取消/超时、Source ID 一致性和 Dart Web interop 已实现；真实 Chromium 初始化通过                                                 | 六项操作全部在线成功和图片阅读                                                                                       |
| P0-F2 Native   | Dart 受管 WebView、可见登录、内置 host/Blob Worker 已实现；iOS 26.4/Android API 36 模拟器正式主入口、三端组合双向续读、真实图片和 D1 确认分项通过                                 | Cloudflare 生产 Access 正向会话、Native 视觉/触控、物理设备与后台恢复                                                |
| P0-F3 图片机制 | Web 产品已接原始 Page 会话、Source 图片链、64 KiB/ACK、Blob 资源及释放；真实章节首中末页解码通过；双端正式受管文件机制及进程重启、双端模拟器原 xkcd ReaderScreen 与进度恢复已验证 | 更广 Native Source、正式主入口、任意阶段取消与合计峰值                                                               |
| P0-R 阅读核心  | 逻辑锚、单双页/LTR/RTL、竖向/Webtoon、缩放和有界 Provider 已实现；同路由切章、自动有界邻章准备、D1 确认与三端非默认页续读分项通过；历史本地恢复证据保留                           | 多源连续切章、实际跨端并发、浏览器进程恢复、超长图、物理设备与性能分布                                               |
| P0-B v2        | 帧协议、按需 Worker 流、operation/generation handle、Java Okio Source/有界上传 Sink 已实现；当前产品源码与构建清单统一为 v2，模拟 supplier 回归通过                               | 受控 HTTP/文件/Cache 同版及 Web xkcd fresh Cache/Worker 重建已通过；更广 Source、Access、Native 与合计资源门仍待验收 |

Java 的 `popular/latest/search/details/chapters/pages` 边界已返回完整 DTO，Long ID/日期跨语言使用字符串。当时 host ABI v2 的 Arknights Comics 在内置浏览器经真实 workerd/HTTP v2 通过热门、标题搜索、详情、章节与 51 页列表；首、中、末页经原 Source 解码和释放通过，实际 Flutter 已能打开章节阅读。latest 按源声明跳过。该证据使用显式本地政策与测试 JWT，不是生产 Access；详情见 [VERIFICATION](../VERIFICATION.md#web-产品图片通道)。此前 Protobuf 控制升为 host ABI v3 / protocolVersion 2；固定 `6e08ec9` 后已重新构建并通过内置浏览器的同类 Source/图片分项，见 [v3 运行证据](../verification/protocol-v3-runtime.md)，Native 与剩余运行门继续验收。历史 MangaDraft 的文本搜索与挑战失败不因另一源的成功而变为通过。

`karuyomi.wybxc.cc` 历史 protocolVersion 1 部署曾通过公开入口、匿名 Access 拦截与生产登录后的正向 bootstrap。当前生产 v4 / protocolVersion 2 已通过匿名静态入口、Access 拦截、Web 恢复登录和真实 Source 热门列表；生产图片与完整阅读继续验收。具体部署版本和历史浏览器环境只在验证记录维护。固定 `b6b5f47` Cache2 材料的 Arknights/CuuTruyen 元数据与首中末图片已重新通过；此前 Little Tyrant/Philia 列表为真实 403。三至五源完整覆盖、真实 Source 冷/热 Cache 命中对照仍未齐，见[实际 Source 记录](../verification/graphics-source-runtime.md)。

## 下一步

[六材料 Native 阅读中 Access 恢复](../verification/native-main-entry.md#android-阅读中-access-失效与原位恢复)已通过 Android 只读失效后同章同页恢复并直接退出，D1 不变；[iOS 有待确认进度时的复验](../verification/native-main-entry.md#ios-阅读中-access-失效与待确认进度)确认重登只读，显式重试只提交原请求一次，控件收起不写入，主动翻页仍保存。[iOS](../verification/native-main-entry.md#ios-阅读中切换身份)和 [Android](../verification/native-main-entry.md#android-阅读中切换身份)模拟器都已验证切换测试身份时退出原阅读、旧草稿不重发、新身份独立保存和冷启动读回。生产 Access、真机和最终签名安装包另验。

当前 v6 材料已在正式 Web 读完 ToonLook 英文源 Doomed 的第一章、进入第二章并逐页显示，两章各 10 页，新文档首次续读恢复到第二章第 10 页；五个实图样本的条带重排与独立参考相符。[验收记录](../verification/aot-current-pilot.md#toonlook-的长图重排完整章节与续读)只覆盖这一作品的 Web 分项。继续补相同材料的代表源、Native 实图和真机性能。

阅读连续性三个实现里程碑已接通：保留 Source 原序/反序与重复章节，用包含漫画/Source 作用域的章节键在同一 route 切章；新叶等旧调度、图片 pin、provider 清理确认后才安装。路由退出时，迟到 pages 与尚未挂载的新 provider 均有明确关闭者。有界下一章在真实末页 frame、窗口与 Source 空闲后自动准备，邻章不取图片；清理失败保留 owner 并阻止继续占用会话。历史目录/详情/Reader 曾使用受信身份与 Drift 进度，SQLite 文件关闭重开回归通过；当前业务读写已改为 Worker API + D1，历史本地数据库证据不代表跨端恢复。真实 Arknights 连续切章及关标签页重开的章节/页码/顺序恢复已通过，见[Web 产品进度](../verification/reader-progress-web.md)；iOS/Android 模拟器原 xkcd 的正式 ReaderScreen 已分别通过受控入口下真实进程重启恢复章节、末页和完成状态；浏览器进程退出、真机与完整日用流程仍待验收；随后固定 `19b65f5` 的 Cache v3 原 Source 双端重启也已通过[分项复验](../verification/reader-frame-native.md)，另见[阅读记录](../verification/reader-continuity.md)与[进度记录](../verification/local-progress.md)。

固定 `31555e8` 的 Cache v3 新材料已通过 Web 三源元数据与首中末图片分项，xkcd 正式 Flutter 两章阅读和显式完成也通过。但关标签页后虽恢复原章末页与完成状态，文字图首次显示为空黑，翻页后才正常；首次恢复视觉门仍失败，见[当前材料记录](../verification/cache-v3-sources.md)。该旧失败保持原状；随后固定 `19b65f5`（加入 `5267181`）的正式 Web release 已通过同类两章及关标签页首次恢复文字图，见[修复后 Web 记录](../verification/reader-frame-web.md)，不推广到其他 Source 或浏览器进程恢复。

Android 当前材料首轮显示后未推进 observed，已定位为 post-frame 回调登记后没有请求后续帧。ReaderScreen 的尺寸、恢复与 viewport 调度现使用 Flutter 官方 `ensureVisualUpdate()`；新增解码在帧尾通知的回归，旧码明确没有后续帧，修复后正常观测。阅读相关 43 项及 Dart 分析通过；修复后 Web 首次恢复与双端模拟器的真实 Source / 进程重启均已按固定 `19b65f5` 通过，详见[Native 修复后记录](../verification/reader-frame-native.md)；不把诊断补帧结果计为产品通过。Web 旧黑屏与该问题是否完全同因仍未确定。

存储细分推进见[运行时文件与 HTTP Cache](runtime-storage.md)，editor 生命周期机制门与原 JVM/正文语义门分别记录。固定 `b4f72f7` 的新 AOT 原 xkcd 已通过 Web fresh metadata Cache，以及实际 manager dispose/Worker 终止后新 manager/Worker 的同 namespace 正文复用，7187 B 读至 EOF、零网络、原 PageList 摘要一致；详见[原 Source Cache 证据](../verification/source-network-cache.md#原-source-cache-跨-managerworker-重建复用)。这是同一浏览器文档内重建。随后原 xkcd 也通过双端模拟器的正式 Native Java Source 冷/热 Cache 与容器重建复用，见[Native Source Cache](../verification/source-cache-native.md)。首发六材料的正式 iOS 与 Android App 又通过实际退出和重开后的 xkcd 章节 HTML 复用。iOS 核对了磁盘正文摘要；Android 清除本地 App 数据后，同一 D1 账号的相同章节恢复完整 HTML 请求。浏览器进程重启、扩展更新后的复用、更多 Source、生产 Access 和 Native 身份切换仍待验收，Web 产品身份分项见下文。

同一新 host 的 Arknights DREAM 51 页与 CuuTruyen Chương 142 的 23 页，已在正式 Flutter Web 主入口逐页显示、保存并显式完成，随后正常阅读下一章开头，见[完整章记录](../verification/full-chapter-web.md)。本轮发现的手动双页选择被末页控件覆盖已补正式回归并修复；固定 `be5c3ed` 的正式 Flutter Web release 已通过修复后末页单页保持、保存/显式完成及返回详情分项，原 b4 完整章与布局失败记录保留。重连身份空窗与迟到控制结果污染新会话也已通过正式 Dart/SQLite 回归修复，见[重连记录](../verification/runtime-reconnect.md)。随后固定正式客户端通过 Web 原 xkcd 的 A→B→A 主入口分项：B 无 A 的继续阅读，返回 A 首次恢复第 2 页文字图；三个新 Worker 的 namespace 为 A/B/A，A 的 7187 B 元数据经真实 ETag 304 再验证后从 store 读至 EOF。记录器首轮失败保留，独立 origin 的修复后队列和关闭证据完整。该门使用受控 RS256，不代表官方版本更新、Native 身份切换或生产 Access 恢复。

1. **收齐 P0-B。** 真实 workerd 与受控 origin 已通过压缩、重定向、Cookie、HEAD/206、204/205/304、精确 Range、urlencoded/multipart、流式上传、截断上传/响应和三类取消门。继续固定输入比较原 JVM 基线与当前 v2 的响应字节、原 Source 输出和异常；这些 Worker 分项不代替正式 Source/cache 或 Java 同版全部语义对照。当前只维护 v2，旧包需要重新构建。
2. **验证缓冲与取消。** META/DATA 最多 64 KiB，正文请求最多 8 MiB、响应最多 64 MiB，适配队列最多四块。真实 workerd 的持续发送与显式 TCP reset/idle 门已使用 30 秒请求期限、1 秒取消窗口分别通过；固定 Web 主入口的原 Arknights 图片获取中退出、未完成 HTTPS 及时关闭、恢复阅读及最终 Worker/遥测/服务清理也已通过限定分项，见[取消证据](../verification/source-cancellation-web.md)。继续检查慢消费者、背压、迟到响应和 generation 销毁能终止上游并释放 handle；整体请求预算和两次读取之间的 idle timeout 分别验证。生产 Access、Native 与其它图片阶段不由本轮替代。协议细节见 [HTTP bridge](../HTTP-BRIDGE.md)。
3. **完成图片剩余门槛。** Web 单页及真实 Flutter 阅读闭环已通过分项门，合同见[图片资源通道](../IMAGE-RESOURCES.md)。正式 Native 文件通道已实现：Android 采用锁定插件的六个常驻 ArrayBuffer 槽位，iOS 使用受管 WKDownload 薄扩展；iOS 模拟器实际 Flutter Headless/受信 HTTPS、文件解码与清理通过，见 [Native 文件证据](../NATIVE-IMAGE-FILES.md)。iOS/Android 模拟器原 xkcd 经正式 ReaderScreen 显示及进度重启已分别通过固定材料分项，Cache v3 固定 `19b65f5` 原 xkcd 双端模拟器分项已复验，继续验收真机；机制分项不能代替这些门。内部 Bitmap/ImageDecoder 已改为二进制 handle、≤64 KiB 像素/字节块、解码前头部校验和 surface/decoder/font 合计账本；只查 bounds 不完整解码。JVM、受控时序、实际 TeaVM→Canvas 分项通过；取消仍等待 Java 退出，不扫描删除 Source 持有对象。详见 [graphics 合同](../IMAGE-RESOURCES.md#source-内部图形桥)。继续固定新 host 重新 AOT 并验收实际处理源；Cache/File 有界正文与共享 JVM/TeaVM 分项已通过，跨目录与合计存储预算、正式 Source 和移动环境继续按存储计划验收，终端与图形账本均不代表进程/GPU 实际峰值。不绕过插件直接读取原图 URL。当前图片交付边界已收敛为仅含身份、位置与编码字节数的不透明资源，不读取 MIME、尺寸或 EXIF，不提供 Source 编码页/分片/window 控制。Flutter 从实际 ImageInfo 学习尺寸并负责显示、布局和解码预算；这轮工程回归不自动继承旧版本的在线/终端验收。
4. **汇合 P0-R / F4 / P0-C，验收服务端进度确认。** 章序、切章与有界下一章准备已有实现：保留 Source 原序/反序与重复章节，在同一阅读路由等待旧资源 ACK 后切章；邻章不取图片，不推进进度。普通活动 Source 调用不冒充可抢占取消，过期准备结果等待返回后关闭。历史 Drift/SQLite 的章节、方向和页内偏移恢复证据继续保留，业务读写已移除。当前按 [P2](p2-sync.md)由 Worker API + D1 保存当前位置、最远位置、阅读 epoch 与显式完成状态；节流发送，切章/退出/后台切换尽力提交，服务端确认后才显示已保存。未确认草稿仅保留在当前会话，失败仍能阅读并可重试，不承诺关闭后恢复。测试身份下三端组合的独立会话/安装已通过双向非默认页恢复，见[Android 配对](../verification/android-server-state.md)，继续覆盖生产、真机与实际并发/前台重取；完整跨端一致性按 P2 验收。Source 文件/HTTP Cache 与图片资源的本地存储仍各自保持既有所有权和限额。UI 直接解码的首图、跳转、滚动、CPU/RSS/GPU baseline 与真机验收继续，区域 decoder、降采样或分片只依据实测决定。
5. **完成实际部署与恢复。** 在真实 Access、Web 和移动容器验证登录/过期/回跳、Cookie 恢复、执行槽/文件恢复、跨包切换和后台重建；不自动重发无幂等保证的副作用请求。

历史 `be5c3ed` Web 主入口通过官方 Arknights 1.6.1 → 1.6.2 的静态快照更新、重新连接与 DREAM 第 3 页首次续读；两版章节会话均关闭、两 Worker 最终终止，见[版本更新证据](../verification/extension-version-web.md)。新版以真实上游 200 重新写入正文，未验证换版后 HTTP Cache 正文复用。同期 Native 主入口因工具无法操作 Simulator 未安装或启动，见[当时的准备与阻断](../verification/native-main-entry.md)。

随后固定 `426536d` 的正式 iOS 模拟器通过 [xkcd 1.6.1 同版本构建替换](../verification/extension-version-native.md)：明确确认新构建，清理旧扩展代码缓存，新进程从书架首次续读恢复同一真实第 2 页，D1 阅读状态与确认前一致。Native 上游版本升级、Android 换版、真机和生产 Access 仍待验收；P0 完整门槛不变。

图片解码按[独立子计划](reader-image-decoding.md)推进：Source/host 只交付不透明编码资源，Flutter 以实际 ImageInfo 尺寸更新布局与预算，退休资源计费保留至释放 ACK。当前仍为客户端整图显示，后验账本不证明初次 decoder 临时分配或 GPU 峰值有界，也没有调高整图预算。未采用的自研 codec 候选源码和专属工具已删除，历史评估保留原输入与限定结论。先完成真实 UI 直接解码 baseline，并在相同输入/设备比较首图、跳转、滚动、CPU/RSS/GPU，再决定是否采用成熟区域解码、降采样或分片；Source 不重新感知图片信息。历史编码页/host tile 机制证据保留并标为已替代，原失败不覆盖。真实长图、EXIF/LOD、真机和实际峰值继续待验。

协程执行语义另按[官方核心与平台适配计划](coroutine-runtime.md)收敛：优先复用已锁定的官方 JAR，只保留必要的平台与宿主集成。隔离 AOT 成功不等于已替换产品路径；首次真实挂起与 operation 所有权门通过后再删除当前自有入口。

Native 启动确认超时或关闭时的旧代退役已修复并通过[定向插件边界回归](../verification/runtime-reconnect.md#native-启动确认超时)。Android 模拟器的[真实启动、显式平台重建、UI 重连与关闭](../verification/runtime-reconnect.md#android-模拟器复验)通过。固定 `2c012db` 的 [iOS 模拟器同服务重连](../verification/runtime-reconnect.md#ios-同服务重连与真实续读)也通过：同一 App 进程经正式设置重连，新 Source generation 和图片绑定重新解码 xkcd 第 2 页，独立 HTTPS 六路业务响应逐字节不变。实际丢启动确认、Source 自动触发重建、生产 Access 和物理设备另验。

## 验收

- P0-A：原输入/工具链/ABI/实际执行身份一致；Source IDs 与清单吻合；文件与 HTTP Cache 在重启、取消和版本切换后语义正确。
- P0-B：Workers↔浏览器、浏览器↔Java 两段正文均无整段 Gson/Base64；固定输入字节/异常一致；慢消费缓冲有界，上游取消与 Access 通过。
- P0-F / P0-R：Web 与声明支持的 iOS/Android 真机完成 DTO、取消、容器恢复及图片释放；翻页、惯性滚动与缩放不争抢，旋转和布局切换保持逻辑锚。
- P0-C：3–5 个未修改原版源覆盖直图、特殊请求头、图片处理；完整章首中末页和下一章可交互阅读，进度经 Worker API 确认保存到 D1，全新客户端可恢复已确认的逻辑位置。跨端并发与冲突门按 [P2](p2-sync.md)验收。记录手机/重包首图分布及进程/GPU 合计峰值，不用桌面或模拟器机制数字替代。

只在以上门槛汇合后标记 P0 通过；独立探针、编译、完整性或初始化成功分别保留其证据层级。
