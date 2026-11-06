# typed Source 筛选验证

2026-11-06，本地 macOS，正式 Source 筛选已接入 Protobuf、TS/Dart 解析、Java 原具体子类适配与 Flutter 浏览入口。设计见[Source 筛选](../design/source-filters.md)，范围与待办见[P3](../plan/p3-extensions-and-migration.md)。状态为**已实现并通过集中工程检查，修复后的两包 v5 AOT 与 CuuTruyen 真实 Web 动态筛选、空 query 和分页分项通过；其它 Source、Native 与生产仍待验收**。

## 合同与宿主

新增 `getFilters` 描述和 `SearchRequest.filters`，八类节点保留原 Source 的具体子类；所有叶状态完整校验后写回，不重建通用 Filter 替代插件对象。Sort 的 null、首项和倒序保留 presence。显式 retained snapshot 与最新描述各占一个槽，新描述及后台 drain 成功后才发布；search 不逐出原已应用查询。

TS 严格类型检查、筛选合同 3 项、Dart 筛选及相邻传输/协议 36 项、跨语言 golden 10 项已通过。Java 新筛选 oracle 242 断言与正式 TeaHost 集成编译通过，覆盖八类、插件自有 Select marker 接口与 Group/CheckBox 子类、完整叶原子性、pin/失败/代次、选项与树预算。上述检查使用受控对象，不是原 Source 在线证据。

正式 driver/manager 定向 35 项通过，包含 getFilters 的 retainedSnapshotId/Java entry 上下文、空 query 和分页、sort:{} 与 false 的 ProtoJSON presence，以及活动取消、排队取消与迟到取消边界。正式 `pnpm teavm:check` 也已通过现有 DTO、正文、图形、原 OkHttp Cache、文件与网络配置 oracle。

## 产品交互与取消

表单草稿不写 D1。只有成功的显式应用才更新漫画结果与已应用状态；空 query 仍走 search，分页复制已应用状态。加载失败可重试，仍可默认浏览；重置重新调用原 Source 描述，保留当前已应用查询的快照。换 Source、身份或运行代次后丢弃旧引用和迟到结果。

交叉检查发现，原 manager 会终止活动 Worker，却对 cancel 控制返回 completed，使客户端保留已失效会话。现活动 Source 取消向控制请求返回 runtime_lost，由正式 Dart transport 清会话并通知界面重连；原 invoke 仍以 cancelled 结束。排队、已完成与旧代次取消不回收当前槽。另补请求完成到调度 finally 之间的迟到取消保护。

首轮组件组合发现 sheet 的 isCurrent 会把自身下拉菜单误判为离开页面，已改为所属 route 的 isActive，并保留身份/Source/Worker/关闭守卫；修复后新增 controller/widget 及既有 catalog controller 均在完整 Flutter 回归中通过。取消夹具通过正式 ProtoJSON 控制错误触发 Dart transport，不手动注入容器失效来代替取消合同。纯编辑关闭不调用 runtime.cancel。另补描述已在宿主完成但面板已关闭的时序：只清当前 epoch 的旧描述缓存，下次显式重取并 pin 原已应用查询，不清新会话缓存或已应用分页状态。

## 集中工程检查

`pnpm check` 通过，包含生成一致性、portable 格式、所有 TS 严格类型、依赖边界、397 项 Vitest、10 项跨语言 golden 和扩展/构建/完整性/补丁/Cloudflare 工具检查。`pnpm flutter:check` 通过：reader_core 22 项、source_runtime 47 项、客户端 427 项；三个项目严格分析无问题，135 份自有 Dart 文件格式一致。全库 `pnpm format` 与完整 `pnpm format:check` 通过。

`pnpm build` 通过 Web/Native host 与内置材料、Flutter Web release、Worker/Static Assets 工程构建。这不是 Native App 启动或 Source 验收。首次手工准备的空快照缺 build-state，被装配合同正确拒绝；最终使用仓库正式无快照开发路径生成空索引，未装配旧 v4 AOT、未部署或改发布 checkpoint。

## 首轮真实 v5 AOT 与后台任务收尾

固定 `225ac336a24cfc9d5ea05b2335d2bbb2597a2c2a` 的独立构建目录，使用锁定的三份上游 submodule 和完整 1448 包计划，仅选择 Komiic 1.6.11 与 CuuTruyen 1.6.2 构建，未改 baseline 或部署状态。两包官方 Gradle、TeaVM AOT 与传输完整性检查通过，随后经正式 `prepare-snapshot` 生成仅本地验收的候选快照；仍为 `compiled_unverified/runtimeReady=false`。

官方 Wrangler `createTestHarness` 现在可通过 `ACCEPTANCE_SOURCE_POLICIES` 从当前 Static Assets 验证并注册显式网络政策，仍使用隔离 D1 和真实 RS256 测试身份。命令及 Native TLS 要求见[集成验收说明](../../apps/reader/integration_test/README.md)。这不是生产 Access；未加入自有服务器或替换 Source。正式 `acceptance:build` 携两包候选快照通过。

Codex 内置浏览器通过正式 Flutter 入口取得 CuuTruyen 真实热门列表，看到 Spy x Family、Sakamoto Days 等返回；筛选首次描述及显式重置仍只显示原 `Tap 'Reset' to load filters`。Komiic 原 Header 与 Select 描述可显示，非默认排序可编辑，但热门和空 query 应用均返回 Source 请求失败，不能登记在线筛选通过。

实际 CuuTruyen JAR 的原 `getFilterList` 会通过 `GlobalScope.launch(Dispatchers.IO)` 请求标签、写缓存并清理 inFlight。旧宿主仅等待已登记的 HTTP 回调；子线程尚未执行时，entry 可能 drain 空集合并关闭，后台任务随后被过期 owner 拒绝。确定性 JVM 用例先复现失败：已绑定但未调度的工作未阻止 drain。修复在排队前登记一次性工作 lease，涵盖开始执行、HTTP 与返回后的缓存写入和完成回调，真实 finally 才释放；独立 64 个工作与原 64 个 HTTP 回调额度、30 秒总期限保留，未启动 LAZY 不占 lease。

另一个先失败后修复的组合用例覆盖：旧 entry 创建 LAZY 并注册 completion，下一 entry 启动时不能通过失败回调取得新 owner。任务及完成回调均固定原 owner，过期执行被拒绝；调度构造/start 失败释放 lease，运行中 cancel 不假装已收尾。最终 Enqueue oracle 81 断言及完整 `pnpm teavm:check` 通过，包含已有 HostFilters、HTTP、图形、Cache、文件与网络配置检查。正式 JVM 清单显式编译自有 `BuildersKt` / `Dispatchers`，避免误跑 seed 旧实现。该结果不能代替修复后真实 AOT 与在线复验。

## 修复后真实 Web 分项

固定 `398d7cd706df8890b6e3a5a1fcd30778a67971fb` 重新建立独立构建目录，三个上游提交不变，重新生成完整 1448 包计划并仅选择两包；没有复用旧 225 AOT。两包官方编译、AOT 和完整性均通过，当前身份如下：

| 扩展            | buildId                                             | canonical SHA-256                                                  | gzip / canonical 字节 |
| --------------- | --------------------------------------------------- | ------------------------------------------------------------------ | --------------------- |
| Komiic 1.6.11   | `ext-zh.komiic-24610b0a4af797f80c60c31a855753f2`    | `e97c95b04be69a1205c7c1bca6fc589148e13fe5ed0c61a51ee9c25ddec2988f` | 518459 / 1645185      |
| CuuTruyen 1.6.2 | `ext-vi.cuutruyen-7559296f3f46f7a92fae64848cbc7fa6` | `4c91374613713a152cde0c75f0c84ad82d513f139c40a1ffdefd0a2252154c5d` | 662801 / 2126391      |

正式 `prepare-snapshot` 的候选 revision 为 `0c9a02ff39614caaacbe770b8b210546`，仅两包可用、1446 包 pending，`bootstrap.complete=false`；独立 checkpoint 仍不存在，未部署或提交发布状态。正式 `acceptance:build` 携此快照通过。本次代码提交的[远端 CI](https://github.com/Wybxc/karuyomi/actions/runs/42146488877)也通过，包含通用检查、Flutter 分析/回归、工程构建及本地 D1 迁移；Source 在线证据仍以以下实际浏览器操作为准。

Codex 内置浏览器，正式 Flutter → manager/TeaHost → 原 CuuTruyen → 官方 workerd HTTP 桥，使用隔离测试身份及显式主机政策，实际通过：

1. 打开 Source 后取得真实热门列表。第一次筛选请求等待后台收尾，原描述仍为 `Tap 'Reset' to load filters`；显式重置后出现原 `Thể loại` Group 和 CheckBox 标签。
2. 选择非默认 `đã hoàn thành`（已完结），搜索框保持空，显式应用成功。界面显示“筛选（已应用）”，热门/最新不选中；首批返回 Hoshi Mamoru Inu、HoloX Meetings、Senkou Girl 等。这不是以热门替代空 query 搜索。
3. “加载更多”成功追加下一页，看到 NOT A HOUSEHUSBAND、IDOLiSH7 LIVE4BIT Beyond the period Special Book 等新条目；重新打开面板，已完结仍为已选。
4. 在面板重置，新草稿的已完结变为未选；直接关闭而不应用，原查询和结果仍保留。无需重新连接，再次“加载更多”成功追加第三页，包括 Ritou No Umi、Parade、Aho-Girl 等。新描述没有逐出原已应用快照，纯草稿关闭没有回收当前会话。

Komiic 的 Select 描述首轮已能呈现，但其默认 `komiic.com` 在当前环境的独立网络探测中 TLS 连接重置，在线搜索未通过。上游同一 Source 通过 `preferred_mirror` 设置选择 `.com` / `.cc`，不是两个 Source；`.cc` 直接查询成功仅作诊断，产品尚无正式 preferences 入口，未改 URL、注入镜像值或修改原扩展来冒充验收。后续按[Source 设置计划](../plan/source-preferences.md)接入原镜像设置后再验证。

此轮只登记 CuuTruyen 的真实 Web 筛选分项，不覆盖所有八类的实际 Source、Native、生产 Access、完整阅读或设备性能。两包自动化记录仍保持 `compiled_unverified/runtimeReady=false`。验收服务正常关闭，构建进程已结束；截图、完整计划、候选和详细日志保留在忽略的本地目录，不提交产物。

## 官方核心后的 Komiic Web 续验

2026-11-06，固定 `7e8fe769` 新建 v6 AOT，通过正式 preferences 选择原 `.cc` 镜像、Source 重开后热门成功；原动态分类“搞笑”应用、加载更多与重开面板保留已选均通过。固定包身份、正式 harness、原默认镜像失败及 Web 范围见[协程 / Source 记录](coroutine-runtime.md#固定官方核心提交的真实-web-分项)。这补充了上轮 Komiic 待验门，不覆盖其它筛选类型、Native 或生产。

## 复验与交付限制

```sh
pnpm exec vitest run packages/contracts/test/filters.test.ts packages/runtime-host/test/teavm-entry.test.ts packages/runtime-host/test/manager.test.ts
pnpm teavm:check
pnpm test:protocol
cd apps/reader
flutter test test/sources/source_filters_controller_test.dart test/sources/source_filters_widget_test.dart test/catalog_controller_test.dart --reporter expanded
```

新能力要求 `hostAbi=karuyomi-source-host-v5`，protocolVersion / bridgeVersion 仍为 2；旧 v4 AOT 不兼容，必须以固定提交重新规划和构建，不把旧三包的浏览/图片结果当成筛选通过。Komiic 仅在空关键词搜索中应用其 Select/Group；原 Header 保留。CuuTruyen 动态标签可能先返回重置提示，须按原后台链路完成后再显式重置确认。

修复后的两包 v5 AOT 与上述 CuuTruyen Web 分项已通过，尚未部署。其它 Source/筛选类型、Native、独立客户端、生产 Access 和目标设备须另外记录。编译/完整性仍只能记 compiled_unverified/runtimeReady=false；首次全量 baseline 与增量 CI 状态不因新增筛选而提升。

临时完整日志留在忽略的 `.local/typed-filters-*.log` 和 `/private/tmp/karuyomi-source-filters-*.log`，不将机器输出提交入库。
