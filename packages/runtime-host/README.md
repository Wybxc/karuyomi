# 公共运行宿主

Web 页面加载 `host.js`，Native 在受控 WebView 中加载内置 host/Worker。唯一公开入口是 `window.karuyomiRuntime.control()`：输入与结果使用 `.proto` 生成的标准 ProtoJSON，每次带 `requestId` 并选择一个 command/result。`ready` 只表示控制协议可用，保持 `sourceReady: false`；真实 TeaVM 初始化和 Source ID 核对成功后，`open` 才返回 session。

当前命令包括：

- `open` 返回绑定 Worker、generation、build 和 Source IDs 的 session；`invoke` 只允许 `popular/latest/search/details/chapters/pages`，Source 调用串行进入 Java。
- `cancel` 取消排队 Source 请求；正在执行的普通 Source 调用通过回收 Worker 取消，不自动重放。
- `acquireImage` 经原 Page、Source 请求与处理链收齐不透明编码字节，仅返回 `resourceId/generation/byteLength/url`。宿主不读取图片 MIME、尺寸、方向，不预解码，也不选择分片。Web 使用受管 Blob URL，Native 平台适配复制为受管文件；不具备交付能力的平台明确拒绝。
- `cancelImage` 经独立通道停止生产，并等待 Java 退出；超过宽限回收 Worker。`releaseImage` 幂等释放正文；`closePageSession` 解除 Java 原始 Page 引用，不代替正文释放。图片合同见 [IMAGE-RESOURCES](../../docs/IMAGE-RESOURCES.md)。
- `fetchApi` 访问同源私有 `/api` 时携带同源 cookie；公开索引/清单仅允许无凭据的静态 GET。控制正文请求/响应分别限制为 128 KiB / 2 MiB。
- `rebuild` 回收当前 Worker 并允许重新打开；`dispose` 结束宿主，静默 Worker 最多有 1 秒提交文件系统状态，随后终止。

扩展索引、清单和 gzip 产物来自同源 `/extensions/` Static Assets，不经私有 API 或 Worker 转发正文，也不携带 Access/GitHub 凭据。加载器拒绝跳转、HTML、协议/ABI 不匹配、超预算与传输摘要错误。缓存与文件系统按已确认身份、仓库、包和 storage schema 隔离；旧 generation 或 workerInstanceId 的结果不得进入当前会话。

Source HTTP 使用 v2 有界二进制协议，向 `/api/bridge/http` 发送小 metadata 与分帧正文，携带同源 cookie 和 `X-App-Request: 1`；图片/HTTP 大正文不进入控制 ProtoJSON。远程脚本能力仍未开放。

图片内容解释、解码与缓存属于 UI。当前默认使用 Flutter/平台直接解码；未采用且缺少同条件真机性能证据的 `runtime/image-codec` 候选源码与专属工具已删除。先完成真实 UI 基线，再针对实测瓶颈评估成熟方案；长图与设备峰值仍待验收。

构建入口为 `pnpm --filter @karuyomi/runtime-host build`，通过声明式 Vite CLI 先生成六份共享材料，再构建 Web/Native 宿主。资源生成、材料清单与 Native 内嵌集中在 `vite.runtime-plugin.ts`；独立 `materials.ts` 已删除。`@karuyomi/contracts` 提供纯 `runtimeMaterialCatalogSchema` 模型及类型，消费者直接 `readFile` 已生成的 `dist/materials.json` 并用该 schema 解析，再按需读取字节。catalog 只包含五桥与 Zstd WASM，不保留闲置 codec 字段或构建入口。

工程检查使用 `pnpm --filter @karuyomi/runtime-host typecheck`、`pnpm test` 及 `BROWSER=none pnpm test:browser`；后者用 Codex 内置浏览器打开官方 Preview URL。当前测试结构见 [Vite 计划](../../docs/plan/vite-build-and-testing.md)。真实 Source、Access、Native、图片阅读与设备峰值分别验收，范围见 [VERIFICATION](../../docs/VERIFICATION.md)；本地 fixture 通过不能代替产品结果。
