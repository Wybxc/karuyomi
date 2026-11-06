# 额外仓库验证

2026-11-07，本地 macOS，固定 Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4。正式协议、API/D1、登记工具、runtime-host 和 Flutter 管理入口已接入；实现范围见[设计](../design/additional-repositories.md)，待办见[计划](../plan/additional-repositories.md)。

## 独立集中工程检查

`pnpm check` 已独立完整通过：生成一致性、portable 格式、严格 TypeScript 和依赖检查，32 文件 465 项 Vitest、10 项跨语言 golden、34 项登记/网络政策、50 项扩展工具、14 项构建、15 项产物完整性、4 项 TeaVM 和 9 项 Cloudflare 回归均绿。没有缩小检查或跳项。

定向与审查覆盖：catalog URL/repoId 必填和 ACK 回显、四个 HTTP 来源头、跨仓 buildId 冲突整批回滚、来源范围内退役/hosts 继承、D1 Source 设置隔离与外仓空同步规则、原 CAS/未知 ACK、同包明确换仓、只读预览/刷新、移除保留安装引用、公开下载无凭据/无重定向及主动取消。namespace 增加应用 origin，避免 Native 在两个 API 部署间复用同 subject/外仓的数据。

独立审查发现并修复了准备 ACK 字段误置、Web 下载默认携带同源凭据、额外仓读取缺少逐请求生命周期、设置与管理面板首帧前身份变化、以及对话框退出动画提前释放输入控制器的问题。Web 元数据 fetch 明确使用 `cache: no-cache`；它仍服从 HTTP 缓存再验证，不自行维护另一份目录权威。

最后的 Dart 来源设置面板窄修发生在上述 TS 集中检查之后，未修改已冻结的 TS/API/协议。完整 `pnpm flutter:check` 重跑已通过：三个包严格分析均绿，Reader Core 22 项、Source Runtime 68 项、Reader 527 项全部通过，163 份自有 Dart 格式零变化。首轮完整 Flutter 的 7 项失败已修复，保留原业务断言；来源设置恢复先完成精确来源的权威清单读取，再重建运行槽。全库 `pnpm format`、完整 `pnpm format:check` 通过。`pnpm build` 独立通过，Flutter Web 编译完成，Static Assets 为 57 文件、0 个 current extensions；这是工程构建，不能视为 Source 在线运行。随后真实 IAB 发现的身份请求缺口与修复后分项见下节。

## Codex 内置浏览器与真实 Source 分项

同日，主代理在 Codex 内置浏览器操作正式 Flutter Web，独立验收代理负责只读 HTTP/D1 核对及完整工程回归。应用使用官方 Wrangler `createTestHarness`、隔离 workerd/D1 和 RS256 测试身份 `acceptance-owner`；外仓使用官方 Wrangler assets-only CLI，`repoId=acceptance-extra`、空 builds、CORS `*` 和 `Cache-Control: public,max-age=3600`。没有操作其它浏览器或部署生产。

首次实际操作发现：初次管理刷新和确认添加后的刷新显示泛化错误，账户仓库已经保存。独立 A/B 请求确认 `/api/extensions/network-policies` 漏带 `X-App-Subject`，无头返回 `403 identity_changed`，正确头返回 200；原工程 fake 未强制这条合同。修复后该 GET 复用正式业务客户端和已确认身份头，绑定客户端与 epoch，清除旧就绪结果；普通网络失败保留当前 Source，Access 失效退休旧管理页。服务端身份校验保持不变，旧身份迟到结果与失败路径已补正式回归。

修复后重新创建干净 harness，使用当前固定 `3ed3945` 三包 AOT，未给旧清单补字段。完整 `pnpm flutter:check` 重跑通过：三个包严格分析、Reader Core 22、Source Runtime 68、Reader 534 项，以及 163 份 Dart 格式全部通过。完整 `pnpm build` 通过；随后通过官方 API Vite 配置装配候选，64 个 Static Assets / 3 个 current extensions，并重建 acceptance 配置。只登记英语 xkcd 所需的 `xkcd.com`、`imgs.xkcd.com`，其它两包明确显示网络待登记。`3ed3945` 的 GitHub CI 也已全部通过。

实际通过的分项：

- 管理页初次刷新正常；外仓只读预览显示原身份和零扩展，停在确认弹窗时独立 HTTP 确认 account/global revision 仍为 0、仓库为空。
- 明确添加后显示成功，第二个独立应用标签读回同一仓库。外仓 HTTP 改为不同 repoId 后，检查更新识别读取失败，账户仍 revision 1 和原身份；还原外仓后刷新恢复。该门实测了 max-age 3600 下的再验证，没有接受变化后的来源。
- 明确移除后两个标签依次刷新均显示零额外仓库；这是顺序收敛，未测同时写竞争。
- 默认 xkcd 正式准备并安装成功；独立 HTTP 确认 global revision 3、enabled=true、精确 build `ext-all.xkcd-5bf877b13dad1a2515bfd386fab67e96` 与 manifest digest。另一独立应用标签刷新读回同一选择；两个标签共享浏览器 IndexedDB，此项不能当作独立设备或空缓存客户端证据。
- 通过该安装选择打开英语 Source `1538249443376436084`，真实热门、详情和 3319 章列表返回；收藏按钮获得服务端确认。打开第 3320 章后，真实漫画首图和插件生成的第二页文字图均在正式 Flutter Reader 显示，UI 确认 `2/2` 阅读进度已保存到服务端、最远第 2 页。没有用图片原 URL 绕过插件处理。独立 HTTP/D1 核对 account revision 7、global revision 3，唯一英文 xkcd favorite=true，当前与最远 pageIndexHint 均为 1（第 2 页），最远 normalizedOffset=1；设置仍只安装原精确构建。

临时证据与原失败日志留在 `/private/tmp/karuyomi-additional-repositories-acceptance-*`，首图截图为 `/private/tmp/karuyomi-current-aot-xkcd-reader.jpg`；它们不作为源码或公开产品资产提交。三包 AOT 固定输入、传输收据与首次 baseline 限制见[扩展管理记录](extension-management.md#固定-3ed3945-三包-aot-候选)。本轮保留候选 `compiled_unverified/runtimeReady=false`，不将单个 Web 分项提升为完整兼容声明。

## 剩余实际运行门

尚不宣称已通过真实外仓 Source 在线读取、同包换仓后的图片、同时写竞争、独立设备同步、Native、生产 Access 或真机验收。早期固定 `ad869d2` 候选不含本轮协议，不能补字段冒充新产物。

`0009` 尚未部署到生产；它重建旧网络政策/Source 设置并要求按来源重新登记。书架、进度与账户安装意图不受该重建影响。新 AOT 必须固定提交后独立构建；首次 baseline 仍未完成。
