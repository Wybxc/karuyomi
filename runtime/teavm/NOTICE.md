# 运行时来源与第三方许可

`java/` 与 `bridge/` 是本项目维护的兼容层和运行实现，源于 release9 研究交付后继续开发。历史交付的源指纹见 [验证要点](../../docs/verification/runtime-evidence.md)，不用于冻结当前项目代码。旧参考工程、研究探针、导入脚本和原始流水不作为正式构建源。

- TeaVM 0.16.0 由 `vendor/teavm` submodule 固定，Apache-2.0。正则 `Patched*` 实现从该上游源码加 `patches/teavm/` 生成，不保留平行拷贝；输出保留原有 TeaVM / ASF 许可头。`prototype/jcl/Base64.java` 是重新实现的兼容适配，保留其历史 TeaVM 作者许可头；`WaitObjectMethods.java` 提取并适配 TeaVM `TObject` 的等待逻辑，保留来源说明。
- Suwayomi-Server 由 `vendor/suwayomi-server` submodule 固定，MPL-2.0。Source、模型与部分网络 ABI 来自其依赖材料；`HttpSource.java` 和 `OkHttpExtensionsKt.java` 是本项目的 Kotlin→Java / TeaVM 同步 ABI 适配，未把旧参考 Kotlin 工程当作项目原创。历史材料来源 commit 为 `6b481e8b62938b9c060eb210b934e0fbfdfa466b`；材料原 JAR 摘要由工具链锁校验。许可证见 `licenses/Suwayomi-MPL-2.0.txt`。
- Keiyoushi 扩展源码由 `vendor/extensions-source` submodule 固定，Apache-2.0。正式构建使用其 Gradle/KSP 生成的 JAR 与 Source 元数据，不修改扩展业务字节。许可证见 `licenses/Keiyoushi-Apache-2.0.txt`。
- ICU4J 79.1 的 Unicode 许可见 `licenses/ICU4J-Unicode.txt`。`AotServiceFactory` 只分派到原 ICU 构造器；原 ICU 实现和资源保持依赖材料身份。`java.text.Collator` / `Normalizer` 是浏览器 Intl / normalize 适配。
- Zstandard 的 BSD 许可见 `licenses/Zstd-BSD.txt`；`@bokuweb/zstd-wasm` 0.0.27 来源为 [bokuweb/zstd-wasm](https://github.com/bokuweb/zstd-wasm)，包声明 MIT，由精确版本与 pnpm tarball integrity 固定。WASM 在 Web 作为静态资源交付，在 Native 随应用打包，构建与加载均校验其摘要；客户端构建不从私有 JVM seed 提取 WASM。
- Gson、Jsoup、OkHttp、Okio、Kotlin、Android ABI 及其他 JVM 依赖的版本和文件摘要在 `toolchain-lock.json` 的 runtime seed 中固定，各库原许可见其 JAR 的 `META-INF`。同名 Java 文件是项目为 TeaVM 提供的适配；例如 Gson `Streams` 提供递归 JSON 读写，未复制完整原库源码。

正式构建中的 `PatchLibraries.java` 仅适配宿主和依赖 JAR，不改写扩展输入 JAR。发布 provenance 记录实际上游提交、材料摘要、工具链和构建输出；编译或初始化通过不代表在线网站语义与图片功能通过。
