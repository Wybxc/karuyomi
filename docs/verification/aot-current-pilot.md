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
