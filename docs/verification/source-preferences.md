# typed Source preferences 工程与运行验收

当前实现使用 `karuyomi-source-host-v6`，设计见[Source 设置](../design/source-preferences.md)，任务与完整验收门见[计划](../plan/source-preferences.md)。本记录区分工程检查、固定 AOT、真实 Source 与独立客户端结果。

## 已取得的工程证据

2026-11-06，main 的 Source 设置里程碑：

- `pnpm format` 后完整 `pnpm format:check` 通过，包含 macOS/Xcode 原生格式检查；`pnpm check` 完整通过，含生成一致性、依赖层级、类型、官方测试与工具回归。
- `pnpm flutter:check`：reader_core 22、source_runtime 58、reader 443 项全部通过，三个包严格分析无问题；新增产品数据/控制器/480×800 正式组件共 16 项通过，相邻浏览与筛选回归亦通过。
- `pnpm build`：声明式 Vite 的运行时与 Native assets、Flutter Web、Cloudflare Worker/API 构建通过；未据此宣称 Native 应用或真实 Source 设置已验收。
- `pnpm typecheck`：contracts、API 源码及测试、runtime-host、tools 和产品桥的严格 TypeScript 检查通过。
- `pnpm test`：声明式 Vite 构建通过，官方 Vitest 共 30 文件 / 418 项通过，包括 workerd 和真实 D1。测试关闭时的 pipe abort 诊断不改变退出结果。
- Node 定向合同/宿主回归 82 项通过：typed 值宽度、默认值与缺省、秘密分区、整体预算、get/edit 映射、driver 构造配置与可信策略、manager BigInt bootstrap、成功/veto/异常后的代次门及队列清理；包含旧 image/verified loader 回归。
- `pnpm test:protocol` 10 项通过，增加设置 bootstrap、描述、change、click、veto 及业务读写的 TS → Dart → TS / Dart → TS → Dart golden，保留标准 ProtoJSON 和 Protobuf 二进制一致性。
- `packages/source_runtime` 新增 11 项正式 Dart 测试通过，含生成 codec 的 int64 越界预拒绝、合法正负边界无损、嵌套 bootstrap、调用方变更隔离、编辑发送一次、成功/veto/异常后阻止 Source 与图片工作、保留 cleanup、新代恢复与旧响应丢弃。严格测试文件分析通过。
- `pnpm teavm:check` 的 HostPreferences oracle 125 断言通过，并通过完整现有 DTO、filters、HTTP、图片、enqueue、文件与网络检查；全部 owned Java 以锁定依赖执行 `javac --release 17` 通过。这是 JVM/oracle 与编译证据，不是 TeaVM AOT 或真实 Source。

统一预算覆盖最多 64 Sources、每源 128 entries / 32KiB、entries 数组总计 64KiB、完整 bootstrap 128KiB，以及树/选项/控制封装上限。未知文本、密码及未批准别名不得进入 API；真实 workerd/D1 的同步许可、幂等旧 ACK、独立 CAS、身份隔离和并发包配额共 5 个定向场景通过。

首轮完整 Flutter 检查发现一处 Dart 括号样式和旧测试第二包的非法身份；修正样式与真实包身份夹具后完整复验通过，未放宽产品校验。格式首轮还遇到并行文档草稿移出导致文件列表失效，冻结文件集后完整重跑通过。原失败日志保留。

详细临时日志位于 main 忽略目录 `.local/source-preferences-*.log`；Java oracle 和全源编译的临时日志在 `/private/tmp/karuyomi-source-preferences-*.log`。不提交机器输出或临时工程。

## 文本设置绑定与输入校验

2026-11-08，正式设置链保留 Source 的有界 `EditText` 绑定任务和 `TextWatcher`。提交候选值先执行原 watcher；当 watcher 设置错误、禁用确认或异常时，不调用原 change listener 或执行默认保存。通过时仍由原 change listener 决定是否默认保存；它主动写入的值按实际分区读取。Flutter 支持输入提示和打开时全选，秘密输入不携带提示。

- `pnpm teavm:check` 通过；HostPreferences oracle 共 191 断言，覆盖原回调顺序、拒绝时跳过 change、有效值持久化、别名写入、只读 Editable、绑定上限和秘密提示隔离。
- `pnpm check` 通过（513 项 Vitest、10 项协议 golden 及工具回归）；TS/Dart 分别校验提示的 UTF-8 预算和秘密边界。
- `pnpm flutter:check` 通过；reader_core、source_runtime 和正式 reader 均通过严格分析与回归，reader 共 604 项。正式设置组件断言显示提示及输入打开时的实际选择范围。
- `pnpm build` 通过，产出 Vite runtime 和 Native 内置材料、Flutter Web 与 Worker/API。

拒绝阻止默认写入和原 change listener，不能撤销原 watcher 自身的副作用。

固定提交 `f1b0d88` 在独立目录以锁定 TeaVM 0.16.0、上游 `efa93f5` 和未修改的原 JAR 重建 FoolSlide Customizable 与 MangaDex。两包均越过原 `EditText` 缺符号并通过 AOT 及 `node --check`：

| 扩展                   | 声明 Source 数 | JS 字节数 | JS SHA-256                                                         |
| ---------------------- | -------------: | --------: | ------------------------------------------------------------------ |
| FoolSlide Customizable |              1 |   4371712 | `58cdf281dec32010d7c85cae081c5a41596912966533688342d825555918881e` |
| MangaDex               |             61 |   4385642 | `23d197c12359f1f3c2feda3ed7e781f122bebc94f415fee07bce8f890f68cb7d` |

原 JAR 摘要、宿主指纹和复验日志在 `/private/tmp/karuyomi-preference-aot-vNGv9d/`，入口为 `freeze.sh` 与 `run.ts`。未执行发布或修改全量 baseline，两包保持 `compiled_unverified/runtimeReady=false`。正式设置界面的结果见下节。

### 双包正式 Web 设置

2026-11-08，固定 `f1b0d88` 的正式 Flutter Web / Worker 通过 `pnpm acceptance:build`，装配上述两包（index SHA-256 `a28862c009afd96039d592ea7a38a1fd28638a4318170d9ddcb5c4b0bedf80c5`）。官方隔离 workerd / D1 与 `acceptance-owner`，Codex 内置浏览器从扩展管理确认安装两包。

- **MangaDex 1.6.1**：英文 Source `2499283573021220255` 经正式 HTTP 桥返回真实热门结果。打开原 `Block groups by UUID`：`not-a-uuid` 被拒绝，重开输入仍为空；输入合法测试 UUID 后，Source 自动重开，设置页读回相同值。重新加载为全新 Web 文档、打开同一 Source 后又为空。独立 API GET 确认两包均无 D1 设置行（账户 revision 2 来自两次安装），该输入只在当前客户端会话。
- **FoolSlide Customizable 1.6.7**：首轮默认 `https://127.0.0.1` 被网络政策拦截；旧 Worker 返回 403 `target_not_allowed`，客户端误判账号无权并关闭设置。独立正式帧复现 403，同时 `/api/bootstrap` 返回 200。固定 `f561a16` 用同一索引和扩展产物重建正式 Web 与 Worker；默认地址仍被拦截，独立正式帧返回 422，账户与 Source 设置保持可用。
- FoolSlide 的正式 Web 复验在 Codex 内置浏览器打开 Source `6351052922295965587` 的原 URL 控件，默认地址打开时实际全选。输入 `not-a-url` 被拒绝，重开仍为默认值；输入 `https://example.com:443/catalog?probe=1` 后，原回调自行保存归一化的 `https://example.com` 并返回 false，重开读回实际值。新 Web 文档恢复默认，安装仍在。独立 API GET 确认没有同步规则或 D1 设置行，账户 revision 1 来自一次安装。

上述 FoolSlide 浏览器版本在回调返回 false 后仍提示“未接受输入”。后续 Flutter 提示改为按实际存储区分：账户或会话值有变化时提示核对实际值；无变化时提示输入被拒绝且设置未更改。Flutter 设置控制器与组件定向回归共 14 项通过，覆盖账户副作用、会话归一化写入及已有会话值下的无变化拒绝；Dart 严格分析通过。新提示未在上述浏览器复验中观察。

原始 API 快照与候选复验入口在 `/private/tmp/karuyomi-preference-aot-vNGv9d/acceptance/`，FoolSlide 二轮步骤和独立 API 证据在 `/private/tmp/karuyomi-preference-policy-6S8TYv5T/`。本轮不证明原 MangaDex 图片、其它语言、FoolSlide 源站或 Native/生产设置。

## Komiic v6 真实 Web 分项

固定 `384627e9f58e6f940effe57d6c6a2d06b32eb016` 的独立 clone，锁定的上游和工具链不变，生成完整 1448 包计划后只选 Komiic 1.6.11。未复用 v5 AOT，未改变全量 baseline 或发布 checkpoint。

| 身份                  | 本轮值                                                             |
| --------------------- | ------------------------------------------------------------------ |
| buildId               | `ext-zh.komiic-8b3f71f1f85cd5857db8abaf969f23c7`                   |
| host ABI / Source     | `karuyomi-source-host-v6` / `792932060924485302`                   |
| canonical SHA-256     | `c0b8c15661e322d8a5a6f2c2616a0b9c5ea8d557d4f40041b51658971a9a681a` |
| gzip / canonical 字节 | 527464 / 1674394                                                   |
| 候选 revision         | `06720893a860473e9f54ff4575473974`                                 |

官方 Gradle、TeaVM AOT、完整性、索引/manifest 和正式静态装配检查通过。候选仅 1 包 available、1447 包 pending，bootstrap 未完成；仍为 `compiled_unverified/runtimeReady=false`，未部署。

客户端/API 使用 `54594de` 的正式 `acceptance:build`，携该候选通过；它与 `384627e` 的产品源码相同，仅多协程调查文档。官方 Wrangler `createTestHarness` 应用正式迁移，使用隔离 D1、真实 RS256 测试身份和明确 `komiic.com` / `komiic.cc` 网络政策。Codex 内置 Chromium、正式 Flutter → manager/TeaHost → 原 Source → 正式 HTTP 桥实际通过：

1. 打开默认 Source，`.com` 的热门请求失败；设置入口仍可用，原控件显示镜像 `komiic.com` 与“同時顯示卷和章節”。
2. 仅通过原镜像控件选择 `komiic.cc` 并应用。D1 的 Source revision 变为 1，保存 `preferred_mirror` 的原始字符串值 `1`；重开后的原设置显示 `.cc`，热门真实返回“腦洞學生會”“鬼畜英雄”“ONE PIECE航海王”等作品。未改 URL、Source JAR 或业务源码。
3. 再通过原控件选择“僅顯示章節”。D1 revision 变为 2，同时保留 `CHAPTER_FILTER=chapter` 与 `preferred_mirror=1`，没有因完整分区替换丢失上一设置。
4. 关闭第一个标签，打开全新 Web 文档并重新加载扩展和 Source。没有再次编辑，首个热门请求成功；设置页显示 `komiic.cc` 与“僅顯示章節”。这是相同 origin 的独立文档/Worker，确认值由 D1 读取并在 Source 构造前注入；不是独立 Native 安装或浏览器 profile。

设置恢复已有可视记录。此后继续打开筛选时浏览器报告该临时标签已不属于当前会话，标签清单为空；没有实际执行新的 Komiic 筛选门，不将本轮热门成功登记为筛选或完整阅读通过。官方验收服务随后按 Enter 正常关闭。

界面还发现成功后提示一直写“正在重新打开”，已改为准确的确认完成提示；原控制器与正式组件回归 10 项通过，该文案修正不扩展上述运行证据。工程提交 `384627e` 与文档提交 `54594de` 的[通用 CI](https://github.com/Wybxc/karuyomi/actions/runs/42154045691)均已通过，含完整检查、Flutter、构建和本地迁移。

复验入口：

```sh
EXTENSION_ASSETS_DIR=/private/tmp/karuyomi-source-preferences-384627e/.local/source-preferences-validation/snapshot pnpm acceptance:build
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.zh.komiic","allowedHosts":["komiic.com","komiic.cc"]}]' pnpm acceptance:serve
```

固定输入、独立 state 与本机路径见该 clone 的忽略目录 `.local/source-preferences-validation/`。临时 clone 清理后需按上述固定输入重新构建，不将产物或详细日志入库。

## 尚未通过的运行门

- [ ] 其它真实 Source 控件、原 click/veto、实际别名、动态依赖、密码/会话值与刷新；Komiic 仅通过本轮明确的原单选/镜像和新文档恢复分项。
- [ ] 同一身份 Web 与独立 Native 读取/修改非敏感设置后收敛，确认旧 ACK 不回退 Source 构造基线。
- [ ] Web/iOS/Android 各自正式入口、取消/身份切换及秘密值仅当前会话的实际运行。
- [ ] 生产 Access 正向和目标真机门。

本次未部署生产、未修改扩展 baseline，也未把包标为 `runtimeReady=true`。AOT 编译、工程检查和真实阅读是独立验收层级。
