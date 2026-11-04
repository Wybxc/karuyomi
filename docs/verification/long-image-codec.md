# 长图 libspng / WASM 机制验证

## 结论与边界

2026-11-04，固定 libspng 的顺序行解码已通过 Node Worker 的两张大尺寸合成 PNG、ACK 边界取消及缺失 IEND 尾部四项机制测试。完整 RGBA 输出分别为 86,400,000 B 与 172,800,000 B，实际 WASM 线性 heap 均为 16 MiB；没有在 WASM 中建立完整 raster。该证据推进[长图计划](../plan/reader-image-decoding.md)的 codec 可交付性门，尚未接入 Source、Flutter 或 Native 产品，也不证明进程/GPU 峰值。

同一 WASM 与素材已在 Codex 内置 Chromium 156 的真实 Web Worker 通过五项测试，并亲眼核对首/中/末区域。正式长图合同、任意区域读取、缩放/LOD、PNG tile 编码、资源池和真实设备仍未完成，不改变现有 16 Mi 像素准入。

## 固定输入与构建

实验保留在忽略的 `.local/long-image-codec/`，不将临时工程、下载或产物提交源码。第三方上游保持原样；正式采用时应以 submodule 固定库源码，并锁定构建器与工具链。

| 项目            | 本轮输入                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| libspng         | v0.7.3，`bab9f94a1186f8fda234b4e1cb65e1b9a77049cc`                                                   |
| Emscripten      | 5.0.7，`263db4cffa6f9fc2ec514a70abac81362ea41849`                                                    |
| 本机编译工具    | LLVM 23.1.4、Binaryen 133；后者与 Emscripten 预期 128 不同，本轮不是官方 SDK 的可复现构建验收        |
| zlib port       | 官方 v1.3.1 archive，1,572,744 B，按固定 Emscripten port 的完整 SHA-512 校验；HTTP/1.1，TLS 校验开启 |
| Node            | v24.15.0，`worker_threads`                                                                           |
| WASM            | 67,183 B，SHA-256 `2d4f6e9c543bdce9eed1ee994ac491f9a16a684b7d3ad9961c427dbccffa0538`                 |
| 独立像素 oracle | Sharp 0.35.5 / libvips 8.18.7 / libpng 1.6.58                                                        |

使用 libspng 的 [progressive row API](https://github.com/randy408/libspng/blob/bab9f94a1186f8fda234b4e1cb65e1b9a77049cc/docs/decode.md)，逐行写入至多 256 行条带。每次只转移一个至多 64 KiB 的块，收到 ACK 后再发送；首 ACK 延迟 80 ms，验证等待期间没有第二块越过背压。完成全部行后还调用 `spng_decode_chunks()` 检查尾部，不能只根据像素已输出判断文件完整。

编译配置为无 pthread、无内存文件系统，初始 heap 16 MiB、最大 32 MiB，C 计量 allocator 的活跃请求 payload 上限 16 MiB，编码输入上限 8 MiB。输入仍有 Node Buffer / 浏览器 ArrayBuffer 和 WASM 副本，尚不是流式输入。

## Node 实际结果

两张素材均为可辨图案的非交错 8-bit RGBA PNG（color type 6），不是原 Source 内容。生成器在写入编码前原始 RGBA 时增量保存完整流 SHA；Sharp/libpng 独立解码首/中/末各 32 行，并逐字节对照原始图案，保存三个区域 SHA。被测 Worker 的完整流与原始 RGBA 生成基准匹配，三个区域另与独立 libpng oracle 匹配；consumer 只增量计算 hash，不收集完整 raster。

| 场景                        | 交付与结果                                                                | C 活跃请求 payload 高水位 | 清理                                            |
| --------------------------- | ------------------------------------------------------------------------- | ------------------------- | ----------------------------------------------- |
| 1080×20000，PNG 1,232,056 B | 20,000 行 / 86,400,000 B；原始 RGBA 完整流 SHA 与三个独立区域 SHA 全匹配  | 2,390,666 B               | live=0、allocations=0、Worker exit=0            |
| 1080×40000，PNG 2,463,519 B | 40,000 行 / 172,800,000 B；原始 RGBA 完整流 SHA 与三个独立区域 SHA 全匹配 | 3,622,129 B               | live=0、allocations=0、Worker exit=0            |
| 40000 高图首块后取消        | 已同步解码首 256 行，只交付 65,536 B，ACK 等待点接收 cancel 后不再输出    | 3,622,129 B               | cancelled；live=0、allocations=0、Worker exit=0 |
| 同图仅删除 IEND 的 12 B     | 全部像素已输出，尾部阶段仍拒绝，`SPNG_IO_EOF=-1`，phase=3                 | 3,622,117 B               | failed；live=0、allocations=0、Worker exit=0    |

完整图耗时约 242 / 376 ms，均含一次 80 ms ACK 人为延迟，仅用于复验这台机器的机制结果，不是产品首图或移动性能分布。最大条带 1,105,920 B；所有场景的实际 heap 都为 16,777,216 B、非共享 buffer。

截断测试曾发现自有 C 适配将 libspng 的负 IO 错误再次取负，误作正行数。修复为明确的负失败哨兵并单独保留原错误码/阶段后重跑四项通过；没有修改 libspng 或素材来掩盖失败。该场景也证明，正式产品必须能在尾部失败时作废已生成片，不能把部分像素显示当成整页有效。

## Codex 内置浏览器实际结果

07:32:39.286–07:32:40.308 UTC，由测试页的“运行全部五项”按钮启动。环境为 Codex 内置 Chromium 156，`crossOriginIsolated=false`、`SharedArrayBuffer` 未暴露，四个协作终态均报告实际 `sharedHeap=false`，没有增加 COOP/COEP 或 pthread。

- 两张完整图依次输出 86,400,000 / 172,800,000 B；seq/offset 连续、首 ACK 延迟门通过。浏览器只保留每图首/中/末三个 32 行区域（每个场景 414,720 B），六个区域的原始 RGBA SHA 均匹配独立 oracle，六条 Canvas 已实际可见并截图。浏览器没有计算完整输出 SHA；完整流 SHA 是前述 Node 分项证据。
- 两张图的 Worker 实测耗时约 201 / 297 ms，consumer 约 231 / 318 ms；包含刻意的 80 ms 首 ACK 延迟，不能当作产品或冷启动性能。WASM heap、allocator 高水位与 Node 对应场景一致。
- 协作取消只收到首个 65,536 B，终态 `cancelled`、已解码 256 行、C 计量清零。截断图在输出全部行后以 phase=3 / IO EOF 拒绝，C 计量清零。
- 额外强制终止场景在首块后调用浏览器 `Worker.terminate()`，不发送 ACK/cancel；100 ms 观察窗无后续消息，未收到协作 close。报告明确保留 `allocatorCleanupObserved=false`、`wasmHeapReleaseMeasured=false`，不将无消息或应用活动计数归零称作已观测 heap/进程回收。
- 总报告为 `passed=true/error=null`，应用活动计数与迟到消息均为 0；四个协作 Worker 的 close 后由主页面调用 terminate。浏览器没有原生 Worker exit 事件，这与 Node 的自然 exit=0 是不同证据。

页面“关闭服务”按钮触发 `server.close()` / `closeIdleConnections()`；exec session 11773 随后输出 `server closed`、exit=0，`lsof` 复核 8951 无监听。没有重启 AOT 或遗留本轮 Node 服务。

### 保存身份与本地复验

本轮自有 C/TypeScript、HTML、三套 strict TS 配置、构建参数、版本与 Node 结果已冻结在 `.local/long-image-codec/runs/2026-11-04-libspng-rgba8/`；上游仅保留固定提交与校验来源，不将 vendor/缓存搬入源码。浏览器报告、截图、AX 与关闭证据补充到同一目录，各自 SHA 单列在 `web-evidence-sha256.json`。

| 证据                     | SHA-256                                                            |
| ------------------------ | ------------------------------------------------------------------ |
| Node `result.json`       | `9593084a6bcfc407096ee37881412e9e92c624affd9380c2409a42d7c970e608` |
| Web `web-result-1.json`  | `1ebd3e3d6c05e57bb8a52064ee4bcae579e3c419af2c82e43969117074c76f64` |
| 首中末截图 `regions.jpg` | `e0442501a911e27b8bfbafb4eabda11ab18c7b0d8dd9fded640b128c2ad2baef` |

已保留实验输入的这台机器可在主仓库复验；首次环境仍需固定上游、完整 bootstrap、zlib archive 校验与构建，不能将以下 replay 命令当作干净 checkout 的正式产品构建入口。

```sh
env PATH="$PWD/.local/node24/bin:$PATH" node .local/long-image-codec/run.ts
env PATH="$PWD/.local/node24/bin:$PATH" PORT=8951 node .local/long-image-codec/server.ts
```

浏览器访问 `http://127.0.0.1:8951`，点击“运行全部五项”，报告自动保存为新的 `web-result-N.json`；完成后点击“关闭服务”，再核对 shell exit 与端口释放。重跑前保留冻结原报告，不把重复结果覆盖成旧轮证据。

## 限制与后续

- allocator 高水位只统计 libspng、zlib、编码输入和条带的请求 payload；不含 allocation header、分配器元数据/碎片、栈、静态区或 realloc 短暂新旧并存。heap 上限与该计数均不等于进程物理内存峰值。
- 64 KiB 单块背压不证明已消费的 JS ArrayBuffer 立即 GC。消费者保存的三个 oracle 区域也须在后续产品预算中单独计费。
- 取消只证明 ACK 等待点协作取消，首个 256 行同步 C 调用已经结束；不证明同步 C 内抢占，也没有用自然 exit 冒充强制 Worker 终止。
- 本轮仅覆盖 RGBA8 非交错素材；RGB/灰度/调色板 tRNS、ICC/gamma、16-bit、Adam7、JPEG、WebP、动画与 EXIF 方向尚未验收。不能泛称支持全部非交错 8-bit PNG。
- 顺序输出不等于随机区域访问或按视口生成。末尾跳转、反向滚动、重新扫描、LOD 交替、实际 tile 编码和最终 Flutter cache / GPU 释放都仍待正式实现。
- Native 的内置 WASM / Worker、平台文件、Flutter 与真机内存仍须单独验证。当前机制不构成调整正式协议和限额后即可发布的依据。

原始 JSON、源码冻结记录、工具日志与素材保留于 ignored 实验目录；本页只保留后续实现需要的输入、结果和边界。
