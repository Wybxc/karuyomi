# Native 服务端同步集成测试

`category_sync_test.dart` 和 `settings_sync_test.dart` 使用正式 `app.main()`、`NativePlatformRuntime` 和业务 repository 验证分类与全局设置；独立于 Source 阅读。`server_sync_test.dart` 保留原阅读驱动，其旧配套服务状态单独见下节。普通无设备 `flutter test` 不执行本目录；`flutter analyze` 与仓库格式检查仍覆盖它。

## 分类同步

在仓库根目录构建正式产品与官方 HTTPS harness：

```sh
pnpm acceptance:build:native
NODE_EXTRA_CA_CERTS=/absolute/path/rootCA.pem \
WRANGLER_HTTPS_KEY_PATH=/absolute/path/key.pem \
WRANGLER_HTTPS_CERT_PATH=/absolute/path/cert.pem \
ACCEPTANCE_FIXTURE=categories pnpm acceptance:serve
```

证书必须包含 harness 实际 loopback hostname（当前为 `127.0.0.1`），由本轮可丢弃设备正常信任。iOS 可使用 `xcrun simctl keychain UUID add-root-cert /absolute/path/rootCA.pem`。Android 使用隔离 debug 副本的精确主机 Network Security Config，仅加入本轮 CA，并保留系统 CA、证书/hostname 检查与明文禁用；release 不加入测试 CA。不要修改系统全局信任或接受证书错误。Android 通过 `adb -s SERIAL reverse tcp:PORT tcp:PORT` 访问官方实际端口，不制造不同 APP_ORIGIN 别名。

官方 `createTestHarness()` 应用正式 D1 迁移，以临时 RS256 测试身份运行正式 API；可选 `ACCEPTANCE_FIXTURE=categories` 在就绪前经同一 API 创建“分类同步·甲”“分类同步·乙”两部受控收藏，初始无分类。它们只用于业务元数据测试，不可进入 Source 阅读；默认未设置 fixture 时仍为空 D1。测试不注入假 PlatformRuntime、业务服务或 Source supplier。

在 `apps/reader` 执行以下模板，`APP_ORIGIN` 使用服务实际输出，依次运行 A `create` → B `update` → A `verify` → B `delete` → A `verify-deleted`；A/B 是独立客户端安装，每个命令启动新进程。阶段严格核对前置状态，不要在已提交后盲目重跑写阶段。

```sh
flutter test integration_test/category_sync_test.dart --no-pub \
  -d DEVICE_ID \
  --dart-define=APP_ORIGIN=https://127.0.0.1:PORT \
  --dart-define=CATEGORY_PHASE=create \
  --reporter expanded
```

五阶段分别验证创建并关联甲、第二端读回后改名并关联乙、第一端重启读回两关系、删除分类保留收藏、第一端重启确认两部未分类。实际操作经过分类 UI，并由 repository 正常 API 重新读取已确认快照；每个阶段有操作预算和最终运行时释放，输出 `CATEGORY_SYNC_RESULT` 和 binding `reportData`。Web 双会话使用单独 HTTP 模式入口，证据与 Native 分别记录；同一 HTTPS 的混合会话须另行取得正常浏览器信任和实测结果。

本入口只证明实际执行的平台组合和操作，不代表 Source、生产 Access、同时写竞争、网络故障、物理触控或真机性能。当前证据见[分类同步记录](../../../docs/verification/category-ui-sync.md)。完成后按 Enter 关闭 harness，停止测试进程并删除本轮专用设备。

## 全局设置同步

`settings_sync_test.dart` 复用上面的正式产品构建、官方 HTTPS harness 和设备信任配置；启动服务时不设置 `ACCEPTANCE_FIXTURE` 或 Source policies，使用空 D1 与零扩展索引。两个客户端必须使用同一个实际 HTTPS origin 和服务输出的 subject。Android 的隔离 debug 副本按上面的精确主机 CA 配置，并逐文件核对当前产品 Dart、驱动、锁文件与内置材料；不要复用历史副本的旧业务源码。

Android 的 WebView 与 Dart HTTP 客户端分别维护证书信任；上面的 Network Security Config 只配置 WebView。使用本地 CA 时，在该驱动的阶段配置中额外传入 `SETTINGS_TEST_CA_BASE64` 的标准 Base64 字符串（对本轮 PEM 文件的原始字节编码，不是文件路径）。驱动仅允许 Android 且已校验的 `https://127.0.0.1` origin，在 `app.main()` 前用 Dart 标准库解码后向当前测试进程的默认 `SecurityContext` 追加本轮 CA；保留既有根证书与主机名校验，不使用 `HttpOverrides` 或 `badCertificateCallback`，不改变产品 TLS。iOS 不传该字段，继续由专用模拟器正常信任证书。

每阶段先从该服务经正常 TLS 校验 GET `/api/settings`，使用 `Origin`、`X-App-Subject` 与 `X-App-Request: 1` 正常业务头，取得完整当前 `SettingsResponse`。将本阶段配置保存到忽略的本地 JSON 文件；`SETTINGS_EXPECT_JSON` 是完整响应经 JSON 编码后的字符串，不是手工填写 revision 或嵌套对象。配置包含：

| 字段                      | 内容                                                |
| ------------------------- | --------------------------------------------------- |
| `APP_ORIGIN`              | 官方 harness 的实际 HTTPS origin                    |
| `SETTINGS_SUBJECT`        | 本次服务已确认的 subject                            |
| `SETTINGS_PHASE`          | `verify`、`write` 或 `resume`                       |
| `SETTINGS_EXPECT_JSON`    | 本阶段完整当前 SettingsResponse 的 JSON 字符串      |
| `SETTINGS_PRESET`         | 写入与前台恢复阶段填写，取下述两个预设之一          |
| `SETTINGS_TEST_CA_BASE64` | 可选，仅 Android loopback 本地 CA 文件字节的 Base64 |

在 `apps/reader` 使用固定 SDK 运行：

```sh
flutter test integration_test/settings_sync_test.dart --no-pub \
  -d DEVICE_ID \
  --dart-define-from-file=/absolute/path/.local/settings-native/phase.json \
  --reporter expanded
```

依次运行 A `verify` → B `write`（`dark-rtl-double-width-crop`）→ A 新进程 `verify` → A 新进程 `write`（`light-webtoon-auto-height-no-crop`）→ B 新进程 `verify`。每阶段重新取得当前完整快照作为前置；保存成功后不要盲目重跑旧写阶段。正式表单修改主题、阅读模式、页组、适配和裁白，其它字段与列表保留。驱动验证草稿不提前应用主题、服务端确认后清除 pending，并输出完整 `SETTINGS_SYNC_RESULT`。

这组顺序操作证明实际执行平台间的全局设置读写与新进程恢复；漫画覆盖、同时写竞争、丢响应、自动前台、Web↔Native、生产 Access 和真机分别验收。全局默认 false/0 与 optional 漫画覆盖的 presence 语义不同，驱动按生成 getter 核对非 optional 值。实际结果与剩余门见[设置记录](../../../docs/verification/reader-settings.md)。完成后关闭 harness，移除本轮 reverse、测试安装与专用设备，结束测试进程。

另可用同一初始快照和预设验证自动前台重取：客户端 A 运行 `resume`，等到 `SETTINGS_RESUME_READY` 后用系统 Home 或 App 切换器将其送到后台，不结束进程。等 A 输出 `SETTINGS_RESUME_PAUSED` 后，在同一服务的独立客户端 B 运行 `write`，确认 account/global revision 各只增加 1。然后用系统界面回到 A 的原进程和设置页面，不点重读、不切换应用内导航、不重启。A 在暂停期间不 pump 或发起测试读取，等待实际系统事件至多 5 分钟；输出同 PID 的 `SETTINGS_RESUME_RESUMED` 后，先核对事件时的原快照，再等待正式客户端自动更新同一设置控制器、表单和实际应用主题。驱动在此期间不注入生命周期事件，也不主动重取设置。最后从独立客户端只读确认 revision 没有再次增加；记录实际平台、设备和事件。

## 章节书签同步

`bookmarks_sync_test.dart` 使用正式 `app.main()` → `NativePlatformRuntime` → 服务端真实 xkcd 书架点击 → `MangaDetailsPage` → `ChapterBookmarkButton`。复用下节的当前 Source 产物、网络政策与官方 HTTPS harness。它只在详情标记章节，不进入 Reader、不请求阅读页或图片；本轮书架不得有自定义封面。iOS 使用正常设备信任，不传测试 CA；Android 如需本地 CA，可按全局设置驱动相同的标准追加方式传 `BOOKMARKS_TEST_CA_BASE64`，仅允许 Android 的 `https://127.0.0.1`，保留系统根证书与 hostname 检查。

若新 HTTPS D1 没有可用的 Web 客户端，可先从 iOS 或 Android 运行 `prepare`。该阶段要求初始 account revision 为 0、书架与账户安装列表为空；从正式空书架进入浏览，在扩展管理准备并安装指定构建，选择精确英文 Source 并从热门打开目标作品，点击「加入书架」后通过只读 API 核对已确认状态。只进行安装和收藏这两次业务写入；不设置书签、不打开阅读器。准备失败后先检查实际 D1 状态，已提交的安装或收藏不得盲目重跑该阶段。

完成 `prepare` 或手动用正式 UI 安装并收藏目标 xkcd 后，确认 Source 资料稳定。开始 `verify`、`set` 或 `remove` 前，从同一服务和 subject 只读取得下列三份**同 account revision** 的完整响应：`GET /api/settings`、`GET /api/state/manga/:mangaKey`（不带 `chapterKey`）、`GET /api/state/manga/:mangaKey/bookmarks?revision=ACCOUNT_REVISION`。请求使用前述正常业务头。书签响应必须没有 `nextKey`，本轮最多 64 个书签；驱动另完整读取进度并限最多 64 项，不截断集合。Source 资料若在本阶段打开时改变，严格前置会失败；应在准备阶段稳定后重新 GET，不放宽零写断言或重跑旧写阶段。

将配置保存到忽略的本地 JSON 文件。`prepare` 不需要快照字段。其余阶段的三项 `EXPECT_*_JSON` 都是完整响应再经 JSON 编码的**字符串**，不是嵌套对象，也不只填 revision：

| 字段                                             | 内容                                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------------------- |
| `APP_ORIGIN`                                     | 官方 harness 实际 HTTPS origin                                                  |
| `BOOKMARKS_SUBJECT`                              | 本次服务已确认的 subject                                                        |
| `BOOKMARKS_PACKAGE_NAME` / `BOOKMARKS_SOURCE_ID` | 真实 xkcd package 和精确英文 Source ID                                          |
| `BOOKMARKS_MANGA_URL`                            | Source DTO 的精确作品 URL                                                       |
| `BOOKMARKS_CHAPTER_URL`                          | Source DTO 的精确章节 URL；必须在当前清单中唯一，不使用章节标签或浏览器地址替代 |
| `BOOKMARKS_BUILD_ID`                             | 仅 `prepare` 必填：当前默认静态目录的精确构建 ID                                |
| `BOOKMARKS_PHASE`                                | `prepare`、`verify`、`set` 或 `remove`                                          |
| `BOOKMARKS_EXPECT_SETTINGS_JSON`                 | 完整 `SettingsResponse`，不含漫画作用域                                         |
| `BOOKMARKS_EXPECT_STATE_JSON`                    | 完整 `MangaStateResponse`，含当前收藏与分类目录，不含分章 progress/bookmark     |
| `BOOKMARKS_EXPECT_BOOKMARKS_JSON`                | 完整、无 `nextKey` 的 `BookmarkPageResponse`                                    |
| `BOOKMARKS_TEST_CA_BASE64`                       | 可选，仅 Android loopback 本轮 CA 文件原始字节的标准 Base64                     |

在 `apps/reader` 使用固定 SDK：

```sh
flutter test integration_test/bookmarks_sync_test.dart --no-pub \
  -d DEVICE_ID \
  --dart-define-from-file=/absolute/path/.local/bookmarks-native/phase.json \
  --reporter expanded
```

建议先由 Web 正式 UI 添加目标书签，再运行 Native 新进程 `verify` → Native `remove` → Web 刷新读回；反向可运行 Native `set` → 独立客户端读回。只有 Native 时，可在同一个 HTTPS harness 上顺序运行 iOS `prepare` → iOS `set` → Android `verify` → Android `remove` → iOS `verify`；每个阶段使用新测试进程。每个书签阶段重新取得准确前置；`set` 要求目标原先不存在，`remove` 要求已存在。`verify` 打开书架与详情全程不允许业务 revision 推进；写阶段先确认完整前置集合，再点正式图标，等待 pending 清空、无错误及完整重读，严格要求 manga/account revision 各仅增加 1、只改变目标书签。全局与漫画设置、分类、收藏、资料、封面、resume 和所有已有章节进度必须不变。

驱动按正式 `ChapterSequence` 从唯一 exact URL 算稳定 key；移除阶段用正式「仅书签」筛选定位，其他阶段用章节名缩小列表；两种筛选均不承担身份。单操作预算 120 秒、主体总预算 10 分钟，finally 正式 unmount 并等待 Native disposal ACK，成功输出 `BOOKMARKS_SYNC_RESULT` 与 binding reportData。只有实际运行的平台组合可登记通过；驱动分析不证明 Native、跨端、故障恢复、生产 Access 或真机通过。结束后按上文清理 harness、reverse、测试进程及专用设备。

## Source 阅读与筛选验收

官方 harness 现在可以按显式主机列表注册当前静态快照中的真实 Source。先用固定提交构建与当前 ABI 匹配的候选快照，再运行正式构建：

```sh
EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build
ACCEPTANCE_SOURCE_POLICIES='[{"packageName":"eu.kanade.tachiyomi.extension.zh.komiic","allowedHosts":["komiic.com"]}]' \
  pnpm acceptance:serve
```

`ACCEPTANCE_SOURCE_POLICIES` 是本地验收配置，最多 16 包、每包 32 个明确 hostname，总输入不超过 32 KiB；不能填 URL、通配符或省略真实请求主机。入口从本轮官方 Static Assets 读取并验证索引、清单和资源权威关系，经正式 `registrationSql` 生成网络政策，写入隔离 D1。不存在于当前索引的包或无效政策会在输出就绪 URL 前失败；不更改生产 D1、公开资产或发布状态。无需伪造 Source supplier 或关闭正式网络检查。对额外图片域名、重定向域名仍须逐项确认后声明。

Native 使用 `pnpm acceptance:build:native`，并按上文证书和设备要求启动同一官方 HTTPS harness；同时设置 `ACCEPTANCE_SOURCE_POLICIES`。HTTP 模式用于内置浏览器，不作为 Native TLS 或生产 Access 的证据。以下 Source 驱动可复用该服务，但新的正式链路仍须实际执行各平台门，不能把配置就绪当成在线验收通过。旧自有服务已退役，历史记录保留原环境。

`server_sync_test.dart` 通过 Flutter 官方 `integration_test` 启动正式 `app.main()`，使用真正的 Native WebView、内置运行时材料、Source、阅读 UI 和业务 API。它不注入测试 PlatformRuntime、内存业务服务或图片 supplier。

### 前置条件

1. 准备与当前宿主 ABI 匹配的真实 xkcd 构建、Native 内置材料与正式 Web 构建，入口见仓库构建说明；只使用与当前 ABI 一致的产物，旧 v4/v5 构建不可混入 v6 验收。
2. 按上文配置 xkcd 的实际网络政策，启动官方 HTTPS harness。Web 与 Native 使用同一实际 origin、测试身份与隔离 D1。原[Source 测试服务](../../api/test/source-metadata-probe.md)只保留历史说明；本地签名身份不证明生产 Access/Cookie 行为。
3. Native 必须正常信任 HTTPS 证书。建议创建可丢弃模拟器，只向该设备添加本轮测试 CA；不修改产品 TLS、Mac 全局信任或已有设备信任，不接受证书错误。
4. 从内置浏览器的正式 UI 收藏英文 xkcd。初次运行测试前保留第 1 页进度或尚无进度；测试从服务端书架进入该作品。

在 `apps/reader` 使用固定 Flutter SDK 执行：

```sh
flutter test integration_test/server_sync_test.dart \
  -d IOS_SIMULATOR_UUID \
  --dart-define=APP_ORIGIN=https://127.0.0.1:PORT \
  '--dart-define=SYNC_CHAPTER_LABEL=3319: Elevators' \
  --dart-define=SYNC_START_PAGE=1 \
  --dart-define=SYNC_TARGET_PAGE=2 \
  --reporter expanded
```

测试等待真实图片 frame，使用正式上一页/下一页按钮导航，等待服务端已保存，再读取同一业务 API 核对 current/furthest。它输出 `SYNC_RESULT` 与 integration binding reportData，包含作品、章节、清单和已确认锚点，不输出 Cookie 或凭据。返回详情并等待章节入口恢复后，再关闭运行时，确保资源清理 ACK 已完成。

Native 成功保存后，在内置浏览器刷新并从书架继续阅读，核对恢复位置；反向验收时先从 Web 保存非默认位置（例如第 2 页），再使用全新 Native 安装和 `SYNC_START_PAGE=2` / `SYNC_TARGET_PAGE=1` 运行测试，排除默认首页掩盖恢复错误。回看后最远进度仍须不低于起始页和目标页。普通无设备 `flutter test` 不执行本目录；`flutter analyze` 与仓库格式检查仍覆盖它。

只有实际成功的测试才能登记平台门。测试驱动的模拟器 UI、生产 Access、物理触控和真机性能分别记录；结束后停止测试服务、关闭并删除本轮可丢弃设备，保留忽略目录中的必要报告。
