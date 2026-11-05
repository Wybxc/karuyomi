# 图片 codec 候选库

这里保留 PNG/JPEG 解码、PNG 编码的 C 适配、严格 TypeScript 顺序接口、独立 Worker 和可复现工具链，**仅作为显式验证的分片候选，不进入默认构建或 Web/Native 产品打包**。当前 Reader 直接使用 Flutter/平台解码，图片识别、尺寸、方向、预算与缓存属于 UI；Source host 只交付处理后的编码字节，不调用本库或选择分片。

现有证据证明部分格式可顺序生成 PNG 条带并执行局部限额，没有同条件真机性能依据支持将其设为默认。先建立直接解码基线，再比较首个可见 frame、跳转、滚动、CPU、峰值 RSS/GPU；采用门槛见[解码设计](../../docs/design/reader-image-decoding.md)。Reader 分片、LOD、方向映射和 Native 消费均未接入。

`client.ts/worker.ts` 提供独立 codec 会话；`assets.ts`、`tile-store.ts`、`errors.ts` 从原宿主内化到客户端库，分别负责材料准备、窗口与租约、局部错误。它们不依赖 Source host，原宿主页控制协议已删除。材料准备由调用方显式提供目录和 loader；默认应用不下载、内嵌或发布这些候选资源。

历史构建、Node 像素与独立浏览器 Worker 的原始身份、素材及限制保留于[codec 验证](../../docs/verification/long-image-codec.md)，不作为当前 Reader 或 Native 验收。下列命令专供维护与复验候选，不是正常产品构建的前置步骤。

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

## 工具链历史证据

macOS arm64 官方归档已按锁文件完成真实离线安装与复用；归档验证、HTTP 限额、取消、进程组与锁清理均有独立回归。原始输入身份和限制见[codec 验证](../../docs/verification/long-image-codec.md)，详细临时摘要留在忽略目录。Linux 官方 SDK 仍待实际执行验收；不能用历史 Linux 材料装配结果代替它。

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

首批能力明确为非隔行 RGBA8 PNG，以及 8-bit 单 scan 顺序 Huffman 灰度/RGB/YCbCr JPEG；PNG 仅分母1，JPEG 支持1/2/4。编码输入不超过8 MiB、C 请求 payload不超过16 MiB、条带不超过256行；宽不超过4096，PNG高不超过100000，JPEG高不超过65500。不支持的颜色、隔行或多 scan 输入明确拒绝，这些限制仅属于候选，不筛选 Source 正文或改变普通图直接解码能力。

普通工程回归使用小夹具，不下载或编译 SDK；真实验收另行运行，避免在 CI 隐式触发全工具链构建：

```sh
pnpm test:image-codecs
pnpm image-codecs:check --build runtime/image-codec/.local/build/<identity>
```

真实命令使用锁定的 Sharp 重新生成超16 Mi像素合成长图，PNG完整像素对照原始RGBA，JPEG对照Sharp重新解码结果；消费者增量校验完整流和首/中/末区域。另测同线程 pull 暂停窗口、取消、消费者退出、截尾、首版不支持格式、ABI长度与释放/peak重置。四幅长图分别记录 heap/payload；同线程背压不等同跨 Worker ACK。JPEG新一轮缩放只核尺寸及字节数，历史独立原生djpeg像素对照单独保留。参考图生成和Sharp完整解码内存不属于被测WASM计量；这里不报告进程/GPU峰值。报告只写忽略的 `.local`，不依赖临时探针目录。

同主机独立缓存构建、真实 WASM 回归及不依赖 SDK 下载的工程回归保留于[正式源码证据](../../docs/verification/long-image-codec.md#正式源码构建与-node-验收)。它们不能代替新产物的浏览器、Native 执行、原 Source 图片链、Flutter 或设备性能对照。

## 独立 Worker 与 PNG 条带

`client.ts` 的 `decodeImageTiles()` 消费插件处理后的受管 `Blob`；单个专用 module Worker 与 Source Worker 分开。输入在读取前限制为 8 MiB，PNG/JPEG decoder 顺序输出，独立 libspng encoder 将至多 256 行 RGBA 编为 PNG。每块传输至多 64 KiB，等待 ACK 后再发；下一条带由消费者下一次 pull 驱动。最大宽 4096、RGBA 条带 4 MiB、编码 PNG 8 MiB。两个 WASM 各自最多 32 MiB heap / 16 MiB C payload；合计上界不代表实际同时峰值或进程 RSS。

事件为 header、tile 与 terminal；tile 的 `sourceRect` 保留原图坐标，所有 tile 在真实 IEND/EOI 完成前都是 provisional。终态失败或取消必须作废该页已交付 tiles。消费者退出、AbortSignal、超时均取消；协作清理读真实 C 账本，超出 grace 则 terminate，强制终止的未取得计量为 null，不能当作已测 heap 归零。调用方将已验证模块 URL 的 `release()` 作为 `releaseModules` 传入，在 Worker 终止后释放。

`assets.ts` 的 `prepareImageCodecAssets()` 使用调用方提供的结构化 loader，验证 Worker、decoder/encoder 模块与两份 WASM 后才创建 Blob URL。已有 WASM 字节传入 Emscripten，不从相对 URL 回退下载。`tile-store.ts` 管理单活动会话、有界扫尾、窗口 PNG 缓存与显示 lease，调用方负责 UI 图片识别、显示 URL/文件和 cache 引用。它不是 Source host 的页控制服务。

此前 Web catalog、Native host 内嵌以及独立 `assets/image-codec/` 目录的装配均为已撤回的中间接线。候选退出默认材料与应用打包；若后续性能证据支持采用，再明确接入共享 Web Static Assets 或 Native 随应用资源，不能通过 Source host 隐式消费。

候选 JavaScript 通过独立声明式 Vite 配置生成，不进入默认产品材料：

```sh
pnpm --filter @karuyomi/runtime-host build:image-codecs
```

输出为 `packages/runtime-host/.local/image-codecs/{client.js,worker.js}`。候选 JavaScript 与下述 portable C/C++ 产物独立准备、验证，不合并到产品的 `materials.json`，也不存在材料收集 API。

原 `image-codecs:check-worker` 自定义浏览器 runner 已于 2026-11-05 退役。历史长图 PNG 摘要、几何、ACK/pull、取消、截尾及恢复结果仍保留在[codec 验证](../../docs/verification/long-image-codec.md)，其命令只适用于原固定 checkout。当前官方 Browser 桥测试不等价于完整候选长图验收；候选新产物的浏览器、Native 和直接解码性能对照仍待单独执行。当前构建与测试入口见 [Vite 计划](../../docs/plan/vite-build-and-testing.md)。

## 供显式候选验证使用的固定产物

`artifacts-lock.json` 固定三组模块、许可证、构建清单及来源身份。它是候选的固定构建输入，默认产品构建不消费归档。显式验证时也不隐式编译 SDK 或下载未验收的 Linux 工具链；扩展 Static Assets 分发规则不变：

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

发布候选构建依赖时，tag 必须指向包含实际构建源码的提交，核实公开下载与锁一致；这不使默认分支构建自动消费候选。扩展 AOT 与该归档分开，不能复用旧冻结 checkpoint 作为当前 host 身份。

既有独立浏览器验收使用当时固定的 catalog/client/loader/Worker，在 Codex 内置 Chromium 156 对照 Node 同产物基准检查 PNG 字节、几何、背压、取消、截尾及恢复。完整身份与范围见[正式 Worker 历史证据](../../docs/verification/long-image-codec.md)；Worker 终止观察不等于物理 heap 归零，更不提供直接解码对照或真实设备峰值。候选目录迁移后的工程测试不自动继承旧浏览器环境的结论。
