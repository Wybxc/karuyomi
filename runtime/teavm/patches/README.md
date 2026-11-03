# TeaVM 类库补丁

原始类库来自官方 `vendor/teavm` 子模块，固定在 TeaVM 0.16.0（`e87d452e4bd70c77b9e19314a46c3d6971c148b6`）。本目录只维护项目需要的差异，不再保存完整的上游类库副本。

`tools/teavm/upstream_sources.py` 读取 `classlib/src/main/java/org/teavm/classlib/java/util/regex/T*.java`，应用对应补丁后，在临时构建目录生成 `Patched*.java`。生成类经项目的 `TeaTransformer` 替换 TeaVM 编译器 IR 中的实现。13 个补丁覆盖正则回溯、Unicode 分类、大小写及行边界；补丁同时记录供 IR 替换使用的类名调整。

物化过程验证每个原文件和结果文件的 SHA-256，精确校验补丁上下文，不允许偏移或模糊套用。更新 TeaVM 时需重新审查补丁和锁定摘要。原 Apache-2.0 与 Apache Harmony 版权头保留在生成文件中；许可证见子模块 `LICENSE`、`NOTICE`。

`runtime/teavm/java` 中的 `Base64`、`WaitObjectMethods` 和 `HttpSource` 等小型兼容实现由研究阶段为该宿主编写或提取改写，现作为项目代码维护，并保留来源说明。它们不是完整的第三方工程副本。Suwayomi 原始 Kotlin API 位于官方 `vendor/suwayomi-server` 子模块；历史参考工程和机器验证流水不参与当前构建。

验证入口：`python3 -m unittest discover -s tools/teavm -p 'test_*.py'`。完整物化检查需要先执行 `git submodule update --init vendor/teavm`。
