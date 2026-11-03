# 扩展 AOT 构建与发布

当前上游来源是固定提交的 `vendor/extensions-source` submodule。调度器读取源码树的 `src/<lang>/<key>/build.gradle.kts`，不使用已退化成“Outdated App”提示的旧 `index.min.json`，也不把仓库提交时间当成扩展版本。当前 Gradle DSL 的 `pkgName` 覆盖默认 `<lang>.<key>`；主题的 `baseVersionCode` 与扩展 `versionCode` 相加得到有效版本，`versionName=<libVersion>.<有效版本>`，Android/index versionCode 按上游 `ExtensionPlugin.kt` 的 libVersion 编码规则计算。无法静态确认的 Kotlin 表达式单独记为 `discovery_failed`。

源码指纹覆盖自身目录、主题、递归 `project(":lib:...")` 依赖，以及上游 `common/core/compiler/gradle` 和根构建配置。host 指纹覆盖内化的 Java/bridge、正式构建工具、协议、共享材料生成器、runtime-host 包定义、pnpm 锁、工具链与 seed 锁，以及真正上游 submodules 的 gitlink/checkout 提交。同版本的共享库、host、工具链变化会生成新输入身份；无关上游提交不会使所有包重建。源码必须保持已提交状态，生成的 build/target/cache 不进入身份。

`scripts/build-extension.py --descriptor PATH --output DIR` 是逐包构建接口。它保留业务源码，通过官方 Gradle/KSP 生成 JAR 和 Source 元数据，再执行 AOT。输出包括 `manifest.json`、`artifacts/<sha256>`、`provenance.json` 与 `build-result.json`；失败必须非零退出并记明 upstream/host/aot 阶段。依赖只通过 `scripts/prepare-runtime.py --android` 的固定工具链、公开下载与本项目私有 runtime seed 准备，CI 不依赖研究 ZIP。

这里的 runtime seed 是 JAR 等构建依赖，不是下发给 Web/Native 阅读器的客户端资源。扩展 AOT bundle 通过本仓库私有 Release 分发。每包 `artifacts/` 和 `build-result.json.artifacts` 只包含私有 bundle；5 个通用桥和 zstd WASM 使用 `/runtime/materials/<sha256>` 公共内容寻址引用，由 Web 静态资源或 Native 应用资源交付。构建器调用 `node packages/runtime-host/prepare-materials.mjs --print` 取得 catalog，provenance 记录 `materialVersion`、完整 catalog 字节 SHA256 和协议 ABI。材料的顺序、长度、MIME、哈希仍须核验，不因公共交付而跳过。`--print` 不读取私有 seed 或 npm 安装目录；实际生成客户端资源时才读取并核对固定版本的 npm WASM。

## 首次全量只在本地执行

先提交稳定的 host/工具链变更并准备 seed。Python 之外需要 Node 24.15.0；私有 Release REST 访问使用环境中的 `GH_TOKEN` 或 `GITHUB_TOKEN`，需要本仓库 contents 权限；不要把令牌写入配置或提交记录。

```sh
python3 scripts/prepare-runtime.py --android
python3 tools/extensions/pipeline.py plan \
  --state .local/extensions/state.json --output .local/extensions/plan.json
python3 tools/extensions/pipeline.py bootstrap \
  --state .local/extensions/state.json --output .local/extensions/plan.json \
  --repository Wybxc/karuyomi --jobs 1
```

`bootstrap` 默认覆盖所有未尝试输入，限并发 1，最高可设 4；可用 `--limit N` 分批。每个包发布或失败后立刻原子保存 checkpoint，重复运行跳过已发布和未变更的确定失败。`--retry-failed` 明确重试原失败；GitHub 传输失败会在后续同身份运行中自动重试，累计最多三次，不会在当前批次立即循环。构建日志留在 plan 所在目录的 `builds/<inputFingerprint>/`，包含 `build.log` 与 `logs/upstream.log`、`logs/aot.log`，索引只保留有用的阶段/错误信息。state 使用文件锁防止两个进程并写。中断后保留 state 和输出，再执行同一命令即可继续；已上传的 matching draft 继续补齐，已发布身份不会覆盖。

长时间本地运行可在准备好凭据后交给后台，并保留统一日志：

```sh
mkdir -p .local/extensions
nohup python3 -u tools/extensions/pipeline.py bootstrap \
  --state .local/extensions/state.json --output .local/extensions/plan.json \
  --repository Wybxc/karuyomi --jobs 1 \
  > .local/extensions/bootstrap.log 2>&1 &
tail -f .local/extensions/bootstrap.log
```

全部发现包都有 `published` 或明确 `failed` 终态后，再执行一次带 `--finalize` 的 bootstrap：

```sh
python3 tools/extensions/pipeline.py bootstrap \
  --state .local/extensions/state.json --output .local/extensions/plan.json \
  --repository Wybxc/karuyomi --jobs 1 --finalize
```

baseline 完成代表首次覆盖已结束，记录 published/failed/discoveryFailed 数量；不代表所有扩展可运行。未尝试、仅本地 built 或尚未上传的包会阻止正常完成标记。`CI=true` 或 `GITHUB_ACTIONS=true` 环境完全禁止首次 bootstrap/finalize。

## 不可变 Release 与索引

每包 tag 为 `ext-<packageSuffix>-v<AndroidVersionCode>-<inputFingerprint前32位>`。新 `source-aot` Release 仅将私有 bundle 用 gzip level 9 压缩，固定 mtime=0、无文件名、平台无关 gzip 头；资产名为 `<canonicalSHA256>.gz`，共享 JS/WASM 不重复上传。另含 `manifest.json`、调度 provenance、原始 build provenance 与 validation。清单始终声明解压后的 canonical SHA256/长度，R2 注册和客户端执行也使用原始字节。

`artifact-encodings.json` 的版本为 `schemaVersion: 1`，`artifacts` 中每项包含 `sha256`、`size`（canonical 原始值）、`asset`、`encoding: "gzip"`、`encodedSha256`、`encodedSize`。`release-manifest.json` 则汇总所有实际上传资产的 SHA256/长度，包括压缩字节及编码表，并最后上传。先建 draft，确认资产与服务端 digest 后才发布；同 tag 不同内容、额外资产或缺失资产都会失败，绝不 clobber。失败 draft 可续传。私有 API 下载跨 host 重定向时移除 Authorization/Cookie。

恢复先校验完整 Release 传输清单，再核对编码表中的压缩 SHA256/长度，解压最多允许清单声明的原始长度（单项上限 64 MiB），最后再次核对 canonical SHA256/长度。截断、拼接 gzip、尾随字节、超长输出、重复或未知编码项均失败；存在错误编码表时不回退 raw。旧 Release 没有编码表时继续读取原有 64 位 SHA 命名的 raw 资产；已有 legacy 发布不改写。恢复后重试发布会保留原压缩字节，避免不同 zlib 版本改变不可变资产。

指定计划中的单包构建命令会先尝试恢复相同 Release，成功则不运行 Gradle/AOT；同时重建本地 `artifacts/<canonicalSHA256>` 供注册使用：

```sh
python3 tools/extensions/pipeline.py build --plan .local/extensions/plan.json \
  --key INPUT_FINGERPRINT --output .local/extensions/builds/INPUT_FINGERPRINT \
  --repository Wybxc/karuyomi
```

两份现有 AOT 字节已在本地完成共享材料引用、gzip、下载校验、canonical 恢复和不可变重试核验。MangaDraft 为 3,777,975 → 791,368 bytes，Arknights 为 1,824,293 → 583,749 bytes。此核验使用内存中的 GitHub API 替身，未新建或发布真实 Release，未重新执行 AOT，也不增加浏览器或在线兼容声明；压缩字节长度可能随 zlib 版本变化，实际发布以编码表哈希为准。

单包发布之后，才生成含完整 checkpoint 的 `extensions-index-<快照SHA前32位>` Release，内含 `index.json` 和 `state.json`。只有索引设置 GitHub latest；seed/单包都显式 `make_latest=false`。快照身份同时覆盖 index 和 state，重试计数等 checkpoint 变化也不会覆盖旧快照。发布前检查远程 index 未被另一运行推进，否则拒绝覆盖，先拉取并合并 checkpoint。索引保留上一可用版本并将未完成的新身份标为 stale；删除的源不再列入当前索引。

发布前逐个重新验证清单与所有产物字节。编译和完整性成功的包可以发布为 `compiled_unverified`，其索引 `runtimeReady=false`。只有带匹配 buildId/manifestSHA 的实际 Worker/browser 验证均通过才标为 `browser_verified`。默认无浏览器批量验证不会把编译冒充兼容、真实 Source 网络或图片支持；失败包只进入失败记录。

默认调度器直接执行严格的清单/字节完整性检查，不会因可选验证脚本存在就启动浏览器。人工浏览器验证是显式阶段：

```sh
node tools/extensions/verify-build.mjs --directory DIR --report DIR/validation.json
node tools/extensions/verify-build.mjs --directory DIR --report DIR/validation.json \
  --serve --timeout-ms 120000
node --test tools/extensions/verify-build.test.mjs
```

第一条只检查清单、SHA256、长度与 MIME；完整性通过但未运行浏览器时退出 2，报告 `valid=false`、`runtimeReady=false`、`browser_not_run`。`--serve` 只监听 `127.0.0.1` 临时端口；人或 CUA 打开打印的 URL 后，页面自动用真实产品 Worker 和 IndexedDB 执行初始化。清单/字节或浏览器验证失败退出 1，实际浏览器验证通过才退出 0。报告始终将 `onlineCompatibility` 记为 `not_tested`，初始化成功不代表在线 Source 或图片链路可用。验证器的 Node 回归测试不执行生成的扩展代码。

已发布资产不会为补充验证而覆盖，后续兼容证据应使用独立不可变 attestation 或新的发布身份。

旧冻结研究输入的已转换构建与当前源码基线严格分开，可用下列命令先查看发布计划，再移除 `--dry-run` 实际发布；它只创建 `legacy-<buildId>`，不会进入当前 source baseline 或 latest 索引：

```sh
python3 tools/extensions/pipeline.py import-legacy \
  --manifest PATH_TO_MANIFEST --artifacts PATH_TO_ARTIFACT_FOLDER \
  --provenance PATH_TO_ORIGINAL_PROVENANCE --dry-run
```

已发布的 [legacy MangaDraft e350 构建](https://github.com/Wybxc/karuyomi/releases/tag/legacy-release9-mangadraft-product-e3505206005c25f69b92)来自旧冻结输入，`runtimeReady=false`，未进入当前源码基线。其 release-manifest SHA256 为 `b7f4deda88af0a10c3132b8c0275b0f207c405f280b07f06cc4994ef103eacec`；私有仓库与资产保持私有。

## CI 只做增量

`.github/workflows/extensions.yml` 每六小时或手动执行，先读私有最新 checkpoint，再跟进上游 main 的固定提交。缺少已完成的本地 baseline 时在 plan 阶段拒绝，不会启动首次全量 matrix。默认每次最多 12 包，手动上限 24，并发最多 2；共享库/host 变化产生的积压按多次运行消化。不自动重试所有未变更的确定失败。

plan/build jobs 只有 contents:read，checkout 不保留 git 凭据；上游 Gradle 子进程移除 GitHub token。三个 job 均用 setup-node 固定 Node 24.15.0，材料 catalog 的读取不需要 npm install；publish 的非递归 checkout 已含桥源码、协议与固定 WASM 元数据。publish job 单独拥有 contents:write，只读取并复核构建资产，既不运行扩展 Gradle，也不执行生成的 JS。整个 workflow 通过同一 concurrency group 串行更新索引，失败包不阻断其他包的记录。

回归测试不需要网络、GitHub token 或 JVM：

```sh
python3 -m unittest discover -s tools/extensions/tests -v
```

实现依据是上游源码中 `ExtensionPlugin.kt`、`generate-build-matrices.py` 和 `publish-repo.py`；GitHub transport 使用[官方 Releases REST API](https://docs.github.com/en/rest/releases/releases)的 draft、make_latest 与资产 digest 契约。
