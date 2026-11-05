# Manager namespace 与组合存储验证

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，Codex 内置 Chromium 156 通过 **11 组**真实 manager/Worker/IndexedDB/Web Locks 检查，正式 runner 退出 0。这补充了[Cache 39 组](http-cache-runtime.md)与[普通文件 14 组](file-storage-runtime.md)各自的机制门：同一产品派生键下，两套数据库实际达到合计 **256 MiB allocated**，同时验证构建更新后的数据保留与 identity/repo/package/storageSchema 隔离。

本门使用明确标注的 **受控 TypeScript host ABI fixture**。执行的是产品 `SourceRuntimeManager`、`VerifiedLoader`、`src/worker.ts`、`WorkerRuntime`、`TeaVMDriver` 和 canonical Cache/file 桥；没有运行 TeaVM 生成的 Java bundle、原 CacheInterceptor 或官方 Source。测试 identity 是本轮夹具输入，静态资源由 loopback 服务提供；不能据此宣称真实 Access、Native、正式 Source 更新、浏览器/应用进程重启、物理磁盘或进程内存通过。

## 实际接线与切换

`tools/teavm/check-runtime-storage.ts` 用正式 `compileBridge` 编译两桥，esbuild 编译产品 Worker、浏览器 suite 和两份受控 ABI bundle。两个 bundle 字节、buildId、version 和规范 manifest 路径均不同，正常经过产品加载器的 gzip 传输、摘要和当前协议校验。受控 ABI 使用标准生成的 SourceCall/search 和结果边界驱动存储动作；二进制正文始终在真实 Worker 内通过现有最多 64 KiB 的 Cache/files 通道读写，报告只返回小型状态。

namespace 直接取产品 manager 实际创建的 Worker URL。测试没有复制 SHA 派生算法，也没有伪造 usage：manager 从测试 identity、manifest repoId、packageName、storageSchema 生成同一个 64hex 值，分别交给 plugin/fsNamespace。它覆盖以下六组：

- A 构建写入 Cache 和普通文件的 131079 B 确定性正文，再保留一个 staging editor 与未链接的 open inode。打开新路径的 B 构建，真实旧 Worker 被终止，新 Worker 读回完整原字节，并回收旧 staging 和未链接 inode。
- dispose 后创建新的 manager，再次打开 B，两个数据库仍有完整原数据。
- identity、repo、package、storageSchema 分别变化时，两套存储均 miss；各自写入不同 sentinel、清理后返回原元组，原数据仍完整。四个维度分别计一组。

同路径、同 open options 的调用会复用既有 session，不能当成版本更新。storageSchema 切换验证的是当前元组隔离，没有数据库升级迁移或旧格式兼容层。这里的“重建”限于 Worker/manager，未重启浏览器进程。

## 同 namespace 的实际组合压力

剩余五组验证满额、结构预算、拒绝的原子性、两分区不借贷和全量读回/清理。

| 观察值                    |       Cache |  普通 files |
| ------------------------- | ----------: | ----------: |
| allocated                 | 134217728 B | 134217728 B |
| 实际 IDB chunk 数         |        2048 |        2048 |
| 结构 metadata reservation |    391578 B |    296749 B |
| 分块读回校验的正文        | 134217686 B | 134217728 B |

Cache 的两个 body 与三个活 editor metadata 正好占满 128 MiB；其中 42 B 是已计入 allocated 的响应 metadata。files 真正写入两份 64 MiB 正文，每块 64 KiB；没有用 sparse resize 代替已分配 chunks。两库 allocated 加结构 reservation 实测共 **269123783 B**，在既定 262 MiB 逻辑 reservation 政策内。这些数值不是物理磁盘或 JS/进程峰值。

两个分区都满时，各自溢出写入被拒绝，files cursor/数据/账本保持不变；Cache 失败 writer 释放自己的 reservation，editor 槽可重用。释放 files 一个块后，Cache 仍不能扩大自己的配额；反向释放 Cache body 后，files 仍不能借用其额度。随后只用各自释放的容量继续写入，并逐块校验全部正文。

产品主动 close/abort/clear/delete 后，两库 allocated 和 chunk 记录均为 0；Cache 无 owner/editor/reader/body。此刻 files 的当前活 Worker 仍保留一个 owner 和两个根目录 inode，符合其生命周期。随后真实 manager.dispose 完成 Worker 停止；suite 的独立维护清理仅删除本轮随机元组产生的 namespace 键，最终 cleanupPassed=true。维护删除不计入上述产品退款断言，不删除其他 namespace，也不读取全部 chunk 正文来清理。

## 正式入口与身份

安装锁定 Node/pnpm 依赖即可运行，无需 JVM seed、AOT、API 密钥或网络 Source：

```sh
node tools/teavm/check-runtime-storage.ts --port 0 --timeout-ms 300000
# 用 Codex 内置浏览器打开 stdout URL，页面自动运行。
pnpm typecheck:tools
pnpm exec tsc -p packages/runtime-host/test/tsconfig.bridge-browser.json
pnpm check:dependencies
```

维护代码为上述 runner、`packages/runtime-host/test/storage-namespace-browser-suite.ts` 与 `fixtures/storage-namespace-host.ts`；两浏览器输入已纳入严格检查。静态服务直接使用锁定的 sirv，有限 gzip 夹具走标准 Node 原样字节响应；无新增通用工具包装、配额层或生产预算变更。39/14 组保持独立入口，本门没有把它们重新计入 11 组。

成功原报保留在忽略的 `.local/runtime-storage/browser-manager-combined-passed.json`。实际服务字节摘要：

| 输入                        | SHA-256                                                            |
| --------------------------- | ------------------------------------------------------------------ |
| 产品 Cache 桥               | `7fc988f9937eaaf232c42a52e61e9a45112377e4d09be857386b356e77c36518` |
| 产品 file 桥                | `15bf15014a1869b2209fbfc53bc7288fbc7766cd85ff0fd89458e0a882fc1358` |
| 产品 src/worker.ts 编译字节 | `3c7a02826ed7f5dbc59a69a473123a9920ba2847762392e1b94aae0492f7bca8` |
| 浏览器 suite                | `1ad1a8579fe5c185fcd4f10cbe94ff0f65240104f1c36981f9253261e31d82d9` |
| 受控 ABI A                  | `08e3356f5a77a435ed562cd6cb1e1bfbc3ffabe6587fe628efcf3d0f6ea6f6cd` |
| 受控 ABI B                  | `d90dc6a8e5b1eb335e86ceccc2349d5edf81a250c53c250fbcf4bda646fd8be7` |
| 正式 runner                 | `c5be8c3a119cd000075509b8e98741a38ba154578b3b50662ca81dc8c6893974` |

## 失败记录与剩余门

首轮 sirv 把显式 `.gz` 夹具当成 HTTP Content-Encoding gzip，产品加载器正确拒绝；修正的是测试响应头，没有放宽产品校验。第二轮测试维护清理误用 key-only cursor.delete，错误掩盖了主结果；已改为 table.delete(primaryKey)，UUID-keyed editor/reader 只读取小记录的 namespace 字段，并保留聚合原始错误。两次实际失败分别留在 `browser-fixture-mime-failed.json` 和 `browser-keycursor-cleanup-failed.json`，不当作成功或产品缺陷。

每轮在编译前写新失败初态，当前 `browser-report.json` 总是代表最近一次运行。最终字节的实际 `--timeout-ms 1000` 和 URL ready 后 SIGTERM 均退出 1，留下 deadline/interrupted 失败与本轮 identity；独立 TCP 确认端口 ECONNREFUSED。它们没有打开浏览器，cleanupConfirmed=false，不能称已经收到 IDB 清理 ACK。报告分别为 `browser-timeout-failed.json`、`browser-sigterm-failed.json`；不会覆盖单独保存的成功原报。成功还要求浏览器 cleanupPassed 与 11 组完整通过；server 终态清理若失败也会写 passed=false。

仍须验收正式扩展/Flutter 的版本与身份切换、更广 Source Cache / 取消、生产 Access、Native Java / Source、所有 origin namespaces 合计占用及设备资源峰值。262 MiB 是同一 namespace 的既定逻辑 reservation 分区政策，不是浏览器物理存储上限。

原 xkcd 的新 AOT Web 元数据 fresh Cache 已通过[独立正式 Source 证据](source-network-cache.md)，不计入本受控 ABI 的 11 组；图片保留原 cacheless 语义。
