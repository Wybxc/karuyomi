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

- 已取得的全局设置 Web 双文档双向读回、旧 CAS 拒绝、新文档恢复和双 iOS 模拟器新进程恢复见上节；漫画继承/覆盖/清空、实际丢响应恢复和同时请求竞争仍待独立客户端验收。
- Web↔iOS↔Android 实际组合、可靠前台恢复、生产 Access、Native 手动触控与真机。
- 该轮三项设置之后，阅读背景、应用内调暗与点击区/键盘预设已继续接入，结果分别见[后续记录](reader-appearance.md)；适宽/适高与裁白已实现，分别见[图像适配](reader-fit.md)和[同步裁白](reader-crop.md)。

当前交付顺序见 [P1](../plan/p1-library-and-progress.md) 与 [P2](../plan/p2-sync.md)。生产、跨端和真机门未因上述工程与组件测试通过。
