# 扩展 AOT 构建与静态分发

Static Assets 是 Web 与 Native 的扩展权威来源。每个包只部署最新可用构建，客户端或 Service Worker 检查索引、更新并清理旧缓存。扩展不再发布到 GitHub Release，不经 R2 或入口 Worker 转发正文；共享桥与 WASM 使用 Web 静态资源 / Native 内置材料。动态 Source HTTP 请求仍由受 Access 保护的 `/api/bridge/http` 处理。

## 静态快照与传输合同

通过 `--assets-dir` 选择快照根目录，客户端使用以下公开路径：

| 路径                                         | 内容与缓存                                                     |
| -------------------------------------------- | -------------------------------------------------------------- |
| `/extensions/index.json`                     | `schemaVersion: 1`、当前 `builds`；no-cache                    |
| `/extensions/builds/<buildId>/manifest.json` | 与索引身份严格一致的 `BuildManifest`；no-cache                 |
| `/extensions/artifacts/<canonicalSHA>.gz`    | 唯一 AOT 交付文件；`application/gzip`、一年 immutable          |
| `/extensions/build-state.json`               | 增量调度状态与已完成 baseline 标记；no-cache，不作为客户端目录 |

索引每个包只含一个 build，字段为 `buildId/packageName/repoId/version/sourceIds/sources/manifestPath`。`sources` 为完整 `CatalogSource{id,name,lang}` 列表，与 manifest 的同名字段一致，且每个 ID 与 `sourceIds` 一一匹配；每包 1–500 个唯一 signed int64 十进制字符串 ID，名称去空白后非空且最多 500 个 UTF-16 code units，语言最多 64 个且允许空值。`manifestPath` 必须绑定 buildId；manifest 上限 64KiB，完整索引上限 2MiB、5,000 包。build-state 与客户端索引分开维护，以 `indexSha256` 绑定索引的精确字节，状态上限 16MiB。

Source 资料由官方 Gradle `keiyoushi-source-info.json` 的 `metadata.sources` 产生，builder 校验后写 manifest，快照再原样投影到 index。目录只列当前最新可用构建，不包含尚未构建或无可用交付的上游包；名称/语言用于加载前的展示与本地语言筛选，不声明运行时能力或网络可用。不为筛选下载或执行其它扩展，账户安装/卸载也不是目录成员关系。设计见[语言筛选](design/source-language-filter.md)。

装配和客户端打开前核对索引与 manifest 的构建身份及 Source 资料；不一致明确要求刷新，不能静默改用另一资料源。原型不支持缺少 `sources` 的旧格式 fallback；协议/host 输入变化后按固定新输入重建候选，不能将旧清单补标签后当成新 AOT。

Bundle 清单记录 canonical `sha256/size/contentType`，以及 `encoding: gzip`、`encodedSha256/encodedSize`。canonical 上限 64 MiB，gzip 文件上限 25 MiB；路径绑定 canonical SHA。gzip 使用 level 9、mtime 0、无文件名的固定编码。它是应用显式解压的文件，HTTP 响应不能附加 `Content-Encoding: gzip`。客户端先验证收到的 gzip 长度/摘要，再有界解压并验证 canonical 长度/摘要，最后执行 JavaScript；不读取 raw 资产或私有 API 回退。

所有客户端获取索引、清单和 bundle 时均使用 `credentials: omit`。索引/清单使用 no-cache，内容寻址 bundle 使用 immutable 缓存。共享材料只能引用 `/runtime/materials/<sha256>`，来源与 Native 内置规则见[共享运行时材料](RUNTIME-MATERIALS.md)。

`apps/api/vite.assets.ts` 的 Vite 资源插件仅复制当前索引可达的清单与 gzip，拒绝索引/清单身份不一致、不可用材料、超限或编码摘要错误。部署快照不包含旧版本目录、未引用 bundle、构建 provenance 或日志。普通无快照的本地客户端构建会生成空索引；正式部署必须显式设置 `EXTENSION_ASSETS_DIR`，缺失目录会报错。

## 发现、输入身份与失败保留

上游来源是固定提交的 `vendor/extensions-source`。调度器读取 `src/<lang>/<key>/build.gradle.kts`，按官方 `ExtensionPlugin.kt` 计算 Android versionCode，不依赖已退化为提示页的旧 `index.min.json`。无法静态确认的 Kotlin 表达式记录为 `discovery_failed`。

`inputFingerprint` 覆盖包名、版本、源码依赖闭包及 host 输入，用于增量计划、内部工作目录、checkpoint 和 provenance。共享库、桥、工具链变化即使未修改扩展版本，也会产生新输入；无关上游提交不使所有包重建。`plan` 只选择缺失输入、明确不可用的成功记录，以及本地显式要求重试的失败输入。

正式清单和静态目录的公开 `buildId` 在编码后生成：内部工作名 `ext-<包短名>-<输入指纹前 32 位>` 加上 `-<canonicalSHA>`。同一输入即使重编出不同字节，也使用不同清单路径、可被客户端检测为更新。快照状态记录已验证的 canonical SHA 并据此定位保留产物；回拉须与该身份一致。没有绑定摘要的记录不参与产物复用，应重新构建；已确认远端 revision 仍作为部署基线。派生公开 ID 直接复用编码阶段取得的摘要，不重复读取正文。

Source host 的第三方源码输入包含已初始化、HEAD 与已提交 gitlink 一致且 tracked clean 的 TeaVM、Suwayomi 和 libwebp 子模块；扩展上游归 Source 闭包身份。libwebp 只用于共享图形桥的编码，准备工具和编译配方都进入 host 输入。

构建失败保留同运行时的上次成功构建，同一失败输入不会自动反复重试。发现失败时，仍存在的 `sourcePath` 也保留上次成功；真正从上游删除的模块才退役。成功更新替换旧 build，快照仅保留当前可用版本。协议、ABI 或材料不匹配的旧成功只保留状态，标为 unavailable，不进入索引，也不复制旧 bundle；原型不维护兼容集合。

每包本地交付包含 `manifest.json`、`artifacts/<canonicalSHA>.gz`、`provenance.json`、`build-result.json`；调度器另保存 descriptor、`validation.json`、`pipeline-result.json` 和日志。`built` 只表示本地编译/完整性检查完成，`published` 是候选状态中的成功记录；是否已经部署，必须以确认后的快照 revision 为准。

## 首次本地全量与恢复

2026-11-15 用户补充构建位置：AOT 可 offload 到 `ssh macbook-pro-4`。该机为 M4 MacBook Pro，用户说明其性能强于 clab；为节约当前本机电量，后续重编可优先使用该机，仍不使用 pku-dasys。本节的“本地”指非 CI 的开发/构建机，包含已授权的 SSH 主机；不是要求在当前笔记本执行。开始实际构建前在目标机核对固定工具链、仓库提交和 checkpoint，并按实测资源确定并发；本次仅记录授权及设备信息，尚未运行该机上的 AOT 或性能比较。

先提交稳定的当前 host，使用固定提交、干净的独立 clone。下列命令在该 clone 内执行；长批次必须同时固定 supervisor、verifier、builder 和 submodules，不能只固定 builder 却让其它阶段读取持续变化的开发目录。执行前将 `AOT_DIR` 设为本次发布专用的持久目录绝对路径，并在同一 shell 运行以下命令。首次构建、恢复与部署使用同一个目录，保存状态、冻结计划、逐包结果和候选快照。

```sh
: "${AOT_DIR:?请设置本次发布的持久目录绝对路径}"
mkdir -p "$AOT_DIR"
git submodule update --init vendor/extensions-source vendor/suwayomi-server vendor/teavm vendor/libwebp
pnpm install --frozen-lockfile
node scripts/prepare-runtime.ts --android
node tools/extensions/pipeline.ts bootstrap \
  --state "$AOT_DIR/state.json" \
  --output "$AOT_DIR/plan.json" \
  --assets-dir "$AOT_DIR/assets" \
  --jobs 1 --finalize
```

`bootstrap` 默认处理所有未尝试输入，本地上限 10,000，并发默认 1、最高 4。它先保存每包 built/failed 结果，完成本批后生成完整候选快照，尚不写入已部署 checkpoint。中断后重跑会重新验证并复用已有成功交付；`--retry-failed` 才明确重试相同失败输入。

在 libwebp 接入前冻结的批次仍使用接入前的 supervisor 与补编 checkout 完成原候选。当前工具会按新增的固定输入重新计算指纹，不能用于重扫旧冻结树。包含编码器的新材料须另建候选，不能用旧清单混装。

需要显式恢复完整冻结计划时，在同一固定 clone 执行：

```sh
node tools/extensions/pipeline.ts bootstrap \
  --plan "$AOT_DIR/plan.json" \
  --build-checkout "$PWD" \
  --state "$AOT_DIR/state.json" \
  --output "$AOT_DIR/resume-plan.json" \
  --assets-dir "$AOT_DIR/assets" \
  --jobs 1 --finalize
```

runner 检查冻结 checkout 的提交、干净 host 输入、指纹、submodule 和上游提交，先在该 checkout 运行声明式 Vite CLI `pnpm --filter @karuyomi/runtime-host build:materials`，再调用构建器并直接读取已生成 catalog。材料读取不隐式编译。`--output` 保持在同一目录，可复用相邻 `builds/<inputFingerprint>/`。磁盘结果必须重新做当前完整性校验，不能凭 JSON 恢复信任。

`--limit N` 可分批；分批候选部署并确认 checkpoint 后，下一批才会跳过这些输入。全部发现输入都有成功或明确失败记录时才加 `--finalize`。baseline 完成只表示覆盖结束，不表示全部 Source 可运行。`CI=true` 或 `GITHUB_ACTIONS=true` 禁止首次全量、冻结计划恢复和 finalize。

保存有效本地交付结果后，调度器仅清理精确内部工作名的 `extension-work`、`extension-cache` 和 `gradle-launcher`，不跟随 symlink。交付目录、checkpoint、日志和失败诊断保留，共享 Maven/Gradle 缓存保留。SIGINT/SIGTERM 会先终止并等待本次 builder 进程组，再释放 checkpoint 锁；三秒宽限后终止剩余组成员，不搜索或终止其它任务。

## 候选、部署与 checkpoint

`prepare-snapshot` 将成功结果和已部署的上次成功版本合成完整候选，先在临时目录完成，再替换本地快照。缺少 matrix 结果、下载/完整性错误或取消均不会替换已有快照。它不提交部署状态。

```sh
node tools/extensions/pipeline.ts prepare-snapshot \
  --plan "$AOT_DIR/plan.json" \
  --state "$AOT_DIR/state.json" \
  --results "$AOT_DIR/builds" \
  --assets-dir "$AOT_DIR/assets"
EXTENSION_ASSETS_DIR="$AOT_DIR/assets" pnpm build
node tools/extensions/pipeline.ts check-base \
  --assets-dir "$AOT_DIR/assets"
node scripts/release-web.ts check-schema
pnpm --filter @karuyomi/api exec wrangler deploy --config dist/karuyomi/wrangler.json
node tools/extensions/pipeline.ts commit-snapshot \
  --state "$AOT_DIR/state.json" \
  --assets-dir "$AOT_DIR/assets"
```

`bootstrap` 已生成候选时可跳过上面的 `prepare-snapshot`。`check-base` 应紧邻部署，确认远端 revision 仍为计划基线；首次替换已知旧 SPA 时可在本地显式增加 `--initialize`，它不接受任意错误响应，也不能在 CI 使用。网络命令默认 origin 为 `https://karuyomi.wybxc.cc`，可用 `--origin` 明确指定。

数据库结构或其他不兼容变更使用[开发机停机迁移流程](PRODUCTION.md)。快照确认仍在正式服务恢复并完成读回后执行。

用户指定优先包时，可以先发布本地分批候选。保留原完整冻结计划及其 `entries`、目录指纹、输入身份和父 revision；按原 descriptor 调用 `build --key`，只调整构建顺序。组装时派生一份 `selected` 仅含已有正式终态的计划，未尝试输入仍保留在完整目录中并计入 pending。使用普通 `prepare-snapshot`，不使用 `--finalize`；原计划和生产父状态不手工修改。

运行时身份变化的分批候选会清除旧材料的 baseline 完成标记。只有匹配当前材料的构建进入索引，其余旧构建仅保留状态；首批可按正式部署与 checkpoint 流程上线，但不能据此启用增量 CI。后续在本地补齐完整目录并正式 finalize、部署和确认后，再运行有界增量。运行时相同的普通有界更新保留既有 baseline 完成状态。

### 首次全量候选的定向补编

冻结全量期间如有少量包需要用新版 AOT 重编，先确认新旧 checkout 的上游源码和共享运行材料相同。新版固定 checkout 以同一份已核对的生产父状态运行 `plan --limit 10000`，按新计划中的精确 `inputFingerprint` 对指定包运行 `build --key`，每个包使用独立输出目录。两份 checkout 先各自执行 `pnpm --filter @karuyomi/runtime-host build:materials`。独立试编可以在冻结队列运行期间完成。原计划和逐包回执持续保留，完整候选在原队列取得全部终态后装配。

本地候选可以同时纳入多个独立补编批次。`--supplements` 指向 JSON 数组，每项记录原计划、实际结果目录、固定 checkout 和要合入的完整包名。相对路径以该 JSON 文件所在目录为基准。每个包只能由一个补编批次提供。

```json
[
  {
    "plan": "supplement-a/plan.json",
    "results": "supplement-a/builds",
    "checkout": "supplement-a/checkout",
    "packages": ["eu.kanade.tachiyomi.extension.all.komga"]
  },
  {
    "plan": "supplement-b/plan.json",
    "results": "supplement-b/builds",
    "checkout": "supplement-b/checkout",
    "packages": ["eu.kanade.tachiyomi.extension.en.theblank"]
  }
]
```

```sh
node tools/extensions/pipeline.ts prepare-baseline \
  --state "$parent_state" --plan "$frozen_plan" \
  --results "$frozen_results" --build-checkout "$frozen_checkout" \
  --supplements "$supplements_file" --assets-dir "$candidate"
```

入口核对线上 state/index 仍为同一真实父快照，逐批检查完整源码目录、共享运行材料、固定 checkout 和实际产物。组装只替换指定包，保留每个产物的构建输入身份及其余冻结终态。补编替换失败的冻结输入时，构建状态保留该输入的精确失败回执，使原 Host 的增量计划跳过已尝试输入。当前失败统计按最终选定输入计算。缺检查点、材料不符或传输损坏会中止，并保留已有候选。仍在上游目录且现网可用的包必须留在候选索引。组装只生成本地候选，仍须完成正式构建、验收和 `check-base` 才可部署。增量 CI 继续以真实已部署且完成的 baseline 为前提。

### 部署确认

`commit-snapshot` 只有在远端 state 与候选完全一致、远端 index 与本地字节一致后才原子保存本地 checkpoint。`--state` 应指向持有已确认父状态的文件；若使用新路径，在切流前保存当时的生产 state 并核对 index 摘要。部署失败或未确认时，旧 checkpoint 保持不变。所有 publisher 必须串行；本地文件锁和 CI concurrency group 不能替代跨工作区的发布协调。

摘要只在传输边界检查：下载验证编码/canonical 各一次，后续本地阶段复用验证结果；assembler 在上传边界校验实际 gzip 字节，不再次解压计算 canonical 摘要。schema、身份、大小、路径和材料检查仍保留。

### 旧网络登记部署切换

迁移 `0009` 和 `0010` 的旧网络登记切换保留在[历史演练记录](verification/d1-relay-cutover.md)。当前生产使用统一的[停机迁移流程](PRODUCTION.md)。

## Source 网络和设置

静态分发无需 Access。Source HTTP 使用同一应用的 Access 会话和 Worker 公网 fetch；安装、更新或切换漫画站不需要登记包、域名或镜像。额外仓库须与应用 ABI/materials 一致，并为浏览器及 Native WebView 下载提供 CORS；目录、清单与产物验证仍在正式加载边界执行。

具体扩展的适配由 AOT 提供。AOT 可将已审核的非敏感设置键写入当前构建的 `preferenceSyncRules`。正式装配从当前官方清单投影精简的 `/extensions/preference-rules.json`，供 Worker 读取。缺规则的键只在当前客户端会话生效。额外仓库不获得官方清单的设置规则。

当前 Source 设置表依赖历史 `0009` 的来源主键。迁移 `0010` 删除退役的网络登记表。

## 增量 CI 与验证层级

`.github/workflows/extensions.yml` 每六小时或手动运行。`pull-state --state PATH` 只接受远端已完成且 index/state 一致的 baseline，缺失、HTML、部分 bootstrap 均拒绝，不能退化为首次全量。CI 跟随上游 main，默认每批 12 包、手动最高 24，并发最多 2；相同失败输入不自动重试。

增量计划读取正式构建生成的共享材料清单，并与已部署索引中的可用扩展逐一比较运行时身份。只要其中一个扩展的协议、ABI、运行基线、HTTP bridge 版本或实际共享材料不匹配，或者缺少已验证的运行时身份，CI 就在输出计划前停止；组装候选前再次检查同一 parent state。先在本地完成并部署当前运行时的全量候选，再恢复增量发布。输入指纹变化但运行时身份相同，继续正常分批构建，未选中的可用构建继续保留。

plan/build/deploy 三个 jobs 只需 GitHub `contents: read`，均安装固定 Node 和锁定 npm 依赖。AOT 在隔离 matrix 中执行；deploy 汇总结果、生成完整快照、构建客户端、检查基线、部署并确认 checkpoint。即使本轮没有待编译包，catalog 变化（例如删除模块）仍会生成并部署新快照。Cloudflare 凭据仅提供给可信部署步骤，所有增量发布使用同一 concurrency group。

为本次增量批次设置独立的 `AOT_DIR`。增量调度使用以下命令，再以本批结果执行上面的 `prepare-snapshot` 和部署流程；`INPUT_FINGERPRINT` 来自 plan 的 selected 条目：

```sh
: "${AOT_DIR:?请设置本次增量批次的持久目录绝对路径}"
node tools/extensions/pipeline.ts pull-state --state "$AOT_DIR/state.json"
pnpm --filter @karuyomi/runtime-host build:materials
node tools/extensions/pipeline.ts plan --ci \
  --state "$AOT_DIR/state.json" --output "$AOT_DIR/plan.json" --limit 12
node tools/extensions/pipeline.ts build \
  --plan "$AOT_DIR/plan.json" --key INPUT_FINGERPRINT \
  --output "$AOT_DIR/builds/INPUT_FINGERPRINT"
```

编译成功可以交付为 `compiled_unverified`，保持 `runtimeReady=false`。只有匹配 buildId/manifest SHA 的真实 Worker/browser gate 均通过才为 `browser_verified`；初始化成功不证明在线 Source、图片或真机支持。当前完整性验证使用 gzip 目录，先准备匹配的共享材料：

```sh
pnpm --filter @karuyomi/runtime-host build:materials
node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json
pnpm test:extensions
pnpm test:extension-build
pnpm test:extension-integrity
```

当前 verifier 只做完整性验证：通过时仍退出 2，报告 `valid=false`、`runtimeReady=false`、`browser_not_run`；失败退出 1。旧动态浏览器 verifier 及 `--serve`/`--timeout-ms` 已退役，历史 `browser_verified` 仅适用于当时固定的 build/manifest。官方 Browser fixture 入口为 `BROWSER=none pnpm test:browser`，它不加载指定扩展，不能将该目录标为 `browser_verified`；`onlineCompatibility` 保持 `not_tested`。真实扩展初始化、在线 Source 和 Native 完整门须另行建立并记录，不能以单元测试代替。静态装配边界由 `pnpm test` 的 API Vite 插件单元测试和官方 harness 验证。当前测试结构见 [Vite 计划](plan/vite-build-and-testing.md)。

项目 CI 使用 `.github/workflows/project-ci.yml`，仅分支 push/PR 触发。历史 Release 传输、旧宿主 bulk 与旧 R2 探针只保留测量背景，不是当前恢复入口；有用体积数据见 [AOT 包体分析](AOT-SIZE.md)，实际门槛见 [VERIFICATION](VERIFICATION.md)。

## CI 凭据检查

仓库 Actions secrets 使用 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`。Workers Editor 用于更新现有 Worker，D1 查询权限用于只读迁移账本，`wybxc.cc` 的 Workers Routes Edit 用于域名连接。正常部署不要求创建或删除 Worker 的 Admin 权限。生产迁移使用开发机的 Wrangler 会话。

手动工作流 `cloudflare-permissions.yml` 在预先建立、无 `workers.dev`/preview URL 的 `karuyomi-ci-permission-check` 上实际上传 Worker 和静态文件，再恢复空白配置；另创建并删除独立 D1 和唯一测试路由。该 Worker 缺失时应由本地管理员预先创建，检查不会自行申请扩权或新建 Worker。它不修改生产 Worker 或 D1。实际结果见 [验证记录](VERIFICATION.md#ci-凭据权限)。
