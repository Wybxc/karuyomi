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

Android 的 Dart HTTP 客户端与 WebView 分别维护证书信任。使用本地 CA 时，在 Android 分类阶段的 `--dart-define-from-file` 配置中加入 `CATEGORY_TEST_CA_BASE64`（本轮根 CA PEM 原始字节的标准 Base64）。驱动只在 Android 的 `https://127.0.0.1` 验收进程向默认 `SecurityContext` 追加该 CA，保留既有根和主机名检查；iOS 不传此项。系统 WebView 仍需前述隔离 debug 配置。

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

### 跨端重排后删除

新建同一 HTTPS fixture。通过正常 TLS 与 `Origin`、`X-App-Subject`、`X-App-Request: 1` 读取 `/api/library`，初始有两部收藏、空目录。使用 [ProtoJSON 业务协议](../../../protocol/karuyomi/v1/business.proto)按以下顺序预置数据；每个 POST 都使用不同的 mutation UUID，核对 200 与返回 revision：

1. 向 `/api/categories/mutations` 提交两个 `createCategory`，各用新的分类 UUID，依次创建「工作日」「周末」，目录预期 revision 分别为 0 和 1。
2. 向 `/api/state/mutations` 各提交一个 `setCategories`，以书架返回的 `mangaKey` 关联甲至「工作日」、乙至「周末」。两部作品预期 revision 均为 1，`expectedCatalogRevision` 均为 2。

按上面的设备命令运行 Android `reorder` → iOS `delete-reordered` → Android 新进程 `verify-reordered-deleted`。三阶段分别上移「周末」、按新顺序读回后删除「周末」、只读验证「工作日」及未分类筛选；测试仍操作正式 UI。预置后及每阶段分别独立 GET `/api/categories`、`/api/library` 和两部 `/api/state/manga/{mangaKey}`。账户／目录／甲／乙 revision 应依次为 `6/2/2/2`、`7/3/2/2`、`8/4/2/3`、`8/4/2/3`。重排只改变目录顺序；删除仅移除乙的关联，两部收藏保留。若写后驱动失败，先检查权威状态；已提交的写阶段只在新 D1 重跑。

## 全局设置同步

`settings_sync_test.dart` 复用上面的正式产品构建、官方 HTTPS harness 和设备信任配置；普通顺序和前台恢复阶段不设置 `ACCEPTANCE_FIXTURE`，丢确认阶段使用下方专用夹具；全局设置阶段均不设置 Source 策略，使用空 D1 与零扩展索引。两个客户端必须使用同一个实际 HTTPS origin 和服务输出的 subject。Android 的隔离 debug 副本按上面的精确主机 CA 配置，并逐文件核对当前产品 Dart、驱动、锁文件与内置材料；不要复用历史副本的旧业务源码。

Android 的 WebView 与 Dart HTTP 客户端分别维护证书信任；上面的 Network Security Config 只配置 WebView。使用本地 CA 时，在该驱动的阶段配置中额外传入 `SETTINGS_TEST_CA_BASE64` 的标准 Base64 字符串（对本轮 PEM 文件的原始字节编码，不是文件路径）。驱动仅允许 Android 且已校验的 `https://127.0.0.1` origin，在 `app.main()` 前用 Dart 标准库解码后向当前测试进程的默认 `SecurityContext` 追加本轮 CA；保留既有根证书与主机名校验，不使用 `HttpOverrides` 或 `badCertificateCallback`，不改变产品 TLS。iOS 不传该字段，继续由专用模拟器正常信任证书。

每阶段先从该服务经正常 TLS 校验 GET `/api/settings`，使用 `Origin`、`X-App-Subject` 与 `X-App-Request: 1` 正常业务头，取得完整当前 `SettingsResponse`。将本阶段配置保存到忽略的本地 JSON 文件；`SETTINGS_EXPECT_JSON` 是完整响应经 JSON 编码后的字符串，不是手工填写 revision 或嵌套对象。配置包含：

| 字段                      | 内容                                                |
| ------------------------- | --------------------------------------------------- |
| `APP_ORIGIN`              | 官方 harness 的实际 HTTPS origin                    |
| `SETTINGS_SUBJECT`        | 本次服务已确认的 subject                            |
| `SETTINGS_PHASE`          | `verify`、`write`、`resume` 或 `ack-loss`           |
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

这组顺序操作证明实际执行平台间的全局设置读写与新进程恢复；单作品覆盖见[独立驱动](#单作品阅读设置同步)，同时写竞争、丢响应、自动前台、Web↔Native、生产 Access 和真机分别验收。全局默认 false/0 与 optional 漫画覆盖的 presence 语义不同，驱动按生成 getter 核对非 optional 值。实际结果与剩余门见[设置记录](../../../docs/verification/reader-settings.md)。完成后关闭 harness，移除本轮 reverse、测试安装与专用设备，结束测试进程。

另可用同一初始快照和预设验证自动前台重取：客户端 A 运行 `resume`，等到 `SETTINGS_RESUME_READY` 后用系统 Home 或 App 切换器将其送到后台，不结束进程。等 A 输出 `SETTINGS_RESUME_PAUSED` 后，在同一服务的独立客户端 B 运行 `write`，确认 account/global revision 各只增加 1。然后用系统界面回到 A 的原进程和设置页面，不点重读、不切换应用内导航、不重启。A 在暂停期间不 pump 或发起测试读取，等待实际系统事件至多 5 分钟；输出同 PID 的 `SETTINGS_RESUME_RESUMED` 后，先核对事件时的原快照，再等待正式客户端自动更新同一设置控制器、表单和实际应用主题。驱动在此期间不注入生命周期事件，也不主动重取设置。最后从独立客户端只读确认 revision 没有再次增加；记录实际平台、设备和事件。

### 全局设置已提交后丢确认

为每端分别启动新的官方 HTTPS harness，设置 `ACCEPTANCE_FIXTURE=settings-ack-loss`。从另一个主机进程以正常 TLS 和本节的业务头读取 `/api/settings` 与 `/api/library`，要求空书架、系统主题、账户和全局设置 revision `0/0`。阶段 JSON 使用服务的 `APP_ORIGIN`、`SETTINGS_SUBJECT=acceptance-owner`、完整 `SETTINGS_EXPECT_JSON` 和 `SETTINGS_PHASE=ack-loss`，不传 `SETTINGS_PRESET`。Android 继续使用精确主机 debug CA 配置、`SETTINGS_TEST_CA_BASE64` 与实际端口的 `adb reverse`。

用上方命令运行正式设置驱动。它只将主题改为深色，验证首次丢确认保留原草稿；在同一进程以独立 HTTPS 连接核对已提交的深色 `1/1`；用正式「重新读取设置」应用主题但保留原待确认操作，再点「重试原设置操作」才清除提示，版本仍为 `1/1`。另一个主机进程重取设置与书架，仅允许主题和 revision 改变。按 Enter 停服，核对 `ACCEPTANCE_SETTINGS_ACK_AUDIT` 恰好两条、`sequence=1/2`、`drop_ack=1/0`、预期 revision 均为 0、确认 revision 均为 `1/1`，同一 mutation UUID 及正文、确认和持久回执的 SHA-256 全同。已提交的写阶段须用新 D1 才能重跑。实际结果与边界见 [Native 丢确认记录](../../../docs/verification/native-settings-ack.md)。

## 章节书签同步

`bookmarks_sync_test.dart` 使用正式 `app.main()` → `NativePlatformRuntime` → 服务端真实 xkcd 书架点击 → `MangaDetailsPage` → `ChapterBookmarkButton`。复用下节的当前 Source 产物与官方 HTTPS harness。它只在详情标记章节，不进入 Reader、不请求阅读页或图片；本轮书架不得有自定义封面。iOS 使用正常设备信任，不传测试 CA；Android 如需本地 CA，可按全局设置驱动相同的标准追加方式传 `BOOKMARKS_TEST_CA_BASE64`，仅允许 Android 的 `https://127.0.0.1`，保留系统根证书与 hostname 检查。

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

## 章节范围已读与未读

`chapter_read_sync_test.dart` 复用上文真实 xkcd 静态快照、官方 HTTPS harness 和设备证书配置。使用新的空 D1，不设故障夹具；先在 iOS 跑书签驱动的 `prepare`，安装精确 xkcd 构建并收藏英文 Source `1538249443376436084` 的 `SINGLE`。确认 account / manga / global revision 为 2 / 1 / 1，书架只有该作品，进度、书签和续读为空。

用同一实际 HTTPS origin 和 subject 分别运行 iOS `read` → Android `unread` → 新 iOS 进程 `verify`：

```sh
flutter test integration_test/chapter_read_sync_test.dart --no-pub \
  -d DEVICE_ID --dart-define-from-file=/absolute/path/phase.json \
  --reporter expanded
```

每份 JSON 提供 `APP_ORIGIN`、`CHAPTER_READ_SUBJECT`、`CHAPTER_READ_BUILD_ID` 和对应的 `CHAPTER_READ_PHASE`。使用本地 CA 的 Android 阶段另传根 CA PEM 原始字节的 Base64（`CHAPTER_READ_TEST_CA_BASE64`）；WebView 仍需隔离 debug 网络配置和同端口 `adb reverse`。iOS 只用设备自身信任，不传 CA 参数。

两次写入都经正式书架与详情，以来源顺序中的相反方向选中精确 URL `/3317/`、`/3318/`、`/3319/` 的闭区间，核对确认清单和 3/3 回执。Android 写入前先在已读筛选中看到这三章；iOS 重启后同一筛选显示 0 章，不写入。每阶段从 API 核对全局与漫画设置、作品快照、书签、完整分章进度和相邻负对照 `/3316/`。可用独立 HTTPS 客户端采集同 revision 的 `GET /api/settings`、`GET /api/settings/manga/KEY`、`GET /api/library?revision=REV`、`GET /api/state/manga/KEY`、其 `/bookmarks?revision=REV`、`/progress?revision=REV` 和四个 `?chapterKey=CHAPTER_KEY` 响应逐字段比对。预期 revision 2/1/1 → 5/4/1 → 8/7/1 → 8/7/1，只改变三章的 epoch 与完成状态，无页码锚或 resume。每个成功阶段输出 `CHAPTER_READ_SYNC_RESULT`；任一失败先核对实际提交状态，勿盲重跑写阶段。结束后关闭 harness、reverse 和专用设备。

## 单作品阅读设置同步

`manga_settings_sync_test.dart` 使用正式 Native Reader 与同一官方 HTTPS harness。用下节方式构建与当前宿主材料匹配的 xkcd v6 快照。使用新隔离 D1、`acceptance-owner` 和实际回环 HTTPS origin，关闭故障夹具。按上文书签驱动的 `prepare` 安装精确构建，收藏英文 Source `1538249443376436084` 的 `SINGLE`；保持默认全局阅读设置。

另用正式 `POST /api/state/mutations` 添加一个仅用于独立读回的对照收藏。使用相同业务请求头及 JSON 正文：`schemaVersion` 取当前 `businessSchemaVersion`，`mutationId` 为新 UUID，`expectedRevision: 0`，`setFavorite.favorite: true`，`setFavorite.metadata` 含与 xkcd 不同的 `packageName`、`sourceId`、`sourceName`、`sourceLang`，以及 `manga.url/title`。按正式规则计算 `mangaKey`：`SHA256(UTF8(JSON.stringify([packageName, sourceId, mangaUrl])))`。核对回执中的 key 与收藏状态；对照作品不进入 Reader。书架应只有这两部作品，均无自定义封面。

在 `apps/reader` 用固定 SDK 运行，各阶段启动独立进程：

```sh
flutter test integration_test/manga_settings_sync_test.dart --no-pub \
  -d DEVICE_ID --dart-define-from-file=/absolute/path/phase.json \
  --reporter expanded
```

阶段 JSON 提供 `APP_ORIGIN`、`MANGA_SETTINGS_PHASE`、`MANGA_SETTINGS_BUILD_ID`、`MANGA_SETTINGS_CONTROL_KEY`（对照作品 key）。先运行 iOS `prime`：打开 `/3319/` 并确认真实图片解码，到第 2 页并确认最远进度，再回第 1 页并确认保存。用独立 HTTPS GET `/api/settings` 的实际账户 revision 作为其余三阶段共同的 `MANGA_SETTINGS_BASE_ACCOUNT`。Android 使用本地 CA 时传 `MANGA_SETTINGS_TEST_CA_BASE64`，并按上文配置隔离 debug WebView 信任和 `adb reverse`；iOS 只用设备信任。

依次运行 iOS `set` → Android `clear` → iOS 新进程 `verify`。iOS 在正式 Reader 表单保存从右到左、单页、裁白显式关闭；Android 先核对已确认的覆盖及 Reader 配置，再逐项选择跟随全局；iOS 新进程确认三项均继承、Reader 恢复从左到右与自动页组。每阶段输出 `MANGA_SETTINGS_SYNC_RESULT`。独立 HTTPS 客户端对照 `/api/settings`、`/api/library?revision=REV`、两部作品的 `/api/settings/manga/KEY`、`/api/state/manga/KEY` 及其 `/progress?revision=REV`、`/bookmarks?revision=REV`，另查目标章 `/api/state/manga/KEY?chapterKey=CHAPTER_KEY`。两次保存各只推进一个账户与目标作品设置 revision，开章、退出和新进程读回不推进 revision；全局、作品业务状态及已确认进度须保持一致。失败后先核对 D1，勿盲重跑保存。结束后按上文清理。实际通过范围见[单作品设置记录](../../../docs/verification/reader-settings.md#ios-与-android-模拟器单作品设置覆盖)。

## Source 阅读与筛选验收

先用固定提交构建与当前 ABI 匹配的候选快照，再运行正式构建。中继不需要指定扩展域名：

```sh
EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build
pnpm acceptance:serve
```

Native 使用 `pnpm acceptance:build:native`，按上文证书和设备要求启动同一官方 HTTPS harness。HTTP 模式用于内置浏览器，不作为 Native TLS 或生产 Access 的证据。以下驱动复用该服务；配置就绪不表示在线验收通过。

`server_sync_test.dart` 通过 Flutter 官方 `integration_test` 启动正式 `app.main()`，使用真正的 Native WebView、内置运行时材料、Source、阅读 UI 和业务 API。它不注入测试 PlatformRuntime、内存业务服务或图片 supplier。

### 前置条件

1. 准备与当前宿主 ABI 匹配的真实 xkcd 构建、Native 内置材料与正式 Web 构建，入口见仓库构建说明；只使用与当前 ABI 一致的产物，旧 v4/v5 构建不可混入 v6 验收。
2. 启动官方 HTTPS harness。Web 与 Native 使用同一实际 origin、测试身份与隔离 D1。原[Source 测试服务](../../api/test/source-metadata-probe.md)只保留历史说明；本地签名身份不证明生产 Access/Cookie 行为。
3. Native 必须正常信任 HTTPS 证书。建议创建可丢弃模拟器，只向该设备添加本轮测试 CA；不修改产品 TLS、Mac 全局信任或已有设备信任，不接受证书错误。
4. 使用上文书签驱动的 `prepare` 阶段，或在能够正常信任同一 HTTPS origin 的内置浏览器中，经正式 UI 安装并收藏英文 xkcd。初次运行前保留第 1 页进度或尚无进度；测试从服务端书架进入该作品。

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

### 书架直接续读

用同一隔离 HTTPS / D1 和固定英文 xkcd `3319: Elevators`。先按上文准备，并在 iOS 用默认详情入口保存第 2 页。Android 新进程在相同配置下增加 `SYNC_ENTRY=shelf`、`SYNC_SUBJECT`、精确 `SYNC_BUILD_ID` 和原 `SYNC_EXPECT_EPOCH`，以 `SYNC_START_PAGE=2` / `SYNC_TARGET_PAGE=1` 运行 `server_sync_test.dart`。随后新 iOS 进程用同一书架模式设为 `1` / `1`。设备使用自动单页或已确认单页，Android 使用上文测试 CA 方式。

每个阶段从独立进程读 `/api/state/manga/:mangaKey?chapterKey=CHAPTER_KEY`。Android 打开后不写入，回看只推进账户/作品 revision 各一次，最远仍第 2 页；iOS 打开、退出不改权威状态。两次正式书架入口均须解码真实图像并等待章节资源释放。已有详情、前台与故障驱动仍使用原入口。

### 阅读中的前台 epoch 冲突

同一 HTTPS / D1 上使用两个独立的 Native 安装。用书签驱动 `prepare` 安装并收藏固定 AOT 快照中的英文 xkcd，保留空进度。验收 `SINGLE` 的 `/3319/`（`3319: Elevators`，实际两页）。两个阶段都用同一实际 origin、subject、精确构建 ID 和原 epoch（新 D1 为 0），并使用手机上的自动单页或事先确认的单页；阶段中不改变阅读设置。

| 参数                                                               | A 持续阅读                           | B 正式重置 |
| ------------------------------------------------------------------ | ------------------------------------ | ---------- |
| `SYNC_PHASE`                                                       | `resume`                             | `reset`    |
| `SYNC_START_PAGE` / `SYNC_TARGET_PAGE`                             | `1` / `2`                            | `2` / `1`  |
| `APP_ORIGIN`、`SYNC_SUBJECT`、`SYNC_BUILD_ID`、`SYNC_EXPECT_EPOCH` | 由本轮实际服务、账户安装及原进度确定 | 与 A 相同  |

按上面的 `flutter test` 命令，在两个设备上使用各自的 `--dart-define-from-file`。Android 如需本地 CA，另传 `SYNC_TEST_CA_BASE64`：仅允许正式校验过的 Android `https://127.0.0.1` origin，传本轮根 CA 文件原始字节的标准 Base64；与全局设置驱动一样，WebView 仅由隔离 debug 包配置信任，Dart 测试进程追加 CA，保留系统根、证书及 hostname 检查。iOS 不传该参数。

1. A 打开真实第 1 页、翻到第 2 页并确认已保存。等待 `SYNC_RESUME_READY`，通过系统 Home 或切换应用送 A 入后台。记录真实 `SYNC_RESUME_PAUSED` 与原 PID；不关闭或重启 A。
2. A 暂停期间启动 B。B 从服务端恢复第 2 页，等待正常打开章节的保存确认，再点正式「重新阅读本章」。B 必须显示第 1 页真实图像，并确认 epoch 增加 1。B 退出并等待资源释放后，从独立进程 GET 取得权威快照；这时才恢复 A 的同一进程和阅读路由。
3. A 不手动刷新。等待 `SYNC_RESUME_RESUMED`、`SYNC_RESUME_CONFLICT` 与 UI 的 epoch 重置提示，检查旧第 2 页仍有解码图像，「重新阅读本章」「读完本章」禁用。驱动在原阅读叶实际翻到第 1 页再回第 2 页；`SYNC_RESUME_STALE_VIEW` 后跨 3 秒保存观察窗，正式只读 inspect 结果必须与远端快照完全一致。需要外部独立快照时，在恢复 A 前启动采样器监听该 marker，及时读取，无需在 UI 中加刷新或等待控件。
4. 驱动随后点正式「重新打开本章」，核对旧资源的清理 ACK、新阅读叶的真实第 1 页及新 epoch，报告 `SYNC_RESUME_REOPENED`。退出后独立读取最终状态。显式打开或重开可以保存导航，reset 后首图也可能保存已观察位置；不要将全程 revision 固定为只增加 1 或要求最远锚始终为空。

各节点独立 GET `/api/settings`、`/api/library` 与 `/api/state/manga/:mangaKey?chapterKey=CHAPTER_KEY`；如需比对无关进度和书签，补同作品的完整分页查询。使用上文正式请求头与 TLS 校验。用驱动的作品、章节、清单及构建身份核对 exact 目标，保留 B 重置后、A 旧叶翻页和显式重开后的 D1 证据。旧叶窗口 revision 和锚点不变说明没有覆盖 D1；仅靠 GET 不断言没有发送任何网络请求。报告、独立快照和实际系统前后台证据放在忽略目录。

只有实际成功的测试才能登记平台门。测试驱动的模拟器 UI、生产 Access、物理触控和真机性能分别记录；结束后停止测试服务、关闭并删除本轮可丢弃设备，保留忽略目录中的必要报告。

### 已加载阅读在 Android 断连后重试

使用上述正式 HTTPS harness 和同一套 xkcd 静态资产、设备 CA 与精确 subject。用独立 iOS 的书签驱动 `prepare` 安装英文 xkcd 并收藏，保留空进度。Android 用专用、可抛弃的 API 36 Google APIs 测试模拟器；用 `adb -s "$device_a" reverse "tcp:$port" "tcp:$port"` 接入同一 origin。先确认该模拟器的 debug 包只对 `127.0.0.1` 追加本轮测试 CA、禁用明文，Dart 驱动用 `SYNC_TEST_CA_BASE64`；不改系统全局信任。

1. 在 A 运行 `server_sync_test.dart`，通过 `--dart-define-from-file` 提供 `SYNC_PHASE=offline`、`SYNC_START_PAGE=1`、`SYNC_TARGET_PAGE=2`、`SYNC_EXPECT_EPOCH=0`、实际 `APP_ORIGIN`、`SYNC_SUBJECT`、`SYNC_BUILD_ID` 和 `SYNC_TEST_CA_BASE64`。新 D1 以外须改用独立读回的实际 epoch。驱动先在线解码两页，返回已确认第 1 页；等 `SYNC_OFFLINE_READY`，记录 PID 并用另一个正常 TLS 进程取得六路 GET 基准。
2. 只在这台专用模拟器阻断该 origin 的精确端口，保留 ADB reverse 与测试控制通道。可在验收协调脚本中使用下列规则；预先设置退出清理，并在脚本正常或异常结束时精确删除同一条规则，不改宿主防火墙，不对普通设备执行。仅删除 ADB reverse 不能排除复用已有 HTTPS 连接。

   ```sh
   adb -s "$device_a" shell su 0 iptables -I OUTPUT 1 -o lo -d 127.0.0.1/32 \
     -p tcp --dport "$port" -j REJECT --reject-with tcp-reset
   # 等待 SYNC_OFFLINE_PENDING，先完成六路独立 GET 对照，再执行删除。
   adb -s "$device_a" shell su 0 iptables -D OUTPUT -o lo -d 127.0.0.1/32 \
     -p tcp --dport "$port" -j REJECT --reject-with tcp-reset
   ```

3. 看到 `SYNC_OFFLINE_PENDING` 时，驱动已在同一阅读页显示真实第 2 页，且待保存提示与「重试保存」有效。恢复前从独立进程确认六路完整响应与基准相同，并核对规则命中和原 PID。撤销规则后，驱动先确认草稿仍未保存，再点正式重试；等待 `SYNC_OFFLINE_RETRY_CONFIRMED`、测试成功退出及独立 D1 读回。当前页应变为第 2 页，epoch 不变，设置、书签及其它业务字段不变。不要把 revision 当作请求计数。
4. 可另在 iOS 正式重开同一章验证续读。使用 `navigate`、`SYNC_START_PAGE=2`、`SYNC_TARGET_PAGE=1`、同一已知 `SYNC_BUILD_ID` 和原 epoch，不传 Android CA 输入；第 2 页须先出现真实解码帧，第 1 页回看是单独的正常进度写。停止服务并删除本轮设备；详细日志保存在忽略目录。

这项验收只覆盖到该 HTTPS 服务的实际断连和会话内显式保存重试；不模拟已提交后 ACK 丢失，不证明请求 UUID、关闭后草稿恢复或全设备无网。

### 阅读进度已提交后丢确认

启动上述正式 HTTPS harness 时指定 `ACCEPTANCE_FIXTURE=progress-ack-loss`，保留当前 xkcd 构建。使用独立空 D1，先用书签驱动 `prepare` 从正式 UI 安装并收藏英文 xkcd。该夹具只中断 `SINGLE` 的 `/3319/` 末页显式完成的首个成功响应，普通页码保存不消耗故障。

用 `server_sync_test.dart` 的 `--dart-define-from-file` 传 `SYNC_PHASE=ack-loss`、`SYNC_SUBJECT=acceptance-owner`、精确 `SYNC_BUILD_ID`、`SYNC_EXPECT_EPOCH=0`、`SYNC_START_PAGE=1`、`SYNC_TARGET_PAGE=2` 以及服务报告的 `APP_ORIGIN=https://127.0.0.1:PORT`。设备按上文正常信任测试 CA；Android 仍需按规定配置 WebView 和 `SYNC_TEST_CA_BASE64`。

驱动在真实第 2 页先确认正常进度已保存，然后点击「读完本章」。`SYNC_ACK_LOSS_COMMITTED_UNCONFIRMED` 表示同一阅读页仍保留未确认草稿，但只读检查已看到作品 revision 增加 1，页码和 epoch 不变。驱动点击「重试保存」，要求 `SYNC_ACK_LOSS_RETRY_CONFIRMED` 时待确认提示消失、同一阅读页仍挂载、D1 快照不再变化。按 Enter 停止 harness，核对 `ACCEPTANCE_PROGRESS_ACK_AUDIT` 恰好两条、`drop_ack=1/0`，且 UUID、请求正文、预期 revision、ACK 和持久回执的摘要相同。只读检查和审计共同证明本次重试复用了原请求，不能推广为其它平台、关闭后恢复或生产故障通过。

### 真实 Source 完整章、跨章和新进程续读

在隔离回环 HTTPS 入口装配与当前运行材料匹配的真实 AOT，使用新 D1 和 `acceptance-owner`。先用 `bookmarks_sync_test.dart` 的 `prepare` 从正式界面安装、打开英语源、收藏作品。热门无目标作品时可用 `BOOKMARKS_PREPARE_SEARCH` 走正式 Source 搜索；如尚未知 URL，可用 `BOOKMARKS_PREPARE_MANGA_TITLE`、`BOOKMARKS_PREPARE_CHAPTER_TITLE` 唯一定位，已知的 URL 优先。输出 `BOOKMARKS_SYNC_RESULT` 含精确作品、章节及相邻章节的来源顺序偏移与 URL。

用 `flutter test integration_test/source_chapter_test.dart --no-pub -d DEVICE --dart-define-from-file=PARAMS` 启动正式 `app.main()`。参数 `APP_ORIGIN` 不带末尾斜杠；`SOURCE_CHAPTER_PACKAGE`、`SOURCE_CHAPTER_SOURCE`、`SOURCE_CHAPTER_BUILD`、`SOURCE_CHAPTER_MANGA`、`SOURCE_CHAPTER_FIRST`、`SOURCE_CHAPTER_NEXT` 填精确包、Source ID、构建 ID、作品 URL、首章及下一章 URL。`SOURCE_CHAPTER_REVERSED` 按两章的实际相邻顺序设置。设置 `SOURCE_CHAPTER_FIRST_PAGES`、`SOURCE_CHAPTER_SAVED_PAGE`；已知下一章完整页数时可设 `SOURCE_CHAPTER_NEXT_PAGES`，否则按实际清单校验目标页界限。Android 同前使用专用 debug APK 的精确回环信任配置，另传 `SOURCE_CHAPTER_TEST_CA_BASE64`。

`SOURCE_CHAPTER_PHASE=read` 从书架进入详情，逐页核对首章的当前页码与实际解码帧，显式读完，再通过「下一章」读到指定保存页。退出后用独立进程从相同 HTTPS/D1 执行 `SOURCE_CHAPTER_PHASE=resume` 和 `SOURCE_CHAPTER_RESUME_THROUGH`，通过书架续读首次恢复同一清单的已保存页，按需再读至目标页。两阶段以 `SOURCE_CHAPTER_FRAME` 记录页码和实际解码尺寸，以 `SOURCE_CHAPTER_RESULT` 记录进程、已确认的章节锚和完成状态。另从主机以正常 TLS 独立读取 D1，核对首章已完成且锚点未被后续阅读改变。本驱动是功能验收，不用帧记录推断真机性能。

### D1 拒绝阅读进度写入

沿用上一节的正式 HTTPS、空 D1、测试身份和精确 xkcd 构建。启动服务时改用 `ACCEPTANCE_FIXTURE=progress-d1-error`。从正式界面安装并收藏英文 xkcd，再以 `SYNC_PHASE=d1-error` 运行相同的第 1 → 2 页驱动。

真实第 2 页先正常确认。点击「读完本章」后，验收库的 SQLite trigger 在该次 D1 原子批次的最后一个回执更新处拒绝提交，Worker 返回业务 HTTP 503。`SYNC_D1_ERROR_ROLLED_BACK_UNCONFIRMED` 要求真实页仍挂载、界面保留草稿和「重试保存」，只读进度与提交前一致。故障解除后仍需点击该按钮；`SYNC_D1_ERROR_RETRY_CONFIRMED` 才表示同一阅读视图显示已完成和保存确认。

停服核对 `ACCEPTANCE_PROGRESS_D1_ERROR_AUDIT`：恰好两条，503 `UNAVAILABLE` 无回执、两个 revision 不变；200 有持久回执、两个 revision 各增加 1；UUID、原始正文摘要和预期 revision 相同。可用独立 GET 确认最终当前与最远都仍是第 2 页且 epoch 不变。这一门与提交后丢确认分开，不代表生产 D1 故障验收。

### 阅读进度同时写

使用当前 xkcd 快照构建正式产品（Web 用 `pnpm acceptance:build`，Native 用 `pnpm acceptance:build:native`）。在新隔离 D1 上执行 `ACCEPTANCE_FIXTURE=progress-cas-race pnpm acceptance:serve`，两个正式客户端使用服务打印的同一 origin 和测试身份。Native 仍使用前述回环 HTTPS、正常证书信任与实际端口。

先从正式界面安装并收藏英文 xkcd，两个独立 Reader 打开 `SINGLE` 的 `/3319/`，保持真实第 2 页已解码且已保存、尚未读完。两端必须确认同一作品 revision、epoch 与清单后才开始；普通进度观察不会占用夹具。一个 Reader 点「读完本章」，另一个点「重新阅读本章」，两条命令须在 15 秒内到达；双方都经过正式 Worker 的写前读取并到达 D1 原子批次后，才提交各自原有的批次。

分别记录成功端和冲突端。先等成功端显示真实页面并确认当前与最远位置，使其保持挂载；再验证冲突端仍可翻动已加载画面、旧视图无法改变服务端，且显式重开后采用赢家的位置与完成状态。独立进程比较打开前、两端打开后、冲突端重开前后及退出后的设置、书架、作品、书签、进度和指定章。区分竞争当时的单次修订与重置后因真实图片显示产生的普通进度保存。停服核对 `ACCEPTANCE_PROGRESS_RACE_AUDIT` 恰好两条、不同 UUID 与同基线、处理时段重叠、两个 `batch_ready_at_ms` 都不晚于首个响应，一个 HTTP 200 有持久回执，一个 HTTP 409 无回执，两条权威状态摘要相同。已取得[双 iOS 模拟器正式 Reader 证据](../../../docs/verification/concurrent-server-state.md#双-ios-模拟器阅读进度同时写)，与[仅调用 API 的对照](../../../docs/verification/concurrent-server-state.md#阅读进度同时写正式-api-与-d1-夹具)分开记录。
