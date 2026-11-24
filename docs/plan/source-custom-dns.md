# Source 自定义 DNS

## 目标

支持原扩展通过 OkHttp `Dns.lookup()` 指定公网 HTTPS 连接地址。Web、iOS 和 Android 共用 Source 宿主与 Access 中继。出站保留原始域名、TLS 认证、请求签名、Cookie 和拦截器语义。

## 实施

- [x] 在 HTTP 帧的有界元数据中携带本次连接的 DNS 候选地址，并在出站前验证公网地址。
- [x] 接入支持自定义解析的 HTTPS 出站服务，复用 Access、中继流控、取消及错误回传。
- [x] 补齐 TeaVM 的 `InetAddress` 和 OkHttp DNS 回调代码。正式 AOT 验收在下方继续。
- [ ] 在正式构建和 Wrangler harness 验证默认出站、DNS 分支和请求生命周期。
- [ ] 在已授权构建机复编哔咔漫画，核对原扩展登录、目录、封面及分发结果。

## 验收

以真实 AOT 和 HTTPS 请求确认自定义地址参与建连，证书及 HTTP authority 仍绑定原域名。验证重定向、非公网结果、超时、请求取消和流式正文。生产兼容性以实际部署与图源行为为准。
