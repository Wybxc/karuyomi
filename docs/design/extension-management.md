# 账户扩展与本机准备

Worker API + D1 保存同一身份的扩展使用意图；Static Assets 提供每包最新可用构建；每台客户端独立准备可丢弃代码副本。正式管理入口将这三种状态分开，不用目录可见或缓存命中冒充账户已安装。实施与实际通过范围分别见[计划](../plan/extension-management.md)和[验证](../verification/extension-management.md)。

## 账户合同

`business.proto` 的 `GlobalSettingsValues.installedExtensions` 使用 `InstalledExtension`：

| 字段           | 含义                                 |
| -------------- | ------------------------------------ |
| `catalogUrl`   | 选择构建的仓库目录 URL               |
| `repoId`       | 仓库稳定身份                         |
| `packageName`  | 包身份，也是清单唯一键               |
| `buildId`      | 用户明确选择的精确构建               |
| `bundleSha256` | 该构建 canonical bundle 的完整性身份 |
| `enabled`      | 账户确认的启用意图                   |

清单最多 128 项，package 唯一；同包跨仓库替换需要明确操作，不并装共享业务身份的两个副本。缺记录就是未安装，不自动将目录迁为已安装。字段在 TS/Dart 边界解析，不能只信生成类型。

`catalogUrl` 最长 2048 字符，使用规范化 origin 加精确 `/extensions/index.json`，无 userinfo、query 或 fragment，包括空的 `?`/`#`。网络仓库要求 HTTPS；开发 HTTP 仅允许 literal localhost、127.0.0.1 或 [::1]。当前正式 UI 仅连接部署 origin 的默认仓库，额外仓库添加与网络政策接入仍待实现；预留字段不是已经具备额外仓库能力的证明。

复用现有身份绑定 `SettingsRepository/SettingsController`、全局 CAS 与 mutation UUID；不新增扩展业务数据库或 outbox。修改复制完整已确认全局值，保留主题、阅读偏好和收藏源。安装/更新在准备开始前固定完整值与 revision，准备完成后按原 CAS 提交；发生并发变更时明确冲突，由用户重新读取并确认。

未知 ACK 的任意全局 pending 阻止新扩展编辑，界面可查看整份原内容，只显式重试原 UUID/body/CAS。确认后重取当前状态，不将旧 ACK 当成当前清单；只读刷新、进入页面和恢复前台不隐式 POST。未确认草稿不进入已安装列表。

## 准备与缓存

`control.proto` 增加 `prepareBuild/cancelPreparation/extensionCache/forgetExtensionArtifact/closeBuild`。准备请求带唯一 preparation ID 与完整目录 descriptor，响应给出同一 descriptor、bundle digest 和字节数。控制消息继续使用生成 ProtoJSON 和运行时语义校验；代码字节沿独立有界下载路径。

`VerifiedLoader.prepare` 重新读取当前索引，核对 descriptor 与 manifest，检查共享材料，然后下载/解压/校验 bundle。比较使用生成 Protobuf 消息语义，不依赖 JSON 属性顺序。整个流程不创建 Source Worker、不构造或调用 Source，不执行代码。Web 共享材料来自公开 Static Assets；Native 依照打包 metadata 检查可用性，缺少材料提示更新应用，不从网络补齐内置材料。

manager 同时只允许一个准备，相同 ID/descriptor 复用进行中的结果，其它准备明确 busy；设置 60 秒 AbortSignal 期限。取消按 ID，等待当前操作收尾，防止迟到下载在清理之后重新提交缓存。准备失败不主动终止正在使用的 Source。

代码缓存直接引入 `idb@8.0.4`，在宿主同源 IndexedDB 分存 metadata 与 canonical JS bytes，使用同一事务提交。默认预算为 128 产物 / 256MiB；重复 digest 不重复计费，无 LRU 或多级缓存。缓存记录保存传输验证收据，本地命中核对元数据/字节长度，复用收据而不重算 hash。达到预算后用户清理无用副本再准备。

shared Web Lock pin 覆盖准备/读取与活动运行槽；删除只能取得同 digest 的 exclusive 锁，否则报告使用中。不同宿主实例共享该存储域时也不能误删活动副本。manager 清理先取消并等待自身准备完成；永久 dispose 释放 pin 和 namespace 后关闭 IDB 连接。缓存本身不保存账户权威或 Source 可变数据，不能推断另一台设备已准备，也不承诺浏览器/WebView 永久保留。

## 账户操作与运行槽

- 安装/更新：先准备候选，再提交原 CAS；候选错误或写入未确认不伪报成功。用户点击检查更新只读取当前目录，不改变账户选择；已选择旧 build 不静默换版。
- 启用/停用：只从已确认清单投影状态。停用确认后，后续调用和图片取得禁止继续，关闭已有章节 provider 与对应运行槽。
- 卸载：先确认账户移除，再关闭和清理本机副本。账户结果与本机关闭/清理结果分别显示，失败保留显式恢复入口；其它客户端在既定只读刷新边界读回后收敛。
- 仅准备或清理本机副本：不改变账户意图。清理当前构建要求先退出阅读、释放资源并关闭精确槽；使用中副本不强删。

浏览开包、目录 Source、收藏源和书架打开共用已确认 installed/enabled、仓库、build 与 digest 校验。收藏与书架的稳定业务身份仍是原 package/Source/漫画，不因更新变更；没有安装、停用、未知仓库或下架精确构建都明确提示。调用及章节图片 provider 持续检查当前确认状态，防止已打开入口绕开停用。

`closeBuild` 带预期 buildId/generation。调用方先正常释放 provider、图片资源和活动请求；manager 对尚有请求、队列或资源的关闭明确拒绝，不以强制 terminate 冒充排空。关闭期间拒绝新 open/调用，Worker shutdown ACK 期限为 5 秒；收到精确 ACK 后失效运行槽并等待 namespace 和产物 pin 释放。失败时回收但报告失败；相同已完成关闭可幂等确认，迟到旧代关闭不能影响新代。

卸载只移除账户成员和本机代码副本，保留书架、分类、进度、书签、收藏源、Source 数据与 HTTP Cache，不清空 IndexedDB/WebView。共享 materials 不进入逐扩展代码缓存。未来若有“清除来源数据”，需另设明确操作及 namespace 所有权，不能混入普通卸载语义。

## 当前构建与可用性

Static Assets 只保留每包最新可用构建。账户选择的旧 build 可能已无产物或网络登记；即使本机缓存命中，也不能保证它仍可联网。网络登记缺失的 `404 build_not_found` 与 Access 登录/权限错误分开，界面要求用户手动更新，不恢复历史目录或兼容协议。

本轮没有变更静态发布方式、启动新 AOT 或部署。目录元数据已于 `830161c` 接入，但管理功能及协议需要相同固定输入的新构建另行验收；下载、组件和工程构建不提升 `compiled_unverified/runtimeReady=false`，也不代替实际 Source 或三端同步证据。

## 失败恢复

清理失败保留原资源身份和占用，失败的进行中 Future 不能永久阻止重试；只有 ACK 成功才确认释放。页面会话关闭、Dart 图片释放与 Native 文件删除均按原身份重试。未知业务写响应沿原全局 UUID/body/CAS 恢复；普通业务 API 网络失败不使无关 Source 运行槽失效，Access 失败仍沿原暂停流程处理。

Worker shutdown 失败或超时仍报告未确认，并回收该运行槽；重复旧 close 不伪造 ACK。管理页提供独立的显式重建恢复：仅对仍为原 build/generation 且账户已确认不可用的运行槽，先成功关闭 provider，阻止新操作，再等待既有重建协议确认与产物/namespace 引用释放，最后清理旧会话。迟到恢复不能清除新一代会话。Native 的实际 reset 仍须平台验收。
