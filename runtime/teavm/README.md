# TeaVM release9 工作副本

本目录保留经过固定 SHA-256 校验的 release9 源码与少量产品适配。原型 ZIP、历史候选、原型诊断服务、HTTP fixtures、批量 AOT 产物均不进入版本控制。

- `upstream/`：221 份最终 Java / 兼容层 / 原构建工具 / 参考 ABI 源码 / 许可证，字节只读；逐文件摘要见 `upstream-manifest.json`。
- `java/`：产品覆盖层，新增 `hostInvoke(sourceId, operation, argsJson)`，完整 DTO、分页与显式漫画/章节引用。
- `bridge/`：当前工作桥，不包含旧测试回调桥。Zstd 只读取已校验资源映射，不再引用原型 `/assets/`。
- `verification/`：真实浏览器、字节边界和 iOS 机制验证的小型摘要；它们不表示产品验收完成。
- `.local/`：被忽略的原 JAR、第三方依赖、Maven 缓存、隔离构建副本、私有产物与 `research/` 临时研究归档。不能复制整个目录到 Static Assets。

冻结源指纹为 `06b2e8f9b560f41c60ce6779ee320ac50523780bf5dd24c08dc01a65010fe299`；工具同时固定 `source-snapshots/release9/manifest.json` 和 `V2-FREEZE.json` 的 SHA-256。TeaVM 固定 0.16.0 JS backend，Maven 固定 3.9.11，当前验证 JDK 为 Oracle GraalVM 25.0.4。上游库版本与转换输入均来自原交付，扩展 JAR 不修改。

```sh
python3 scripts/import-teavm.py /path/to/teavm-compatibility-v2.zip --package mangadraft
python3 tools/teavm/check-dto.py
python3 scripts/build-teavm.py mangadraft
```

导入工具拒绝未知冻结清单、文件摘要不符和覆盖已修改文件。只导入源码时加 `--sources-only`；为其他原版包重复指定 `--package`。构建时复制源到 `.local/work/<package>-product`，叠加产品覆盖层，并重新核验原 JAR。原构建工具生成的 TypeMap / ResourceConfig 只改该隔离工作副本。`--baseline` 另建冻结文本桥开发对照，证据写入 `.local/baselines/`，不生成可安装产品清单，也不是产品运行时回退。

构建结果位于 `.local/manifests/<buildId>.json`；清单符合共享 `BuildManifest` 协议，私有文件按 SHA-256 放在 `.local/artifacts/`。清单包含原包、版本、Source ID 字符串、协议/ABI/bridge/storage 版本、产物大小和 hash；buildId 摘要覆盖全部清单内容。相邻 `.evidence.json` 另存源文件摘要、JDK、原输入 APK/JAR 摘要及构建耗时。`upstream-materials.json` 固定原依赖与 WASM 摘要，构建前逐项校验。TeaVM 同输入重建仍可能产生不同 JS 字节；记录的是每次实际输出，不承诺逐字节确定性。清单只是构建输出，安装/发布仍需受保护的 D1 注册与 R2 交付。

当前支持 `popular`、`latest`、`search`、`details`、`chapters`、`pages` 的 Java 边界；非默认筛选显式拒绝，尚未提供 filters/preferences 映射。原图片 `hash/采样` 摘要没有作为产品图片结果保留，图片需另接可取消/释放的二进制资源通道。

正式浏览器/网络集成回归使用产品 JS 与真实 workerd/D1/R2，并在隔离测试入口验证 RS256 测试签名：

```sh
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.mjs runtime/teavm/.local/manifests/<buildId>.json
```

打开脚本输出的 localhost 页面运行。它核对清单/hash 与实际 `hostInit/hostLoad`，再尝试真实漫画资料操作；范围、上游 Human Verification 阻断和原 Source 搜索行为见 [集成回归说明](../../apps/api/test/source-metadata-probe.md) 与 [实测摘要](verification/mangadraft-live-metadata.json)。测试签名不替代生产 Access。

独立字节、回调与 iOS 机制研究只保留 [验证摘要](../../docs/VERIFICATION.md)。临时工程与构建脚本已移入本机被忽略的 `.local/research/`，不作为产品源码或正式发布工具入库。历史摘要中的原始 harness 摘要用于溯源，不代表仓库继续携带这些临时工程。

本地 Chromium 探针通过不等于 P0-B 完成。v2 分帧、HTTP/Okio 按需消费、真实网络取消、缓冲峰值、图片资源与 iOS 实测仍待实施。

保留 `upstream/NOTICE.md` 和 `upstream/licenses/`。其中原研究报告的本机路径、CheerpJ 对照和测试证据属于来源记录，不代表本项目携带或启用这些功能。
