# HTTP Cache namespace 存储预算

2026-11-04。HTTP 缓存策略继续由原 OkHttp CacheInterceptor 决定；这里约束浏览器持久副本和引用生命周期。实现直接使用锁定的 `idb@8.0.4`，不另建通用配额或事务包装库。运行证据见[HTTP Cache](../verification/http-cache-runtime.md)，普通文件的独立分区见[文件存储设计](runtime-file-storage.md)。

## 固定分区

同一产品 namespace 使用两个独立数据库，不能跨数据库原子借贷。Cache DB 为 `teavm-http-cache-v3`，原型不迁移旧数据。

| 逻辑 reservation         | Cache 全部目录合计                   | 普通 files         |
| ------------------------ | ------------------------------------ | ------------------ |
| 正文 allocated           | 128 MiB                              | 128 MiB            |
| 结构 metadata            | 4 MiB                                | 2 MiB              |
| 目录或 inode             | 32 个目录，包括 generation tombstone | 4096 inode         |
| current entries / bodies | 4096 / 4224                          | —                  |
| reader / editor          | 64 / 64                              | 64 个 open handle  |
| 有持久引用的 owner 记录  | 32                                   | 32                 |
| chunk 记录               | 16384，单 body 最多 8192             | 由独立文件预算约束 |

正文和结构的静态分区合计最多 **262 MiB**。这不是实际磁盘占用或 JavaScript、浏览器进程、解码图片内存测量，也不是所有用户、扩展与 namespace 的 origin 总配额。files 的逻辑长度和实际 chunk 分配另各受其 128 MiB 上限约束；稀疏长度不等于已分配正文。

Cache 每目录可见预算仍为 `min(maxSize, 64 MiB)`；该目录 current、staging、retired pin 的 allocated 不超过其可见预算两倍。全 namespace 128 MiB 上限同时生效，不能通过建立多个 Cache 目录扩大正文预算。

## 计费与事务

Cache allocated 计入全部 body 字节及 current entry、staging editor 的响应 metadata JSON。替换、清空或淘汰 current 引用不会提前释放仍被 reader 固定的 body。结构 reservation 独立计入：

- directories、entries、bodies、editors、readers、owners、usage 的固定字段 allowance，以及实际 UTF-8 动态字符串、主键和各索引键。数值字段使用固定 allowance，避免读 cursor 增长一位就需要额外分配 metadata。
- 普通 metadata 记录采用 192 B 固定 allowance，加对应字符串和键的 JSON UTF-8 长度。响应 metadata payload 已在 allocated 计费，不重复作为结构 payload 加总。
- chunk 只有二进制 value 与 out-of-line 主键，没有 value-side key 或二级索引，采用 64 B 加实际主键的 JSON UTF-8 长度。典型短目录、64 位 namespace 的 16384 次 8 KiB 写入可同时达到 128 MiB 正文；长键会更早受结构上限约束。
- directory 最多 4096 UTF-8 B，URL 最多 16384 B，外部 handle/editor/reader/expected 最多 256 B，namespace 最多 256 B。JSON 控制仍不超过 64 KiB，单响应 metadata 不超过 48 KiB。

`usage` 与业务记录同一个 IDB readwrite scope，按业务增删维护 allocated、metadata、各种记录数和全域 LRU sequence；事务终态检查非负安全整数及所有上限。目录账本和 usage 在实际 `tx.done` 后才向 Java ACK。事务失败自然回滚记录和账本，失败后的独立 CAS 清理也使用同一分录逻辑。[idb 的事务生命周期](https://github.com/jakearchibald/idb#transaction-lifetime)和 [IndexedDB 的重叠 scope 调度](https://w3c.github.io/IndexedDB/#transaction-scheduling)提供这项原子性；它不能跨两个数据库成立。

Body 记录累积已计 chunk 的记录数与结构 reservation，回收时删除对应主键范围并按已计值退款，不扫描或重读整个正文。这样，测试中的 missing/empty/truncated chunk 也不会凭损坏后的值少退或多退账。Body metadata、pin 或 usage 本身损坏不属于本轮恢复保证。

## 目录、回收与拒绝

未知目录的 size/get miss/clear 不建目录。initialize 或成功 begin 才分配目录；clear/delete 保留已有目录的 generation tombstone，最多 32 个，不通过删除空目录并重置 generation 破坏迟到提交约束。

先按目录可见/allocated 预算淘汰，再按 namespace 全域 LRU 淘汰其他目录的 current entry；活 editor 对应 entry 保留。Pinned body 转为 retired 后仍计费，最后一个 reader EOF、显式关闭或死亡 owner 回收才退款。结构或记录预算也可以触发 LRU；不能满足时拒绝缓存副本。

容量拒绝在 get 表现为 miss，begin 为 accepted false，write 为 false 并清理自己的 editor，commit/update 为 committed false。Java CacheSink 已将存储 IOException 或容量拒绝隔离为缓存 abort，网络正文继续；已交付的 cache-hit 读取损坏仍报错，不擅自重新联网。initialize/flush/size 等显式强操作仍可能报告存储错误，不能统称所有 Cache 故障都被隐藏。

有 reader/editor 引用的 Worker 登记到最多 32 行 owner registry。控制操作取得 namespace owner 快照，在事务外用 Web Locks `ifAvailable` 探测死亡 owner，再同一事务清理其跨目录引用。访问 B 可以回收死亡 A 目录的 staging/pin，不必再次访问 A。活 owner 的 Web Lock 不会被抢占；锁在 [Worker 终止时释放](https://w3c.github.io/web-locks/#termination)。闲置 Worker 不占 owner registry 名额，这不是浏览器 Worker 进程数量上限。

普通 get/begin/read/write 每 Worker 同时最多 4 个；close/reader-close/abort 不占该窗口，也不先等待 namespace 回收探测，保证 Java 一次关闭仍能清理引用。这里没有宣称终态 Promise 总数或进程内存总上界。每块 read 使用 reader/body/chunk/usage 的直接 lookup，不扫描全部记录；仅元数据维护、压力淘汰和有界 owner 回收使用索引。

## 身份与验收边界

产品 manager 从已确认 identity、repoId、packageName、storageSchema 的同一元组派生 SHA-256 namespace，并把同一值同时传给 Cache 的 plugin 与 files 的 fsNamespace。build/version 更新不改变同一元组；身份、repo、包或 schema 改变则隔离。正式 manager 的保留/四维隔离单元回归已通过，不能据此声称真实 IDB 持久数据已跨扩展版本验收。

真实机制测试使用与产品相同长度的 64 位 namespace、产品编译桥、真实 Worker/IDB/Web Locks。Cache 与 files 分区各自机制门已经存在；两者同一 origin/namespace 的组合 128+128 MiB 压力、正式 Source Cache 冷热对照、Native Cache 和设备资源测量仍待验收。
