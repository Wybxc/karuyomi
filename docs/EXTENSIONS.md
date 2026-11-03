# 扩展 AOT 构建与静态分发

Static Assets 是 Web 与 Native 的扩展权威来源。每个包只部署最新可用构建，客户端或 Service Worker 检查索引、更新并清理旧缓存。扩展不再发布到 GitHub Release，不经 R2 或入口 Worker 转发正文；共享桥与 WASM 使用 Web 静态资源 / Native 内置材料。动态 Source HTTP 请求仍由受 Access 保护的 `/api/bridge/http` 处理。

## 静态快照与传输合同

快照根目录默认为 `.local/extensions-assets`，公开目录结构如下：

| 路径                                         | 内容与缓存                                                     |
| -------------------------------------------- | -------------------------------------------------------------- |
| `/extensions/index.json`                     | `schemaVersion: 1`、当前 `builds`；no-cache                    |
| `/extensions/builds/<buildId>/manifest.json` | 与索引身份严格一致的 `BuildManifest`；no-cache                 |
| `/extensions/artifacts/<canonicalSHA>.gz`    | 唯一 AOT 交付文件；`application/gzip`、一年 immutable          |
| `/extensions/build-state.json`               | 增量调度状态与已完成 baseline 标记；no-cache，不作为客户端目录 |

索引每个包只含一个 build，字段为 `buildId/packageName/repoId/version/sourceIds/manifestPath`。`manifestPath` 必须绑定该 buildId；索引上限 2 MiB、5,000 包。build-state 与客户端索引分开维护，以 `indexSha256` 绑定索引的精确字节，状态上限 16 MiB。

Bundle 清单记录 canonical `sha256/size/contentType`，以及 `encoding: gzip`、`encodedSha256/encodedSize`。canonical 上限 64 MiB，gzip 文件上限 25 MiB；路径绑定 canonical SHA。gzip 使用 level 9、mtime 0、无文件名的固定编码。它是应用显式解压的文件，HTTP 响应不能附加 `Content-Encoding: gzip`。客户端先验证收到的 gzip 长度/摘要，再有界解压并验证 canonical 长度/摘要，最后执行 JavaScript；不读取 raw 资产或私有 API 回退。

所有客户端获取索引、清单和 bundle 时均使用 `credentials: omit`。索引/清单使用 no-cache，内容寻址 bundle 使用 immutable 缓存。共享材料只能引用 `/runtime/materials/<sha256>`，来源与 Native 内置规则见[共享运行时材料](RUNTIME-MATERIALS.md)。

`scripts/assemble-assets.ts` 仅复制当前索引可达的清单与 gzip，拒绝索引/清单身份不一致、不可用材料、超限或编码摘要错误。部署快照不包含旧版本目录、未引用 bundle、构建 provenance 或日志。普通无快照的本地客户端构建会生成空索引；正式部署必须显式设置 `EXTENSION_ASSETS_DIR`，缺失目录会报错。

## 发现、输入身份与失败保留

上游来源是固定提交的 `vendor/extensions-source`。调度器读取 `src/<lang>/<key>/build.gradle.kts`，按官方 `ExtensionPlugin.kt` 计算 Android versionCode，不依赖已退化为提示页的旧 `index.min.json`。无法静态确认的 Kotlin 表达式记录为 `discovery_failed`。

`inputFingerprint` 覆盖包名、版本、源码依赖闭包及 host 输入，用于 buildId、增量状态和 provenance。共享库、桥、工具链变化即使未修改扩展版本，也会产生新输入；无关上游提交不使所有包重建。`plan` 只选择缺失输入、明确不可用的成功记录，以及本地显式要求重试的失败输入。

构建失败保留同运行时的上次成功构建，同一失败输入不会自动反复重试。发现失败时，仍存在的 `sourcePath` 也保留上次成功；真正从上游删除的模块才退役。成功更新替换旧 build，快照仅保留当前可用版本。协议、ABI 或材料不匹配的旧成功只保留状态，标为 unavailable，不进入索引，也不复制旧 bundle；原型不维护兼容集合。

每包本地交付包含 `manifest.json`、`artifacts/<canonicalSHA>.gz`、`provenance.json`、`build-result.json`；调度器另保存 descriptor、`validation.json`、`pipeline-result.json` 和日志。`built` 只表示本地编译/完整性检查完成，`published` 是候选状态中的成功记录；是否已经部署，必须以确认后的快照 revision 为准。

## 首次本地全量与恢复

先提交稳定的当前 host，使用固定提交、干净的独立 clone。下列命令在该 clone 内执行；长批次必须同时固定 supervisor、verifier、builder 和 submodules，不能只固定 builder 却让其它阶段读取持续变化的开发目录。state、plan、builds 和 snapshot 可以使用绝对路径放在统一的忽略目录。

```sh
git submodule update --init --recursive
pnpm install --frozen-lockfile
node scripts/prepare-runtime.ts --android
node tools/extensions/pipeline.ts bootstrap \
  --state .local/extensions-current/state.json \
  --output .local/extensions-current/plan.json \
  --assets-dir .local/extensions-assets \
  --jobs 1 --finalize
```

`bootstrap` 默认处理所有未尝试输入，本地上限 10,000，并发默认 1、最高 4。它先保存每包 built/failed 结果，完成本批后生成完整候选快照，尚不写入已部署 checkpoint。中断后重跑会重新验证并复用已有成功交付；`--retry-failed` 才明确重试相同失败输入。

需要显式恢复完整冻结计划时，在同一固定 clone 执行：

```sh
node tools/extensions/pipeline.ts bootstrap \
  --plan .local/extensions-current/plan.json \
  --build-checkout "$PWD" \
  --state .local/extensions-current/state.json \
  --output .local/extensions-current/resume-plan.json \
  --assets-dir .local/extensions-assets \
  --jobs 1 --finalize
```

runner 检查冻结 checkout 的提交、干净 host 输入、指纹、submodule 和上游提交，调用该 checkout 的构建器和材料入口。`--output` 保持在同一目录，可复用相邻 `builds/<inputFingerprint>/`。磁盘结果必须重新做当前完整性校验，不能凭 JSON 恢复信任。

`--limit N` 可分批；分批候选部署并确认 checkpoint 后，下一批才会跳过这些输入。全部发现输入都有成功或明确失败记录时才加 `--finalize`。baseline 完成只表示覆盖结束，不表示全部 Source 可运行。`CI=true` 或 `GITHUB_ACTIONS=true` 禁止首次全量、冻结计划恢复和 finalize。

保存有效本地交付结果后，调度器仅清理精确 buildId 的 `extension-work`、`extension-cache` 和 `gradle-launcher`，不跟随 symlink。交付目录、checkpoint、日志和失败诊断保留，共享 Maven/Gradle 缓存保留。SIGINT/SIGTERM 会先终止并等待本次 builder 进程组，再释放 checkpoint 锁；三秒宽限后终止剩余组成员，不搜索或终止其它任务。

## 候选、部署与 checkpoint

`prepare-snapshot` 将成功结果和已部署的上次成功版本合成完整候选，先在临时目录完成，再替换本地快照。缺少 matrix 结果、下载/完整性错误或取消均不会替换已有快照。它不提交部署状态。

```sh
node tools/extensions/pipeline.ts prepare-snapshot \
  --plan .local/extensions-current/plan.json \
  --state .local/extensions-current/state.json \
  --results .local/extensions-current/builds \
  --assets-dir .local/extensions-assets
EXTENSION_ASSETS_DIR="$PWD/.local/extensions-assets" pnpm build
pnpm --filter @karuyomi/api exec wrangler d1 migrations apply DB --remote
node tools/extensions/pipeline.ts check-base \
  --assets-dir .local/extensions-assets
pnpm --filter @karuyomi/api exec wrangler deploy
node tools/extensions/network-policies.ts --remote
node tools/extensions/pipeline.ts commit-snapshot \
  --state .local/extensions-current/state.json \
  --assets-dir .local/extensions-assets
```

`bootstrap` 已生成候选时可跳过上面的 `prepare-snapshot`。`check-base` 应紧邻部署，确认远端 revision 仍为计划基线；首次替换已知旧 SPA 时可在本地显式增加 `--initialize`，它不接受任意错误响应，也不能在 CI 使用。网络命令默认 origin 为 `https://karuyomi.wybxc.cc`，可用 `--origin` 明确指定。

`commit-snapshot` 只有在远端 state 与候选完全一致、远端 index 与本地字节一致后才原子保存本地 checkpoint。部署失败或未确认时，旧 checkpoint 保持不变。所有 publisher 必须串行；本地文件锁和 CI concurrency group 不能替代跨工作区的发布协调。

摘要只在传输边界检查：下载验证编码/canonical 各一次，后续本地阶段复用验证结果；assembler 在上传边界校验实际 gzip 字节，不再次解压计算 canonical 摘要。schema、身份、大小、路径和材料检查仍保留。

## 网络策略

静态分发无需 Access。D1 仅保存当前 build 的 Source 网络策略，不保存扩展清单或正文；`/api` 继续校验 Access、Origin 和显式域名白名单。

部署后的 `network-policies.ts --remote` 将已批准 package 的域名策略切换到当前 build，退役已不在索引中的策略；它不自动批准新包、不从请求学习白名单，也不下载 gzip。首次批准一个当前包时，明确指定允许的 hostname：

```sh
node tools/extensions/registration.ts PATH_TO_OUTPUT/manifest.json \
  --allow-host www.mangadraft.com --remote
```

远程注册先核对部署 origin 的当前 index/manifest；本地测试必须使用 `--local --static-root SNAPSHOT`。注册只解析元数据，不读取本地 gzip、不下载正文，也不重复计算扩展摘要；上传/下载边界负责完整性校验。构建任务不持有 Cloudflare 部署凭据；上游 Gradle/AOT 子进程移除 GitHub 和 Cloudflare 凭据。runtime seed 是独立构建依赖，不属于扩展发布。

## 增量 CI 与验证层级

`.github/workflows/extensions.yml` 每六小时或手动运行。`pull-state --state PATH` 只接受远端已完成且 index/state 一致的 baseline，缺失、HTML、部分 bootstrap 均拒绝，不能退化为首次全量。CI 跟随上游 main，默认每批 12 包、手动最高 24，并发最多 2；相同失败输入不自动重试。

plan/build/deploy 三个 jobs 只需 GitHub `contents: read`，均安装固定 Node 和锁定 npm 依赖。AOT 在隔离 matrix 中执行；deploy 汇总结果、生成完整快照、构建客户端、检查基线、部署、同步网络策略并确认 checkpoint。即使本轮没有待编译包，catalog 变化（例如删除模块）仍会生成并部署新快照。Cloudflare 凭据仅提供给可信部署步骤，所有增量发布使用同一 concurrency group。

增量调度使用以下命令，再以本批结果执行上面的 `prepare-snapshot` 和部署流程；`INPUT_FINGERPRINT` 来自 plan 的 selected 条目：

```sh
node tools/extensions/pipeline.ts pull-state --state .local/extensions/state.json
node tools/extensions/pipeline.ts plan --ci \
  --state .local/extensions/state.json --output .local/extensions/plan.json --limit 12
node tools/extensions/pipeline.ts build \
  --plan .local/extensions/plan.json --key INPUT_FINGERPRINT \
  --output output/INPUT_FINGERPRINT
```

编译成功可以交付为 `compiled_unverified`，保持 `runtimeReady=false`。只有匹配 buildId/manifest SHA 的真实 Worker/browser gate 均通过才为 `browser_verified`；初始化成功不证明在线 Source、图片或真机支持。人工验证使用当前 gzip 目录：

```sh
node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json
node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json \
  --serve --timeout-ms 120000
pnpm test:extensions
pnpm test:extension-build
pnpm test:extension-integrity
pnpm test:extension-assets
```

默认完整性通过但未运行浏览器时退出 2，报告 `valid=false`、`runtimeReady=false`、`browser_not_run`；失败退出 1，实际浏览器通过才退出 0。`--serve` 只监听 loopback，由人或 Codex 内置浏览器运行真实产品 Worker/IndexedDB；`onlineCompatibility` 仍为 `not_tested`。单元测试不使用真实 Source、生产 Access 或远程部署凭据。

项目 CI 使用 `.github/workflows/project-ci.yml`，仅分支 push/PR 触发。历史 Release 传输、旧宿主 bulk 与旧 R2 探针只保留测量背景，不是当前恢复入口；有用体积数据见 [AOT 包体分析](AOT-SIZE.md)，实际门槛见 [VERIFICATION](VERIFICATION.md)。

## CI 凭据检查

仓库 Actions secrets 使用 `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`。Workers Editor 用于更新现有 Worker，D1 Edit 用于迁移和网络策略，`wybxc.cc` 的 Workers Routes Edit 用于域名连接。正常部署不要求创建/删除 Worker 的 Admin 权限。

手动工作流 `cloudflare-permissions.yml` 在预先建立、无 `workers.dev`/preview URL 的 `karuyomi-ci-permission-check` 上实际上传 Worker 和静态文件，再恢复空白配置；另创建并删除独立 D1 和唯一测试路由。该 Worker 缺失时应由本地管理员预先创建，检查不会自行申请扩权或新建 Worker。它不修改生产 Worker 或 D1。实际结果见 [验证记录](VERIFICATION.md#ci-凭据权限)。
