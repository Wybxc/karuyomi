# 额外扩展仓库

## 目标与状态

**状态：已实现，独立集中工程检查、当前三包 AOT、Web 仓库管理及默认 xkcd 安装/阅读分项通过；实际外仓 Source、Native 与生产待验收。** 在默认仓库扩展管理基础上，完成额外仓库的账户登记、只读预览、更新与移除、同包明确替换和完整运行来源隔离。设计见[额外扩展仓库](../design/additional-repositories.md)，上级见 [P3](p3-extensions-and-migration.md) 与[扩展管理](extension-management.md)。

## 实施范围

- 生成协议统一仓库设置、必填 CatalogReference、index repoId、准备/打开/会话来源回显。
- D1/API 保存最多 16 个额外仓库；默认仓库固定保留，URL/repoId 分别唯一；installed package 唯一，同包跨仓明确确认。
- Flutter 添加先预览、再确认；刷新只读；移除保留安装引用和业务数据。四打开入口、Access 恢复、源迁移候选及阅读请求按完整来源解析。
- 扩展元数据与代码直接无凭据下载、拒绝重定向；共享 materials 与应用 HTTP 桥不随仓库切换。
- 可变存储、Cookie、D1 Source 设置和当前会话敏感值按来源隔离；外仓不能自报官方身份获得账户设置同步许可。
- 所有来源统一使用 Access 中继；无需网络登记，精确产物身份校验保留。

## 待办与验收

- [x] 正式协议、API、工具、Flutter 入口和 runtime-host 完整接线。
- [x] 独立审查来源混淆、凭据与重定向、同包替换、原 CAS/未知 ACK、取消/迟到结果、页面身份退休和跨部署隔离；发现的问题已修复并补定向回归。
- [x] 生成一致性、严格类型、依赖检查、正式回归、全库格式和完整客户端/API 构建；精确层级见验证记录。
- [x] 固定提交的当前协议三包 AOT 与本地候选 Static Assets；不向旧 AOT 补字段冒充新构建，baseline 仍未完成。
- [x] Codex 内置浏览器空外仓预览零写入、添加/移除、max-age 再验证与两个独立应用标签的顺序刷新收敛。
- [x] 默认 xkcd 正式安装、精确构建选择在第二标签读回、英语 Source 在线列表/详情与两页实际阅读、进度服务端确认分项；不冒称独立设备或冷缓存客户端。
- [ ] 真实外仓扩展的同包换仓、读取和图片，Native 正式入口与生命周期。
- [ ] 仓库及安装选择的并发冲突、未知 ACK 原请求重试，以及独立设备刷新收敛。
- [ ] 通用中继与迁移 `0010` 的部署验收，生产 Access 和真机分别记录。

Source 设置校验已和安装使用同一通用包标识，工程回归覆盖非 Keiyoushi 命名空间；[实际外仓 Source](../verification/generic-source-relay.md#第三方包名) 仍待独立运行验收。

功能实现与工程通过不替代实际 Source、独立客户端、Native 或生产验收。当前候选 AOT 与首次 baseline 状态继续按[扩展管理记录](../verification/extension-management.md)维护。
