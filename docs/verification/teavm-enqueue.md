# 实际 TeaVM 的 enqueue 与 RPC owner

2026-11-05，Codex 内置 Chromium 156 使用项目正式 TeaHost、BrowserCall 和二进制 HTTP transport，执行受控 Source 的嵌套回调、异常、取消与跨 RPC 所有权分项。浏览器报告与 Node 后处理均通过，命令退出 0。产品运行时代码固定为 `1f599cd`；三个官方 Source 的独立在线证据见[v4 运行记录](v4-source-runtime.md)。

## 输入与范围

正式复验入口为 `tools/teavm/check-enqueue.ts`，Java 夹具在 `tools/teavm/fixtures/enqueue/Generated.java`，浏览器 driver 在 `packages/runtime-host/test/enqueue-java-browser-worker.ts`。入口复制正式 Java、物化固定上游补丁，再经正式 `compileExtension` 和 TeaVM 0.16.0 生成 JS；没有用 JVM 或手写 JS 冒充 Java 执行，也没有修改官方扩展。

- ABI 为 `karuyomi-source-host-v4`，使用已锁定 seed/JDK/Maven 和 Node 24.15.0。
- Java bundle 为 1,933,152 B，SHA-256 `08100535e1c36d5ca1dcfdc6bc06e10f7cfdf14fe8e7260f45b6b2c8cb6254a6`。
- Java 夹具 SHA-256 为 `2d4a4058f195abdeed1369d4548ba6d36d34e5c099753f58aa2b5ff9f5a06299`。
- 实际 Worker SHA-256 为 `0ba47fa69941aa6502e7c937916f71047f4cce453dfc163067d0dd569c2e2f54`。独立复核确认实际文件、identity 与报告一致。

这是实际 TeaVM 到受控 HTTP-v2 端点的分项，不包含 workerd、真实上游 origin、生产 Access、官方 Source 或 Native。受控 Source 故意在主方法返回后完成回调，以验证产品 Java 的真实排空路径。

## 已通过

共九个 entry（init、load 和七次 popular），每次故意复用相同 requestId/generation，核对每次 token 唯一：

- Source 主方法先返回，第一层和嵌套 enqueue 回调随后完成，最后才交付 `teaDone`。
- `onResponse` 抛出异常成为 Source 错误，响应由宿主清理，不再调用第二次 `onFailure`；下一 RPC 仍可成功。
- 网络失败经 `onFailure` 处理后正常排空；开启 OkHttp retry 的受控 POST 仍只发送一次。
- `Call.cancel()` 到达正式二进制 transport，未完成正文读取被拒绝，连接实际关闭。
- 下一 RPC 正在执行时唤醒旧 owner，旧动作被拒绝，没有启动迟到 HTTP，新 RPC 正常完成。
- RPC A 创建 Call，RPC B 首次 execute/enqueue；二者绑定首次执行时的 owner，前台结果和后台回调均完成。

每个 entry 完成时 HTTP handle 集合均为空；最终 `open=0`，观测到两次 transport cancel。Node 在清理服务前核对八个预期路径各只有一次 POST、取消连接已关闭且正文未完成，以及旧 owner barrier 已收到；`networkVerified=true`。该连接关闭不是服务最终退出产生的假象。

## 复验与保留

```sh
node tools/teavm/check-enqueue.ts --build-only
node tools/teavm/check-enqueue.ts --serve-only --timeout-ms 180000
```

在 Codex 内置浏览器打开输出的 loopback URL，页面自动执行并 POST 小报告；Node 写入 ignored `.local/v4-enqueue/browser-report.json` 后清理连接并退出，不需要下载文件。必须同时核对退出码、报告 `passed/networkVerified` 和 identity；`--serve-only` 不证明维护源码在构建后未变化，源码变化须重新 build。runner/driver 分别纳入 tools/bridges 严格类型检查与依赖检查，实际浏览器门保持手动执行。

本次不可变通过报告保留为 `.local/v4-enqueue/browser-report-passed.json`，构建与检查日志同目录；不将机器输出提交源码。实际服务已退出、无监听或本次编译进程。30 秒 fatal drain 超时、并发上限、manager 回收的实际浏览器组合仍未在本门覆盖；已有 JVM/TS 回归不能代替这些实际运行门。

验收后修正了夹具报告自身的失败路径：参数解析、构建和身份校验前复位为未通过，错误写入 `cliError`；页面无论报告 POST 成功与否均终止 Worker。随后注入非法参数与错误 Worker 摘要，两次 CLI 均退出 1、报告 `passed=false`，未残留旧通过结果；恢复原 identity 后确认实际 Worker 字节未变。负向报告也留在 ignored 目录，因此读取本次浏览器证据时应使用上述单独保存的通过报告，不能把最后一次负向命令的报告当作浏览器结果。报告 POST 失败的浏览器分支未做故障注入。
