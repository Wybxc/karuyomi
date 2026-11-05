# 分类 UI 与多端同步

2026-11-05，本地 macOS、固定 Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4，Codex 内置浏览器。本文只验收分类，双 Web 和 Native 范围分别记录；组件测试、测试身份或受控书架元数据不代表真实 Source 阅读、生产 Access 或真机证据。

## 实现与边界

书架接入管理分类（创建、改名、删除、上下移动）、全部/未分类/单分类筛选，以及每部漫画的多分类选择。筛选与现有搜索/排序共同作用于服务端已确认视图；目录和漫画关系由同一快照发布。

编辑固定打开时的目录 revision，关联编辑还固定漫画 revision。提交失败冻结原输入；未确认命令只保存在当前会话，关闭弹窗后书架提供继续处理入口，新编辑不能隐式重发旧修改。数据层也阻止资料刷新、收藏或进度等不同命令隐式重发未确认的分类关联。明确重试复用原 mutation UUID/正文；冲突必须重新读取并重开编辑，不自动提高 CAS。身份/服务断开永久停用旧编辑，迟到结果不能操作其它弹窗。

## 官方集成入口

```sh
pnpm acceptance:build
pnpm acceptance:serve
```

构建使用正式 Flutter `main.dart`、当前 Static Assets 与独立声明式 Vite 测试配置；启动器直接使用官方 Wrangler `createTestHarness()`，以本地隔离 workerd/D1 应用正式迁移。测试边缘为 loopback 请求签发临时 RS256 身份，实际请求仍经过产品 JWT、Origin、`X-App-Subject` 和 `X-App-Request` 校验。它不补业务请求头，不进入生产构建，也不使用真实 Access 凭据。

在输出 URL 打开两个独立标签页；同一身份的数据经 D1 共享，每个 Flutter 文档有独立内存会话。为保持分类验证独立，经正式 mutation API 种入两部明确的受控漫画元数据，没有启动或绕过任何 Source 图片流程。按 Enter 结束后官方 harness 关闭，临时 D1 随进程销毁。

HTTP smoke 已实际通过：签名 bootstrap 为 200；业务缺失或错误 subject 为 403；缺失写标识或错误 Origin 的 POST 为 403；Flutter 静态入口为 200 且绕过 Worker。

## 首轮实际双会话

产物 `main.dart.js` 为 3,540,333 B，SHA-256 `99171fd2b06c1ebbef4b5c24bdb26a15d57b6955e6ed438dcfc31e4d661cff8a`。以下均通过真实界面操作，API 仅用于初始受控收藏及最后读回：

- A 创建“工作日”“周末”，将“周末”上移；B 显式刷新后目录名称和顺序相同。
- A 为漫画甲同时关联两个分类；B 刷新后显示两个名称，“工作日”只显示甲，“未分类”只显示乙。
- B 将“周末”改为“休闲”，并为乙关联“休闲”；A 刷新后读回新名称与乙的关系。
- A 保留打开时的关联编辑并取消选中“工作日”；B 先将该分类改名“通勤”。A 保存明确显示“分类或漫画已在其他设备修改，请重新读取后重开编辑”，没有覆盖另一端目录或旧关系。显式重新读取并关闭后恢复当前确认视图。
- B 删除临时“通勤”分类；A 刷新后目录与两部漫画只剩“休闲”，收藏仍为两部。B 整页重载后从 D1 恢复同一目录与关系。

最后 API 读回 account revision 为 10、catalog revision 为 6；甲 revision 为 3、乙为 2，两者关联同一保留分类。初轮服务 exit=0，监听端口 61987 已释放。构建日志与截图保留在忽略的 `.local/category-acceptance/`。

初轮之后仅补了同身份重连期间原命令完成的界面状态：恢复中的管理器接纳确认快照，关联弹窗给出已确认提示与手动完成按钮，不新增自动导航。最终产物的实际回归如下，初轮身份保持原样。

## 最终构建与回归

最终 `main.dart.js` 为 3,540,925 B，SHA-256 `8256fcd6b9d7cdb1592205480c78dcd2168129d3d5f063c2c9e5beec46ea55a0`，正式 Flutter 输出与验收 Static Assets 字节一致。新隔离 D1、两个新 Web 会话再次通过 A 创建目录→B 刷新、B 为甲关联→A 刷新、B 改名→A 旧关联编辑明确冲突并重新读取；A 整页重载后目录为“最终分类”、甲已关联、乙仍未分类，没有应用旧草稿。最终 account revision 为 5、catalog revision 为 2，甲 revision 为 2、乙为 1。第二轮服务 exit=0，端口 65201 已释放。

分类组件新增 14 项，整个 `test/library` 的 25 项通过，包含 CRUD、排序、筛选、多关联、原请求精确重试、双 revision 冲突、身份/服务替换、迟到 ACK、小屏，以及同身份重连后继续原请求完成而不重复 mutation。分类数据层共 15 项通过，新增四项分别验证发送前失败/丢响应时目录或关联命令不会被新编辑、资料刷新等入口隐式重发；这些是模拟 supplier 证据。

`pnpm acceptance:build` 两轮成功；完整 `pnpm check` 通过（359 项 Vitest 及工具、协议回归；154 个模块依赖检查无违规）。`pnpm format`、`pnpm format:check` 与 `pnpm flutter:check` 全部通过，Flutter 三项目分别为 21 / 42 / 238 项。

## 双 iOS 模拟器顺序闭环

2026-11-05 至 06，同一主目录 `7276a9a` 产品代码和随本记录提交的测试驱动/HTTPS 配置，iPhone 17 Pro / iOS 26.4 两台本轮专用模拟器。五个独立 Flutter `integration_test` 进程均启动正式 `app.main()` / `NativePlatformRuntime`，经过正常受信的 `https://127.0.0.1:56341` 和同一隔离 workerd/D1。仅向这两台设备加入本轮 CA，未修改全局信任、产品 TLS 或 release。

正式 mutation API 预置两部受控收藏（甲/乙），初始 account revision 2、空目录；本轮未启动任何 Source。每个阶段实际操作 UI，再经 repository 读回权威快照，核对书架显示，最后卸载界面并 dispose 正式 runtime。以下五阶段各 1/1 通过：

| 阶段             | 实际结果                                         | 目录 revision | 甲 / 乙 revision |
| ---------------- | ------------------------------------------------ | ------------- | ---------------- |
| A create         | 新建“跨端分类”，关联甲                           | 1             | 2 / 1            |
| B update         | 读回甲关系，改名“共享分类”，关联乙，分类 ID 保持 | 2             | 2 / 2            |
| A verify         | 新进程读回改名和两部关联                         | 2             | 2 / 2            |
| B delete         | 删除目录，两部收藏保留且关系清空                 | 3             | 3 / 3            |
| A verify-deleted | 新进程读回两部未分类，实际选择未分类筛选         | 3             | 3 / 3            |

最终独立 API 读回 account revision 7、空分类目录和两部 favorite=true，与 UI/驱动结果相符。五份原始日志保留在忽略的 `.local/category-native/{a-create,b-update,a-verify,b-delete,a-verify-deleted}.log`。官方 harness 已 exit=0，端口 56341 已释放。这是两台 iOS 模拟器的顺序读写与新进程恢复，不是同时写竞争、真实断网、生产 Access、物理触控、Source 阅读或真机性能验收；其它平台组合另列。

## iOS 与 Android 顺序闭环

2026-11-06，重新构建 `pnpm acceptance:build:native` 并启动新隔离 HTTPS harness（端口 59252），可选分类 fixture 经生成 ProtoJSON 与正式 mutation API 自动初始化两部收藏。正式 Web 产物 SHA 与上一节双 Web 最终产物一致；Native 驱动 SHA-256 为 `056e45089e0f7fca60b2294d8bdd5bd4396ec8188f442a541232b1cd9ede88c4`。Android 为本轮专用 API 36 / Android 16 ARM64 模拟器，WebView 133.0.6943.137；iOS 使用上一节 A。Android 的忽略 debug 副本逐文件核对产品 Dart、驱动与内置材料，只调整测试 applicationId、debug CA 配置和构建运行参数；CA 仅对精确 `127.0.0.1` 生效，保留系统 CA、hostname/TLS 校验，禁止明文，未改变主树 release。

Android create、iOS update、Android verify、iOS delete 四阶段各 1/1 通过：Android 创建并关联甲，iOS 读回后改名并关联乙，Android 新进程读回共享分类及两关系，iOS 删除后两部收藏保留且均未分类。分类 ID 始终为同一 ID，目录 revision 依次 1→2→3；独立 API 最终读回 account revision 7、空目录。原始结果保留在 `.local/category-native/{android-create,ios-update,android-verify,ios-delete}.log`。

Android 最后 verify-deleted 首次在测试体加载前 DDS 启动失败；详细日志重试时 DDS 成功，但实际 WebView renderer 在初始化阶段中断，UI 报告“运行容器已中断，请重新连接”，测试失败。失败原始日志分别为 `android-verify-deleted.log` 和 `android-verify-deleted-retry.log`。保留的诊断没有确定更早的网络/JS 错误、OOM、GPU 或原生崩溃；renderer 的 code -1 也可能是加载/握手失败后 dispose 的结果，不能据此认定根因。Android 首轮工具末尾按旧包名卸载失败；第二轮调整本轮 SDK 用户目录导致 debug 签名不同，Flutter 正常卸载再安装后测试通过；这些打包/驱动记录与运行时中断分开保留。

随后仅冷重启本轮 Android AVD，保持同一服务/D1、源码、驱动、TLS、GPU、内存与端口转发条件不变；原 `verify-deleted` 只读阶段 1/1 通过，目录 revision 3、两部收藏各 revision 3 且关系为空，实际未分类筛选通过。原始成功日志为 `android-verify-deleted-cold.log`。因此这组 iOS↔Android 顺序五阶段数据收敛与新进程读回已通过；DDS/Native 初始化间歇失败仍是独立可靠性待办，冷启动成功不能当作根因已修复。两个 iOS 专用设备已删除，HTTPS harness 已 exit=0、59252 已释放。

内置浏览器访问同一 HTTPS URL 返回 `ERR_CERT_AUTHORITY_INVALID`，未绕过警告、未改全局信任，测试标签已关闭。因此本轮不声明 Web↔Native 分类混合会话通过；此前 HTTP 双 Web 门仍独立有效。

## 本轮工程检查与清理

最终 HTTPS 配置使用官方 Cloudflare `config` callback 合并已解析的 `dev` 默认值，再声明两个 HTTPS 协议；严格 `DevConfig` 类型检查通过，没有断言或关闭类型检查。最终 `pnpm acceptance:build:native` 完整成功；端口 65090 的新官方 harness 经正常 Node CA 校验，通过签名 bootstrap 200、正式 response schema 解析、两部已确认收藏和空目录 smoke，随后 exit=0、端口释放。默认 HTTP mode 的 Vite CLI 构建、签名 bootstrap 和生成响应解析 / 两收藏夹具也通过；端口 49152 的服务 exit=0 并释放，未使用 HTTPS 配置或设备 CA。

完整 `pnpm check` 通过：359 项 Vitest、协议/工具回归及 154 个模块 / 498 条依赖检查。`pnpm flutter:check` 三项目分析和 21 / 42 / 238 项均通过，新集成驱动纳入分析；设备上的十个成功阶段与前述失败分别计证据。全库 `pnpm format`、`pnpm format:check` 通过。

本轮两台 iOS 模拟器及专用 Android AVD 已删除；Android 测试包、reverse、emulator 与本轮 ADB server 均确认结束，所有验收 harness 已收 exit=0。原始日志、隔离副本和诊断保留在忽略目录，不提交临时工程、CA 或构建输出。

## 尚待验收

- Web↔Native 分类混合会话、物理设备读回；双 Web、双 iOS 及 iOS↔Android 的顺序分项已分别通过。
- Android DDS/Native 容器初始化的间歇失败复现与根因修复；当前冷启动读回通过不覆盖此门。
- 实际网络丢响应、同时到达的写竞争及自动前台/断网恢复；当前组件故障注入与顺序旧视图冲突分别计证据。
- 生产 Access 正向会话及生产分类部署；本地临时 RS256 身份不代表此门通过。
