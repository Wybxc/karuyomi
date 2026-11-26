# Source 设置与多端确认

## 范围

正式协议位于 `protocol/karuyomi/v1/{control,business}.proto`。Host ABI 为 `karuyomi-source-host-v6`；原型直接更新当前 ABI，不为旧 AOT 加兼容路径。实现与平台验收状态见[计划](../plan/source-preferences.md)，工程及运行证据见[验证记录](../verification/source-preferences.md)。

设置编辑执行原 Source 的 `ConfigurableSource.setupPreferenceScreen` 和 Preference listener。已审核的账户值以 Worker API + D1 为唯一权威。其它值和凭证在当前设备保存，由用户使用同一账户重开应用时恢复。普通业务 API 只接收账户分区。

## 控制合同

`getPreferences` 返回有界 `PreferenceSnapshot`，包含当前 `snapshotId`、递归 nodes，以及实际 SharedPreferences 的两个完整分区 `syncValues` / `sessionValues`。描述支持开关、文本、单选、多选、分组、动作和明确不支持的项；保留标题、summary、enabled、visible、默认值及同步范围。

设置页以 Cupertino 分区呈现原树，保留分组、子组与空分组的标题。组的禁用状态传到子控件，选择行的标签、当前值和辅助功能状态一起反映可用性。显示分区和筛选可见项目均保留叶节点在原描述中的索引路径。

`editPreference(snapshotId,path,change|click)` 一次只修改一个原控件或执行一次原点击 listener，返回 `accepted`、`clickHandled` 和更新后的快照。路径绑定原 Source 实例、Source ID 和 generation；旧快照、非法路径、类型错误、不可用项与非法选项在回调之前拒绝。单选和多选使用真实 entryValues，不能用标签或选项索引代替。当前值暂时不在动态选项中时明确显示不可用值，不自动改变存储；空选项可描述，但禁止编辑。

存储使用 typed `PreferenceValue`，区分 boolean、text、sint32、sint64、float 和唯一字符串集合。缺键是默认/未存储状态，false、0、空字符串与空集合都是存在的值。sint64 采用 ProtoJSON 十进制字符串，Java 分别通过 `putInt` / `putLong` 保存，不能把两者都转换成 Number；Dart 在生成 codec 解码之前额外拒绝会被 fixnum 环绕的越界长整数。float 必须有限。没有通用的“重置单项”操作；原 Source 提供的 action 仍可调用。

change listener 返回 true 才执行该控件的标准持久化；返回 false 仍可能写别名键或清缓存，因此必须重读实际存储。点击独立执行原 listener，不能当作普通值修改。不能自动重试这两个插件操作。

用户可从源列表或源内浏览页打开设置。每项编辑立即保存，窗口继续使用同一个 Source 实例和编辑响应中的设置树。关闭后统一重建一次，按已确认的值刷新当前浏览列表。从源列表设置时，在第一次进入漫画源后请求列表。开关和单选在选择时提交。普通文本可通过键盘完成输入，多选在选完后应用整组值。密码及插件动作保留明确确认，每种入口都使用同一个 Source 编辑命令。

## 原对象、构造顺序与生命周期

客户端先 GET 整包已确认设置，再形成 `PreferenceBootstrap(packageName,sources,syncRules)`。driver 消费账户 API 返回的同步规则，作为 `PreferenceHostConfiguration` 传给 `hostLoad`。Java 使用 init 创建的原 Application 和原 SharedPreferences.Editor，在 `Generated/createSources` 之前注入 `source_<id>`；不能构造 Source 后才更新设置，因为构造函数、lazy client 和 headers 可能已经读取旧值。

保留原 Preference 实例、具体子类和 listener。必要的 Preference 分组、dependency 和有界 headless 编辑元数据属于项目宿主 ABI 适配；不替换整个 Context，不改扩展源码或原 JAR。原 bind 超出已实现的 headless 方法子集时呈现 unsupported；不创建 Activity、原生对话框或任意 Android UI。密码行不回显原 summary、默认值或输入提示。

setup 和编辑回调可能启动后台 HTTP 并在返回后写设置。宿主仍使用有界 operation owner；描述和实际存储最终序列化放在 `owner.drain` 成功之后，避免保存回调尚未写完的值。headless bind 仅在建立描述时执行一次，drain 后不重复触发。设置专用 EditText 支持有界 bind post、全选、非秘密提示及原 TextWatcher；不为普通 Android 控件提供此行为。Flutter 通过 typed 提示和全选字段呈现元数据。

文本编辑弹窗保留源的 `dialogMessage`。宿主将 `Linkify.WEB_URLS` 识别出的显式 HTTP(S) URL 表示为原文的 UTF-16 区间，TS 和 Dart 在使用前校验区间顺序、地址和大小。Flutter 将原文与链接显示在输入框前。用户点击才打开对应地址，打开失败时保留输入草稿和链接。密码由设备存储，弹窗说明属于显示元数据。

提交文本时，对原存储值到候选值执行一轮 before/on/after，候选通过只读 Editable 提供。设置专用的 `android.R.id.button1` 只表示本次提交是否启用；任一 error、禁用或校验异常均拒绝候选，宿主不调用 change listener、不执行默认写入，原始异常与输入文本不作为错误回显。允许后仍执行原 change listener 一次，并重读实际存储，保留它在返回 false 之前自行写入的值。此边界不模拟逐键输入、IME、span 或其它 Android 对话框。

首次发送 edit 后，该运行时仅供当前设置窗口使用。TS manager、Worker 和 Dart transport 在收到有效编辑响应后，只放行同一 Source 和返回快照的后续编辑。成功和 veto 都使用实际存储与当次更新后的描述。结果未知时必须重建后才能继续编辑。其间仍可释放已有资源、关闭页面会话和关闭运行时。退出设置窗口后通过平台 `rebuildRuntime` 构造新代，再恢复普通 Source 和图片请求。遇到未确认的账户请求时，保留明确重试和读取服务端状态入口。

## 同步许可与业务 API

已审核的键由 AOT 写进当前官方构建的 `preferenceSyncRules`。正式部署装配从同一快照投影设置规则，Worker 只接受应用自己的 Static Assets 提供的规则，并在账户读取和写入时按 Source、原始键与值类型检查。额外仓库与无规则构建使用本机设置。响应和 ACK 回显当前规则，原规则撤下后保留已确认 revision。密码、未知文本和未知键通过 `sessionValues` 交给客户端保存。

禁漫天堂的屏蔽词与自动签到开关、哔咔的屏蔽词、图片质量及分流选择纳入各自 AOT 的同步规则。两者的登录凭证和哔咔的自定义分流 URL 由当前设备保存。规则从对应的新构建发布时生效。

- GET `/api/source-preferences/packages/:packageName?catalogUrl=...&repoId=...` 返回该身份、该来源的整包 `SourcePreferencesResponse`。
- POST `/api/source-preferences/mutations` 接收 mutationId、CatalogReference、packageName、sourceId、expectedRevision 和完整 entries，返回确认的 Source 状态与 accountRevision。

每个 `(subject,catalogUrl,repoId,packageName,sourceId)` 独立 CAS，整组 entries 替换；遗漏的键删除，清空后仍保留 revision 行。D1 batch 原子维护 Source revision、account revision 和持久幂等确认；包内 Source 数量与总字节配额在同一写入门验证，不能被并发跨 Source 请求绕过。

首项编辑以构造 Source 时注入的 revision/entries 为基线。打开设置页先 GET，整包确认设置或同步规则已变化时先重开 Source 再取描述。同一窗口内的下一项以此前服务端确认的 revision 为基线。编辑只上传 `syncValues`。实际 `sessionValues` 变化时等待本机写入，空分区删除该记录。另一端进入漫画源或打开设置时读取已确认值，重入已有会话也会检查最新账户配置。失败与未知结果提供重新读取入口，插件回调只执行原编辑一次。

本机记录按确认的部署/账户、目录 URL、repoId、package 和 Source 隔离。iOS 使用设备 Keychain，Android 使用由 Keystore 保护的存储并排除系统备份，Web 保存在当前浏览器站点存储中。Web 使用浏览器同源锁串行化写入，避免多标签首次保存时生成不同密钥。源列表、浏览、封面与跨源搜索通过同一入口在构造前读取设置。当前同步许可覆盖的键由账户分区提供，防止已保存在设备的值进入同步正文。[存储依赖文档](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)

业务响应丢失时保留冻结的 UUID、body 和 CAS。显式重试重发这份业务请求，插件回调仍只执行原编辑一次。校验 ACK 的身份、版本和提交值后，在原会话保存确认，随后的失败恢复只 GET 整包。保存或确认期间等待当前操作完成再关闭窗口。读回校验确认版本并采用当前 D1 数据，明确恢复时重开运行容器。未确认和已确认的恢复均可查看本次提交的同步值。冲突、显式放弃或未知运行结果可读取 D1 当前状态后重开。关闭表单、切换 Source/包/身份/部署及迟到结果不能复活旧草稿。相同账户和部署再次连接时才能访问各自保存的本机设置。额外仓库边界见[设计](additional-repositories.md)。

## 统一限额

| 对象                                | 限额                                                      |
| ----------------------------------- | --------------------------------------------------------- |
| 设置树                              | 深度 8，节点总数 256                                      |
| 单组选项 / 字符串集合               | 256，值唯一                                               |
| key / title、label / summary / text | 200 / 512 / 2048 / 4096 UTF-16 单元                       |
| 文本输入提示                        | 最多 512 UTF-8 字节，密码控件不发送                       |
| 文本编辑弹窗说明                    | 最多 2,048 UTF-8 字节、8 个按原文排序的 HTTP(S) 链接      |
| 每个文本 bind 的 post / watcher     | 各最多 16；仅 bind 阶段登记                               |
| 每 Source 实际存储（两个分区合计）  | 128 entries、entries 数组 ProtoJSON 32KiB                 |
| 整包存储 / bootstrap                | 最多 64 Sources，各 entries 数组 ProtoJSON 字节之和 64KiB |
| bootstrap / 整包业务响应            | 完整 ProtoJSON 128KiB                                     |
| snapshot / edit result              | 256KiB                                                    |
| 编辑及控制请求                      | 完整控制请求 128KiB，含封装开销                           |

所有字节限额使用 UTF-8；各层同时检查整体预算，不把多份独立合规的小消息无界拼接。API 保存 sync 分区，bootstrap 还可能包括设备恢复的分区；合并超额明确失败。

## 验证边界

生成一致性、TS/Dart 双向 golden、Java oracle、官方 workerd/D1 与 Flutter 组件回归是工程证据。按 v6 重建后的真实 Source 原设置回调、构造生效、在线业务，以及同身份 Web/Native 独立客户端读回，须分别验收。Komiic 镜像偏好可用于正式选择站点；不能直接改 URL、JAR 或 supplier 冒充原 Source 设置生效。
