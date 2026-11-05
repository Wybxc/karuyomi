# 普通文件运行证据

> 入口状态（2026-11-05）：本文保留原日期、固定输入与实际结果。涉及的旧自定义探针、浏览器 runner 和构建入口已退役；旧命令仅适用于记录中的历史 checkout，不能在当前源码直接复验。当前入口及覆盖见 [Vite 计划](../plan/vite-build-and-testing.md)。新官方 fixture 的结果单独验收，不把本文历史证据算作当前 Source 在线、生产 Access 或 Native 完整门通过。

2026-11-04，当前普通文件实现完成二进制分块、typed idb、inode、配额与 owner 生命周期。以下三个测试层级独立记录；均不代表正式 Source、Native 或性能验收。设计见[普通文件存储](../design/runtime-file-storage.md)，后续门见[运行时存储计划](../plan/runtime-storage.md)。

## 浏览器桥机制

主代理使用 Codex 内置 Chromium 156，运行正式 `file-lifecycle-browser-suite.ts` 和 `file-lifecycle-worker.ts`，**14 组全部通过**。实际使用产品 file bridge、真实 Worker、IndexedDB 和 Web Locks；故障仅由测试 driver 注入。

覆盖二进制 64 KiB 与跨块随机 IO、拒绝旧 Base64 操作、稀疏文件、truncate 后重扩零、独立 cursor、rename 替换、unlink 后冷读写、目录与高 Unicode 路径、双 Worker 原子 append、namespace 隔离、未链接 open 文件计费、handle/metadata 配额与拒绝回滚、pending 4 操作上限。

真实 IDB 重复主键请求触发 `ConstraintError`，验证跨块写入的正文、长度、cursor 和 usage 一起回滚。system close 的真实事务 abort 保留原 owner 锁、未链接 inode 计费及兄弟/外来句柄，第二次显式重试成功后才释放。Worker terminate 在提交前只留下旧完整事务；提交后 ACK 前死亡则保留新完整事务。新 Worker 回收死亡 owner，不等待旧时间租约。

报告位于忽略的 `.local/files-stage3/report.json`；这组不执行 Java。

## 原 JVM、Accessor 与实际 TeaVM

`tools/teavm/FileScenarios.java` 在两端运行相同代码。原 JVM 使用实际临时文件系统与原 Java File/RandomAccessFile/Okio，没有安装项目 FS；**32 项断言通过**。场景覆盖 131079 字节大文件、随机访问、truncate/稀疏、独立 cursor、rename/unlink 打开 inode、append、Unicode 目录、unsigned 单字节/连续 EOF、RAF 零长度与溢出范围、原 Okio 文件流。

`tools/teavm/FileAccessorTest.java` 使用产品 Java Accessor 和 JCL donor 方法、窄二进制存储 fixture，**24 项检查通过**：65536/65536/7 分块、准确输入范围、短读、EOF、非法回复、存储异常保留已提交前缀、关闭幂等及失败 close→重试 ACK。它不是浏览器或实际 JCL IR 替换测试。

两组 JVM 门和产品 Bridge/Accessor 编译均已接入 `pnpm teavm:check`；也可单独运行 `node tools/teavm/check-files.ts`。

同一共享场景经正式 `prepareSources`、`compileExtension` 和锁定 TeaVM 0.16.0 编译，在内置 Chromium 156 的真实 Worker 中，执行产品 Java `PersistentFileSystem`、`Bridge` 二进制 JSO 和产品 idb file bridge，**32 项全部通过**。两端共享正文 SHA-256 均为 `1933f7f279fb4232259d5af94a6f792a308a78e4c18b8ed5caafd99e943f9a78`。该独立测试 bundle 为 441628 B，SHA-256 `9a5d267f101b5533f49295c081f44bff0f7d5b12a3a0fb1ae1b5987e5a3be0b3`；不是发布扩展的 AOT 身份。

首次实际 TeaVM 场景在 append 后 EOF 断言失败。定位到项目 Accessor 返回 `-1`，而锁定 TeaVM 的内部 accessor 使用 `0`；此外上游 `FileInputStream.read()` 直接返回 signed byte。修正项目 Accessor 和自有 JCL IR 适配后，以新增 `0x80`/`0xff`、重复 EOF、RAF 零长度/range 和 close 重试回归重跑通过；没有改 vendor 或放宽断言。

实际 TeaVM 报告为忽略的 `.local/files-stage3/java-browser-report.json`。产物使用本次维护工作区的独立 Java fixture，仅把 mainClass 改为 `FileProbe`；没有改官方扩展源码或原 JAR。

## 复验与边界

准备锁定工具链和 seed 后：

```sh
pnpm teavm:check
pnpm typecheck:bridges
pnpm exec tsc -p tsconfig.tools.json
pnpm exec vitest run packages/runtime-host/test/bridge.test.ts
```

本次本地浏览器编排保留在忽略目录，不随干净检出交付；维护的测试主体是上述 Java fixture 与 browser suite。当前 checkout 可运行以下临时驱动，实际端口以 stdout 为准：

```sh
node .local/files-stage3/server.ts
# 内置浏览器打开打印的 loopback URL，自动执行 14 组机制门。
node .local/files-stage3/build-java.ts
node .local/files-stage3/java-server.ts
# 内置浏览器打开打印的 loopback URL，自动执行实际 TeaVM 共享场景。
```

改 Java 后须重建测试 bundle；改桥后须重启编排，不能复用旧内存产物。浏览器编排尚未接入自动 CI。正式 Source 读写、版本/身份 namespace 切换、Native、Cache 与 files 合计配额、真实取消和设备资源测量仍待验收；普通文件 allocated 不等于实际磁盘占用。
