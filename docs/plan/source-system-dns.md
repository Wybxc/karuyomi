# Source 系统 DNS 兼容

## 目标

支持调用 `OkHttpClient.Builder.dns(...)` 的原扩展继续构造请求。由现有 Worker 解析原域名并出站，保留 Source 的签名、Cookie、拦截器和有界正文。

## 状态

- [x] Java 宿主接受 DNS 配置，并继续使用现有中继的系统解析。
- [x] 用固定上游提交补编哔咔漫画并核对正式产物。
- [x] 在隔离上游夹具中用正式产物验证签名登录和热门列表请求，检查 Cookie 与封面 URL。
- [ ] 发布单包增量后验证生产 Worker 出站、真实登录、目录与封面。

## 验收

宿主及原扩展的对照见[默认 DNS 验证](../VERIFICATION.md#source-系统-dns-兼容)。原扩展能否在线使用由 Worker 对上游域名的实际连通性和站点响应决定。
