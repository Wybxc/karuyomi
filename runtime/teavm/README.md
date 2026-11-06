# TeaVM 运行时

本目录维护项目的 Java 兼容层、Source RPC 和浏览器桥。研究交付 release9 是历史起点；项目源码在这里继续开发，不受旧逐文件冻结清单约束。真正第三方源码通过根目录 `vendor/` submodules 固定，上游改动通过明确补丁物化。

- `java/`：正式 Java 源码、JCL/Android/库 ABI 适配、Maven 配置与服务注册。`hostInvoke` 使用完整 DTO、分页与显式漫画/章节引用；各宿主 entry 接收 requestId、generation 和独立 token，将 HTTP 与异步回调绑定到发起 RPC。
- `patches/teavm/`：针对固定 TeaVM 上游的兼容补丁；[物化工具](../../tools/teavm/upstream-sources.ts) 校验原始和输出摘要，只写隔离构建目录。
- `bridge/`：严格 TypeScript 产品浏览器桥。Zstd 只读取已校验的共享材料映射，Web 使用静态字节，Native 使用应用内字节。
- `toolchain-lock.json`、`toolchain/`：工具版本、下载摘要、runtime seed 材料与 Android SDK 元数据。`toolchain/android-sdk-license` 是复制到 SDK `licenses/` 的协议接受摘要记录；协议正文在相邻 XML 元数据中。
- [来源与许可](NOTICE.md)、`licenses/`：ABI 适配、上游来源与必须保留的许可说明。
- `.local/`：被忽略的依赖材料、工具链、缓存、隔离构建副本、交付和历史研究归档。不能整体复制到 Static Assets；正式快照只选取当前清单与 gzip bundle。

## 正式构建

```sh
git submodule update --init --recursive
node scripts/prepare-runtime.ts --android
node tools/teavm/check-dto.ts
pnpm --filter @karuyomi/runtime-host build:materials
node scripts/build-extension.ts --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
```

完整发现、增量身份、首次本地批量构建与 latest-only 快照部署流程见 [扩展静态分发](../../docs/EXTENSIONS.md)。依赖材料通过固定摘要的 runtime seed 获取，公开工具链按锁定 URL 和摘要下载；不依赖本机研究 ZIP。seed 是独立构建依赖，不下发客户端，也不受扩展停止 Release 发布的决定影响。

构建器复制正式 Java 到隔离目录，从固定 TeaVM submodule 应用补丁，再生成 TypeMap / ResourceConfig。随后 [正式 AOT 工具](../../tools/teavm/build.ts) 裁剪被兼容层替换的依赖类、运行宿主字节码适配并编译；原扩展 JAR 不修改。生成注册表、裁剪 JAR、Maven 输出和运行日志均留在被忽略的工作目录。

Source 的默认网络配置由 owned `eu/kanade/tachiyomi/network/NetworkHelper.java` 维护，配置来源为固定 Suwayomi-Server submodule 的 `NetworkHelper.kt`，保留 MPL-2.0 来源头。它保留既有 Cookie、UA 与拦截器，在稳定 Context cache 目录下接入 5 MiB Cache；构建时移除 seed 同名类。锁定 seed 原类默认 Cache 为 null 的复现、配置门与真实 Source 待验边界见 [Source 网络缓存配置](../../docs/verification/source-network-cache.md)。图片原有 cacheless 语义不变。

每包输出 `manifest.json`、唯一 `artifacts/<canonicalSHA>.gz`、`provenance.json` 与 `build-result.json`。清单符合共享 `BuildManifest`，包含原包、版本、全部 Source ID 字符串、协议/ABI/bridge/storage 版本，以及 gzip 编码与 canonical 两个字节域的大小和摘要。TeaVM 同输入重建仍可能产生不同 JS 字节；记录的是实际输出，不承诺逐字节确定性。

所有客户端以公开 `/extensions/index.json` 为准，从 Static Assets 加载当前清单和 gzip；共享材料由 Web 静态资源 / Native 内置提供。扩展不再上传 GitHub Release 或 R2，不由 API 转发正文。D1 只登记 Source HTTP 网络策略，动态 `/api` 仍受 Access 保护。编译成功保持 `compiled_unverified`，不能宣称浏览器或在线 Source 兼容。

## 运行与回归

当前 Java 边界支持 `popular`、`latest`、`search`、`details`、`chapters`、`pages`、`getFilters`、`getPreferences` 与 `editPreference`；typed filters 保留原具体子类并按完整叶状态应用，描述使用有界快照和显式保留引用，详见 [Source 筛选](../../docs/design/source-filters.md)。Source preferences 保留原控件和 listener，构造前注入确认值、编辑后排空重读，并经 D1 确认和容器重开生效，详见 [Source 设置](../../docs/design/source-preferences.md)。当前合同为 `hostAbi=karuyomi-source-host-v6`、`protocolVersion=2`、HTTP `bridgeVersion=2`；旧 ABI 扩展需要重新构建，不提供兼容回退。原 Source 的 `enqueue` 在首次执行时绑定 RPC owner，主结果返回前有界等待回调结束；无法确认收尾时丢弃运行时，不把迟到结果归入下一个 RPC。

协程使用工具链锁定的官方 `kotlinx-coroutines-core-jvm-1.11.0.jar`，由 TeaVM 一起编译；自研 Green Job 和四个同名 kotlinx 覆盖已删除。`HostCoroutines` 与构建副本的精确生命周期接点只管理 operation owner / lease，Job、builder、取消和 dispatcher 保留官方实现；TeaHost 提前关闭 TeaVM 下不可用的可选堆栈恢复。隔离 Kotlin 语义与归属分项、正式 JVM oracle、HTTP 子任务取消缺口和真实 Source 的验收分别见[计划](../../docs/plan/coroutine-runtime.md)及[验证](../../docs/verification/coroutine-runtime.md)。

正式图片通道保留原 Java Page 与 Source 图片处理链，经有界二进制通道交付不透明编码字节。Web 使用受管 Blob URL，Android/iOS 交接受管临时文件，再由同一 Flutter 图片入口识别、解码和显示；宿主不读取 MIME、尺寸或方向，不预解码。取消、generation、字节预算和释放确认分别由对应 owner 落实，详见[图片资源合同](../../docs/IMAGE-RESOURCES.md)及 [Native 文件合同](../../docs/NATIVE-IMAGE-FILES.md)。

当前工程回归使用声明式 Vite 预构建、Cloudflare 官方 Workers Vitest/Test Harness，以及官方 Vitest Browser Preview：

```sh
pnpm test
BROWSER=none pnpm test:browser
```

浏览器测试用 Codex 内置浏览器打开 Preview 报告的 URL。旧 Source HTTP/HTTPS 服务、自定义 socket/HTTP 探针和浏览器 runner 已退役；旧命令仅适用于记录中的历史 checkout。当前官方 fixture 覆盖不等于指定 AOT 的 `hostInit/hostLoad`、真实漫画资料操作或 Source 图片处理验收，也尚未替代 Native 完整在线门。构建与覆盖见 [Vite 计划](../../docs/plan/vite-build-and-testing.md)。

历史 v4 三源分项见 [v4 运行记录](../../docs/verification/v4-source-runtime.md)；退役入口、上游挑战及搜索行为见 [历史集成说明](../../apps/api/test/source-metadata-probe.md)与[实测摘要](../../docs/verification/runtime-evidence.md)。原日期、材料与结果保留，测试签名仍不替代生产 Access，浏览器分项不替代 Native、真机或完整阅读验收。

独立字节、回调与 iOS 研究工程和旧导入/构建脚本只保留在被忽略的 `.local/research/`。必要基线摘要、关键门槛与已知失败已归并到 [验证要点](../../docs/verification/runtime-evidence.md)，其中 R2/v1 记录属于历史机制证据。当前 Java、Worker 和 API 只维护 HTTP v2，已有分帧、Okio 按需消费及历史受控 workerd 网络取消证据；当前官方 Workers 回归的取消覆盖使用模拟 upstream，不证明真实 TCP reset；真实 Source/Cache 同版对照、图片资源、移动端内存和产品实测仍按 [HTTP 桥](../../docs/HTTP-BRIDGE.md) 与 [VERIFICATION](../../docs/VERIFICATION.md) 单独验收，不能据机制测试宣称 P0-B 完成。
