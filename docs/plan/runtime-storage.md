# 运行时文件与 HTTP Cache

## 目标与状态

为未修改的 Source 提供持久文件与原 OkHttp 缓存语义，在 Worker 取消、异常终止、重建和扩展版本切换后保持完整条目、句柄所有权与有界资源。状态：**进行中**。Cache 正文、namespace 总预算与普通文件核心已通过分层机制门；原 JVM/TeaVM 的共享 CacheInterceptor 场景已通过。iOS/Android 模拟器的 Cache 桥 39 组机制及最终容器销毁也已通过；真实 manager 的 namespace 切换与同键 Cache/files 256 MiB allocated 组合门已通过受控 ABI 分项；原 xkcd 的 Web 元数据 fresh Cache、实际 manager/Worker 重建，以及双端模拟器正式 Native runtime 的原 Java Source 冷热 / 容器重建复用已通过新 AOT 分项；App / 浏览器进程重启、更广 Source 与产品切换仍待验收。

已有浏览器桥机制门覆盖正常持久化、namespace 隔离、Cache editor 竞争/CAS 和文件 rename/unlink；图片 JVM oracle 明确使用 cacheless 链，不是 HTTP Cache 语义验收。证据参见 [Worker 桥](../verification/worker-bridges.md)，P0 总目标参见 [运行时计划](p0-runtime-and-reading.md)。

## 阶段一：Cache editor 生命周期

**已实现并通过机制门**：2026-11-03，Codex 内置浏览器 Chromium 156 使用正式产物通过十组生命周期与失败终态回归；真实 Worker 终止后新 Worker 的首次 begin 成功，未等待旧五分钟过期时间。该结果不代表原 Java CacheInterceptor 或 Source 语义验收。

已完成：

- 每个 Cache Worker 持有一个 Web Lock；终止 Worker 自动释放，不再使用五分钟时钟判断 owner 是否失效。
- Cache 操作先取得 namespace owner 快照，在 IDB 事务外用 Web Locks 探测死亡 owner，再以独立原子事务清理其跨目录 editor/reader。不会等待锁时持有 IDB 事务；显式终态清理不先等待这项探测。
- editor token、Java handle、entry version 和 clear generation 继续约束提交；外来 Worker 不能提交或 abort 活 owner 的 editor。Java `Cache.close()` 只清理对应 handle，不影响同 Worker 的其他 Cache 实例。
- `put` 的真实 IDB request failure 等到事务 abort/回滚结束后，再以独立小事务按 editor、Worker/Java handle 和 generation 清理；原始失败仍向调用方报告。清理不会删除期间替换的 editor、owner 或 generation。
- begin 在第一个异步等待前登记 pending attempt，close/delete 同步失效同 handle 的在途 attempt；主事务复查，避免关闭后迟到 begin 重建锁。Java delete 先标记 closed，再发送明确的 delete 操作；evictAll 仍为 clear，不关闭 handle。完成后即删除跟踪记录，不保留无限增长的 closed handle 历史表。
- 独立正式浏览器入口为 `packages/runtime-host/test/cache-lifecycle-browser-suite.ts` 和 `cache-lifecycle-worker.ts`；由正式 `compileBridge('cache')` 产物驱动，使用真实 Worker、IndexedDB 和 Web Locks。

验收：A 写入完整条目后 begin 新 editor，活 A 期间 B 竞争失败；terminate A 后 B 立即 begin 成功，旧完整字节/版本保留，旧 editor 无法提交；活 Worker 锁不被误清理；并发唯一 editor、Java handle close、CAS 和 clear generation 均保持有效。附加门以真实 IndexedDB `ConstraintError` 触发产品事务 abort，验证旧完整条目不变、活 Worker 的下一次 begin 成功，及清理期间替代 editor/真实活 owner/新 generation 不被误删；另以受控 Web Locks 探测延迟验证 close/delete 先完成时在途 begin 被拒绝，clear 后原活 handle 仍可 begin。故障与延迟只由测试 driver 注入，存储和锁仍使用浏览器标准实现。严格类型检查使用 `pnpm typecheck:bridges`。临时服务和原始报告留在忽略目录，不作为维护源码。

## 阶段二：有界 Cache 正文

**核心正文通道、namespace 预算与受控 Java 场景已通过，产品验收仍进行中**。移除产品 Cache 的正文 Base64 与整段 Java Buffer；使用精确依赖 `idb@8.0.4` 的 typed schema 与 `tx.done`，不另建通用存储包装。当前数据库为 `teavm-http-cache-v3`，原型不维护旧格式迁移；固定分区与结构计费见[Cache 存储设计](../design/runtime-cache-storage.md)。

已接线：

- 小 JSON 控制不超过 64 KiB，metadata 不超过 48 KiB。`get` 仅返回 metadata/version/generation/reader/length，`begin` 接收 metadata，`commit` 原子发布完整 body 指针。
- `teaCacheRead(reader, javaHandle, maximum)` 和 `teaCacheWrite(editor, javaHandle, sequence, bytes)` 传递不超过 64 KiB 的二进制块；Java 同样逐块复制，写 ACK 在实际事务提交之后。editor 与 reader 均校验 Worker/Java handle 所有权。
- IDB 拆分 entries、bodies、chunks、editors、readers、directories；size、URLs、304 update 和 LRU 只读 metadata。读者 pin 不可变 body，replace/remove/clear/delete 仅移除当前引用，旧 snapshot 在最后 reader EOF/close 或死亡 owner 回收后释放。
- 每目录可见上限为 `min(maxSize, 64 MiB)`，逻辑 allocated 计入 current、staging、retired-but-pinned 正文和响应 metadata，上限为该目录可见预算两倍。全 namespace 全部 Cache 目录合计 allocated 128 MiB、结构 metadata 4 MiB；32 个目录 tombstone、4096 current entries、4224 bodies、64 editor、64 reader、32 有引用 owner、16384 chunks，单 body 最多 8192 块。所有动态主键/索引键计费；未知 size/get/clear 不造目录。usage 与记录增删同事务，跨目录 LRU 和死亡 owner 回收释放可回收的副本，活 pin 不提前退款。
- 普通 get/begin/read/write 每 Worker pending 4；close/reader-close/abort 走清理旁路，不因普通窗口已满遗留 pin，不宣称终态 Promise 或进程内存总上界。事务 5 秒超时后 abort 并等到终态，再独立 CAS 清理；每块 read 使用直接 lookup，不全表扫描。allocated/结构 reservation 是应用逻辑政策，不是浏览器实际磁盘占用。
- commit 与 metadata update 若无法在保留活 editor 的前提下达到可见预算，会原子回滚并拒绝发布；commit 再独立清理原 editor。close/delete 的原事务失败后，独立事务仅清对应 Worker/Java handle 的 staging editor，保留旧 current、打开 reader、sibling 和其他 owner；原始失败仍报告，清理失败聚合两个错误。
- reader-close 的原事务失败后，以 readerId/Worker/Java handle/directory 验证独立清理；不因 Java 已标记释放且不会重试而遗留 retired pin。原错误保留，清理再失败则聚合错误；错 handle、兄弟和外来 owner 不被误清理。
- Java `CacheSink` 将存储 IOException 或容量拒绝转为一次缓存 abort，精确消费本次 write 的剩余 count，后续仅丢弃缓存副本，网络正文继续；程序参数错误不宽泛吞掉。原网络读取异常仍传播，已发布 cache-hit 的读取故障不擅自重新请求网络。
- `pnpm teavm:check` 已接入 CacheSink 正式 JVM 边界门：19 项检查覆盖 65536/65536/7 分块、额外未请求字节保留、写入/提交拒绝、存储异常和关闭期间的计数及终态。正式 Cache/Bridge 六源 javac、严格 TS 和 bridge unit 6/6 均通过；这些结果不代替实际 TeaVM JSO、CacheInterceptor 或 Source 验收。

2026-11-04，主代理 Codex 内置浏览器 Chromium 156 使用正式 compileBridge 产物通过 **39 组**：保留原 27 组生命周期、chunk 损坏及真实事务失败门，新增 namespace 预算矩阵。以生产长度 64hex namespace 和真实 8 KiB 块填满 128 MiB/16384 chunks，另以 64 KiB 块验证两 Worker 竞争最后一个正文字节；验证跨目录 LRU/retired pin、全域 reader/editor/owner、metadata/UTF-8、小 chunk 放大、目录 tombstone、pending 清理旁路、死亡 owner 跨目录回收和账本真实 abort。测试没有篡改 usage 假装正文边界。正式入口 `node tools/teavm/check-cache-storage.ts` 提供 loopback 页面并等待内置浏览器，报告编译字节摘要并在通过后退出；不是自动 CI 浏览器门。单次恢复延时不是性能分布。Body metadata/pin/usage 本身损坏、持续清理失败及生产网络取消另验；共享 Java 受控 HTTP 取消见阶段四。Java Cache 场景的 no-cache/POST 对照见 [HTTP Cache 运行证据](../verification/http-cache-runtime.md)；正式 Source 仍须使用新 AOT 身份验收。

同日，固定 `31555e8` 的 iOS 26.4 Simulator WKWebView 与 Android API 36 / WebView 133 均以完全相同的桥、Worker 与 suite 字节通过 39 组，最终 Headless WebView dispose 成功。正常系统 TLS 验证、平台与 UA 差异、失败保留及复验命令见[Native Cache 机制证据](../verification/cache-v3-native.md)。这是移动引擎的 IndexedDB/Web Locks/Worker 门，不能替代 Native Source 或 Java CacheInterceptor。

## 阶段三：有界普通文件

**核心实现与分层机制门已通过，产品验收仍进行中**。官方候选源码核对后，直接使用现有 `idb@8.0.4` 提供 typed schema 与事务；项目保留 Java FS 语义、inode、owner 与配额适配。新 DB `teavm-java-files-v2` 不迁移原型旧格式。选型、接口与固定预算见[普通文件存储设计](../design/runtime-file-storage.md)。

- 正文移除整文件记录与 Base64；Java/JS 每块最多 64 KiB，按 inode/chunk 随机 IO。稀疏扩容只更新逻辑长度，缺块读零；truncate 清尾块，重扩不泄露旧内容。
- 单文件 64 MiB；普通 files namespace 逻辑长度/allocated chunks 各 128 MiB，metadata 2 MiB、4096 inode、64 handle、32 live owner；每 Worker pending 4，事务期限 5 秒。未链接 open inode 仍计费。与 Cache 独立静态分区合计最多 262 MiB 逻辑 reservation，不跨两个 DB 借贷；同一 namespace 的真实组合压力已通过[受控 ABI 门](../verification/runtime-storage-namespace.md)，不代表物理占用或 Source/Native 验收。
- data/路径/inode/usage 同事务，提交后才更新 cursor 与 ACK；rename/unlink 保留打开 inode，append 使用事务内最新 EOF。Web Locks 死亡 owner 以快照、事务外探测和 token CAS 清理；system close 失败保留 owner/句柄，可显式重试。
- 修正 TeaVM 内部 accessor EOF0、FIS unsigned/EOF、RAF 零长度/range 和 close ACK 语义；仅项目自有 JCL IR 适配，不改 vendor 或扩展 JAR。

2026-11-04，主代理内置 Chromium 156 通过 14 组真实 Worker/IDB/Web Locks 门，包含真实事务 abort、配额、pending、terminate、提交后 ACK 前死亡、system close abort→重试。原 JVM 共享 File/RandomAccessFile/Okio 场景 32 项、Accessor/JCL 窄 fixture 24 项及实际 TeaVM 二进制 JSO 共享场景 32 项分别通过；两端正文摘要一致。分层证据与复验命令见[普通文件运行证据](../verification/file-storage-runtime.md)。仍待正式 Source、Native、正式扩展/Flutter 的版本与身份切换和设备资源测量；真实 manager + IDB 切换及组合分区已另验，取消不承诺撤销已提交写入。

真实 xkcd 冷热观测曾全部为零，已核实锁定 seed 的 `NetworkHelper` 没有配置 Cache。现已内化最小 owned 适配，保留既有 ABI、Cookie、UA 与拦截器，显式启用稳定目录下的 5 MiB Cache；图片原有 cacheless 调用保持有效。原 seed 与 owned JVM 配置门及实际 TeaVM 浏览器 Worker 配置门已通过，详见[Source 网络配置证据](../verification/source-network-cache.md)。随后固定 `b4f72f7` 的新指纹 / 原 JAR AOT 已实际证明 xkcd 3318 元数据 cold commit 7187 B、warm 从 store 读完 7187 B 且上游零请求；Page 会话关闭及页列表摘要一致。图片保持原 cacheless，两轮各走真实网络。随后独立新 origin 的原 Source 通过 12 项 manager/Worker 重建门：旧 manager dispose 实际终止 Worker，新 manager/Worker 以相同四维 namespace 读完持久 store 的 7187 B、EOF 与 reader-close，上游零请求、PageList 摘要一致，最终两 Worker 均终止。这是同一浏览器文档内重建，未发生 304。另有[原 Source Native Cache 门](../verification/source-cache-native.md)：同一新 AOT 在 iOS / Android 模拟器通过正式 Native runtime 的 cold commit、warm 正文读取及容器重建后复用，三阶段 Page 会话关闭和最终 dispose 均确认。App / 浏览器进程重启、正式版本更新与其他 Source 仍须另验。固定 `be5c3ed` 的正式 Flutter Web 主入口随后通过原 xkcd A→B→A：独立 namespace 的 B 冷取，返回 A 恢复自身进度并在真实 304 后读完原 7187 B 正文，详见[产品重连记录](../verification/runtime-reconnect.md)；不将其记成零网络，也不推广到 Native 身份或生产会话。

正式 Flutter Web 的官方 Arknights 1.6.1 → 1.6.2 更新与第 3 页续读已按[版本证据](../verification/extension-version-web.md)通过：同 namespace 的新版可见旧 Cache 条目、旧新 Worker 均正常终止；但本轮全部上游 200、新版正文读取计数为 0，只证明重新获取并写入。版本更新后 Cache 正文复用、普通文件、Native 及进程重启仍须分别验收，不用产品页位恢复替代存储语义门。

## 阶段四：原 JVM 同版对照与产品门

原 JVM 与 TeaVM 共享基线已通过；受控 HTTP 截断与半途取消也已完成独立对照，更广异常、生产网络取消和产品场景仍待实施。seed 中同名 OkHttp JAR 的 `newCall` 已适配为 BrowserCall，不能用作原 JVM oracle；当前从官方 Maven 获取同版未适配的 5.5.0 JAR，验证 SHA-256 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52` 并断言实际 CodeSource。共享 `CacheScenarios.java` 已覆盖 131079 字节冷热、304 合并、no-store、Cookie Vary、evictAll 后继续读已打开 snapshot，并追加 no-cache 强制重验证、POST 上传与同 URL GET 失效/重新缓存；两端本轮均为 18 次请求、13 次网络、7 次命中、8 次成功写入（历史首轮为 11/8/4/5），正文 SHA-256 均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`。TeaVM 在 Codex 内置 Chromium 156 的真实 Worker 中运行产品 BrowserCall/Cache、二进制 JSO、typed idb 与 HTTP v2，由 workerd 映射隔离的受控 origin，未放宽生产网络策略。该门不代表正式 Source、生产 Access 或 Native。产物与原始报告留在忽略目录，见 [HTTP Cache 运行证据](../verification/http-cache-runtime.md)。

1. 已补充 `CacheFailureScenarios.java`：两端四场景、50 项检查通过，精确读 8192 B 后截断/取消，Cache.close 后同目录重开验证半成品不可见、旧条目保留及恢复；不是进程重启。真实本地 HTTP/1 中继 RST 与原点关闭单独确认，生产 HTTP/2、HTTP/3、Access/Native 仍待验，见[独立故障记录](../verification/cache-http-failures.md)。历史冷热、Vary/Cookie、304、no-cache/no-store 和 POST invalidation 对照保留。
2. 对照正文摘要、状态及关键响应头、网络请求次数、cache/network 标记和异常类型；不能只比较测试数量或编译结果。
3. 正式 manager namespace 的版本/重建保留和 identity、repo、package、storageSchema 四维隔离单元门已通过；buildId 不参与派生。新增[真实 manager/存储门](../verification/runtime-storage-namespace.md)通过 11 组：由产品加载器和 Worker/driver 驱动受控 TS ABI，实际 IDB 数据跨构建/manager 保留、四维隔离，以及同键两分区合计 256 MiB allocated 和不借贷。该组合门不运行 Java/官方 Source。另有原 xkcd 的实际 manager/Worker 重建及双端模拟器 Native 容器重建后复用通过上述独立门；正式扩展/Flutter 的版本更新、Native 身份切换、App / 浏览器进程重启、生产 Access 及其它 Source Native Cache 仍须验收；Web 原 Source 身份分项按上述产品记录单独通过。
4. 原版 Source、HTTPS handshake 适配、生产 Access 和 Web/Native 实际环境分别验收。受控 HTTP 或存储机制门不能替代这些结果。

原 Arknights cacheless 图片的正式 Web 获取中退出与恢复随后通过[限定 Source 门](../verification/source-cancellation-web.md)：暂停的真实未完成 HTTPS 响应在 UI 取消后及时关闭，Java/章节终态、恢复显示及最终 Worker/遥测/服务清理均确认。该门不是 Cache editor 取消、生产 Access、Native、全部阶段或更多 Source 的验证；前两轮上游等到 Source 期限的失败保留。

完成以上阶段也不等于已控制整个 Worker 或进程/GPU 峰值；存储、网络、图形和终端图片预算的组合与实际测量仍需 P0 汇合验收。
