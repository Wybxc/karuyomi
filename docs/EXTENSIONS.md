# 扩展 AOT 构建与发布

当前交付决策是 Static Assets 作为所有客户端的扩展权威源，每包只保留最新可用构建，客户端或 Service Worker 管理更新。扩展不再发布到 GitHub Release；共享材料仍由 Web Static Assets / Native 内置提供。下文 Release/R2 流程是待替换的现有实现，静态分发与增量状态迁移按[工程计划](plan/engineering-and-release.md)推进。

上游来源是固定提交的 `vendor/extensions-source`。调度器读取 `src/<lang>/<key>/build.gradle.kts`，按官方 `ExtensionPlugin.kt` 计算 Android versionCode，不使用已退化为提示页的旧 `index.min.json`。无法静态确认的 Kotlin 表达式单独记录为 `discovery_failed`。

`inputFingerprint` 仍是内部增量身份，覆盖包名、版本、源码依赖和 host 输入。共享库、桥、工具链变化即使没有修改扩展版本，也会产生新输入身份；无关上游提交不使全部包重建。它用于 checkpoint、buildId 和 provenance，不进入 Release tag/title。

## 固定 Release 定位

扩展的 tag 和 title 都为 `ext-<packageSuffix>-v<AndroidVersionCode>`，例如 `ext-all.ahottie-v106005`；索引固定为 `extensions-index`。名称只用于定位当前结果，同版本 host 变化会更新相同定位。tag 不移动，实际构建的上游提交、host 提交和输入身份由 provenance 记录。

本项目仍在原型阶段，只支持当前格式，不提供旧 hash-tag、旧传输清单或 raw 资产恢复兼容。历史 Release 保留原样，发布器不查找、改写或迁移它们。旧 checkpoint 中已经发布的历史记录仍会跳过，并从新 `index.json` 的可下载包列表排除；它们不代表已按新格式重新发布。

GitHub 不支持覆盖同名资产。更新流程明确为：

1. 将当前定位设为 draft，暂时隐藏该 Release。
2. 移除旧 `release-manifest.json`，删除多余或内容不匹配的资产，补齐当前资产。
3. 最后上传 `release-manifest.json`，核对上传响应的服务端 SHA256/长度。
4. 最后一次 PATCH 写入当前 pointer 并设为非 draft；索引更新总在本批单包处理之后。

中断留下 draft，重跑会补齐；同内容重跑不替换资产。更新期间定位可能暂时不可用，读者必须重试；拉取处于 draft 的索引会报可重试错误并保留本地 checkpoint。读者若跨越替换窗口取得混合快照，会在下载完整性校验中失败，不能将其视为成功。这里不提供无停机替换或历史 generation 读取。仓库必须允许 mutable releases，发布器遇到 immutable 定位会拒绝修改。

Release body 的 `karuyomiRelease` pointer 含 `schemaVersion: 2`、内部 generation、manifest asset id 和 manifest SHA256。`release-manifest.json` 同为版本 2，记录 tag、generation 和每个上传资产的 SHA256/长度。只有索引设置 GitHub latest，扩展和 runtime seed 均不设置 latest。远端 index pointer 不符合 checkpoint 时拒绝覆盖，先拉取并合并状态。GitHub PATCH 没有事务式 CAS；本地文件锁和 CI concurrency group 必须保证只有一个 publisher，不能同时从独立工作区或 CI 发布。

## 传输与校验

每包只上传一个私有 AOT bundle，使用 gzip level 9、mtime=0、无文件名及平台无关头。资产为 `<canonicalSHA256>.gz`，另有 `artifact-encodings.json`、`manifest.json`、调度及构建 provenance、validation。通用桥与 zstd WASM 由 Web 静态资源或 Native 打包交付，不重复上传到扩展 Release。

编码表记录 canonical SHA256/长度和 encoded SHA256/长度。清单与客户端始终使用解压后的 canonical 身份。下载先校验收到的 manifest 和每个资产；有界解压时再验证不同字节域的 canonical SHA256/长度。截断、拼接 gzip、尾随字节、超长输出、缺失或重复编码项均拒绝。

摘要只在上传/下载边界验证。上传在读取 canonical 字节进行压缩时核对一次，压缩摘要复用于清单和服务端响应比较；下载收到的压缩字节只计算一次摘要，解压后的原始字节也只计算一次。进程内的 owned bytes/metadata receipt 在相邻阶段传递，不从磁盘 JSON 恢复“信任”。阶段间仍检查 schema、身份、大小、MIME、静态材料引用及路径，不反复读取同一大文件计算摘要。注册到 D1/R2 是独立交付边界，其默认完整性校验不关闭。

构建器调用 `node packages/runtime-host/prepare-materials.ts --print` 获取 catalog。该命令需要安装锁定的 npm 依赖，会编译项目 TypeScript 桥并打包锁定的 npm zstd glue；metadata-only 不读 WASM bytes 或私有 JVM seed。实际生成 Web/Native 材料时才读取并核对固定 WASM。runtime seed 是 JAR 等构建依赖，不下发阅读器。

## 本地首次全量与恢复

先提交稳定 host/工具链，初始化 submodules，执行 `pnpm install --frozen-lockfile` 并准备依赖。新的全量宿主统一使用 HTTP v2；先完成代表包验证，再固定全量输入，避免先发布 v1 后立即重建。REST 凭据使用环境中的 `GH_TOKEN` 或 `GITHUB_TOKEN`，不写入配置；上游 Gradle/AOT 子进程会移除这些发布凭据。

```sh
python3 scripts/prepare-runtime.py --android
python3 tools/extensions/pipeline.py bootstrap \
  --state .local/extensions-current/state.json --output .local/extensions-current/plan.json \
  --repository Wybxc/karuyomi --jobs 1
```

`bootstrap` 默认处理所有未尝试输入，并发默认 1、最高 4，`--limit N` 可分批。每包 published/failed 后原子保存 checkpoint，跳过已发布及未变化的确定失败；`--retry-failed` 明确重试失败。GitHub 传输失败最多自动重试三次，不在同批中无限循环。保存成功后，仅清理精确 buildId 的 `extension-work`、`extension-cache` 和 `gradle-launcher`，不跟随 symlink。交付目录、state、`build.log`、`logs/upstream.log`、`logs/aot.log` 和失败诊断保留，共享 Maven/Gradle 缓存保留。

每个 builder 使用独立进程组。SIGINT/SIGTERM 会停止派发、取消待运行任务，先终止并等待已注册的 builder 进程组，再释放 checkpoint 锁；三秒宽限后仍在运行的组成员会被强制终止。该操作只针对本次创建的构建进程组，不搜索或终止共享 Gradle daemon 和其他任务。

长批次使用固定提交的独立 clone。外层 runner 可以复用该 clone 的完整 plan 和 checkpoint，不修改 clone，也不重算或替换 descriptor/host 身份。下面使用当前 host 的独立构建目录作为示例；冻结材料必须仍属于当前产品 catalog，才能继续当前产品发布：

```sh
python3 tools/extensions/pipeline.py bootstrap \
  --plan .local/extensions-current/plan.json \
  --build-checkout .local/current-aot \
  --state .local/extensions-current/state.json \
  --output .local/extensions-current/resume-plan.json \
  --repository Wybxc/karuyomi --jobs 1
```

runner 检查冻结 checkout 的提交、干净 host 输入、实际指纹、submodule 和上游提交，调用该 checkout 自己的 `scripts/build-extension.py` 与当前 TypeScript 材料入口；不提供旧 MJS 或旧协议回退。此前已成功构建但发布中断的本地交付可以复用，避免重新执行 Gradle/AOT。磁盘 `pipeline-result.json` 不作为当前 Release 仍存在的证据；只有本轮真实下载得到的进程内 receipt 可以免发布，普通磁盘复用必须重新走当前定位发布。工作缓存清理指向 `--build-checkout`，交付和日志继续保留在 `--output` 相邻的 `builds/<inputFingerprint>/`。

切换 publisher 前先正常停止旧调度进程，确认它释放 checkpoint 锁，再启动新命令；不要并发写同一 state。历史 `.local/aot-bootstrap` 固定于 `7f54463`，在 1,448 包中已记录 86 published、9 failed、1,353 pending 后停止，记录已备份至 `.local/extensions/history/pre-typescript-host/`。其五个桥的 hash 不属于当前 Web/Native 六项材料集合，不能接续为当前产品发布；旧 Release/checkpoint 保留为历史，当前队列必须在提交稳定的当前 host 后以新指纹重新计划。冻结 runner 保留用于可复验构建，不为当前产品增加旧材料兼容层。

全部发现包都有 published 或明确 failed 后，再对同一命令增加 `--finalize`。baseline 完成代表覆盖已结束，记录 published/failed/discoveryFailed，不代表全部扩展可运行。未尝试或仅 built 的包阻止 finalize。`CI=true` 或 `GITHUB_ACTIONS=true` 禁止首次全量及冻结计划恢复/finalize。

恢复单个当前格式 Release，可使用：

```sh
python3 tools/extensions/pipeline.py build --plan .local/extensions-current/plan.json \
  --key INPUT_FINGERPRINT --output .local/extensions-current/builds/INPUT_FINGERPRINT \
  --repository Wybxc/karuyomi
```

相同定位的当前 generation 匹配输入身份时，下载恢复代替 Gradle/AOT。同版本但 generation 不同视为缓存未命中，构建新输入后替换该定位。

## 兼容证据与 CI

编译成功可以发布为 `compiled_unverified`，始终 `runtimeReady=false`。只有匹配 buildId/manifestSHA 的真实 Worker/browser gate 均通过才为 `browser_verified`；初始化成功不证明 Source 在线请求、图片或真机支持。人工验证是显式步骤：

```sh
node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json
node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json \
  --serve --timeout-ms 120000
node --test tools/extensions/verify-build.test.ts
```

默认完整性通过但未运行浏览器时退出 2，报告 `valid=false`、`runtimeReady=false`、`browser_not_run`；失败退出 1，实际浏览器通过才退出 0。`--serve` 只监听 loopback，人或 CUA 打开 URL 后运行真实产品 Worker/IndexedDB。`onlineCompatibility` 始终为 `not_tested`。

`.github/workflows/extensions.yml` 每六小时或手动运行，只做增量。没有已完成本地 baseline 时拒绝生成首次全量 matrix；每次默认 12 包、手动最高 24，并发最多 2。plan/build 仅 contents:read，publish 单独 contents:write；三个 jobs 均安装固定 Node 和锁定 npm 依赖。publish 只编译受信桥 metadata 并处理资产，不运行扩展 Gradle 或生成的 JS。所有发布使用同一 concurrency group。

项目 CI 使用 `.github/workflows/project-ci.yml`，仅分支 push/PR 触发；Release tag 不启动项目检查。历史 `ci.yml` 在 GitHub 禁用，避免指向旧构建提交的 tag 重新触发旧配置。

```sh
python3 -m unittest discover -s tools/extensions/tests
CI=true GITHUB_ACTIONS=true python3 -m unittest discover -s tools/extensions/tests
```

测试不使用网络、GitHub 凭据、JVM 或真实 Source。冻结 runner 测试只执行自有 Python fixture，验证 checkout 选择、凭据隔离、本地复用，以及 SIGINT/SIGTERM 下 sleeping builder/孙进程停止后才释放锁。发布行为依据 [GitHub Releases API](https://docs.github.com/en/rest/releases/releases) 和 [Release assets API](https://docs.github.com/en/rest/releases/assets)。
