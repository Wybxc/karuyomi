# TeaVM 运行时

本目录维护项目的 Java 兼容层、Source RPC 和浏览器桥。研究交付 release9 是历史起点；项目源码在这里继续开发，不受旧逐文件冻结清单约束。真正第三方源码通过根目录 `vendor/` submodules 固定，上游改动通过明确补丁物化。

- `java/`：正式 Java 源码、JCL/Android/库 ABI 适配、Maven 配置与服务注册。`hostInvoke(sourceId, operation, argsJson)` 使用完整 DTO、分页与显式漫画/章节引用。
- `patches/teavm/`：针对固定 TeaVM 上游的兼容补丁；[物化工具](../../tools/teavm/upstream_sources.py) 校验原始和输出摘要，只写隔离构建目录。
- `bridge/`：产品浏览器桥。Zstd 只读取已校验的私有资源映射。
- `toolchain-lock.json`、`toolchain/`：工具版本、下载摘要、runtime seed 材料与 Android SDK 元数据。
- [来源与许可](NOTICE.md)、`licenses/`：ABI 适配、上游来源与必须保留的许可说明。
- `.local/`：被忽略的依赖材料、工具链、缓存、隔离构建副本、私有产物和历史研究归档。不能复制到 Static Assets。

## 正式构建

```sh
git submodule update --init --recursive
python3 scripts/prepare-runtime.py --android
python3 tools/teavm/check-dto.py
python3 scripts/build-extension.py --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
```

完整发现、增量身份、首次本地批量构建与不可变发布流程见 [扩展发布说明](../../docs/EXTENSIONS.md)。依赖材料通过固定摘要的私有 runtime seed 获取，公开工具链按锁定 URL 和摘要下载；不依赖本机研究 ZIP。

构建器复制正式 Java 到隔离目录，从固定 TeaVM submodule 应用补丁，再生成 TypeMap / ResourceConfig。随后 [正式 AOT 工具](../../tools/teavm/build.py) 裁剪被兼容层替换的依赖类、运行宿主字节码适配并编译；原扩展 JAR 不修改。生成注册表、裁剪 JAR、Maven 输出和运行日志均留在被忽略的工作目录。

每包输出 `manifest.json`、`artifacts/<sha256>`、`provenance.json` 与 `build-result.json`。清单符合共享 `BuildManifest`，包含原包、版本、全部 Source ID 字符串、协议/ABI/bridge/storage 版本、产物大小和摘要。TeaVM 同输入重建仍可能产生不同 JS 字节；记录的是实际输出，不承诺逐字节确定性。编译成功不能宣称浏览器或在线 Source 兼容；安装仍需受保护的 D1 注册和私有 R2 交付。

## 运行与回归

当前 Java 边界支持 `popular`、`latest`、`search`、`details`、`chapters`、`pages`；非默认筛选显式拒绝，filters/preferences 映射仍待实现。图片需另接可取消、释放的二进制资源通道，当前产品明确不支持。

正式浏览器/网络集成回归使用产品 JS 与真实 workerd/D1/R2，并在隔离测试入口验证 RS256 测试签名：

```sh
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

打开脚本输出的 localhost 页面运行。它核对清单/hash 与实际 `hostInit/hostLoad`，再尝试真实漫画资料操作；范围、上游 Human Verification 阻断和原 Source 搜索行为见 [集成回归说明](../../apps/api/test/source-metadata-probe.md) 与 [实测摘要](../../docs/verification/runtime-evidence.md)。测试签名不替代生产 Access。

独立字节、回调与 iOS 研究工程和旧导入/构建脚本只保留在被忽略的 `.local/research/`。必要基线摘要、关键门槛与已知失败已归并到 [验证要点](../../docs/verification/runtime-evidence.md)。本地浏览器机制通过不等于 P0-B 完成；v2 分帧、HTTP/Okio 按需消费、真实网络取消、缓冲峰值、图片资源与 iOS 产品实测仍待实施。
