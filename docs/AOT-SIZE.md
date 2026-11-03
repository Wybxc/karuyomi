# 扩展 AOT 包体分析

2026-11-03，首次全量尚未启动。本次使用此前已完成的两个当前源码构建，只测现有字节的压缩和后处理，没有启动新的 AOT。原始中间报告留在 ignored `.local`，本页保留后续决策需要的数据。

优先做共享材料单独交付和传输压缩，再测宿主初始化是否引入无用依赖。TeaVM 当前已开启代码裁剪、混淆和均衡优化；把生成文件中的一段直接抽成共享 JavaScript 不能保证正确性。

## 已测量的体积

以下均为十进制 bytes；压缩是离线结果，生产 HTTP 压缩尚未验收。

| 样本 / 主 AOT JS       |      原始 |  gzip 9 | Brotli 5 | Brotli 11 |
| ---------------------- | --------: | ------: | -------: | --------: |
| MangaDraft 1.6.2       | 3,777,975 | 794,217 |  723,909 |   605,203 |
| Arknights Comics 1.6.2 | 1,824,293 | 588,794 |  540,377 |   458,913 |

两包来自 Keiyoushi 提交 `efa93f5a3537856fe830450bbe33f69d21d28167`。原始 JAR SHA-256 分别为 `033c74c396d6b001649911e6e428c88bd3253266732adfd02e47c9b5f6caa011`、`4cc8aed82a0250ee60dddcbe62fccead4090d9ad20a73df72e1c9b9c2d0818ea`，业务 JAR 未改写。对应 AOT 摘要为 `c1502b1cd5407a47b3e43c1501a105b2d4f7105ad496483a4d97f047c574e893`、`992ed3ad5db946bad2ddf03b548f9cf2775bfc33961c124054c0994d1ac9689d`。两包的实际 Chrome 156 Worker / IndexedDB 初始化通过，但未据此判定在线 Source 语义、图片或移动性能通过。

每包另外有完全相同的 6 项共享材料：5 个桥脚本共 45,891 bytes，Zstd WASM 为 251,806 bytes，合计 297,697 bytes（约 291 KiB）。这些文件分别压缩后合计 gzip 94,359 / Brotli 11 72,497 bytes。主 AOT 占当前整包的 92.70% / 85.97%，所以拆共享材料有明确收益，仍需继续分析主程序。

两个 `ResourceConfig` 均为空，没有内嵌扩展 assets 或 ICU 数据文件；不能把两包体积差异归因于 ICU 数据。依赖 JAR 在构建环境的大小也不等于最终 JS 大小，TeaVM 会做全程序可达性分析与裁剪。

## 优先采用的交付调整

1. **共享材料只交付一份。** Web 在 `/runtime/materials/` 按摘要发布静态资源；Native 将相同材料随应用打包，由明确的 material 版本与摘要校验命中。每包清单声明所需材料，缺失或版本不匹配时明确失败。扩展 AOT 继续按版本发布到 GitHub Release，个人 API 和扩展私有交付仍经 Access。
2. **区分构建依赖。** `runtime-materials.tar.gz` 中的 JAR、材料锁等仅供构建，不能作为应用安装依赖；Maven 与 Android SDK 同理。实际客户端只需生成的 AOT、桥脚本和用到的 WASM 等资源。
3. **启用可验证的传输压缩。** Web 的 JS / WASM 可使用 HTTP gzip / Brotli；GitHub Release 的原始二进制资产不能假定会自动获得相同压缩，需设计带编码说明的压缩分发格式。编码后的长度/摘要与解码后的 canonical 长度/摘要分别记录；解码限额、最终校验、缓存与 Range 语义保持明确。R2 可继续保存 canonical 原文，通过 HTTP 层压缩完整响应。

当前 R2 已按 SHA 去重，共享交付的主要收益是减少每包发布重复、客户端重复获取，以及清晰的 Web / Native 资源边界。两个样本的 Release 资产合计可从 6,197,662 降为 5,899,965 bytes（减少 4.80%）。现有客户端也可能通过 ETag 得到 304，因此不能把全部原始字节当成每次必然节省的流量。若 1,448 包都包含同一套共享材料，按包重复发布会产生约 431 MB 原始资产；保留一份可避免约 430.8 MB 的重复。该数字是按相同材料的理论累计，不是当前实占或每个用户的下载量。

Cloudflare 的实际压缩受 MIME、状态码、浏览器协商、套餐与规则影响；完整响应和 Range 响应需分别验收。不能将上述 Brotli 11 离线值写成生产下载量。依据：[官方压缩说明](https://developers.cloudflare.com/speed/optimization/content/compression/)和[静态资源说明](https://developers.cloudflare.com/workers/static-assets/)。

## 主 AOT 还可以从哪里减小

### 宿主初始化的依赖根

`TeaHost.init` 无条件注册 `ProtoBuf.Default` 和配置过的 kotlinx `Json`，会把对应初始化链变成可达代码。两个原业务 JAR 均没有 protobuf 类引用，实际业务 TypeMap 引用只有 Json；当前生成的 TypeMap 还包含 9 项来自依赖材料的历史宿主类型，其中包括 ProtoBuf。这是值得优先验证的多余可达根。

可研究根据每包实际字节码与生成的 TypeMap 安装需要的服务，并收窄类型注册，让 TeaVM 裁剪不用的 codec。收益尚未测量；需要包含 JSON、ProtoBuf 和多 Source Factory 的样本验证，不能只凭文本搜索删掉依赖或影响原 Source 行为。

反射策略已经限定到明确字段、构造器和 `JavascriptInterface` 方法，宿主 JSON DTO 使用显式读写；当前没有开启全库反射保留。后续应核对统计中的异常、线程、正则、集合、codec 和元数据占比，按实际依赖链处理。

### 编译选项与统计

`java/pom.xml` 当前为 `ADVANCED`、`minifying=true`、生产 source maps 关闭。固定 TeaVM 0.16.0 源码中的映射是 `NONE → SIMPLE`、`BALANCED → ADVANCED`、`AGGRESSIVE → FULL`，因此当前已处于官方 JS 默认的均衡档。不能把当前误判为尚未开优化，或把 `ADVANCED` 误解为激进档。

`SIMPLE` 跳过内联，可作为后续少量样本的体积/启动/运行性能对照，收益与兼容性均待测。`FULL` 允许更大内联预算，不能预设它会缩小包体。下一次样本 AOT 应通过 `MAVEN_OPTS` 启用 JVM 属性 `-Dteavm.js.stats=true`；`JavaScriptTarget.printStats` 原生输出总量、元数据、字符串池和各 Java 包的代码大小，无需修改编译器。这些统计实际按 UTF-16 源码偏移计数，用于归因与相对比较；交付大小继续以 UTF-8 文件字节及压缩结果为准。依据：[官方 Gradle 选项](https://teavm.org/docs/tooling/gradle.html)、[Maven 选项](https://teavm.org/docs/tooling/maven.html)，以及固定子模块的 `TeaVMTask.java`、`TeaVM.java`、`JavaScriptTarget.java`。

### 提取公共常量数据

现有两包经 AST 分析有 644 段长度至少 512 字符的完全相同字符串；每包内部均为唯一值，语义 UTF-16 内容和排列也一致。它们占原 JS 字面量源码 402,863 bytes。将这些 primitive string 表达式替换为公共只读字典引用，可独立于 Java 类 ABI 研究，具体库归属仍需进一步统计。

离线模拟的静态字典为 400,846 bytes，gzip 165,776 / Brotli 11 118,202 bytes；改写后的两个 AOT Brotli 分别为 489,809、344,141 bytes。两包共用一份字典时总量从 1,064,116 降至 952,152 bytes，减少 111,964 bytes（约 10.52%）。首包冷加载加字典会略增约 2.8–3.4 KB；已缓存字典后再获取另一扩展才体现复用收益。这里只计算主 AOT 与该字典，原有 6 项共享桥/WASM 未计入。

这只是 AST 可解析与压缩模拟，没有执行改写程序。正式实现需生成无绑定冲突的引用，跳过属性键、directive、import/export 等语法位置，保留 UTF-16 字符串语义，并在执行 AOT 前校验、加载固定摘要的字典。字典版本要进入输入身份和新 buildId；Web 静态缓存与 Native 内置可复用，跨 Worker 不代表共享 JS 堆。该方向比拆完整 Java 运行时更独立，但仍需实际 Source 回归后才能采用。

### 生成后再次 minify

对现有输出使用 esbuild `minify:true`、`target:es2022`、`legalComments:none` 测量：

| 样本             | 后处理原始 JS | 原始减少 | 后处理 Brotli 11 | 压缩后额外减少 |
| ---------------- | ------------: | -------: | ---------------: | -------------: |
| MangaDraft       |     3,495,679 |    7.47% |          586,558 |          3.08% |
| Arknights Comics |     1,719,795 |    5.73% |          438,156 |          4.52% |

这是已测的字节收益，不是已验收的运行优化。后处理版本尚未做真实 Worker/网络回归；全局导出、异步恢复、异常与许可证必须保留。压缩后的额外收益有限，优先级低于正确的共享交付和传输压缩。

### 共享 TeaVM 核心代码

0.16.0 的 JavaScript backend 在全程序分析后裁剪运行时，再按当前程序的引用频率给符号命名，并一起写出闭包、类声明与元数据。不同包的裁剪集合、别名和类引用不同，不能按文件前缀或文本相似度抽取公共段。当前没有使用一个受支持的独立 JS 类库链接 ABI。

真正拆成共享 Java/Kotlin 库加小扩展，需要编译器级稳定符号、元数据、虚调用、异常与 fiber 链接设计，成本和兼容风险明显高于交付层去重。Wasm GC 的独立 loader/runtime 属于另一 backend，不能直接套用到当前 JS 宿主。该方向暂不阻塞首次全量。依据：[TeaVM 全程序优化说明](https://teavm.org/docs/intro/overview.html)及固定源码 `JavaScriptTarget.emit` / `RuntimeRenderer.removeUnusedParts`。

## 首次全量前的顺序

先调整共享材料交付和压缩契约；随后只用少量代表包开启包级体积统计，比较服务安装裁剪、当前 `ADVANCED` 与 `SIMPLE`，必要时再评估后处理。保留原业务 JAR，验证实际 Source ID、六项操作边界、网络/缓存/取消及压缩后完整性。选定策略后固定新的 host 输入身份，再从本地启动可断点续传的首次全量，CI 继续只跟随增量。
