# 扩展管理验证

设计见[账户扩展与本机准备](../design/extension-management.md)，待办与验收条件见[计划](../plan/extension-management.md)。当前状态为**默认仓库功能和集中工程检查通过，实际平台验收继续进行**；以下区分定向、独立集中检查与实际 Source、独立客户端及 Native 层级。

## 定向 TypeScript、D1 与协议

2026-11-06，本地 macOS，主树基于 `830161c` 的未提交扩展管理变更。使用固定 Node 24.15.0、pnpm 12.6.0、Flutter 3.47.5 / Dart 3.13.4 和项目工具链；测试没有部署或改动正式 baseline/checkpoint。

- 四个 contracts/runtime 文件共 72 项通过：新控制合同、真实 Node Web Locks 配合 `fake-indexeddb@6.2.7` 的产物缓存、正式 manager 与 loader。
- 业务合同与官方 workerd/D1 两文件共 50 项通过：账户 installed 清单读写、替换、移除、CAS、原 UUID 重试，以及其它全局设置保留。API 与 contracts 严格类型检查通过。
- `pnpm typecheck` 全部通过，包含协议/contracts/API/runtime-host、工具和桥。
- `pnpm test:protocol` 10 项通过，生成 TS↔Dart 的 ProtoJSON/二进制 golden 包含新管理控制与 enabled true/false 的账户记录。首轮遗漏 `FLUTTER_ROOT` 导致 Dart ENOENT，保留失败后按正确环境重跑通过；不将其写成产品行为失败或跳过项。

定向复验入口：

```sh
pnpm exec vitest run packages/contracts/test/extension-management.test.ts packages/runtime-host/test/extension-artifact-cache.test.ts packages/runtime-host/test/manager.test.ts packages/runtime-host/test/verified-loader.test.ts
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts
pnpm typecheck
pnpm test:protocol
```

实际检查范围：

- 账户 URL、字段、128 项限额和 package 唯一约束；新控制请求/响应的 descriptor、digest、预算与结果语义。D1 保存的是账户意图，本机缓存不作为业务权威。
- 缓存 metadata/bytes 原子预算、跨实例读写、复制后存储、重开、重复准备不重复计费、事务 abort、shared pin 和排他删除。受控 IndexedDB 不等同于实际浏览器/WebView 持久性或系统磁盘压力。
- 准备只用正式静态加载路径，不创建 Source Worker 或调用 Source；验证后缓存命中不重复 hash，失败不终止已活动 Source；清理取消并等待准备，迟到下载不能重新写回已删除副本。
- 精确 close 等待 Worker ACK，关闭期间拒绝 open；活动请求下拒绝关闭，shutdown 失败不伪报成功；新槽建立后旧代 close 不会关闭新代。测试使用受控 Worker supplier，不能据此声称官方 Source 已排空。

临时日志分别保留在 `/private/tmp/karuyomi-extension-management-*.log` 和 `/private/tmp/karuyomi-extension-intents-validation-20261106/`，不将原始机器输出入库。上述计数属于已执行批次；之后新增回归与最终检查以实际补录为准。

## 独立审查与恢复回归

独立验收发现并修复了清理失败 Future 永久阻止重试、承接未保存进度后安装订阅漏重绑、关闭期间继续接收新请求，以及真实 Worker shutdown 失败后仅重试 close 无法恢复的问题。组件回归保留原资源身份和占用直至 ACK，不通过丢弃资源或伪造 shutdown 成功绕过失败。

新增正式 manager/loader 回归通过：准备的真实停滞 stream 在 60 秒超时取消，活动 Source 保持可用；dispose 排空期间拒新调用、迟到准备结果被拒；Native 准备只检查内置材料身份，缺失不网络回退；跨 loader 的已验证产物命中不重新 hash。shutdown 失败后的旧 close 继续失败，独立 rebuild 返回 completed 后可清理缓存并打开新代，未将 reset 说成 closed ACK。manager 与 loader 两文件最终定向 69 项通过，日志在 `/private/tmp/karuyomi-extension-runtime-lifecycle-tests-green.log`。

## 独立集中工程检查

2026-11-07，全库格式通过后，独立验收代理在冻结代码上顺序完成正式检查与构建；本轮结果如下：

- 全库 `pnpm format` → 完整 macOS `pnpm format:check` 通过，包含全部项目自有语言。
- 完整 `pnpm check` exit 0：生成一致性、portable 格式、严格类型、依赖层级、正式测试构建、32 文件 445 项 Vitest、10 项跨语言 golden，以及全部注册、扩展、工具链、完整性、上游 patch 和 Cloudflare 工具测试通过。
- 完整 `pnpm flutter:check` exit 0：三包严格分析无问题，reader_core 22、source_runtime 63、Reader 470 项测试全部通过，151 个 Dart 文件格式无变动。管理页、四打开路径的未安装/停用门禁、原请求失 ACK 恢复、更新/取消、订阅重绑、精确清理重试和 Native 文件占用均有回归。
- 完整 `pnpm build` exit 0：Web/Native 运行时 JS 与内置资源、Flutter Web 和 API Static Assets 均构建成功；实际装配 57 静态文件、0 current extensions。这是空扩展目录的工程构建，不是 Source 或原生 App/设备验收。
- 独立审查确认原全局 UUID/body/CAS、缺记录不自动安装、取消与迟到结果、精确关闭与显式 reset、跨实例缓存引用和已确认停用的调用门禁。`git diff --check` 通过。

首轮完整检查保留两类失败：Native 直接 import 测试漏设新增 Vite define；五项旧 Flutter 夹具没有为新身份/新构建明确安装。补齐夹具后重跑完整检查通过，未在产品自动安装、弱化原业务断言或跳过检查。独立验收本轮再次检查到 IAB inventory 为空，未尝试其它浏览器。

最终日志为 `/private/tmp/karuyomi-extension-management-acceptance-{check,flutter,build}-green.log`；定向管理/Native 45 项与四个旧夹具文件 39 项的日志留在同目录 `karuyomi-extension-ui-*` / `karuyomi-extension-fixtures-final.log`。临时机器输出不提交。

## 待实际运行验收

本节初次集中验收时，Codex 内置浏览器 provider 不可用：可用 browser 清单为空，创建 IAB 标签返回 `Browser is not available`，`open_in_codex` 仅 queued；未操作其它桌面浏览器。生产 Access 用户选择稍后登录，该会话不作为本轮已完成证据。

尚待在符合当前元数据/协议的新固定 AOT 与正式客户端完成：

- Web / iOS / Android 的安装准备、明确更新、启停、卸载、占用/清理，以及真实 Source 打开和阅读。
- 两个独立客户端同身份读回相同账户选择；空缓存客户端准确显示未准备。并发改全局设置、ACK 丢失、旧 CAS 冲突与原请求重试不覆盖其它已确认值。
- 活动章节、请求与跨实例 namespace/产物占用下，关闭、取消、迟到结果及清理失败恢复；卸载保留全部业务、Source 数据与 HTTP Cache。
- 下架构建提示与 `build_not_found` 分层，不自动换版，也不把缓存命中当在线能力。
- 生产 Access 和真机门；该功能提交当时尚无新 AOT 或 Native App 构建/运行、部署、checkpoint 变更；后续固定三包候选另见下节。

额外仓库随后已接入正式合同、账户读写与运行来源隔离；当前工程与实际浏览器门见[额外仓库验证](additional-repositories.md)。本节早期默认仓库入口证据不自动覆盖额外仓库。

## 固定 ad869d2 三包 AOT 候选

2026-11-07，在 `fedora@clab` 的独立目录 `/home/fedora/karuyomi-builds/extensions-ad869d2-20261107-0020` 固定 `ad869d2759ae9d878a89154f80a1d094bba36564`，三份 submodule 与锁定 gitlink 匹配、tracked 输入干净；Linux x86_64、Node 24.15.0、pnpm 12.6.0、Temurin JDK 25.0.5+8。三包官方 Gradle → TeaVM → 正式完整性 → `prepare-snapshot` 通过，没有修改官方扩展业务或原 JAR。

| 包        | buildId                                          | canonical / gzip 字节 |
| --------- | ------------------------------------------------ | --------------------- |
| all.xkcd  | `ext-all.xkcd-38ab36e0fc4a177f69711e53c4a9b60a`  | 4467904 / 929613      |
| zh.bh3    | `ext-zh.bh3-e29e80275074264edf4c2b1c118ab470`    | 4321388 / 886365      |
| zh.komiic | `ext-zh.komiic-e537a3bfc1a8490c5586fa0ae3cf0b0f` | 1865559 / 573768      |

xkcd 正式 Gradle metadata 含 en/ru/es/zh/fr 五个 Source，BH3/Komiic 各一个 zh Source；没有给旧清单补字段。hostFingerprint 为 `ea289e6aa7a37950cfefd072a14e2158cc170dedaeb7a7e38caf6d8e1489a4c4`，materialVersion 为 `24275ab6ea0ae12e91869699faabba7024272784b2d6d1d243be69ec67bfb9de`。候选 revision `6ff8677868024a298782c7831c970f33`，3 available / 0 failed / 1445 pending，`bootstrap.complete=false`。

归档取回边界校验一次，通过后复用验证收据。首轮临时选择器误写 `en.xkcd`，在 AOT 前退出；实际 `ps` 确认终态后以官方 `all.xkcd` 在原总期限内恢复，原失败日志保留。最终 controller exit 0，控制器、timeout 和本目录构建进程均已实际确认不存在；无重复发布器。

全部仍为 `compiled_unverified/runtimeReady=false`，没有部署、Release 或正式 checkpoint 写入，baseline 未完成。该固定输入包含当时的目录元数据和扩展管理协议，尚无后续源迁移变更；后续实际验收须核对产品 host/材料身份，不能据此宣称新协议、真实 Source、浏览器或 Native 通过。

候选 snapshot 位于 `/private/tmp/karuyomi-clab-extensions-ad869d2/remote-results/results/snapshot`，正式 materials catalog 位于同一 `results/materials.json`；`RESULTS.md`、saved plan、summary 和原始日志均保留在该临时目录，不提交大产物。复验以同一固定 checkout、锁定环境及 saved plan 调用正式 `tools/extensions/pipeline.ts build` / `prepare-snapshot`；正式发布、checkpoint 和单发布器约束仍以 [EXTENSIONS](../EXTENSIONS.md) 为准。

## 固定 3ed3945 三包 AOT 候选

2026-11-07，`fedora@clab` 独立目录 `/home/fedora/karuyomi-builds/repositories-3ed39454a4da-20261106182253` 固定已推送提交 `3ed39454a4daf819cd64a9afba6b3f43fc0cdfe2`。Linux x86_64、Node 24.15.0、pnpm 12.6.0、Temurin JDK 25.0.5+8；正式工具链锁/seed 校验和 tracked 输入清洁检查通过。实际 gitlink 为：

- Keiyoushi `efa93f5a3537856fe830450bbe33f69d21d28167`。
- Suwayomi `6b481e8b62938b9c060eb210b934e0fbfdfa466b`。
- TeaVM `e87d452e4bd70c77b9e19314a46c3d6971c148b6`。

三包官方 Gradle → TeaVM → 正式 pipeline 完整性 → `prepare-snapshot` 全部通过，没有修改官方业务源码或原 JAR。新候选由该固定输入正式生成，index 顶层 `repoId=keiyoushi`，没有给旧产物补字段。

| 包        | buildId                                          | canonical / gzip 字节 |
| --------- | ------------------------------------------------ | --------------------- |
| all.xkcd  | `ext-all.xkcd-5bf877b13dad1a2515bfd386fab67e96`  | 4467911 / 929622      |
| zh.bh3    | `ext-zh.bh3-76d8d8b7f32917e1ff3b14b9b02e4e66`    | 4321383 / 886415      |
| zh.komiic | `ext-zh.komiic-cc36675b6c8282249f6de47b539d2af9` | 1865559 / 573768      |

hostFingerprint 为 `514ca5ff478539a30536a3d789d6d262550a88a09c390c4b5fffbad3ef3d9e82`，materialVersion 为 `24275ab6ea0ae12e91869699faabba7024272784b2d6d1d243be69ec67bfb9de`。候选 revision `cbe847ea98be46e688111c1c864c5e1b`，3 available / 0 unavailable / 0 failed / 1445 pending，`bootstrap.complete=false`。全部仍为 `compiled_unverified/runtimeReady=false`；这些事实只证明编译、完整性与静态候选，不是 Source、浏览器、Native 或生产 Access 通过。

首次临时 TS 监督器误用 execa 10 的直接事件接口，在 plan/Gradle 前退出；实际 `ps` 确认旧进程退出后，修为正式 `nodeChildProcess` 接口并恢复。原脚本和失败日志保留，仍以最初 18:22:55Z 起算 90 分钟总期限，18:31:55Z 终态 exit 0，没有改固定产品输入或启动重复发布器。最终 controller PID1010850、timeout PID1010859 均已不存在；扫描本任务 cwd 下的 node/java/gradle/timeout 也为空。未部署、未发布 Release、未写正式 checkpoint，baseline 未完成。

候选 `EXTENSION_ASSETS_DIR` 为 `/private/tmp/karuyomi-clab-repositories-aot-mwoketc7/remote-results/results/snapshot`，正式材料位于同一 `results/materials.json`。归档 5748409 字节、SHA-256 `59673e7ddb4ad18b63258cb96d8630299ee85cad4b4840fde703a16c53a14e4c`，取回边界仅校验一次；收据 `/private/tmp/karuyomi-clab-repositories-aot-mwoketc7/transfer-receipt.json` 后续直接复用，没有重新计算扩展摘要。结构化 summary、saved plan、环境与进程收尾证据和原始日志均留该临时目录，不提交大产物或机器输出。

在同一固定 checkout 和锁定环境中，按 saved plan 使用正式入口复验：

```sh
node tools/extensions/pipeline.ts build --plan ../results/selected-plan.json --key INPUT_FINGERPRINT --output ../results/builds/INPUT_FINGERPRINT
node tools/extensions/pipeline.ts prepare-snapshot --plan ../results/selected-plan.json --state ../results/state.json --results ../results/builds --assets-dir ../results/snapshot
```

`results/state.json` 保持不存在。后续客户端验收须核对当前 host/材料身份，以独立运行记录为准；正式发布约束仍按 [EXTENSIONS](../EXTENSIONS.md)。

## 当前 AOT 的 Web 管理与阅读分项

固定 `3ed3945` 候选随后经官方 API Vite 配置装配至本地验收 Static Assets，正式 Flutter Web 与 Codex 内置浏览器通过默认 xkcd 的准备/安装、第二独立应用标签读回精确账户选择、英语 Source 列表/详情和两页真实阅读及服务端进度确认。完整步骤、初次身份请求缺口、修复回归和限制统一见[额外仓库验证](additional-repositories.md#codex-内置浏览器与真实-source-分项)。这不覆盖 Native、独立设备冷缓存、换仓、并发竞争、生产或完整启停/卸载矩阵，候选状态保持不变。
