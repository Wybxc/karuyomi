# 七材料生产与增量发布

2026-11-11，用户要求完成生产发布和扩展增量发布，并停止原生验证、节约本机电池。本轮 AOT 在 clab 的独立冻结目录执行，本机无 AOT 构建进程；不恢复原生登录、签名或真机验收。随后用户指定“优先构建中文和全语言包，把这些构建完就上线”。当前状态：**全语言已取得终态，中文优先构建中；首批尚未部署，增量工作流仍停用**。

## 固定输入与前置检查

- 产品源码：`main@2fa8a335bea2204ada7c0c170e8a28ff95679273`；该提交的[通用 CI](https://github.com/Wybxc/karuyomi/actions/runs/42953840361)和[Cloudflare 部署权限检查](https://github.com/Wybxc/karuyomi/actions/runs/42954478943)通过。
- 四个 submodule 按提交的 gitlink 初始化，跟踪输入干净；扩展上游为 `efa93f5a3537856fe830450bbe33f69d21d28167`。
- hostFingerprint：`0fa4bda380f85e322d362cc2595bd03f9f0a156a5b645340d37432c1830d2c67`。
- 七材料版本：`785088dcdd123ce1b640c044b83f590ff5e075833c2abf727f0762ece16d5c5b`；`materials.json` SHA-256 为 `a307dca6daeff7592f6e742e8462b088570c68be267fa284f4add27841d82b36`，与本机同提交的正式材料生成结果一致。
- 以正式 `pull-state` 读取生产父 revision `3c24b0d7c0a745a58de4bd6b5ffb7654`；state SHA-256 为 `18dea38e6c99418eefdc85b2d640feb2566d12b02dc6aeb6ad750ae08dc35a22`，未修改父状态或历史检查点。
- 完整计划发现并选择 1,448 包，零发现失败；plan SHA-256 为 `02e972028f0caa209867ec1f3b9ec74f81ace7299fa11f5ddc7c7442f8bf144c`。

clab 独立目录为 `/home/fedora/.local/karuyomi-seven-2fa8a33.NxbBAV`，冻结 clone 位于 `source/`。依赖按锁文件安装，Node 24.15.0、pnpm 12.6.0；工具链、seed 和材料经过正式准备入口校验。已有依赖缓存只用于加速，未导入旧六材料 AOT 或修改旧冻结批次。

正式 `bootstrap --jobs 1 --finalize` 已启动，并通过实际 PID、首包日志及结果确认执行。clab 为 4 CPU、3.8 GiB 内存，Maven 和 Gradle heap 均限制为 1 GiB，JVM 活跃处理器为 3。进程使用 nohup，与本机 SSH 会话分离；逐包结果保存在 `builds/`，汇总日志为 `bootstrap.log`。恢复须先确认原进程及其子进程已退出，再按 [EXTENSIONS](../EXTENSIONS.md#首次本地全量与恢复)使用原计划；不能并行启动两个发布器。

完成下述 Web 隔离验收后，原 supervisor 及全部构建子进程已通过正式 SIGTERM 退出，并逐 PID 核实。随后使用原 `plan.json`、同一冻结 checkout 和生产父状态，通过 `bootstrap --plan ... --build-checkout ... --jobs 2 --finalize` 恢复；每个 JVM 限两颗活跃处理器，heap 限额不变。恢复计划和日志单独保存为 `resume-2jobs-plan.json`、`resume-2jobs.log`，原计划和父状态摘要不变，已有正式成功和失败终态由入口复验复用。此后仅该双并发队列写同一 state。用户明确禁止使用 pku-dasys；该机器仅做过只读资源检查，没有启动任务或转移文件，后续只使用 clab 与 CI。

为节约本机电池，通用 CI 在 `main` push 的全部检查通过后保留 `web-build-<commit>` artifact，包含实际 Flutter Web 和 runtime-host 构建输出，保留七天。它不包含扩展基线，也不自动部署。组装生产候选时须核对 artifact 的运行与源码身份、材料目录和字节；如使用较后的仅文档或 CI 提交，先证明 Web、API、运行时、依赖锁等产品输入与冻结源码相同。再在远端用正式 API Vite CLI 和完整候选重新装配 Static Assets、执行部署预演及验收，不能直接发布 CI 的空索引。

## 首个实际交付

`eu.kanade.tachiyomi.extension.all.ahottie` 1.6.5 的原版 Gradle 构建与正式 AOT 成功，builder 总耗时 218.79 秒。canonical 为 4,251,027 B，SHA-256 `cac399991fc0fa79d6b51fad144181e9cda43ce042f313e8f6da44965b7a39bd`；gzip 为 873,970 B，SHA-256 `206979ac09d7216e2ed0f3b4442c63efad07525bf6bd32ba79df3ee81a734d49`。

公开 buildId 为 `ext-all.ahottie-6284b6146ba79eb4353a1db065cce03b-cac399991fc0fa79d6b51fad144181e9cda43ce042f313e8f6da44965b7a39bd`。清单包含五桥和两份 WASM；正式 runner 的 `artifactIntegrity=passed`，`workerInit/browserLoad=not_run`，状态保持 `compiled_unverified/runtimeReady=false`。首包成功不表示完整候选或 Source 在线行为通过。

## 七材料 Web 隔离验收

同一冻结输入的 `eu.kanade.tachiyomi.extension.all.xkcd` 1.6.1 已经正式 `build --key` 构建并通过完整性校验。canonical 为 4,486,032 B，SHA-256 `d4c7fd8c83a3c5cdd43cb9de2a2a1ebcbbbb793e711794b4dfc13fbb21a60536`；gzip 为 932,252 B，SHA-256 `6c2cef34d915f79b9281212a72b2d793c22c0bf9d30c1b15ff26c1fa24b3ca79`。该逐包结果与原全量计划 descriptor 一致，留在正式 `builds/` 目录供队列复验复用，未修改原计划或生产父状态。

Web 来自[通过全部检查的 CI](https://github.com/Wybxc/karuyomi/actions/runs/42956939491) artifact `web-build-dcb1eab71979036d76484b8a6317617d9f3c1060`。排除文档及该 CI artifact 步骤后，产物源码与 `2fa8a33` 的全部产品输入相同。下载 ZIP 16,183,637 B，SHA-256 `2a4851beaa92c8d6c0d3799baf241fafbfcf2668064871eaad3d2ed75992fefb`，本机及 clab 的传输边界校验均通过；`main.dart.js` SHA-256 为 `19b7b3873ef626af787323eeb784d98071da833213aee7305e825d98565b722b`。本机没有运行 Flutter 编译。

独立发布 clone 使用正式 `prepare-snapshot` 生成仅含 xkcd 的局部快照，revision `1c3c1155c23e4fffb92d344f81f88514`、`bootstrap.complete=false`，不用于生产或启用 CI。clab 的正式 API Vite 装配、验收 Worker 构建及官方 Wrangler `createTestHarness` 均通过；临时 D1 身份为 `acceptance-owner`。内置浏览器通过本机 SSH loopback 转发，实际验证：

1. 空书架下安装七材料 xkcd，账户选择由服务端确认。
2. 英文 Source 返回真实热门、详情及章节；收藏 xkcd 后，API 独立读回 `favorite=true`。
3. 实际显示 `3319: Elevators` 两页，翻至第 2 页并显示“阅读进度已保存到服务端”。
4. 关闭原标签，在新标签的服务端书架直接继续阅读，恢复到第 2 页并显示真实图片及保存确认。
5. 独立 GET 进度读回 `current.pageIndexHint=1`、`furthest.pageIndexHint=1`，与 UI 一致。书架和进度原始响应及两张截图保存在 ignored 发布目录。

本次是 **Linux clab workerd + CI Flutter Web + Codex 内置浏览器的隔离验收**，没有经过生产 Access，也没有执行原生 App。清单仍为 `compiled_unverified/runtimeReady=false`；不能据此提升整个目录的兼容性。验收标签、SSH 隧道与临时 harness 已关闭，原全量构建未受验收清理影响。

装配顺序也已实测：`build:materials` 会清理 runtime dist；之后在装配 API 前须执行完整的 `pnpm --filter @karuyomi/runtime-host build`，生成正式 host/worker 和静态材料。该远端构建不执行 Flutter 或原生 App。

## 中文与全语言优先首发

用户调整首批发布顺序后，原双并发 supervisor 通过正式 SIGTERM 退出；原 supervisor 及六个构建子进程均已核实消失，完成结果保留。按原冻结计划的 `sourcePath` 统计：`src/all/` 共 138 包，129 built、9 failed；`src/zh/` 共 59 包，当时均待构建。包名不能代替路径分类，例如 `src/zh/` 下存在 `en.cmanhua`。

同一 clab 目录中的临时 TypeScript 调度入口通过原 `ExtensionPipeline.buildOne`、`BuilderProcesses`、`withStateLock` 和 p-limit，以双并发优先完成这 59 包。调度入口已在 clab 通过项目严格 TypeScript 配置检查，留在 ignored 目录；原冻结 clone、完整计划、材料、父状态和逐包输出位置不变。当前日志为 `priority-zh.log`，按用户要求每 10 分钟检查；不再使用已退出的全量队列作为存活依据。

首批在这 197 包都有成功或明确失败终态后装配、验收并上线，不等待其它语言。此前已完成的其它语言新材料构建也可纳入；未重建的六材料包仅保留状态，暂不进入新目录。首批保持完整 catalog 和 pending 记录，不手工把其它语言记作失败或伪造完整 baseline；完成生产确认后再从同一冻结计划补齐其余包，完整基线部署确认后才恢复全语言增量。

分批装配还修正了旧完成标记沿用的问题：父快照的可用构建与当前材料身份不同，且未显式完成全量 finalize 时，候选 `bootstrap` 重置为 `{complete:false}`。clab 的 31 项 pipeline 回归通过，覆盖旧材料完成基线切换、所有旧包已替换但新目录仍有 pending、CI 拉取与计划拒绝、后续补齐 finalize，以及同运行时增量保留完成状态。该调度与状态修正不改变 AOT host 输入或材料，不要求重编已有包。

## 剩余验收

1. 完成中文优先队列，核对全部中文与全语言终态、失败原因及首批范围内现网包的保留情况，生成七材料分批候选。不能把六材料旧清单补标签混装，也不把本轮失败算作兼容。
2. 完成首批的 Web/Worker 构建、部署预演与内置浏览器验收；紧邻部署执行 `check-base`。部署后确认全部流量、D1、匿名静态交付和生产测试账号的阅读、保存、续读，再以正式 `commit-snapshot` 确认检查点。
3. 首批上线后继续在 clab 补齐其余语言，正式 finalize 并部署确认完整基线，再启用扩展工作流、运行真实有界增量。核对实际构建、完整快照部署、失败保留、已确认检查点与客户端更新；首批上线和启用开关均不等于增量发布通过。

现网继续服务[首版六材料快照](first-web-release.md)。本记录不提升原生未通过项，也不声称已发布七材料或已完成增量验收。原始计划、日志和逐包结果留在上述 ignored 目录；本机交接入口为 `.local/production-seven-2fa8a33.7Js42X/REPRODUCE.md`。
