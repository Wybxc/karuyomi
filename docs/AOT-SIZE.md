# 扩展 AOT 包体分析

2026-11-03，首次发布采用的方案已确定：共享桥/WASM 在 Web 静态交付、Native 随应用打包，每包 Release 仅发布确定性 gzip 编码的 AOT；保留 TeaVM `ADVANCED` 与现有宿主服务。以下包括现有产物测量和少量真实 A/B 编译，原始中间报告留在 ignored `.local`。

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
3. **启用可验证的传输压缩。** 新 source-aot Release 使用 `<canonicalSHA>.gz` 和 `artifact-encodings.json`，gzip level 9、固定时间戳 0。编码后的长度/摘要与解码后的 canonical 长度/摘要分别记录；恢复时限制解码长度，拒绝截断、尾随内容或多个 gzip stream，最终再次校验原文。旧 raw 资产继续可读且不会覆盖。R2 保存 canonical 原文，Range 仍以原文为准；生产 HTTP 压缩另行验收。

两份真实 AOT 经正式发布器编码、模拟下载与恢复后，原始 SHA/字节完全一致：MangaDraft 3,777,975 → 791,368 bytes，Arknights Comics 1,824,293 → 583,749 bytes。每包只剩 1 个私有 AOT 和 6 个静态材料引用；这项 roundtrip 是本地输送验证，不是 GitHub 实际发布或运行兼容证据。与原来每包重复携带 297,697 bytes 材料相比，两包资产合计从 6,197,662 降至 1,375,117 bytes（不含小型清单、另行交付的共享材料）。

正式输入固定到 `8dc22e3` 后，已重新编译并实际发布首两包；从 GitHub 下载并按正式恢复器核验结果如下。每包 7 个 Release 资产，包含一个 gzip AOT 和六个清单/溯源文件；压缩与 canonical 双摘要、长度均通过，`runtimeReady=false` / `compiled_unverified`。

| 正式 Release                                                                                                                             | canonical bytes | gzip bytes |   减少 |
| ---------------------------------------------------------------------------------------------------------------------------------------- | --------------: | ---------: | -----: |
| [MangaDraft 1.6.2](https://github.com/Wybxc/karuyomi/releases/tag/ext-all.mangadraft-v106002-364cdedb6cd1e1c7a4aacd99aa2eb05c)           |       3,777,971 |    791,388 | 79.05% |
| [Arknights Comics 1.6.2](https://github.com/Wybxc/karuyomi/releases/tag/ext-en.arknightscomics-v106002-dd22d6bbf6f048ad02515caa96989397) |       1,824,293 |    583,745 | 68.00% |

当前 6 份共享材料合计 297,946 bytes（cache/file 新增 Native 命名空间适配），Web 另保留两份旧桥以支持历史清单；材料实际字节不会进入每个 Release。正式发布保留原业务 JAR；重新编译结果与此前分析样本分别记录，不以分析样本的 SHA 代替正式产物。

当前 R2 已按 SHA 去重，共享交付的主要收益是减少每包发布重复、客户端重复获取，以及清晰的 Web / Native 资源边界。两个样本的 Release 资产合计可从 6,197,662 降为 5,899,965 bytes（减少 4.80%）。现有客户端也可能通过 ETag 得到 304，因此不能把全部原始字节当成每次必然节省的流量。若 1,448 包都包含同一套共享材料，按包重复发布会产生约 431 MB 原始资产；保留一份可避免约 430.8 MB 的重复。该数字是按相同材料的理论累计，不是当前实占或每个用户的下载量。

Cloudflare 的实际压缩受 MIME、状态码、浏览器协商、套餐与规则影响；完整响应和 Range 响应需分别验收。不能将上述 Brotli 11 离线值写成生产下载量。依据：[官方压缩说明](https://developers.cloudflare.com/speed/optimization/content/compression/)和[静态资源说明](https://developers.cloudflare.com/workers/static-assets/)。

## 主 AOT 还可以从哪里减小

### 宿主初始化的依赖根

`TeaHost.init` 无条件注册 `ProtoBuf.Default` 和配置过的 kotlinx `Json`，会把对应初始化链变成可达代码。两个原业务 JAR 均没有 protobuf 类引用，实际业务 TypeMap 引用只有 Json；当前生成的 TypeMap 还包含 9 项来自依赖材料的历史宿主类型，其中包括 ProtoBuf。这是值得优先验证的多余可达根。

已做真实 A/B 编译：只保留业务 TypeMap 所需的 Json，并移除无用 ProtoBuf 初始化。MangaDraft gzip / Brotli 仅减少 538 / 753 bytes，Arknights Comics 仅减少 298 / 275 bytes，约为压缩体积的 0.06%–0.12%。收益不足以支持增加逐包服务扫描和兼容分支，因此首批不采用，保留原 JAR 和现有初始化。

反射策略已经限定到明确字段、构造器和 `JavascriptInterface` 方法，宿主 JSON DTO 使用显式读写；当前没有开启全库反射保留。后续应核对统计中的异常、线程、正则、集合、codec 和元数据占比，按实际依赖链处理。

### 编译选项与统计

`java/pom.xml` 当前为 `ADVANCED`、`minifying=true`、生产 source maps 关闭。固定 TeaVM 0.16.0 源码中的映射是 `NONE → SIMPLE`、`BALANCED → ADVANCED`、`AGGRESSIVE → FULL`，因此当前已处于官方 JS 默认的均衡档。不能把当前误判为尚未开优化，或把 `ADVANCED` 误解为激进档。

`SIMPLE` 跳过内联；`FULL` 允许更大内联预算，两者都不能预设更小。首批固定现有 `ADVANCED`，不为可选实验延迟发布。A/B 已通过 `MAVEN_OPTS=-Dteavm.js.stats=true` 获取 TeaVM 原生包级统计：主要体积来自 Jsoup parser、regex/re2j、Unicode 与 time formatting，收窄 ProtoBuf 服务未改变这些依赖链。统计实际按 UTF-16 源码偏移计数，只用于归因与相对比较；交付大小继续以 UTF-8 文件字节及压缩结果为准。依据：[官方 Gradle 选项](https://teavm.org/docs/tooling/gradle.html)、[Maven 选项](https://teavm.org/docs/tooling/maven.html)，以及固定子模块的 `TeaVMTask.java`、`TeaVM.java`、`JavaScriptTarget.java`。

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

共享材料与 gzip 契约固定并提交后，先在本地发布两份代表包，核对 GitHub 实际资产与恢复结果；随后启动可断点续传的首次全量，CI 只跟随增量。公共常量字典、二次 minify 和编译档位对比留作后续优化，不阻塞首批。编译成功仅发布为 `compiled_unverified`；真实 Source ID、六项操作、网络/缓存/取消与图片兼容仍按独立证据验收。
