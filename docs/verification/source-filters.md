# typed Source 筛选验证

2026-11-06，本地 macOS，正式 Source 筛选已接入 Protobuf、TS/Dart 解析、Java 原具体子类适配与 Flutter 浏览入口。设计见[Source 筛选](../design/source-filters.md)，范围与待办见[P3](../plan/p3-extensions-and-migration.md)。状态为**已实现并通过集中工程检查，代表 AOT 和真实 Source 未验收**。

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

## 复验与交付限制

```sh
pnpm exec vitest run packages/contracts/test/filters.test.ts packages/runtime-host/test/teavm-entry.test.ts packages/runtime-host/test/manager.test.ts
pnpm teavm:check
pnpm test:protocol
cd apps/reader
flutter test test/sources/source_filters_controller_test.dart test/sources/source_filters_widget_test.dart test/catalog_controller_test.dart --reporter expanded
```

新能力要求 `hostAbi=karuyomi-source-host-v5`，protocolVersion / bridgeVersion 仍为 2；旧 v4 AOT 不兼容，必须以固定提交重新规划和构建，不把旧三包的浏览/图片结果当成筛选通过。Komiic 仅在空关键词搜索中应用其 Select/Group；原 Header 保留。CuuTruyen 动态标签可能先返回重置提示，须按原后台链路完成后再显式重置确认。

本轮尚未构建代表 v5 AOT、运行真实在线筛选或部署。实际空 query、非默认选择与后续页，动态标签、Native、独立客户端、生产 Access 和目标设备须另外记录。编译/完整性仍只能记 compiled_unverified/runtimeReady=false；首次全量 baseline 与增量 CI 状态不因新增筛选而提升。

临时完整日志留在忽略的 `.local/typed-filters-*.log` 和 `/private/tmp/karuyomi-source-filters-*.log`，不将机器输出提交入库。
