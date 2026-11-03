# API 验证

`pnpm exec vitest run apps/api/test` 验证 Access 签名与 claims、完整 API 鉴权、请求 origin/host、登录返回路径、HTTP bridge 边界，以及旧扩展 API 已删除、公开静态资源不读取私有绑定。

`node --test tools/extensions/registration.test.ts` 验证 gzip 编码/canonical 双 SHA256、有界解压、静态 index/manifest 当前身份、按包替换网络策略、不可变 buildId 冲突及事务回滚。它使用内存 SQLite；材料目录来自当前受信 host 构建元数据，不访问 Cloudflare。

生产扩展唯一来源是 Static Assets：`/extensions/index.json`、`/extensions/builds/<buildId>/manifest.json`、`/extensions/artifacts/<canonicalSHA>.gz`。`.gz` 是 manifest 声明的 payload 编码，HTTP 不使用 `Content-Encoding: gzip`。网络 API 不再提供扩展列表、清单或正文，也没有 R2 绑定。D1 只登记当前 build 的 Source 网络策略；`registration.ts --remote` 在写入前检查部署 origin 的公开 index 和清单，`--local` 必须显式提供 `--static-root` 受控快照，不能用于 remote。

静态更新部署后，可信部署任务运行以下命令，将已批准 package 的域名策略切换到当前 build；它不下载 gzip，不为新 package 批准域名，也不从 Source 请求学习白名单。AOT 构建任务不持有部署凭据：

```sh
node tools/extensions/network-policies.ts --remote
```

同步先校验部署 origin 的完整静态 index 与各清单，再以 Wrangler D1 JSON 接口读取已批准策略并在单个 SQL 文件事务中更新 buildId/bundle SHA、保留原域名、删除退役授权。读写之间的并发禁用或策略修改使事务失败。开发探针只可显式使用 `--local --static-root SNAPSHOT --persist-to STATE`。`node --test tools/extensions/network-policies.test.ts` 覆盖跨 build 保留 host、新包不授权、删包、禁用/并发冲突和 metadata-only 校验；正式 workerd 探针同时使用真实本地 D1/Wrangler 验证这条同步链。

HTTP 网络生产入口只接受 `application/vnd.karuyomi.http.v2`，不提供 JSON/Base64 回退。真实 workerd 的受控 HTTP origin 回归独立执行：

```sh
node apps/api/test/http-bridge-workerd-probe.ts
```

此命令不需要私有凭据、JVM、AOT 或外网。它使用锁定 Wrangler 的 Miniflare/workerd、临时 D1、现场生成并验证的 RS256 JWT，以及临时 loopback HTTP server。只有该探针的 outbound Node HTTP handler 将已声明的 `fixture.example.org` 逐块转发到本地夹具；生产域名、鉴权和网络策略不放宽。成功结果默认写入忽略目录 `.local/probes/http-bridge-v2.json`，可用第一个参数指定输出路径。

夹具实际发送 gzip/Brotli 压缩字节，验证解码后的正文 SHA256、200/206/403、重复 Set-Cookie、HEAD 的表示头、禁止自动重定向、流式二进制上传、早响应仍要求完整请求 END，以及消费取消、请求 AbortSignal、超时均关闭 origin 连接。它验证真实 workerd 与受控 origin，不验证真实 Source、生产 Access 或 CacheInterceptor。压缩边界依据 [Cloudflare Fetch 文档](https://developers.cloudflare.com/workers/runtime-apis/fetch/)；测试不把附加 gzip 头的普通字节当作压缩证据。

真实 D1 策略注册与 Static Assets 路由探针：

```sh
node apps/api/test/workerd-probe.ts \
  PATH_TO_OUTPUT/manifest.json \
  PATH_TO_OUTPUT/artifacts
```

探针以给定清单与唯一 `artifacts/<canonicalSHA>.gz` 创建临时受控静态快照，执行全部 Drizzle 迁移与正式 `registration.ts --local --static-root ... --persist-to ...`。随后用真实 Miniflare Static Assets 路由公开交付 index、manifest 和 gzip，检查已有静态资源绕过入口 Worker、gzip MIME/无 HTTP Content-Encoding、传输双 hash、未知静态导航 404、已知应用路由 shell 与 host.html 307。独立测试入口添加 marker header 以区别是否经过入口 Worker；生产入口不包含该 header 或测试公钥。

D1 只含当前网络策略，不含 manifest/artifact 表；探针验证冲突时整个 Wrangler SQL 文件事务回滚。API 仍校验真实 RS256、audience、host；已删除 `/api/extensions/*` 在鉴权后返回 404。默认结果在忽略目录 `.local/probes/workerd-static-extensions.json`，可选第四个参数改输出位置。临时状态始终清理，不访问远程 D1，不输出 JWT、密钥或 Source 正文。此探针可以输入受控构建夹具，因此通过仅证明本地 workerd/D1/Static Assets 集成，不能冒充真实 Source、生产 Access 或在线分发验收。

Wrangler 使用 `not_found_handling: none`，只让 `/api`、`/api/*` 和 `/runtime/host.html` 优先经过 Worker；已有扩展和共享材料直接由 Static Assets 提供。缺失资源保持 404。只有实际应用地址 `/`、`/auth/complete`、`/browse`、`/settings` 显式读取 shell，避免未知扩展路径获得 SPA 200。依据 [官方 Static Assets 配置](https://developers.cloudflare.com/workers/static-assets/binding/) 与 [SPA 路由说明](https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/)。

真实 Source 浏览器回归使用 [source-metadata-probe.ts](source-metadata-probe.ts)，步骤与边界见 [说明](source-metadata-probe.md)。它加载当前静态产品构建并通过正式 HTTP bridge 请求 Source，不以夹具替代 Source，不把编译或初始化当作在线兼容。
