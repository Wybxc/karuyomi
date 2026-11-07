# 非敏感阅读设置验证

2026-11-06，本轮优先完成现有三项设置的同步功能：全局应用主题、四种阅读模式、AUTO/SINGLE/DOUBLE 页组，以及阅读模式/页组的逐字段漫画覆盖。设计和继承语义见[设置设计](../design/reader-settings.md)。工程检查、受控组件与独立客户端验收分别计证据。

## 已取得的后端证据

- `pnpm generate:check` 通过，TypeScript/Dart 模型与 `business.proto` 一致；API 类型检查与依赖层级检查通过。
- contracts 业务边界测试 7 项通过，包含设置的枚举、完整默认值、optional 覆盖 presence、有效值合并与响应 revision 校验。
- 官方 Cloudflare Vitest / workerd / 真实 D1 状态测试 24 项通过。其中新增 5 项设置测试覆盖无副作用默认读取、逐字段继承、显式 AUTO、清空覆盖保留 revision 和旧写拒绝。
- 同一测试入口还覆盖 global/manga 并发的独立 CAS 与提交后确认快照、进度与设置互不改动业务 revision、幂等重试和 UUID 跨作用域/消息冲突、subject/请求头隔离、正文预算及 D1 batch 失败回滚。

## 客户端与集中工程结果

正式设置页和阅读页已接入同一身份绑定的设置仓储。全局表单显式保存，主题在读回服务端确认值后应用；阅读页快捷选择写漫画覆盖，弹窗可逐字段恢复继承。只读刷新不重发未确认操作；重新打开编辑器显示原命令值，冲突后明确重读，身份或仓储变化使旧编辑永久失效。

- 新增设置仓储 10 项、完整数据层 72 项通过：默认值、presence、独立作用域、固定 UUID/正文/CAS、ACK 后当前值读回及旧 ACK 冲突。
- 设置控制器/表单 8 项通过：确认前状态、原操作重试、身份变化后的迟到 ACK、全局继承、未编辑表单刷新、编辑后固定 CAS、逐字段继承/显式 AUTO，以及全局/漫画 pending 重开。
- 正式 `KaruyomiApp` 组件导航 2 项通过：保存前主题不变，确认后 MaterialApp 使用主题；详情进入阅读继承全局，阅读选择写漫画覆盖；弹窗逐字段恢复继承，AUTO 在切章和退出重开后保持，程序应用不产生额外设置写入。
- `pnpm check` 完整通过：372 项 Vitest、协议 golden 与全部工具测试通过，157 模块 / 509 依赖无违规。
- `pnpm flutter:check` 完整通过：reader_core 21、source_runtime 42、客户端 291 项，静态检查无问题。现有进度导航回归通过正式设置命令选择布局，并验证迟到 viewport 报告不能覆盖已确认偏好；更新测试未移除原进度、远端重开和来源顺序断言。
- `pnpm format`、完整 `pnpm format:check` 与 `pnpm build` 通过；正式 Web/Native runtime 资源、Flutter Web 和 Worker/Static Assets 构建成功。

这些客户端结果使用受控 Source/业务 supplier，不是独立浏览器、模拟器、生产 Access 或真机验收。官方 workerd/D1 证据与组件导航分开计算。详细临时输出保留在忽略的 `.local/settings-*.log`。

## 2026-11-07：独立 Web 文档与双 iOS 模拟器

本轮使用正式客户端、官方 Vite / Wrangler acceptance harness 和真实 workerd / D1，所有设置写入均由正式设置表单的保存操作发起。独立验收只发 GET，逐阶段核对完整权威快照、account/global revision 和其余字段；没有直接写 API 来替代 UI。Web 与 Native 使用两个隔离服务和独立 D1，虽然测试 subject 都是 `acceptance-owner`，仍不是同一服务身份的 Web↔Native 验收。索引均为零扩展，未启动 Source。

### 真实交付边界发现并修复默认值确认错误

首次 Web 双文档验收发现：B 保存关闭裁白后，D1 已到 revision 2，UI 却提示设置尚未确认。正式 Protobuf-ES ProtoJSON 会省略非 optional 的 `false` / `0`，Dart 的 Protobuf 对象相等比较却区分显式默认值和未赋值，导致客户端误拒已提交的 ACK。此现场和修复前失败日志均保留，没有把这次失败记为 CAS 冲突或已完成的原 UUID 重试。

修复提交 `804e5ef` 对完整全局设置使用生成 getter 的值语义比较，保留三个列表的顺序；漫画 optional 覆盖继续严格比较 presence。独立设置仓储回归先取得红测试，再全文件 16/16 通过，新增四项覆盖全局 `true→false` / `35→0`、扩展 `enabled=false`、同 revision 仅 wire 默认值 presence 变化，以及漫画显式 `false` / `0` 与继承的区别。修复后完整格式化、格式检查和 `pnpm build` 通过；`pnpm flutter:check` 为 reader_core 22、source_runtime 78、客户端 577，依赖检查为 179 模块 / 590 依赖无违规。本地没有重新执行全套 `pnpm check`；独立核对精确修复提交 `804e5efc7423baf013507fb97d049dcb652cda52` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42286890583) 为 completed / success，CI 结果与上述本地命令分别记录。

### Web：双向读回、旧 CAS 拒绝与新文档恢复

Codex 内置浏览器打开 A、B 两个独立文档，随后新建 C 文档。修复后重新启动隔离的 HTTP 服务 `http://127.0.0.1:60778`，D1 从 revision 0 开始；实际提供的 `main.dart.js` SHA-256 为 `e00b3c886cbcf1145bfab20b54ba791bf9d9860ab2a837ccc5694389074942e3`，与本轮构建一致，缓存策略为 `max-age=0, must-revalidate`。

| 阶段                     | 正式 UI 与独立 D1 结果                                                                                                                                                                            |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 编辑未保存             | DARK / RTL / DOUBLE / HEIGHT、裁白 true、调暗 35%；独立 GET 仍为 revision 0 默认值。                                                                                                              |
| A 保存、B 明确重读       | account/global revision 均为 1；B 读回 A 的完整设置。                                                                                                                                             |
| B 编辑未保存             | LIGHT / WEBTOON / AUTO / WIDTH、裁白 false、调暗 0%；独立 GET 仍为 revision 1。                                                                                                                   |
| B 保存、A 明确重读       | account/global revision 均为 2；保存无未确认提示，正式 JSON 实际省略裁白 false 和调暗 0，A 读回完整当前值。                                                                                       |
| 两文档以 revision 2 编辑 | B 保留 SYSTEM 草稿；A 保存 DARK 后 revision 到 3。B 再保存旧草稿时 UI 明确提示其他设备修改，保存和原操作重试禁用；B 明确重读后清除冲突和 pending，恢复 DARK。独立 GET 仍为 revision 3，未覆盖 A。 |
| 新文档 C 初始化          | 未点重新读取或保存即显示 revision 3 的 DARK / WEBTOON / AUTO / WIDTH、裁白 false、调暗 0%；独立 GET 仍为 revision 3。                                                                             |

各阶段阅读背景始终 BLACK、点击区和键盘始终 STANDARD，收藏 Source、安装和额外仓库列表始终为空，有效阅读值与全局值一致。两个 revision 2 草稿依次提交证明旧 CAS 写拒绝，没有记录为两个请求同时到达的竞争；未捕获该 POST 的 HTTP 状态码，仅记录实际 UI 冲突和独立 GET 不变。

本轮不能验收自动前台重取：IAB 的 A/B 后台 surface 都报告 `document.visibilityState=visible`，没有可靠的后台→前台事件。A→B / B→A 使用明确重读；没有把 AX 读取当作生命周期事件。新文档 C 与 A/B 仍处于同一浏览器环境，也不称为全新设备或浏览器进程重启。

### iOS：独立应用进程双向恢复

两台新建的 iPhone 17 Pro / iOS 26.4（23E244）模拟器以 debug 集成测试运行正式 `app.main`、`NativePlatformRuntime` 和全局设置表单。使用独立 HTTPS 服务 `https://127.0.0.1:61168`、受信任测试 CA 和真实 D1；独立 HTTP 核对同样正常校验证书。`integration_test/settings_sync_test.dart` 在五个独立 `flutter test` 调用和新应用进程中分别运行，五阶段均通过：

| 阶段         | account/global revision 与结果                     |
| ------------ | -------------------------------------------------- |
| A 首次只读   | 0→0，SYSTEM / LTR / AUTO / CONTAIN、裁白 false。   |
| B 首次保存   | 0→1，DARK / RTL / DOUBLE / WIDTH、裁白 true。      |
| A 新进程只读 | 1→1，从 D1 恢复 B 的完整设置。                     |
| A 新进程保存 | 1→2，LIGHT / WEBTOON / AUTO / HEIGHT、裁白 false。 |
| B 新进程只读 | 2→2，从 D1 恢复 A 的完整设置。                     |

保存前草稿不改变应用主题或已确认快照；ACK 和当前 GET 确认后才应用主题、清除 pending。正式 TS 响应在裁白关闭后省略 `cropBorders`，Native 仍成功确认；调暗本轮始终为 0，不据此声称验证非零调暗归零。BLACK、STANDARD 输入预设和三个空列表保持不变，未创建 Source 会话或未保存阅读进度。独立验收逐一解析五份 `SETTINGS_SYNC_RESULT` 与通过标志，并在每阶段 GET 核对 revision 和全部字段。

复验先在已完成正式构建的主树装配 Native 官方 harness，再用仅供本地验收的现有 CA 和证书启动 HTTPS；证书及模拟器信任准备见[Native 分类验收](category-ui-sync.md)。

```sh
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts --mode native-acceptance
NODE_EXTRA_CA_CERTS="$PWD/.local/category-native/tls/rootCA.pem" \
  WRANGLER_HTTPS_KEY_PATH="$PWD/.local/category-native/tls/key.pem" \
  WRANGLER_HTTPS_CERT_PATH="$PWD/.local/category-native/tls/cert.pem" \
  pnpm acceptance:serve
```

从该服务 GET 当前完整 ProtoJSON，用 JSON 工具生成忽略的本地阶段配置文件。`APP_ORIGIN`、`SETTINGS_SUBJECT`、`SETTINGS_PHASE` 和 `SETTINGS_EXPECT_JSON` 都是字符串；最后一项是完整 `SettingsResponse` 的 JSON 字符串，不能只填写 revision。验证阶段使用 `SETTINGS_PHASE=verify` 且不设置 preset；写阶段使用 `SETTINGS_PHASE=write`，并填写 `SETTINGS_PRESET=dark-rtl-double-width-crop` 或 `light-webtoon-auto-height-no-crop`。配置文件通过绝对路径传入，避免把任意完整 JSON 内嵌到 shell：

```sh
cd apps/reader
flutter test integration_test/settings_sync_test.dart --no-pub -d <simulator-udid> \
  --dart-define-from-file=/绝对路径/.local/settings-native/phase.json \
  --reporter expanded
```

每阶段须以新的当前快照为前置，不盲目重跑写阶段。实际五份配置文件 `{a1-verify,b1-write-dark,a2-verify,a3-write-light,b2-verify}.defines.json` 和各阶段原始 GET 留在 `.local/settings-native-20261107/`。

本轮日志和临时快照保留在忽略目录：`.local/settings-defaults-{format,format-check,flutter-check,build}.log`、`.local/settings-native-20261107/` 与 `/private/tmp/karuyomi-settings-{web-fixed,native}-*.json`；修复前红测试为 `/private/tmp/karuyomi-settings-protojson-defaults-red.log`，完整设置仓储绿测试为 `/private/tmp/karuyomi-settings-protojson-defaults-final.log`。Native 汇总为 `.local/settings-native-20261107/results.json`，含设备、输入摘要、五阶段完整结果与清理记录。详细机器输出和截图不入库。Web / Native 两个 harness 均正常 exit 0，端口 60778 / 61168 已释放，本轮测试进程无残留；Native 两台专用模拟器已关闭并删除。

上述新证据覆盖全局设置的 Web↔Web、iOS 模拟器↔iOS 模拟器在线读写。漫画继承/覆盖/清空、实际丢响应原操作恢复、可靠前台恢复、Web↔Native、Android、生产 Access、真机手势及性能仍须分别验收。

## 2026-11-07：同服务重连与无效配置的受控回归

后续只读复审发现两个正式 AppShell 路径会丢失未确认命令的入口：Native 点击“连接服务”即使仍是原 origin，也会替换 Catalog / 设置仓储；无效新地址则会先拆除旧服务，再由 Native 构造器拒绝配置。修复后，同一已验证服务的空路径和根尾斜杠使用原平台重建运行时，再 bootstrap 确认当前 subject，保留同身份的 BusinessStateClient 和原 pending；不会因重新连接自动重发设置写入。

切换服务先用正式平台构造器验证候选，失败时保留旧设置面板、会话和原命令；尚未采用的候选由 `finally` 释放。真正切换 origin 或 bootstrap 返回不同 subject 时，旧编辑永久退役，新身份使用独立命令与 CAS。只读复核同时检查了候选所有权、卸载期间的释放和身份隔离。

正式 `settings_navigation_test.dart` 全文件 10/10 通过，其中原有 3 项导航回归保留，新增 7 项为：

- 同服务空路径、根尾斜杠两种重连：业务 supplier 已提交但 ACK 正文截断；重连只 bootstrap / 重读，原 UUID、正文、expectedRevision 留在当前会话。只有明确点“重试原设置操作”才重发逐字相同正文，累计仅应用一次写入。
- 三种无效地址：额外路径、HTTP 与畸形 URI。修复前 3/3 均因设置面板丢失失败；修复后配置被拒而旧 pending 保持可处理，改回原服务再明确重试成功，原 POST 正文不变。
- 真正切换服务、同服务切换 subject：旧编辑不能重试，也不向新身份发送旧命令；新写使用新 UUID、当前身份和独立 CAS。

独立验收只读审查产品差异，并核对红日志与最终 `All tests passed`。修复前证据在 `/private/tmp/karuyomi-settings-invalid-origin-red.log`，完整导航绿日志在 `/private/tmp/karuyomi-settings-reconnect-final-green.log`。最终完整 `pnpm flutter:check` 通过：reader_core 22、source_runtime 78、客户端 584，三个项目静态分析无问题，日志为 `.local/settings-reconnect-final-flutter-check.log`。这是正式 AppShell 与受控 TestPlatform / 业务 supplier 的组件回归，未新增真实设备丢响应、Access 续期或网络故障验收。

固定提交 `2123b5b7d6fcf897f0120e1873001f398363b968` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42288468310) 和本节修复提交 `eee2b8115ccf215bb8d1c57dd7bec76d16333195` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42292436578) 均已独立核对为 completed / success。上述 AppShell 修复与固定 `2123b5b` 的设备副本是不同输入，不能用旧设备运行证明本节新修复已在设备执行。

## 2026-11-07：零 Source 业务 API 的受控 Access 恢复

后续审计发现，私有 API 在尚未打开 Source 时返回 401、403、跳转或登录 HTML，宿主只把它们作为 HTTP 结果交付，未向 Dart 发出结构化 Access 错误。因此设置保存可能保留未确认命令，却没有进入正式登录恢复入口。修复后，当前请求所属代际的私有 API 401、跳转及 HTML 返回 `access_required`，403 返回 `access_denied`，经正式 ProtoJSON 控制响应进入 Dart 的 Access 暂停和 Catalog 登录状态；公开扩展目录、业务 409 与 5xx 仍保留原 HTTP 语义。

运行时宿主使用受控 Fetch Response 与正式 `host-api.control` 验证零 Source 和已有 Source 两种状态，包含普通和 opaque 跳转、HTML Content-Type 大小写、响应正文取消失败，以及资源保留。manager 78 项与 Native/image 17 项合计 95/95 通过；这不是连接真实 Access 服务的 HTTP 验收。独立复审还发现正文 `cancel()` 的异步窗口：清理旧失败响应时若已打开新 Source，旧错误不能暂停新代。零/已有 Source 两项回归修复前均失败；修复后先等待正文取消，再在同步发布段检查当前 generation 和 disposed，过期响应保留 HTTP 状态并返回空正文，不重读已取消的流。红绿日志分别为 `/private/tmp/karuyomi-api-access-cleanup-{red,green}.log`。

Dart 的正式 `TransportSourceRuntime` 用生成的 `ControlResponse` 和受控传输覆盖零/已有 Source × Access required/denied 四种错误。另四项延迟 envelope 回归在修复前均因旧 `RuntimeEvent` 污染新 Source 失败；修复后仅将过期 Access 错误交给原调用者，不修改新会话的 Access 状态或发出事件。成功业务 ACK 继续独立于 Source 换代。晚交付红绿证据为 `/private/tmp/karuyomi-api-access-delivery-{red,green}.log`。

正式 AppShell 新增两项零 Source 设置回归，全导航文件 12/12 通过：受控业务 supplier 已应用设置后返回 typed Access required/denied 错误，UI 显示正式登录入口，暂停编辑并保留原命令；登录恢复保留原 BusinessStateClient，不自动重发写入；明确点击“重试原设置操作”才重发逐字相同的 UUID / 正文 / CAS，累计只应用一次。该组件测试直接提供结构化错误，未把它记作实际 Fetch、登录弹窗或生产 Access 续期。日志为 `/private/tmp/karuyomi-settings-access-navigation.log`。

扩大回归执行完整 `packages/runtime-host/test`，14 个文件 / 217 项全部通过，日志为 `.local/settings-api-access-host-all.log`；上述 95 项是其中的定向集合。全仓 `pnpm typecheck` 与 `pnpm check:dependencies` 通过，依赖检查为 179 模块 / 590 依赖无违规，分别记录在 `.local/settings-api-access-{typecheck,dependencies}.log`。

最终完整 `pnpm check` 通过，包含 33 个文件 / 505 项 Vitest、协议 golden 和全部工具测试；完整 `pnpm flutter:check` 为 reader_core 22、source_runtime 86、客户端 586 项，三个项目静态分析无问题、172 个 Dart 文件格式零差异，日志为 `.local/settings-api-access-final-{check,flutter-check}.log`。完整 `pnpm build` 通过并核对 57 个静态文件 / 0 个当前扩展，日志为 `.local/settings-api-access-final-build.log`；该零扩展工程构建不计为在线 Source 或生产 Access 验收。

## 2026-11-07：Android↔iOS 同服务全局设置同步

本轮新建 Android Pixel 9 / API 36 Google APIs ARM64 模拟器和 iPhone 17 Pro / iOS 26.4 模拟器，使用同一个正式 HTTPS acceptance 服务 `https://127.0.0.1:52754`、同一 subject `acceptance-owner` 和同一真实 D1。服务从 revision 0 开始，所有写入均通过正式 `app.main`、NativePlatformRuntime 与设置表单发起；独立验收只发正常校验证书的 GET，没有代写业务状态。各阶段为独立 `flutter test` 调用和新应用进程，实际报告平台分别为 `android` / `ios`，不是 Web 模式或单平台改写标签。

| 阶段               | account/global revision 与实际结果                 |
| ------------------ | -------------------------------------------------- |
| iOS 首次只读       | 0→0，SYSTEM / LTR / AUTO / CONTAIN、裁白 false。   |
| Android 正式保存   | 0→1，DARK / RTL / DOUBLE / WIDTH、裁白 true。      |
| iOS 新进程只读     | 1→1，读回 Android 保存的完整设置。                 |
| iOS 正式保存       | 1→2，LIGHT / WEBTOON / AUTO / HEIGHT、裁白 false。 |
| Android 新进程只读 | 2→2，读回 iOS 保存的完整设置。                     |

独立验收解析全部五份 `SETTINGS_SYNC_RESULT` 与通过标志，每阶段 GET 核对完整 global / effectiveReader 和 revision；最后的完整权威响应与 iOS 写后相同，没有新增写入。保存前草稿不改变应用主题或已确认设置，ACK 和当前 GET 确认后才应用主题并清除 pending。裁白关闭后的正式 TS ProtoJSON 实际省略 `cropBorders=false`，Android 仍正确确认和恢复；调暗始终为 0，不据此声称非零调暗归零已在该设备组合验收。背景 BLACK、输入预设 STANDARD 和三个空列表保持不变；零扩展索引、无 Source 会话，也未创建未保存阅读进度。

两平台产品固定在 `2123b5b7d6fcf897f0120e1873001f398363b968` 的同一忽略副本。逐文件身份记录共 95 项；验收驱动之外的 94 项输入在本轮保持不变。首次 iOS 只读使用驱动 SHA-256 `5e15a9014e4ee9cffbec836fd424a9e0cd50e8ea21d7ab055e2ffca4f44e6319`，其余成功阶段使用追加测试 CA 输入的正式驱动 `4ffc0a9c056a9c00beb6a5ebba59479e3100d2a892cf19715f073b9fbd15903b`。主树同期的同服务重连和 Access 恢复修复没有混入该固定副本，不能用本节设备结果证明这些新修复已在设备运行。

首次 Android 写入尝试在进入表单前失败，D1 仍为 0；独立诊断取得 Dart `dart:io` 的 `CERTIFICATE_VERIFY_FAILED / unable to get local issuer certificate`，说明 WebView 的测试 CA 配置没有覆盖 Dart HTTP 的信任。正式集成驱动随后新增可选 `SETTINGS_TEST_CA_BASE64`：仅允许已校验的 Android `https://127.0.0.1` origin，用标准库解码本轮 CA 文件字节后，向测试进程默认 `SecurityContext` 追加信任，保留系统根与主机名校验。没有使用 `badCertificateCallback`、`HttpOverrides` 或修改产品 TLS。多行 PEM 参数曾在 Flutter Android 编译层失败，改用标准 Base64 后，先通过独立只读预检确认 revision 仍为 0，才重新进入正式写阶段；这些环境与准备失败日志均保留，没有计作额外业务写入，也没有声称修复了产品启动可靠性。

复验沿上节官方 HTTPS harness 和[正式驱动说明](../../apps/reader/integration_test/README.md)，按每阶段前的完整 GET 生成本地 `--dart-define-from-file` 配置。Android 的配置额外填写本轮 CA 原始字节的标准 Base64 字符串；iOS 不传该字段。完整产品副本、源码身份、配置和运行日志保留在 `.local/settings-android-ios-20261107/`，独立原始响应与审计快照在 `/private/tmp/karuyomi-settings-android-ios-*.json`。这组证据覆盖模拟器 Android↔iOS 同服务的全局设置在线写入和新进程读回；没有验证 Web↔Native、并发竞争、网络故障、生产 Access、真实手动触控或真机性能。

本轮汇总为 `.local/settings-android-ios-20261107/results.json`，保留完整报告、按阶段的驱动 SHA、失败分类、输入身份及清理记录。HTTPS harness 与 Android emulator 均正常 exit 0；端口 52754 已释放，专用 Android AVD 和 iOS 模拟器均已删除，确认 ADB 无设备后关闭本轮 server。独立只读检查未发现可归因本轮的测试、设备或服务进程残留；原有 iOS 设备的元数据差异按实际结果保留在汇总中。

## 2026-11-07：Web 全局设置的真实确认丢失与原样重试

正式 Flutter Web 通过 Codex 内置浏览器连接同一官方 Vite / Wrangler harness（本轮 `http://127.0.0.1:54698`、`acceptance-owner`、独立 D1）。使用正式设置 UI，不加载漫画源，不拦截浏览器 API。夹具仅在显式启用时，在正式 Worker 校验并提交首次成功的全局设置后，确认 D1 中已有匹配回执，再中断 HTTP 200 的响应正文。独立 socket 预验收用普通 Node 24 fetch 收到 200 响应头，正文读取以 `UND_ERR_SOCKET` 失败，确认不是正常读到一份被截短的 JSON。后续同一请求走完整正式回执。

1. A 将默认外观从跟随系统改为深色并保存。UI 提示尚未确认并提供「重试原设置操作」；独立 GET 已读到深色，account / global revision 从 0 / 0 到 1 / 1。
2. A 点击「重新读取设置」，仍保留待确认操作。新文档 B 打开正式设置，读到已提交的深色，无 A 的待确认操作。
3. 回到 A 点击「重试原设置操作」，待确认提示和重试按钮消失，仍显示深色。独立读取的设置与书架在丢确认、A 重读、B 读回和 A 重试四阶段完全相同，revision 保持 1 / 1。其它设置和书架内容未变。

关闭时的 D1 夹具审计只有两次成功 POST 观察：首次截断、第二次放行，UUID、原始正文 SHA-256、预期 revision 0、正式 ACK 与持久回执摘要均一致，显式重试原样重发，服务端仅提交一次。未直接调用业务 POST 为浏览器步骤补数据。测试标签和服务已关闭；证据只覆盖此 Web 全局设置写入的响应中断，不替代设备实际断网、阅读进度恢复、Native 或生产 Access。

在准备好正式 Web/API 输出后，以官方本地入口复验：

```sh
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts
ACCEPTANCE_FIXTURE=settings-ack-loss pnpm acceptance:serve
```

用打印的实际 URL 操作，独立 `GET /api/settings` 和 `GET /api/library` 使用该 origin、`X-App-Subject: acceptance-owner` 与 `X-App-Request: 1`。正常按 Enter 停止，读取 `ACCEPTANCE_SETTINGS_ACK_AUDIT`，要求恰好两条记录及上述不变量。夹具、临时表和故障动作仅存在于隔离的验收入口，默认关闭。

## 可复验入口

```sh
pnpm generate:check
pnpm --filter @karuyomi/api typecheck
pnpm check:dependencies
pnpm exec vitest run --project node packages/contracts/test/business-state.test.ts
pnpm exec vitest run --project workers apps/api/test/state-workerd.test.ts
```

完整工程复验：`pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check`、`pnpm build`。组件可定向运行 `flutter test test/settings/`；使用仓库固定的 Flutter SDK。

## 尚待验收与完整范围

- 已取得的全局设置 Web 双文档双向读回、旧 CAS 拒绝、新文档恢复和双 iOS 模拟器新进程恢复见上节；漫画继承/覆盖/清空、其它写入的实际丢响应恢复和同时请求竞争仍待独立客户端验收。
- Android↔iOS 同服务全局设置在线读写和新进程恢复已取得上节模拟器证据；Web↔Native、可靠前台恢复、生产 Access、Native 手动触控与真机仍待验收。
- 该轮三项设置之后，阅读背景、应用内调暗与点击区/键盘预设已继续接入，结果分别见[后续记录](reader-appearance.md)；适宽/适高与裁白已实现，分别见[图像适配](reader-fit.md)和[同步裁白](reader-crop.md)。

当前交付顺序见 [P1](../plan/p1-library-and-progress.md) 与 [P2](../plan/p2-sync.md)。生产、跨端和真机门未因上述工程与组件测试通过。
