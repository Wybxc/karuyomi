# TeaVM 类库补丁

原始类库来自官方 `vendor/teavm` 子模块，固定在 TeaVM 0.16.0（`e87d452e4bd70c77b9e19314a46c3d6971c148b6`）。本目录只维护项目需要的差异，不再保存完整的上游类库副本。

`tools/teavm/upstream-sources.ts` 读取 `classlib/src/main/java/org/teavm/classlib/java/util/regex/T*.java`，在构建生成步骤使用精确锁定的 `java-parser` 解析 Java token，生成独立的 `Patched*` 供体类，再应用本目录的行为补丁。生成文件只写入临时构建目录，上游 submodule 不变。生成类经项目的 `TeaTransformer` 替换 TeaVM 编译器 IR 中的实现。13 个补丁只维护正则回溯、Unicode 分类、大小写及行边界等行为差异，不再包含类名和构造器改名。

生成步骤仅调整该文件约定的标识符；`Pattern` 另引用 `PatchedLexer`，两类供体的 public 可见性及唯一 Javadoc 链接也在生成步骤处理。字符串、文本块、其他注释和原始排版保留。命名先于行为补丁，因此补丁刻意加入的 `(TPattern)(Object)this`、`Lexer` 对原始 `TPattern` 的引用及其他上游类型不会被误改。补丁头和上下文对应生成后的供体基线。

物化过程先验证每个原文件的 SHA-256，再要求补丁上下文精确匹配（`fuzzFactor: 0`），最后验证生成结果的 SHA-256。本次命名步骤拆分保留全部 13 个结果摘要，生成 Java 字节与拆分前一致。更新 TeaVM 时需重新审查补丁和锁定摘要。原 Apache-2.0 与 Apache Harmony 版权头保留在生成文件中；许可证见子模块 `LICENSE`、`NOTICE`。

`runtime/teavm/java` 中的 `Base64`、`WaitObjectMethods` 和 `HttpSource` 等小型兼容实现由研究阶段为该宿主编写或提取改写，现作为项目代码维护，并保留来源说明。它们不是完整的第三方工程副本。Suwayomi 原始 Kotlin API 位于官方 `vendor/suwayomi-server` 子模块；历史参考工程和机器验证流水不参与当前构建。

验证入口：`pnpm test:teavm-patches`。完整物化检查需要先执行 `git submodule update --init vendor/teavm`。
