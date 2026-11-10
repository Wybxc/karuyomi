# v6 本地 AOT 试编与公开构建身份

2026-11-07，在干净的独立 checkout 固定项目 `993fe544`、Keiyoushi `efa93f5a`、host ABI v6 / control 2 / HTTP bridge 2 / release9。以匿名 HTTPS 重新核对线上 build-state 与 index 的精确字节，基线 revision 为 `702cc6bfb2974682bf1c83325458535a`，`bootstrap.complete=false`。正式发现 1,448 包，无发现失败；全量计划 SHA-256 为 `ed1e73ed6eb423fdab76cdbf6b9cf82fb642f602b094597aa3d2c07b0e556eec`，大小 14,321,059 B。仅从该计划选三个代表包，按 `jobs=1` 走正式构建与静态快照装配。

| 扩展             |    耗时 |      gzip |
| ---------------- | ------: | --------: |
| xkcd             | 42.14 s | 930,610 B |
| Arknights Comics | 36.27 s | 669,533 B |
| CuuTruyen        | 41.46 s | 888,248 B |

三份终态均为 `compiled_unverified`，静态候选 revision 为 `21204762900b4cb88ed88c9d908d1a5a`，index SHA-256 为 `e424ec777f9fbdb12fd6c6d5abf041a436086e9a9ea6a3c7c134029efc26276e`。构建与装配正常退出，其余 1,445 包没有启动，未部署、未提交生产 checkpoint、未启用增量 CI。固定输入、输出和逐包记录留在本地忽略的 `/private/tmp/karuyomi-local-baseline-993fe54-yDXFKs`，只作该次证据。

## 同一输入两次输出的对照

当前候选和先前 `5ba6fff` 的 xkcd 使用同一个输入指纹 `dd84d305506e2bdc34ac62988aef645f56bb7b6567c85ed55b73d2b4284ca491`。原始 JAR、15 份 donor、seed、材料及实际工具链 JAR 摘要一致。两份 canonical JS 均为 4,477,929 B，AST 可正常解析，字符串池排序后完全相同；37 个索引和相应代码顺序发生移动。当前 SHA-256 为 `31de2bd8c529bb0cbd310725b7c400cf511be1863554bf9d55a17ffc03f27e55`，此前为 `5fd6e868d3b077db8893ce4a517dd486dc7938c04a7af5c70507ba0eabea7682`。TeaVM 0.16.0 实际字节码的依赖传播存在按对象身份哈希排列的集合，发射器依赖发现顺序；本轮未隔离触发具体重排的传播边，不声称已使编译器可复现。

当时仅以输入指纹生成公开 ID，两份不同 JS 共用同一个清单路径和索引身份。Flutter 会把已安装记录识别为当前版本，隐藏更新操作；下载准备读取新清单后又会按已确认的旧摘要拒绝打开。现有缓存与授权以 canonical SHA 隔离，两份字节不会被错误混用。旧候选保留为观察证据，原 `5ba6fff` 的在线验收不能移用到新字节。发布身份与恢复合同见[扩展静态分发](../EXTENSIONS.md)。

## 绑定摘要后的正式三包和同站 Web 更新

固定 `952bbab` 的新 checkout 再次从原 JAR 串行编译三包。1,448 条完整计划 SHA-256 `8606cad23bd27a10b5588ef0e4bdcb23cee255d53e87524bc0eb247c5c797532`；生产 parent 仍为 `702cc6bfb2974682bf1c83325458535a`，构建前后远端 state/index 字节不变，正式 `check-base` 通过。候选 revision `48dc5b618c924a6eaa53bb5ed02a49cf`，index SHA-256 `57bcd5bd0cda4d3467950c2d8b399d8f4bccb56e1f396291146bde4cc5339277`，3 成功、0 失败、1,445 待构建，`bootstrap.complete=false`。xkcd、Arknights Comics、CuuTruyen gzip 分别为 930,554、669,511、888,219 B。逐包确认公开 ID 的后缀、清单、索引、状态记录与实际正文一致；内部工作名没有公开路由。

Web 使用固定 `d2a21aa` 的 Flutter 产物（`main.dart.js` SHA-256 `178c4b43bfe620ef8df51078db0e87a8bb53c8c05d9e555f2ed221d42063794c`）。旧 `5ba6fff` xkcd 快照与新三包快照都经正式 Vite 组装，客户端和验收 Worker 的 JS 字节相同。Codex 内置浏览器在同一文档、同一 loopback origin、同一隔离 workerd/D1 和 `acceptance-owner` 进行：

| 阶段         | 实际结果                                                                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 旧快照       | 正式扩展管理确认安装 xkcd 1.6.1；从英文 Source 收藏 xkcd，打开 `/3319/` 并保存第 2 页，真实文字图显示；缓存只有旧摘要 `5fd6e868d3b0…`。                                        |
| 切换静态快照 | 官方 TestHarness 重载配置，origin 不变。独立请求确认旧清单和旧 gzip 为 404，新清单和新 gzip 为 200；独立读取的设置、书架、作品和章节进度与切换前逐字段相同。                   |
| 正式更新     | 版本号仍为 1.6.1，界面显示旧构建下架和「准备并确认更新」。确认后只修改已确认安装的 ID、摘要与对应 revision；书架、阅读锚点和其它设置不变，本机缓存只剩新摘要 `969bd86a14e9…`。 |
| 新构建续读   | 从原书架点击「继续阅读：xkcd」，首次即显示 `3319: Elevators` 第 2 页真实文字图，未手动翻页，进度获得服务端确认。独立 GET 核对 epoch、当前页与最远页的稳定 key 不变。           |

正式复验命令（依次执行，使用已核对的两个快照绝对路径）：

```sh
EXTENSION_ASSETS_DIR="$before" pnpm acceptance:build
EXTENSION_ASSETS_DIR="$after" pnpm --filter @karuyomi/api build
pnpm --filter @karuyomi/api exec vite build --config vite.acceptance.config.ts \
  --outDir "$stage/next"
ACCEPTANCE_NEXT_CONFIG="$stage/next/karuyomi/wrangler.json" \
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.all.xkcd","allowedHosts":["xkcd.com","imgs.xkcd.com"]}]' \
pnpm acceptance:serve
```

用服务打印的 URL。旧版阅读已确认且退出后，在验收进程的 stdin 输入 `switch`，等待 `ACCEPTANCE_SWITCH=switched`；在产品界面确认更新并复验续读。输入 `stop` 关闭验收服务。切换过程只更新本地 Source 网络登记，不重跑 D1 migrations；没有用直接业务写入代替 UI。原始业务采样与构建日志留在本地忽略目录，试跑目录和文件未发布。三个候选仍为 `compiled_unverified` / `runtimeReady=false`；本门只验证 xkcd Web 更新与续读，生产、Native 更新、其它 Source 及完整 baseline 独立验收。

## 首次本地全量启动

2026-11-07 17:20（UTC+8），从固定 `952bbab` 的隔离 checkout 启动本地全量。正式入口记录 `discovered=1448`、`selected=1448`；以完整计划复用三个输入身份匹配的成功检查点，首个新包 `all.ahottie` 已进入上游 Gradle 构建。这里记录的是启动证据，不能据此认定任何新包完成。

本机忽略目录 `.local/extensions-baseline-952bbab/` 保存冻结计划、独立 checkout、已核对的生产 parent state/index、逐包结果、恢复计划及日志。使用单并发 `bootstrap --plan frozen-plan.json --build-checkout checkout --state state.json --output resume-plan.json --assets-dir candidate --jobs 1 --finalize`（路径按该目录解析）。若中断，先确认原发布器已退出，再按 [恢复约束](../EXTENSIONS.md#首次本地全量与恢复)使用相同冻结输入和检查点。此命令只准备本地候选，不部署，不更新生产 checkpoint，不启用增量 CI。

## 当前宿主全量启动

2026-11-08，原 `952bbab` 批次的图形桥摘要与当前宿主不同，正式装配不能混用。旧 runner 按正式取消路径收到 SIGTERM，退出码 143，锁释放；保留 867 个成功、76 个失败检查点作为该提交的证据，另有 505 包未尝试。未生成、部署旧全量快照。

新的独立 checkout 固定为 `c04d436`；上游扩展提交仍为 `efa93f5a`，宿主指纹为 `d9990e66a60fa830c943dcceb07a2fa5558e053d5f40f4b74d48bc3977fa496b`。通过匿名读取生产 index/state 核对真实父 revision `702cc6bfb2974682bf1c83325458535a`、三包和 index SHA。固定 Node 24.15.0、pnpm 12.6.0、三子模块及工具链锁，以正式 `prepare-runtime.ts --android --seed` 校验准备工具链和 seed。

本地忽略目录 `.local/extensions-prototype-v6.n7bHUj/` 保存原样父状态、固定计划、构建结果和日志。按[首次全量与恢复](../EXTENSIONS.md#首次本地全量与恢复)生成 `frozen-plan.json` 后，单并发 `bootstrap --plan … --build-checkout … --jobs 1 --finalize` 发现并选择 1,448 包，首包 `all.ahottie` 已写入正式 built 检查点。此次不使用旧宿主结果，仍只准备本地候选。后续需要用匹配的产品材料装配，验证静态及 Source 分项、生产 Access 和网络政策；候选未部署，增量发布继续停用。

同日，为释放 Mac 的 CPU，将该冻结批次迁至独立 Fedora x86_64 构建机。先用固定提交和锁定工具链在 Linux 重建材料，`materials.json` SHA-256 与 Mac 完全一致；在独立输出目录重新编译 xkcd，编译与产物完整性通过。Mac 调度器收到 SIGTERM 后等待 builder 退出并释放状态锁。停机后将父状态、计划和逐包结果同步至 Fedora；传输前后 295 个成功、16 个失败检查点的记录逐项摘要一致，剩余 1,137 个输入。Fedora 用同一冻结计划单并发恢复，保留原失败结果，并为首个待处理输入 `d68d5c0f…` 写入新 `built` 检查点。Mac 目录保留为交接备份，恢复只生成待验收候选，未部署。

## clab 在途失败抽样

2026-11-09 23:08（UTC+8），在固定 `c04d436` 的 clab 批次仍运行时，只读核对当时已完成的 1,088 个逐包 `pipeline-result.json`：1,036 成功、52 失败（16 条由 Mac 迁入、36 条在 clab 生成）。1,036 个成功均为 `compiled_unverified`。同次公开读取确认生产仍是三个包，`build-state.json` 的 revision 仍等于该批次的生产 parent，`bootstrap.complete=false`。这些是固定时点的观察，不是最终候选或部署结果。

52 条结果均为 AOT 阶段的 `ExecaError`，对应的上游 Gradle 均已成功。逐包 `logs/aot.log` 显示其中 50 条为 TeaVM 缺类或方法，另有 `en.manhwaread` 的编译 JVM `Java heap space`，以及 `all.lunaranime` 的无栈 `Unexpected error occurred: 2/2`；后一条不能单凭文本套用下节旧批次的定位。逐包摘要和只读复验方法保存在本机忽略目录 `.local/aot-clab-triage/`，重采样结果与原摘要逐字节一致。

链接缺口包括 Android API（21 包，其中 10 包涉及 WebView）、JCA 加解密（10 包）和 OkHttp 接口（8 包），同一包可有多项。11 包缺 `Class.getResource(String)`，其中 5 包当次只报这一项。核对原始 JAR 和调用点，Webnex、CapibaraTraductor、MangaFire 用它读取打包在 `assets/` 内的文本。全量结束后可先在隔离 AOT 实现并验证此资源读取模式，保留缺失资源、字符集和流关闭的语义；仍需对代表包验证实际读取，不能据一次编译认定兼容。没有修改冻结输入、重试同指纹失败包或启动第二个发布器。

## 冻结全量与当前 AOT 的定向补编预检

2026-11-10，重新从公开静态路径读取生产 state/index，核对二者摘要匹配。固定 `c04d436` 的冻结计划与 `a382be1` 的补编计划使用同一生产父 revision `702cc6bfb2974682bf1c83325458535a`、同一上游 `efa93f5a`、同样的 1,448 包与源码输入。两版生成的 ABI、协议、HTTP 桥及共享材料字节一致；AOT 宿主指纹不同，逐包编译记录仍需保留各自实际输入身份。

冻结 AOT 的清单未生成当前的 Source 设置同步规则。首发前补编 Komiic、Asura Scans 和 MangaKatana，再核对成品清单与正式设置读写。冻结 MangaFire 是已记录的编译失败，仍保留原结果。三包补编及真实候选尚未生成。

新增的[本地候选组装入口](../EXTENSIONS.md#首次全量候选的定向补编)用这两份固定计划、同一生产父快照和两个空结果目录预检，确认缺少首个冻结结果时退出且不生成快照。定向回归另覆盖成功合入及保留冻结失败、父索引不符、材料不符、缺失与损坏结果，以及上游输入不一致。真实两份计划和原始预检日志保存在 `.local/baseline-supplement-a382be1/`。当前 clab 队列与生产均未改动。

2026-11-10，在 clab 用固定 `2a07fc2` 补编 checkout、真实 `c04d436` 冻结结果目录、同一生产父快照及上述三个精确包名执行正式 `prepare-baseline`。两个 checkout 与六份共享材料一致，线上 state/index 校验通过；入口到达冻结终态检查，报告 `tr.eskimangalar` 尚无结果，未生成快照。原始结果在 clab 的补编目录 `candidate-preflight.4IUnji/prepare.log`。冻结 supervisor 持续运行；未启动补编、未改生产。该结果验证的是实际输入预检和缺结果时停止，完整候选仍待生成。

## 首发六材料产品归档

2026-11-10，另建固定 `2c012db` 产品 checkout，回摘本机服务地址保存 `98d78aa` 和 Native 登录修复 `016a5d0` 的生产源码路径。正式 `hostFingerprint()` 完整结果应用前后逐字节一致（`1ba88f82…18dc`）；保留冻结与补编扩展各自原始宿主指纹。空索引 `pnpm build` 成功，六份共享材料、Web host/worker 及 Native host/worker/manifest 与原 `2c012db` 成品逐字节一致，材料版本仍为 `5d1260e5…92e4`。

该归档的正式 Wrangler harness 核对登录 303 携带同一 UUID、回跳 GET/HEAD 无脚本且 no-store、随后 bootstrap 200。旧 Native 回跳参数返回 400，首发必须使用新版配套安装包。服务地址正式 AppShell 回归 1/1 通过；`wrangler versions upload --dry-run` 通过且未上传。复验命令、补丁和原始比对保存在本机忽略目录 `.local/six-material-product-2c012db.3549L2/`。

本轮空索引不能发布。等待冻结结果和三个补编结果后，用同一产品归档装配正式扩展快照并重跑构建、dry-run、双端 Native 安装与实际 Source 门；未改冻结运行目录、候选 state 或生产。

2026-11-10，从上述归档独立复制源码，再回摘阅读中 Access 恢复的显式重试和视口保留两项修复。回摘的七个产品源码文件与通过隔离 iOS 复验的文件逐字节一致。完整 `hostFingerprint()` JSON、Web 材料清单与 host/worker、Native host/worker/manifest 与旧归档逐字节相同，仍使用冻结 v6 的六份材料。空索引的正式 Web/Worker 构建和 Wrangler 上传 dry-run 通过；使用完整快照的最终构建、发行签名与生产验收另做。本机忽略目录 `.local/prototype-reader-recovery.mw5OJU/` 保留补丁、构建和核对日志。

### 六材料 Native 发布构建

2026-11-10，用上述固定归档与 Flutter 3.47.5 / Dart 3.13.4 分别从正式 `lib/main.dart` 构建 Android arm64 release APK 与 iOS arm64 iPhoneOS `--no-codesign` 应用。两个 Dart AOT 二进制均包含正式默认服务地址、本机服务地址保存键和新登录回跳路径。此归档只回摘了服务地址与 Access 修复，尚未包含后续的阅读进度恢复修复。

- Android APK 为 23,480,920 B，SHA-256 `ed057058cd4a6d1f4424ab5d93514af0f336d8fe28dd85f3542fb47ea19e02e5`，仅 `arm64-v8a`，不可调试。项目当前 Gradle 配置生成的本机 Android Debug 证书通过 APK v2 校验；没有发行签名，也不能以该证书覆盖旧的不同证书侧载包。
- iOS Runner 和 `App.framework/App` 均为 iPhoneOS Mach-O arm64，应用 ID `dev.karuyomi.karuyomi`。成品无签名和 provisioning profile，尚不能安装到真机。

从两份实际成品分别取出 `host.js`、`worker.js`、`manifest.json`，均与归档 Vite Native 输出逐字节一致；从 Worker 核对实际嵌入的五个桥脚本和 zstd WASM 全部匹配六材料 `5d1260e5…92e4`。构建未改变 Dart 依赖锁或平台跟踪文件。命令、产物和核对日志见本机忽略目录 `.local/six-material-product-2c012db.3549L2/NATIVE_RELEASE.md`。两包未安装或运行；最终扩展快照、发行签名、真机和生产 Access 另验。

同日，从加入两次阅读恢复修复的六材料归档重建 Android arm64-v8a release APK 和未签名 iPhoneOS arm64 App。两份实际包内的三项 Native 资源逐字节匹配，清单 SHA-256 仍为 `c0839e9a5af816ccb0681a8187558cc80f7cc16b641daa20bde744b4418c31f5`，Worker 确认内嵌同一六份材料；Dart 锁文件未变。Android APK CRC 和本地测试签名验证通过，在无默认网络的专用模拟器侧载并冷启动显示书架。iOS 未签名。本轮复验命令与成品记录见 `.local/prototype-reader-recovery.mw5OJU/REPRODUCE.md`；在线阅读使用独立调试验收包，发行签名、生产和真机另验。

### 六材料首发修复合并预检

2026-11-10，在带本机服务地址、登录回跳及阅读恢复修复的 `2c012db` 归档副本中，回摘 `a430647` 的 Android 发行签名配置和 `ab46c3b` 的短窗口阅读修复。以冻结 `c04d436` 的 Arknights Comics 1.6.2 单包静态快照运行 `EXTENSION_ASSETS_DIR=<单包快照> pnpm build`，部署输出的扩展索引与输入相同，六份 Web 材料和三个 Native 运行时文件均与原归档逐字节一致。使用实际生成的 Wrangler 配置执行 `deploy --dry-run` 通过；阅读恢复与 ReaderScreen 的 43 项定向回归通过。

从正式 `lib/main.dart` 和生产默认服务地址构建 Android arm64-v8a release APK 和 iPhoneOS arm64 App。两包均未签名，包内运行时文件与 Vite 输出逐字节一致，Worker 内嵌六份材料，Native 清单摘要与原归档相同。构建未更改 Dart 依赖锁。Android 在测试后用正常 release 命令重新生成插件注册；iOS 首次受 SwiftPM 缓存写权限阻断，允许 Xcode 写构建缓存后通过。复现步骤、失败记录、产物及核对结果见本机忽略目录 `.local/prototype-six-material-rc.XbbXZW/REPRODUCE.md`。

此预检只覆盖单包装配、工程回归和未签名构建。完整快照到位后复用同一归档重跑构建及部署预演，执行真实 Source 验收，并使用正式签名在真机验证；本轮未安装这两个包或切换生产。

### 六材料完整候选

2026-11-10，clab 固定 `c04d436` 的 1,448 个输入全部取得终态：1,371 成功、77 失败。使用固定 `2a07fc2` 和同一上游提交、生产父快照与六份材料，定向补编 Komiic、Asura Scans、MangaKatana；三包均为 `built`。首次 Gradle 下载很慢，在进入编译前有序取消，确认未写入失败结果。之后复用冻结批次中相同版本的 Gradle 和依赖缓存，在独立输出目录构建；其余冻结失败保持原结果。

按[定向补编流程](../EXTENSIONS.md#首次全量候选的定向补编)执行 `prepare-baseline`，生成本地 revision `3c24b0d7c0a745a58de4bd6b5ffb7654`，父 revision 为 `702cc6bfb2974682bf1c83325458535a`。索引 SHA-256 为 `b819024786b18fa87be8f9f16b350cf4e70564268e592d28946866d24ccf11eb`。与冻结索引相比只有三个补编包的 buildId 变化，实际清单包含预期类型的五项 Source 设置规则；保留现网 xkcd、Arknights Comics、CuuTruyen。候选目录含 1,371 个可分发包，77 个失败只留在构建状态，所有可分发记录仍为 `compiled_unverified`、`runtimeReady=false`。

拉取候选到六材料归档的独立副本，以 `EXTENSION_ASSETS_DIR=<完整候选>` 运行正式 `pnpm build`，Vite 检查引用产物和传输摘要。输出的索引和构建状态与候选逐字节一致，Web 共享材料和 Native 内置运行时文件与合并预检归档逐字节一致。以实际生成配置运行 Wrangler `deploy --dry-run` 通过，读取 4,194 个静态文件；`check-base` 确认公开生产父状态仍匹配。原始日志和复验命令保存在本机忽略目录 `.local/prototype-full-six-material.tLNTHI/`。

#### 完整目录的 Android 阅读验收

用完整快照启动官方 Wrangler HTTPS、隔离 D1 和 Android 16 模拟器。首轮驱动未能在完整目录滚到 xkcd；改为用扩展管理的搜索后，D1 确认精确构建已安装、未收藏作品，但浏览页的 Source 控件排在 1,371 个目录条目之后。修复将当前 Source 和漫画结果放在目录之前，目录优先显示本账户已启用的扩展；用户打开扩展成功后回到浏览页顶部。目录语言筛选及包内语言筛选仍独立。

以修复后的正式 App 入口和全新 D1 复验：从完整索引搜索并安装原版 xkcd 1.6.1，打开英文 Source、读到真实热门与详情并收藏。独立进程进入 `3319: Elevators` 显示两张真实图片，保存第 2 页；再次启动从书架直接恢复第 2 页。主机独立读取书架和作品状态，续读前后原始响应逐字节一致（账户 revision 4），没有附带写入。本分项只覆盖隔离 Android 模拟器、该 Source 与该章节。故障、生产 Access、更多代表源和签名真机另验。

将浏览页修复并入六材料归档后，重新通过完整候选的 Web/Worker 构建和 Wrangler dry-run。Android arm64 APK 与 iOS arm64 `Runner.app` 均完成未签名构建，核对了生产地址和包内运行时文件。维护树的完整格式、Flutter 分析和测试通过。未签名包仅作构建验收，未用于真机安装。

未上传或切换生产。本机 Wrangler 管理登录仍不可用，未读到生产 D1 迁移账本。正式签名、物理设备、生产 Access 和完整代表源门继续按 P0 验收。

## LunarAnime 编译器诊断

2026-11-08，从固定 `952bbab` 全量的只读检查点复制 LunarAnime 1.6.6 工作目录和 Maven 本地仓库，独立运行同一 TeaVM 0.16.0 Maven 目标（`-o -e`）。上游 Gradle、原 JAR 和转换产物已有成功结果；AOT 首次失败的堆栈确认 `IndexOutOfBoundsException: 2/2` 来自 `StringConcatFactorySubstitutor.appendArgumentWithRecipe`。原版 Kotlin 代码使用 U+0001、U+0002 作分隔符，转换 JAR 中有两个动态实参夹一个静态常量的拼接配方。TeaVM 错把静态常量也算进动态实参索引，读取不存在的第三个参数。

仅在诊断副本中分开两种索引，并按常量本身类型选取追加方法。小型 Java 夹具的原版 TeaVM 再现同栈；隔离修正后 AOT 成功，Node 执行的四项断言输出与 JVM 逐字节相同，覆盖普通拼接、两个分隔符、静态常量与 String/int 混合。真实 LunarAnime 同一输入越过这个错误，但后续缺 Java EC/签名类和 Android Activity、WebView 方法，Maven 仍失败，无可发布 bundle。没有修改扩展、正式编译器、原始 Maven 缓存或正在运行的全量；该包保留失败。原始对照、补丁和日志在 `/private/tmp/karuyomi-lunaranime-concat.OHFZge/`。

## AsgardScans 的 Android JSON

固定 `952bbab` 全量记录中，AsgardScans 1.6.3 在调用 Android 的 `JSONObject`、`JSONArray` 时缺类；此路径用于从原站详情页的 JSON-LD 取简介、别名与分类。冻结原 JAR SHA-256 为 `c36be974cc8ad903885a1d4cb57466e0e6e90a390bd4ca61ddaf368f4a4025b6`。

在独立副本中，仅加入固定 Suwayomi `6b481e8` 的六份 AndroidCompat 实现，去掉 `JSONObject` 的 AndroidX 空值标注；同一锁定 Maven / TeaVM 0.16.0 离线重编成功，生成 4273929 B JS，SHA-256 `56c2812d2c10cbd05f2cdff76aba249f236c34f56c40c0f54a6039f7134b1815`。原 JAR 摘要未变。正式构建现在在生成目录做同样的准备，`pnpm teavm:check` 的 JVM 回归验证 JSON-LD、缺省、精确 Long 和无效输入；该初次 AOT 是独立诊断，并未发布、更新全量 checkpoint 或确认真实详情/图片。日志留在 `/private/tmp/karuyomi-asgard-json.VpCOGI/`。

随后固定 `975c650` 在独立 checkout 以同一原 JAR 通过正式 `prepareSources`、TeaVM、`node --check`、`verifyOutput`、候选静态装配和 `pnpm acceptance:build`。构建 ID 为 `ext-ar.asgardscans-be73a260e6247a66880ad39ddbf7367e-04bea62075812d18770a79c0690e44e427dcfb57f67529d2113b0a2b1d1f918d`；JS 4,280,375 B，gzip 880,539 B；静态快照 revision 为 `c752d4becbcf43249e06d0086d8e1e0a`。

隔离 workerd/D1 仅登记 `asgardscans.com`，bootstrap 200，实际提供的索引和清单与候选一致，gzip artifact HEAD 200。Codex 内置浏览器的新文档加载已安装扩展并列出 `AsgardScans · ar`（Source `1271101147092894805`）；选择后热门请求失败，未返回作品。用同一候选在正式 HTTP v2 入口独立重放原热门 URL `https://asgardscans.com/manga?page=1&sort=popular`，外层 200，META 内上游状态 404，513 B HTML 后正常 END/EOF。这不是原浏览器请求的抓包，也不能据此判断为何源站返回 404。没有真实 JSON-LD 详情、章节或图片证据。

复验入口、候选身份、服务和帧记录见 `/private/tmp/karuyomi-asgard-formal.Tqguie/` 下的 `reproduce.md`、`summary.json` 和 `popular-bridge-replay.json`。本轮未更新冻结 checkpoint、未部署，仍为 `compiled_unverified` / `runtimeReady=false`。

## Alpha Manga 的 Canvas 旋转

固定 `952bbab` 的全量记录中，Alpha Manga 1.6.3（英文 Source `370653027333714265`）因缺 `Canvas.rotate(float)` 在 AOT 失败。原 `ImageInterceptor` 对图块执行 save → translate → rotate → 可选 mirror → drawBitmap → restore。宿主按原 Canvas 的局部坐标合成旋转，保留原平移和 save/restore；复用现有 `setTransform` 图形桥，未修改原扩展或图片交付边界。

2026-11-08，固定 `aef05f7` 加本次旋转改动的独立 checkout：Android 35/Robolectric native Skia oracle 3/3 通过；同一像素场景由锁定 TeaVM 编译，经正式 Vite 图形材料与独立 Node Skia 后端运行，正负 90 度、镜像、restore 后七个像素位置精确一致，释放后六项资源计数为零。这不是浏览器或真实 Source 读图证据。

原 JAR SHA-256 `9d8867f5ab9f07827db575083e840a271a7c480c6022fd47455491127fed8556` 不变，正式 `prepareSources`、TeaVM AOT 与 `node --check` 通过；JS 4,410,962 B，SHA-256 `4ab1868a166cc2dc0a22d378a583103ca1859cdd28a19bc4611a62b22568ed17`。独立输入、复验命令和日志见 `/private/tmp/karuyomi-alpha-rotation.TgZ74e/reproduce.md`。当前冻结全量输入与 checkpoint 未改变，候选仍为 `compiled_unverified` / `runtimeReady=false`。线上应以免费章节验证经原拦截器处理的实际图片；仅有封面或元数据不足以证明旋转路径。

同一 JS 已通过单包完整性校验、候选装配及正式 `pnpm acceptance:build`；快照 revision `fbfb089bcd964a85bd431a6fba10891e`，gzip 904,200 B。隔离服务仅登记 `www.alpha-manga.com`，实际 index/manifest 与候选逐字节一致，artifact HEAD 和测试身份 bootstrap 均返回 200。独立 CLI 对公开章节 URL 收到 HTTP 202 与 `x-amzn-waf-action: challenge`，未获得 viewer 正文或图像域名。未放宽网络策略，未做浏览器图片验收或部署；精确身份与命令见同一证据目录下的 `acceptance/summary.json`、`acceptance/smoke.log` 与 `acceptance/acceptance-serve.sh`。

同一候选随后在隔离 `http://127.0.0.1:61630` 经正式 Codex 内置浏览器通过扩展安装、精确构建加载和英文 Source 列表。选择该源后显示「漫画源请求失败，请重试」，没有作品可打开。以同一候选独立通过正式 HTTP v2 桥重放原热门 URL（`/manga/search.json?query=&progress&genre&page=1`）：测试身份 bootstrap 200、外层 bridge 200、上游 META 为 CloudFront 202，带 `x-amzn-waf-action: challenge`，正文 0 B 后正常 END/EOF。该复验仅携明确的 JSON Accept 头，非浏览器原请求抓包；真实列表、章节和图片均未通过。服务正常停止；帧记录在同目录 `acceptance/popular-bridge-replay.json`。

## MangaTek 的气泡图形操作

固定 `952bbab` 的 MangaTek 1.6.13（阿拉伯语 Source `1011491016492324749`）缺少原气泡拦截器使用的绕中心旋转、矩形裁剪和描边斜接限制。原 JAR 的字节码有三个调用；虽然没有使用裁剪返回值，后续画笔仍受裁剪约束。原 Source 和 JAR 未改。

Android 35 native Skia 对照发现普通 Canvas 2D 旋转裁剪边缘有半透明像素，而 Android Bitmap Canvas 的矩形裁剪是硬边。修正后 Android 35 oracle 4/4，同一 Java fixture 经正式 TeaVM 和 Vite 图形桥、Node Skia 后端，也通过 45 度旋转、按调用时的矩阵裁剪、边缘像素、空/越界交集、保存恢复、描边及资源归零。额外扫描只在裁剪的位图范围内，合并相同跨度；共享图形材料 gzip 从 30,327 B 到 43,766 B，增量 13,439 B，每个 Web 快照只需一份。未测量目标设备的绘制耗时。

固定 `72a2f70` 加图形补丁的独立构建，以未修改的原 JAR（SHA-256 `5728f0c45e3b13e237c08ea8c62ed39dce5dcf444e95b45482b645a92eea3439`）通过 AOT、语法检查、单包静态装配和正式 `pnpm acceptance:build`。host 指纹为 `d9990e66a60fa830c943dcceb07a2fa5558e053d5f40f4b74d48bc3977fa496b`；JS 5,086,621 B，SHA-256 `b11da504d714e76859420c57f4cdd38f736e633878186dd4ea2d6a34af82e530`，gzip 983,806 B。正式隔离服务的静态索引、清单、产物 HEAD 与测试 bootstrap 均返回 200，索引与清单和候选逐字节相同。

2026-11-08，Codex 内置浏览器经 `http://127.0.0.1:49314` 安装并加载精确构建，识别原 MangaTek 阿拉伯语 Source。选择源后热门报错。独立 HTTP v2 重放其热门 URL `https://mangatek.com/manga-list?sort=views&page=1`，外层 200、上游 403 Cloudflare HTML、6050 B 后正常 END/EOF；这不是浏览器请求的抓包。当前只登记已确认的 `mangatek.com`、`api.mangatek.com`，没有访问真实章节或叠字页，仍为 `compiled_unverified` / `runtimeReady=false`。未部署或修改冻结批次，服务已退出。

像素对照入口为 `node tools/teavm/check-text-layout.ts`（需要锁定依赖）；冻结副本的命令、像素和材料记录见 `/private/tmp/karuyomi-mangatek-graphics.QY6mor/reproduce.md`，静态与 HTTP 证据在该目录的 `acceptance/`。

## MANGA Plus Creators 的图片 Referer 和续读

2026-11-08，固定 `5e403b1` 和未改的 MANGA Plus Creators 1.6.1 原 JAR（SHA-256 `bc385c175172b13ef8d65c2ba598f194a38dbab88aa99d8781c64c9a2424dc2a`），通过正式 TeaVM AOT、单包静态装配和 `pnpm acceptance:build`。英语 Source `4994699950662723787`，快照 revision `83fc244e7d7640c5b930c7c7f9884073`，JS 4,416,711 B、gzip 902,902 B；完整身份在本地候选清单。隔离官方 Vite/Wrangler 验收入口 `http://127.0.0.1:53740`，测试身份与 D1，网络只登记 `mangaplus-creators.jp` 和 `assets.mangaplus-creators.jp`。

正式 Codex 内置浏览器安装精确构建、初始化英语源、在热门列表打开并收藏 Sense Life，读取 18 个章节。反转原章节顺序后进入 `#001`，首图和第 2 页进度通过，按 End 跳至第 72 页并看到末图和保存确认；用「下一章」进入 `#002` 并实际显示首图，翻到第 2 页且确认保存。退出并关闭原文档，从新文档的服务端书架点「继续阅读」首次恢复 `#002` 第 2 页，实际画面可见。独立只读 API 确认两次采样的章节与 pageKey 相同、current/furthest 都为第 2 页、反向顺序保留。重新打开后的 account revision 10 → 11；没有把这次恢复写成无写入读回。

隔离 Node preload 仅在 Wrangler 把正式 workerd 的出站请求交给实际 fetch 时比较两章 CDN 图片请求的 Referer，原请求未修改。两章各有 6 个观测，全部与各自完整章节 URL 精确匹配，图片响应都是 200；日志只存章节别名、比对结果和状态。独立合成 Range 控制可区分缺失与匹配，两者均取得 206，因此这证明原 Source 的请求头被保留，不证明 CDN 强制需要它。

本轮只验收抽样页、跨章及 Web 新文档续读，没有逐页验收 107 页，也未验证其它作品/语言、Native 或生产。构建仍保持 `compiled_unverified` / `runtimeReady=false`，未修改冻结 AOT 或部署。启动步骤和精确构建见 `/private/tmp/karuyomi-mpc-5e403b1.7OHoGs/acceptance/handoff.md`，原始观测和独立 API 样本在同目录，服务及标签已关闭。

## MANGA Plus Creators 的 iOS 图片超时对照

2026-11-08，在固定产品 `9ef3ccb` 的独立副本使用 Flutter 官方 `integration_test`、iPhone 17 Pro / iOS 26.4 模拟器及官方回环 HTTPS Wrangler 服务。使用上一节同一 v6 候选，核对 Native host、worker 和材料清单逐字节相同；隔离 D1 只登记原 Source 两个域名。正式 `prepare` 安装英语 Source 并收藏 Sense Life，独立读回账户／作品 revision `2/1` 且无进度。

首轮从书架打开时，扩展 gzip 与 JS 已加载，详情或章节阶段的同源请求约 10 秒后取消；D1 快照不变。第二轮通过同一正式书架入口打开 `#001`，实际显示第 1、2 页的解码帧；第 3 页显示「图片未能加载」。独立读回只证明已保存到所选第 3 页，没有已观察的最远锚。独立诊断副本从该页重开，原界面和显式「重试」都再次报告 `RuntimeException(timeout)`，错误来自 HTTP transport；没有到达完整章或跨章验收。诊断只记录错误类型，未改图片处理和超时。

第 3 页的独立对照使用同一当前图片 URL 与精确章节 Referer，尝试读取完整响应至 EOF：

| 路径                                         | 实测结果                                                                                                                                                                    |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 从宿主直接请求 CDN                           | `200`，205,238 B，约 0.49 秒读完。                                                                                                                                          |
| 独立 Node 经同一官方 HTTPS 服务，10 秒帧预算 | 多次见到上游 `200` 后超时；一次在约 0.215 秒收到 META、读到 187,954 B / 46 块后，于约 10.009 秒收到远端 `timeout` ERROR 帧。同轮第 2、4 页读完；另一轮第 3 页也曾完整读完。 |
| 同一桥，独立帧请求使用 30 秒诊断预算         | `200`，205,238 B / 51 块，约 9.77 秒读完；正式 Source 的预算未调整。                                                                                                        |

另起同配置官方 harness，仅用 Node `diagnostics_channel` 观测入站正文，不读取或替换流，也不改 10 秒预算。同一第 3 页三次帧重放，两次约 1.66／8.68 秒完整结束，一次约 10.01 秒收到远端超时；失败时 Node 从 CDN 收到的 122,418 B / 30 块均已交付帧客户端，对应累计字节的到达差最大约 2 毫秒。绕过 Worker 的直接 Node 请求也有一次 9.93 秒完整结束、一次 10 秒只收到 167,474 B。4 KiB 块已出现在 Node 入站；本组慢样本主要等待上游正文，未发现 Worker 帧转发额外拖慢，也未到 WebKit 文件交付或 Flutter 解码。现有对照不足以区分 CDN、连接与本地网络的成因。

失败帧之后，本地 Wrangler 的 Node fetch 到约 17.89 秒才收完正文；这次本地 harness 未把取消及时传到出站连接，生产取消需独立验收。后续应核对 Source 的读取超时与宿主整体预算语义，再复验真实 Native 阅读；本轮未调整产品超时。模拟器、回环服务均已清理，未更新冻结 AOT 或部署。原始 UI 日志、GET 对照和驱动在 `/private/tmp/karuyomi-ios-mpc-9ef3ccb.FrFKke/`，逐块对照见 `/private/tmp/karuyomi-mpc-frame-diag.idt5I9/summary.json`。

## HTTP 读取空闲与总期限回归

2026-11-08，MANGA Plus Creators 的部分正文超时样本中，超过 10 秒的是整次调用，最大 DATA 间隔约 2.65 秒。修正 v2 桥：原 `timeoutMs` 用于源站响应头与按需正文的读取空闲，API 与本地 handle 各自保留独立 300 秒总限，现有上层 Source 操作预算仍可提前取消。没有修改 Java、扩展 JAR 或 wire 格式。

官方 Workers 测试用每隔约 100 毫秒返回的四个 DATA 验证 300 毫秒空闲预算，旧代码超时，修复后通过 END 与 EOF。Host 测试也复现旧绝对计时中断。定向回归另覆盖真正读空闲、空块不续期、慢消费、总限、上传后等响应头、取消与迟到响应。生成的 `materials.json` 与六份共享材料逐一核对 SHA-256，和冻结 `c04d436` 构建完全相同；正式 AOT 计算的 host fingerprint `d9990e66…` 也未变。Native worker 随宿主代码重建。正式 iOS 复验见下一节，生产仍待验证。

## MANGA Plus Creators 的 iOS 完整章节与续读

2026-11-08，以 `4e5ca90` 的产品副本加入与 `8ed8436` 相同的两份 HTTP 产品源码，用上一节相同的 v6 MANGA Plus Creators 1.6.1 英语 Source 和静态快照 `83fc244e7d7640c5b930c7c7f9884073`。Flutter 官方 `integration_test` 在 iPhone 17 Pro / iOS 26.4 模拟器运行正式主入口，连接官方回环 HTTPS Wrangler 服务，专用模拟器正常信任本轮 CA。索引、扩展清单和 gzip 与候选一致，两轮实际 App 包内 host、worker 和清单一致，六份共享材料与冻结构建 SHA-256 相同。

修复后首次从空 D1 准备正式书架，Sense Life `#001` 第 1–32 页逐页显示，包含此前失败的第 3 页；第 33 页 120 秒内未满足解码帧和当前页码的断言，本轮未完成首章。独立 GET 仅确认所选第 33 页、无最远锚、未完成、无第二章记录，账户／作品 revision 为 `17/16`。34 次出站 Referer 均精确匹配，33 次收到上游 `200` 响应头，一次 fetch 失败；日志未关联页码，不能据此归因。

失败后的独立帧重放仍使用原 10 秒读取空闲预算：第 3 页 1.542 秒读完；第 33 页三次都读到 EOF（221,752 B，0.104–0.106 秒）。这是后续请求，不能说明先前的 UI 失败原因。另一次诊断用新 iOS 进程从失败 D1 的服务端书架恢复 `#001` 第 33 页，点击「继续阅读」约 6.77 秒看到解码帧，无需点击「重试」；独立 GET 仍为同章同页，revision `17/16 → 18/17`。

第二轮用新 HTTPS 入口和全新 D1，恢复未经修改的验收驱动。进程 `81224` 逐页解码 `#001` 全部 72 页，显式确认完成，经「下一章」进入 `#002` 并逐页读到第 7 页；新进程 `86388` 从服务端书架首次显示 `#002` 第 7 页，章节键、页键与清单版本一致，再逐页读至第 35 页。独立 GET 核对反向章序、首章完成及其当前／最远第 72 页在两次读回间不变；次章当前／最远第 7 → 35 页，未显式完成。账户／作品 revision `2/1 → 18/17 → 23/22`，收藏、设置和书签业务字段保持。读与续读的测试体分别约 39 秒和 18 秒。两章分别观测到 72 和 37 次精确 Referer、上游响应头均为 `200`；次数含预取及重开，不作吞吐或延迟基准。

复验用原单包快照执行 `EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build:native`，按 [Native 官方 HTTPS 配置](../../apps/reader/integration_test/README.md#分类同步)仅登记原两域名并启动空 D1；依次执行 Flutter 驱动的 `prepare`、`manga-plus-read`、`manga-plus-resume`，两次阅读使用独立进程。命令、驱动副本、两轮日志与独立 GET 在 `/private/tmp/karuyomi-http-idle-8fd995e.021mnf/`，成功轮核验在 `attempt2/verified.json`。此门覆盖这部作品两章的 iOS 模拟器流程；未实测其它作品、Android、真机或生产 Access，未部署，包仍为 `compiled_unverified` / `runtimeReady=false`。两轮服务和专用设备均已清理。

## MANGA Plus Creators 的 Android 完整章节与续读

2026-11-10，固定正式产品 `68e5e08`，Pixel 7 / Android 16（API 36，WebView `133.0.6943.137`）模拟器，经官方 Wrangler `https://127.0.0.1:60562`、专用回环 CA、私有 ADB 和全新隔离 D1。采用同一 v6 运行材料及冻结 `c04d436` 的 MANGA Plus Creators 1.6.1 英语 Source `4994699950662723787`，单包快照 `f64ea58e2c9f4ab5b1db47c874a04f6e`。和 iOS 历史记录是同版本的不同 AOT 字节；未使用旧 Source 域名登记或绕过图片处理。

正式入口安装并收藏《Sense Life》，进程 `5170` 逐页显示 `#001` 的全部 72 页，显式确认读完，并通过「下一章」在 `#002` 确认保存第 7 页。进程 `5443` 从书架首次显示同一清单的第 7 页（实际解码 812 × 1275），再逐页读到第 35 页。独立正常 HTTPS 读回确认首章当前／最远第 72 页且完成，次章当前／最远第 7 → 35 页、未完成，反向章序保留，设置、收藏和书签的业务字段保持。账户／作品 revision `2/1 → 10/9 → 23/22`。

用 [通用 Native 驱动](../../apps/reader/integration_test/README.md#真实-source-完整章跨章和新进程续读)复验。固定输入、两个进程的逐帧结果、独立读回和机器核对保存在 `.local/manga-plus-android-68e5e08/`；首轮只解码第 1 页，因驱动误选 Tooltip 在翻页前停止，新 D1 复验时已修正。此门只覆盖该作品的 Android 模拟器功能，未测真机、性能、生产或其它 Source；AOT 产物仍为 `compiled_unverified`。

## ToonLook 的长图重排、完整章节与续读

2026-11-08，固定产品 `b64fc90` 与当前 v6 宿主材料，使用未修改的 ToonLook 1.6.2、英文 Source `8320348786843379620`。单包候选 revision `5f2dbba16f6947d284bd93f85311ff2f`；六份共享材料与当前构建逐字节相同。正式 API、runtime 和验收配置从固定提交构建；Web release 复用 `8705ee4` 的现有字节，先核对正式 Flutter 输入、锁和工具链完全相同。官方 HTTP harness 的测试身份连接独立 workerd/D1，仅登记 `toonlook.com`、`img.toonlook.com`。

Codex 内置浏览器通过正式 UI 安装并加载英文源，搜索和收藏 Doomed，反转章节顺序，从 `131-chapter-1?lang=en` 逐页显示全部 10 页。第 10 页服务端确认后显式点「读完本章」，独立 GET 核对当前与最远均为 10、`completed=true`。用正式「下一章」进入 `131-chapter-2?lang=en` 并显示全部 10 页；退出旧文档，从新文档的服务端书架继续阅读，首次打开第 2 章第 10 页。独立 GET 的两章进度、当前与最远锚、章序、书架资料逐字段相同；重开前后账户／作品 revision `34/32 → 37/35`，不将这次续读记为无写入，GET 也不能单独判定每次写入的操作类型。

临时验收 HTML 的观察器只读取正式 `acquireImage` 交付的 Blob；原 Source、正式 Flutter JS 与宿主未改。对两章各第 1、6、10 页比对独立参考：五个非恒等样本全部符合按原 Source 规则重排后的 500 px 条带顺序，原图直通负对照均失败；第 1 章第 10 页预期为恒等顺序，只核对几何与尾段。四个样本高度 5,000 px；观察器可能见到预取资源，其结果只作像素证据，逐页显示单独由正式阅读界面确认。额外解码使本轮不能作为性能测量。

复验用独立快照执行 `EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build`，通过 `ACCEPTANCE_SOURCE_POLICIES` 为 `eu.kanade.tachiyomi.extension.all.toonlook` 指定上述域名后运行 `pnpm acceptance:serve`。本轮运行参数、隔离候选与独立 D1 样本位于 `/private/tmp/karuyomi-toonlook-p0-b64fc90.41hfTc/`，独立参考及正负对照在 `/private/tmp/karuyomi-toonlook-8705ee4.AZ7u6I/acceptance/observe/`。此门只覆盖该作品两章的 Web 阅读；Native、物理设备、长图性能和生产另验。未部署或修改全量构建输入，仍为 `compiled_unverified` / `runtimeReady=false`。

## ToonLook 的 iOS 首图失败

2026-11-10，固定正式产品 `68e5e08` 与冻结 `c04d436` 的 ToonLook 1.6.2（英语 Source `8320348786843379620`，单包快照 `f978898a11704b4bbb2adb3b7f0e2a4f`）。iPhone 17 Pro / iOS 26.4 模拟器通过 Flutter 官方 `integration_test`、受信回环 HTTPS 与隔离 D1 启动。正式入口安装、搜索及收藏 Doomed，并打开 `131-chapter-1?lang=en`。阅读器获得 10 页清单并显示 `1 / 10`，第 1 页提示「当前平台尚未支持图片阅读」，120 秒内未显示解码帧。独立 D1 读回只确认第 1 页已选中；无最远进度，未完成。后续诊断驱动未通过重新开章，无法据此归因具体图形操作。

同日诊断复验使用同一快照、同一 iOS 模拟器和全新 HTTPS/D1。仅在独立产品副本的 Worker driver 和测试 UI 增加观察，六份共享材料及 AOT 未变。同一次首图请求中，`ImageDecoder` 缺失导致 `openDecoder` 抛错，但 Source 捕获后通过 `createImageBitmap` 静态解码，创建并绘制重排后的 Bitmap。`OffscreenCanvas.convertToBlob({type: 'image/webp'})` 对 720 × 5,000 surface 返回 `image/png`，桥按约定拒绝格式不匹配，原 Source 抛出 `java.io.IOException`（`Could not encode descrambled image`），尚未打开图片交付通道。driver 优先呈现了之前已回退的解码能力错误，因此界面提示不指向真正的失败步骤。独立 D1 再次确认只记录首图选中、无最远锚或完成状态（账户／作品 `3/2`）。

复验沿用[通用 Native 驱动](../../apps/reader/integration_test/README.md#真实-source-完整章跨章和新进程续读)。构建输入、诊断补丁、准备与阅读日志、独立读回和界面截图见 `.local/ios-toonlook-v6-68e5e0.t6QMCa/evidence/`。此门确认该 iOS WebView 缺少 Canvas WebP 编码路径，未验证其它 WebKit 版本、修复或真机；AOT 产物仍为 `compiled_unverified`。

## ToonLook 的 iOS WebP 编码探针

用官方 libwebp 1.6.0 和 Zig 0.17.0 构建独立单线程 encoder-only WASM。质量 90 的探针为 168,745 B（gzip 83,415 B），限制 3,600,000 像素、4 MiB 输出和 96 MiB 线性内存；一个 720 × 5,000 的合成 RGBA 输入编码为 1,000,214 B，WASM 线性内存容量高点 68.875 MiB，官方 `dwebp` 成功解码。超像素、输出空间不足、非法质量及越过内存上限有负对照。该内存只指 WASM 线性内存；Node 的单次编码结果不代表 Canvas、WebKit 或设备峰值。上游、命令、ABI、摘要和负对照见 `.local/libwebp-wasm-1.6.0.8SnXZg/REPRODUCE.md`。

在上节同一 iOS 模拟器、同一 ToonLook v6 AOT 和新的隔离 HTTPS/D1 中，仅在独立副本的 Worker 用该探针替换 Canvas 的错误格式输出：从已经由 Source 绘制完的 surface 读 RGBA，以原质量参数编码，校验 RIFF/WebP 签名，再经原图形桥和原图片交付。共享材料 catalog SHA-256 仍为 `eec7701e311b37ac3c03005a128d98b8f54f65d8a873c549ccf860f8fbb765ae`。真实《Doomed》首章 10 页逐页显示并显式确认完成，经「下一章」保存第二章第 7 页（720 × 5,000）；新进程从书架首次显示第 7 页并读到第 10 页。独立 HTTPS 读回确认首章保持完成，当前和最远均为第 10 页；第二章当前和最远从第 7 页到第 10 页，仍未完成，反向章序保留。账户／作品 revision `2/1 → 9/8 → 11/10`。诊断对照、探针补丁、复验参数、帧日志和机器核验见 `.local/ios-toonlook-v6-68e5e0.t6QMCa/evidence/`。

此门证明通用编码可恢复这一真实 Source 的阅读，不代表生产已经修复。探针的临时 Canvas 包装及内联 WASM 不进入产品；正式共享材料装配、图形账本、取消与释放、其它平台及真机仍待验收。未修改冻结输入或部署，产物仍为 `compiled_unverified`。

## 正式 WebP 编码材料与图形桥

2026-11-10，从固定 libwebp 1.6.0 提交 `4fa21912338357f89e4fd51cf2368325b59e9bd9` 和校验过的官方 Zig 0.17.0 在 macOS arm64 与 clab Linux x64 独立准备。相同的低内存编码配方和导入内存 ABI 生成 176,717 B，SHA-256 同为 `29e4972e12f6239d00e7832ed406108fc4d964d0d55ffeb2d1c2946836a57738`，摘要和长度已进入工具链锁。Linux 在冻结批次之外使用隔离目录、低优先级，未修改或重启在途 AOT。

同一正式 WASM 在 Node 24.15.0 用两种确定性 720 × 5,000 RGBA 输入、质量 90 运行：结构图输出 786,652 B，线性内存容量高点 45.875 MiB；高噪声图输出 3,017,796 B，线性内存容量高点 57.875 MiB。两份字节均通过 RIFF/WebP 签名校验；高噪声输出另经官方 `dwebp` 解码。容量测量不含 Canvas、JS、进程 RSS 或 GPU。图形桥分项用正式材料验证 Canvas 优先、能力探针、长图编码、输出租约和取消；Vite 材料测试检查 Web 静态路径、实际字节与 Native 内置集合一致。

复验先 `git submodule update --init --depth 1 vendor/libwebp`，运行 `pnpm webp:prepare`，再 `pnpm --filter @karuyomi/runtime-host build` 和 `pnpm exec vitest run packages/runtime-host/test/graphics-bridge.test.ts packages/runtime-host/test/materials.test.ts`。本轮是正式材料与桥的工程验收；原 Source 仍须用新材料身份重编后，在正式 iOS 包复验，不以早前隔离探针代替。新材料未部署。

固定 `a1dd0cd` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/42688888405) 已通过。clab 的独立 checkout 已准备锁定工具链与 ToonLook 单包计划；正式材料清单与 macOS 构建逐字节一致，七份资源均通过摘要和大小校验。macOS 独立验收目录已重建 Native 内置文件，host、worker 与清单均与该提交的正式构建字节相同。旧冻结 ToonLook 清单与新材料不匹配。clab 的冻结全量仍在运行；独立单包计划尚未执行，不能加入旧候选或用来声称正式 iOS 已通过。

## Arknights Comics 的 Android 完整章节与续读

2026-11-10，固定正式产品 `2c012db`、冻结 `c04d436` 的 Arknights Comics 1.6.2（英语 Source `5973713386239249589`，独立静态快照 `b1ab2d45307a4a2cbc51ccfcb38860d7`）。从冻结检查点正式组装，未重编原扩展。实际静态索引、清单、gzip 和 App 内置材料均经核对，与六份材料身份匹配。Pixel 7 / Android 16 API 36 模拟器使用正式 Flutter 入口、官方 Wrangler HTTPS / workerd / D1 及测试身份；回环 CA 仅用于隔离调试构建，保留证书与主机名检查。

从空书架经正式界面安装并收藏《Prelude Suite: The Lone Walker》。章节清单确认来源原序中《DREAM》的下一章是《HEARTBEAT》。阅读进程逐页显示《DREAM》51 页（实解码尺寸 1200 × 1691），显式标记完成后用「下一章」进入《HEARTBEAT》，显示并保存第 3 页。独立 Android 新进程从书架直接续读，首次显示《HEARTBEAT》第 3 页，无需经过详情。

独立 HTTPS 读回确认账户／作品 revision 为 `2/1 → 58/57 → 58/57`，重开前后的完整响应相同。《DREAM》的当前与最远页均为 51 且已完成，《HEARTBEAT》的当前与最远页均为 3、未完成，保留来源章序。复验使用[通用 Native 驱动](../../apps/reader/integration_test/README.md#真实-source-完整章跨章和新进程续读)，逐页日志和读回摘要见本机忽略目录 `.local/arknights-android-2c012db/evidence/`。本分项未部署产物，不改变静态快照的 `compiled_unverified` 状态；生产和真机另验。

## Arknights Comics 的 Android 与 iOS 模拟器接力

沿用上节同一隔离 HTTPS / D1、静态快照、产品与测试身份。iPhone 17 Pro / iOS 26.4 专用模拟器信任本轮证书，从正式书架首次续读到 Android 已确认的《HEARTBEAT》第 3 页，显示真实解码帧，再操作一次「下一页」，确认第 4 页。实际 iOS App 的 host、worker、清单与正式构建字节一致。随后独立 Android 进程从书架首次显示第 4 页，不再翻页。

独立 HTTPS 读回确认账户／作品 revision 为 `58/57 → 60/59 → 60/59`。《DREAM》第 51 页的完成状态和两份锚点全程相同；《HEARTBEAT》保留原清单和章序，当前与最远均为第 4 页、未完成。只读检查实际 D1 的三条回执：`58/57` 当前／最远为 `3/3`，`59/58` 为 `4/3`，`60/59` 为 `4/4`，且后两条的当前锚完全相同。两次提交分别确认用户导航和第 4 页真实解码后推进的最远位置；iOS 打开第 3 页没有附带提交。Android 回读前后各路原始响应正文逐字节一致。复验日志、快照与回执见 `.local/arknights-ios-handoff-2c012db.Gp8GbB/` 和上节 Android 证据目录。此分项覆盖同一作品的真实跨端续读，生产 Access、真机和其它 Source 另验。

## CuuTruyen 的 Native 完整章节与跨端续读

2026-11-10，从首发六材料归档（`2c012db` 加服务地址、登录回跳与两次阅读恢复修复）构建正式 Native 入口。用 `prepare-snapshot` 装配冻结 `c04d436` 的原 CuuTruyen 1.6.2（越南语 Source `8222087175453285202`），独立快照 revision 为 `de03c647bc85477f92f8d5d5145bd223`。实际 HTTPS 静态索引和清单与候选逐字节一致，清单引用的六份材料与正式宿主构建匹配。使用同一 Wrangler HTTPS／D1 和隔离测试身份，无故障夹具；Android 调试包和独立 iOS 模拟器仅为回环服务信任测试 CA，保留 TLS 校验。

Pixel 7 / Android 16 API 36 模拟器在正式界面搜索并收藏《Spy x Family (FULL HD)》，返回作品 `152`、`Chương 142`（`98727`）和来源原序下一章 `Chương 141`（`97844`）。从书架打开详情，逐页显示第 142 章全部 23 张原 Source 处理后的图片，显式标记完成；通过「下一章」进入第 141 章，核对 27 页清单并实际显示、保存第 3 页。iPhone 17 Pro / iOS 26.4 模拟器从同库书架直接续读第 3 页，翻到第 4 页并保存；Android 新进程直接从书架显示第 4 页。

独立 API 和实际 D1 回执确认账户／作品 revision 为 `2/1 → 8/7 → 9/8 → 9/8`。第 142 章的第 23 页完成标记及两份锚点保持不变；第 141 章未完成，当前和最远位置均由第 3 页推进到第 4 页。iOS 接力期间只新增一条进度回执，Android 读回前后的 API 原始正文和九条持久回执逐字节一致。

复验使用[通用 Native 阅读驱动](../../apps/reader/integration_test/README.md#真实-source-完整章跨章和新进程续读)。准备阶段在隔离副本传入越南语断言和实际完整标题，保留两次因驱动预期不匹配而停止的记录；最终从空 D1 开始。逐页尺寸、快照、回执与独立 `verify.ts` 见本机忽略目录 `.local/prototype-cuutruyen.vYTzzD/`。本分项未发布单包快照，不提升 `compiled_unverified`；第 141 章剩余页、生产 Access、真机和完整候选另验。
