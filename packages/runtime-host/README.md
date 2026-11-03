# 公共运行宿主

`host.html` 是 Web 与原生 WebView 共用的同源控制页，`host.js` 也可直接加载到 Flutter Web 页面。`window.karuyomiRuntime.ready` 只表示控制协议可用，始终保持 `sourceReady: false`；只有真实 TeaVM `hostInit`、`hostLoad` 成功且 Source IDs 与已验证清单一致时，`open()` 才返回 session。

控制接口只传小型 DTO：

- `open({manifestPath, identity, expectedBuildId?, expectedBundleSha256?, userAgent?})` 返回 `{protocolVersion, workerInstanceId, generation, buildId, sources, capabilities}`。
- `invoke({requestId, sourceId, operation, args, timeoutMs?})` 返回 `{requestId, generation, buildId, data}`。Source 操作只允许 `popular/latest/search/details/chapters/pages`，顺序进入 Java。
- `cancel(requestId)` 取消排队任务；取消正在执行的任务会回收整代 Worker，不重放 Source 操作。
- `fetchApi({path, method?, headers?, body?})` 使用相同 cookie 上下文访问同源 `/api`，返回 `{status, headers, body, redirected}`；控制请求/响应分别限制为 128 KiB / 2 MiB。
- `rebuild()` 回收当前 Worker 并允许重新打开。`dispose()` 结束宿主；静默 Worker 最多有 1 秒提交文件系统状态，随后必定终止。
- `acquireImage()` 明确返回 `unsupported_capability`，等待真实二进制与处理后图片资源通道通过验证。

清单、脚本和资源只能通过 Access 保护的 `/api/extensions` 获取。加载器拒绝跳转、登录 HTML、协议/ABI 不匹配、超预算与 SHA-256 不符的产物；执行前检查完整字节。构建清单不属于公共静态目录。缓存与文件系统以已确认身份、仓库、包、storage schema 的摘要隔离。Worker 回收后，旧 generation 或 workerInstanceId 的响应不进入当前会话。

`teaHttp` 仍使用 P0-A v1 文本/Base64 基线，POST `/api/bridge/http` 并携带同源 cookie、`X-App-Request: 1` 与 `X-Runtime-Build`。远程脚本能力未开放。此基线不表示 P0-B 二进制桥或 P0-F3 图片门已完成。

运行 `pnpm --filter @karuyomi/runtime-host typecheck`、`pnpm exec vitest run packages/runtime-host/test`、`pnpm --filter @karuyomi/runtime-host build`。真实浏览器初始化探针由 `tools/teavm/browser-probe.mjs` 提供；本地探针不能替代生产 Access 或原生真机验证。
