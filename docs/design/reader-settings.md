# 非敏感阅读设置

本轮同步现有阅读能力的三项偏好：应用主题、阅读模式和页组选择。Worker API + D1 是唯一业务权威，Web/iOS/Android 共用 `business.proto` 生成模型与标准 ProtoJSON。本轮不表示完整 P1 阅读设置已经完成；适宽/适高、裁白、阅读背景/应用内亮度和可配置输入继续保留在 [P1](../plan/p1-library-and-progress.md)。

## 全局默认与漫画覆盖

| 偏好     | 有类型的取值                                         | 作用域                              |
| -------- | ---------------------------------------------------- | ----------------------------------- |
| 应用主题 | SYSTEM / LIGHT / DARK                                | 全局；SYSTEM 由各端跟随本机系统外观 |
| 阅读模式 | LEFT_TO_RIGHT / RIGHT_TO_LEFT / CONTINUOUS / WEBTOON | 全局默认，可逐漫画覆盖              |
| 页组     | AUTO / SINGLE / DOUBLE                               | 全局默认，可逐漫画覆盖              |

全局默认是 SYSTEM、LEFT_TO_RIGHT、AUTO。AUTO 由客户端按实际可用宽度决定单双页，不同步设备宽度或当前计算结果；连续/Webtoon 不显示双页，但仍保留偏好，以便恢复分页模式。

漫画覆盖使用 `ReaderSettingsOverride` 的 optional 字段。字段缺省表示继承全局；显式 AUTO 表示覆盖为自动布局，不能当成继承。提交完整覆盖文档，未包含的字段恢复继承；空 `overrides` 清空全部覆盖。应用主题没有漫画覆盖。全局变化会改变未覆盖字段的有效值，但不会修改漫画覆盖的 revision。

章节来源顺序已经随 `MangaResume.reversedOrder` 由进度链路保存，不再建立第二份设置权威。当前缩放/平移矩阵、视口尺寸、工具栏显隐、服务连接地址和平台资源状态不进入同步设置；Source 密码、token、Cookie 也不混入本协议。

## API 与原子状态

- `GET /api/settings` 返回全局设置与有效阅读默认值。
- `GET /api/settings/manga/:mangaKey` 用同一 SQL 快照读取全局、该漫画覆盖与 account revision，并返回合并后的 `effectiveReader`。不存在覆盖时仍返回该漫画的 revision 0 和空覆盖；读取不建行，也不要求收藏或写入漫画资料。
- `POST /api/settings/mutations` 接受 `setGlobal` 或 `setManga`，请求带 UUID 与目标作用域的 `expectedRevision`。沿用受信 Access subject、绑定身份的 `X-App-Subject`、Origin、写标识和业务正文预算。

全局和每漫画各有独立 revision，避免普通阅读进度或另一漫画设置造成无关 CAS 冲突；成功写入统一提升 account revision，不改变漫画业务 revision、进度、resume 或 epoch。`reader_settings` 按 subject 和作用域唯一，清空覆盖保留空文档及递增 revision，旧请求不能复活覆盖。

设置值、作用域 revision、account revision 和 `kind=settings` 的幂等结果经条件 SQL、唯一约束及 nonce gate 在同一 D1 batch 提交。确认响应在事务最后读取当前全局/覆盖并计算有效值，避免另一作用域并发变化时拼接旧默认和新 account revision。相同 UUID/正文返回原确认；同 UUID 不同内容或跨业务消息复用明确冲突。

## 客户端确认与恢复

每个作用域的编辑基于已确认 revision，首次发送后 UUID、正文和 CAS 固定。不确定写入只显式重试原命令，只读刷新不能偷偷重发；确定冲突后重新读取当前作用域再编辑。幂等成功仅证明原写入发生过，客户端重新 GET 当前作用域并核对提交值，不能用旧确认覆盖其它端之后的修改。

全局与漫画设置读取、合并和 UI 应用须保持身份绑定；服务/身份变化使旧编辑失效，迟到结果不能更新新会话。布局设置变化保持原图逻辑锚，不能把设置刷新当成跳到另一设备阅读位置。请求失败仍可继续已加载阅读；未确认草稿只保存在当前会话，不承诺关闭后恢复。

全局设置页显式提交完整偏好，未编辑的表单跟随新确认快照；开始编辑后保留最初 revision，不能因后台刷新悄悄抬高 CAS。阅读页快捷选择保存为漫画覆盖，弹窗允许每项“跟随全局”；AUTO 始终保留显式 presence。待确认时禁用设置编辑和提供原操作重试，已加载阅读可继续。重新打开编辑器显示待确认命令的实际值。

连接确认、进入设置页、恢复前台和同身份重连时只读刷新。全局确认变化触发当前漫画重新读取有效设置，保留显式覆盖；来源顺序继续由阅读进度管理。父级应用设置、窗口变宽及切章不产生保存回调，迟到 viewport 数据不能覆盖父级偏好。成功确认的设置从服务端恢复，不在客户端另建权威偏好文件。

实施状态见 [P2](../plan/p2-sync.md)，证据与实际平台限制见[设置记录](../verification/reader-settings.md)。
