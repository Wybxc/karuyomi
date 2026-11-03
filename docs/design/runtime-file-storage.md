# 普通文件存储

Source 保留原有 Java `File`、`RandomAccessFile` 和 Okio 调用，由项目的 TeaVM `VirtualFileSystem` 适配浏览器持久文件。正文使用二进制块，小 JSON 只表达操作与 metadata；不以通用 Node 文件系统 API 为目标。实施与证据分别见[存储计划](../plan/runtime-storage.md)和[文件运行证据](../verification/file-storage-runtime.md)。

## 第三方方案选择

2026-11-04 核对官方发布源码后，继续直接使用已有精确依赖 `idb@8.0.4` 提供 typed IndexedDB 与事务；项目仅保留 Java 文件语义、所有权和配额策略。候选没有安装运行，以下是源码审查结论。

| 固定候选                      | 与当前需求的差距                                                                                                                                                                                                                                                                                                                                                     |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ZenFS core 2.8.3 / DOM 1.2.14 | [IndexedDB backend](https://github.com/zen-fs/dom/blob/cfa7d8b4ef556056a8f4545311f2b199e39c9434/src/IndexedDB.ts) 使用整记录与缓存；[StoreFS resize/write](https://github.com/zen-fs/core/blob/ecb25b1bfd81879ef79052156c0171f215117b59/src/backends/store/fs.ts) 仍分配完整文件或 EOF 到目标 offset 的连续空洞，不能直接提供有界稀疏写。                            |
| LightningFS 4.10.5            | [公开实现](https://github.com/isomorphic-git/lightning-fs/blob/69224913b0470fd3685f93b30c2b2b3b933ab775/src/DefaultBackend.js) 缺少 fd 随机访问，目录 superblock 延后保存，[正文与目录分别写入](https://github.com/isomorphic-git/lightning-fs/blob/69224913b0470fd3685f93b30c2b2b3b933ab775/src/IdbBackend.js)。当前版本已有 Web Locks，不能用旧 mutex 描述排除它。 |
| Filer 1.4.1                   | [write/truncate](https://github.com/filerjs/filer/blob/e135305f25d8796b3dd7aff3bebc64204c0ab487/src/filesystem/implementation.js) 分配完整目标文件；[IndexedDB provider](https://github.com/filerjs/filer/blob/e135305f25d8796b3dd7aff3bebc64204c0ab487/src/providers/indexeddb.js) 的成功回调早于整个事务完成。                                                     |

ZenFS 的 API 最接近，但仍需改造正文分块、稀疏写、跨 Worker 缓存和打开 inode 的生命周期，改造范围超过本项目需要的 Java 子集。当前 StoreFS 已把 data 与 inode 更新放在同一事务，不沿用旧原子性缺陷作为否决理由。其 [VNode 按 path 补读](https://github.com/zen-fs/core/blob/ecb25b1bfd81879ef79052156c0171f215117b59/src/vfs/vnode.ts) 与 unlink 删除底层记录还提示冷 open→unlink→read 的风险；这只是源码推断，没有候选库实测证据。

## 数据与接口

新数据库 `teavm-java-files-v2` 不迁移原型旧格式。`paths` 映射路径到 inode，`inodes` 保存属性与逻辑长度，`chunks` 以 namespace/inode/index 保存固定 64 KiB 块；`handles`、`owners` 和 `usage` 保存持有关系及 namespace 账本。metadata 操作不读取正文 chunks。

- `teaFile(json)`：有界小 JSON，支持路径、属性、open、seek、resize、flush 和 close。
- `teaFileRead(handle, maximum)`：返回 `Uint8Array` 或 EOF `null`，最多 64 KiB。
- `teaFileWrite(handle, bytes)`：接收非空 `Uint8Array`，最多 64 KiB，事务提交后返回 `true`。
- `teaFileSystemClose()`：停止接受新操作，等待已接受队列，提交当前 owner 清理后释放 Web Lock。失败保留 owner 与句柄，可显式重试。

Java 大 write 按 64 KiB 逐块发送，不复制整个调用数组；Accessor EOF 使用 TeaVM 内部约定的 `0`，JCL 对外转换为 `-1`。项目自有 IR 适配修正 `FileInputStream.read()` 的 unsigned/EOF、`RandomAccessFile` 的零长度/range 检查和成功 ACK 后关闭；不修改 vendor 或扩展 JAR。

## 语义与事务

稀疏扩容只改 inode 长度，缺块读零；缩短文件删除尾块并清最后块尾，重新扩容不会读到旧数据。每个打开 accessor 有独立 cursor，append 在事务中读取最新 EOF。rename 替换和 unlink 只移除路径引用，已打开的 inode 保留到最后句柄关闭或死亡 owner 回收。

data、inode、路径与 usage 使用同一事务。仅在 [idb `tx.done`](https://github.com/jakearchibald/idb#transaction-lifetime) 成功后更新 cursor 或返回 ACK；事务失败回滚正文、长度和账本。取消不能撤销已经提交的写入。

每个 Worker 持有唯一 Web Lock。回收先读 owner 快照，在 IDB 事务外用 `ifAvailable` 探测，再在独立事务中以 owner token 做 CAS 清理；不在事务中等待 Web Locks。Worker [终止释放锁](https://w3c.github.io/web-locks/#termination)，只证明 owner 已死亡，不能代替事务完整性。system close 失败不会冒称已释放，也不删除兄弟或外来 owner 的句柄。

## 配额

| 范围                                     | 上限           |
| ---------------------------------------- | -------------- |
| 二进制块 / 小 JSON 控制                  | 各 64 KiB      |
| 单文件逻辑长度                           | 64 MiB         |
| 每 namespace 逻辑正文 / allocated chunks | 各 128 MiB     |
| 每 namespace metadata                    | 2 MiB          |
| 每 namespace inode / handle / live owner | 4096 / 64 / 32 |
| 每 Worker 已接受未完成操作               | 4              |
| 路径 UTF-8 / 单次事务期限                | 4096 B / 5 秒  |

未链接但被打开的文件仍计入全部预算。metadata 采用记录序列化字节与键的逻辑账本；allocated 是存储块逻辑容量，不是浏览器物理磁盘测量。普通文件与独立 Cache 数据库的合计配额、全进程峰值和设备性能仍需后续汇合验收。
