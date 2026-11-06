# Source 业务筛选

状态：正式链路已实现并通过集中工程检查，代表 AOT、真实 Source 与平台验收仍待完成。目标是把原 Source 的筛选描述、编辑、搜索与分页接入正式链路；不将默认搜索成功视为筛选可用。实施状态见 [P3](../plan/p3-extensions-and-migration.md)，实际运行证据须绑定新 ABI 的 AOT 构建。

## 类型与原对象

控制协议枚举 Header、Separator、Text、CheckBox、TriState、Select、Sort 和递归 Group。Java 保留 Source 返回的具体 Filter 子类树，界面只提交有界索引路径和类型化叶状态。所有更新先整体验证，再写回原对象；必须完整覆盖可编辑叶，拒绝重复路径、错误类型和非法选项。未知 Filter 类型明确失败，默认浏览仍可独立使用。

树最多 8 层、256 个节点，每个选择最多 256 项；名称和选项标签最多 512 字符，文本状态最多 4096 字符。快照 ID 为 1–200 字符；快照正文最多 256KiB，控制请求仍为 128KiB。Sort 用可选 selection 保留 null、索引 0 与倒序的区别；Header、Separator 和 Group 不直接接受叶状态更新。

## 草稿与查询身份

`getFilters` 返回绑定当前 Source 与 generation 的 `snapshotId` 和描述。表单草稿与已应用查询分开；用户明确应用后即使关键词为空也调用 search，只有成功才发布新结果和已应用状态。后续分页复制已应用状态，不能读取未提交草稿。

重新获取动态描述时，客户端在 `GetFiltersRequest.retainedSnapshotId` 指定当前已应用查询的快照。宿主常驻最多两个槽：最新描述与客户端明确保留的快照；进行中的一次请求可暂持一个候选。新描述连同后台收尾成功后才替换槽，失败保留原槽。search 不自动提升或逐出快照，避免迟到成功、取消或丢响应后破坏客户端原查询的分页。每次新 getFilters 才按客户端当前确认的查询更新保留引用，运行时初始化或 generation 变化清理全部引用。

取消纯表单草稿不发 Source 请求。取消正在执行的 Source 调用沿用现有运行时语义：active 调用会回收 Worker、使整代失效，取消控制请求返回 `runtime_lost` 以立即清理客户端会话并提示重连；排队、已完成和旧 generation 的取消不回收当前执行槽。不能用受控 supplier 的温和取消冒充生产行为。切换身份、Source 或运行代次后丢弃描述和迟到结果。

## 原型交付边界

本次 host ABI 升为 `karuyomi-source-host-v5`，传输协议版本仍为 2；旧 ABI 扩展必须重建，不维护兼容回退。筛选是会话查询状态，不引入 D1、持久 outbox 或 Source preferences 设置系统。

Komiic 的 Select 子类同时实现其自有业务接口，空查询搜索才应用筛选；它可作为静态选择与原子类保留的实际候选。界面保留 Source 自身关于关键词与筛选组合的 Header，不承诺插件没有实现的组合。CuuTruyen 的动态标签 Group/CheckBox 可作动态验收候选。其 getFilterList 可能先返回缓存或重置提示，再通过原后台机制取得标签；宿主不改写插件业务，也不把初次返回提示当成标签已加载。代表 AOT、真实在线筛选、空查询和分页均须另行实测。JVM、TS/Dart 合同与组件检查不能替代这些门。
