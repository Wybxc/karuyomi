# P2 多端同步与服务端权威状态

## 目标与状态

**多端同步是首要设计目标和当前实施主线。** 同一部署、同一身份在 Flutter Web、iOS 和 Android 共享书架、分类、阅读进度、书签和非敏感设置。Worker API 负责业务读写，D1 保存唯一权威状态；功能从数据模型、协议到 UI 都按多端共同使用设计，不先完成一套独立本地产品再补同步。

状态：**收藏与阅读进度的服务端底座已接入，工程检查、正式 Web/API 构建、真实 Web 独立会话及测试身份下三端组合的双向非默认页续读已通过；已部署生产并通过匿名静态/API访问边界检查，已确认生产 Web 恢复登录与真实 Source 热门列表，三端同身份读写待验收**。Codex 内置浏览器与正式 iOS/Android `app.main()` 经真实隔离 workerd/D1，完成收藏读回、真实图片、双方保存和非默认页恢复，回看最远进度不倒退，见[Web/iOS 证据](../verification/native-server-state.md)和[Android 配对证据](../verification/android-server-state.md)。同 origin Web 独立会话另见[证据](../verification/server-state.md#真实-web-独立会话闭环)。`business.proto`、D1 业务表、受信身份 API 与共享 Dart 会话客户端已接入正式产品入口，本地业务 SQLite 和对应 Web 资产已移除。双 iOS 模拟器及 Android 前台恢复 / iOS 重置的阅读 epoch 冲突已过；Android 模拟器的阅读断连与显式重试、iOS 续读已通过[分项](../verification/concurrent-server-state.md#android-已加载阅读断连与显式重试)；阅读进度已提交后丢确认与原样重试已在 [Web](../verification/concurrent-server-state.md#web-阅读进度已提交后丢确认)、当前 v6 的 [iOS](../verification/concurrent-server-state.md#ios-模拟器阅读进度已提交后丢确认)和 [Android](../verification/concurrent-server-state.md#android-模拟器阅读进度已提交后丢确认)模拟器通过；双 iOS 模拟器的阅读进度同时写已通过，其它平台配对、前台重取、其余故障恢复、真机及生产 Access 正向继续验收；分类协议、D1 原子读写与 Flutter 数据层已实现并通过组件/真实 D1 检查；分类管理、筛选与多关联 UI 已实现，真实双 Web 分类分项已通过；双 iOS 与 iOS↔Android 分类顺序闭环、Web 分别与双端模拟器的分类创建／关联、改名／关联与新 Web 文档读回均已通过，混合平台剩余分类操作、Android 初始化可靠性、章节书签、范围已读/未读与同步阅读设置（含裁白）的独立客户端验收继续推进；自定义封面已通过独立 Web 往返，Native、故障及生产私有 bucket 绑定与部署待验。`P2` 保留主题编号，执行顺序前移，与 [P1](p1-library-and-progress.md) 一起交付；[P0](p0-runtime-and-reading.md) 的会话、Source 和真实阅读验收仍须完成。

## 权威来源与初版边界

[双 iOS 模拟器阅读进度同时写](../verification/concurrent-server-state.md#双-ios-模拟器阅读进度同时写)已通过。两端以相同 revision 打开真实第 2 页；完成与重置在同一 D1 基线上得到一次确认和一次冲突。冲突端可翻动原画面而不覆盖服务端，显式重开后恢复到新 epoch 的第 1 页。其它平台配对和正式 Reader 的完成获胜分支继续验收。

双 Reader 验收准备时发现，恢复已确认的同一章节会发送内容未变的保存；修正后 iOS 首帧重排仍可能只改变视口放置并触发保存。已补齐控制器去重和确认续读的首帧保留策略：原图点仍可见时保留已确认的放置偏好；实际导航、原图点修正和新观察仍可提交。[回归与首轮实际结果](../verification/concurrent-server-state.md#双-ios-阅读器的开章基线)已记录，修复后的两端开章都未推进共享 revision。

- 所有客户端经同一 Worker API 读取与修改 D1 状态，服务端只使用校验后的 Access 身份确定归属。客户端内存保存已读取的状态和当前会话草稿，不能把本地写入成功显示为云端保存成功。
- 初版直接读取当前状态，集合使用有界分页；进入页面、恢复前台、恢复连接以及显式刷新时重新读取并按 revision 收敛。先验证两端在线闭环，不以前端持久数据库、outbox、增量 change log、cursor 或 DO 实时通知为前置条件。
- 请求失败或 Access 失效时保留当前已加载阅读和内存草稿，明确“未保存”并允许同一身份重试。关闭应用前未获服务端确认的修改不承诺恢复；新客户端或重启后从 D1 重新读取已确认状态。
- 同步只保存当前业务状态，不生成阅读历史、时长或统计事件；不传阅读图片、下载任务和源站密码/token/cookie。用户自定义封面是独立的私有二进制上传，D1 只保存当前业务引用，不把图片嵌入控制消息。扩展缓存、Source 普通文件/HTTP Cache、图片资源继续按各自生命周期管理，不成为书架或进度的业务权威。
- Protobuf `.proto` + Buf 是 Worker TypeScript 与 Dart 业务协议的唯一来源，使用生成模型、标准 ProtoJSON 与正式运行时校验；继续落实请求大小、身份、版本和迟到结果约束。
- 增量读取、推送通知或只读持久缓存只有在功能闭环通过、实测显示需要后再评估；不恢复离线优先或持久待提交队列作为默认架构。

## 当前实现与剩余主线

- 已接入 `GET /api/library`、`GET /api/state/manga/:mangaKey`、`GET /api/state/manga/:mangaKey/progress` 和 `POST /api/state/mutations`。书架每页 8 部作品，章节进度每页最多 64 项并固定 account revision；请求上限 128 KiB、响应上限 2 MiB；清单最多 2048 个稳定 pageKey，完整 Source memo 保持不透明文本。
- D1 按 Access subject 隔离 account/manga revision、分章进度与 mutation 结果；条件 SQL、唯一键和 nonce gate 在同一 batch 内提交。客户端固定首次请求的 mutation ID/正文，丢响应时复用，CAS/epoch 冲突明确停止旧视图写入。
- 正式 Flutter 入口共用 `BusinessStateClient`，收藏与进度仅保存服务端确认状态；未确认进度只留当前会话，同一服务和身份恢复后重绑 API 再重试。书架进入、前台恢复、重连和手动刷新重取；本地搜索/排序只处理已确认视图。
- Web 登录改为独立窗口，保留原页面与草稿；重新 bootstrap 确认身份前不提交旧身份草稿，恢复后只提交当前身份的 writer。进度冲突不能由收藏或书架刷新解除，旧幂等成功须核对当前权威状态。
- 阅读中的章节保持当前页面；后台尽力提交、恢复前台和显式刷新已接入。刷新先用当前视图的 revision 提交未确认草稿，再只读检查服务端；发现其他端修改进度、epoch 或继续阅读状态时，保持画面并停止旧视图写入，用户明确“重新打开本章”后才采用服务端位置和章节顺序。书架或详情读取不能替旧阅读视图推进写入基线。两个实际 Web 文档经同一隔离 D1 已通过手动刷新保持画面、远端 epoch 重置、停止旧视图写入、未先刷新时正式写路径冲突及明确重开恢复，见[双会话证据](../verification/concurrent-server-state.md)。双 iOS 模拟器经同一受信 HTTPS / D1 通过真实系统前后台：A 保持原进程与旧第 2 页，无手刷自动提示 B 的 epoch 重置；旧叶翻页未覆盖 D1，显式重开后恢复第 1 页真实图。见[双 iOS 证据](../verification/concurrent-server-state.md#双-ios-模拟器前台-epoch-冲突)。[Android A 前台恢复、iOS B 重置](../verification/concurrent-server-state.md#android-前台恢复与-ios-重置同一账户)也通过同进程/任务恢复、旧叶翻页六路 D1 状态不变和明确重开。Web、其它设备组合及生命周期场景继续验收。
- 测试身份下 Web↔iOS、Web↔Android、iOS↔Android 的基础书架读回、真实阅读和双向非默认页续读已通过；继续生产 Access、真机、其它平台的阅读前台重取、其它断连恢复及其它平台配对的同时写竞争。Android 模拟器已通过到验收服务的实际断连：已加载图片仍可阅读，断连时显示未保存且权威状态不变，恢复后显式重试确认，独立 iOS 模拟器可续读。分类与章节书签已采用同一权威模型；非敏感阅读设置的协议、D1 和正式 UI 已接入，集中工程检查与全局设置双 Web/双 iOS/Android↔iOS 分项及 Web↔iOS、Web↔Android 模拟器双向读写通过，iOS→Android→iOS 的单作品模式、页组与裁白覆盖和清空已通过，Web↔Native 漫画覆盖、其它字段及故障门待验。模拟器正式入口分项不等于 Native 视觉、触控或真机验收；真实平台验收仍按下方完整条件，组件共享测试服务不能替代。

分类数据层已支持目录增删改名/排序和漫画多分类。目录使用独立 revision，关联写同时校验漫画与目录 revision；删除按实时关系原子提升受影响漫画 revision，取消收藏保留分类关系。Dart 使用独立目录队列和精确 mutation 重试，目录与书架一次发布确认快照。数据层证据见[分类数据记录](../verification/category-state-data.md)。管理、排序、筛选与多选关联 UI 已接入；未确认命令显式继续，固定编辑 CAS，服务或身份变化使旧编辑永久失效。真实双 Web 已通过双向目录/关联读回、筛选、旧编辑目录冲突、删除与页面重载恢复，见[分类 UI 记录](../verification/category-ui-sync.md)。双 iOS 与 iOS↔Android 的正式入口分类顺序闭环也已按同一记录通过。Android 最后读阶段曾出现 DDS/容器初始化失败，仅冷启动后原阶段通过，根因仍未修复；Web 分别与 iOS、Android 模拟器的创建／关联、改名／关联、独立新 Web 文档读回和筛选已通过，每组均使用同一隔离 D1 的两个回环入口。继续混合平台删除、重排与同一 HTTPS origin、Android 初始化可靠性，以及章节书签、漫画设置覆盖与混合平台的独立客户端读回，实际网络故障和生命周期门仍分别验收。

章节书签的协议、D1 原子读写、有界查询、共享 Dart 数据层和正式详情/阅读入口已接入。详情可标记、移除并筛选章节，阅读页可标记当前章；取消收藏或重新阅读保留书签。未确认命令只显式精确重试，旧幂等响应核对当前章，当前 Source 列表中消失的章节不猜匹配。设计见[章节书签](../design/bookmarks.md)，工程和组件证据见[记录](../verification/bookmarks.md)。真实 Web 独立文档及 iOS ↔ Android 模拟器的添加、读回、移除与再次读回已通过；Web ↔ Native、生产及真机运行门继续验收。按用户要求优先推进功能完整性，再集中补齐跨端与恢复验收；Android 间歇初始化继续保留独立待办，不扩大诊断范围阻塞功能。

非敏感设置本轮同步已有的全局主题、四种阅读模式和 AUTO/SINGLE/DOUBLE 页组，阅读字段支持逐漫画覆盖或继承。协议、独立作用域 CAS、D1 原子确认快照及幂等 API 已接入，Dart 仓储、正式设置/阅读 UI 与集中工程检查通过，见[设置设计](../design/reader-settings.md)与[证据](../verification/reader-settings.md)。清空覆盖保留 revision，不因普通进度写入冲突；全局设置已取得双 Web、双 iOS 与 Android↔iOS 顺序往返及新文档/进程恢复证据，双 Web 旧 CAS 拒绝与明确重读也通过；两个正式 Web 文档的同 revision 全局设置保存已通过[同时写竞争、读回与重编辑](../verification/reader-settings.md#双-web-全局设置同时保存)，Native 与其它写入类型的竞争另验；Web 全局设置的真实丢确认、独立文档读回与精确重试已通过[分项](../verification/reader-settings.md#2026-11-07web-全局设置的真实确认丢失与原样重试)；[iOS 和 Android 模拟器](../verification/native-settings-ack.md)分别通过全局主题已提交后丢确认、同会话重读取值及精确重试，独立 HTTPS 快照与 D1 审计确认各只提交一次；第二 Native 客户端读回另验；同一 HTTPS/D1 的双 iOS 模拟器已通过[全局设置前台自动重取](../verification/reader-settings.md#2026-11-07ios-模拟器回到前台自动读回全局设置)：另一端在当前应用真实后台时保存，原进程回到前台自动更新原编辑器和主题。随后 [Android 从 iOS 保存读回](../verification/reader-settings.md#2026-11-07android-模拟器回到前台读回-ios-保存)也通过真实后台和同一 Android 进程/任务恢复。[Web↔iOS 模拟器双向设置读写](../verification/reader-settings.md#web-与-ios-模拟器双向读写)及 [Web↔Android 模拟器双向设置读写](../verification/reader-settings.md#web-与-android-模拟器双向读写)已通过同一隔离 D1 的两个回环入口。[单作品覆盖 iOS→Android→iOS](../verification/reader-settings.md#ios-与-android-模拟器单作品设置覆盖)已通过：iOS 保存阅读方向、页组和裁白显式关闭，Android 读回并清空，新 iOS 进程恢复继承，全局、另一作品及完整进度保持不变。Web↔Native 漫画覆盖、其余字段、Web 前台、其它故障恢复、生产及真机设置门仍待验收。背景、应用内调暗及点击区/键盘预设已沿同一合同、D1、表单和阅读链路接入，见[后续设置记录](../verification/reader-appearance.md)，独立客户端门待验；完整显示/适宽/适高、原图二维锚及视口锚已接入同一合同、D1 和正式阅读链路，见[适配记录](../verification/reader-fit.md)。原图 x 不参与最远进度排序，独立客户端和平台恢复门待验。裁白已实现并沿同一协议、D1 和全局/漫画设置表单应用到正式 Reader，全局默认关闭，漫画缺省继承、显式 false 关闭；确认快照、独立作用域 CAS 与原请求重试语义保持一致。全局裁白开关的独立客户端读回和恢复分项见[设置记录](../verification/reader-settings.md)，模拟器间的单作品裁白显式 false 与缺失继承已验，实际裁白阅读效果、Web↔Native 漫画覆盖及其余平台仍待验收；工程范围与验收门见[裁白记录](../verification/reader-crop.md)。后续仍按 [P1](p1-library-and-progress.md) 的日用流程与错误恢复实际缺口推进。

设置重连恢复已补齐：同服务（含尾斜杠）保留业务客户端和待确认原命令，重新 bootstrap 核对身份后只读刷新；Native 无效地址先由正式平台构造器拒绝，保留旧会话和显式精确重试入口，未采用的候选负责释放。真服务或身份变化仍隔离旧命令。受控正式 AppShell 回归覆盖丢 ACK 后同服务重连、无效地址、原 UUID/CAS/正文重试及身份隔离，证据见[设置记录](../verification/reader-settings.md)；不据此提升真实设备故障恢复验收门。

业务 API 的 Access 失效恢复已补齐正式宿主控制错误路径：当前私有请求的 401/403、登录重定向与 HTML 触发既有 Dart 运行时事件和登录/拒绝状态，零 Source 也适用；已发布图片保留释放语义，迟到旧 generation 不暂停新会话。设置认证恢复保留原命令，只读核对后仍须显式精确重试。工程与受控组件证据沿[设置记录](../verification/reader-settings.md)维护，实际生产 Access 续期和设备故障恢复继续单独验收。

自定义封面已实现，独立 Web 文档的上传、替换、清除及顺序读回通过。私有 R2 保存正文，D1 当前引用经作品 CAS 和幂等确认；multipart 的二进制上传与同一 mutation 一次确认，清除沿现有 JSON mutation，客户端固定原 UUID、CAS、正文和字节进行明确重试。相同业务会话重建仓储保留未确认原操作，旧 ACK 需要当前权威读回，关闭或身份变化后拒绝迟到结果。普通源元数据、收藏、分类和进度修改保留封面；旧对象与失败候选经至少一小时宽限后显式清理，不在修改时即时删除。设计见[自定义封面](../design/custom-covers.md)，Web 实际结果与剩余 Native/故障/生产部署门见[验证记录](../verification/custom-covers.md)。

书架批量操作复用单漫画 API，逐本串行确认，不增加跨漫画原子事务。确认清单冻结漫画与目录 revision；分类操作保留其它关联，移出书架不覆写元数据或清除进度。首失败停止，未确认项只能精确重试，剩余项须明确继续；已拒绝项只读刷新后结束旧批次，再重新确认。会话草稿以业务客户端为归属，同客户端 wrapper 重建保留恢复入口；旧窗口失效后不得续发或导航。[双 Web 真实 D1 验收](../verification/library-batch.md#双-web-部分提交与冲突恢复)已通过批量添加分类的部分提交、旧 CAS 拒绝及重新确认；其它批量操作、Native/混合平台、断网/丢响应和生产仍须另验。设计见[批量操作](../design/library-batch.md)。

章节范围已读/标未读已复用现有进度表和作品 mutation，允许无真实锚的独立 epoch/已读状态；普通进度跨 manifest 保留章级已读值，标未读或重新阅读才清除。详情筛选、多选及范围确认已接入，串行 CAS 链、原请求重试、显式继续与旧窗口退役见[设计](../design/chapter-read-state.md)。真实 Web 独立文档及 iOS ↔ Android 模拟器的范围已读与标未读往返通过；同页收藏后的旧版本误冲突已修复并通过新构建复验，见[验证记录](../verification/chapter-read-state.md)。Web ↔ Native、Reader 与详情同时写、部分提交及丢响应恢复、生产与真机待验。

书架直接续读和详情失败恢复沿用现有权威状态与正式 Reader：只按当前章节键定位，恢复时区分已确认视图和当前会话草稿；续读只读重取不 flush，附带资料更新不隐式重放原 pending，资料失败单独显式重试。设计见[阅读入口](../design/reading-entry.md)，功能及验收状态以 [P1](p1-library-and-progress.md#下一功能里程碑) 和[验证记录](../verification/reading-entry.md)为准。

2026-11-07，固定 `5ba6fff` 的日期修复通过实际无插桩 xkcd 重开，Web 同源同身份的书签添加、读回、移除及第三文档读回通过；重开不推进共享 revision。同一隔离 HTTPS / D1 的正式 iOS ↔ Android 模拟器也已完成相同往返，两次跨端读回业务快照不变。同一 HTTPS origin 的内置浏览器证书信任仍阻断 Web ↔ Native 门，生产与真机另验，见[书签记录](../verification/bookmarks.md)。

## 实施顺序

1. **先固定跨端合同与 D1 模型。** 定义漫画/收藏、章节引用、分类、多分类关联、书签、设置、当前继续阅读位置及最远进度；保留原 Source URL、字符串 ID、稳定作品/章节键和完整 Manga 快照。定义有界查询、mutation ID、服务端 revision、预期 revision、写入结果和冲突响应。D1 使用受支持的 batch、条件 SQL 和唯一约束保证业务修改、幂等结果及 revision 原子提交，Worker 不能以内存持有权威状态。
2. **完成最小跨端业务闭环。** 先接收藏列表/增删与当前/最远阅读进度：A 端写入并收到服务端确认，B 端重取后显示同一状态，B 端继续阅读后 A 端可恢复。一起替换 P1 的本地书架和进度入口；直接移除本地权威读写，不保留双写、旧数据库导入或兼容路径。初版使用当前状态全量或有界分页读取，返回可判断新旧的服务端 revision；分页发现 revision 改变时重新取当前状态，不拼接不同版本为一份快照。
3. **落实幂等与并发。** 每次用户操作及每份节流进度草稿在首次提交时取得 mutation ID，服务端幂等记录按受信身份隔离；响应丢失后重试复用该 ID，服务端返回同一结果，不重复执行。收藏、分类、设置和删除使用预期 revision 条件写入；冲突返回当前权威状态，重新读取后按操作语义处理，不能盲目重放旧整份状态。删除也保留足以拒绝旧 revision 写入的约束，避免迟到请求使项目复活。
4. **落实阅读语义。** 同一 epoch 内最远进度只前进，当前回看位置单独保存；不能直接比较不同 manifest 的旧页码。标为未读/重新阅读由服务端原子提升 epoch，旧 epoch 提交不能覆盖 reset；并发 reset 或当前继续阅读位置冲突按服务端 revision/明确冲突处理，不用客户端时钟裁决。其它设备的进度可显示为新的继续阅读位置，不强制跳转当前正在阅读的页面。
5. **按分类 → 书签 → 非敏感设置扩展。** 每项从 Protobuf 合同、D1 原子读写到 Flutter UI 一起交付，复用同一读写确认路径；每项都包含第二客户端读回验收门，功能从协议、D1 到正式 UI 一起实现；当前按用户要求优先补齐功能，再集中取得跨端证据，不能把未验收的工程实现标为已通过。分类包含目录排序及多分类关系；完成这些基础同步功能后，再完善 P1 搜索/过滤/批量操作等外围 UI。Source 登录凭据及平台专属临时状态不混入同步设置。
6. **完成恢复与实际环境验证。** 覆盖断网/重连、服务端已提交但响应丢失、重复/乱序提交、两客户端并发、删除、epoch reset、Worker 重建、D1 错误及 Access 恢复。前台重取必须独立于通知正常收敛；同身份恢复可重试当前会话草稿，身份/服务变化立即停用旧草稿，迟到响应不能污染新身份。

## 验收

- 至少两个独立客户端会话验证 A→B、B→A；Web↔iOS、Web↔Android 和 iOS↔Android 均记录实际环境，不能用同一进程两个 repository 或模拟 supplier 代替。收藏、分类、书签、设置及已确认阅读位置在另一端与客户端重启后从 D1 恢复。
- 先证明真实“收藏 → 另一端书架 → 详情 → 阅读 → 另一端继续阅读”闭环，再扩大外围功能；P1 日用功能验收包含该闭环。
- 服务端确认是“已保存”的唯一依据；响应丢失后使用同一 mutation ID 重试只执行一次。并发写入有明确 revision 冲突，最远进度不倒退、旧 epoch 不覆盖 reset、删除不因旧请求复活。
- 断网或 Access 失效不阻断已经加载的阅读，未确认状态显示准确并可在当前会话重试；应用关闭后的未确认草稿不冒充已保存。重新连接、前台重取和手动刷新能看到服务端当前状态，不依赖 DO 通知。
- 不同 subject/部署 origin 的数据、草稿和迟到结果隔离；生产 Access、实际浏览器、Native UI 与真机证据分别记录。
- 不扩展为离线阅读、持久离线操作合并、后台任务、历史事件、文件归档或敏感凭证同步。性能优化不能先于基本多端功能验收。
