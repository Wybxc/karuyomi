# API 验证

`pnpm exec vitest run apps/api/test` 验证 Access 签名与 claims、完整 API 鉴权、请求 origin/host、登录返回路径、扩展注册读取、私有缓存、条件/Range 请求及 HTTP bridge 边界。

`python3 scripts/test_register_build.py` 验证不可变构建 ID/网络策略/产物元数据冲突、幂等重试、失败回滚、清单边界及上传中断不触发发布。它使用内存 SQLite，不访问 Cloudflare。

真实 workerd、D1、R2 集成探针单独执行，需要已构建的清单及其所有内容寻址产物：

```sh
node apps/api/test/workerd-probe.mjs \
  runtime/teavm/.local/manifests/BUILD_ID.json \
  runtime/teavm/.local/artifacts
```

可选第四个参数是要保存的证据 JSON 路径。探针创建独立临时 Wrangler 状态，执行真实迁移和 `register-build.py --local --persist-to`，然后运行 Miniflare/workerd。它会在请求前验证真实 RS256 签名；测试入口只信任该次运行生成的公钥，生产 `src/index.ts` 不导入它，也不提供任何跳过鉴权的开关。

探针检查已注册的真实 TeaVM manifest/list、所有 R2 产物的完整字节和 SHA256、私有缓存、缺失 JWT/错误 audience/错误 host、HEAD、304、Range、416。它还让 Wrangler 执行一个先写入 marker 再触发不可变冲突的文件，并证明 marker 一并回滚。无论成功或失败，临时状态都会清理；不访问远程 D1/R2、不输出 JWT/密钥/Source 正文。

`evidence/workerd-registered-artifacts.json` 是一次本地真实运行结果，记录清单和源文件摘要。它证明 API 与本地存储适配工作，不替代生产 Cloudflare Access、线上 Source 网络语义或浏览器元数据闭环验收。HTTP bridge 只允许已验证构建的明确 hostname，禁用自动重定向和上游隐式缓存；不会把应用请求头复制给 Source。生产部署还使用 Cloudflare 的公网 fetch 路由边界，本地 workerd 运行不得绑定私网服务或放宽 host 白名单。

真实 Source 浏览器回归使用 [source-metadata-probe.mjs](source-metadata-probe.mjs)，复验步骤与边界见 [说明](source-metadata-probe.md)。它加载已校验的产品构建，使用相同测试入口和真实 HTTP bridge，不以夹具替代 Source，也不把编译成功当作在线兼容。
