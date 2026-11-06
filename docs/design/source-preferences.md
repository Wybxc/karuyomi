# Source 设置与多端确认

## 范围

正式协议位于 `protocol/karuyomi/v1/{control,business}.proto`。Host ABI 为 `karuyomi-source-host-v6`；原型直接更新当前 ABI，不为旧 AOT 加兼容路径。实现与平台验收状态见[计划](../plan/source-preferences.md)，工程及运行证据见[验证记录](../verification/source-preferences.md)。

设置编辑执行原 Source 的 `ConfigurableSource.setupPreferenceScreen` 和 Preference listener，不能把配置转换成一组脱离插件的通用表单。服务端确认的非敏感值以 Worker API + D1 为唯一权威；未知值及凭证只存在当前客户端会话，不写普通业务 API 或持久 outbox。

## 控制合同

`getPreferences` 返回有界 `PreferenceSnapshot`，包含当前 `snapshotId`、递归 nodes，以及实际 SharedPreferences 的两个完整分区 `syncValues` / `sessionValues`。描述支持开关、文本、单选、多选、分组、动作和明确不支持的项；保留标题、summary、enabled、visible、默认值及同步范围。

`editPreference(snapshotId,path,change|click)` 一次只修改一个原控件或执行一次原点击 listener，返回 `accepted`、`clickHandled` 和更新后的快照。路径绑定原 Source 实例、Source ID 和 generation；旧快照、非法路径、类型错误、不可用项与非法选项在回调之前拒绝。单选和多选使用真实 entryValues，不能用标签或选项索引代替。当前值暂时不在动态选项中时明确显示不可用值，不自动改变存储；空选项可描述，但禁止编辑。

存储使用 typed `PreferenceValue`，区分 boolean、text、sint32、sint64、float 和唯一字符串集合。缺键是默认/未存储状态，false、0、空字符串与空集合都是存在的值。sint64 采用 ProtoJSON 十进制字符串，Java 分别通过 `putInt` / `putLong` 保存，不能把两者都转换成 Number；Dart 在生成 codec 解码之前额外拒绝会被 fixnum 环绕的越界长整数。float 必须有限。没有通用的“重置单项”操作；原 Source 提供的 action 仍可调用。

change listener 返回 true 才执行该控件的标准持久化；返回 false 仍可能写别名键或清缓存，因此必须重读实际存储。点击独立执行原 listener，不能当作普通值修改。不能自动重试这两个插件操作。

## 原对象、构造顺序与生命周期

客户端先 GET 整包已确认设置，再形成 `PreferenceBootstrap(packageName,sources)`。driver 根据已验证 manifest 的 packageName 生成可信同步规则，作为 `PreferenceHostConfiguration` 传给 `hostLoad`。Java 使用 init 创建的原 Application 和原 SharedPreferences.Editor，在 `Generated/createSources` 之前注入 `source_<id>`；不能构造 Source 后才更新设置，因为构造函数、lazy client 和 headers 可能已经读取旧值。

保留原 Preference 实例、具体子类和 listener。必要的 Preference 分组、dependency 和有界 headless 编辑元数据属于项目宿主 ABI 适配；不替换整个 Context，不改扩展源码或原 JAR。原 bind 超出已实现的 headless 方法子集时呈现 unsupported；不伪造 Activity、按钮或 Android UI 成功。密码行不回显原 summary/default。

setup 和编辑回调可能启动后台 HTTP 并在返回后写设置。宿主仍使用有界 operation owner；描述和实际存储最终序列化放在 `owner.drain` 成功之后，避免保存回调尚未写完的值。headless bind 仅在建立描述时执行一次，drain 后不重复触发。

一次 edit 发送后，即使 veto、异常、取消或响应丢失，该代都不得继续普通 Source/图片请求。TS manager、Worker 和 Dart transport 都执行此门；已有资源的 release、close 与 shutdown 仍可用。必须确认保存或显式放弃并读取 D1 后，通过平台 `rebuildRuntime` 清理旧阅读资源并构造新代；不能用命中缓存的同一 open 或只丢 session 替代。

## 同步许可与业务 API

唯一可信许可表为 `packages/contracts/src/source-preference-policy.ts`，同时用于 driver 配置 Java 分区与 Worker API 校验。许可按 package、可选 Source ID、实际存储 key 和值类型配置，不信任插件描述或客户端自行声称 ACCOUNT。初始只批准已核对的 Komiic、MangaFire、AsuraScans 和 MangaKatana 非敏感键；后者保留 UI key 和 listener 别名键。未知文本、未知 key 和秘密值留在 `sessionValues`，绝不整体上传 `getAll()`。

- GET `/api/source-preferences/packages/:packageName` 返回该身份整包 `SourcePreferencesResponse`。
- POST `/api/source-preferences/mutations` 接收 mutationId、packageName、sourceId、expectedRevision 和完整 entries，返回确认的 Source 状态与 accountRevision。

每个 `(subject,packageName,sourceId)` 独立 CAS，整组 entries 替换；遗漏的键删除，清空后仍保留 revision 行。D1 batch 原子维护 Source revision、account revision 和持久幂等确认；包内 Source 数量与总字节配额在同一写入门验证，不能被并发跨 Source 请求绕过。

编辑基线必须是该 Source 构造时注入的 revision/entries。打开设置页先 GET；若与构造基线不同，先重开 Source 再取描述，不能把旧 runtime 的值套到新 revision 上。编辑后只上传 snapshot.syncValues；sessionValues 在当前部署/身份会话内保留，供确认后重开注入。

业务响应丢失时保留冻结的 UUID、body 和 CAS，显式重试只重发这份业务请求，不重跑插件回调。收到旧幂等 ACK 后再次 GET 整包再重开，不能用旧 ACK 回退 runtime 基线。只读刷新不重放 pending；冲突、显式放弃或未知运行结果都读取当前 D1 后重开。关闭表单、切换 Source/包/身份/部署及迟到结果不能复活旧草稿；切换身份/部署清空客户端秘密值。

## 统一限额

| 对象                                | 限额                                                      |
| ----------------------------------- | --------------------------------------------------------- |
| 设置树                              | 深度 8，节点总数 256                                      |
| 单组选项 / 字符串集合               | 256，值唯一                                               |
| key / title、label / summary / text | 200 / 512 / 2048 / 4096 UTF-16 单元                       |
| 每 Source 实际存储（两个分区合计）  | 128 entries、entries 数组 ProtoJSON 32KiB                 |
| 整包存储 / bootstrap                | 最多 64 Sources，各 entries 数组 ProtoJSON 字节之和 64KiB |
| bootstrap / 整包业务响应            | 完整 ProtoJSON 128KiB                                     |
| snapshot / edit result              | 256KiB                                                    |
| 编辑及控制请求                      | 完整控制请求 128KiB，含封装开销                           |

所有字节限额使用 UTF-8；各层同时检查整体预算，不把多份独立合规的小消息无界拼接。API 只保存 sync 分区，bootstrap 还可能包括客户端 session 分区；合并超额必须明确失败，不能悄悄截断。

## 验证边界

生成一致性、TS/Dart 双向 golden、Java oracle、官方 workerd/D1 与 Flutter 组件回归是工程证据。按 v6 重建后的真实 Source 原设置回调、构造生效、在线业务，以及同身份 Web/Native 独立客户端读回，须分别验收。Komiic 镜像偏好可用于正式选择站点；不能直接改 URL、JAR 或 supplier 冒充原 Source 设置生效。
