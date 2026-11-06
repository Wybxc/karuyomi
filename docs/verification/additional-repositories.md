# 额外仓库验证

2026-11-07，本地 macOS，固定 Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。正式协议、API/D1、登记工具、runtime-host 和 Flutter 管理入口已接入；实现范围见[设计](../design/additional-repositories.md)，待办见[计划](../plan/additional-repositories.md)。

## 独立集中工程检查

`pnpm check` 已独立完整通过：生成一致性、portable 格式、严格 TypeScript 和依赖检查，32 文件 465 项 Vitest、10 项跨语言 golden、34 项登记/网络政策、50 项扩展工具、14 项构建、15 项产物完整性、4 项 TeaVM 和 9 项 Cloudflare 回归均绿。没有缩小检查或跳项。

定向与审查覆盖：catalog URL/repoId 必填和 ACK 回显、四个 HTTP 来源头、跨仓 buildId 冲突整批回滚、来源范围内退役/hosts 继承、D1 Source 设置隔离与外仓空同步规则、原 CAS/未知 ACK、同包明确换仓、只读预览/刷新、移除保留安装引用、公开下载无凭据/无重定向及主动取消。namespace 增加应用 origin，避免 Native 在两个 API 部署间复用同 subject/外仓的数据。

独立审查发现并修复了准备 ACK 字段误置、Web 下载默认携带同源凭据、额外仓读取缺少逐请求生命周期、设置与管理面板首帧前身份变化、以及对话框退出动画提前释放输入控制器的问题。Web 元数据 fetch 明确使用 `cache: no-cache`；它仍服从 HTTP 缓存再验证，不自行维护另一份目录权威。

最后的 Dart 来源设置面板窄修发生在上述 TS 集中检查之后，未修改已冻结的 TS/API/协议。完整 `pnpm flutter:check` 重跑已通过：三个包严格分析均绿，Reader Core 22 项、Source Runtime 68 项、Reader 527 项全部通过，163 份自有 Dart 格式零变化。首轮完整 Flutter 的 7 项失败已修复，保留原业务断言；来源设置恢复先完成精确来源的权威清单读取，再重建运行槽。全库 `pnpm format`、完整 `pnpm format:check` 通过。`pnpm build` 独立通过，Flutter Web 编译完成，Static Assets 为 57 文件、0 个 current extensions；这是工程构建，不能视为 Source 在线运行。IAB 管理元数据门待补充。

## 实际运行门

尚不宣称已通过真实外部 Source 在线读取、同包替换后的真实图片、独立设备同步、Native、生产 Access 或真机验收。旧固定 AOT 候选不包含本轮协议，不能手工补字段用于当前验收。

`0009` 尚未部署到生产；它重建旧网络政策/Source 设置并要求按来源重新登记。书架、进度与账户安装意图不受该重建影响。新 AOT 必须固定提交后独立构建；首次 baseline 仍未完成。
