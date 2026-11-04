# 长图 codec / WASM 机制验证

## 结论与边界

2026-11-04，固定 libspng 的顺序行解码已通过 Node Worker 的两张大尺寸合成 PNG、ACK 边界取消及缺失 IEND 尾部四项机制测试。完整 RGBA 输出分别为 86,400,000 B 与 172,800,000 B，实际 WASM 线性 heap 均为 16 MiB；没有在 WASM 中建立完整 raster。该证据推进[长图计划](../plan/reader-image-decoding.md)的 codec 可交付性门，尚未接入 Source、Flutter 或 Native 产品，也不证明进程/GPU 峰值。随后同一素材又通过官方 macOS SDK 的独立重建和 Node / Web 复验，见下方第二轮；首轮组合工具链证据保留原样。

同一 WASM 与素材已在 Codex 内置 Chromium 156 的真实 Web Worker 通过五项测试，并亲眼核对首/中/末区域。正式长图合同、任意区域读取、缩放/LOD、PNG tile 编码、资源池和真实设备仍未完成，不改变现有 16 Mi 像素准入。

同日，固定 libjpeg-turbo 3.2.1 又通过官方 macOS SDK 的 Node 顺序 JPEG 机制：两张 baseline 长图的完整尺寸、1/2 与 1/4 原生 IDCT 缩放，连同 ACK 取消、缺失 EOI 和 progressive 拒绝，共九项通过。随后 JPEG 又在 Codex 内置浏览器通过完整尺寸及生命周期六项；Web 只核对首/中/末区域，未计算完整流 SHA，1/2、1/4 像素对照仍只有 Node 证据。

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

## 官方 macOS SDK 的第二轮

为消除首轮本机组合工具链偏差，另建 `.local/long-image-official-sdk/`，仅下载 emsdk 5.0.7 的官方 Darwin arm64 归档。SDK 来源由 emsdk 固定提交 `41190c21c662e9cc1962aea94e71cbae9fd2fc87` 映射到 release `6cd98e86d7749ff98b82b7f2ae78eb4f01942788`；GCS 对象 generation 为 `1777481187423024`，大小 282,468,276 B。下载第一段触发 600 秒上限，确认退出后对同一 generation 断点续传；完整文件的官方 MD5、CRC32C 均匹配，SHA-256 为 `37554ed4c36abb1c802aa280f2c1ef9702e19e832a66c2fe6d940b65a2049b2c`。

实际工具是 emcc 5.0.7 / `263db4c…`、LLVM 23.0.0git / `7b58716d96c3ae4c0c4e6f72e29b16137bb6224b`、Binaryen 129 / `version_125-430-gc6a5e65b7`。Emscripten 的版本检查接受 128 或 129；本轮保留 `-Werror=version-check`，没有把“源码预期 128”误称归档实际版本，也没有复用 Homebrew 二进制或第一轮编译缓存。

官方 `--emit-tsd` 使用 `--outFile`，与项目 TS 6.0.3 的弃用错误冲突；声明生成改用该官方 package-lock 固定的 TypeScript 5.9.3 独立工具依赖。自有脚本和三套 harness 继续由项目 TS 6.0.3 严格检查，不增加 `ignoreDeprecations`、宽泛断言或上游源码补丁。首次缺少 tsc 和随后 TS5101 的失败日志均保留。

同一冻结 C / libspng 得到新 WASM 67,341 B，SHA-256 `a90a18bce4ea17b9de95cff97acae2d560025030e12fb085eb583d6167bc7190`。Node 四项全部重跑通过，完整流匹配原始 RGBA 基准、三个区域匹配独立 libpng oracle，16 MiB 非共享 heap、条带和 allocator 计数与首轮对应场景一致，四个 Worker 均清理至 0 并自然 exit=0。

08:02:22.635–08:02:23.643 UTC，主代理在 Codex 内置 Chromium 156 点击官方新页面的全部五项；首/中/末六区可见且摘要匹配，两个完整输出、首块取消、IEND 尾部拒绝及额外强制 terminate 观察窗均通过。`crossOriginIsolated=false`、无 SAB，四个协作终态的实际 heap 16 MiB、C 请求账本为 0。强制 terminate 仍未声称观测到 heap 释放。页面关闭服务后 session 99171 输出 `server closed`、exit=0，8952 无监听。

第二轮冻结在 `.local/long-image-official-sdk/runs/2026-11-04-official-darwin-arm64-rgba8/`，与首轮分别保存；`official-lock.json` 的 Web 待验状态反映其生成时点，后补的浏览器报告记录上述实际完成结果，不改写旧清单或日志。

| 第二轮证据               | SHA-256                                                            |
| ------------------------ | ------------------------------------------------------------------ |
| Node `result.json`       | `1dc04e63ff7fbcf731441a260f718decbac0f8e36cd1c744e123cc160f0c8059` |
| Web `web-result-1.json`  | `617eab2d9a164fdb3c9f7db898debd0c72534b3a432b77c5b58fb85575fd1465` |
| 首中末截图 `regions.jpg` | `0d25dfe682937876b05dbd03c235e2f6e7dfd1905d8b5453ec9d350f01efd25f` |

该轮证明固定官方 macOS 工具链能重建并执行此 PNG 机制；尚未验证 Linux SDK、跨主机字节一致性或 Native 内置执行，不能据此宣称完整跨平台可复现构建已通过。正式接入还需上游 submodule、维护构建入口和后文各项产品门。

## libjpeg-turbo 顺序 JPEG 机制

### 固定输入与适配

实验位于忽略的 `.local/long-image-jpeg/`。官方 [libjpeg-turbo 3.2.1](https://github.com/libjpeg-turbo/libjpeg-turbo/releases/tag/3.2.1) 独立 checkout 固定为 `7b4993786d856cbccabfc0ed2f923ba000e326cc`，上游工作区保持干净。使用上一节同一官方 Emscripten 5.0.7 SDK、Node 24.15.0 与项目 TS 6.0.3，但使用 JPEG 自己的 `EM_CONFIG` 和缓存，保留 `-Werror=version-check`。CMake 构建无 SIMD 的 `jpeg-static`，关闭 shared、TurboJPEG API、tools 和 tests，再链接项目自有最薄 C 适配；未使用实际指向 IJG jpeg 9f 的 Emscripten 内置 `USE_LIBJPEG` port。

适配按官方 [libjpeg API](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/7b4993786d856cbccabfc0ed2f923ba000e326cc/doc/libjpeg.txt) 执行 `read_header → start_decompress → read_scanlines → finish_decompress → destroy`。头部后先以 `jpeg_has_multiple_scans()` 拒绝多 scan，另限定 8-bit、Huffman、灰度/RGB/YCbCr 和顺序 DCT 的 SOS 参数；实际素材是 SOF0 baseline。`JCS_EXT_RGBA` 保证 opaque alpha，缩放设置为 1/1、1/2 或 1/4，再从库计算的输出尺寸分配至多 256 行条带；每次累积 `read_scanlines()` 实际返回的行数。

单 scan 顺序 DCT 的系数控制器只需局部 MCU 缓冲；progressive 及 multi-scan sequential 会使用整图系数，普通 `start_decompress()` 还会预读所有 scan，不能靠缩小输出 raster 消除这些内存。依据为固定 [系数控制器](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/7b4993786d856cbccabfc0ed2f923ba000e326cc/src/jdcoefct.c)和[解压启动逻辑](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/7b4993786d856cbccabfc0ed2f923ba000e326cc/src/jdapistd.c)。当前适配上限为宽 4096、高 65500、编码输入 8 MiB；JPEG 本身的每轴尺寸字段及该库上限不能沿用 PNG 的 100000 高范围。

通过官方 `jmemsys` 后端接口计量库的池分配，加上自有编码输入和条带，请求 payload 总上限 16 MiB；不修改上游。WASM 初始 16 MiB、最大 32 MiB，关闭 pthread 和内存文件系统。通道每次只转移至多 64 KiB，收到 ACK 才继续，首 ACK 人为延迟 80 ms。消费者增量计算 SHA，不保存完整 raster。

默认内存 source 在数据耗尽时会警告并合成 EOI，故自有 `emit_message` 将 corrupt-data warning 转为失败；完整行读取后仍调用 `finish_decompress()` 消费尾部。每个可能进入 libjpeg 的导出调用都有活跃 `setjmp`，失败后统一 destroy，避免跳向已经返回的栈帧。首次额外使用的 `is_baseline` ABI 字段虽在头文件中存在，固定库实际上未赋值，曾错拒有效 baseline；已删除此门和不必要的 JPEG8 ABI 设置，保留错拒摘要，没有修改上游。此路径可以接纳符合条件的 SOF0/SOF1 单 scan 顺序 DCT，但未据此声称全部模式已实测。

WASM 模块以 `unknown` 导入，再由 Zod 的具名函数 schema 校验导出函数的参数/返回值；每次读取 heap 时重新解析 `HEAPU8`，避免增长后的旧 view。未消费的 `--emit-tsd` 在遭遇前述 SDK/TS6 弃用冲突后删除，失败日志保留；没有使用 `any`、宽泛断言或关闭类型检查。

### 九项实际结果与像素基准

两张 JPEG 由 Sharp 0.35.5 编码，输入为可辨的合成图案，不是 Source 内容。完整尺寸的 expected SHA 与首/中/末各 32 行均取自 Sharp / libvips 8.18.7 / mozjpeg `0826579` **重新解码 JPEG** 的 RGBA，不能以编码前原始 RGBA 的无损 SHA 作为有损结果基准。

缩放参考来自 Homebrew 安装的本机原生 `djpeg` 3.2.1：`-strict -scale 1/2` 或 `1/4 -dct int -rgb -png -noicc`。其输出 PNG 由 Sharp 无损解析为 RGBA，未调用 Sharp resize。被测 WASM 的六个完整流 SHA 和各自三个区域 SHA 均精确匹配；这证明与独立原生编译结果一致，仍是同一 libjpeg-turbo 算法，不能称为另一种独立 JPEG 算法实现。

| 输入与比例     | 输出 raster / 完整流字节  | C 请求 payload 高水位 |
| -------------- | ------------------------- | --------------------- |
| 720×30000，1/1 | 720×30000 / 86,400,000 B  | 1,370,703 B           |
| 同图，1/2      | 360×15000 / 21,600,000 B  | 986,217 B             |
| 同图，1/4      | 180×7500 / 5,400,000 B    | 795,369 B             |
| 720×60000，1/1 | 720×60000 / 172,800,000 B | 1,959,276 B           |
| 同图，1/2      | 360×30000 / 43,200,000 B  | 1,574,790 B           |
| 同图，1/4      | 180×15000 / 10,800,000 B  | 1,383,942 B           |

两张 JPEG 分别为 589,235 / 1,177,808 B；全尺寸峰值包含这份编码输入及 737,280 B 条带，扣除输入后的计量值同为 781,468 B。六项实际 heap 均为 16,777,216 B、非共享 buffer，关闭后 live/allocations 均为 0、Worker 自然 exit=0。两次全尺寸耗时约 268 / 427 ms，含 80 ms ACK 人为等待，只是本机机制记录，不能作为产品或真机性能结论。

其余三项使用 60000 高素材或独立小 progressive 素材：

- 首块 ACK 点协作取消：已经同步解码 256 行，只交付 65,536 B；终态 `cancelled`，live/allocations=0，exit=0。没有证明同步 C 内抢占。
- 仅删除最后 EOI 的 2 B：在 scanline phase=2 触发 `JWRN_JPEG_EOF=120`，只交付 59,904 行 / 172,523,520 B 后失败；live/allocations=0，exit=0。该警告可在库的预读阶段发生，不能写成全部行交付后才在 finish 阶段失败。
- 320×480 progressive JPEG（2,841 B）：在 `start_decompress()` 之前以自有拒绝码 `-4`、phase=1 返回，无 raster 交付；live/allocations=0，exit=0。这是 progressive 的接纳拒绝证据，不是 progressive 解码通过，也未另行实测 multi-scan sequential 素材。

最终 Node exec session 80502 exit=0；两套 strict TS、Prettier 和 Xcode clang-format 21.0.0 检查通过。所有测试、素材生成、原生 oracle 和编译命令已退出；临时 raw/参考 PNG 已删除，进程复核无 JPEG 相关遗留。

### JPEG 内置浏览器实际结果

主代理在 Codex 内置 Chromium 156 亲自点击“运行全部六项”。保存的报告为 `passed=true/error=null`，`crossOriginIsolated=false`、`SharedArrayBuffer` 未暴露，五个协作终态均报告实际非共享 heap；活动 Worker 与迟到消息计数均为 0。

- 两张完整图输出 86,400,000 / 172,800,000 B，seq/offset 连续，首 ACK 延迟门通过；每图只保留首/中/末三个 32 行区域共 276,480 B，六个区域与 Sharp 解码 JPEG oracle 的 SHA 精确匹配，六条 Canvas 可见并截图。Web 没有完整流 SHA，也没有执行 1/2、1/4 缩放；这两项范围不能沿用 Node 的像素证明。
- 两次完整图 Worker 耗时约 233 / 354 ms，含人为 80 ms 首 ACK 等待；实际 heap 16 MiB，C 请求高水位分别为 1,370,703 / 1,959,276 B，与 Node 一致。这不是产品或真机性能结论。
- 首 ACK 协作取消只交付 65,536 B，已解码 256 行；缺失 EOI 在 phase=2 / code=120、59,904 行处失败；小 progressive 在 phase=1 / code=-4、`start_decompress()` 前拒绝。五个协作终态在 C close 后均为 live/allocations=0。
- 额外强制 terminate 在首块后直接调用 `Worker.terminate()`，不发送 ACK/cancel；100 ms 内无后续消息，未伪造协作 close。报告保留 `allocatorCleanupObserved=false`、`wasmHeapReleaseMeasured=false`，没有测量浏览器线程退出或 heap 清理。

主代理点击“关闭服务”后，server exec session 58504 输出关闭终态并 exit=0；`lsof` 再次核对 8952 无监听。浏览器报告、截图、AX 与关闭证据后补到同一冻结目录；最初 `checks.json` / `toolchain.json` 的 Web 待验字段仅反映生成时点，不改写为后续状态。

### JPEG 保存身份与复验

最终源码、素材与 oracle 清单、工具链、构建参数、运行日志和校验已冻结在 `.local/long-image-jpeg/runs/2026-11-04-libjpeg-turbo-3.2.1-official-sdk/`，详细临时输出不入库。后补 Web 证据的 SHA 另存于 `web-evidence-sha256.json`。

| JPEG 证据                   | 身份                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------- |
| WASM                        | 250,040 B；SHA-256 `369247f9e75917b33dc0f17decc508ee6eac01c2e20a4bf3ddeab57c591c91da` |
| Node `result.json`          | SHA-256 `39ac3576abdaedf9d34b0255eb41d93c42bb832913a712ce0e4f9a6b380e4c5c`            |
| `fixtures.json`             | SHA-256 `357639e092add3684f3a47d8867b6cf5d53542a3b8e1b6c753fcf011b50315a6`            |
| Web `web-result-1.json`     | SHA-256 `857150ddfe03c145813cc5e51e737661e631ed91ddb6968ed11134c1d002400a`            |
| Web 截图 `jpeg-regions.png` | SHA-256 `c702cb691aa960f9629e915404296cd130df4f65a92b27e3778922a57c1200cf`            |
| Web AX `jpeg-ax.txt`        | SHA-256 `759516393053f7ea6f2d0be38b63115dfd617e31bcff50043e1bbe02a589d496`            |

已保存输入及官方 SDK 的这台机器可在主仓库复验；以下不是干净 checkout 的正式产品构建入口。先保留冻结报告，再在工作实验目录重跑，不覆盖旧轮证据。

```sh
env PATH="$PWD/.local/node24/bin:$PWD/node_modules/.bin:$PATH" \
  EM_CONFIG="$PWD/.local/long-image-jpeg/.emscripten" \
  JPEG_EMCC="$PWD/.local/long-image-official-sdk/sdk/emscripten/emcc" \
  JPEG_EMCMAKE="$PWD/.local/long-image-official-sdk/sdk/emscripten/emcmake" \
  JPEG_TOOLCHAIN_ID=emscripten-5.0.7-official-37554ed4c36abb1c802aa280f2c1ef9702e19e832a66c2fe6d940b65a2049b2c \
  node .local/long-image-jpeg/build.ts
env PATH="$PWD/.local/node24/bin:$PATH" node .local/long-image-jpeg/native-oracles.ts
env PATH="$PWD/.local/node24/bin:$PATH" node .local/long-image-jpeg/run.ts
pnpm exec tsc --project .local/long-image-jpeg/tsconfig.json
pnpm exec tsc --project .local/long-image-jpeg/tsconfig.web.json
```

Web 复验另运行 `node .local/long-image-jpeg/build-web.ts`，再以 `PORT=8952 node .local/long-image-jpeg/server.ts` 启动本地页；在 Codex 内置浏览器点击“运行全部六项”，完成后点击“关闭服务”，核对 shell exit 与端口释放。重跑会在工作实验目录写报告，须先保留冻结原报告。

JPEG 当前尚未覆盖 Web 缩放、Native、真实 Source、EXIF 方向、ICC/色彩管理、CMYK/YCCK、高位深、随机区域或 tile 编码。严格 warning 与 finish 证明本轮缺 EOI 被拒绝，不证明校验真实 EOI 之后的额外字节。计量不含 allocation header、libc 元数据/碎片、栈、静态数据、JS 副本或 RSS；WASM 最大 heap 也不是浏览器/进程总内存上限。前述离线 Sharp/native oracle 生成中的完整图像分配不计入被测解码器证据。

## 限制与后续

- PNG allocator 高水位只统计 libspng、zlib、编码输入和条带的请求 payload；JPEG 另按上述 libjpeg 池请求、编码输入和条带计量。均不含自有 allocation header、底层分配器元数据/碎片、栈或静态区，PNG 还未计入 realloc 短暂新旧并存。heap 上限与该计数均不等于进程物理内存峰值。
- 64 KiB 单块背压不证明已消费的 JS ArrayBuffer 立即 GC。消费者保存的三个 oracle 区域也须在后续产品预算中单独计费。
- 取消只证明 ACK 等待点协作取消，首个 256 行同步 C 调用已经结束；不证明同步 C 内抢占，也没有用自然 exit 冒充强制 Worker 终止。
- PNG 分项仅覆盖 RGBA8 非交错素材；RGB/灰度/调色板 tRNS、ICC/gamma、16-bit、Adam7、WebP、动画与 EXIF 方向尚未验收。JPEG 只在上述 Node baseline / 原生缩放及 Web 完整尺寸机制范围通过，不能泛称所有 PNG/JPEG 或终端阅读均支持。
- 顺序输出不等于随机区域访问或按视口生成。末尾跳转、反向滚动、重新扫描、LOD 交替、实际 tile 编码和最终 Flutter cache / GPU 释放都仍待正式实现。
- Native 的内置 WASM / Worker、平台文件、Flutter 与真机内存仍须单独验证。当前机制不构成调整正式协议和限额后即可发布的依据。

原始 JSON、源码冻结记录、工具日志与素材保留于 ignored 实验目录；本页只保留后续实现需要的输入、结果和边界。

## 正式源码构建与 Node 验收

2026-11-04，macOS arm64。上述忽略目录内的历史机制随后内化为 `runtime/image-codec/{codec.h,png.c,jpeg.c}`、严格 TypeScript session 和 `tools/images` 构建/验收工具；真正上游由固定提交的 `vendor/libspng`、`vendor/libjpeg-turbo` submodule 提供。本节记录正式入口生成的新产物，不将前述旧 WASM 的浏览器或原生 oracle 结果移作新产物验收。构建和操作说明见 [image-codec README](../../runtime/image-codec/README.md)。

实际工具为 Node 24.15.0、Python 3.15.2、CMake 4.4.5、官方 Emscripten 5.0.7-git / `263db4cffa6f9fc2ec514a70abac81362ea41849`、Clang 23.0.0git / `7b58716d96c3ae4c0c4e6f72e29b16137bb6224b`、Binaryen 129 / `version_125-430-gc6a5e65b7`。SDK 归档仍为本页已记录的官方 Darwin arm64 SHA-256 `37554ed4c36abb1c802aa280f2c1ef9702e19e832a66c2fe6d940b65a2049b2c`；上游提交分别为 libspng `bab9f94a1186f8fda234b4e1cb65e1b9a77049cc`、libjpeg-turbo `7b4993786d856cbccabfc0ed2f923ba000e326cc`，zlib 1.3.1 来自固定官方 SDK port。参考图工具为锁定的 Sharp 0.35.5 / libvips 8.18.7 / mozjpeg `0826579`。

最终构建身份为 `0c00a221dbc8df36bddb2baf4393fb2cc492a8f288a0a0daf088dfe900dc4a8d`。正式 CLI 先验证 manifest 身份与输入自洽，再核对真实四份 JS/WASM 的大小和 SHA。最终19项全部通过、进程 exit=0；报告保存在忽略的 `runtime/image-codec/.local/verification/formal-final/result.json`，SHA-256 为 `c516f2982013c0e163279d039c845a924d5bfef75ddfb2700f017309de26eab5`。

### 四幅合成长图与资源终态

素材由正式 CLI 每次重新生成，不依赖旧研究目录。PNG 为非交错 RGBA8，完整流 expected SHA 取编码前原始 RGBA；JPEG 为 baseline、4:4:4，expected SHA 取 Sharp 重新解码同一 JPEG 的 RGBA，不能使用有损编码前像素。消费者只增量计算完整流及首/中/末256行区域的摘要，不积存完整输出 RGBA；四图的完整与区域摘要均精确匹配参考。

| 格式与尺寸     | 编码输入 B | 完整 RGBA 输出 B | C 请求 payload 高水位 B | 实际 WASM heap B |
| -------------- | ---------: | ---------------: | ----------------------: | ---------------: |
| PNG 1080×20000 |  1,243,254 |       86,400,000 |               2,401,864 |       16,777,216 |
| PNG 1080×40000 |  2,487,252 |      172,800,000 |               3,645,862 |       16,777,216 |
| JPEG 720×30000 |    904,939 |       86,400,000 |               1,679,009 |       16,777,216 |
| JPEG 720×60000 |  1,809,921 |      172,800,000 |               2,583,991 |       16,777,216 |

四个完整终态均为 `complete`、C error=0、phase=3；`closeSucceeded=true`，close 后 live bytes 和 allocations 均为0。输入上限8 MiB、计量 payload 上限16 MiB、最大 WASM heap 32 MiB、条带最多256行；实际观察到的16 MiB heap是容量，不是进程峰值。payload包含编码输入、条带及库分配请求，排除 allocation header、底层分配器元数据/碎片、realloc 短暂双占用、栈、静态数据、JS副本和图形资源。夹具生成与 Sharp 参考解码确实分配完整图像，其内存不属于被测 WASM 计量；本轮没有测量进程 RSS 或 GPU 峰值。

### 19项真实覆盖与边界

首轮正式源码15项已通过；最终轮保留其范围，增加两幅更高图的完整像素检查和两种 codec 各一个真实 pull 暂停检查，共19项：4项完整图、2项暂停、2项首块 signal 取消、2项消费者 break、2项截尾、3项不支持格式拒绝、2项直接 ABI 生命周期、2项 JPEG 缩放尺寸/字节。新增高图只增加完整流验证，不能写成四幅图均运行了全部取消、截尾或缩放场景。

- PNG/JPEG 暂停检查分别使用1080×20000和720×30000输入，在公开 lease 上只计数并转调真实 `image_next()`：header 后调用数为0，首 chunk 后为1；请求80 ms暂停，实际约82.73 / 81.42 ms，调用数仍为1。恢复拉取同一 strip 的下一 chunk 后仍为1，再取消，终态交付131,072 B、已解256行、live/allocations=0。这证明同线程 pull 背压，不等于跨 Worker 的 ACK 协议验收。
- 两种 codec 首 chunk 后 signal 取消，以及消费者直接 break，均只交付65,536 B、已解256行；终态为 `cancelled`、close成功、live/allocations=0。这是同步 C 调用之间的协作取消，不证明 C 内抢占。
- PNG 仅删除末尾12 B的 IEND：已经交付全部20,000行 / 86,400,000 B，随后在 phase=3、code=-1失败，确实经过尾部操作。JPEG仅删除末尾2 B的EOI：在 phase=2、code=120失败，交付29,952行 / 86,261,760 B；不能写成所有行完成后才在 finish 失败。两者 close 后账本均为0。
- 小型非RGBA PNG、Adam7 PNG和progressive JPEG均在 phase=1拒绝，没有 raster交付；这是拒绝范围的验证，不是这些格式解码通过。
- 两库直接 ABI 均拒绝输入分配长度与 open 长度不一致、拒绝超过8 MiB的输入；多次close后live/allocations为0。1 MiB输入的peak在close后保持可读，下次32 B输入的peak为32 B，不继承上次高水位。
- JPEG 720×30000的1/2、1/4输出分别为360×15000 / 21,600,000 B和180×7500 / 5,400,000 B，尺寸、字节数、真实收尾及释放通过。新一轮没有对这些缩放输出运行像素oracle；前述独立原生djpeg结果保留为历史证据，不把Sharp resize或本轮记录的未对照SHA当作缩放像素证明。

### 产物身份与独立缓存重建

| 正式产物    |  大小 B | SHA-256                                                            |
| ----------- | ------: | ------------------------------------------------------------------ |
| `png.mjs`   |  31,143 | `e169f3f750965775be6522bb0578f7f2f2919fb41e912e688e2f2397c7a1e3e2` |
| `png.wasm`  |  67,753 | `dcacd157f1a0712a81560b0b0abcdf0dd737e1509f3e468bfe3f68d06a5b2840` |
| `jpeg.mjs`  |  37,316 | `48acf0712120301e105513078dd477f4fb557dae6e8ef282c83502ef54ac35ad` |
| `jpeg.wasm` | 250,162 | `b5f81ab31746b0cc11970885b94fa5f213b1b2f8be7650593994e2affb092b63` |

同一主机、同一固定SDK下，另设独立构建缓存和输出目录，并在外部注入无效 `CFLAGS`、`LDFLAGS`、`EMCC_CFLAGS`、`CMAKE_TOOLCHAIN_FILE` 后重新构建，exit=0；构建身份及上表四份资产字节均一致，四份JS/WASM中未发现本机绝对路径字符串。摘要保存在忽略的 `.local/image-codec-repro-result.json`。这证明本轮同机、独立缓存与环境过滤下的重建一致性；没有验证Linux构建或跨主机字节一致性。

使用仓库固定Node/pnpm版本，在根目录通过正式入口复验；新报告写入另一个忽略目录，保留原报告：

```sh
git submodule update --init --depth 1 vendor/libspng vendor/libjpeg-turbo
pnpm image-codecs:build
pnpm image-codecs:check \
  --build runtime/image-codec/.local/build/0c00a221dbc8df36bddb2baf4393fb2cc492a8f288a0a0daf088dfe900dc4a8d \
  --report runtime/image-codec/.local/verification/formal-rerun/result.json
```

输入或工具链变化时，使用构建命令返回的新身份目录；已有SDK/zlib归档可按 [README](../../runtime/image-codec/README.md) 的正式选项传入。普通 `pnpm test:image-codecs` 是不编译SDK的小夹具工程回归，不能替代这里的真实WASM命令。

本节只证明正式源码在Node中的顺序解码与生命周期，以及上述同机重建。新产物尚未据此取得浏览器、Source图片链、Flutter、Native内置执行、tile/LOD/位置恢复或真实设备性能验收；也不代表全项目检查、P0或长图产品门通过。历史浏览器的Worker/ACK与原生缩放结果仍按各自输入和旧产物身份单独解释，正式16 Mi像素准入不因这份报告自动改变。
