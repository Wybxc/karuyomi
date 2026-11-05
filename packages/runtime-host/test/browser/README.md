# 真实浏览器回归

使用 Vitest Browser 的官方 preview provider，由 Vite 处理 TypeScript 与 `?worker` 入口；Worker 调用直接使用 Comlink。这里不维护自建 HTTP server、打包步骤或测试结果协议。

```sh
DEBUG=vitest:browser:pool pnpm exec vitest --watch --config packages/runtime-host/vitest.browser.config.ts
```

配置固定 Vite 官方环境变量 `BROWSER=none`，防止 preview 自动打开默认浏览器。`server.open: false` 本身不能阻止当前 preview provider 的 `openPage()` 调用。启动日志中的 `creating session` 行给出 UUID；在 Codex 内置浏览器手工打开日志中的本地地址，并附上 `?sessionId=<UUID>`。首次连接须在 5 分钟内完成，直接打开不带 sessionId 的首页可能显示 Connecting 且不运行测试。每次重启使用新 UUID。

例如，日志地址为 `http://127.0.0.1:63315/__vitest_test__/` 时，打开 `http://127.0.0.1:63315/__vitest_test__/?sessionId=<UUID>`。测试结束后按 `Ctrl-C` 清理 runner；一次性执行可将 `--watch` 换为 `run`。Vitest 的 `chromium` instance 名称只是 preview 配置标签，验证记录必须写实际打开页面的浏览器，不能据此声称 Chromium 覆盖。

当前回归检查：缓存二进制 reader 的快照、真实 Worker/Web Locks owner 回收与 namespace 隔离、generation 与 chunk 限额、真实 IndexedDB 事务 abort 的原子性、文件 unlink 后 handle 生命周期，以及真实 OffscreenCanvas 像素与 Bitmap owner 释放。测试结束回收所有 Worker 并删除测试数据库。

旧 `check-cache-storage`、`check-runtime-storage`、`check-enqueue`、图片 Worker/owner 专项及其专属 browser suite 已退役；这里保留核心产品约束，并未搬运旧报告脚本的全部断言或 Java 编译专项。Node 中的受控 codec/graphics 单元测试仍独立保留。浏览器桥机制通过不能代替真实 Source、Access、图片阅读或真机性能验收。
