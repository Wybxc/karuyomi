# 图片 codec 构建依赖

当前已内化 PNG/JPEG 解码与 PNG 编码的 C 适配、严格 TypeScript 顺序接口、独立 codec Worker，以及官方 SDK 准备器与构建器。Worker 消费有界 Blob 并输出 PNG 条带；材料加入 Web Static Assets / Native 内置目录。正式 Source 所有权、Protobuf、缓存和 Flutter 阅读器接入仍按[长图计划](../../docs/plan/reader-image-decoding.md)推进。历史 Node/Web 机制与正式源码验收分别见[长图 codec 验证](../../docs/verification/long-image-codec.md)。

## 准备工具链

使用仓库 `.node-version` 固定的 Node 和 Python 3.10+：

```sh
pnpm image-codecs:prepare
```

锁文件 `toolchain-lock.json` 固定官方归档的 generation、字节数、SHA-256 及实际编译器版本。当前只完成 macOS arm64 官方归档和可执行文件验证；Linux x64 只有官方元数据，尚缺归档 SHA-256 与运行验收，准备器明确拒绝该平台，不自动下载未验证的工具链。

已有同一份官方归档可在导入边界校验后离线安装：

```sh
pnpm image-codecs:prepare --archive /absolute/path/wasm-binaries-arm64.tar.xz
```

SDK 安装在忽略的 `runtime/image-codec/.local/toolchains/<host>-<archive-sha256>/`。同一安装由 `proper-lockfile` 互斥，下载或导入时验证归档大小与 SHA-256；解包、真实版本检查和完成记录写入成功后才原子替换目标目录。复用读取完成记录并检查 Emscripten / Clang / Binaryen 版本，不重复遍历并计算整个 SDK 的文件哈希。修改或损坏的安装应删除相应缓存目录后重新准备，不增加旧安装兼容层。

`.emscripten` 明确指向该安装的 LLVM、Binaryen、项目 Node 和独立 `EM_CACHE`；准备器保留官方版本检查，不使用本机 Homebrew 编译器或执行 `emsdk.py`。可用 `--cache-root` 指定缓存根、`--python` 指定 Python。SDK 属于校验下载的构建依赖，不作为源码或未使用的 submodule 提交。构建器不在 SDK 内执行 npm 安装；项目工具依赖由 pnpm 精确锁定，产物 ABI 在加载边界做运行时校验。

中断准备会关闭 HTTP 流、终止所属子进程组并等待退出，删除临时安装并释放锁。回归使用临时小归档和本机 HTTP 服务，不下载大型 SDK：

```sh
pnpm test:image-codecs
```

准备器通过不表示已经生成产品 WASM，也不表示 Source、Flutter、Native、真机或进程/GPU 峰值验收完成。

## 本轮验证

2026-11-04，在 macOS arm64 上用已保存的 282,468,276 B 官方归档执行正式 CLI 离线安装，exit=0，耗时 19.51 s；随后不传 `--archive` 复用同一安装，exit=0，耗时 0.339 s，没有下载。实际版本为 Node 24.15.0、Python 3.15.2、Emscripten 5.0.7-git、Clang 23.0.0git、Binaryen 129，与锁一致。摘要保存在忽略的 `.local/image-codec-toolchain-acceptance/`。

19 项回归覆盖离线复用、归档大小与摘要错误、完成记录/身份/可执行文件不一致、HTTP 限额与取消、父进程退出后持有 stdio 的后代清理和主动取消。后两项实际完成清理，不只核对配置；结束后没有本轮准备器、夹具、临时安装或锁残留。Linux 官方归档仍待验收；正式 codec 构建与运行证据按下文独立记录。

## 固定上游与正式构建

真正上游通过 `vendor/libspng`（v0.7.3 / `bab9f94a1186f8fda234b4e1cb65e1b9a77049cc`）和 `vendor/libjpeg-turbo`（3.2.1 / `7b4993786d856cbccabfc0ed2f923ba000e326cc`）submodule 引入；自有薄适配是这里的 `png.c`、`jpeg.c`、`encoder.c` 与共同 ABI header，不复制依赖缓存为源码。

```sh
git submodule update --init --depth 1 vendor/libspng vendor/libjpeg-turbo
pnpm image-codecs:build
```

构建器读取父仓库 index 的 gitlink，检查上游 HEAD 和工作区干净；身份包含 SDK、实际 Node/Python 与 CMake 版本、上游 pin、自有 C/header 与构建源码、zlib port 和规范参数。编译前清理 ambient 编译器、链接器、Make 与 CMake 初始化参数，显式固定 flags；保留正常 PATH 与代理环境。只在输入保持一致且三组 JS/WASM 完整生成后原子发布。每个身份拥有独立 `EM_CACHE`、CMake 缓存与进程生命周期，取消或编译失败不发布部分结果。

输出为忽略的 `runtime/image-codec/.local/build/<identity>/`，包含 `png.mjs/png.wasm`、`jpeg.mjs/jpeg.wasm`、`encoder.mjs/encoder.wasm`、上游许可及构建清单。清单记录输入身份、真实工具版本、产物大小及 SHA。SDK 官方 port 固定 zlib 1.3.1 及 SHA-512；已有归档可在导入边界验证后离线使用：

```sh
pnpm image-codecs:build --zlib-archive /absolute/path/zlib.tar.gz
```

`--archive` 转交 SDK 准备器，`--output` 和 `--cache-root` 分别指定输出根与构建缓存根。构建参数使用无 pthread/SAB、无内存文件系统、初始 16 MiB / 最大 32 MiB 的 WASM；这不是进程 RSS 上限。生成 JS 不提交，运行时从 `unknown` 校验真实具名 ABI，不生成未消费的声明文件或屏蔽类型检查。

## 顺序消费与真实回归

`decoder.ts` 的 `decodeImage({bytes,codecUrl,format,denominator?,signal?})` 返回单消费者 session。异步事件依次为 header、连续字节 chunk 和 terminal；每个 chunk 至多 64 KiB，消费者下一次拉取才推进，没有在运行时积存完整 raster。chunk 可以跨行，不能直接用作 Flutter tile。`completion` 在真正 close 后提供结果、错误阶段与计量；显式取消、signal abort 和消费者退出都驱动清理。加载等待可以立即取消，迟到实例不再接纳、迟到拒绝会被消费；底层动态导入/WASM 初始化本身仍不可中断，尚未取得实例时计量为 null、close 不冒充成功。取消只能发生在同步 C 调用之间；原始 WASM 实例同一时刻只有一个 lease，清理失败的实例不再复用。

首批能力明确为非隔行 RGBA8 PNG，以及 8-bit 单 scan 顺序 Huffman 灰度/RGB/YCbCr JPEG；PNG 仅分母1，JPEG 支持1/2/4。编码输入不超过8 MiB、C 请求 payload不超过16 MiB、条带不超过256行；宽不超过4096，PNG高不超过100000，JPEG高不超过65500。不支持的颜色、隔行或多 scan 输入明确拒绝，不沿用原型产品整图解码路径的更广范围。

普通工程回归使用小夹具，不下载或编译 SDK；真实验收另行运行，避免在 CI 隐式触发全工具链构建：

```sh
pnpm test:image-codecs
pnpm image-codecs:check --build runtime/image-codec/.local/build/<identity>
```

真实命令使用锁定的 Sharp 重新生成超16 Mi像素合成长图，PNG完整像素对照原始RGBA，JPEG对照Sharp重新解码结果；消费者增量校验完整流和首/中/末区域。另测同线程 pull 暂停窗口、取消、消费者退出、截尾、首版不支持格式、ABI长度与释放/peak重置。四幅长图分别记录 heap/payload；同线程背压不等同跨 Worker ACK。JPEG新一轮缩放只核尺寸及字节数，历史独立原生djpeg像素对照单独保留。参考图生成和Sharp完整解码内存不属于被测WASM计量；这里不报告进程/GPU峰值。报告只写忽略的 `.local`，不依赖临时探针目录。

2026-11-04，正式源码的两次同主机独立缓存构建及 19 项真实 WASM 回归已通过；四幅图的完整输出及首/中/末摘要一致，heap 均为 16 MiB。第二次构建使用无效 ambient flags，四份生成资产仍逐字节相同；输入身份与详细范围见[正式证据](../../docs/verification/long-image-codec.md#正式源码构建与-node-验收)。无 SDK 下载的工程回归共 53 项，覆盖工具链、builder 与运行库生命周期，已通过 `pnpm check`。

正式源码的 Node 回归不能代替新产物的浏览器、Native 内置执行、原 Source 图片链、Flutter、LOD/位置恢复或真实设备验收；材料和协议接线后仍需逐项完成这些门。

## 独立 Worker 与 PNG 条带

`client.ts` 的 `decodeImageTiles()` 消费插件处理后的受管 `Blob`；单个专用 module Worker 与 Source Worker 分开。输入在读取前限制为 8 MiB，PNG/JPEG decoder 顺序输出，独立 libspng encoder 将至多 256 行 RGBA 编为 PNG。每块传输至多 64 KiB，等待 ACK 后再发；下一条带由消费者下一次 pull 驱动。最大宽 4096、RGBA 条带 4 MiB、编码 PNG 8 MiB。两个 WASM 各自最多 32 MiB heap / 16 MiB C payload；合计上界不代表实际同时峰值或进程 RSS。

事件为 header、tile 与 terminal；tile 的 `sourceRect` 保留原图坐标，所有 tile 在真实 IEND/EOI 完成前都是 provisional。终态失败或取消必须作废该页已交付 tiles。消费者退出、AbortSignal、超时均取消；协作清理读真实 C 账本，超出 grace 则 terminate，强制终止的未取得计量为 null，不能当作已测 heap 归零。宿主将已验证模块 URL 的 `release()` 作为 `releaseModules` 传入，客户端在 Worker 终止后调用。

`prepareImageCodecAssets()` 通过正式 VerifiedLoader 验证 Worker、decoder/encoder 模块与两份 WASM 后才创建 Blob URL。已有 WASM 字节传入 Emscripten，不从相对 URL 回退下载。`MaterialCatalog.imageCodecs` 独立于 Source hostScripts/resources：Web 只交付一份共享 Static Assets；Native 由 `host.js` 内置所需字节和 resolver，公开 `window.karuyomiImageCodecs`，Source Worker 不预载 codec，Native 不请求远端材料。Native client 已 bundle，避免重复嵌入 Web client.js。当前只是运行库和材料接线，未改变产品 16 Mi 像素门。

真实浏览器验收工具使用正式 catalog、client、VerifiedLoader 和独立 Worker：

```sh
pnpm image-codecs:check-worker --output .local/image-codec-worker/acceptance
```

CLI 准备夹具和增量逐 tile Node 基准后提供 localhost URL；使用 Codex 内置浏览器点击运行，报告保存在同一忽略目录。工具检查四幅长图与高熵最大条带的全部 PNG SHA/几何、pull/ACK、取消、截尾和恢复，只保留首/中/末三幅预览；不会积存整图 raster。独立 Sharp 像素正确性由另行执行的 24 项 Node 门提供。通过页面关闭服务或 SIGINT 退出，服务还有有界存活期限。`--prepare-only` 只准备；可选 `--build <directory>` 校验并使用本地 builder 目录。

## 供工程构建使用的固定产物

`artifacts-lock.json` 固定三组模块、许可证、构建清单及来源身份。它是构建输入，归档属于独立运行时构建依赖；客户端扩展仍只从 Static Assets 下载。CI 不隐式编译 SDK，也不下载未验收的 Linux 工具链：

```sh
pnpm image-codecs:prepare-artifacts
# 离线导入同一归档
pnpm image-codecs:prepare-artifacts --archive /absolute/path/image-codecs.tar.gz
```

准备器校验有界归档 size/SHA、精确成员集合、逐成员 SHA、manifest 身份、自有构建输入和 Git index 的上游 pin，再原子安装到忽略缓存。复用也检查锁定成员；材料收集复用该次已验证结果。归档检查和 extractor 清理在真实进程终态后才释放 stage/lock，回归覆盖失败、取消及提前退出父进程的后代。

维护 C/builder/toolchain 输入或上游 pin 后必须重新构建、运行真实 Node 门，再生成新归档和锁：

```sh
pnpm image-codecs:package --build runtime/image-codec/.local/build/<identity> \
  --archive .local/image-codecs.tar.gz \
  --url https://github.com/Wybxc/karuyomi/releases/download/<dependency-tag>/image-codecs.tar.gz
```

发布构建依赖时，tag 必须指向包含实际构建源码的提交；核实公开下载与锁一致后才让分支 CI 使用。扩展 AOT 与该归档分开，不能复用旧冻结 checkpoint 作为当前 host 身份。

2026-11-04，正式 catalog/client/VerifiedLoader/Worker 在 Codex 内置 Chromium 156 通过 11 项验收；四幅长图与高熵条带共 590 个基础 tile 的 PNG 字节和几何匹配 Node 同产物基准，另测 ACK/pull、取消、截尾及恢复。所有会话记录 terminal → terminate → release，最终活动 Worker 为零；25 ms 无迟到消息观察不等于物理 heap 已回收。服务已正常关闭、端口释放。完整身份与范围见[正式 Worker 证据](../../docs/verification/long-image-codec.md)；Source/Reader/Native 产品接线和峰值仍按计划待验。
