# API 验证

`pnpm exec vitest run apps/api/test` 验证 Access 签名与 claims、完整 API 鉴权、请求 origin/host、登录返回路径、扩展注册读取、私有缓存、条件/Range 请求及 HTTP bridge 边界。

`python3 scripts/test_register_build.py` 验证不可变构建 ID/网络策略/产物元数据冲突、幂等重试、失败回滚、清单边界及上传中断不触发发布。它使用内存 SQLite，不访问 Cloudflare。

HTTP 网络生产入口只接受 `application/vnd.karuyomi.http.v2`，不提供 JSON/Base64 网络回退。真实 workerd 的受控 HTTP origin 回归独立执行：

```sh
node apps/api/test/http-bridge-workerd-probe.ts
```

此命令不需要私有凭据、JVM、AOT 或外网。它使用锁定 Wrangler 的 Miniflare/workerd、临时 D1、现场生成并验证的 RS256 JWT，以及临时 loopback HTTP server。只有该探针的 outbound Node HTTP handler 将已声明的 `fixture.example.org` 逐块转发到本地夹具；生产域名、鉴权和网络策略不放宽。成功结果默认写入忽略目录 `.local/probes/http-bridge-v2.json`，可用第一个参数指定输出路径。

夹具实际发送 gzip/Brotli 压缩字节，验证解码后的正文 SHA256、200/206/403、重复 Set-Cookie、HEAD 的表示头、禁止自动重定向、流式二进制上传、早响应仍要求完整请求 END，以及消费取消、请求 AbortSignal、超时均关闭 origin 连接。它验证真实 workerd 与受控 origin，不验证真实 Source、生产 Access 或 CacheInterceptor。压缩边界依据 [Cloudflare Fetch 文档](https://developers.cloudflare.com/workers/runtime-apis/fetch/)；测试不把附加 gzip 头的普通字节当作压缩证据。

真实 workerd、D1、R2 集成探针单独执行，需要已构建的清单及其所有内容寻址产物：

```sh
node apps/api/test/workerd-probe.ts \
  PATH_TO_OUTPUT/manifest.json \
  PATH_TO_OUTPUT/artifacts
```

默认结果保存到被忽略的 `runtime/teavm/.local/probes/workerd-registered-artifacts.json`；可选第四个参数指定其他输出路径，不会默认改写已提交文档。探针创建独立临时 Wrangler 状态，执行真实迁移和 `register-build.py --local --persist-to`，然后运行 Miniflare/workerd。它会在请求前验证真实 RS256 签名；测试入口只信任该次运行生成的公钥，生产 `src/index.ts` 不导入它，也不提供任何跳过鉴权的开关。

探针检查已注册的真实 TeaVM manifest/list、所有 R2 产物的完整字节和 SHA256、私有缓存、缺失 JWT/错误 audience/错误 host、HEAD、304、Range、416。它还让 Wrangler 执行一个先写入 marker 再触发不可变冲突的文件，并证明 marker 一并回滚。无论成功或失败，临时状态都会清理；不访问远程 D1/R2、不输出 JWT/密钥/Source 正文。

[历史验证要点](../../../docs/verification/runtime-evidence.md) 保留一次本地真实运行的关键结果；完整请求/来源摘要只存于被忽略的本地研究归档。它证明 API 与本地存储适配工作，不替代生产 Cloudflare Access、线上 Source 网络语义或浏览器元数据闭环验收。HTTP bridge 只允许已验证构建的明确 hostname，禁用自动重定向和上游隐式缓存；不会把应用请求头复制给 Source。生产部署还使用 Cloudflare 的公网 fetch 路由边界，本地 workerd 运行不得绑定私网服务或放宽 host 白名单。

真实 Source 浏览器回归使用 [source-metadata-probe.ts](source-metadata-probe.ts)，复验步骤与边界见 [说明](source-metadata-probe.md)。它加载已校验的产品构建，使用相同测试入口和真实 HTTP bridge，不以夹具替代 Source，也不把编译成功当作在线兼容。
