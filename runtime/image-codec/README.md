# 图片 codec 构建依赖

当前提供官方 Emscripten SDK 准备器。PNG / JPEG 的 Node 与 Web 机制证据见[长图 codec 验证](../../docs/verification/long-image-codec.md)；正式 codec 源码、共享产物和阅读器接入仍按[长图计划](../../docs/plan/reader-image-decoding.md)推进。

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

`.emscripten` 明确指向该安装的 LLVM、Binaryen、项目 Node 和独立 `EM_CACHE`；准备器保留官方版本检查，不使用本机 Homebrew 编译器或执行 `emsdk.py`。可用 `--cache-root` 指定缓存根、`--python` 指定 Python。SDK 属于校验下载的构建依赖，不作为源码或未使用的 submodule 提交。后续 builder 所需 npm/声明生成依赖另由锁定流程准备，不在这里重写官方依赖。

中断准备会关闭 HTTP 流、终止所属子进程组并等待退出，删除临时安装并释放锁。回归使用临时小归档和本机 HTTP 服务，不下载大型 SDK：

```sh
pnpm test:image-codecs
```

准备器通过不表示已经生成产品 WASM，也不表示 Source、Flutter、Native、真机或进程/GPU 峰值验收完成。

## 本轮验证

2026-11-04，在 macOS arm64 上用已保存的 282,468,276 B 官方归档执行正式 CLI 离线安装，exit=0，耗时 19.51 s；随后不传 `--archive` 复用同一安装，exit=0，耗时 0.339 s，没有下载。实际版本为 Node 24.15.0、Python 3.15.2、Emscripten 5.0.7-git、Clang 23.0.0git、Binaryen 129，与锁一致。摘要保存在忽略的 `.local/image-codec-toolchain-acceptance/`。

19 项回归覆盖离线复用、归档大小与摘要错误、完成记录/身份/可执行文件不一致、HTTP 限额与取消、父进程退出后持有 stdio 的后代清理和主动取消。后两项实际完成清理，不只核对配置；结束后没有本轮准备器、夹具、临时安装或锁残留。Linux 官方归档和产品 codec 构建仍须分别验收。
