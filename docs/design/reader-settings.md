# 非敏感阅读设置

同步设置覆盖应用主题、阅读模式、页组、阅读背景、应用内调暗、点击区与键盘预设。Worker API + D1 是唯一业务权威，Web/iOS/Android 共用 `business.proto` 生成模型与标准 ProtoJSON。完整 P1 的适宽/适高与裁白仍按 [P1](../plan/p1-library-and-progress.md) 推进；实现与验收状态分别维护。

## 全局默认与漫画覆盖

| 偏好       | 有类型的取值                                         | 作用域                              |
| ---------- | ---------------------------------------------------- | ----------------------------------- |
| 应用主题   | SYSTEM / LIGHT / DARK                                | 全局；SYSTEM 由各端跟随本机系统外观 |
| 阅读模式   | LEFT_TO_RIGHT / RIGHT_TO_LEFT / CONTINUOUS / WEBTOON | 全局默认，可逐漫画覆盖              |
| 页组       | AUTO / SINGLE / DOUBLE                               | 全局默认，可逐漫画覆盖              |
| 阅读背景   | BLACK / WHITE / THEME                                | 全局默认，可逐漫画覆盖              |
| 应用内调暗 | 0–80 的整数百分比                                    | 全局默认，可逐漫画覆盖              |
| 点击区     | STANDARD / REVERSED / DISABLED                       | 全局默认，可逐漫画覆盖              |
| 键盘       | STANDARD / REVERSED / DISABLED                       | 全局默认，可逐漫画覆盖              |

全局默认是 SYSTEM、LEFT_TO_RIGHT、AUTO、BLACK、调暗 0%、STANDARD 点击区与 STANDARD 键盘。AUTO 由客户端按实际可用宽度决定单双页，不同步设备宽度或当前计算结果；连续/Webtoon 不显示双页，但仍保留偏好，以便恢复分页模式。

漫画覆盖使用 `ReaderSettingsOverride` 的 optional 字段。字段缺省表示继承全局；显式 AUTO 表示覆盖为自动布局，不能当成继承。提交完整覆盖文档，未包含的字段恢复继承；空 `overrides` 清空全部覆盖。应用主题没有漫画覆盖。调暗覆盖的显式 0 表示不调暗，与缺省继承不同；D1 计算有效值时以字段 presence 合并，不能按数值真假选择默认值。全局变化会改变未覆盖字段的有效值，但不会修改漫画覆盖的 revision。

章节来源顺序已经随 `MangaResume.reversedOrder` 由进度链路保存，不再建立第二份设置权威。当前缩放/平移矩阵、视口尺寸、工具栏显隐、服务连接地址和平台资源状态不进入同步设置；Source 密码、token、Cookie 也不混入本协议。

## 阅读内容与输入

背景使用黑色、白色或当前应用主题的背景色，相应状态文字保持可读。应用内调暗只给阅读内容叠加 0–80% 黑色遮罩；分页、连续/Webtoon 与独立图片放大窗口使用同一确认偏好，打开的放大窗口也跟随设置更新。工具栏、设置与显式导航仍保持可操作，不申请系统亮度权限。偏好变化不重新获取图片、替换章节或伪造观察位置。

点击预设用于分页模式的左右区域：STANDARD 沿阅读方向翻页，REVERSED 反转左右区域，DISABLED 关闭区域翻页；中央工具栏切换始终保留。滑动翻页与连续滚动维持各模式原有语义。

键盘预设覆盖方向键、PageUp/PageDown、空格、Home/End。STANDARD 保留现有方向语义；REVERSED 反转相对翻页，Home/End 仍定位绝对首末；DISABLED 消费这些阅读导航键而不导航。设置表单和其它路由的键盘交互不受影响。显式导航按钮始终保留，偏好变化保持当前图像逻辑锚与真实末页观察规则。

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

实施状态见 [P2](../plan/p2-sync.md)，原有三项设置证据见[记录](../verification/reader-settings.md)，阅读外观与输入的工程范围及实际平台限制见[后续记录](../verification/reader-appearance.md)。
