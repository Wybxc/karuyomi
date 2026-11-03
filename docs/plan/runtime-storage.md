# 运行时文件与 HTTP Cache

## 目标与状态

为未修改的 Source 提供持久文件与原 OkHttp 缓存语义，在 Worker 取消、异常终止、重建和扩展版本切换后保持完整条目、句柄所有权与有界资源。状态：**进行中**。当前只实施 Cache editor 的 Worker lifetime 所有权回收；去正文 Base64、分块存储、总预算和原 JVM 同版对照尚未完成。

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

待实施。当前 Java Cache 使用整段 Okio Buffer/Base64，JS 每次操作扫描目录全部正文，容量检查发生在完整解码之后；缓存 `maxSize` 不是传输或峰值内存约束。

- 小控制仅交换 metadata、editor/reader handle；正文经不超过 64 KiB 的二进制块，写入有背压。
- IDB 分离 metadata 与正文 chunks，以 entry version/generation 原子提交完整 body 指针。读者保留稳定 snapshot；中止和死亡 owner 回收未提交块。
- size/LRU 查询不读取正文；预先落实单条、目录和临时写入预算。缓存预算不足时放弃缓存写入，继续交付正常网络正文。
- 取消门验证完整旧条目或完整新条目，不允许半条正文；已完成提交不承诺因后续取消而回滚。

## 阶段三：有界普通文件

待实施。当前文件 accessor 的 Base64 块长随调用方决定；IDB node 保存整文件，每次 write/resize 复制完整数组，允许近 2 GiB 的逻辑长度，没有正式单文件/namespace 总预算。

- Java accessor 与 JS 使用有界二进制块，随机访问按 inode/chunk 读写；resize 和稀疏区间不通过分配整段数组实现。
- 先确定单文件、namespace、未链接但被打开文件和待提交操作的配额，保留打开时 rename/unlink 与独立 cursor 语义。
- 真实 terminate/reopen 检查 Web Locks owner 清理、孤立 inode 回收和最后完整事务边界。取消不承诺撤销已持久化写入。

## 阶段四：原 JVM 同版对照与产品门

原 JVM 基线已建立，TeaVM 同场景对照仍待实施。seed 中同名 OkHttp JAR 的 `newCall` 已适配为 BrowserCall，不能用作原 JVM oracle；当前从官方 Maven 获取同版未适配的 5.5.0 JAR，验证 SHA-256 `234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52` 并断言实际 CodeSource。共享 `CacheScenarios.java` 已在原 JVM 通过 131079 字节冷热、304 合并、no-store、Cookie Vary、evictAll 后继续读已打开 snapshot；结果为 11 次请求、8 次网络、4 次命中、5 次成功写入，尚不是 TeaVM Cache 通过。产物留在忽略目录。继续使用工具链锁定的原始 OkHttp JAR，与 TeaVM 的产品 BrowserCall/Cache 运行同一 Java 场景和受控 origin；测试入口沿用既有 workerd 受控 origin 映射，不能放宽生产网络政策。

1. 比较冷/热命中、Vary/Cookie、ETag 304 合并、no-cache/no-store、POST invalidation、截断正文、半途取消和重启。
2. 对照正文摘要、状态及关键响应头、网络请求次数、cache/network 标记和异常类型；不能只比较测试数量或编译结果。
3. 验证正式 namespace 派生：identity、repo、package、storageSchema 相同的版本保留数据；新 schema、其他身份或包隔离。buildId 不参与当前存储 namespace。
4. 原版 Source、HTTPS handshake 适配、生产 Access 和 Web/Native 实际环境分别验收。受控 HTTP 或存储机制门不能替代这些结果。

完成以上阶段也不等于已控制整个 Worker 或进程/GPU 峰值；存储、网络、图形和终端图片预算的组合与实际测量仍需 P0 汇合验收。
