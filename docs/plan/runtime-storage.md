# 运行时文件与 HTTP Cache

## 目标与状态

为未修改的 Source 提供持久文件与原 OkHttp 缓存语义，在 Worker 取消、异常终止、重建和扩展版本切换后保持完整条目、句柄所有权与有界资源。状态：**进行中**。Cache editor 的 Worker lifetime 已通过机制门；正文已接入 typed idb 分块与二进制 JSO，已通过真实浏览器机制门和原 JVM/TeaVM 的共享 CacheInterceptor 场景；正式 Source、普通文件及 namespace 总预算尚未完成。

已有浏览器桥机制门覆盖正常持久化、namespace 隔离、Cache editor 竞争/CAS 和文件 rename/unlink；图片 JVM oracle 明确使用 cacheless 链，不是 HTTP Cache 语义验收。证据参见 [Worker 桥](../verification/worker-bridges.md)，P0 总目标参见 [运行时计划](p0-runtime-and-reading.md)。

## 阶段一：Cache editor 生命周期

**已实现并通过机制门**：2026-11-03，Codex 内置浏览器 Chromium 156 使用正式产物通过十组生命周期与失败终态回归；真实 Worker 终止后新 Worker 的首次 begin 成功，未等待旧五分钟过期时间。该结果不代表原 Java CacheInterceptor 或 Source 语义验收。

已完成：

- 每个 Cache Worker 持有一个 Web Lock；终止 Worker 自动释放，不再使用五分钟时钟判断 owner 是否失效。
- Cache 操作先取得目录 owner 快照，在 IDB 事务外用 Web Locks 探测死亡 owner，再以独立原子事务清理其 editor。不会等待锁时持有 IDB 事务。
- editor token、Java handle、entry version 和 clear generation 继续约束提交；外来 Worker 不能提交或 abort 活 owner 的 editor。Java `Cache.close()` 只清理对应 handle，不影响同 Worker 的其他 Cache 实例。
- `put` 的真实 IDB request failure 等到事务 abort/回滚结束后，再以独立小事务按 editor、Worker/Java handle 和 generation 清理；原始失败仍向调用方报告。清理不会删除期间替换的 editor、owner 或 generation。
- begin 在第一个异步等待前登记 pending attempt，close/delete 同步失效同 handle 的在途 attempt；主事务复查，避免关闭后迟到 begin 重建锁。Java delete 先标记 closed，再发送明确的 delete 操作；evictAll 仍为 clear，不关闭 handle。完成后即删除跟踪记录，不保留无限增长的 closed handle 历史表。
- 独立正式浏览器入口为 `packages/runtime-host/test/cache-lifecycle-browser-suite.ts` 和 `cache-lifecycle-worker.ts`；由正式 `compileBridge('cache')` 产物驱动，使用真实 Worker、IndexedDB 和 Web Locks。

验收：A 写入完整条目后 begin 新 editor，活 A 期间 B 竞争失败；terminate A 后 B 立即 begin 成功，旧完整字节/版本保留，旧 editor 无法提交；活 Worker 锁不被误清理；并发唯一 editor、Java handle close、CAS 和 clear generation 均保持有效。附加门以真实 IndexedDB `ConstraintError` 触发产品事务 abort，验证旧完整条目不变、活 Worker 的下一次 begin 成功，及清理期间替代 editor/真实活 owner/新 generation 不被误删；另以受控 Web Locks 探测延迟验证 close/delete 先完成时在途 begin 被拒绝，clear 后原活 handle 仍可 begin。故障与延迟只由测试 driver 注入，存储和锁仍使用浏览器标准实现。严格类型检查使用 `pnpm typecheck:bridges`。临时服务和原始报告留在忽略目录，不作为维护源码。

## 阶段二：有界 Cache 正文

**核心正文通道与受控 Java 场景已通过，产品验收仍进行中**。移除产品 Cache 的正文 Base64 与整段 Java Buffer；使用精确依赖 `idb@8.0.4` 的 typed schema 与 `tx.done`，不另建通用存储包装。新数据库为 `teavm-http-cache-v2`，原型不维护旧格式迁移。

已接线：

- 小 JSON 控制不超过 64 KiB，metadata 不超过 48 KiB。`get` 仅返回 metadata/version/generation/reader/length，`begin` 接收 metadata，`commit` 原子发布完整 body 指针。
- `teaCacheRead(reader, javaHandle, maximum)` 和 `teaCacheWrite(editor, javaHandle, sequence, bytes)` 传递不超过 64 KiB 的二进制块；Java 同样逐块复制，写 ACK 在实际事务提交之后。editor 与 reader 均校验 Worker/Java handle 所有权。
- IDB 拆分 entries、bodies、chunks、editors、readers、directories；size、URLs、304 update 和 LRU 只读 metadata。读者 pin 不可变 body，replace/remove/clear/delete 仅移除当前引用，旧 snapshot 在最后 reader EOF/close 或死亡 owner 回收后释放。
- Cache 可见大小上限为 `min(maxSize, 64 MiB)`，逻辑 allocated 同时计入 current、staging、retired-but-pinned 正文和 metadata，上限为可见预算两倍。每目录最多 64 个 editor 和 64 个 reader，每 body 最多 8192 块；事务 5 秒超时后 abort 并等到终态，再独立 CAS 清理。allocated 是应用逻辑字节预算，不是浏览器实际磁盘占用测量；普通文件与跨目录 namespace 总预算仍属后续阶段。
- commit 与 metadata update 若无法在保留活 editor 的前提下达到可见预算，会原子回滚并拒绝发布；commit 再独立清理原 editor。close/delete 的原事务失败后，独立事务仅清对应 Worker/Java handle 的 staging editor，保留旧 current、打开 reader、sibling 和其他 owner；原始失败仍报告，清理失败聚合两个错误。
- Java `CacheSink` 将存储 IOException 或容量拒绝转为一次缓存 abort，精确消费本次 write 的剩余 count，后续仅丢弃缓存副本，网络正文继续；程序参数错误不宽泛吞掉。原网络读取异常仍传播，已发布 cache-hit 的读取故障不擅自重新请求网络。
- `pnpm teavm:check` 已接入 CacheSink 正式 JVM 边界门：19 项检查覆盖 65536/65536/7 分块、额外未请求字节保留、写入/提交拒绝、存储异常和关闭期间的计数及终态。正式 Cache/Bridge 六源 javac、严格 TS 和 bridge unit 6/6 均通过；这些结果不代替实际 TeaVM JSO、CacheInterceptor 或 Source 验收。

2026-11-04，Codex 内置浏览器 Chromium 156 使用正式 compileBridge 产物通过十七组：保留阶段一十组，追加多块 snapshot 替换/clear/EOF 与 allocated 释放、metadata 操作不读 chunks、块/目录预算、Java handle 隔离、可见预算 commit/update 原子拒绝，以及 close/delete 真实 IDB 失败后的同 handle 清理。原始报告在忽略目录；单次恢复延时不构成性能分布。待验收：reader 死亡回收、正文损坏和取消中途故障门。同一 Java Cache 场景的 TeaVM/原 JVM 对照已通过，证据与复验入口见 [HTTP Cache 运行证据](../verification/http-cache-runtime.md)；仍须以新 AOT 身份验收正式 Source。取消只允许完整旧或完整新条目，不允许半条正文；已完成提交不承诺因后续取消而回滚。

## 阶段三：有界普通文件

待实施。当前文件 accessor 的 Base64 块长随调用方决定；IDB node 保存整文件，每次 write/resize 复制完整数组，允许近 2 GiB 的逻辑长度，没有正式单文件/namespace 总预算。

- Java accessor 与 JS 使用有界二进制块，随机访问按 inode/chunk 读写；resize 和稀疏区间不通过分配整段数组实现。
- 先确定单文件、namespace、未链接但被打开文件和待提交操作的配额，保留打开时 rename/unlink 与独立 cursor 语义。
- 真实 terminate/reopen 检查 Web Locks owner 清理、孤立 inode 回收和最后完整事务边界。取消不承诺撤销已持久化写入。

## 阶段四：原 JVM 同版对照与产品门

原 JVM 与 TeaVM 共享场景已通过；更广的异常、取消和产品场景仍待实施。seed 中同名 OkHttp JAR 的 `newCall` 已适配为 BrowserCall，不能用作原 JVM oracle；当前从官方 Maven 获取同版未适配的 5.5.0 JAR，验证 SHA-256 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52` 并断言实际 CodeSource。共享 `CacheScenarios.java` 已在原 JVM 通过 131079 字节冷热、304 合并、no-store、Cookie Vary、evictAll 后继续读已打开 snapshot；两端结果均为 11 次请求、8 次网络、4 次命中、5 次成功写入，正文 SHA-256 均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`。TeaVM 在 Codex 内置 Chromium 156 的真实 Worker 中运行产品 BrowserCall/Cache、二进制 JSO、typed idb 与 HTTP v2，由 workerd 映射隔离的受控 origin，未放宽生产网络策略。该门不代表正式 Source、生产 Access 或 Native。产物与原始报告留在忽略目录，见 [HTTP Cache 运行证据](../verification/http-cache-runtime.md)。

1. 比较冷/热命中、Vary/Cookie、ETag 304 合并、no-cache/no-store、POST invalidation、截断正文、半途取消和重启。
2. 对照正文摘要、状态及关键响应头、网络请求次数、cache/network 标记和异常类型；不能只比较测试数量或编译结果。
3. 验证正式 namespace 派生：identity、repo、package、storageSchema 相同的版本保留数据；新 schema、其他身份或包隔离。buildId 不参与当前存储 namespace。
4. 原版 Source、HTTPS handshake 适配、生产 Access 和 Web/Native 实际环境分别验收。受控 HTTP 或存储机制门不能替代这些结果。

完成以上阶段也不等于已控制整个 Worker 或进程/GPU 峰值；存储、网络、图形和终端图片预算的组合与实际测量仍需 P0 汇合验收。
