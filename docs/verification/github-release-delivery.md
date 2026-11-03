# 公开 GitHub Release 下载门

2026-11-03，`Wybxc/karuyomi` 已是公开仓库。用户要求扩展 AOT 从 GitHub Release 直接下载，共享桥和 WASM 由 Web Static Assets / Native 内置交付。本次只验证下载可行性，没有部署新的交付链路。

## 实测结果

Codex 内置浏览器 Chromium 156 从 loopback 页面发起匿名 `fetch`，`credentials: omit`，同时检查普通 GET 和 Range：

| 入口                                                  | 浏览器结果                                      | 补充证据                                                                                      |
| ----------------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `github.com/.../releases/download/...`                | 普通 GET、Range 均 `TypeError: Failed to fetch` | 初始 302 未带 `Access-Control-Allow-Origin`                                                   |
| `release-assets.githubusercontent.com` 的有效最终地址 | 直接 GET、Range 均 `TypeError: Failed to fetch` | 匿名命令行 GET 返回 200，Range 返回 206，但最终响应未带 `Access-Control-Allow-Origin`         |
| GitHub asset API，`Accept: application/octet-stream`  | 403 JSON，能跨域读取错误响应                    | `x-ratelimit-remaining: 0`，明确为匿名 API 限流；不是资产读取成功，也不能将该项归为 CORS 失败 |
| GitHub asset JSON API 对照                            | 相同限流响应，可跨域读取                        | 说明浏览器能访问 API 的 CORS 响应                                                             |

命令行另用 loopback、`null` 和 HTTPS 页面 Origin 检查最终 CDN 的完整 GET，均未收到 ACAO。API 在未限流的命令行请求中返回带 `ACAO: *` 的 302，但这不能补足最终资产响应的 CORS 许可。官方 API 支持二进制 200 或 302；客户端仍必须满足实际返回链路的浏览器约束。[GitHub Release assets API](https://docs.github.com/en/rest/releases/assets#get-a-release-asset)、[GitHub REST CORS](https://docs.github.com/en/rest/using-the-rest-api/using-cors-and-jsonp-to-make-cross-origin-requests)。

## 当前决策边界

仓库公开解决匿名下载权限，不解决本次实测中的 Web 跨域读取。普通浏览器下载成功也不代表 Worker 能取得、解压并验证扩展字节。不能使用 `no-cors` 的 opaque 响应、关闭浏览器安全检查或携带私有 token 来冒充验收通过。

用户在本次实测后决定，Static Assets 改为所有客户端的最终权威来源，每个扩展只保留最新可用构建，由客户端或 Service Worker 管理更新。扩展不再需要 GitHub Release 发布；增量构建状态与客户端索引分开维护，首次全量在本地完成，CI 跟随上游做有界增量。当前代码迁移与跨端下载、取消、有界解压和更新验收仍待完成；本页的 CORS 结果仅解释为何放弃 Release 直下方案。

临时页面、重定向地址及原始机器输出留在忽略目录；本次浏览器报告为 `runtime/teavm/.local/probes/github-cors/browser.json`。最终签名地址会过期，不作为源码、长期定位或公开文档保存。
