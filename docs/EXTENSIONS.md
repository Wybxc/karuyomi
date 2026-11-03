# 扩展 AOT 构建与发布

当前上游来源是固定提交的 `vendor/extensions-source` submodule。调度器读取源码树的 `src/<lang>/<key>/build.gradle.kts`，不使用已退化成“Outdated App”提示的旧 `index.min.json`，也不把仓库提交时间当成扩展版本。当前 Gradle DSL 的 `pkgName` 覆盖默认 `<lang>.<key>`；主题的 `baseVersionCode` 与扩展 `versionCode` 相加得到有效版本，`versionName=<libVersion>.<有效版本>`，Android/index versionCode 按上游 `ExtensionPlugin.kt` 的 libVersion 编码规则计算。无法静态确认的 Kotlin 表达式单独记为 `discovery_failed`。

源码指纹覆盖自身目录、主题、递归 `project(":lib:...")` 依赖，以及上游 `common/core/compiler/gradle` 和根构建配置。host 指纹覆盖内化的 Java/bridge、正式构建工具、协议、工具链与 seed 锁，以及真正上游 submodules 的 gitlink/checkout 提交。同版本的共享库、host、工具链变化会生成新输入身份；无关上游提交不会使所有包重建。源码必须保持已提交状态，生成的 build/target/cache 不进入身份。

`scripts/build-extension.py --descriptor PATH --output DIR` 是逐包构建接口。它保留业务源码，通过官方 Gradle/KSP 生成 JAR 和 Source 元数据，再执行 AOT。输出包括 `manifest.json`、`artifacts/<sha256>`、`provenance.json` 与 `build-result.json`；失败必须非零退出并记明 upstream/host/aot 阶段。依赖只通过 `scripts/prepare-runtime.py --android` 的固定工具链、公开下载与本项目私有 runtime seed 准备，CI 不依赖研究 ZIP。

这里的 runtime seed 是 JAR 等构建依赖，不是下发给 Web/Native 阅读器的客户端资源。扩展 AOT 资产继续通过本仓库私有 Release 分发；客户端共享 JS/WASM 的静态或打包交付由产品资源层负责。

## 首次全量只在本地执行

先提交稳定的 host/工具链变更并准备 seed。私有 Release REST 访问使用环境中的 `GH_TOKEN` 或 `GITHUB_TOKEN`，需要本仓库 contents 权限；不要把令牌写入配置或提交记录。

```sh
python3 scripts/prepare-runtime.py --android
python3 tools/extensions/pipeline.py plan \
  --state .local/extensions/state.json --output .local/extensions/plan.json
python3 tools/extensions/pipeline.py bootstrap \
  --state .local/extensions/state.json --output .local/extensions/plan.json \
  --repository Wybxc/karuyomi --jobs 1
```

`bootstrap` 默认覆盖所有未尝试输入，限并发 1，最高可设 4；可用 `--limit N` 分批。每个包发布或失败后立刻原子保存 checkpoint，重复运行跳过已发布和未变更的确定失败。`--retry-failed` 明确重试原失败；GitHub 传输失败最多自动重试三次。构建日志留在本地 `builds/<inputFingerprint>/`，索引只保留有用的阶段/错误信息。中断后保留 state 和输出，再执行同一命令即可继续；已上传的 matching draft 继续补齐，已发布身份不会覆盖。

全部发现包都有 `published` 或明确 `failed` 终态后，再执行一次带 `--finalize` 的 bootstrap：

```sh
python3 tools/extensions/pipeline.py bootstrap \
  --state .local/extensions/state.json --output .local/extensions/plan.json \
  --repository Wybxc/karuyomi --jobs 1 --finalize
```

baseline 完成代表首次覆盖已结束，记录 published/failed/discoveryFailed 数量；不代表所有扩展可运行。未尝试、仅本地 built 或尚未上传的包会阻止正常完成标记。`CI=true` 或 `GITHUB_ACTIONS=true` 环境完全禁止首次 bootstrap/finalize。

## 不可变 Release 与索引

每包 tag 为 `ext-<packageSuffix>-v<AndroidVersionCode>-<inputFingerprint前32位>`。每个内容 SHA256 是独立资产，另含 `manifest.json`、调度 provenance、原始 build provenance 与 validation。`release-manifest.json` 汇总所有资产的完整 SHA256/长度并最后上传。先建 draft，确认资产与服务端 digest 后才发布；同 tag 不同内容、额外资产或缺失资产都会失败，绝不 clobber。失败 draft 可续传。私有 API 下载跨 host 重定向时移除 Authorization/Cookie。

单包发布之后，才生成含完整 checkpoint 的 `extensions-index-<快照SHA前32位>` Release，内含 `index.json` 和 `state.json`。只有索引设置 GitHub latest；seed/单包都显式 `make_latest=false`。快照身份同时覆盖 index 和 state，重试计数等 checkpoint 变化也不会覆盖旧快照。发布前检查远程 index 未被另一运行推进，否则拒绝覆盖，先拉取并合并 checkpoint。索引保留上一可用版本并将未完成的新身份标为 stale；删除的源不再列入当前索引。

发布前逐个重新验证清单与所有产物字节。编译和完整性成功的包可以发布为 `compiled_unverified`，其索引 `runtimeReady=false`。只有带匹配 buildId/manifestSHA 的实际 Worker/browser 验证均通过才标为 `browser_verified`。默认无浏览器批量验证不会把编译冒充兼容、真实 Source 网络或图片支持；失败包只进入失败记录。

默认调度器直接执行严格的清单/字节完整性检查，不会因可选验证脚本存在就启动浏览器或运行尚未完成的验证工具。人工浏览器验证是显式阶段；已发布资产不会为补充验证而覆盖，后续兼容证据应使用独立不可变 attestation 或新的发布身份。

旧冻结研究输入的已转换构建与当前源码基线严格分开，可用下列命令先查看发布计划，再移除 `--dry-run` 实际发布；它只创建 `legacy-<buildId>`，不会进入当前 source baseline 或 latest 索引：

```sh
python3 tools/extensions/pipeline.py import-legacy \
  --manifest PATH_TO_MANIFEST --artifacts PATH_TO_ARTIFACT_FOLDER \
  --provenance PATH_TO_ORIGINAL_PROVENANCE --dry-run
```

已发布的 [legacy MangaDraft e350 构建](https://github.com/Wybxc/karuyomi/releases/tag/legacy-release9-mangadraft-product-e3505206005c25f69b92)来自旧冻结输入，`runtimeReady=false`，未进入当前源码基线。其 release-manifest SHA256 为 `b7f4deda88af0a10c3132b8c0275b0f207c405f280b07f06cc4994ef103eacec`；私有仓库与资产保持私有。

## CI 只做增量

`.github/workflows/extensions.yml` 每六小时或手动执行，先读私有最新 checkpoint，再跟进上游 main 的固定提交。缺少已完成的本地 baseline 时在 plan 阶段拒绝，不会启动首次全量 matrix。默认每次最多 12 包，手动上限 24，并发最多 2；共享库/host 变化产生的积压按多次运行消化。不自动重试所有未变更的确定失败。

plan/build jobs 只有 contents:read，checkout 不保留 git 凭据；上游 Gradle 子进程移除 GitHub token。publish job 单独拥有 contents:write，只读取并复核构建资产，既不运行扩展 Gradle，也不执行生成的 JS。整个 workflow 通过同一 concurrency group 串行更新索引，失败包不阻断其他包的记录。

回归测试不需要网络、GitHub token 或 JVM：

```sh
python3 -m unittest discover -s tools/extensions/tests -v
```

实现依据是上游源码中 `ExtensionPlugin.kt`、`generate-build-matrices.py` 和 `publish-repo.py`；GitHub transport 使用[官方 Releases REST API](https://docs.github.com/en/rest/releases/releases)的 draft、make_latest 与资产 digest 契约。
