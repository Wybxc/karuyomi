# 收藏源与快捷打开

收藏源是同一身份在 Web/iOS/Android 之间共享的非敏感全局设置。Worker API + D1 是唯一业务权威；客户端只保存已确认视图和当前会话未确认的原操作，不建设独立收藏数据库。实施状态见 [P3](../plan/p3-extensions-and-migration.md)，工程证据与独立运行门见[验证记录](../verification/source-favorites.md)。

## 身份与权威状态

`business.proto` 的 `FavoriteSource` 保存 `packageName/sourceId/sourceName/sourceLang`。`packageName + sourceId` 是组合身份；Source ID 保持精确的有符号 64 位整数字符串，同一个 ID 出现在不同包中不会碰撞。名称和语言是显示快照，不参与身份；不记录 buildId、版本、generation、Source 登录信息或 Cookie。

列表位于 `GlobalSettingsValues.favoriteSources`，最多 128 项，组合身份不能重复。达到上限时禁止新增并说明原因，仍可打开或取消已收藏的来源。双端运行时解析同时检查字段、Source ID、条目数量和唯一性；不能只依靠生成类型。列表复用 `reader_settings` 的全局 JSON、subject 分区、global revision 与 account revision，不增加表或专门 API。

`GET /api/settings` 返回已确认列表；`POST /api/settings/mutations` 的 `setGlobal` 提交完整全局值。收藏与取消都从已确认快照复制全部值，只改变对应来源；主题和全部阅读偏好必须保留。全局设置页同样保留收藏列表。收藏源和其它全局偏好共享 CAS，另一端修改后旧编辑明确冲突，重新读取、确认后再编辑，不自动合并覆盖。

## 正式浏览入口

浏览页提供“收藏的漫画源”，展示已确认列表，并允许收藏/取消当前已加载扩展中的 Source。未确认的改动不提前进入已保存列表；原操作内容与已确认列表分开展示。不可用的来源仍保留记录，用户可以明确取消收藏。

快捷打开从当前会话已读取的 Static Assets 索引按 packageName 定位构建，再加载 manifest、打开正式运行时、确认原 Source ID 并取得该源列表。收藏不固定旧构建；需要最新远端索引时使用现有“重新连接”。缺包、缺 Source 或请求失败都明确提示，不按名称选其它源，也不回退到隐藏的历史构建。

打开的各阶段共用一次 busy 操作；页面、身份、设置 client、运行时 epoch 和 Source 引用必须仍有效。重复点击不能交错选择来源，页面离开或身份变化后不能继续加载旧源的漫画列表。Source 请求沿正式运行时、HTTP 与存储语义执行，不为快捷入口另建网络路径。

## 确认、冲突与恢复

收藏与设置共用现有 `SettingsRepository/SettingsController` 的确认链路。首次发送后 UUID、正文和 CAS 固定，丢响应只由用户显式重试原命令；重建面板或 repository 包装仍使用同一身份 client 的 pending。原操作可能包含主题、阅读偏好和收藏列表，重试前必须能查看完整内容，不能把其它设置改动伪装成单独的收藏操作。

只读刷新与恢复前台不重发写入。确定冲突后重新读取当前全局值，才解除已拒绝草稿；不确定写入仍保留原请求。幂等 ACK 只证明原写入发生过，成功后重新 GET 并核对当前完整值，另一端之后取消的收藏不能被旧 ACK 复活。关闭身份后丢弃迟到 ACK，不通知新身份的界面。

本次不实现全目录语言筛选、跨源搜索、typed filters/preferences、扩展安装或源迁移。当前静态索引没有完整 Source 名称/语言；收藏快照和已加载 `SourceInfo` 不能冒充全目录元数据。业务协议与生成文件变化仍进入正式 host 输入指纹，工程检查不代表扩展 AOT baseline 已重新完成。
