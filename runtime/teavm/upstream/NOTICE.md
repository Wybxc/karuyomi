# 上游与第三方代码

- reference-host/src 中 eu/kanade/tachiyomi/source、部分 network 类型及 Jsoup 兼容代码来自 Suwayomi-Server，固定 commit 6b481e8b62938b9c060eb210b934e0fbfdfa466b。许可证：licenses/Suwayomi-MPL-2.0.txt。TeaVM HttpSource 的适配源码位于 java/src/main/java/eu/kanade/tachiyomi/source/online/HttpSource.java。
- public/extensions 中 77 个 APK 转换 JAR 来源于 Keiyoushi extensions，版本、URL、SHA256 见 inputs.json；上游源码 https://github.com/keiyoushi/extensions-source ，Apache-2.0，许可证：licenses/Keiyoushi-Apache-2.0.txt。本项目不包含对扩展业务的修改。
- TeaVM 0.16.0，Apache-2.0：https://github.com/konsoletyper/teavm 。构建依赖通过 Maven 获取。
- CheerpJ 4.3 通过官方 CDN 加载，未分发 Core；适用许可见 https://cheerpj.com/docs/licensing 。
- JVM 依赖与来源见 reference-host/pom.xml、java/pom.xml、public/runtime/classpath.json；各库许可见 JAR 中 META-INF。
- 原 HTTP 桥所用 @bokuweb/zstd-wasm 0.0.27 的 npm 包元数据为 MIT；Zstandard 的 BSD 许可见 licenses/Zstd-BSD.txt。本轮 TeaVM Zstd 桥已实现，独立 WASM bundle 的可重建源码在 scripts/zstd-source；JS/DOM 回调桥已实现；使用浏览器 JS 引擎，QuickJS 字节码及完整 Android WebView 仍有边界。
- ICU4J 79.1 的 Unicode 许可见 licenses/ICU4J-Unicode.txt。ICU4J 的 Collator／BreakIterator 服务工厂适配调用原 ICU 实现与资源；java.text.Collator／Normalizer 兼容类另使用浏览器 Intl／normalize，二者应区分。
- 原始结果中的漫画简介与图片地址属于原网站和作者，仅为公开 API 兼容性验证样本。全量结果保存宿主返回字段、状态和请求／错误观测；固定输入回放另在 public/performance-v2-fixtures.json、public/plugin-probe-fixtures.json 及失败配对结果的 responses 中保存公开 HTTP 响应正文，供字段、异常与请求差分复现。

- Base64 与 GroupQuantifierSet patch 派生自 TeaVM 0.16.0 类库源码；对应源码文件保留 Apache-2.0（及其原有附加）许可头，通过 TeaTransformer 替换编译器 IR 中的类实现。
