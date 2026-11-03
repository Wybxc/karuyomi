# 提交要求

提交前必须对所有项目自有代码运行 `pnpm format`，再运行 `pnpm format:check`。范围包含 Java、Dart、JavaScript/TypeScript、Python、Kotlin/Gradle Kotlin DSL、Swift、Objective-C、Ruby、SQL 和结构化配置。按改动运行相关回归；格式化不是语义变更的替代验证。

使用 `pnpm hooks:install` 由 pnpm 精确锁定的 prek 0.5.9 安装标准提交前检查。检查不自动暂存；部分暂存的工作区处理交给 prek。`pnpm hooks:check` 可对全库手动执行相同检查。

- 需要完整 JDK 21+、Flutter 3.47.5 / Dart 3.13.4、macOS Xcode 27.2 的 swift-format 6.4.4 与 clang-format 21.0.0。Python / Java / Kotlin formatter 的版本和校验规则固定在格式化工具中；首次运行允许下载公开工具，不需要私有 JVM seed。
- `pnpm check` 在跨平台 CI 使用显式 portable 格式检查；Swift / Objective-C 仍必须在 macOS 上通过完整的提交前检查。
- 上游 `vendor/` submodules、生成产物、锁文件、冻结设计副本、精确上游上下文补丁和 `runtime/teavm/bridge/compat/` 的已发布内容寻址材料不是可重新排版的项目源码。兼容材料须保留已发布摘要；当前桥源码正常格式化。不能修改这些历史字节再覆盖旧哈希。

扩展首次全量在本地固定提交的独立构建目录运行；后续开发不得改动该构建目录的 host 输入。发布、checkpoint 和清理行为见 `docs/EXTENSIONS.md`。
