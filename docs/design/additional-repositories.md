# 额外扩展仓库

账户扩展意图继续以 Worker API + D1 为权威；每个仓库自己的 Static Assets 是该仓库扩展的最终分发来源。客户端直接下载公开目录、清单和代码，不通过应用 Worker 转发正文。实现进度见[计划](../plan/additional-repositories.md)，实际检查与平台证据见[验证记录](../verification/additional-repositories.md)。

## 仓库与账户选择

`GlobalSettingsValues.repositories` 保存最多 16 个额外 `ExtensionRepository(catalogUrl, repoId, name)`。默认仓库是当前应用 origin 的 `/extensions/index.json`，稳定身份为 `keiyoushi`，隐式固定保留。额外仓库的 URL、repoId 分别唯一，也不能复用默认仓库的任意一项。名称仅用于展示。

目录 URL 必须是规范化 HTTPS origin 加精确 `/extensions/index.json`，不含凭据、查询或 fragment；开发 HTTP 仅允许 literal localhost、127.0.0.1、[::1]。repoId 是 1–200 字符 ASCII 标识，允许字母、数字、点、下划线和连字符。目录顶层 `ExtensionIndex.repoId` 必填，每项 descriptor 与 manifest 的 repoId 必须一致。用户先只读获取并预览目录，再明确确认；刷新没有账户写入。

`InstalledExtension` 继续以 package 唯一。同包的另一个仓库是明确替换候选：先准备候选、固定原全局 revision 和完整值，再经用户确认提交原 CAS。不能因目录刷新、同名 package 或相同 buildId 静默换仓。未知 ACK 只重试原 UUID/body/CAS；任意全局 pending 阻止新全局编辑。

移除额外仓库不删除已确认安装引用、书架、分类、进度、书签或收藏源。缺仓库、下架或未登记网络的扩展显示具体不可用原因，并保留卸载入口；不会改用另一仓库的同名包。稳定 package/source 业务身份跟随用户明确选择的安装来源。

## 下载与运行身份

`CatalogReference(catalogUrl, repoId)` 贯穿 `PrepareBuildRequest`、`PreparedBuild`、`OpenRequest`、`OpenWorker` 和 `RuntimeSession`。准备和打开都核对精确来源、descriptor、manifest、bundle hash；响应回显须匹配请求。四个正式打开入口、Access 恢复、迁移候选、后续调用与图片取得均遵守已确认来源。

公开元数据和 bundle 下载使用 `credentials: omit`，拒绝重定向，保留流式字节预算、MIME、超时和取消；外部仓库须提供允许浏览器及 Native 内置 WebView 运行时读取的 CORS；Native 的 Dart 元数据读取成功不能代替 bundle 运行时下载验收。共享 materials 始终来自应用 Static Assets 或 Native 内置资源，HTTP 桥始终访问应用 origin。外仓不能替换共享宿主代码或借下载携带应用凭据。

可变 Source 存储与 Cookie 的 namespace 包含应用/API origin、Access subject、catalog URL、repoId、package 和 storage schema。不可变代码缓存仍按已验证 canonical digest 复用，同一份代码不重复验证；缓存命中不授权账户安装或网络访问。

Source 设置也以 `(catalogUrl, repoId, package, source)` 隔离。D1 的非敏感设置、客户端当前会话敏感值以及已确认 bootstrap 都按来源解析。只有可信应用 origin 的默认目录加 `keiyoushi` 可获得已审阅的账户同步规则；外仓即使自报官方 package/repoId，也只获得空规则。非空账户写入被拒绝，外仓当前会话值不会进入其它仓库。

## Source 网络政策

代码可以公开准备，Source 网络调用仍需要应用操作员登记。只读 `GET /api/extensions/network-policies?catalogUrl=...&repoId=...` 返回该来源的 `buildId/packageName/bundleSha256` 登记状态。客户端分别展示“代码可准备”和“网络待登记”，打开必须匹配已登记来源、构建和 digest。

网络登记读取属于账户 API，通过已确认身份的业务客户端携带 `X-App-Subject`，服务端核对当前 Access subject；它不复用公开目录的无凭据下载通道。请求绑定业务客户端和连接代次，旧身份的迟到回复不能写入新会话。刷新开始清除该来源的旧就绪结果，普通网络失败保留当前 Source 和账户意图，后续打开须重新读取成功；登录失效或拒绝访问则暂停旧会话并退休管理页，重新确认身份后再打开。

`/api/bridge/http` 每次精确核对 `X-Runtime-Build`、`X-Runtime-Catalog`、`X-Runtime-Repo`、`X-Runtime-Bundle`。buildId 是全局登记主键，跨仓重复 ID 明确冲突，即使 digest 相同也不覆盖。包唯一约束、hosts 继承、退役和同步删除都限定在 `(catalogUrl, repoId)`，默认 CI 不删除外仓登记，也不跨仓继承网络目标。

原型迁移 `0009` 重建无来源的网络政策与 Source 设置表，并撤销旧 Source 设置写入收据。它不保留旧协议回退；部署前须规划重登记；应用该迁移后、实际运行验收前，按当前来源重新登记网络政策。书架、分类、进度、书签和全局账户意图不因此重建。操作命令与发布限制见[扩展发布](../EXTENSIONS.md)。
