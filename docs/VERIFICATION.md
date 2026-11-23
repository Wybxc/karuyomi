# 实施验证记录

记录以提交号、实际运行环境、观测结果和未通过项标识每轮验收。需要重跑时从仓库的[工程检查入口](TOOLING.md)、[Worker 测试](../apps/api/test/README.md)或[原生集成测试](../apps/reader/integration_test/README.md)重新生成输入。历史日志、截图名称和报告摘要只标识当时的观测。

2026-11-22，主线 `af8c203` 的生产 Worker `70948d0b-ac41-4e03-a68a-d7912c0c6829` 接收全部流量。公开状态与索引逐字节匹配 revision `ddb5ac8f3b2a46cb8efc2dafc440b3d4`，46 项 Web 静态资源和匿名 Access 302 通过。Arknights Comics 1.6.2 的清单、gzip 与解码后摘要通过。逐包检查与生产索引一致的 191 个产物，只有该包导出 `hostAcquireCover`。生产登录后的普通封面显示待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，在 `macbook-pro-4` 固定 `af8c203`、Keiyoushi `efa93f5a` 和生产父快照试编 xkcd。Gradle 构建、TeaVM AOT、正式产物校验及 `hostAcquireCover` 导出检查通过，canonical SHA-256 为 `4ef740416ad8976e9870e161ce5c7edff8b60f7261e71f3648f03edee10d5f89`。该包仍标记 `compiled_unverified`。随后在同一台机器启动两并发冻结队列。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`macbook-pro-4` 复用主线 `af8c203` 的 CI Web/runtime 归档，用生产父快照通过正式 Vite 装配和 Wrangler 4.156.1 dry-run。生产索引及 191 份清单与预演输入逐字节一致，191 个公开 gzip 的强 ETag 与固定 Wrangler 的上传指纹一致，MIME 与 HTTP 编码均符合交付合同。完整候选的生产交付与普通封面现场验收仍待完成。[主线 CI](https://github.com/Wybxc/karuyomi/actions/runs/44912832454)

2026-11-22，在 `macbook-pro-4` 从同一冻结计划和检查点优先编译队列末尾的 54 个现网包，全部成功。逐包核对原索引中的 191 个包，其中 190 个重编并通过正式构建校验，Arknights Comics 复用同一输入的已上线构建。解码后的 191 个包均导出 `hostAcquireCover`，原有 1,035 个 Source 条目保留。四并发全量队列随后接续，父 revision、目录指纹及 1,447 个选择项与原计划一致。内置浏览器的控制调用仍超时，真实页面出图待复验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，原现网 191 个扩展的封面宿主升级已发布。Worker `68584fe5-3d3b-4425-8017-77ca374cc0c0` 承接 100% 流量。公开状态与索引逐字节匹配 revision `ef76d5d1952b4733a10704d8401748ad`，191 份清单、191 个安装包强 ETag、46 项 Web 静态资源及匿名 Access 302 均通过。已用正式 `commit-snapshot` 提交该检查点。完整目录仍有 1,257 个输入待计入已发布基线，`bootstrap.complete` 为 `false`。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，冻结批次的 MangaFire 缺少 TeaVM `Class.getResource`。宿主补充了打包资源的 URL 读取，JDK 与实际生成的 JavaScript 对照通过 8 项资源读取断言，原 80 项日期断言和 `pnpm teavm:check` 均通过。在 `macbook-pro-4` 固定 `b4cbede` 与同一上游提交补编 MangaFire 1.6.36，正式 Gradle、TeaVM 和产物完整性检查通过，打包有 7 个 Source 及 `hostAcquireCover`。共享运行材料清单与冻结批次逐字节一致，canonical SHA-256 为 `307cae848db6c5af71f33518daa46eee2c76d0e148f189b1cd6ebe2fb8573449`。结果为 `compiled_unverified`，等待完整候选合入及在线复验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，冻结批次的 Komga 缺少 `Builder.authenticator`，BookOrbit、LANraragi、Mango 缺少 `Builder.dns`。宿主补齐同源 401 和系统 DNS，`pnpm teavm:check` 的 24 项回环 HTTP 断言和 26 项网络配置断言通过，覆盖重定向凭证隔离、一次性正文及响应释放。在 `macbook-pro-4` 固定 `a2d506a` 和 Keiyoushi `efa93f5a` 补编 Komga 1.6.75、BookOrbit 1.6.1、LANraragi 1.6.2、Mango 1.6.1，四包均通过正式完整性和 `hostAcquireCover` 检查，共 7 个 Source。共享运行材料清单与冻结批次逐字节相同，四包保持 `compiled_unverified`，生产出图与源站登录待验。[Source 网络桥](design/mihon-web-design.md#84-扩展回调与网络桥)

2026-11-22，冻结批次的 BookWalker 和 J-Novel 缺少 Java 摘要子类构造器与 `InvalidParameterException`。补齐宿主分派后，`pnpm teavm:check` 通过，生成的 JavaScript 与 JDK 对照通过 10 项摘要断言。在 `macbook-pro-4` 固定 `f64676e` 和同一 Keiyoushi 提交，BookWalker 1.6.2 与 J-Novel 1.6.3 均通过正式 AOT、产物完整性及 `hostAcquireCover` 检查，各包含 1 个 Source。共享运行材料一致，两包均为 `compiled_unverified`，在线验收待完成。[摘要实现](../runtime/teavm/README.md)

2026-11-22，Read Berserk Manga 在冻结并发构建中因 Gradle 打包共享主题缓存时读取文件模式失败。用 `macbook-pro-4` 上独立的 `f64676e` checkout 串行复验同一 Keiyoushi 提交，Gradle、TeaVM 和正式完整性检查通过。1.6.1 产物包含 1 个 Source 与 `hostAcquireCover`，canonical SHA-256 为 `161714228319a84bb9d32249751dd604bc69a82b881dbb219bb513a76bf419d5`，保持 `compiled_unverified`，已登记到完整候选。同期其他扩展有上游 KSP `@Source` 继承校验错误，原诊断按包保留。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`303bc67` 补齐冻结批次缺少的 Java PBKDF2 接口。`pnpm teavm:check` 通过，实际生成的 JavaScript 与 JDK 对照通过 8 项断言。在 `macbook-pro-4` 固定同一 Keiyoushi 提交补编 Coolmic 1.6.3、Manga Drama 1.6.6、Mgread.io 1.6.7，三包正式 AOT、完整性和 `hostAcquireCover` 检查通过，各保留 1 个 Source。共享运行材料与冻结批次逐字节相同。三包与此前八个补编结果通过候选装配前检查，等待全量终态。三包保持 `compiled_unverified`，生产发布与在线出图待验。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 用 LunarAnime 的隔离构建副本复现 TeaVM 字符串拼接参数越界。`5281227` 的固定编译器补丁经 JDK 与生成 JavaScript 对照通过，`pnpm teavm:check` 通过。随后同机用原扩展正式重编，越过原异常，AOT 仍因 `KeyFactory`、`KeyPairGenerator`、`KeyPair` 和 `ECPoint` 缺失而失败。[编译器补丁](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 的独立 `5281227` checkout 串行复验冻结批次上游 KSP 失败的 Read One Piece Manga Online。使用同一 Keiyoushi 提交，Gradle、TeaVM、完整性和 `hostAcquireCover` 检查均通过。1.6.1 产物包含 1 个 Source，canonical SHA-256 为 `49995bc1842d7c7464f9553f25de7d374492fcfc1e30f4e56e0bd8e5c125292e`。该包保持 `compiled_unverified`，同主题同类失败按包排队复验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，同一 `5281227` checkout 的 The Blank 1.6.5、TCB Scans 1.6.1 和 Webnex 1.6.9 通过正式 AOT、完整性和 `hostAcquireCover` 检查，各保留 1 个 Source。补编分别使用时区与资源、应用数据目录和资源读取适配。候选预检核对 `303bc67` 和 `5281227` 两批的 15 个真实产物与封面入口，生产父 revision 为 `ef76d5d1952b4733a10704d8401748ad`，两批共享材料逐字节一致。多批组装通过 62 项扩展流水线、14 项构建和 16 项完整性测试。全量落盘及生产出图待验。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，`macbook-pro-4` 的独立 `5281227` checkout 串行复验冻结批次中同一 MangaCatalog 主题的 KSP 继承校验失败。包含先行试编在内，12 个受影响扩展均在固定的 Keiyoushi 提交上通过正式构建、产物完整性和 `hostAcquireCover` 检查，共 12 个 Source。各包保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`7e0c053` 的 P‑256 适配通过 `pnpm teavm:check`。JDK 与生成的 JavaScript 均通过 12 项密钥和签名断言，验证 RFC 6979 的公开向量，两端也能互相读入 X.509 公钥并验签。LunarAnime 与 ProComic 已在 `macbook-pro-4` 排入固定提交的正式补编。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 的独立 `7e0c053` checkout，ProComic 1.6.4 通过正式构建、产物完整性和 `hostAcquireCover` 检查，包含 1 个 Source。共享运行材料逐字节匹配，canonical SHA-256 为 `c6234a722a92ca4200f0261c50fb1ad7fe93af14e7643432ffb6e14b84c40a2d`，保持 `compiled_unverified`。同一批次的 Lunar Manga 越过密钥接口错误，正式 AOT 仍卡在上游 Turnstile helper 所需的 Android Activity 和 WebView 接口。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，同一 `7e0c053` checkout 的 Capibara Traductor 1.6.5、Mangas.in 1.6.4、Mangas No Sekai 1.6.78 通过正式 AOT、产物完整性及 `hostAcquireCover` 检查，各包含 1 个 Source。后两包以打包资源读取适配重新构建。三个补编批次共 30 个包经候选预检，与生产父快照 `ef76d5d1952b4733a10704d8401748ad` 和冻结批次共享材料匹配。三包保持 `compiled_unverified`，等待全量发布与在线验收。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，Nexus Scanlation 在冻结批次因缺少 Java `KeyPairGenerator` 和 `KeyAgreement` 失败。宿主补齐两方 P‑256 协商后，JDK 和生成的 TeaVM JavaScript 对照通过 18 项椭圆曲线断言。其中 6 项新增断言覆盖 RFC 5903 公开向量、错误输入和协商状态复用，双向 ECDSA 验签也通过。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 固定 `65e303a` 与同一 Keiyoushi 提交补编 Nexus Scanlation 1.6.8，正式构建、产物完整性及 `hostAcquireCover` 检查通过，包含 1 个 Source。canonical SHA-256 为 `cf7ba2151c27e2bccf2e7f2f3ec299dc77e936898cc6fd86ac8a2c86ce52f535`。共享材料逐字节一致，第四个补编批次已通过候选预检，保持 `compiled_unverified`。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，Emaqi 的冻结构建缺少 Java 的 RSA 密钥及 OAEP 参数接口。使用正式宿主兼容层在 JDK 与生成的 TeaVM JavaScript 各通过 16 项 RSA-OAEP 断言，覆盖标准密钥编码、标签和参数、单块长度、短输出重试及错误标签。正式扩展构建和在线运行需另外验收。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 固定 `9e67f54`，Emaqi 1.6.3、Epsilon Scan 1.6.5、Soft Epsilon Scan 1.6.5 均通过正式构建、产物完整性和 `hostAcquireCover` 检查，各包含 1 个 Source。两项法语扩展使用已验证的时区与打包资源读取。第五个补编批次使用与冻结批次逐字节一致的共享材料，候选预检累计纳入 34 个补编结果，仍待上线与在线验收。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，Falco Scan（`tenkaiscan`）冻结构建缺少位图矩阵绘制和颜色过滤接口。JDK 与生成 TeaVM JavaScript 对照通过 45 项仿射和颜色断言，Android API 35 原生图形 oracle 通过 5 项测试，核对裁剪、密度、颜色矩阵及画笔透明度的顺序。对合成 129×129 位图执行生成的 TeaVM 绘图代码，受控 Node 图形桥核对两个不超过 64 KiB 的 RGBA 块、实际下发矩阵及模拟绘图失败后的释放，已有 21 项图形桥回归通过。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 固定 `ddbcbb8`，Falco Scan 1.6.1 的正式构建、产物完整性及 `hostAcquireCover` 检查通过，包含 1 个 Source。canonical SHA-256 为 `363d849a4a1d7c40cfc01c238a6113826de4d83f34043323cec153de648bffc1`，共享材料逐字节一致，候选预检纳入第 35 个补编结果，保持 `compiled_unverified`。正式出图和使用真实源站图片的阅读待验。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，在 `macbook-pro-4` 的同一 `ddbcbb8` checkout 提前试编 U-Next、OneReader 和 MoeTruyen，三包使用相同上游源码闭包及共享材料。U-Next 1.6.4 通过正式构建、产物完整性和 `hostAcquireCover`，canonical SHA-256 为 `f7b0597516d7fbb035f2a4df681d7bc2464bbefdbdce185e62d1fd21599bf05f`，候选预检等待该包的冻结原回执。OneReader 的密钥接口已通过编译解析，缺少 Java `SequenceInputStream`。MoeTruyen 仍依赖未实现的 Android 对话框和视图接口，以及双参数 `Cipher.init`。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，顺序流兼容层在 JDK 与生成的 TeaVM JavaScript 各通过 15 项断言，覆盖延迟读取、空分段、无符号字节、EOF、提前关闭及后续关闭错误的传播。完整 `pnpm teavm:check` 通过，OneReader 正式补编待复验。[宿主实现](../runtime/teavm/README.md)

2026-11-22，在 `macbook-pro-4` 固定 `289f182` 补编 OneReader 1.6.4，正式构建、产物完整性及 `hostAcquireCover` 检查通过，包含 1 个 Source。canonical SHA-256 为 `c2fe7b4a807128569377e50f5faab570d61303ea89c1c9a8619c56c8c9c35879`，共享材料逐字节一致。保留提前构建回执，等待冻结原回执及在线验收。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，Dragon Ball Multiverse 和 ManhuaRM 的冻结构建均缺少 `StaticLayout.Builder`。Android API 35 原生图形参考以合成段落复现三组不同断行结果。80 px 下，简单与高质量断行的第 5 行分别止于 UTF‑16 偏移 40 和 39，关闭与开启完整连字符的第 2 行分别止于 12 和 14。85 px 下，高质量与平衡断行的第 9 行分别止于 69 和 71。扩展所需的断行与连字符仍待宿主实现。[Android 参考测试](../tools/teavm/fixtures/text-layout/AndroidTextTest.java) · [Android Builder](https://developer.android.com/reference/android/text/StaticLayout.Builder)

2026-11-22，宿主接入 `StaticLayout.Builder`、段落断行和按语言选用的连字符词表。布局与图形桥的 28 项定向测试通过，覆盖三种策略、硬换行、字素边界，以及补画连字符后的行宽和原始 UTF‑16 偏移。`pnpm teavm:check`、严格类型检查和正式 Web/Native 运行时构建通过。新图形材料 SHA‑256 为 `3df7d350c88ee9ed495d17df976534d1fdc00c51ed0ce5432bf34d2f263504f0`，须使用匹配的扩展构建。两个扩展的正式补编、实际绘制和生产发布待验。[文字布局计划](plan/text-layout.md)

2026-11-22，在 `macbook-pro-4` 固定 `c549ae6` 和 Keiyoushi `efa93f5a` 后独立补编。Dragon Ball Multiverse 1.6.1 与 ManhuaRM 1.6.1 均通过正式 Gradle、TeaVM AOT、产物完整性和 `hostAcquireCover` 检查，共 44 个 Source。两包的 canonical SHA‑256 分别为 `0f24bf0ea7c2b3ae48a919379d57d5f3fe9a7584d16e0206a5e312b07fa06533` 与 `b5dba5b987116f30f1782832ba5eb4ba3b0435a6fd887560f5ce6de185215b8b`。补编使用与 CI Web 归档匹配的新图形材料，两包保持 `compiled_unverified`，实际绘制和生产发布待验。[GitHub CI](https://github.com/Wybxc/karuyomi/actions/runs/44962498253)

2026-11-22，SoftKomik 冻结构建缺少 Java `UnknownHostException`。JDK 与生成的 TeaVM JavaScript 对照通过该异常的继承、捕获和消息保留，完整 `pnpm teavm:check` 通过。当前 HTTP 中继以通用网络错误表示请求失败，扩展在线遇到 DNS 错误时的分支仍待验证。[HTTP 传输边界](HTTP-BRIDGE.md)

2026-11-22，在 `macbook-pro-4` 固定 `eac70b4` 补编 Softkomik 1.6.4，正式构建、产物完整性及 `hostAcquireCover` 检查通过，包含 1 个 Source。canonical SHA-256 为 `f0606f04683feb3e0d4cf56c5a21ad39eac08f3b4838259c54f1396806a16809`，共享材料逐字节一致，候选预检纳入第 36 个补编结果。生产仍为 revision `ef76d5d1952b4733a10704d8401748ad`，已读回的公开索引含 191 个扩展。在线出图与 DNS 错误情况待验。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，ebookjapan 冻结构建缺少 `Rect.exactCenterX`。宿主补齐双轴中心计算，JDK 与生成的 TeaVM JavaScript 共通过 54 项图形变换断言，其中 9 项覆盖半像素中心、平移、围绕中心旋转及 Android 整数算术。Android API 35 原生图形参考通过 6 项测试，使用 3×1 位图验证半像素中心旋转后的实际像素。完整 `pnpm teavm:check` 通过。[Android Rect](https://developer.android.com/reference/android/graphics/Rect)

2026-11-22，在 `macbook-pro-4` 固定 `0472569` 和同一 Keiyoushi 提交补编 ebookjapan 1.6.5。正式 AOT、产物完整性和 `hostAcquireCover` 检查通过，包含 1 个 Source，canonical SHA-256 为 `abed0629eb3a43f00a36dc49bd1e95fda8b6cee59b54b8989a93bc4bb836ac11`。候选装配预检核对共享材料与生产父快照，累计纳入 37 个补编结果。该包保持 `compiled_unverified`，待生产发布和在线出图验收。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，原冻结队列收到 U-Next 和 OneReader 的 AOT 失败回执。装配预检按原输入及共享材料校验两份正式补编，累计纳入 39 个补编结果，生产父 revision 为 `ef76d5d1952b4733a10704d8401748ad`。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，SoraRaw 冻结构建缺少颜色数组版 `Bitmap.createBitmap`。宿主复用有界像素写入，按原 API 返回独立的不可变位图。Android API 35 原生参考共通过 7 项测试，新增用例核对逐像素复制、负 stride 与无效参数。`pnpm teavm:check` 通过。在 `macbook-pro-4` 固定同材料提交 `58f2d79` 与 Keiyoushi `efa93f5a`，SoraRaw 1.6.3 通过正式 Gradle、TeaVM、完整性和 `hostAcquireCover` 检查，包含 1 个 Source，canonical SHA‑256 为 `56f21ff078d2c80b1cd991603e4e8992f91f367ea373ff438b563a58379e8cc5`。装配预检将其纳入第 40 个补编结果，保持 `compiled_unverified`。[Android Bitmap](https://developer.android.com/reference/android/graphics/Bitmap)

2026-11-22，在 `macbook-pro-4` 复用固定 `58f2d79` 和 Keiyoushi `efa93f5a`，Gölge Bahçesi 1.6.2、Koreli Manga 1.6.6、Manga Ruhu 1.6.6、Merlin Scans 1.6.7 通过正式 AOT、产物完整性和 `hostAcquireCover` 检查，各包含 1 个 Source。Gölge Bahçesi 使用既有打包资源读取适配，其余三包使用既有 PBKDF2 适配。共享材料逐字节一致，装配预检纳入 44 个补编结果，四包保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`1d82b02` 为 OkHttp 整次调用提供超时。完整 `pnpm teavm:check` 通过，包含 13 项新增回环断言，覆盖重定向后的响应头等待、流式正文超时、连接释放和异步回调次数。JDK 与生成的 TeaVM JavaScript 均通过独立的超时与退出探针。同材料固定 checkout `de001d3` 在 `macbook-pro-4` 完成 AnimexNovel 1.6.20 和 ArgosComics 1.6.64 的正式 AOT、产物完整性及 `hostAcquireCover` 检查。两包各包含 1 个 Source，保持 `compiled_unverified`。[超时语义](HTTP-BRIDGE.md)

2026-11-22，`58d38c7` 实现带支点的 `Canvas.scale`。Android API 35 原生图形参考共 8 项通过，新增用例对照绕非整数支点反射后的实际像素。JDK 与生成的 TeaVM JavaScript 各通过 60 项图形变换断言。MangaTR 1.6.25 在 `macbook-pro-4` 同材料 checkout `de001d3` 通过正式 AOT、产物完整性及 `hostAcquireCover` 检查，包含 1 个 Source，canonical SHA-256 为 `93e823a456a69e21e745a70bd341660cd0b903d9c0f60887582299cf9d620d19`，保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，OriManga 1.6.6、Paradox Scans 1.6.6、Ragnar Scans 1.6.6、Siyah Melek 1.6.7 在 `macbook-pro-4` 复用 `58f2d79` 的 PBKDF2 适配，分别通过正式 AOT、产物完整性和 `hostAcquireCover` 检查，各包含 1 个 Source。四包保持 `compiled_unverified`。全量装配预检纳入 51 个补编结果。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`a35e3be` 和 `8cd026f` 将 Android 字节数组版 `ImageDecoder` 接到现有有界位图解码。JVM 受控桥核对同一字节句柄的头部回调、像素解码顺序，以及成功、无效数据和回调异常后的释放。Robolectric API 35 原生参考 9 项通过，新增用例使用合成 PNG 核对数组范围、软件分配、像素与 WebP 编码。该环境的 AVIF 解码返回未实现，合成 AVIF 另用固定头部解析器与 FFmpeg 独立核对尺寸及像素。完整 `pnpm teavm:check` 通过，真实浏览器 AVIF 解码和源站封面待验。[Android ImageDecoder](https://developer.android.com/reference/android/graphics/ImageDecoder)

2026-11-22，HV2TComics 1.6.4 在 `macbook-pro-4` 固定 `efc86e2` 与 Keiyoushi `efa93f5a` 通过正式 Gradle、TeaVM AOT、产物完整性和 `hostAcquireCover` 检查，包含 1 个 Source。共享材料与冻结批次逐字节一致，首个补编的 canonical SHA-256 为 `f5bbcaabb676ca7fa2f038b7b9e0a5da96a8da939ac58eefd211cc9f65be813f`，保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`macbook-pro-4` 收齐冻结目录 1,448 个输入的回执。补编装配纳入 HV2TComics 的数组边界修正版 `739ff03`，以及在收尾阶段成功构建的 Tủ Sách Xinh Xinh、Yuri Garden 和 Picacomic。逐包审计确认 1,414 个可分发扩展均导出 `hostAcquireCover`，共 2,280 个 Source，保留历史可用的 1,371 包并新增 43 包。34 个输入有明确的 AOT 失败记录。漫画人复用 X.509 接口后，仍缺双参数 `Cipher.init`。正式 Vite 与 Wrangler dry-run 通过，当前批次的生产发布和实际出图待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，主线 `af8c203` 的有界增量预检曾将 55 个已由补编恢复的软件包按旧失败输入重新排队。`d7b8485` 修正账本保留逻辑，62 项扩展流水线回归、工具严格类型和依赖分层检查通过。在 `macbook-pro-4` 用同一组产物重装配 revision `85bf2ec61d274e83bfc3b4281034851f`，索引逐字节一致，保留 55 份原失败回执。固定主线的正式 `plan --ci --limit 12` 选择 0 项，生产读回待验。[补编与增量合同](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，带封面入口的完整扩展基线已发布。Wrangler 4.156.1 将 Worker `30f79ab5-5d7e-4390-8f67-e58ec5085986` 切换至 100% 流量，线上 revision 为 `85bf2ec61d274e83bfc3b4281034851f`。生产索引与构建状态逐字节核对，1,414 份清单、1,414 个 gzip 强 ETag 及交付头、46 项 Web 静态资源和匿名 Access 302 均通过。D1 账本读回 13 项迁移，连续至 `0012`。本机与 `macbook-pro-4` 的正式检查点均已写入。从生产读回状态后，同一主线的有界增量计划选择 0 项。定时扩展工作流保持手动停用。内置浏览器连接超时，生产登录后的出图待验。34 个扩展仍有 AOT 失败记录。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，`00df97d` 补齐 X.509 RSA 公钥导入及 PKCS#1 v1.5 公开加密。完整 `pnpm teavm:check` 通过，生成的 JavaScript 与 JDK 对照通过 13 项 PKCS#1 v1.5 断言和原有 16 项 OAEP 断言。JDK 独立解出了由生成代码使用合成公钥加密的测试数据。在 `macbook-pro-4` 的独立 `3fe63f1` checkout 用固定 Keiyoushi `efa93f5a` 补编漫画人 1.6.2，正式 AOT、产物完整性和 `hostAcquireCover` 检查通过。共享运行材料与生产父快照相同，canonical SHA-256 为 `78c22a39d47b1776906e16763e619406f695fad568ac5eb4ddd279b6502d41ec`。正式装配核对原有 1,414 个索引条目逐项相同，新增一个扩展和一个 Source，原失败回执保留。Vite 正式构建及 Wrangler dry-run 通过，漫画人保持 `compiled_unverified`。[宿主实现](../runtime/teavm/README.md)

2026-11-22，Wrangler 4.156.1 上传漫画人的清单和 gzip、扩展索引及构建状态共 4 项，Worker `9d83d2e9-be0b-4a34-9dbc-d930d54bc192` 接收 100% 流量。生产 revision `253d97308eb0412280daba751b79b945` 可分发 1,415 个扩展和 2,281 个 Source，33 个 AOT 失败保留诊断。通过 `macbook-pro-4` 读回生产索引、状态、漫画人清单和 gzip，核对安装包压缩前后摘要、强 ETag、46 项 Web 静态资源及匿名 Access 302。本机和构建机检查点均已确认，固定主线的 `plan --ci --limit 12` 选择 0 项。生产登录后的漫画人出图待验。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，固定 PDFium 3.0.0 的合成双页用例在 Node 24.15.0 栅格化真实像素，覆盖不同页尺寸、透明背景、坏 PDF、超内存分配、按需加载和请求结束后的句柄释放。PDF、图形和材料 29 项测试通过，`pnpm teavm:check`、严格类型、依赖分层和扩展构建与完整性检查通过。正式 Vite 构建生成八份共享材料，原生 Worker 为 6,713,931 字节，低于 8 MiB 脚本限额。原扩展正式 AOT、生产与真实阅读另验。[运行材料](RUNTIME-MATERIALS.md)

2026-11-22，在 `macbook-pro-4` 固定宿主 `db79dd5` 和 Keiyoushi `efa93f5a`，MangaDash、Dragon Ball Multiverse 和 ManhuaRM 的 1.6.1 产物通过正式 AOT、完整性和 `hostAcquireCover` 检查，共覆盖 45 个 Source。运行材料版本 `5216a27745dc1bb1c1e2760ae99cd179b1352924c41b8edeb93e912ac026bcdf` 与本机产物一致。通过正式入口读回生产父 revision `253d97308eb0412280daba751b79b945` 后，四路全量重建已启动，复用这三份回执并覆盖 1,448 项。三个包均保持 `compiled_unverified`，生产发布与实际阅读待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`08475d4` 补齐发布测试的 PDFium 材料元数据。macOS arm64 上的完整 `pnpm check` 和 `pnpm build` 通过。Web 和 Native 产物的材料身份相同。直接检查 Worker 静态目录确认 PDFium 的长度、SHA-256、`application/wasm` 与 immutable 缓存头，Web 随附上游许可。构建时扩展队列仍在运行，故本次产品构建使用空扩展目录。[运行材料](RUNTIME-MATERIALS.md)

2026-11-22，`93202ca` 将 OkHttp 调度容量接入宿主的 HTTP 调用。完整 `pnpm teavm:check` 及工具类型检查通过，队列用例合计 97 项断言，覆盖总并发、按域名跨端口限额、配置调整、回调期间占用名额和排队取消。在 `macbook-pro-4` 固定 Keiyoushi `efa93f5a`，MangaKakalot 1.6.28 分别用现网材料 checkout `5a72a6f` 和新材料 checkout `65934a1` 完成正式 AOT、产物完整性和 `hostAcquireCover` 验证。两份产物均保留一个 Source。canonical SHA-256 分别为 `ab70100b7af58e91ecea5f7228f508c8c5acfaa1fb078d143a05f771cd82e66c` 和 `38259acb8dc747a1f594bdbe3a3817d8e16922071da220c45200540bc7879cf4`。[宿主实现](../runtime/teavm/README.md)

2026-11-22，MangaKakalot 1.6.28 加入现网索引。Wrangler 4.156.1 更新 4 项静态资源，Worker `177a3744-ed76-48e9-9f37-47653d57fd7c` 接收全部流量。生产 revision `fd36b3a383664022934cf2f3f2abc47d` 的 1,416 个扩展包含 2,282 个 Source，32 个 AOT 失败保留诊断。原有 1,415 个索引条目逐项对照通过。公开索引、状态、MangaKakalot 清单和 gzip、46 项 Web 静态资源及匿名 Access 302 均已读回确认。两地检查点已更新，同一主线的有界规划选择 0 项。该扩展保持 `compiled_unverified`，实际出图待验。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，从生产 `fd36b3a383664022934cf2f3f2abc47d` 派生八材料装配计划，保留全部 1,448 个冻结输入并纳入同材料的 MangaKakalot 成功回执。构建过程仍使用原冻结 checkout。复核时全量进程存活，已记录 94 个成功和 1 个失败。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`56ab110` 接入 Source 文本设置的原弹窗说明和有界 HTTP(S) 链接。`pnpm check`、`pnpm flutter:check`、`pnpm teavm:check` 与 `pnpm build` 通过，设置 JVM 夹具共 198 项断言，Flutter 设置组件共 38 项测试。在 `macbook-pro-4` 固定 Keiyoushi `efa93f5a`，Mehgazone 1.6.1 的正式 AOT、产物完整性、弹窗描述和 `hostAcquireCover` 导出检查通过，包含 1 个 Source。八份共享材料与冻结队列相同，canonical SHA-256 为 `141fd57b59b4f6d46d386bcf5af11ba66c809bd155b387d6dff27127f9e75942`。回执保持 `compiled_unverified`，实际设置、源站登录及出图待验。[设置计划](plan/source-preferences.md)

2026-11-22，以同一生产父 revision 核对 1,448 个冻结输入和两个替换包 MangaKakalot、Mehgazone。原八材料队列复核时收到 150 个成功和 2 个失败回执。最终装配仍待冻结输入全部取得正式终态。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`23ae07b` 复用固定 Bouncy Castle 实现 Source 使用的 `AES/ECB/NoPadding`。`pnpm teavm:check` 与工具类型检查通过，固定 JDK 和生成的 JavaScript 均通过 45 项 AES 断言。在 `macbook-pro-4` 固定 Keiyoushi `efa93f5a`，Doujin.io 1.6.5 的七材料 checkout `027f722` 和八材料 checkout `23ae07b` 均通过正式 AOT、产物完整性和 `hostAcquireCover` 检查，各包含 1 个 Source。两个 canonical SHA-256 分别为 `3bef027571462d55e0c889c1dca178e78e71d09f3bc44ffc6e455a3f24b5b2f3` 与 `d25fc4be245d4e9359b7370a7b7f8eabe7cc30266ff0d84d2ec5b14bb8f7139b`。回执保持 `compiled_unverified`，实际出图待验。[宿主实现](../runtime/teavm/README.md) · [完整 CI 与 Web/Wasm 构建](https://github.com/Wybxc/karuyomi/actions/runs/45019244395)

2026-11-22，Doujin.io 1.6.5 的七材料构建已发布。Wrangler 4.156.1 核对 Worker `5cb2eecb-b1b9-486b-892e-b4ffda8cbd60` 接收全部生产流量。revision `448797e3feaa477c8ea18f54c6b874bd` 包含 1,417 个扩展和 2,283 个 Source，保留 31 个失败输入。候选逐项比对原 1,416 个索引条目，通过 Vite 与 Wrangler dry-run。生产读回确认公开索引、状态、Doujin.io 清单、gzip 与解码后的两域摘要、强 ETag、46 项 Web 资源及匿名 Access 302。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，本机和 `macbook-pro-4` 已提交 revision `448797e3feaa477c8ea18f54c6b874bd` 的正式检查点。固定主线从生产状态运行的有界增量规划选择 0 项。八材料装配计划以该 revision 为父，纳入 MangaKakalot、Mehgazone 和 Doujin.io 的成功回执。原四路冻结队列复核时收到 228 个成功和 2 个失败回执。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`943b348` 补齐流式 HMAC-SHA-512，并用同一固定库执行原有的 HMAC-SHA-256。`pnpm teavm:check` 与工具类型检查通过，固定 JDK 和生成的 JavaScript 均通过 17 项 HMAC 对照断言。用七材料 `3c21348` 与八材料 `943b348` 在 `macbook-pro-4` 重编 MoeTruyen 1.6.21，两份 JAR 均生成。两套 TeaVM 诊断均定位到 Keiyoushi `askInput` 所用的 Android 对话框、Activity 和输入控件。R8 映射确认原 `askInput` 已内联到调用者。正式 AOT 待终端输入交互接入后复验，当前没有可发布产物。[完整 CI 与 Web/Wasm 构建](https://github.com/Wybxc/karuyomi/actions/runs/45022438982)

2026-11-22，在 `macbook-pro-4` 的临时 checkout 用固定 Keiyoushi `efa93f5a` 和官方 Gradle `assembleRelease` 验证 MoeTruyen 1.6.21 与 MeDamTruyen 1.6.12。通过 Gradle init 脚本给这两个模块的 release 加入 `-keep,allowshrinking`，保留 `keiyoushi.utils.ui.DialogHelperKt.askInput` 的公开静态签名。固定 ASM 9.9.1 在两份官方 JVM JAR 中分别找到一条该签名的直接调用及一条进入辅助类的外部调用。原 MoeTruyen JAR 的该签名与直接调用均为 0。已核对上游跟踪文件，弹窗消息与 Flutter 响应仍待接入。[Android keep 规则](https://developer.android.com/topic/performance/app-optimization/add-keep-rules)

2026-11-22，重新读回生产 revision `448797e3feaa477c8ea18f54c6b874bd` 的索引，摘要与已校验的发布快照匹配。逐包解码核对 1,417 份构建，全部导出 `hostAcquireCover`，覆盖 2,283 个 Source。已核对发布工件，实际出图仍逐源验收。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-22，章节输入桥通过 TypeScript、`pnpm teavm:check`、89 项 Worker 与驱动测试、39 项 Dart 传输测试及两项 Flutter 弹窗测试。隔离夹具验证当前调用绑定、无效和重复答复拒绝、明确确认产生一次模拟写入及取消零次。Flutter 核对密码遮蔽、必填与请求失效后移除对应弹窗。异步桥的真实扩展 AOT 和读章仍待复验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，固定 `f00c680` 的 `pnpm check`、`pnpm flutter:check` 和 `pnpm build` 均通过。工程检查包含 611 项 Vitest 测试，Flutter 应用通过 1,031 项测试。含章节输入的产品归档传到 `macbook-pro-4` 后通过摘要校验，八份共享材料与原冻结队列逐字节一致。在同一构建机固定 Keiyoushi `efa93f5a` 补编 MoeTruyen 1.6.21，官方 Gradle、TeaVM、产物完整性、封面入口和输入能力标记均通过。canonical SHA-256 为 `2acde11ba8adc3759705713f003b884755138e8d3a11e3c55c64ea2a1f49a298`，回执保持 `compiled_unverified`。其余四包继续补编，实际读章待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，`macbook-pro-4` 收齐同一输入下五个扩展的正式成功回执。MoeTruyen 1.6.21、MeDamTruyen 1.6.12、Panomic 1.6.10、SoaiCaComic 1.6.8 和 TeamLanhLung 1.6.42 均通过产物完整性、封面入口及章节输入能力检查。固定 Node 24.15.0 使用 `f00c680` 官方构建的原生 Worker 和五份真实 AOT，每包分别执行确认、取消和后台预取，共 15 个用例。所有源站响应由进程内夹具提供。每包确认产生一次模拟 POST 并返回一页，取消返回 `cancelled` 且零写入，后台预取没有弹窗且零写入。错误提示标识、旧 generation、空必填值和重复答复均未多发请求。生产读章仍待验，回执保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-22，五个输入扩展加入生产父 revision `448797e3feaa477c8ea18f54c6b874bd` 的八材料装配输入。预检读回生产状态，核对 1,417 个现网包仍在完整的 1,448 项计划中、四批共八个替换包的实际回执与八份共享材料。产品归档固定为 `f00c680`，SHA-256 为 `785ab4798789e112477d0e0e3d2045ff8576bae7460de1839e98a28394e9f251`。预检时冻结队列已取得 402 个成功和 6 个失败回执，正式装配待冻结终态。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-22，在 `macbook-pro-4` 使用同一产品归档和 Node 24.15.0，为八个补编包以及原冻结批次的 MangaDash、Dragon Ball Multiverse、ManhuaRM 实际调用封面入口。每包选一个 Source，通过隔离 HTTP 响应获取合成 PNG。11 个 Source 均各发出一次 GET，经二进制通道回传逐字节一致的 68 字节，资源标识、generation、分帧确认和 Worker 关闭通过。源站连通性与客户端实际显示另行验收。`f00c680` 的 CI 和 Wasm 检查已通过。[GitHub Actions](https://github.com/Wybxc/karuyomi/actions/runs/45026856832)

2026-11-23，在 `macbook-pro-4` 用 MangaDash 1.6.1 真实 AOT、`f00c680` 的原生 Worker、Node 24.15.0 和 Skia Canvas 1.1.1 验证合成 PDF 读章。Source 经隔离 HTTP 各读取一次章节文档和 PDF，生成两页，并从原扩展拦截器交付 250×350 与 200×150 的 JPEG。解码核对第一页的红色及白色区域、第二页两处蓝色区域。PDFium 按需加载一次，章会话和 Worker 均确认关闭，图形句柄归零。实际源站和客户端界面待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在同一台构建机以 Dragon Ball Multiverse 1.6.1 的英文 Source、`f00c680` 原生 Worker、Node 24.15.0 和 Skia Canvas 1.1.1 验证文字布局。隔离 HTTP 提供章节目录、带两段对话的页面与空白 PNG。真实 AOT 经过原图片拦截器生成 320×240 JPEG，两个指定区域分别有 185 和 254 个深色像素，空白区为零。正式二进制交付、章会话及 Worker 关闭通过。源站和客户端界面待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在 `macbook-pro-4` 用同一产品归档和 ManhuaRM 1.6.1 英文 Source 的真实 AOT，通过隔离 HTTP 验证两页合成。原扩展从合成识别结果绘制 360×250 PNG，两个对话区域分别核对黑字和白色描边，外部区域像素保持原底色。无对话页的 996 字节 PNG 与输入逐字节一致。正式二进制交付、章会话和 Worker 关闭通过。构建机直接访问公开热门目录返回 HTTP 403，源站读章及客户端显示待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在同一构建机用 Dragon Ball Multiverse 1.6.1 的英文 Source 和 `f00c680` 原生 Worker 读取真实目录。两次普通 HTTPS GET 分别读取公开目录及第一项《DB Multiverse》的 JPEG 封面，均返回 HTTP 200。目录返回 25 项，封面通道回传的 284,609 字节与源站逐字节一致，Worker 正常关闭。影像验收在 Node 24.15.0 执行，客户端显示与发布待验。[公开目录](https://www.dragonball-multiverse.com/en/read.html)

2026-11-23，冻结目录中仍在产的 Monochrome Scans 遇到上游 KSP 处理错误。在 `macbook-pro-4` 用固定 `f00c680`、同一 Keiyoushi 提交和相同八份材料独立补编，1.6.1 的正式 Gradle、TeaVM AOT、产物完整性和封面入口检查通过，canonical SHA-256 为 `a63050c9449aa79386967a4f37278e487a3a766d052dda801437b4240b3bc848`。隔离 Worker 经一次 GET 完整回传合成封面。装配预检读回同一生产父快照，九个替换包分属五批，1,417 个现网包均保留在 1,448 项计划中。[装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-23，在 `macbook-pro-4` 固定 `58d3411` 与 Keiyoushi `efa93f5a` 补编 MegaTokyo 1.6.1。正式 Gradle、TeaVM AOT、产物完整性及封面入口检查通过，包含 1 个 Source，canonical SHA-256 为 `8d73d3b51211409e885aac5cd61913cbd7ef186dfbfe24b1721e081c3cb47f33`。`pnpm check` 通过。在 Node 24.15.0 中用 `f00c680` 的原生 Worker 载入新 AOT，经该 Source 读取真实首话 HTML 和图片。两次 HTTPS 请求均通过平台证书校验并返回 HTTP 200，一页 80,282 字节 GIF 经正式图片通道回传，Worker 正常关闭。新装配预检读回同一生产父快照，核对六批共十个替换构建及八份共享材料，保留全部 1,417 个现网包。生产发布、客户端显示和实际封面读取待验。[MegaTokyo 首话](https://megatokyo.com/strip/1) · [装配入口](EXTENSIONS.md#首次全量候选的定向补编)

2026-11-23，在 `macbook-pro-4` 使用原生 Worker 和与生产 revision `448797e3feaa477c8ea18f54c6b874bd` 索引相同的两份 AOT，验证普通封面交付。Arknights Comics 1.6.2 从官方热门接口读取《Prelude Suite: The Lone Walker》的封面地址，经正常 TLS 获取 JPEG，正式二进制通道回传 58,121 字节，与源站响应逐字节一致。英文 xkcd 1.6.1 经原 Source 拦截器读到内置的 300×424 PNG，回传 15,307 字节，无源站请求。两次均释放 Worker。测试在 Node 24.15.0 隔离宿主执行，生产登录及客户端显示待验。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-23，在 `macbook-pro-4` 固定 `eaab1ad` 和 Keiyoushi `efa93f5a` 为现网七份材料补编 MegaTokyo 1.6.1。正式构建、完整性和封面入口通过。现网同版原生 Worker 在 Node 24.15.0 使用正常 HTTPS 读回首话 80,282 字节 GIF。正式装配保留原 1,417 个索引条目，Wrangler 4.156.1 dry-run 通过，随后 Worker `a2a4e916-2aa2-4ac1-90da-69e2dc8e6259` 接收 100% 生产流量。公开索引、状态和新增清单逐字节匹配 revision `ac983abafd1d43b49b9f5eb9f8d5c24d`。新增 879,761 字节 gzip 的强 ETag、编码与解码摘要、46 项 Web 资源及匿名 Access 302 通过。生产现有 1,418 个扩展和 2,284 个 Source，剩余 30 个失败输入。构建机提交生产 checkpoint，八材料装配输入已同步父版本并保留十个替换构建。生产认证后读图和实际封面显示待验。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json) · [七材料补编](https://github.com/Wybxc/karuyomi/commit/eaab1ad6f31454d23e6679108e12d8cf8a001925)

2026-11-23，MegaTokyo 发布后的有界规划发现首次装配裁掉了 59 条旧失败记录。用归档的 1,448 份原始回执、19 批补编和正式 `prepare-baseline` 恢复，核对 59 条记录的构建身份和失败详情。新候选共 1,507 条回执，同一主线和上游的有界计划选择 0 项。Wrangler dry-run 后，Worker `d2615968-2271-49ce-9110-29f703e15627` 承接 100% 生产流量。revision `dde7ff44d08140d79aeeaf219aaddf21` 的状态与索引读回一致，扩展索引摘要与上一版相同，46 项 Web 资源和匿名 Access 302 复验通过。[生产扩展索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-23，在 `macbook-pro-4` 用固定 `f00c680` 产品归档预演八材料发布。13 份实际 AOT 包含冻结队列的三个图像处理扩展和六批十个替换构建。正式快照组装、Vite 打包与 Wrangler 4.156.1 dry-run 通过。Wrangler 回环服务读回索引、状态、根页面、13 份清单及 gzip 产物，以及含 PDFium 的八份共享材料。逐项核对响应字节与 MIME，并确认五个扩展声明 Source 输入能力。样本共 55 个 Source，快照仍为未完成基线。完整队列、正式发布及客户端现场待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在 `macbook-pro-4` 固定 `017e214` 及 Keiyoushi `efa93f5a` 编译 ToonLivre 1.6.90。正式构建、完整性和封面入口检查通过，canonical SHA-256 为 `8e1991c16178fc5a7ebb84a3d39b48c53e96af976a89b653f1d290b1824f1c99`。固定 `f00c680` 原生 Worker 与 Node 24.15.0 通过正常 TLS 读回 24 个线上目录项，并完整回传官方 CDN 的 98,538 字节 WebP 封面。隔离章页接口核对原扩展筛选、去重和排序后返回两页，验证要求触发时返回官方阅读器提示并仅发送一次受控请求。另一次只读在线试验读到同一作品的目录与详情，所选章节的章页请求返回 HTTP 404。候选装配预检确认七批十一个替换构建、八份共享材料与全部 1,418 个现网包。生产发布、真实读章和验证交互待验。[上游公开入口](https://toonlivre.net/)

2026-11-23，在 `macbook-pro-4` 固定 `6035114` 与同一 Keiyoushi 上游补编 SpyFakku 1.6.2。按官方 JVM 产物修正客户端配置方法的保留签名后，正式构建、完整性及封面入口检查通过，canonical SHA-256 为 `08fb749c67d035c17e3f25e5ae74cb34d1109988da00b68e374938f673ecd053`。真实 AOT 从默认站用平台 TLS 读回 24 个目录项。隔离测试核对原图片拦截器的 HTTPS 路由及 68 字节 PNG 回传，另用原镜像设置验证触发浏览器提示时仅发送一次受控请求。预检合入两包后共有八批十二个替换构建，保留全部现网包与八份共享材料。真实镜像、源站读章及生产发布待验。

2026-11-23，在 `macbook-pro-4` 固定 `bd90453` 与 Keiyoushi `efa93f5a` 补编爱看漫 1.6.2、ReiManga 1.6.9。原扩展固定 HTTP/1.1 的调用改由中继采用平台协商，原 Cookie 和拦截器继续参与请求。爱看漫实测同一目录在 HTTP/1.1 和 HTTP/2 下均返回 200。用 `f00c680` 原生 Worker 和 Node 24.15.0 执行真实 AOT，从源站返回 48 项，后两次请求携带原 Source 会话 Cookie，封面通道交付的 142,760 字节 JPEG 与源站一致。ReiManga 的真实目录返回 403，隔离响应验证原 Cookie、目录解析及 68 字节 PNG 回传。各次 Worker 关闭均获确认，应用界面与生产发布待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，同一提交的 TempleScan 1.6.64、Cosmic Scans ID 1.6.3 和 CodeArc 1.6.4 通过正式 AOT、完整性与封面入口检查。TempleScan 的真实 `/comics` 返回 307 并引导至站点验证，Source 返回官方浏览器验证提示。隔离测试复现提示并确认请求止于三次 GET。另两包分别通过固定原生 Worker 初始化，报出一个 Source 及封面能力，均已获关闭回执。五个定向补编输入保持 `compiled_unverified`，装配预检确认九批十七个替换构建、相同八份共享材料及全部 1,418 个现网扩展。读漫屋、如漫画的公开目录在同台机器正常 TLS 下分别遇到握手和证书校验错误。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，固定 `bd90453` 的十四包定向补编在 `macbook-pro-4` 收齐全部回执。十三包正式 AOT 成功，WebtoonLib 在冻结图形材料下缺少 `TextPaint.setLetterSpacing`。Toonkotsu、Coffee Manga、EmperorScan、HentaiCube、MangaCloud、LxHentai、LunarAnime 和 Koharu 的八个真实产物在 `f00c680` 原生 Worker 与 Node 24.15.0 完成初始化、封面能力登记及关闭。Toonkotsu 与 Coffee Manga 的真实目录各返回 403。预检按实际包名纳入全部十三包和十八个 Source，替换总数增至九批二十五个，当前 1,418 个生产包均在完整计划内。各包保持 `compiled_unverified`，真实客户端显示及候选发布待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在 `macbook-pro-4` 固定 `c503abb` 和 Keiyoushi `efa93f5a`，读漫屋和如漫画 1.6.1 通过正式 AOT、完整性及封面入口检查。固定的 MMLook 使用平台证书校验，保留原扩展禁止自动跟随重定向的策略和原 URL 的协议。以 `f00c680` 原生 Worker 和 Node 24.15.0 运行真实产物，隔离目录各返回一项，读漫屋与如漫画分别保留无斜杠和带斜杠的作品引用，封面各回传完整的 68 字节 PNG。302 测试各只发出一次 GET。真实请求分别遇到 `ECONNRESET` 与 `ERR_TLS_CERT_ALTNAME_INVALID`，各次 Worker 均获关闭回执。两包保持 `compiled_unverified`。装配核对十批二十七个精确替换、原八份材料及全部 1,418 个生产包。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，发布前从 `macbook-pro-4` 恢复固定 `f00c680` Web 和运行材料归档。归档实际 SHA-256 与已确认摘要一致，原八份共享材料逐字节一致。本机 Wrangler 4.156.1 的 OAuth 登录可用，只读核对 Worker `d2615968-2271-49ce-9110-29f703e15627` 承接 100% 流量，D1 已应用 13 个迁移至 `0012`，待应用列表为空。增量发布工作流处于停用状态，无执行中的增量任务。完整候选、切流和登录后读取待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，M4 冻结批次收齐 Keiyoushi `efa93f5a` 的 1,448 份正式回执。原 27 个精确替换产物和 26 份被替换的失败回执均经正式装配核对。八材料 revision `ac464cf6987d4e25a556bd7b695a7c2d` 包含 1,444 个扩展和 2,357 个 Source，保留原有 1,418 个扩展。逐包检查确认全部交付构建均导出封面入口。四个 AOT 失败保留诊断，分别是 Comix、WebtoonLib、Japscan 和 Scan-Manga。

2026-11-23，固定 `f00c680` 的正式 Web 归档与八材料扩展通过 Vite 和 Wrangler 4.156.1 dry-run。最终生成的配置与前一版路由和绑定一致，D1 没有待应用迁移。上传版本后复核原流量，再将生产流量全部切到 `de1f87d0-4aae-4555-ad01-79aab4ca6d47`。公开状态和索引逐字节匹配候选，核对 47 项 Web 资源、匿名 Access 302，及 Arknights Comics、xkcd、爱看漫、ToonLivre、Dragon Ball Multiverse、读漫屋和如漫画的清单、gzip 传输合同与压缩前后摘要。本机和 M4 均保存了从生产读回确认的检查点。1,444 份公开清单逐字节匹配，所有 gzip 的强 ETag 与锁定 Wrangler 的上传指纹一致，MIME、编码和缓存头符合交付合同。已确认状态覆盖全部 1,448 个有效输入，有界重放选择 0 项。原冻结计划单独重放时仍选择被替换的 Doujin.io 原成功输入。生产登录后的封面显示及读章待验。[公开索引](https://karuyomi.wybxc.cc/extensions/index.json) · [合并 PR #9](https://github.com/Wybxc/karuyomi/pull/9)

2026-11-23，从已确认的生产检查点在 M4 启动下一版图形材料的四路全量 AOT，冻结同一上游的 1,448 个输入，复用 WebtoonLib 1.6.1 的精确回执。该包的专题回归验证了隔离 HTTP 下的三页读章、字距和图片交付。下一版材料尚待完整装配及发布。[专题验收](https://github.com/Wybxc/karuyomi/blob/440fbf716595cff033606934884067560aab7f9b/docs/verification/text-layout-runtime.md#webtoonlib-字距)

2026-11-23，主线 `193d1d8` 的工程检查、Wasm 与发布作业全过。自动发布保留 revision `ac464cf6987d4e25a556bd7b695a7c2d`，Worker `20bce439-01e8-40ba-b523-c700498a84a8` 接收全部流量。线上 47 项 Web 资源、匿名 Access 302 以及扩展状态与索引逐字节读回通过。[主线发布](https://github.com/Wybxc/karuyomi/actions/runs/45072299200)

2026-11-23，在 M4 使用固定 `f00c680` 的原生 Worker 和 Node 24.15.0，直接载入生产公开索引内的实际清单与 AOT。爱看漫 1.6.2、英文 Dragon Ball Multiverse 1.6.1、ToonLivre 1.6.90 各从真实源站读回热门目录及一张封面。分别得到 48、25、24 条作品及 142,760 字节 JPEG、284,609 字节 JPEG、98,538 字节 WebP。图片通道回传字节与各源站一致，三个 Worker 均获关闭回执。Komiic 1.6.11 的默认站在公开目录查询中返回连接重置。隔离会话注入 Source 自带的已确认镜像值 `preferred_mirror=1` 后，原扩展从 `komiic.cc` 读到 30 项，并经原拦截器从 `public.komiic.cc` 取回 25,646 字节 JPEG，与响应逐字节一致。两次 Komiic Worker 均确认关闭。该轮用正常 HTTPS 和原 Source 请求，验收环境是 Node 隔离宿主。生产登录后的 Flutter 显示待验。[生产索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-23，将下一版 `afbf310` 的正式 CI Web 和 Native 归档保存到 M4。24,903,827 字节归档的 SHA-256 为 `d2c2eed0bfea81bf764b4d8b7f048886c99a577586e5c7ccaf3d84daa6ae591e`，本机下载及构建机接收两端均与官方归档摘要一致。归档包含正式 Web 入口、Native Worker 和八份运行材料，每份材料的大小和摘要均匹配活动队列的材料清单。下一版仍待 1,448 个输入的正式回执、全量装配与生产发布。[下一版 CI](https://github.com/Wybxc/karuyomi/actions/runs/45069123305)

2026-11-23，在 M4 独立 checkout 还原 `afbf310` 正式归档，用冻结计划里的 WebtoonLib 1.6.1 精确回执完成隔离装配、Vite 和 Wrangler 4.156.1 dry-run。官方 Workerd 测试宿主核对 47 项实际静态资源、索引和状态字节、清单、gzip 传输头及压缩前后摘要，匿名 API 返回 `401 access_required`。隔离候选仅纳入一包，剩余 1,447 个输入待构建，1,444 个旧材料构建在该候选中标记为 `unavailable`。生产父状态读回与已确认检查点逐字节一致。完整目录发布及真实页面待验。[配套 CI](https://github.com/Wybxc/karuyomi/actions/runs/45069123305)

2026-11-23，复核 Keiyoushi `92906c0` 的 Comix 1.6.65、Japscan 1.6.3 和 Scan-Manga 1.6.4。M4 的普通 HTTPS 请求读到 Comix 目录 HTML 7,312 字节，其中作品详情链接和图像均为 0。上游热门目录仍通过 `runInWebView` 获取。Japscan 和 Scan-Manga 的同版公开热门路径分别返回 HTTP 403 和 404，两包的章节入口仍进入 Android WebView 流程。已有材料的三个 AOT 失败保持在生产账本中。[固定上游](https://github.com/keiyoushi/extensions-source/commit/92906c0382547f30a03b3176f2f2429be6b54dce)

2026-11-23，下一版扩展并发构建中，Fansubs.cat 与 Bakkin 的上游 Gradle 任务均因共享 Kotlin 增量缓存重复注册失败。M4 固定 `1f17b74` 和同一 Keiyoushi `efa93f5a`，在独立 checkout 同时构建共用主题库的 Fansubs.cat 1.6.1 与 Hentai.cat 1.6.1，观察到两个各自独立的主题库 Kotlin 构建目录同时存在。两包及随后补编的 Bakkin 1.6.1 均通过正式 Gradle、TeaVM AOT、产物完整性和 `hostAcquireCover` 导出检查，各有 1 个 Source。八份共享材料逐字节匹配冻结批次。补编预检在父 revision `ac464cf6987d4e25a556bd7b695a7c2d` 的 1,448 项计划中选择 Fansubs.cat 和 Bakkin，原有成功的 Hentai.cat 回执可直接使用。三包均为 `compiled_unverified`。完整装配及生产显示待验。[构建隔离修复](https://github.com/Wybxc/karuyomi/commit/1f17b74c30181c90dbc2b96f61bbf8a63421c064)

2026-11-23，新材料冻结队列及独立补编的 VIZ Shonen Jump 1.6.31 在 Maven Central 下载 `kim:0.32.0` 时发生 TLS 握手中断。标准 TLS 1.2 的试编取到该依赖，随后三个传递依赖握手仍中断。M4 在固定的 `1f17b74` checkout 直接复用已结束的八材料生产构建的 Gradle 依赖目录后，官方 Gradle、TeaVM AOT、完整性和封面导出通过。产物 canonical SHA-256 为 `d6bd647c65528d813a41909c439509113c113a54dce25840a9e743d41b8a994a`。匹配的 `fef3df5` 正式 Native Worker 登记了 VIZ Shonen Jump、VIZ Manga 和封面能力，并确认关闭。恢复原目录链接后，五包补编方案通过 1,448 项装配预检。候选保留原失败回执并选用新成功构建。VIZ 仍标记 `compiled_unverified`，实际目录、封面和阅读待验。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，用 `fef3df5` 的正式 Native Worker 和 VIZ 1.6.31 补编包在 M4 执行两次源站热门目录查询。VIZ Shonen Jump 和 VIZ Manga 都由出版社返回 HTTP 302 跳转到各自服务首页，随后原 Source 报告地区不可用。四次请求为普通匿名 HTTPS GET，项目中继正常传回状态，两次 Worker 均确认关闭。该轮未取得作品目录和封面，扩展仍标记 `compiled_unverified`。[出版社公开目录](https://www.viz.com/manga-books/shonenjump/section/trending-manga)

2026-11-23，冻结队列的 Mangas.in 1.6.4 在 Kotlin 编译时无法解析共享 `synchrony` 库及 `Deobfuscator` 类。M4 在固定 `1f17b74` 的独立 Gradle checkout 保留同一上游源码闭包，正式 Gradle、TeaVM AOT、完整性和封面导出通过。canonical SHA-256 为 `5dbc179cdeb3861d59c712d51e41a4257d4c37c9dfaff9b9b959d2b306c8b8bc`。使用 `fef3df5` 正式 Native Worker 初始化 1 个 Source，登记封面能力并确认关闭。预检确认第六个替换构建与冻结批次的八份运行材料完全一致，完整装配计划仍覆盖 1,448 项。源站行为未测，产物保持 `compiled_unverified`。[全量升级计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，M4 固定 `28a32ec` 与 Keiyoushi `efa93f5a` 补编 Japscan 1.6.2 和 Scan-Manga 1.6.1。AOT 兼容层对两项固定输入报告宿主无法启动原 Android 阅读器 Activity，并保留原扩展已有的验证提示。正式 Gradle、TeaVM AOT、产物完整性及封面导出均通过，canonical SHA-256 分别为 `d32b6cccebc3ff5eb6e33dd103658bd40c227c581bcff284cdbeb9df5e03a030` 与 `3588ccbc0a122fae4f4e9c3e781be1250e095233bef358142fa77c751bfe30b0`。八份共享材料与冻结批次逐字节匹配。M4 在 Node 24.15.0 中用同材料正式 Native Worker 归档加载两包，各登记 1 个 Source 和封面能力，并取得关闭回执。两包保持 `compiled_unverified`。本机普通 HTTPS 复验中，Japscan 的热门目录返回 403，Scan-Manga 的热门目录及移动站首页均返回 404，源站封面和读章仍待验。[宿主适配](https://github.com/Wybxc/karuyomi/commit/28a32ec78f35ed9bc8641c873f3381617bf8b49d)

2026-11-23，M4 上的 `afbf310` 原冻结队列先后写入 Japscan 和 Scan-Manga 的 AOT 失败回执，均缺少 `Application.startActivity(Intent)`。逐项核对原始指纹、同一上游源码闭包、`28a32ec` 补编回执和八份共享运行材料，并将两份 Native 初始化、封面能力和关闭记录绑定到最终装配计划所选的精确构建。两份原失败保留诊断，补编保持 `compiled_unverified`。[装配计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，在 M4 用 `fef3df5` 的正式 Native Worker、Node 24.15.0 和项目 HTTP v2 中继加载两份真实补编产物。Japscan 1.6.2 的热门和最新各收到源站 HTTP 403。Scan-Manga 1.6.1 的热门、最新和原站搜索均收到 HTTP 404。五次请求为普通匿名 HTTPS GET，中继完整传回源站状态，两次 Worker 初始化、封面能力登记和关闭通过。目录没有封面地址可交付，两包保持 `compiled_unverified`。[实施计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，PR #10 的 `fef3df5` 工程检查和 Wasm 构建通过。官方 Web 与 Native 归档为 24,903,831 字节，下载与 M4 收件的 SHA-256 均为 `0da7dcbbbb71376a87d4af72ba76087d3d5cb372ff659a7a9ffc887c414482f9`，八份共享运行材料逐字节匹配活动队列。M4 从现网父 revision `ac464cf6987d4e25a556bd7b695a7c2d` 隔离装配 WebtoonLib、Fansubs.cat、Bakkin、Japscan 和 Scan-Manga，Vite 和 Wrangler 4.156.1 dry-run 通过。官方 Workerd 读回核对 47 项 Web 静态资源、索引、状态、五份清单及 gzip 编码摘要，匿名 API 返回 `401 access_required`，私有 Native Worker 路径返回 404。该候选的 `bootstrap.complete` 为 `false`，1,443 个原计划输入等待完整装配。[配套 CI](https://github.com/Wybxc/karuyomi/actions/runs/45086073766)

2026-11-23，在 M4 用 `fef3df5` 的正式 Native Worker 归档、冻结批次的实际 AOT 和项目 HTTP v2 二进制中继验收英文源。隔离 Node 24.15.0 脚本起初误将 Worker 的 `trace` 消息当成重复握手，修正消息分发后重新验收。MangaDex 1.6.1 从源站读取 20 项热门作品并回传一张 1,887,651 字节 JPEG，与源站响应逐字节一致。xkcd 1.6.1 从源站读取热门目录，经原拦截器回传 15,307 字节的扩展内置 PNG。MANGA Plus 1.6.68 的热门接口两次返回 HTTP 200，复验正文为 4 字节 Protobuf，其中顶层字段 2 表示错误，原 Source 无目录结果。Webtoons.com 1.6.3 读回 30 项作品，两次封面请求都在 `webtoon-phinf.pstatic.net` 超时。四个扩展均获关闭回执并保持 `compiled_unverified`，生产登录后的 Flutter 显示待验。[配套 CI](https://github.com/Wybxc/karuyomi/actions/runs/45086073766)

2026-11-23，用 PR #10 的 `fef3df5` 正式材料和当前生产 revision `ac464cf6987d4e25a556bd7b695a7c2d` 实测主线自动发布的快照复用入口。读取生产 index、构建状态和四份扩展清单后，在下载任何扩展包之前返回 `unknown_material`。归档中的材料版本为 `82075df16ebee9db465f4d014e9e8be43f2060194d852dabd7dd332525d908f4`，与当前冻结批次逐字节一致。GitHub 合并预览 `fe3d0a9` 的文件树摘要 `1f560d8f222e1acdd53cc4667a951f142ab214d7` 与通过 CI 的 PR 头一致。验证期间生产继续服务原快照。完整候选装配和生产切流待验。[PR #10](https://github.com/Wybxc/karuyomi/pull/10)

2026-11-23，`macbook-pro-4` 收齐冻结 Keiyoushi `efa93f5a` 的 1,448 份正式回执，采用六份同材料补编替换原失败后，候选包含 1,447 个扩展和 2,360 个 Source，保留全部 1,444 个现网包。逐包核对了 1,447 个封面入口。固定 `fef3df5` 的正式归档通过 Vite、Wrangler 4.156.1 dry-run 和 Workerd 对全部清单及安装包路径的核验。合并 PR #10 后，主线 `2cc9bbe` 文件树与该归档源码一致。Worker `362cb66d-ce65-46e7-848f-d1ce55c83343` 接管 100% 生产流量，revision 为 `e9e23f4bbeea46f7b21807f25e18cf39`，索引 SHA-256 为 `b43e906bd8e3b23c1ef3147de255a3de00589472d75709cad6095ec744be2cc1`。公开索引和状态逐字节匹配，1,447 份清单、1,447 个 gzip 强 ETag、47 项 Web 资源及匿名 Access 302 全部通过。WebtoonLib、Japscan 和 Scan-Manga 的线上 gzip 与解码摘要均通过，三包保持 `compiled_unverified`。D1 待迁移为空。Comix 仍因 WebView 相关 AOT 兼容缺口无法分发，登录生产页面后的实际出图待验。[PR #10](https://github.com/Wybxc/karuyomi/pull/10) · [生产索引](https://karuyomi.wybxc.cc/extensions/index.json)

2026-11-23，本机与 `macbook-pro-4` 均通过正式 `commit-snapshot` 写入 `e9e23f4bbeea46f7b21807f25e18cf39` 的已确认检查点。使用同一生产状态和固定上游，构建机以原冻结宿主运行有界规划时选择 0 项，采用合并代码的宿主输入时选择上限 12 项，另有 1,434 项等待按新指纹重编。定时增量工作流保持手动停用，本次只验证规划。[增量发布计划](plan/engineering-and-release.md#封面宿主全量升级)

2026-11-23，主线 CI 的首次自动发布在下载扩展时遇到 `ECONNRESET`。保留成功的工程和 Wasm 检查，重跑失败的发布任务后，CI 确认同一 1,447 包快照、47 项 Web 资源和匿名 Access 302。Wrangler 读回 Worker `159bf300-645f-4d78-b6f1-02a948fa75bf` 接收 100% 流量，公开索引与构建状态仍逐字节匹配 `e9e23f4bbeea46f7b21807f25e18cf39`。主线归档与首次切流归档的 45 项 Web 资源字节一致，差异位于 `flutter_bootstrap.js` 和 `precache_manifest.json`。2026-11-24 再次读回现网，确认这两份文件、共享材料清单及三个新增包的强 ETag 都与最终证据一致。[主线 CI](https://github.com/Wybxc/karuyomi/actions/runs/45196034775)

2026-11-24，在 `macbook-pro-4` 以普通 HTTPS 复核 Comix 的公开数据。热门目录返回 200，初始 HTML 中作品链接和结构化作品记录均为 0。`robots.txt` 声明的站点地图包含 113 个分片。第一个作品分片有 1,000 个链接，每项提供 `loc`、`changefreq` 和 `priority`，图片记录为 0。抽查第 1、501 和 1,000 个作品页，均返回 200 和标题元数据，封面元数据、图片元素和章节链接均为 0。Keiyoushi 的 Comix 目录最新提交仍为 `92906c0`，原扩展的目录及详情请求仍依赖 Android WebView。现有 Native 可见 WebView 绑定应用的 Access 登录，Source 的浏览器桥返回 `unsupported_capability`。Comix 待取得可用的目录、封面和阅读通道后继续正式复编与分发。[公开站点地图](https://comix.to/sitemap/index.xml) · [Source 浏览器桥](../packages/runtime-host/src/teavm-driver.ts) · [固定上游](https://github.com/keiyoushi/extensions-source/commit/92906c0382547f30a03b3176f2f2429be6b54dce)

2026-11-21，固定 `92a0059` 的正式 Flutter Web 在 Codex 内置浏览器、隔离 Workerd 和 D1 验收。本机外观改浅色后重开仍为浅色，主题修改前后的 `/api/settings` 响应逐字节相同。关闭验收服务后，已加载页面仍可切换为深色。图像适配点选「适宽」后，界面自动显示服务端已确认，独立请求读回 `READER_FIT_WIDTH`，全局设置版本由 1 到 2。该轮使用一份浏览器资料，原生现场仍按已有安排暂停。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，隔离 Web 以真实 Arknights Comics 1.6.2 显示 17 张热门封面。在 `dac2e7b` 打开《Prelude Suite: The Lone Walker》，1280×900 下显示列表与详情，将窗口缩到 390×800 后保留同一详情及三章列表。冷启动书架曾因宿主第二槽关闭图片交付而显示占位，`65c63fd` 修复后在新文档显示真实封面。该轮复用固定宿主输入重编的 671,269 字节 gzip，canonical SHA-256 为 `09528e68a34e3fe49030e5a0482081db119672d9852524688981f8164a55d0dc`。108 项 Flutter 定向回归及 95 项宿主与合同回归通过，包含 Native 受管文件和槽身份校验。扩展仍按原发布流程验证和分发。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，`65c63fd` 正式 Web 跨源搜索 `Prelude Suite` 返回五项，其中四项显示真实封面。《Prelude Suite: Keen-Edge, Silver Blade》保持占位。带本机诊断日志的同功能构建曾显示五张。将获取期限临时放宽到 15 秒仍复现一张占位，该作品的正式详情和两章列表可打开。分支沿用 10 秒单张获取期限，个别缺图原因另行核验。完整工程及 Web/Wasm 构建通过。[GitHub Actions](https://github.com/Wybxc/karuyomi/actions/runs/44904585608)

2026-11-21，书架、跨源结果和迁移候选接入普通封面。164 项 Flutter 定向回归、95 项运行宿主与合同测试、10 项跨语言协议测试通过。组件测试通过真实 Flutter 解码受管测试文件，同一作品源的两张书架封面复用第二槽并释放两份资源，账户写入数与基线一致。双槽测试核对搜索启动前按原请求身份取消封面并确认临时会话关闭，取消等待中的封面时保留两个活动搜索会话。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，固定 `92a0059` 与锁定 Keiyoushi 源码在本机 Apple Silicon 独立重编 Arknights Comics 1.6.2。正式工具用官方 JAR 生成 671,300 字节 gzip，canonical SHA-256 为 `4dc463ca25b497c28deec4bea7608f368c01bdee2519580d84ca6741539b5df1`，产物完整性通过并组装单包 Static Assets 验收快照。候选保持 `compiled_unverified`、`runtimeReady=false`。[扩展构建和静态分发](EXTENSIONS.md)

2026-11-21，普通封面接入单源浏览和作品详情。71 项 Flutter 定向回归和本机全量 1,025 项 Flutter 测试通过，覆盖受管文件交付、Flutter 解码、释放与自定义封面清除后的回退。34 项运行宿主及 10 项跨语言协议测试通过。`pnpm teavm:check` 在 JVM 受控 HTTP 服务验证 Source 请求携带 Referer 与已有 Cookie，拦截器修改的字节到达图片接收器。真实扩展的新版 AOT 与在线封面待验。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，Cupertino 自适应布局通过 112 项 Flutter 定向回归。组件在手机、短横屏、平板及桌面尺寸验证主导航位置、大字号、焦点和设置连接草稿。书架和 Source 详情从 1280×900 缩至 390×800 后保留同一页面，恢复宽屏重新并排，切换尺寸和返回时业务写入数保持一致。实际浏览器与原生窗口待验。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，本机阅读设置通过 134 项 Flutter 定向回归、68 项 Workerd 与合同测试和 10 项跨语言协议测试。应用测试使用内存偏好和模拟服务，验证按部署与作品继承、0% 覆盖、重开恢复及同一阅读页应用本机值。只修改背景和输入时账户设置请求数保持不变。隔离 D1 验证清除旧设备字段后保留账户版本及原单漫画回执。浏览器配置和原生存储现场待验。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，账户设置自动保存通过 100 项定向 Flutter 回归。模拟服务暂扣首条回执时，多次修改合并成下一条写入。丢回执后，显式重试复用原正文，随后保存余下修改。另核对账户替换、冲突重读、设置页重开与缩放、Source 普通文本键盘完成及密码显式确认。原生集成驱动已按逐项确认更新，现场执行与上线路径仍待验。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，本机主题阶段通过 264 项 Flutter 定向回归、严格 Dart 分析、TypeScript 类型检查、10 项跨语言协议测试和 52 项 Workerd 测试。组件用内存偏好和模拟服务验证未连接时修改主题、写失败重试、重建客户端恢复及切换账号零账户写入。隔离 D1 验证旧主题移除后原单漫画设置命令仍精确重放，阅读偏好和版本不变。独立浏览器资料与原生平台的持久存储待验。[实施计划](plan/device-settings-adaptive-covers.md)

2026-11-21，正式 Web 双主题验证章节筛选框失焦后有独立的无障碍名称，组件验证章节计数随筛选更新。真实 xkcd 筛选后首次快速到底并回顶，两色仍有 489 逻辑像素的 DOM 坐标偏移，重建的文本输入丢失 DOM 值。浅色按角色定位点击失败，按画面位置可操作。Web JS/Wasm 构建通过。[章节筛选语义实测](verification/mihon-cupertino-fidelity.md#作品详情的章节筛选语义与滚动偏移)

2026-11-21，`e013fb2` 的双主题正式 Web 核对真实 xkcd 章节日期、滚动后的 11 项筛选及短屏六章确认。取消后保留原末行，七路权威读回与基线一致。深色暂扣首项回执时界面显示 0/6，D1 已提交 3325。放行后两色各完成 3325–3320 六章，浅色新文档读回同一组。1019 项 Flutter 测试、改动文件严格 Dart 分析及 Web JS/Wasm 构建通过。浏览器回顶后部分 DOM 语义坐标偏移仍待查证。[短屏六章实测](verification/mihon-cupertino-fidelity.md#作品详情的章节筛选与短屏六章确认)

2026-11-21，`b3b2db7` 的双主题正式 Web 复验跨源搜索。两色打开语言页期间收到真实 MangaDex 的 20 项和一次受控 xkcd 失败，返回后可用 Enter 重开语言页。长名单连续两次到底回顶后保留名称筛选和原勾选。两色真实分页到 34 项，随后 xkcd 独立重试返回空结果。每轮五路权威读回一致。1018 项 Flutter 测试、严格分析、依赖规则与 Web JS/Wasm 构建通过。[跨源搜索实测](verification/mihon-cupertino-fidelity.md#跨源搜索的语言返回与筛选保留)

2026-11-21，`efd402a` 的正式 Web 双主题复验英文 MangaDex。切到「最新」后，所请求的分段可读，进度在内容区中央，随后两色取得真实作品。360×480 追加失败后可直接重试，前后原末排均在 y=149，新取得 20 项。两色各自七路权威响应逐字节相等。1017 项 Flutter 测试复跑通过，严格 Dart 分析及 Web JS/Wasm 构建通过。正式浏览器使用 JS 产物与默认字号。[源内浏览分页实测](verification/mihon-cupertino-fidelity.md#源内浏览的最新等待与分页重试)

2026-11-21，`e95e712` 正式 Web 在 Codex 内置浏览器复验英文 xkcd 3324 的两色阅读滑杆。指针留在原轨道时从 360×480 缩至 844×390，滑杆短暂禁用，再自行恢复原焦点及蓝色焦点环。Home 与 End 可直接跳页，主动按 Tab 或打开阅读菜单后焦点留在新控件。两色各确认九次阅读进度，独立 D1 读回当前第 1 页。1013 项 Flutter 测试、严格 Dart 分析及 Web JS/Wasm 构建通过，浏览器实测使用 JS 构建。系统双倍字号与原生待验。[滑杆焦点实测](verification/mihon-cupertino-fidelity.md#缩高时页码滑杆的键盘焦点)

2026-11-21，`62646c7` 的正式 Web 双主题复验真实 xkcd 3324 的章间按钮、方向回执，以及 3322 的拖动或点按跳页、键盘恢复及新文档续读。两色新文档均恢复第 2 页，各有六路前后读回一致。深色 3324 缩短视口高度时原滑杆失焦，重新 Tab 后 Home/End 正常。首轮标准 HTML 和 Cupertino 滑杆对照均保留焦点，随后在原指针位置重现并修复。[阅读器现场复验](verification/mihon-cupertino-fidelity.md#正式-web-的页码滑杆与章间按钮复验)

2026-11-21，`f30a345` 的正式 Web 在恢复控制的 Codex 内置浏览器中复验英文 xkcd 热门与短屏搜索。首封面的左缘及尺寸与 Mihon 相同，以导航标题中心为原点时上缘只差 1 逻辑像素。两色提交、收起与清除均通过，深色修正后的热门选中字清晰。四路账户读取前后相同，仅会话有效期按签发时刻变化。1013 项 Flutter 测试、严格 Dart 分析与 Web release 构建通过。最新和追加的正式 Web、系统软键盘及原生待验。[源内浏览与短屏搜索](verification/mihon-cupertino-fidelity.md#源内浏览紧凑网格与短屏搜索)

2026-11-21，`12eeb56` 对照 22.03 将章间动作改为两端的 Cupertino 圆形按钮。浅深组件在 360×480 双倍字号的滑杆宽度由 114.7 增至 175，页码恢复单行。长页码另起一行时保留轨道位置与键盘焦点，缺少相邻章仍提供禁用语义和长按说明。1007 项 Flutter 测试与 Web release 构建通过，正式 Web 和原生现场待验。[大字号页码工具区](verification/mihon-cupertino-fidelity.md#阅读页码工具区在大字号下的布局)

2026-11-21，`6b424c5` 的阅读快捷设置在服务端回执前维持已确认的菜单值、翻页方向和画布。在 360×480、844×390 双倍字号中，两色均可看到等待并继续翻页。短屏丢回执后可直接重试，两色组件实测原样重试确认后第 2、3 页才并排。1006 项 Flutter 测试与 Web release 构建通过，正式 Web 与原生现场待验。[阅读快捷设置](verification/mihon-cupertino-fidelity.md#阅读快捷设置的确认布局与短屏反馈)

2026-11-21，`6df9704` 对照 Mihon 18.01 将章节多选的上栏与标记动作固定在列表两端。两色组件的选中行覆盖 x=0–360，未读标题左缘为 x=30。360×480 两倍字号从末章直接打开确认，取消后保留选择和滚动位置，点按退出或系统返回均留在详情。1006 项 Flutter 测试与 Web release 构建通过，正式 Web 与原生实拍待验。[章节多选](verification/mihon-cupertino-fidelity.md#章节多选的固定操作栏)

2026-11-21，`7e4fc47` 将 Source 日期放到章节次级资料首位。对照 17.01 的四个 xkcd 章节，两色 Flutter 组件的日期值和左缘与参考相符。回归覆盖本地日期边界、两倍字号、日期缺失及刷新失败后重试。1004 项 Flutter 测试与 Web release 构建通过。真实 Source 的新版正式 Web 待验。[章节日期](verification/mihon-cupertino-fidelity.md#章节发布日期和刷新回执)

2026-11-21，`11c1ed1` 的双主题章节组件将未读标题左缘从 x=80 移到 x=30，已读标题和次级资料移到 x=16，相邻标题间距从 48 增至 68 逻辑像素，与 Mihon 17.01 的对应边界一致。点按禁用书签不再打开章节，恢复后仅写入点按的重复条目。1003 项 Flutter 测试及 Web release 构建通过。正式 Web 同版渲染待验。[章节布局与独立书签](verification/mihon-cupertino-fidelity.md#章节列表的对齐与独立书签)

2026-11-21，`0d7b34d` 将跨源分页移动到源标题旁，浅深组件中第二组标题上缘由 y=511 移至 y=439，Mihon 参考为 y=433。360×480 两倍字号复验等待、失败与重试，操作和首排位置保持。1002 项 Flutter 测试及 Web release 构建通过。内置浏览器连接超时，正式 Web 分页待验。[源间距与分页](verification/mihon-cupertino-fidelity.md#跨源搜索源间距与分页回执)

2026-11-21，`da3ca05` 的两色 Flutter 组件复验将跨源搜索首个封面上移 113 逻辑像素至 y=242，Mihon 参考为 y=241，标题左缘同为 x=16。两倍字号下提交与查询仍同排，等待和返回的源标题位置一致。998 项 Flutter 测试和 Web release 构建通过。第二组及真实 Web 继续验收。[首排作品量测](verification/mihon-cupertino-fidelity.md#跨源搜索首排作品量测)

2026-11-21，`e39b5ef` 修复跨源搜索打开语言选择页期间的回执丢失。两色组件从原页返回后都保留原选源，焦点回到语言行，正常显示一项结果及另一个源的失败。998 项 Flutter 测试、严格分析和 Web release 构建通过。重复滚动在组件环境的视觉与语义边界相等，内置浏览器连接超时，正式 Web 复验待验。[语言选择页返回](verification/mihon-cupertino-fidelity.md#语言选择页返回时的跨源搜索回执)

2026-11-21，`872a121` 的正式 Web 两色从短屏长选源名单末端通过空词校验及真实 xkcd 搜索。结果回顶后可重新展开范围并读回原勾选。深色 844×390 可用 Enter 提交，两色三路权威状态逐字节相等。996 项 Flutter 测试及严格分析通过。MangaDex 超时，重开范围后的重复滚动另有语义偏移待验。[跨源搜索短屏](verification/mihon-cupertino-fidelity.md#跨源搜索短屏与重新选源)

2026-11-21，`3e25459` 正式 Web 复验两色五个设置栏目。切为双栏时焦点从即将消失的返回交给当前栏目，缩成短横屏时交回详情返回。草稿在换栏与返回后重进仍保留，导航快照逐字节相同，明确保存后各写入一次且新文档读回。994 项 Flutter 回归、严格分析及正常 Web 构建通过。[设置分栏焦点](verification/mihon-cupertino-fidelity.md#设置分栏切换与键盘焦点)

2026-11-21，`a899954` 的书架浅深两色在 360×480 滚到末端仍显示已选、隐藏数量和退出，深色旋转到 844×390 后以 Enter 退出。两色从末端打开移出清单，取消前后账户与完整分页相同；随后各确认两项分类写入，新文档读回。992 项 Flutter 回归、严格分析及正常 Web release 构建通过。[书架选择栏短屏](verification/mihon-cupertino-fidelity.md#书架选择栏与批量预览的短屏复验)

2026-11-21，`71bc54e` 的正式 Web 浅深两色在白画布调暗 80% 时实测 xkcd 3321 同页等待、受控失败、短屏重试及新文档续读。失败文字采样对比约 12.63∶1，等待与失败的七路读回完全相同。两色连续阅读的图片查看器通过放大、复位和短横屏同页关闭。73 项 Flutter 定向回归通过。[单页与图片查看证据](verification/mihon-cupertino-fidelity.md#双主题正式-web-的单页失败与图片查看)

2026-11-21，`7925a84` 的正式 Web 浅深两色在 844×390 下从 MangaDex 详情的源列表末端完成取消准备、清单 503 后原构建重试和安装。独立 D1 核对取消及失败期间账户零提交，重试成功后各确认一次，新文档可读回。990 项 Flutter 测试、改动文件严格 Dart 分析和正常 Web release 构建通过。[扩展详情短屏](verification/mihon-cupertino-fidelity.md#扩展详情短屏的准备取消与重试)

2026-11-21，固定 Mihon 原 APK 补齐受控签名数据缺失的拒绝加载面板和外层清理异常，两色实拍后均复核恢复。已安装 xkcd 的 APK 摘要相同，清理失败保留原六个文件，撤去故障后重试删除六个。Mihon 状态表主图达到 170/170（100%）。[签名数据缺失](verification/mihon-cupertino-fidelity.md#mihon-插件签名数据缺失的双主题实拍) · [清理异常](verification/mihon-cupertino-fidelity.md#mihon-外层清理失败与重试)

2026-11-21，`539ec0c` 的双主题正式 Web 通过可控的浏览器媒体查询复验设置、真实 xkcd 详情、分类 Sheet 和卸载确认。切换减弱动态后四类标记首个采样均在最终位置，详情仍可左缘返回，已打开的弹层按新偏好关闭。七路账户读回一致，211 项定向 Flutter 测试通过。实际系统偏好和原生现场待验。[减弱动态媒体查询](verification/mihon-cupertino-fidelity.md#正式-web-的减弱动态媒体查询复验)

2026-11-21，本机存储在 360×480 两倍字号下可从已滚动列表定位到清理反馈，原因和重试先于完整副本名称与摘要。两色正式 Web 验证真实标签占用、按同一摘要恢复、清空和重新下载，七路账户状态一致。988 项 Flutter 测试、改动文件严格分析和 Web release 构建通过。[本机副本占用与恢复](verification/mihon-cupertino-fidelity.md#本机副本占用与恢复的双主题正式-web)

2026-11-21，详情下拉补上章节区刷新按钮的禁用语义。隔离 Web 用鼠标拖动复验两色，短拖不读取，长拖发起真实 xkcd 刷新，章节失败后独立重试恢复。深色中段同一行坐标保持，七路账户读回一致。988 项 Flutter 测试、改动文件严格分析和正常 Web release 构建通过。触控由组件测试模拟，真机触屏待验。[下拉手势对照](verification/mihon-cupertino-fidelity.md#下拉刷新的双主题手势对照)

2026-11-21，迁移搜索在正式 Web 两色均复验动漫屋第 2 页。等待时旧候选报告禁用，失败和精确重试均保持末排位置，重试实际追加 21 项。八路账户读回一致，44 项定向测试通过。MangaDex 的第 1 页在线中断另记。[搜索分页与禁用语义](verification/mihon-cupertino-fidelity.md#搜索第二页的双主题恢复与禁用语义)

2026-11-21，修复宽封面草稿在短横屏不可见。受控本地 Web 实拍两色选图及取消后均回到同一完整预览，关闭后七路账户和原图读回一致。两色清除各应用一次，新文档读回。31 项定向测试、严格分析和正常 Web release 构建通过。[封面草稿与确认](verification/mihon-cupertino-fidelity.md#替换封面后自动显示草稿)

2026-11-21，`a9a21aa` 正式 Web 补齐浅深稳定章间等待。白画布调暗 80% 后，加载说明和返回仍可见。真实页列表交付前可退回 3320 第 1 页，七路账户读回相等，明确进入 3319 后可在新文档续读。63 项定向 Flutter 回归通过。[双主题稳定章间等待](verification/mihon-cupertino-fidelity.md#双主题正式-web-的稳定章间等待)

2026-11-21，`1e6b1ba` 正式 Web 从真实英文 xkcd 分别复验资料和章节的刷新故障。两色等待、失败与恢复的章节标题像素位置一致，滚动后的底部重试仍可见。刷新前后七路账户响应逐字节一致，深色随后打开同一首章并显示真实图像。61 项定向 Flutter 回归与严格分析通过。16.K2/K3 已补登记，Karuyomi 跨版本主图为 172/173（99.4%）。[详情刷新故障](verification/mihon-cupertino-fidelity.md#详情刷新故障的双主题正式-web)

2026-11-21，`07a2896` 正式 Web 在内置浏览器验证迁移热门第二页的双主题等待、失败和原页重试，末排保持原位，重试追加 30 项。`95bf156` 修复百项候选的预览落点，两色点选后直接呈现并聚焦标题，深色读回失败后也可在原目标重取。七路账户读回前后相同。35 项定向 Flutter 回归和改动文件严格 Dart 分析通过。[迁移网格与预览落点](verification/mihon-cupertino-fidelity.md#修正版迁移网格的双主题正式-web)

2026-11-21，`b7c581f` 本地正式 Web 在内置浏览器补验设置、xkcd 作品详情、分类 Sheet 和卸载确认的两色常规转场。详情按钮和侧滑均实际回到原热门列表，取消卸载前后三路读回一致。图源空态 07.K2 更新两色主图并验证扩展往返。164 项定向 Flutter 回归通过。系统减弱动态的 Web 实拍和原生现场仍待验。[常规转场](verification/mihon-cupertino-fidelity.md#正式-web-的常规-cupertino-转场) · [图源空态](verification/mihon-cupertino-fidelity.md#图源空态与扩展入口)

2026-11-21，`423639a` 的本地正式 Web 在内置浏览器取得扩展准备失败的浅深主图。两次 xkcd 清单 503 均显示读取扩展材料失败，账户仍未安装。恢复 200 后点原重试，确认同一构建只安装一次。Karuyomi 跨版本主图为 170/171（99.4%）。协议生成校验、10 项协议测试、237 项宿主测试、87 项 Dart Source runtime 测试、984 项 Flutter 测试和严格 Dart 分析通过。[扩展材料读取失败](verification/mihon-cupertino-fidelity.md#扩展材料读取失败的正式-web-复验)

同版正式 Web 补验浅深两色仓库表单。Tab 可从地址移到名称，非法地址保留两项输入，取消无仓库写入。实机软键盘与新版有效地址确认转换待验。[仓库录入与短屏键盘](verification/mihon-cupertino-fidelity.md#仓库录入与短屏键盘)

2026-11-21，`b189199` 正式 Web 在内置浏览器取得卸载确认的双主题主图，取消后原扩展、书架和分类的独立读回一致，Karuyomi 跨版本主图达到 169/171（98.8%）。两色同一清单均实测 503，原构建重试成功，故障原因仍只有通用提示。[正式 Web 的扩展准备失败与卸载确认](verification/mihon-cupertino-fidelity.md#正式-web-的扩展准备失败与卸载确认)

2026-11-21，仓库录入在浅深横竖屏两倍字号的键盘组件复验通过，顶部取消和只读预览可点按，地址和名称可滚动编辑。983 项 Flutter 测试与严格 Dart 分析通过，新版正式 Web 和实机键盘待验。[仓库录入与短屏键盘](verification/mihon-cupertino-fidelity.md#仓库录入与短屏键盘)

2026-11-21，「图源 → 作品详情」的导航栏在减弱动态时随页面原位淡入淡出。按浅深两色比对进入和返回的组件画面，常规转场的八对采样 PNG 与基线逐字节相同。979 项 Flutter 测试和严格 Dart 分析通过，其中章节批量恢复核对了原请求重试。正式 Web 与原生现场转场待验。[作品详情导航栏的减弱动态](verification/mihon-cupertino-fidelity.md#作品详情导航栏的减弱动态)

2026-11-20，Karuyomi 在浅深横竖屏组件中暂扣首次连接响应。连接等待、403 拒绝与重试确认均在原设置详情显示，测试观察到零次账户业务写入。977 项 Flutter 测试和严格 Dart 分析通过，正式 Web 与原生主图待验。[首次连接的等待和恢复](verification/mihon-cupertino-fidelity.md#首次连接的等待和恢复)

2026-11-20，复看 Mihon 空书架与设置的浅深参考。Karuyomi 在两倍字号的浅深横竖屏从书架进入浏览并填写服务地址，三个入口均在首屏可点。非法地址保留草稿，修正后确认测试身份。977 项 Flutter 测试和严格 Dart 分析通过，原生双主题主图待验。[首次连接的短屏复验](verification/mihon-cupertino-fidelity.md#首次连接的短屏复验)

2026-11-20，Karuyomi 底栏通过浅深主题的 Tab 焦点、键盘激活及鼠标和触屏接续复验。974 项 Flutter 测试和严格 Dart 分析通过。`ba3b31f` 的正式 Web 归档在隔离 Worker 中交付原始客户端字节，xkcd 清单实测 200 → 503 → 200。预览面板排队，正式 Web 主图待验。[底栏键盘复验](verification/mihon-cupertino-fidelity.md#底栏键盘焦点与切换) · [清单 HTTP 复验](verification/mihon-cupertino-fidelity.md#扩展准备失败的-http-复验)

2026-11-20，复看 Mihon 浅深横竖屏底栏参考。Karuyomi 底栏按标签行高增高，两倍和三倍字号恢复完整图标并可点按三个入口。四组常规字号的前后组件 PNG 相同。972 项 Flutter 测试通过，正式 Web 和真机继续待验。[底栏大字号复验](verification/mihon-cupertino-fidelity.md#底栏大字号的横竖屏复验)

2026-11-20，Mihon 下载失败与卸载参考逐图复看。Karuyomi 在浅深主题、360×480 两倍字号下，从「浏览 → 扩展」复验准备失败和卸载确认。安装重试核对同一构建与一次账户提交，本机副本重试和取消卸载均无新增提交。970 项 Flutter 测试通过，正式 Web 主图待验。[失败重试与卸载确认的短屏复验](verification/mihon-cupertino-fidelity.md#失败重试与卸载确认的短屏复验)

2026-11-20，固定 Mihon 在隔离参考副本补齐图源空态 07.03 的浅深实拍，双主题主图达 168/170（98.8%），并实际进入插件目录后返回空态。Karuyomi 在剩余内容区居中显示确认的空态，短屏与两倍字号均可进入扩展。968 项 Flutter 测试通过，正式 Web 待验。[图源空态与扩展入口](verification/mihon-cupertino-fidelity.md#图源空态与扩展入口)

2026-11-20，对照 Mihon 单页等待和失败的浅深参考，复拍 Karuyomi 页等待、失败和同页重试。白画布调暗 80% 的失败文字实测从 1.66∶1 提高到 12.63∶1。分页、连续及放大核对三种透明度的 PNG，967 项 Flutter 测试通过，正式 Web 待验。[单页反馈与透明图片的调暗](verification/mihon-cupertino-fidelity.md#单页反馈与透明图片的调暗)

2026-11-20，Karuyomi 章间等待的浅深组件实拍补齐稳定帧，章节标签间距 103，Mihon 参考为 104。80% 调暗的白画布保留原底色，标题实测对比度从 1.66∶1 提高到 12.63∶1，返回保持原页。966 项 Flutter 测试与严格 Dart 分析通过，深色稳定等待的正式 Web 待验。[章间稳定等待与调暗](verification/mihon-cupertino-fidelity.md#章间稳定等待与调暗)

2026-11-20，对照 Mihon 扩展详情的双主题原图，把 Karuyomi 的名称、包名、精确版本和仓库放入可滚动的 Cupertino 分组。360×480 与两倍字号的双主题组件复验确认长名称和源名称完整可读。首次自动检查成功后直接展示列表，手动检查保留完成反馈。965 项 Flutter 测试和严格 Dart 分析通过，正式 Web 待验。[扩展详情的身份与字号](verification/mihon-cupertino-fidelity.md#扩展详情的身份与字号)

2026-11-20，固定 Mihon 在隔离设备上取得 Komga 1.6.76 排队态的浅深两色实拍，参考主图达到 167/170（98.2%）。Karuyomi 修正短屏大字号下准备状态的名称截断，取消可见并等待原操作的确认。292 项相关 Flutter 回归与严格 Dart 分析通过，正式 Web 待验。[扩展排队与短屏取消](verification/mihon-cupertino-fidelity.md#扩展排队与短屏取消)

2026-11-20，固定 Mihon 在同一隔离测试书架取得迁移源加载的浅深两色实拍，参考主图达到 166/170（97.6%）。Karuyomi 修正减弱动态下的底页位移和已打开 Sheet 的偏好切换。963 项 Flutter 回归与严格 Dart 分析通过，正式 Web 和原生现场转场待验。[迁移源加载](verification/mihon-cupertino-fidelity.md#mihon-迁移源加载的双主题实拍) · [底页转场](verification/mihon-cupertino-fidelity.md#cupertino-转场的底页位置)

2026-11-20，固定 Mihon 浅深色实测六个缓存文件无法删除时仍显示删除 0 个，占用 134 kB。恢复权限后从同一入口删除六个文件，占用降至 3.20 kB。Karuyomi 本机存储支持长名称换行，容量按实际大小选用单位。Mihon 11.04 外层提示与 Karuyomi 正式 Web 待验。[本机存储的名称容量与清理反馈](verification/mihon-cupertino-fidelity.md#本机存储的名称容量与清理反馈)

2026-11-20，Karuyomi 确认框与编辑 Sheet 共用 Cupertino 路由的动画设置。实际卸载和分类入口的组件回归核对原位淡入、关闭动画后首帧移除与取消零写入，Flutter 全套 957 项回归通过。固定 Mihon 直接进入迁移标签仍未拍到独立加载帧。正式 Web 转场待验。[Cupertino 确认框与编辑 Sheet 转场](verification/mihon-cupertino-fidelity.md#cupertino-确认框与编辑-sheet-转场)

2026-11-20，Mihon 在关闭设备动画的隔离参考副本取得图源、插件和作品详情首次加载的浅深实拍，主图达到 165/170（97.1%）。Karuyomi 共享页面路由的减弱动态保留侧滑淡出，关闭动画时首帧完成入栈和退出。279 项 Flutter 回归通过，正式转场实拍待验。[首次加载参考与 Cupertino 页面转场](verification/mihon-cupertino-fidelity.md#首次加载参考与-cupertino-页面转场)

2026-11-20，固定 Mihon 完成 08.14 双主题类加载错误、堆栈复制与卸载落点复验，主图达到 162/170（95.3%）。08.13 的三种原因已拍，未签名仍待。Karuyomi 准备失败提示保留扩展、版本、仓库及原因，140 项定向回归通过。新增 08.K9 后跨版本主图为 168/171（98.2%），该状态正式 Web 待验。[插件无法加载的双主题复验](verification/mihon-cupertino-fidelity.md#mihon-插件无法加载的双主题复验)

2026-11-20，Mihon 核对六种确认面板的浅深原图，并实测从同一 MangaDex 详情取消卸载。Karuyomi 补齐 Cupertino 卸载确认，138 项定向 Flutter 回归通过。Mihon 双主题 161/170（94.7%），Karuyomi 新登记 09.K6 后为 168/170（98.8%），卸载确认正式 Web 尚待。[确认面板与扩展卸载](verification/mihon-cupertino-fidelity.md#mihon-确认面板与扩展卸载)

2026-11-20，`2b3d4a5` 正式深色 Web 测到迁移候选封面为 162×243，Komiic 第二页精确重试及只读预览通过，七路权威读回一致。实拍发现分页失败把封面下推 184 逻辑像素。改为候选末尾反馈后，72 项定向 Flutter 回归通过，修正版正式 Web 两色待验。[正式深色网格与分页反馈](verification/mihon-cupertino-fidelity.md#正式深色网格与分页反馈)

2026-11-20，`e7523ea` 正式 Web 实拍显式浅深色的同一宽封面，360×800 与 844×390 首屏均见四边。短横屏滚动后两项封面操作可达，两色都返回原作品。内置浏览器完成上述验收后恢复视口。[正式 Web 宽封面复验](verification/mihon-cupertino-fidelity.md#正式-web-宽封面双主题复验)

2026-11-20，Mihon 补齐源浏览追加与迁移空书架，双主题主图达到 160/170（94.1%）。Karuyomi 将追加指示移到封面列表末尾，50 项定向 Flutter 回归通过。[源浏览追加](verification/mihon-cupertino-fidelity.md#mihon-源浏览追加) · [迁移空书架](verification/mihon-cupertino-fidelity.md#mihon-迁移空书架)

2026-11-20，`fd8bc04` 的分支检查在下载 Java 格式化器时收到 Maven Central HTTP 404。下载器增加同版本的 Google GitHub 发布地址。模拟空缓存和 404 后成功读取官方文件，3,781,805 字节的 SHA-256 与原锁定值相等。[分支检查](https://github.com/Wybxc/karuyomi/actions/runs/44631624888) · [Google 官方发布](https://github.com/google/google-java-format/releases/tag/v2.0.0)

2026-11-20，Mihon 新增扩展空目录、下载中、安装阶段、失败重试和仓库连接错误五组双主题实拍，累计 158/170（92.9%）。Karuyomi 调整目录等待、空态和失败反馈，仓库只读预览失败后保留地址与名称。121 项 Flutter 定向回归通过，正式 Web 双主题继续验收。[扩展目录与仓库错误](verification/mihon-cupertino-fidelity.md#mihon-扩展目录与仓库错误)

2026-11-20，Mihon 新增迁移搜索等待、失败、单源网格、共存等待与完成五组双主题实拍，累计 153/170（90.0%）。Karuyomi 迁移候选采用 Cupertino 封面网格，115 项 Flutter 定向回归通过，正式 Web 待验。[迁移搜索与共存](verification/mihon-cupertino-fidelity.md#mihon-迁移搜索与共存)

2026-11-20，`8dd507a` 正式深色 Web 复验竖屏章间缺页与就绪、短横屏重试和第 3319 章第 1 页的新文档续读，进入前六路读回完全一致。`4332503` 的正式深色 Web 复现了宽封面固定占高、横屏裁掉下沿。修正后 138 项 Flutter 定向回归通过，最新版正式 Web 继续待验。[章间量测](verification/mihon-cupertino-fidelity.md#画布内等待的信息间距与按钮) · [封面预览](verification/mihon-cupertino-fidelity.md#karuyomi-封面预览)

2026-11-20，固定 Mihon 0.21.3 的刷新等待、章节失败、源空清单和筛选无匹配新增四组双主题实拍，累计 148/170（87.1%）。Karuyomi 详情的 Cupertino 下拉刷新保留原资料直到两段读取成功，增加失败重试和筛选清除。最新版的正式 Web 双主题继续待验。[详情刷新与章节空态](verification/mihon-cupertino-fidelity.md#mihon-详情刷新与章节空态)

2026-11-20，`66be7cd` 正式 Web 双主题通过分页、连续和条漫的工具显隐、隐藏页码与恢复入口。三种模式均保留当前页位，连续的最远页随新露出的实际图片推进。153 项回归覆盖转场、快速切换和系统减弱动态，分支、PR CI 和 Wasm 通过。[阅读器显隐与页码](verification/mihon-cupertino-fidelity.md#阅读器显隐与页码)

2026-11-19，`313bbc9` 的正式 Web 双主题同页图片上缘从 47 px 移到 128 px，参考 Mihon 为 132–133 px。工具显隐、菜单焦点、书签和新标签续读通过，122 项定向回归、分支与 PR CI 和 Wasm 通过。[阅读器工具区与画布](verification/mihon-cupertino-fidelity.md#阅读器工具区与画布)

2026-11-19，`7db8551` 的正式 Web 双主题通过阅读器页码滑杆、从右到左方向、键盘操作和新标签续读。三个跳转动作各提交一次进度。100 项定向回归、分支与 PR CI 通过；同页画布纵向位置和工具区仍需对齐。[阅读页码与方向](verification/mihon-cupertino-fidelity.md#阅读页码滑杆与方向排列)

2026-11-19，`4026db3` 的第 3324 章第一页完成与 Mihon 的同页量测。`21f23d6` 正式 Web 深浅色核对暂停确认后的独立结束节点、首次回车、页章边界禁用与 D1 续读位置第 2 页。两轮各只有一次章节标记，106 项 Flutter 回归通过。[键盘焦点](verification/mihon-cupertino-fidelity.md#章节批量动作名称与焦点范围) · [同页对照](verification/mihon-cupertino-fidelity.md#阅读器同页与边界的正式-web-双主题对照)

2026-11-19，固定 Mihon 0.21.3 补齐空章反馈、相邻章过渡与失败、首章与末章边界五项双主题参考，累计 137/170（80.6%）。浅色缺页过渡通过原重试恢复并进入实际下一章。`b5998b0` 正式 Web 深色复现章节批量结束键盘失效，`4026db3` 调整辅助动作范围，59 项定向回归通过，正式 Web 复验待完成。[阅读参考及量测](verification/mihon-cupertino-fidelity.md#mihon-章节过渡与空页的双主题参考) · [章节焦点](verification/mihon-cupertino-fidelity.md#章节批量动作名称与焦点范围)

2026-11-19，`f084467` 正式 Web 补齐 30.K6/K7。两种主题均实测逐章部分提交、丢回执后的原文重试、受控 401 后关闭旧窗口及同一身份恢复。16 组六路权威读回确认已生效的命令没有重复写入，第三章只在明确继续后提交。双主题主图累计 168/169（99.4%）。[章节批量与恢复](verification/mihon-cupertino-fidelity.md#章节部分提交与编辑失效的正式-web-双主题验收)

2026-11-19，`d0d963c` 正式 Web 补齐 30.K1–K5。封面和阅读设置显示当前作品与来源，确认等待中的保存和关闭报告禁用。双主题核对取消零写入、丢确认后的原文重试及真实 409 冲突后的只读恢复。双主题主图累计 166/169（98.2%）。[共享编辑](verification/mihon-cupertino-fidelity.md#共享编辑对象与保存阶段的正式-web-双主题验收)

2026-11-19，`704d148` 正式 Web 补齐 28.K1/K2。显式深浅色均通过跨源搜索失效后的释放等待、失败、同槽重试与返回。重新连接后手动查询从新代次取得真实结果，两组四路权威读回一致。双主题主图累计 161/169（95.3%）。[释放与恢复](verification/mihon-cupertino-fidelity.md#失效后释放搜索资源的正式-web-双主题验收)

2026-11-19，`0e432ce` 正式 Web 显式浅深色通过设置分组、继承禁用和原监听路径。两组四路读回各确认一次实际章节设置，主图累计 159/169（94.1%）。[设置分组](verification/mihon-cupertino-fidelity.md#漫画源设置分组与禁用色的正式-web-双主题验收)

2026-11-19，`517a73e` 正式 Web 双主题通过打开迁移目标及追加失败，原候选保留，原页重试成功，五路权威读回相等。主图累计 158/169（93.5%）。[迁移恢复](verification/mihon-cupertino-fidelity.md#迁移目标与分页失败的正式-web-双主题验收)

2026-11-19，`7461850` 正式 Web 双主题通过真实 Komiic 的读取、重置、应用、描述失败和会话失效复验。两组四路权威读回一致，主图累计 157/169（92.9%）。[筛选实拍与运行时验证](verification/mihon-cupertino-fidelity.md#漫画源筛选过程与恢复的正式-web-双主题验收)

2026-11-19，`a251191` 正式 Web 双主题核对退出等待、失败提示、精确重试与返回，两组前后权威读回一致。15.K13 补齐，跨版本主图累计 152/169（89.9%）。[整页退出实拍](verification/mihon-cupertino-fidelity.md#跨源退出清理的正式-web-双主题验收)

2026-11-19，`ad41606` 正式 Web 双主题确认清理和重读在等待中实际禁用，清理后零副本且账户安装一致。11.K3 补齐，主图累计 151/169（89.3%）。[清理实拍与读回](verification/mihon-cupertino-fidelity.md#本机副本清理的正式-web-双主题验收)

2026-11-19，`392273b` 正式 Web 双主题补齐 15.K10 和 15.K12，跨版本主图累计 150/169（88.8%）。同一停止显式重试成功，迟到的真实结果未公开显示。整页退出清理提示另修，正式画面仍待。[实拍与读回](verification/mihon-cupertino-fidelity.md#跨源单源停止的正式-web-双主题验收)

2026-11-19，`78f4c4b` 正式 Web 用隔离运行时回执夹具复现跨源停止停滞，以及存储清理时两项按钮仍报告可用。随后修正清理和重读的禁用语义，修复后正式双主题继续验收。[停止实拍与存储修正](verification/mihon-cupertino-fidelity.md#停止与本机清理的正式-web-基线)

2026-11-19，跨源搜索控制器和执行槽回归复现丢失停止确认时的不可恢复等待。修正后只重试原资源释放，保持旧查询，拦截迟到结果。正式 Web 双主题待验。[复现与修正](verification/mihon-cupertino-fidelity.md#跨源停止确认丢失的复现与修正)

2026-11-19，`78f4c4b` 正式 Web 双主题确认 257／256 条映射时禁用，减去一条后能进入二次确认，退出后权威状态一致。20.K18 补齐，主图累计 148/169（87.6%）。[实拍与读回](verification/mihon-cupertino-fidelity.md#章节映射超限的正式-web-双主题验收)

2026-11-19，`5f5d287` 正式 Web 通过真实英语 Commit Strip 的设置空态双主题，重读及关闭无额外写入，主图累计 147/169（87.0%）。[实拍与读回](verification/mihon-cupertino-fidelity.md#漫画源设置空态的正式-web-双主题验收)

2026-11-19，`5f5d287` 正式 Web 补齐批量分类身份失效双主题，达到 146/169（86.4%）。三轮均只有首部写入，次部收到 401，末部未发送。迁移超限用隔离上游夹具复现并修正确认按钮语义，正式双主题仍待。[批量实拍](verification/mihon-cupertino-fidelity.md#批量分类失效的正式-web-双主题验收) · [迁移复现](verification/mihon-cupertino-fidelity.md#章节映射超限的复现)

2026-11-19，`1ef627b` 正式 Web 验证封面等待的三个禁用语义及失效迁移首个观测帧。三作品批量实测首项确认、次项 401、末项未发送，随后修正旧窗口的重试入口和文案，72 项书架相关回归通过。04.K8 修复后双主题仍待。[实拍与修正](verification/mihon-cupertino-fidelity.md#编辑复验与批量窗口失效)

2026-11-19，`138ccbd` 正式 Web 在系统深色下保留已确认的浅色，补齐分类、封面、迁移和漫画设置四个失效主图及分类与设置禁用语义。101 条审计有终态，两组前后七路读回一致。覆盖达到 145/169（85.8%），迁移首帧调整仍待正式 Web 复验。[实拍与读回](verification/mihon-cupertino-fidelity.md#身份失效的正式-web-浅色复验)

2026-11-19，`1d29865` 的正式 Web 核对服务连接禁用语义和恢复，并补齐 19.K5 的同一封面选图等待双主题。覆盖 141/169（83.4%）。68 条审计均有客户端终态，读回原封面及字节一致。失效由夹具触发，手动系统取消仍待。[实拍与读回](verification/mihon-cupertino-fidelity.md#选图等待的正式-web-双主题验收)

2026-11-19，Access 暂停时的主题突变已复现并修复。两种对向系统主题、账号更替、读取拒绝及重新连接经 167 项定向回归和两文件分析核对，正式 Web 实拍待验。[主题延续](verification/mihon-cupertino-fidelity.md#access-暂停时延续已确认主题)

2026-11-19，`b29c3bb` 正式 Web 确认跨源搜索空态的提交禁用语义，并核对四个编辑身份失效流程。87 条审计均有客户端终态。照片实际为系统深色，双主题主图覆盖保持 140/169（82.8%）。连接、设置重读和分类按钮的禁用语义修正通过 131 项定向回归及六文件分析，正式 Web 复验继续待办。[实拍和修正](verification/mihon-cupertino-fidelity.md#禁用语义与编辑身份失效的正式-web-复验)

2026-11-19，`0a28f6a` 正式 Web 补齐 27.K2–K4 浅色和 15.K14 双主题，覆盖为 140/169（82.8%）。两主题新文档均核对《ONE PIECE航海王》详情、返回原三项结果和同副本清理。133 条审计均有客户端终态。跨源禁用语义与具体失败原因通过 162 项定向回归和四文件分析，最新 Web 无障碍仍待复验。[正式复验与边界](verification/mihon-cupertino-fidelity.md#连接状态与跨源详情的正式-web-复验)

2026-11-18，内置浏览器恢复后使用 `a8997fa` 正式 CI Web，补齐扩展准备、存储检查、两标签真实占用清理和选源空态的四对主图，达到 136/169（80.5%）。70 条审计有 69 条终态，五组账户读取相同。跨源停止、退出、打开反馈与实拍发现的存储及空态修正通过 160 项定向回归和六文件分析，最新正式 Web 待验。[双主题验收](verification/mihon-cupertino-fidelity.md#扩展与选源的正式-web-双主题验收)

2026-11-18，扩展准备显示目标与版本，独立核对了准备结果先到时仍等待取消确认，以及本机副本清理在重新读取后按原 SHA-256 重试。155 项定向回归和四文件分析通过。内置浏览器控制超时，正式双主题覆盖为 132/169（78.1%）。[准备与清理记录](verification/mihon-cupertino-fidelity.md#扩展准备与本机副本清理)

2026-11-18，跨源搜索无可选源可进入扩展管理。360×800 浅深组件验证搜索关闭后导航、零账户写入及零 Source 打开，相关 110 项回归和三文件分析通过，15.K2 正式画面继续待验。[状态记录](verification/mihon-cupertino-fidelity.md#跨源搜索空态直达扩展管理)

2026-11-18，`fcf3632` 的分支和 PR CI 通过。真实 HTTP 核对扩展构建清单延迟约五秒，索引及有查询清单照常交付。本机存储初次读取去除重复进度，未读状态和重读按钮禁用色通过浅深组件测试。三文件 99 项定向回归及两文件分析通过。内置浏览器现场尚缺深色与审计，覆盖仍为 132/169（78.1%）。[验收细节](verification/mihon-cupertino-fidelity.md#扩展准备的正式验收入口)

2026-11-18，`dc6e3c9` 分支 CI、Web、Wasm 和 PR 检查通过。正式 Web 两主题核对 Komiic 单选去重与同步说明，深色实际两标签用 Tab、Enter 恢复热门，再读回设置。四组七路快照及 43 条终态审计确认重试和读回零额外写入。焦点轮廓局部裁切待修。[正式复验](verification/mihon-cupertino-fidelity.md#source-单选值与运行槽重试)

2026-11-18，`92d4f93` 的迁移向导双主题实测打开目标 Source 的等待、读取失败与成功落点。四组六路快照、32 条终态审计确认迁移零业务写入。20.K8 新增一对主图，达到 132/169（78.1%）。[正式验收](verification/mihon-cupertino-fidelity.md#迁移打开目标源的正式-web-双主题验收)

2026-11-18，`92d4f93` 的分支及 PR CI 通过。正式 Web 双主题核对 Komiic 设置读取、关闭重开恢复、两次精确重试零重复和已确认后的只读恢复。17 组七路快照及 137 条终态审计通过，独立 Web 文档读回两项设置。新增 14.K1/K5，主图达到 131/169（77.5%）。[验收与遗留问题](verification/mihon-cupertino-fidelity.md#source-偏好读取与恢复的正式-web-双主题验收)

2026-11-18，`270db05`完整push/PR CI、Web与push Wasm通过，[仓库预览与操作恢复正式双主题](verification/mihon-cupertino-fidelity.md#仓库预览与操作恢复的正式-web-双主题验收)补齐10.K4/K7/K9，126→129/169（76.3%）。40张JPEG/DOM、两份完整ARIA、23组六路快照与13个相等区间核对原对象、确认后读取和中性原值标题；114条审计全部终态，13条POST为两次准备、九次UI原操作和两次零重复重试，已确认读取恢复零额外POST。五次读取503含一次失败快照探测，转场/错过时刻/输入校验失败单列排除。剩余40个主状态及全部变体/最终产物，无Source运行、Native或生产增量，PR仍草稿未部署。

2026-11-18，[仓库预览目标与保存阶段](verification/mihon-cupertino-fidelity.md#仓库预览目标与保存后的读取阶段)的十四项流程先复现后通过，预览与提交期间保留完整名称/地址，有效确认后的目录刷新显示读取，重试等待不再提前显示未知指引。五文件136项相关回归、四文件严格分析通过；内置浏览器空白标签控制实际恢复，新完整CI及正式Web双主题仍待，主图仍126/169（74.6%），没有Source运行、原生或生产增量。

2026-11-18，[已确认原值标题残留](verification/mihon-cupertino-fidelity.md#已确认原值标题的残留修正)在两项既有双主题流程先复现，现改为中性标题，外层确认阶段和原请求不变。五文件134项相关UI回归、两文件严格分析及官方生成一致性通过；新完整CI见PR #8检查，新正式标题复验仍待，主图保持126/169（74.6%）。

2026-11-18，`2512c51`完整push/PR CI、Web及push Wasm通过，[扩展与共享设置正式双主题](verification/mihon-cupertino-fidelity.md#扩展与共享设置恢复的正式-web-双主题验收)以41张DOM实拍、两份ARIA、22组六路快照与14个相等区间核对原对象跨页保留及已确认读取恢复。113条审计中112条终态、首个人工挂起14单列；13条POST为两次准备、八次UI原操作和三次零重复重试，读取恢复零额外POST。补齐07.K8、08.K7/K8及09.K5深色，122→126/169（74.6%），剩余43个主状态及全部变体/最终产物；准备未截到、禁用辅助语义仍待，没有Source运行、Native或生产增量，PR仍草稿未部署。

2026-11-18，[扩展原操作与设置读取恢复](verification/mihon-cupertino-fidelity.md#扩展原操作与设置确认后的读取恢复)补齐冻结的扩展/仓库原对象及完整提交值，并区分未知写入与有效ACK后的补读失败；后者重试零额外POST。相关缺口先复现后修复，十文件189项组件/数据回归通过，无效ACK与已知拒绝重建继续约束。新提交完整CI和正式Web双主题仍待，主图仍122/169（72.2%），没有Source运行、原生或生产增量。

2026-11-18，`1bc3c70`完整push/PR CI、Web及push Wasm通过，[源收藏与存储隔离正式双主题](verification/mihon-cupertino-fidelity.md#源收藏与存储隔离的正式-web-双主题验收)完成。18张JPEG/DOM、16组六路完整快照、十个相等区间和73条终态审计核对两次准备、五次UI原操作（含一次主题保存）与两次相同UUID/CAS/正文重试零重复；其它业务保持。此前失败的深色重开及确认清除后再次重开正常，控制台无错误/警告。新增07.K1/K5/K9三对，119→122/169（72.2%），剩余47个主状态及全部变体/最终产物；没有新增Source运行、Native或生产证据，PR仍草稿未部署。

2026-11-18，`fe57f2c`完整push/PR CI、Web及push Wasm通过，[正式源目录复验](verification/mihon-cupertino-fidelity.md#展开状态与滚动位置的存储隔离)在浅色完成读取/等待/未知恢复与原对象保留，深色重开实际渲染失败。十组六路完整快照、六个相等区间和49条终态审计确认两次准备、两次源原操作、一次主题保存及一次零重复重试，其它业务保持；11张JPEG/DOM及控制台异常保留，没有新主图。定位为Expansible布尔值与滚动数值共用PageStorage，现为六处折叠提供独立键。源/扩展八项共享bucket回归先复现后通过，四文件100项相关回归、五文件严格分析、完整格式/校验、证据工具类型与依赖检查通过；新提交完整CI和新正式Web待验，仍119/169（70.4%），没有Source运行、原生或生产增量。

2026-11-18，正式CI客户端`9a1c03c`在内置浏览器完成[源收藏浅色缺陷复现](verification/mihon-cupertino-fidelity.md#源收藏恢复布局的浅色复现与修复)：状态贴边、全局值挤占内容、取消收藏缺少原对象摘要。七张JPEG/DOM、五组六路快照与26条终态审计核对两次UI原操作及一次零重复原文重试，未执行Source。现改为内缩状态、冻结原对象摘要和可展开完整值；四项主题/字号回归先失败后通过，八文件124项相关回归、五文件严格分析、完整格式/校验、证据工具严格类型和依赖检查通过。新提交完整CI与正式双主题待验，仍119/169（70.4%），没有新增主图或生产证据。

2026-11-18，`9a1c03c`完整push/PR CI及Web/Wasm通过，内置浏览器本轮实际恢复控制。[分类与部分批量双主题验收](verification/mihon-cupertino-fidelity.md#分类与部分批量的正式-web-双主题验收)以28组十二路完整快照、16个相等区间和224条终态审计核对六次准备、17次UI原操作、四次零重复重试、确认读取零额外POST及四次受控400零应用。34张DOM实拍补齐04.K4/K6、05.K10三对，116→119/169（70.4%）；剩余50个主状态及全部变体/最终产物。旧归属失败保留，恢复原因未知；临时标签、视口及harness已正常清理，没有新增真实CAS、身份失效、Source、原生或生产证据。

2026-11-18，[单作品与批量读取恢复](verification/mihon-cupertino-fidelity.md#单作品与批量确认后的读取恢复)先复现有效ACK后补读失败仍重复POST及误报未确认，再改为保留已校验确认、仅重读。批量读取未完成不自动发送后续项；相关十三文件159项组件/仓库回归通过，无效ACK与较新远端修改继续拦截。新提交完整CI见[PR #8检查](https://github.com/Wybxc/karuyomi/pull/8/checks)，正式Web待验，没有新主图，仍116/169（68.6%）。

2026-11-18，用户确认当前聊天浏览器面板已打开后，显式iab选择和完整库存两次调用仍超时，累计六次。最新[归属记录](verification/mihon-cupertino-fidelity.md#分类与部分批量的正式-web-准备受阻)确认桌面`ownerRoutePath`已指向本聊天，但浏览器`conversationId`仍是`client-new-thread`临时身份，控制请求继续因“属于另一个任务”被拒绝；普通打开面板未恢复绑定，官方打开入口仍queued。更深桌面状态原因尚未确定，待重建桌面连接后再验证；没有新产品画面，仍116/169（68.6%）。

2026-11-18，同轮[浏览器归属诊断](verification/mihon-cupertino-fidelity.md#分类与部分批量的正式-web-准备受阻)在ChatGPT 26.1111.21308的本地日志定位到当前聊天/当前turn的直接拒绝：`IAB browser belongs to another task.`，发生于IAB `getInfo / prepareSessionRoute`。在本聊天打开内置浏览器面板的官方入口返回queued，尚不能算控制恢复；已请求用户显示本聊天的浏览器后继续。为什么桌面归属不一致仍未确定，不能把同时出现的其它WebSocket警告当作因果证据。CI与API准备证据保持，主图仍116/169；没有绕过归属检查或改用其它浏览器。

2026-11-18，`c6f1ce6`完整push/PR CI、Web及push Wasm通过，deploy跳过。[正式Web准备受阻记录](verification/mihon-cupertino-fidelity.md#分类与部分批量的正式-web-准备受阻)核对CI客户端`d09212b`与独立夹具，实际HTTP的35条资源与CI相等。临时D1六次准备、三部收藏的十二路ProtoJSON基线及18条完成审计已核对，全部POST均为独立准备，UI业务写入为0。内置浏览器组合调用、库存、指定URL定位与显式iab选择均约30秒超时并重置，未取得可核验画面；首个调用的具体失败步骤和视口是否改变/恢复均未确认，根因未定。未改用其它浏览器，验收服务正常退出0。没有新主图，仍116/169（68.6%）；拒绝修复、部分批量和其余正式UI/生产门继续待验。

2026-11-18，`d09212b`完整push/PR CI、Web及push Wasm通过，deploy跳过；正式Web归档与39条资源校验并装配，拒绝提示的新正式双主题尚待。为取得已确认/未确认/未开始并存的实际批量主图，[官方故障入口](verification/mihon-cupertino-fidelity.md#批量部分提交的确定性故障入口)新增首项确认后丢后项确认模式，62项真实Workers/D1/R2回归通过，精确重试零重复、取消和显式模式覆盖保持。首轮第二作品未收藏的测试准备导致真实400，已补齐收藏后重跑；未放宽分类API。新夹具完整CI、正式UI与剩余门待验，不增加116/169（68.6%）主图计数。

2026-11-17，夹具`5979361`完整push/PR CI、Web及push Wasm通过。复用`49f3482`正式CI客户端完成[分类保存与恢复的双主题复验](verification/mihon-cupertino-fidelity.md#分类保存与恢复的正式-web-双主题复验)，28组九路快照、九个完全相等区间与247条完成审计确认16次UI分类原操作、两次零重复重试、两次已确认读取重试零额外POST；五次准备、四次独立远端写入与一次明确UI主题保存分开核对。新增05.K8/K9两对主图，114→116/169（68.6%），05.K11只补深色；剩余53个主状态（仅单侧9、双侧均缺44）及全部变体/最终产物。双主题明确拒绝及真实409的辅助说明仍沿用未知指引，保留失败后修复；四项主题/字号流程先复现，相关69项分类/书架/批量回归通过。新提示完整CI及正式Web、其它状态与生产仍待，PR草稿未部署。

2026-11-17，`49f3482`完整push/PR CI、Web及push Wasm通过，deploy跳过。[内置浏览器恢复后的分类浅色复验](verification/mihon-cupertino-fidelity.md#内置浏览器恢复后的分类浅色复验)先核对正式CI与实际HTTP的35条Web资源，再验证保存阶段及未知结果下原UUID/CAS/正文重试。四组九路快照、两个相等区间与36条审计核对一次UI原操作、一次零重复重试及五次独立准备；首次确认交付sequence17没有终态，明确单列，不能计正常释放。四张DOM实拍和一张辅助AX图不增加成对主图，仍114/169（67.5%）。现有官方夹具新增短自动确认/读取及确认后读取失败，57项Workers/D1/R2回归和严格类型通过；新夹具完整CI、正式双主题及其余门待验，PR草稿未部署。

2026-11-17，`500b5a3`完整push/PR CI、Web和Wasm通过，deploy跳过。[分类读取与关闭](verification/mihon-cupertino-fidelity.md#分类确认后读取阶段的即时反馈)的四项主题/字号流程先复现确认后仍显示保存及只读关闭禁用，再验证即时读取反馈、关闭/书架重开复用原读取，迟到结果不关闭新窗口。真实CAS重读另复现新窗口保留旧分类，修复后交接新快照并恢复编辑；仓库用例复现其它漫画通知提前放行首次书架读取，现等待自身权威刷新。相关154项数据、书架/续读、批量及迁移回归通过，原UUID/CAS/正文及只读重试规则保持。内置浏览器四次控制调用均超时，根因未确认；未进入产品页面、启动验收服务或取得新截图，仍114/169（67.5%）。新完整CI、正式Web双主题及其余门待验，PR草稿未部署。

2026-11-17，`61608c5`完整push/PR CI及Web/Wasm通过。[分类确认与读取失败的正式Web浅色复验](verification/mihon-cupertino-fidelity.md#分类确认与读取失败的正式-web-复验)已核对实际35条Web资源、七组九路快照和64条完成审计。正常保存说明通过；重排缺对象/目标位置、ACK成功后读取503仍称未确认并重发POST，均保留为失败。四条UI原命令各应用一次，额外相同正文重试零重复，两部作品及其它业务内容不变。修复在当前身份会话内保留已验证ACK，明确继续只重读，关闭后仍恢复读取阶段；重排保留冻结对象与目标位置，相关83项回归通过。新修复完整CI、正式Web双主题及其它门待验，本轮八张浅色图不增加成对主图，仍114/169（67.5%）；PR草稿未部署。

2026-11-17，`94b7b82`完整push/PR CI及Web/Wasm通过。[正式CI客户端与独立夹具的双主题复验](verification/mihon-cupertino-fidelity.md#批量等待与暂停的正式-web-复验)补齐04.K3/K5：当前项提交后等待，请求暂停再确认后保留剩余清单；浅色明确继续、深色明确结束均按原范围处理。13组九路快照、五个相等区间与94条审计核对五次准备、八次UI原操作及一次零重复重试，sequence17首次交付未完成单列、其余93条完成。新增两对主图，跨版本114/169（67.5%），剩余55个主状态及全部变体。实拍发现分类保存期间提前显示“重试”和未确认指引，四项既有主题/字号流程复现后修复，相关35项回归通过；新提示完整CI及正式Web、其余状态/生产仍待，PR草稿未部署。

2026-11-17，[分类目录与批量故障入口](verification/mihon-cupertino-fidelity.md#分类目录与批量操作的故障验收入口)已接入现有官方editor-ui，42项Workers/D1/R2回归通过：目录和作品分类实际提交后才挂起/丢确认，精确重试零重复，旧版本新请求仍真实409，读取取消和拒绝/失效保持原状态。进度及收藏继续透传，首段书架读回仅在相应范围内拦截；普通验收和生产不启用。相关正式Web尚未执行，不增加112/169主图计数；API/test严格类型、全范围格式和依赖分层通过，新提交完整CI与正式Web仍待。

2026-11-17，`ef5f3dd`完整push/PR CI及Web/Wasm成功。[正式Web双主题复验](verification/mihon-cupertino-fidelity.md#勾选身份与目标列表加载的正式-web-双主题复验)确认同名作品勾选框完整身份与键盘取消、英文/法文空分类对象分组，以及真实MangaDex热门/搜索和两种追加的准确说明；未提交输入不改变原查询，等待时保留列表。九组九路快照、七个相等区间及43条完成审计核对仅三次准备和一次明确UI主题保存，没有其它业务POST；Source偏好未改，运行时请求不在审计范围。实际交付35条Web清单与CI相等，23张实拍中八张真实加载图新增20.K10一对主图，跨版本112/169（66.3%），仅单侧8、双侧均缺49。剩余57个主状态、全部变体/最终产物和生产继续验收，PR仍草稿未部署。

2026-11-17，`25be6f5`完整push/PR CI与Web/Wasm通过；[正式Web双主题复验](verification/mihon-cupertino-fidelity.md#分类对象与迁移页脚的正式-web-双主题复验)确认分类面完整对象身份、名称点击/取消/保存、批量添加/移除，以及迁移待确认/书架重开/精确重试后的阶段页脚。21组九路快照、13个相等区间和107条完成审计核对实际写入、零重复与取消零附写；四次独立准备单列，目录准备不在审计范围。首次本地遗漏acceptance重建交付旧客户端，旧记录排除；纠正后实际HTTP的35条Web清单与CI严格相等。25张图是现有状态补充，主图仍111/169；独立勾选框无名称、加载说明缺具体操作的六项既有流程先复现并修复，相关51项回归与四文件严格分析通过，新完整CI/正式Web、空分类新分组、全部剩余状态与生产仍待，PR草稿未部署。Mihon环境记录纠正为配置2GB但启动日志提升至2560MB，实际内存未测；普通UI尚未触发纯空源列表，不补通过。

2026-11-17，复用`a12c779`正式CI Web完成[受阻进度重开与同名书架的双主题复验](verification/mihon-cupertino-fidelity.md#受阻草稿重开与同名书架的正式-web-复验)。原迁移明确确认后，从书架重开及刷新仍保留草稿并等待明确重试；两次明确进度保存及两次后续自动保存各推进一次版本，双主题新文档续读均恢复第2页。30组九路快照、20个完全相等区间及172条含进度JSON的完成审计已核对，旧失败保留且不追溯补全旧审计。中文目标两次中断单列；33张图是转换分项，主图仍111/169。分类对象身份与迁移阶段旧说明两个实拍缺口已在八项既有主题/字号流程复现并修复，相关51项回归及四文件严格分析通过；新完整CI、修复后正式Web、全部剩余状态/变体和生产仍待，PR草稿未部署。`d5a0bc8`完整push/PR CI与Web/Wasm已通过。

2026-11-17，`a12c779`完整push/PR CI与Web/Wasm成功；[正式Web双主题复验](verification/mihon-cupertino-fidelity.md#source-与选源的正式-web-双主题复验)确认Source拒绝采用错误色、原值保留、明确重读清反馈，文本与多选取消/应用/重开和恢复初值，以及选源名称/键盘/隐藏选择保留与真实五源排队。新增14.K6、15.K3、15.K4，跨版本成对主图111/169（65.7%），仅单侧8、双侧均缺50；38张实拍不是38个新状态。10组六路快照、3条Source偏好响应及87条完成审计核对仅两次准备和两次明确UI主题保存，其余业务零附写；审计不含Source调用和偏好API。受阻进度重开、同名书架、全部剩余状态/变体和生产仍待，PR保持草稿未部署。

2026-11-17，`0a02ee6`完整push/PR CI与Web/Wasm通过，[内置浏览器恢复后实测](verification/mihon-cupertino-fidelity.md#内置浏览器恢复后的-source-实测与拒绝提示修复)浅色选源名称/键盘、空查询、真实xkcd结果及MangaDex多选/文本偏好。三组六路快照完全相等，23条范围内审计仅两次独立准备POST；会话操作不附写账户。Source拒绝提示按普通正文显示的实拍保留，已修复错误角色与旧成功说明清除，47项回归及三文件严格分析通过。15.K3仅新增浅色，成对主图仍108/169；新完整CI、修复后双主题、全部变体与生产仍待，PR保持草稿未部署。

2026-11-17，`83e32fd`完整push/PR CI及Web/Wasm成功。[结果区字号与参考补图](verification/mihon-cupertino-fidelity.md#结果区字号角色与复制参考补图)取消源名16px硬编码、采用官方正文和13px次级角色，23项既有页面回归与单文件严格分析通过。Mihon 0.21.3参考28.04补齐应用浅/深的可读复制预览，仅确认可见片段，完整剪贴板仍待；恢复设置后参考模拟器已关闭。内置浏览器尚未取得新页面，Karuyomi主图仍108/169，新字号完整CI、正式Web与生产继续待验。

2026-11-17，[选择行与搜索反馈的Cupertino收敛](verification/mihon-cupertino-fidelity.md#选择行与搜索反馈的-cupertino-收敛)已接入官方选源分组、完整选择行与表单输入、次级页脚、整行/键盘选择及系统错误色；单作品/批量分类名称点击也已复现并修复。本轮78项不同回归与七文件严格分析通过。上一轮`39a55f7`完整push/PR CI及Web/Wasm成功。内置浏览器控制接口再次超时，面板打开入口仅排队，没有新正式页面；新提交CI、正式Web与生产仍待，不增加108/169主图计数。

2026-11-17，[Source偏好子编辑器](verification/mihon-cupertino-fidelity.md#source-偏好子编辑器的分组与失效)修复文本/多选身份失效仍留旧输入与应用入口、多选文字点击未切换及分组说明缺口，43项定向回归与两文件严格分析通过。editor-ui补齐进度等原样业务命令审计，24项官方Workers/D1/R2回归、API/test严格类型和依赖分层通过。`3a3976d`完整push/PR CI及Web/Wasm现已成功；本轮内置浏览器两次连接超时，新的正式Web、生产与原生均未执行，主图保持108/169，PR继续草稿未部署。

2026-11-16，`19c2260`正式Web双主题实看[阅读进度被迁移阻塞的反馈](verification/mihon-cupertino-fidelity.md#阅读进度阻塞的正式-web-复验与重开修复)，浅色明确恢复后另行保存/续读通过；深色从书架重开却自动保存，记录为失败。19组九路快照、13个完全相等区间和121条范围内审计通过核对，进度POST不在该审计范围，写入增量由快照确认。新门控修复的45项回归、同名书架身份修复的38项回归通过，完整CI与新Web仍待。主状态覆盖仍108/169（63.9%），PR仍草稿未部署；`35559fb`已有完整push/PR CI及Web/Wasm成功。

2026-11-16，`19c2260`的58项连接/进度定向回归、完整push/PR CI及Web/Wasm通过。[连接状态正式Web复验](verification/mihon-cupertino-fidelity.md#连接状态的正式-web-复验)补27.K5双主题主图与27.K2/K3/K4有效深色图，跨版本覆盖107→108/169（63.9%）。7组六路快照和29条完成审计确认连接等待、受控401/403/503和显式恢复不写业务状态，主题草稿零附写、一次明确UI保存单列；20项官方Workers夹具回归、严格类型和依赖检查通过。连接故障浅色、未配置地址、进度新提示、全部变体及真实生产Access仍待，PR仍草稿未部署。

2026-11-16，`e8646f5`完整push/PR CI及Web/Wasm通过。[新读取提示正式Web复验](verification/mihon-cupertino-fidelity.md#迁移读取提示及失效状态的正式-web-复验)在浅/深主题分别验证未知及拒绝期间的读取失败反馈；33组九路快照和202条完成审计核对原请求保留、两次精确重试零重复、拒绝/只读零附写。三个失效状态的名义浅色图实际均为深色，只登记有效深色图，跨版本双主题主图仍107/169（63.3%）。真实图片和显式处理拒绝迁移后的进度保存已恢复，连接阶段与迁移阻塞原因的提示缺口正修复；新提示正式产物、其余状态和生产继续待验，不能把覆盖率解释为PR整体完成率。

2026-11-16，`3a57cdf`完整push/PR CI及Web/Wasm通过。[迁移加载与故障正式Web复验](verification/mihon-cupertino-fidelity.md#迁移加载与故障的正式-web-复验)新增九对双主题主图，跨版本覆盖98→107/169（63.3%）。33组九路快照与256条审计确认三条迁移原命令各应用一次、两次精确重试无重复、两次真实409及四次迁移/封面400零覆盖；API准备与UI写入分别计数。浅色挂起未正常释放、夹具满额后的重读均单独排除。已复现并修正待确认期间的新读取失败被旧迁移提示遮蔽，34项迁移回归通过；新修复完整CI、正式Web和生产仍待，不以主图覆盖代表整体完成。

2026-11-16，[明确拒绝状态与迁移故障入口](verification/mihon-cupertino-fidelity.md#明确拒绝状态与迁移故障验收入口)修正封面和迁移拒绝后仍建议重试的说明，迁移400流程先复现再通过。52项封面/共享编辑面/迁移回归、17项官方Workers/D1/R2回归、三文件Dart与API/test严格类型及依赖分层通过。拒绝必须明确重读，结果未知继续精确重试；完整CI和正式Web双主题的后续分项见上项。

2026-11-16，`a9d880a`完整push/PR CI及Web/Wasm通过。[封面正式Web故障复验](verification/mihon-cupertino-fidelity.md#封面故障状态的正式-web-复验)补齐六对双主题主图；32组六路API快照与154条审计核对四次UI清除各应用一次、原请求精确重试无重复、真实409与明确400零覆盖，以及私有图片失败重试同一资源。浅色首次挂起审计未完成单列，深色等待正常释放；拒绝辅助说明、剩余变体与生产继续待，不以主图覆盖代表PR整体完成。

2026-11-16，`42bc9bb`完整push/PR CI和Web/Wasm通过。[正式Web浅色设置故障流程](verification/mihon-cupertino-fidelity.md#正式-web-浅色故障流程与关闭反馈修复)在官方Wrangler临时D1中执行，七路独立快照和43条设置审计确认三条成功漫画原命令、一次精确重试不重复应用、冲突/拒绝零覆盖。故障夹具12项Workers/D1回归通过。实拍暴露读取不能关闭、长表单反馈不在视口；修复后54项定向回归与两文件严格分析通过，读取关闭无迟到跳转或提交、保存仍禁止关闭。浅色过渡帧和旧字段帧保留且排除，新修复完整CI、正式Web双主题与生产继续待验。

2026-11-16，[本漫画阅读设置的状态呈现](verification/mihon-cupertino-fidelity.md#本漫画阅读设置的阶段与确认)在浅/深×1x/2x四项组件流程中先复现读取阶段无说明且误提示连接身份；分开reading/saving，并补齐源收藏和阅读器快捷设置的等待提示后，50项定向回归与七文件严格分析通过。原请求丢确认后精确重试只应用一次，重读零写入、冲突不自动重基、身份失效隐藏旧字段与旧确认；继承说明改为官方Cupertino分组页脚。24.K1–K11目标图与最小信息已补，正式Web双主题及完整CI继续待验，不以组件结果填主图格。

2026-11-16，[迁移返回焦点与位置的正式Web复验](verification/mihon-cupertino-fidelity.md#迁移返回焦点与位置的正式-web-复验)：`86d27e7`完整push/PR CI通过（868项Dart、531项Vitest、Web/Wasm）。浅/深正式Web以实际点击打开和取消章节选择、确认弹窗，跨独立API读取后原按钮位置保持且焦点恢复，九路API确认零写入；补齐深色范围、仅分类和搜索空态主图。语义定位点击后的位置变化仍有观察，可能包含工具自动滚动影响，不据此认定唯一原因；全部输入、变体、故障和生产仍待。临时标签已关闭、视口恢复，官方harness正常退出0。

2026-11-16，[迁移行宽、语言与语义的正式Web复验](verification/mihon-cupertino-fidelity.md#迁移行宽语言与语义的正式-web-复验)：`9228c11`完整push/PR CI通过（868项Dart、531项Vitest、Web/Wasm），正式Web双主题确认整行右侧点击、精确源语言和独立预览语义；补齐51–100映射分页、章节当前项/占用禁用/无匹配/清空及无原标记。九路API确认两次明确迁移各推进一次版本、零新增章节标记，查询/分页/取消零附写。该版延迟返回位置变化的原图保留；四种主题/字号先复现章节选择和确认取消未恢复按钮焦点，Hooks修复后19项迁移回归通过，后续完整CI和实际点击复验见上项。加载/故障/全部变体及生产继续按状态图推进。

2026-11-16，[迁移向导的Cupertino状态呈现](verification/mihon-cupertino-fidelity.md#迁移向导的-cupertino-状态呈现)通过65项不同定向回归、最终格式的三文件严格分析与完整格式校验。浅/深×1x/2x实际组件流程区分首次读取/失败/重读、只读预览、保存阻塞/丢确认、诊断、重开只读等待和精确重试；原请求两次发送只应用一次。官方分组、次级说明、标准绿色开关与系统错误色已接入，失效后隐藏旧操作。完整CI、正式Web全部双主题主图及生产仍待，不以组件证据替代。

2026-11-16，[Mihon 全界面重构](verification/mihon-cupertino-fidelity.md)进行中，最终统一Cupertino导航、控件、动态语义配色与转场，尚未通过全范围视觉或生产验收。`c5f6759`完整push/PR CI通过，含864项Dart、531项Vitest及Web/Wasm；[正式Web分项](verification/mihon-cupertino-fidelity.md#封面与选择语义的正式-web-分项)补齐双主题短/长列表当前项DOM语义，封面草稿、保存/替换、取消/确认清除及新文档读回。独立API确认六次封面提交各写一次、草稿/取消零附写，四次确认图片字节核对通过。[状态机](verification/mihon-state-coverage.md)19.K3/K4/K6/K7正常主图和K5非法输入变体已有；加载/等待、未知/拒绝/失效、图片失败、禁用项与手动系统取消仍待。浅色清除首张缺帧保留且排除主图，不外推全部转场通过。资料故障、迁移、空偏好、全部变体及生产Access/续读仍待；Komiic失败不记兼容通过，Karuyomi原生现场验收保持停止。

分类与批量分组`a9fb310`已有正式Web双主题菜单、名称/校验、草稿/取消、危险预览、分类选择与结果分项，独立API核对十次UI写入及各取消区间零附写。`bbf69d7`确认正文与新建语义修复的57项书架/主题回归、五文件严格分析和正式Web双主题空态/列表、Tab/Return、草稿取消及批量结果通过，独立API核对九次UI写入。未确认、暂停、拒绝和身份失效等主图仍待。

2026-11-13，[Liquid Glass](verification/liquid-glass.md)已按用户决定终止，[统一 Cupertino 已恢复并生产上线](verification/cupertino-ui.md#恢复-cupertino-后的生产复验)。PR #7 合入后主线 CI、742 项 Dart 回归、46 条公开资源与匿名 Access 门禁通过；内置浏览器确认导航、真实图片、翻页保存、主题保存及独立新文档第 2 页续读，独立 D1 核对续读前后状态一致。玻璃库、专用设置及资源已移除。原玻璃性能对照未完成，不宣称能耗结论；代码削减另立重构，原生现场验证保持停止。

2026-11-13，[Cupertino UI 迁移](verification/cupertino-ui.md)完成应用壳、业务页面、阅读器、诊断与原生 Access 页的代码切换，并由主线 CI 自动上线；三项目严格分析、742 项单并发 Dart 回归及完整 CI / Web 构建通过。移除应用直接 Material 依赖，生产手写 Dart 计入新增组件后净减 58 行；缺失组件通过重整选择、筛选、编辑与反馈流程解决。隔离内置浏览器与独立 API 已验证扩展维护、章节输入、真实两页阅读/缩放、设置草稿取消及确认保存、360px 分类/主题和独立新文档续读；发现的字体、焦点和弹层问题复验通过。[生产 Access 下](verification/cupertino-ui.md#生产发布)的真实阅读、翻页确认、设置覆盖/继承与独立新文档第 2 页续读均通过，独立 D1 核对一致；46 条公开资源与匿名 Access 门禁通过。原生现场验证仍停止。

2026-11-13，[Flutter 3.50 / Dart 3.14 更新](verification/flutter-3.50.md)首批已上线。固定 SDK 的严格分析、736 项单并发 Dart 回归、生成一致性、完整格式与完整 CI 通过；Material 独立包、主构造函数、内容哈希和 UI 调整后，生产手写 Dart 净减 60 行。真实 CI 产物的 36 条公开清单与官方 harness 缓存头通过；HTML 规范化修复已合入主线，47 项现网公开资源与匿名 Access 门禁完整复验通过。内置浏览器完成输入/焦点、设置覆盖/继承、1280×720 与 390×844 真实图片、缩放、旧标签跨发布保存及独立新文档第 2 页续读，独立 API/D1 核对通过。Wasm 候选已编译、性能对照仍待测，默认继续 JavaScript；原生现场验收继续停止。

2026-11-12，[Flutter 状态管理重构](verification/flutter-state-management.md)通过集中工程检查、完整分支 CI / Web 构建及内置浏览器实际主流程：采用 Riverpod generator、hooks 和实际启用的 riverpod_lint，三个 Dart/Flutter 项目严格分析、22 + 87 + 625 项测试、生成一致性及 Dart 格式检查通过。生产手写 Dart 净减 463 行，生成 423 行单独统计；并发写入、身份隔离、未确认草稿和资源关闭语义继续由实际回归约束。隔离身份完成安装/收藏源、设置覆盖/继承、真实 xkcd 阅读、跨源搜索与新文档第 2 页续读，独立 API 核对；原生现场验证保持停止，生产发布沿用主线 CI 自动流程。

2026-11-12，[扩展管理与浏览 UI 重整](verification/browse-ui-flow.md)通过本轮分项验收：完整格式检查、三个 Flutter/Dart 项目的严格分析与测试（客户端 621 项）及正式 Web/Worker 构建成功。内置浏览器确认安装、停用恢复、本机清理与自动补齐精确构建、收藏及语言筛选、真实 xkcd 阅读/保存、退出阅读后跨源搜索和关闭旧标签后的新文档第 2 页续读；独立 API 确认保存位置。[新 UI 已生产上线](verification/browse-ui-flow.md#生产发布)，主线 CI、静态交付、真实 Access 登录、Komiic 热门列表及扩展管理最小检查通过。普通 Source 缩略图资源通道尚未接入，原生验证继续停止。详细记录区分隔离浏览器、最终工程和生产分项证据。

2026-11-11，[七材料中文与全语言首批](verification/seven-material-release.md#首批生产发布与验收)已上线：197 包终态，加上此前完成的 7 个阿拉伯语包，共 190 包可分发、14 包失败。Worker `a6cd3ee6-bb09-414f-81bd-1a77b9c953f1` 承接全部流量；26 条匿名交付检查、D1 连续至 `0010`、真实生产 Access 下 xkcd 更新/两页保存/关闭后新标签第 2 页续读，以及正式 `commit-snapshot` 均通过。分批切换不继承旧完成标记的 31 项回归和完整 CI 通过；`bootstrap.complete=false`，其余 1,244 包已在 clab 从新检查点恢复，完整基线和有界增量仍待完成。清单保持 `compiled_unverified/runtimeReady=false`。本机没有编译 AOT 或 Flutter，原生验证继续停止，不使用 pku-dasys。

2026-11-11，[原生模拟器生产登录预检](verification/first-web-release.md#原生模拟器生产登录预检)通过：首发六材料的 Android release 临时签名副本与 iOS 正式入口 debug 构建均打开真实 Access 表单，包内材料核对一致；iOS 外部 XCTest 1 项通过。原生账号登录、生产三端接力、正式签名和真机仍待验。

2026-11-11，[生产代表源整章与续读](verification/first-web-release.md#生产代表源整章与续读)通过。真实 Access 测试账号用同一首版分别完成 Arknights Comics 51 页及 CuuTruyen 23 页，逐页获服务端确认，标记读完后跨章；两者均从独立新标签页恢复下一章第 3 页实图。生产 Web 现有三个代表源的阅读证据，Native 生产及签名真机仍待验。

2026-11-10，[0.1.0 Web 与 API 已上线](verification/first-web-release.md)。生产 D1 账本连续至 `0010`，首份六材料扩展基线已确认。真实 Access 测试账号已通过 xkcd 读图、收藏、服务端保存与新标签续读；清理后新开章节也显示首图并保存。正式签名、真机和生产同账号三端读写仍待验。

2026-11-10，[六材料首发修复合并预检](verification/aot-current-pilot.md#六材料首发修复合并预检)通过：首发归档合入 Android 签名配置和横屏修复，Arknights 单包的正式 Web/Worker 构建和 Wrangler 部署预演、43 项定向阅读回归、双端 arm64 未签名构建及包内六材料核对均通过。完整快照、生产和签名真机另验。

2026-11-10，首发六材料的 [Android xkcd 同版本换构建后章节缓存](verification/source-cache-native.md#2026-11-10android-同版本换构建后复用章节正文)通过。切换静态目录和检查更新均未更改账户选择；明确确认后，新进程从书架恢复到第 2 页，重新请求原图但没有请求章节 HTML。清除本地 App 数据、保留同一 D1 后，章节恢复一次完整请求，正文摘要与首次相同。

2026-11-10，[Android 阅读中书签丢确认与 iOS 冷启动读回](verification/bookmarks.md#2026-11-10native-在线阅读书签丢确认与跨端读回)通过。Android 保留原图和待确认操作，iOS 在重试前读回已提交的书签；Android 刷新不重发，显式重试同一请求。六路独立 API 响应及 D1 审计确认只提交一次，进度不变。Web、生产和真机另验。

2026-11-10，首发六材料的 [iOS](verification/native-main-entry.md#ios-阅读中切换身份)和 [Android](verification/native-main-entry.md#android-阅读中切换身份)模拟器换身份通过。A 的完成请求收到 401，切到 B 时退出旧 Reader 且不重发；仅 B 的显式扩展安装新增一条设置回执，B 冷启动只读，A 的 D1 记录不变。生产 Access 与签名真机另验。

2026-11-10，[CuuTruyen 六材料 Native 完整章和接力](verification/aot-current-pilot.md#cuutruyen-的-native-完整章节与跨端续读)通过。Android 模拟器逐页显示并完成第 142 章 23 页，进入第 141 章保存第 3 页；iOS 同库续到第 4 页，Android 新进程读回。D1 仅为 iOS 翻页新增一条回执，最终读回无写入。生产、真机和完整快照另验。

2026-11-10，[iOS 阅读中重登与显式重试](verification/native-main-entry.md#ios-阅读中-access-失效与待确认进度)在六材料归档和隔离 D1 通过：401 与恢复原位不提交，显式重试按原请求只写一次，收起恢复控件不写，主动翻页再保存。[Android 复验](verification/native-main-entry.md#android-阅读中-access-失效与原位恢复)中，401 后重登、原位恢复及直接退出的 D1 业务状态与基线完全相同。生产 Access 与签名真机另验。

2026-11-10，[iOS Arknights 阅读性能基线](verification/reader-baseline-ios.md)取得一轮正式 iOS debug 模拟器原始数据：Flutter 首次图像帧、连续翻页、固定滚动、跨章帧与 App 自身 RSS 均有样本。没有把 Flutter 图像帧当作物理屏幕呈现；真机、WebContent/GPU 与分布门仍待验。

2026-11-10，[Android 源迁移已提交后丢确认](verification/source-migration.md#android-源迁移已提交后丢确认)通过。隔离 D1 已完成英文到中文 xkcd 迁移后截断首个成功响应，正式向导保留原请求；显式重试恢复确认。真实 D1 核对两次请求相同、只持久化一条迁移回执，新进程读回无附带写。

2026-11-10，[Native 本机服务地址恢复](verification/native-main-entry.md#native-本机服务地址恢复)已通过组件回归、完整 Flutter 检查和正式 Web/Worker 构建。iOS 模拟器两个正式进程均未传默认地址，第二次从实际本机偏好恢复并连接同一测试身份，独立 D1 未见业务写。

2026-11-10，[Android arm64 发布构建与冷启动](verification/native-main-entry.md#v6-android-arm64-发布构建与离线模拟器冷启动)通过。固定 `2c012db` 的 arm64-v8a release APK 包内运行时与冻结 v6 六份材料匹配；用本地调试签名侧载专用 Android 模拟器，冷启动显示正式书架。该次未连接服务，发行签名、真机和生产另验。

2026-11-10，[Android 同版本扩展构建替换](verification/extension-version-native.md#操作与独立核对)通过。真实 xkcd 经显式确认切换构建、清理旧缓存，新进程从书架首次解码第 2 页。独立 API 和 D1 证据只新增一条设置回执，进度与书签不变；真机、生产和上游版本升级另验。

2026-11-10，[iOS 同服务重连与书架续读](verification/runtime-reconnect.md#ios-同服务重连与真实续读)通过。同一正式进程重建运行时，更换 Source generation 和图片目录，书架两次打开真实 xkcd 第 2 页；六路独立 HTTPS 响应逐字节不变。生产 Access 与真机另验。

2026-11-10，[Android 与 iOS 同库源迁移](verification/source-migration.md#android-与-ios-同库迁移)通过。Android 为英文 xkcd 第 2978 章保存已读和书签，iOS 用正式向导映射到中文并确认，Android 新进程读回。确认前七路响应字节不变；确认后账户／英文／中文 revision 从 `4/3/0` 到 `5/3/1`，读回无附带写入。Web↔Native、故障、生产与真机另验。

2026-11-10，[Arknights Comics Android 完整章节与续读](verification/aot-current-pilot.md#arknights-comics-的-android-完整章节与续读)通过：真实《DREAM》逐页显示 51 页，显式完成后进入《HEARTBEAT》，新进程从书架首次显示已确认的第 3 页。[同库 Android↔iOS 接力](verification/aot-current-pilot.md#arknights-comics-的-android-与-ios-模拟器接力)中，iOS 从第 3 页翻到第 4 页，Android 新进程首次显示第 4 页。只读 D1 回执区分导航与实图观察；两端打开没有附带写入。生产与真机另验。

2026-11-10，[iOS→Android→iOS 同库封面交接](verification/custom-covers.md#ios-与-android-模拟器同库封面交接)通过。iOS 从实际 Files 上传，Android 解码同图后清除，iOS 新进程显示默认占位。D1/R2 独立确认恰好两次提交，重启只读，旧路径 404。Web↔Native、故障、生产与真机另验。

2026-11-10，[iOS 模拟器自定义封面](verification/custom-covers.md#ios-模拟器系统选择器与新进程读回)通过。两次实际系统 Files 选择、上传、替换和清除后，新进程读回默认封面；独立读回确认三次写推进 revision，清除后的两份旧路径均撤销。混合平台、故障、生产与真机另验。

2026-11-10，固定 `2c012db` 的 [iOS arm64 发布构建](verification/native-main-entry.md#v6-ios-arm64-发布构建)通过。实际 Runner 与 Dart AOT 均为 iOS arm64，包内运行时与冻结 v6 六份材料匹配。未签名、未安装，真机与生产 Access 另验。

2026-11-10，[Android 模拟器正式源迁移](verification/source-migration.md#android-模拟器正式源迁移与新进程读回)通过。独立隔离 D1 中，真实 xkcd 英文到中文的搜索、热门和手动映射在确认前未改变七份 API 响应；确认后复制一章已读和一枚书签，保留原作，不复制页位。新进程读回通过；混合平台、故障、真机与生产另验。

2026-11-10，[iOS 模拟器详情续读位置读取失败与显式重试](verification/reading-entry.md#ios-模拟器详情续读位置读取失败与显式重试)通过。真实 xkcd 第 2 页已保存后，详情状态读取返回 503，仍保留章节列表；同一 Source 会话显式读回续读目标，六份 D1 响应不变，未重发 Source 中继或业务写入。

2026-11-10，[Android 模拟器自定义封面](verification/custom-covers.md#android-模拟器系统选择器与新进程读回)通过。两次实际系统文件选择、上传与替换、清除和独立新进程读回均通过。独立 D1/R2 核对三个回执、当前引用和正文；旧路径撤销但对象保留至宽限期。iOS、混合平台、故障、真机与生产另验。

2026-11-10，[iOS 模拟器正式源迁移](verification/source-migration.md#ios-模拟器正式源迁移与新进程读回)通过。真实 xkcd 英文到中文的手动映射在确认前未改变七份业务响应；确认复制一章已读和一枚书签，保留原作，未复制页位。新进程从书架与详情读回，独立快照不变。Android、混合平台、故障、真机与生产另验。

2026-11-10，[iOS 重置获胜与 Android 旧完成冲突](verification/concurrent-server-state.md#ios-重置获胜与-android-旧完成冲突)通过。两条请求到达 D1 批次入口，隔离夹具安排 iOS 重置先提交；只有重置留下回执。Android 仍可翻动旧页，显式重开显示真实第 1 页；旧页、重开及退出均不覆盖权威状态。Web 配对、真机与生产另验。

2026-11-09，[iOS 与 Android 模拟器阅读进度同时写](verification/concurrent-server-state.md#ios-与-android-模拟器阅读进度同时写)通过。同一隔离 HTTPS/D1、同一真实第 2 页上，iOS 显式完成提交一次，Android 重置被拒；Android 旧页仍可翻动，显式重开读回完成状态。两端打开不写，冲突后的旧页、重开及退出也不改权威状态。真机与生产另验。

2026-11-09，[正式 Web 真实源迁移](verification/source-migration.md#正式-web-的真实源搜索与热门列表)通过。修正无搜索结果的源无法选择目标后，使用真实 xkcd 英文/中文完成手动映射第 2978 章；确认前七份 D1 API 响应无差异，确认后新增一章已读和一枚书签。新文档读回中英作品及目标标记。故障、Native 和生产另验。

2026-11-09，[Worker 更新后的 D1 读回与原样重试](verification/concurrent-server-state.md#worker-更新保留-d1-状态与原回执)通过官方本地 Wrangler harness：更新 Worker 验签密钥后，相同 subject 读到原书架和进度；旧请求返回原回执，不覆盖更新后的页位，也不增加 D1 写入。生产 Access 和设备 UI 恢复另验。

2026-11-08，[通用 Source 中继](verification/generic-source-relay.md)的本地正式构建、接口与内置浏览器 xkcd 中文热门列表均通过；无需扩展或域名登记。生产尚未部署。

2026-11-08，[生产 Web 恢复登录态](verification/server-state-production.md#生产-web-恢复登录态)已确认：用户自行登录后，Codex 内置浏览器中的生产页从 Access 过期提示恢复到正式服务端书架。同一正式会话随后通过 [Arknights Comics 英文热门列表](verification/server-state-production.md#生产-web-真实-source-列表)只读验收。生产详情、完整阅读和原生跨端验收继续。

2026-11-08，[双 Web 书架批量部分提交](verification/library-batch.md#双-web-部分提交与冲突恢复)通过：第一部确认并留下 D1 回执，第二部因另一会话的修改返回 409 且无回执，第三部未发送。只读结束后按最新书架重新确认余项，第二会话读回全部结果，其原分类关联保留。11-10，[Android 批量移出分类及书架，iOS 新进程读回](verification/library-batch.md#android-批量移出与-ios-读回)通过；隔离 D1 只新增四条预期回执，未选作品、保留分类和阅读标记未改变。Native 其余操作、断网或丢响应、生产另验。

2026-11-08，当前 v6 ToonLook [Web 长图、完整章节与续读](verification/aot-current-pilot.md#toonlook-的长图重排完整章节与续读)通过：两章各 10 页均在正式阅读界面显示，第一章完成，第二章在新文档恢复到第 10 页。六个受管 Blob 的独立像素对照覆盖五个非恒等重排和一个恒等控制；续读后页位、锚点和完成状态保持一致，D1 revision 有变化。未验 Native、性能或生产。

2026-11-08，正式 [Web↔iOS 模拟器分类双向写入](verification/category-ui-sync.md#web-与-ios-模拟器双向读写)通过：Web 创建并关联甲，iOS 读回、改名并关联乙，独立 Web 文档显示两部关联并可筛选。不同回环入口共享同一隔离 D1，最终独立读回不改变业务状态。同一服务亦通过 [Web↔iOS 全局设置](verification/reader-settings.md#web-与-ios-模拟器双向读写)：Web 保存浅色，iOS 读回并保存五项预设，独立新 Web 文档全部读回。[Web↔Android 全局设置](verification/reader-settings.md#web-与-android-模拟器双向读写)也通过同一流程，两次读回都不写入。同一日，[Web↔Android 模拟器分类双向写入](verification/category-ui-sync.md#web-与-android-模拟器双向读写)也通过：Android 改名并关联第二部，新 Web 文档读回并筛选，双入口独立 GET 核对无附带写入。生产、真机和其它门另验。

2026-11-08，MANGA Plus Creators 正式 Web 的[图片 Referer、跨章与新文档续读](verification/aot-current-pilot.md#manga-plus-creators-的图片-referer-和续读)通过限定抽样；两章观察到的 CDN 图请求都保留各自章节 Referer。Android 模拟器[真实容器重建与重连](verification/runtime-reconnect.md#android-模拟器复验)通过空 Source 分项。内置浏览器[未触发真实前台事件](verification/reader-settings.md#web-自动前台读回的观测限制)，Flutter 层自动读回回归通过，真实 Web 前台继续待验。

2026-11-08，同一 MANGA Plus Creators 候选修复前在 iOS 第 3 页超时，独立帧客户端经官方服务读到部分正文后收到远端超时帧，见 [HTTP 对照](verification/aot-current-pilot.md#manga-plus-creators-的-ios-图片超时对照)。

2026-11-08，HTTP v2 现区分源站读取空闲与整次调用总限，[正式 Workers 与 Host 回归](verification/aot-current-pilot.md#http-读取空闲与总期限回归)通过，六份共享材料与冻结输入逐字节一致。[MANGA Plus Creators iOS 复验](verification/aot-current-pilot.md#manga-plus-creators-的-ios-完整章节与续读)保留首轮第 33 页未解码及后续同页恢复；全新 D1 的第二轮通过首章 72 页、显式完成、下一章及新进程从第 7 页恢复至第 35 页，独立 GET 核对进度。其它作品、真机及生产未验。

2026-11-08，[iOS 和 Android 全局设置提交后丢确认](verification/native-settings-ack.md)在隔离 HTTPS/D1 分别通过；两端同一进程重读和原样重试，D1 各提交一次。

2026-11-08，正式 Web [全局设置同时保存](verification/reader-settings.md#双-web-全局设置同时保存)通过。两个文档的同 revision 请求在正式 Worker 的处理窗重叠 12 ms；一个成功、一个冲突，D1 只提交一次。冲突页读回后可按新版本重新编辑保存。Native、其它写入、生产 Access 与真机另验。

2026-11-08，[阅读进度同时写的正式 API 分项](verification/concurrent-server-state.md#阅读进度同时写正式-api-与-d1-夹具)通过：两个独立进程的完成／重置请求以同一 revision 到达正式 D1 原子批次，一个 `200`、一个 `409`，只提交一次。全库 `pnpm check` 通过（Vitest 522 项）。

2026-11-08，修正恢复相同阅读状态时的额外写入。Flutter 回归使用两个独立客户端加载同一已保存的章节与顺序，观察已确认的位置后作品 revision 不变；实际切到另一章则更新继续阅读目标。清单已变化的回归确认会保存修正后的当前锚点、保留已找不到的旧最远锚点。这是客户端控制器证据。

2026-11-08，[双 iOS 首轮准备](verification/concurrent-server-state.md#双-ios-阅读器的开章基线)实测确认另一路写入：新进程首帧解码时只有 `viewportY` 改变，作品 revision 从 3 增到 4，未放行并发操作。修复后，确认续读的首帧布局保留已保存的放置偏好。

2026-11-08，固定 `f3419d0` 的[双 iOS 模拟器阅读进度同时写](verification/concurrent-server-state.md#双-ios-模拟器阅读进度同时写)通过。两个正式 Reader 打开同一真实第 2 页未推进 revision；重置返回 HTTP 200 并留下唯一回执，读完返回 409。冲突端保持原画面，翻页未改变 D1，显式重开后显示新 epoch 的第 1 页。其它平台配对、正式 Reader 的完成获胜分支、生产 Access 与真机另验。

2026-11-08，[iOS→Android→新 iOS 进程的单作品阅读设置](verification/reader-settings.md#ios-与-android-模拟器单作品设置覆盖)通过：iOS 保存真实 xkcd 作品的方向、页组及显式关闭裁白，Android 读回并清空覆盖，新 iOS 进程恢复继承。两次只推进账户与目标设置 revision；另一作品、全局和完整阅读进度不变。实际裁白效果、Web↔Native 漫画设置、故障、生产及真机另验。

2026-11-08，正式 Web 的[阅读进度已提交后丢确认与精确重试](verification/concurrent-server-state.md#web-阅读进度已提交后丢确认)通过。内置浏览器在 xkcd 末页点「读完本章」，正式 D1 已提交但 HTTP 200 正文中断；界面保留待确认操作，显式重试复用 UUID、原始正文和 CAS，返回同一回执，六路独立读回不变。[iOS 模拟器同一丢确认场景](verification/concurrent-server-state.md#ios-模拟器阅读进度已提交后丢确认)也已通过，修正了内部控件重排导致的额外进度写入。[Android 模拟器](verification/concurrent-server-state.md#android-模拟器阅读进度已提交后丢确认)使用相同的当前 v6 xkcd 通过复验。双端模拟器在显式重试前后的独立六路响应均不变，各自审计只有两次原请求且 D1 只提交一次。此分项只覆盖丢确认与原样重试；生产 Access 和真机另验。

2026-11-08，正式 Android 模拟器的[阅读断连与显式重试](verification/concurrent-server-state.md#android-已加载阅读断连与显式重试)通过：定向 TCP 中断期间同一阅读页仍可翻到已加载图片，进度保持未确认，独立六路 D1 读回不变；恢复连接后显式重试确认，独立 iOS 正式入口续读到第 2 页并可回看第 1 页，最远进度保持第 2 页。此分项不覆盖全设备断网、服务端已提交后丢响应、生产 Access 或真机。

2026-11-07，两台 iOS 模拟器经同一受信 HTTPS / D1，通过[阅读前台 epoch 冲突](verification/concurrent-server-state.md#双-ios-模拟器前台-epoch-冲突)：B 正式重新阅读后，A 回到原进程和第 2 页，自动提示冲突；旧叶继续翻页未覆盖 D1，明确重开后恢复新 epoch 的第 1 页真实图。独立六路响应比对通过。2026-11-08 [Android A 恢复前台、iOS B 重置](verification/concurrent-server-state.md#android-前台恢复与-ios-重置同一账户)通过同进程和任务恢复、六路权威状态不变及显式重开。阅读自动前台重取在 Web 和其它设备组合仍待验收；生产 Access 和真机另验。

2026-11-07，正式 Web 的 xkcd 范围已读/未读通过三独立文档往返；首次发现同一详情收藏后误用旧作品 revision，显式重读可恢复，修复后的独立空库首次确认 3/3 通过。独立 D1 核对负对照、书签、设置及阅读锚点未变。2026-11-08，[iOS ↔ Android 模拟器范围往返](verification/chapter-read-state.md#ios--android-模拟器范围往返)也通过：iOS 标已读、Android 在已读筛选读回后标未读、iOS 新进程只读确认。两次各 3/3，独立 GET 核对只改变目标三章。Web ↔ Native、真实并发、批次故障、生产和真机另验。

2026-11-07，两台 iOS 模拟器经同一 HTTPS/D1 实测全局设置自动前台重取：A 真实进入后台，B 保存，A 同一进程回到前台并自动更新原表单与主题。见[前台设置记录](verification/reader-settings.md#2026-11-07ios-模拟器回到前台自动读回全局设置)；随后 [Android 模拟器从 iOS 保存读回](verification/reader-settings.md#2026-11-07android-模拟器回到前台读回-ios-保存)也通过真实系统前后台、原进程和原任务校验。全局设置的 Web 前台与生产另验；阅读进度按上文分项记录。

2026-11-07，正式 Web 全局设置已通过[真实 HTTP 丢确认与精确重试](verification/reader-settings.md#2026-11-07web-全局设置的真实确认丢失与原样重试)：首次 D1 已保存但响应正文中断，独立文档能读到确认值，原会话显式重试复用 UUID/CAS/原始正文，D1 只提交一次。其它写入、设备实际断网、Native 与生产 Access 分开验收。

2026-11-07，同一隔离 HTTPS / D1 和测试身份下，正式 iOS 与 Android 模拟器通过章节书签往返：iOS 添加 → Android 新进程读回并移除 → iOS 新进程读回。独立六路 GET 确认两次读回无附带写入，写入仅改变目标书签和相应 revision；环境与剩余门见[书签记录](verification/bookmarks.md)。Web ↔ Native、生产 Access 与真机另验。

2026-11-07，固定 `5ba6fff` 的日期修复通过 JDK/真实生成 JavaScript 回归，以及无插桩原 xkcd 正式 Web 的两次新文档重开和书签往返。独立四阶段 D1 核对：重开只读，移除仅改变目标书签与相应 revision。历史超时、修复后立即失败及最终通过分别保留在[重开记录](verification/source-reopen.md)。本地候选未部署；同源混合平台、生产和真机门继续验收。

2026-11-07，修复书架无差异打开仍更新资料、推进共享 CAS 的问题，14 项定向回归及完整 Flutter 检查通过，见[阅读入口](verification/reading-entry.md)。正式 Native 书签驱动严格分析通过；后续模拟器实测和内置浏览器对本地 HTTPS 的信任门见[书签记录](verification/bookmarks.md)。

2026-11-07，全局设置的真实双 Web 与双 iOS 模拟器顺序往返、新文档/进程恢复分项通过；双 Web 旧 CAS 拒绝与明确重读通过。修复了 Dart 显式 false/0 与标准 ProtoJSON 省略默认值导致的确认误判，完整 Flutter 检查、格式与构建通过。实际范围、修前失败与其余平台/漫画覆盖/故障门见[设置记录](verification/reader-settings.md)，不计为完整 P1/P2 或生产验收。

2026-11-07，有界跨源搜索的正式协议、服务与 Flutter 页面已接入。完整工程检查与 Web 三包真实 Source 的前台交接、空结果/原错误隔离、CuuTruyen 分页、活动停止和详情/图片阅读分项通过；浏览器发现的前台关闭竞态已修复并推送。物理双 Worker 独立观测、更多 Source、Native 和生产仍待验，精确输入、独立 D1 核对及限制见[跨源搜索记录](verification/cross-source-search.md)。

2026-11-06，官方 `kotlinx-coroutines-core-jvm` 已接入正式源码，自有 Green Job 与四个同名覆盖已删除。正式工程及远端 CI、JVM/AOT 的真实挂起与取消/父子/启动语义、owner/lease 分项通过；固定新 AOT 经正式 Web 主入口完成 BH3 协程详情及 21 页阅读、Komiic 镜像设置/重开与筛选分页，见[协程验证](verification/coroutine-runtime.md)。HTTP await 已恢复 seed 上游可取消实现，响应所有权及 ACK 前清理的正式 JVM 202 项与完整工程检查通过；随后固定 `48c4526` 的正式 TeaVM / Node HTTP 取消子门通过，clab 后台重建两包及本机正式 harness 构建/静态装配/三路径 HTTP 200 通过；Node 最终 runner 使用显式退出，尚非自然 idle，IAB provider 不可用导致该次实际 Source/UI 未执行。两包保持 `compiled_unverified/runtimeReady=false`，无部署或正式 checkpoint 变更；产品取消、Native / 生产等剩余门继续按[计划](plan/coroutine-runtime.md)验收。

2026-11-07，默认仓库扩展管理的账户确认清单、准备/取消、有界缓存、手动更新、启停/卸载与精确关闭/显式重建已接入，独立集中检查、445 项 Vitest、22 + 63 + 470 项 Flutter/Dart 测试与完整构建通过，见[扩展管理验证](verification/extension-management.md)。初次构建为 0 扩展，彼时 IAB provider 不可用；随后通过默认仓库的 Web 安装和 [iOS 模拟器同版本构建替换](verification/extension-version-native.md)分项，完整生命周期与各平台剩余门继续按[计划](plan/extension-management.md)验收。

2026-11-07，额外仓库的账户登记、只读预览与刷新、同包明确换仓、完整来源回显、存储/设置隔离及按来源网络政策已接入，独立集中工程检查、465 项 Vitest、22 + 68 + 527 项 Dart/Flutter 与完整构建通过。随后真实 IAB 发现并修复网络登记 GET 缺身份头，完整 Flutter 回归重跑至 22 + 68 + 534 项全部通过；固定当前三包 AOT 已取回，官方 Vite 装配 64 个 Static Assets / 3 扩展。空外仓管理、max-age 再验证、双 Web 顺序收敛及默认 xkcd 安装/两页真实阅读分项通过，独立 D1 确认收藏与第 2 页进度。精确范围与限制见[额外仓库验证](verification/additional-repositories.md)；真实外仓代码、Native 与生产待验收，`0009` 尚未部署。

2026-11-07，源迁移正式合同、三 CAS D1 原子写、只读预览与书架/详情向导已接入，并通过独立集中工程检查、完整 Flutter 回归与客户端/API 构建，实际范围见[迁移验证](verification/source-migration.md)。真实 Source、独立客户端、Native 和生产迁移仍待验收；工程通过不覆盖这些层级。

2026-11-06，typed Source preferences 的 v6 控制合同、原 Preference 回调、构造前注入、D1 独立 CAS API、客户端秘密值与 Flutter 设置/重开路径已实现；集中工程检查、固定 Komiic AOT、正式 Web 设置/重开和新文档恢复分项通过；其它控件、Native 及生产门见[设置记录](verification/source-preferences.md)，正式决定见[设计](design/source-preferences.md)。历史 v4/v5 证据不自动覆盖 v6。

2026-11-08，补上 Alpha Manga 原图片拦截器调用的 `Canvas.rotate(float)`；Android 与正式 TeaVM 图形桥同一组旋转/镜像/恢复像素断言通过，原 JAR 正式 AOT 与内置浏览器初始化通过。真实热门失败，同一正式帧独立重放获 CloudFront 202 challenge 空正文；真实章节图片、Native 与生产另验，见[旋转记录](verification/aot-current-pilot.md#alpha-manga-的-canvas-旋转)。

2026-11-08，固定 `975c650` 的 AsgardScans 1.6.3 原包通过 Android JSON 的 JVM 回归、正式 AOT、静态装配和内置浏览器初始化；真实热门请求失败，正式 HTTP v2 独立重放收到上游 404。详情 JSON-LD、章节和图片未验，快照未部署，见[验收记录](verification/aot-current-pilot.md#asgardscans-的-android-json)。

2026-11-08，Source 文本设置补上原 `EditText` 输入校验，拒绝无效候选后不会执行原 change listener 或默认保存；Java、跨语言与正式 Flutter 组件的[工程验证](verification/source-preferences.md#文本设置绑定与输入校验)通过；FoolSlide Customizable 与 MangaDex 的原包已隔离重建，MangaDex 的正式 Web UUID 校验与会话隔离通过。FoolSlide Customizable 修正网络政策错误分类后，真实 Web 在默认 URL 被拒绝时仍可打开设置；已通过默认值全选、无效 URL 拒绝、原回调归一化及新文档恢复。两者的会话文本均未写入 D1；FoolSlide 默认源站、Native 与生产未验。

2026-11-06，typed Source 筛选的 Protobuf、原 Java Filter 子类保留、Flutter 编辑及空查询搜索/分页链路已接入；本次开发 host ABI 升为 v5。修复后的两包代表 AOT 与 CuuTruyen 真实 Web 动态标签、空 query、分页及重置草稿关闭后继续原查询分项通过。显式快照保留和活动取消的运行代次回收边界见[设计](design/source-filters.md)，工程结果、固定构建身份与其余真实 Source/平台待验门统一见[筛选记录](verification/source-filters.md)。历史 v4 生产与在线结果仍绑定原构建，不自动覆盖新 ABI。

2026-11-06，正式浏览页的当前包 Source 语言筛选已实现；仅投影已加载 `SourceInfo.lang`，切换包或 generation 重置，不改变已选 Source、不为筛选请求 Source 或写业务状态。设计见[包内语言筛选](design/source-language-filter.md)，正式组件结果与仍待完成的实际 Source/平台门维护在[验证记录](verification/source-language-filter.md)，不宣称全目录语言检索已实现。

2026-11-06，收藏源与快捷打开已接入生成全局设置、既有 Worker API + D1 和正式浏览入口。稳定 package/source 身份、完整全局 CAS、原请求重试与打开边界见[设计](design/source-favorites.md)；合同/API、共享 Dart 数据及其余工程检查的实际范围见[收藏源记录](verification/source-favorites.md)。独立客户端、真实 Source/索引更新、生产 Access 与目标设备继续验收，不能把本轮受控组件结果当成完整 P3 通过。

2026-11-06，书架直接续读、详情失败显式重试、续读位置只读重取及书架资料原请求重试已接入正式 Flutter 入口。稳定章节/位置/顺序恢复、未确认写隔离和迟到结果边界的受控组件记录见[续读与恢复](verification/reading-entry.md)，设计见[阅读入口](design/reading-entry.md)。实际 Source、独立客户端、生产 Access 和目标设备分别验收，不将本轮组件结果提升为完整 P1/P2 通过。

2026-11-08，[Android → iOS → Android 分类重排后删除](verification/category-ui-sync.md#android-与-ios-重排后删除)在同一隔离 HTTPS / D1 上通过，三个正式入口阶段各 1/1。重排保留两个关联，删除只更新受影响作品，最后新进程读回无附带写入。Android 间歇性初始化问题仍待定位，Web↔Native 对应操作、生产与真机另验。

2026-11-08，[正式 Web 书架直接续读](verification/reading-entry.md#正式-web-书架直接续读)在隔离 D1 上通过：Codex 内置浏览器独立文档顺序交接真实 xkcd，直接恢复第 2 页；回看第 1 页后再开，最远仍为第 2 页。两次直接恢复均不改 D1。混合客户端、生产与真机另验。

同日，[iOS↔Android 模拟器书架续读](verification/reading-entry.md#ios-与-android-模拟器书架续读)通过：修复迟到解码尺寸引起的同点视口放置更新后，Android 直接恢复第 2 页不写入，回看第 1 页只提交一次，新 iOS 进程直接恢复第 1 页且最远仍第 2 页。Web↔Native、生产与真机另验。

同日，[正式 Web 详情开章重试](verification/reading-entry.md#详情开章故障验收入口)通过：指定 xkcd 章节只注入一次 502，失败前后 D1 状态一致，详情内显式重试显示两页并确认保存。续读读取错误、Native、生产和真机另验。

2026-11-08，[旧网络登记到通用中继的切换演练](verification/d1-relay-cutover.md)在隔离 workerd/D1 通过：确认旧版与 `0004–0008` 兼容，`0009` 同时停止旧中继并满足新版 Source 设置 schema，切换新版后应用 `0010` 保留书架、位置和作品写入回执。生产迁移与发布未执行。

同日，[Source 设置采用通用包名](verification/generic-source-relay.md#第三方包名)。安装、正式启动校验和设置 API 的工程回归覆盖非 `eu.kanade.` 标识，完整检查与正式构建通过；实际外仓 Source 与生产另验。

2026-11-06，自定义封面已接入生成业务协议、Worker API、D1 当前引用、私有 R2 及正式详情/书架 UI；上传使用独立二进制 multipart 与同一作品 mutation 的 CAS/ACK，清除沿 JSON mutation。共享数据及集中工程检查已通过；2026-11-07，独立 Web 文档的上传、替换、清除和读回已通过，两份旧封面路径撤销。见[自定义封面记录](verification/custom-covers.md)及[对象宽限清理和身份设计](design/custom-covers.md)。Native、故障恢复及生产私有 bucket 绑定与部署尚未验收，不能据此认定完整 P1/P2 通过。

2026-11-06，章节范围已读/标未读已接入正式协议、D1 与详情 UI，包含读状态筛选、保留隐藏选择的多选/反序范围、串行精确确认和恢复。真实 Worker/D1、Dart 数据与正式组件结果及其实际范围见[章节状态记录](verification/chapter-read-state.md)；本轮还修复无 metadata 移出书架被正式合同拒绝的缺口，并通过独立真实 Worker/D1 回归。独立 Web 与 Native 模拟器顺序实测见上文；生产与真机门仍待验收。

2026-11-06，正式书架已接入多选、逐漫画批量添加/移出分类和移出书架；冻结确认清单与 CAS，首失败停止，未确认项精确重试，余项显式继续。工程与组件结果维护在[批量操作记录](verification/library-batch.md)；实际独立客户端、生产和设备门仍待验收。

2026-11-06，详情章节搜索、来源原序/反序和书签组合筛选已接入，保留重复条目、原始 Source DTO 及章节索引；4 项正式组件导航回归通过，含未返回详情状态时恢复服务端阅读顺序。集中检查与实际平台范围见[章节浏览记录](verification/chapter-browsing.md)。

2026-11-05，收藏与阅读进度已接入生成业务协议、Worker API 和 D1 权威状态，本地业务 SQLite 与对应 Web 资产已移除。真实 workerd/D1 的并发、幂等、身份、分页及原子失败测试见[服务端状态记录](verification/server-state.md)；本轮全格式、通用检查与 Flutter 三项目静态分析/测试通过（21/42/208 项）。Codex 内置浏览器已通过真实 xkcd 的独立会话收藏→阅读保存→重启续读，见[实际 Web 记录](verification/server-state.md#真实-web-独立会话闭环)；随后正式 iOS `app.main()` 与 Web 通过测试身份下的双向非默认页续读、真实图片及回看最远进度保持，三次官方集成测试通过，见[Web↔iOS 记录](verification/native-server-state.md)。随后正式 Android 入口补齐 Web↔Android、iOS↔Android 双向非默认页续读，六次 Native 官方集成测试各 1/1 通过，新 Web 实际显示 Android 已确认的第 2 页真实文字图，见[Android 配对记录](verification/android-server-state.md)。双 Web 正式入口随后通过远端位置/epoch 更新保持旧画面、停止旧视图写入、未先刷新时正常写路径冲突及明确重开恢复，见[双会话记录](verification/concurrent-server-state.md)。客户端与业务 API 已[部署生产并通过匿名检查](verification/server-state-production.md)；当时尚未验证同时写竞争、实际自动前台重取、故障恢复、生产 Access 正向与真机，后续分项见上文。历史本地数据库恢复不代表当前同步完成。

2026-11-05，分类协议、D1 API 与 Flutter 数据层通过[数据层验证](verification/category-state-data.md)，管理/排序/筛选/多关联 UI 已接入，真实双 Web 的目录、关联、旧编辑冲突与重载恢复分项通过，见[分类 UI 记录](verification/category-ui-sync.md)；Native 分类后续分项见下段，生产正向继续验收。未采用的 `runtime/image-codec` 候选与专属构建工具已删除，默认只维护 UI 直接解码。项目自有 JS 构建已进一步收敛为声明式 Vite 配置与官方 CLI，旧 builder、独立资产组装和不适合官方集成的探针已删除。Workers HTTP/状态、生成配置 harness 与内置浏览器新版 Browser 测试通过；完整构建、格式、Flutter 与通用集中检查通过，范围及限制见[Vite 记录](verification/vite-build-and-testing.md)。

2026-11-06，正式 `app.main()`、Native runtime、正常受信 HTTPS 与同一隔离 workerd/D1 下，双 iOS 以及 iOS↔Android 分类顺序五阶段已通过：创建关联、另一端改名/关联、新进程读回、删除保留收藏及新进程未分类读回，见[分类多端记录](verification/category-ui-sync.md)。Android 最后阶段曾因 DDS/容器初始化失败，保留失败后仅冷启动 AVD，原只读阶段才通过；初始化可靠性根因仍待修复。内置浏览器未信任此本地 CA，未绕过警告，因此 Web↔Native 分类、生产 Access、真机、并发故障与完整 P1/P2 均保持未验收。

2026-11-06，章节书签的 Protobuf 合同、D1 原子 mutation / 有界查询、共享 Dart 数据层以及正式详情与阅读入口已接入，工程与组件范围见[书签记录](verification/bookmarks.md)。该轮只验收工程与组件；后续实际 Web 独立文档和 Native 模拟器闭环见页首，生产另验。

2026-11-03，本地 macOS。Flutter 3.47.5 / Dart 3.13.4、pnpm 12.6.0；仓库固定 Node 24.15.0，本轮也使用 Node 26.5.0 执行检查。TeaVM 固定 0.16.0 JS backend，验证 JDK 为 Oracle GraalVM 25.0.4、Maven 3.9.11。下表区分代码/分项测试、独立机制探针与尚未完成的产品验收，不以测试总数作为能力证明。

当前图片交付已收敛为 Source 处理后的不透明编码资源，由 Flutter/UI 直接解码；工程回归、诊断性原 xkcd 阅读/恢复和默认关闭的计时采集入口见[UI 图片边界](verification/ui-image-boundary.md)。采集入口尚未取得正式性能数据，长图、真机与进程/GPU 门保持未通过。历史[编码页记录](verification/encoded-image-ownership.md)和[图片页控制记录](verification/image-page-controls.md)保留原输入与范围；其 host 编码页/tile 合同已退出当前产品路径。

2026-11-06，现有三项非敏感设置的协议、D1、API 与正式 Flutter UI 已接入：全局主题、四种阅读模式、AUTO/SINGLE/DOUBLE 页组及逐字段漫画覆盖。独立作用域 CAS、原子确认快照、幂等、继承和清空覆盖的后端分项通过；客户端/集中工程检查已通过；结果及仍待验收的实际跨端、生产和真机门分别维护在[设置记录](verification/reader-settings.md)。背景/亮度与可配置输入、适宽/适高及裁白随后已实现，分别见[外观记录](verification/reader-appearance.md)、[适配记录](verification/reader-fit.md)和[裁白记录](verification/reader-crop.md)；独立客户端与设备门分别维护。

## 工程与代码验证

GitHub 已确认 `Wybxc/karuyomi` 为公开仓库。gitleaks 8.30.1 对截至 `c1c9e7f` 的全部 Git 历史扫描，10 处命中经核对均为文件 SHA-256（8 处）和公开 Access AUD 标识（2 处），未发现实际凭据。当时的 Release 资产清单为 AOT、清单/构建记录与锁定的运行时构建材料；原始扫描报告留在忽略目录，不写入源码。

公开 Release 的浏览器下载门未通过：内置浏览器对下载入口与最终 CDN 的普通 GET/Range 均无法读取正文，响应缺少 CORS 许可；API 对照另遇匿名限流。用户已决定改为全客户端最新版 Static Assets 权威分发，取消扩展 Release 发布，证据见[公开 Release 下载门](verification/github-release-delivery.md)。现已删除 90 个扩展/索引 Release 及对应 tag，GitHub 仅保留锁定的 `teavm-runtime-release9-v1` 构建依赖；旧扩展发布工作流在 baseline 验证期间保持停用。历史两包快照通过线上下载检查；当前已部署 v4 三包并通过[匿名静态交付](verification/v4-production.md)，全量 baseline 尚未完成。

| 范围              | 已有证据                                                                                                                                                                | 复验入口与限制                                                                       |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 协议 / TypeScript | 生成版本一致性、严格类型检查，JS Worker 与 API 边界分项测试通过                                                                                                         | `pnpm check`；测试覆盖协议/ABI、hash/预算、串行与代次、取消/超时、登录响应及错误分层 |
| 运行时桥          | Codex 内置浏览器执行真实 Worker、WebCrypto、npm Zstd WASM、Canvas、IndexedDB、隔离与重启持久化均通过                                                                    | [桥验证](verification/worker-bridges.md)；不等同于 Source 在线或图片阅读验收         |
| Dart / Flutter    | source_runtime、reader_core 与 app 的静态分析、协议/布局/调度/浏览/阅读组件测试分项通过                                                                                 | `pnpm flutter:check`；测试 Provider/渲染夹具不等于真实 Source 或真机                 |
| 构建与静态入口    | 已完成本地 JS 宿主、Flutter Web release、同源资源组装及 Wrangler dry-run；公开 shell 与控制页可加载                                                                     | `pnpm build`、`pnpm dev`；dry-run 不部署，也不证明生产 Access                        |
| 静态分发 / D1     | 最新索引/清单/gzip、API 正文路由移除、D1 仅网络政策；本地真实 workerd 静态路由和政策继承已验证                                                                          | `pnpm test` 的官方 Workers/harness；历史静态探针已退役，受控夹具不是 Source 在线证明 |
| JWT / API         | 本地 RSA 密钥真实签名测试覆盖 issuer、AUD、本人邮箱/可选 subject、过期/伪造凭据、固定回跳、路径规范化与 API 不落入 SPA；静态正文绕过 Worker；动态请求按 D1 域名政策授权 | `pnpm exec vitest run apps/api/test`；测试签名不是 Cloudflare 签发的生产会话         |
| 阅读核心          | 单/双页、LTR/RTL、封面/横图独占、竖向/Webtoon、缩放/翻页、逻辑锚与布局恢复、取消/释放确认和迟到资源清理                                                                 | `pnpm flutter:check`；窗口预算为实现约束，估算解码像素不等于实测进程/GPU 峰值        |
| 设计溯源          | 初次导入摘要记录在[设计文档来源](verification/design-provenance.md)                                                                                                     | `docs/design/` 已解除冻结，摘要不用于声称当前文件仍是初始副本                        |

历史私有交付实现曾在本地与云端注册构建 `release9-mangadraft-product-e3505206005c25f69b92`：7 个私有产物，共 3,957,861 字节，云端查询状态为 verified。登记前逐文件校验长度/hash，构建与产物关联只在完整写入后可见。本地真实 workerd/D1/R2 加 RS256 测试签名探针已检查 manifest/list、全部 R2 SHA-256、HEAD/304/Range/416、缺 JWT/错误 AUD/错误 host 及整批冲突回滚，见 [API 探针](../apps/api/test/README.md) 与 [证据](verification/runtime-evidence.md#通过的分项与限制)。测试入口仅信任本次生成的公钥，产品没有鉴权绕过。

## 执行器与第三方库直接接入

2026-11-03，固定 Node 24.15.0 下完成 execa 迁移与 `tools/lib/` 删除。调用点直接使用 execa、json-stable-stringify、write-file-atomic、is-plain-obj、fflate/tar/yauzl、diff 和 get-stream；没有将通用包装换目录恢复。dependency-cruiser 检查 134 个模块、485 条依赖通过，禁止重新导入 `tools/lib/`。全库 `pnpm format`、`pnpm format:check` 与 `pnpm check` 通过，包含 256 项 TypeScript 测试、真实本地 D1 CLI、归档/补丁/静态分发及受控 origin 的 workerd HTTP v2 回归。

执行器回归真实运行 Unicode/元字符 argv、10 MiB 双流日志和过滤后的环境；checkpoint 校验失败保留旧内容，原子替换保留 0600 权限、末尾换行且无临时残留。41 项扩展发现/流水线/runner 回归包含 SIGINT/SIGTERM、正常退出仍有继承或独立 stdio 的后代，以及真实锁被删除后的失锁检测；后代停止后才允许锁释放和后续状态操作。Cloudflare 部署领域函数的 9 项无网络 CLI 回归覆盖合并输出正好 512 KiB UTF-8、两路总字节溢出、凭据脱敏、取消后独立恢复，以及正常退出和取消时 TERM-resistant 后代在函数返回前停止。这些测试没有重新执行线上权限探测或部署。

同期接入唯一 `.proto` 与 Buf，Protobuf-ES/Dart 官方生成模型用于正式 API、Source/Worker 与 Web/Native 控制边界；`pnpm generate:check` 检查生成文件全集和字节，9 项实际 TS↔Dart golden 覆盖 ProtoJSON/二进制、oneof、可选字段、精确 memo 数字文本及业务预算。`pnpm flutter:check` 的静态分析及 71 项测试通过；`pnpm build` 完成宿主、Native 材料、Flutter Web release、空扩展索引组装及 API Wrangler dry-run。Java DTO、HTTP body、图片和 Locale oracle 也通过。复验范围和命令见[协议计划](plan/cross-language-protocol.md)与[工具计划](plan/tooling-processes.md)。

2026-11-05 功能收尾时 host ABI 为 `karuyomi-source-host-v4`，protocolVersion 2 / HTTP bridgeVersion 2 不变。Access 阅读暂停/同身份恢复、namespace 执行互斥、后台 enqueue owner/drain 和 Android 异常退出文件清理已实现，先完成实现再集中回归，见[功能收尾记录](verification/p0-feature-completion.md)。新 Java 调用约定需要重建 AOT 与 Web/Native 材料；下述历史 Source、Native 与生产记录保留原提交/ABI，不自动计为 v4 通过。

随后固定 `1f599cd` 的三包 v4 原 Source 已重新 AOT，在内置 Chromium 156 通过元数据、原图片处理、2/3/3 张图片解码与释放；正式 Flutter xkcd 阅读完成、同 namespace 第二标签占用失败及关闭持有标签后重开也通过，见[v4 分项](verification/v4-source-runtime.md)。另以真实 TeaHost/BrowserCall AOT 和受控 Source/HTTP-v2 端点通过嵌套 enqueue、异常、取消及旧 owner 隔离，见[回调分项](verification/teavm-enqueue.md)。该次本地验证未部署，不提升流水线兼容标记，不替代生产 Access、Native 或真机验收。

随后固定 `13494a0` 的正式客户端/API 与这三包曾部署，Worker version 为 `9a95d6e6-7578-4781-99aa-3d8bdae6b467`，snapshot revision 为 `702cc6bfb2974682bf1c83325458535a`。26 个匿名路径、三包完整性和旧资产 404 均通过，远端三包显式网络政策已核对，正式 checkpoint 已确认。完整身份与当时的 Access 限制见[v4 生产记录](verification/v4-production.md)。该快照的 `bootstrap.complete=false`，后由 0.1.0 六材料基线替换。

当前 v4 的正式 `lib/main.dart` 已重新构建为 iOS Simulator App 和 Android arm64 调试 APK，双端实际包内 manifest/host/worker 与当前材料逐字节一致，SQLite 映射和导出通过，见[Native 构建记录](verification/v4-native-main.md)。iOS 首次官方库下载失败保留，使用经固定摘要校验的标准缓存后成功；未修改第三方 hook。CUA 仍无法连接 Simulator，App 未安装/启动，不能认定当前 Native UI、Source、Access 或真机通过。

实际 TeaVM 回调门随后补齐产品 manager/Worker/driver 组合：64/65 pending 上限、真实约 30.05 秒 fatal drain、未发送的排队任务拒绝、上游连接关闭、namespace 释放及同 namespace 新 Worker/代次恢复均通过，见[组合记录](verification/teavm-enqueue.md#实际-callback-上限fatal-drain-与-manager-回收)。这是受控 Source/HTTP 端点，不代替官方 Source、生产 Access 或 Native。

P1 本地收藏书架随后接入正式 `main.dart`，支持详情收藏、搜索/排序、按当前索引重开原 Source 和继续阅读；真实 SQLite 文件关闭重开、已有进度增表保留、身份隔离及写入失败恢复通过，见[本地书架分项](verification/p1-local-library.md)。该实现只在当前设备保存，D1 云端状态与 outbox 未实现；组件 Source DTO/viewport 夹具不代替浏览器、Native UI 或生产验收。

2026-11-05，用户将多端同步提升为首要设计目标，Worker API + D1 为唯一业务权威，见[调整后的主线](plan/p2-sync.md)。上述本地书架/进度证据按原实现保留。该次计划调整本身没有实现 D1 业务表、同步 API 或跨端恢复；随后实现及当前实际三端证据见本文开头，不以历史本地恢复或计划声明提升验收状态。

此前控制身份为 host ABI `karuyomi-source-host-v3` / protocolVersion 2，HTTP bridgeVersion 仍为 2。浏览器探针入口已迁至单一 control 和正式生成 codec。固定 `6e08ec9` 后，原版 Arknights Comics 已重新 AOT，并在 Codex 内置浏览器通过初始化、真实 Source 元数据和首中末图片门，见 [v3 运行证据](verification/protocol-v3-runtime.md)。该历史记录不证明 v3 的生产部署或剩余运行门，当前直接维护 v4。生产 Access 正向 bootstrap 的历史证据见下文。下文 v2 图片和 v1 部署证据仍保持原身份；冻结 `022d828` 全量未改动，不能把其产物装配进当前客户端。

同日将正则供体类命名从补丁移入构建生成步骤，使用 `java-parser` token 位置保留原排版与字面量，再应用行为补丁；全部 13 份生成 Java 与拆分前逐字节一致，原输出摘要未改。回归覆盖刻意保留的上游类型转换、Lexer 引用与继承关系、字符串/文本块和注释不误改，以及源码/上下文/结果漂移拒绝。`toolchain/license.txt` 同时改名为 `android-sdk-license`，仅更新锁中的路径，41 字节内容与摘要不变。

## Android 普通文本布局分项

2026-11-04，项目 owned `TextPaint`/`Layout`/旧构造器 `StaticLayout`、真实 Canvas 字体指标与有界布局已接入，并补齐 TextInterceptor 使用的 HTML 字符串投影。Codex 内置浏览器 Chrome 156 通过 Canvas 五组机制门及同份 Java 101 项检查；独立固定 API 35/Robolectric 4.17 的 Android NATIVE oracle 同样通过 101 项，并断言真实 native shadows 和固定 instrumented SDK 身份。两端默认字体输出分别为 1000×140 与 1000×190，不声称高度或 PNG 像素等价。新增 CRLF 场景曾在 TeaVM 失败，修复后完整重跑通过；浏览器资源账本均归零。

这些机制证据覆盖 HTML plain-string、UTF-16 range、padding/spacing/行宽、普通文本绘字与预算。固定 `926b93d` 后原 xkcd 两页及 Flutter 可见文字已通过；固定 `5148c60` 的新文件/Bitmap 生命周期宿主重 AOT 后，两页也已通过。原 JAR 摘要保持一致；重复处理与内部自然回收、生产 Access 和 Native 应用分别验收。旧 host 的 Android Stub 失败证据保留。正式入口、原 Android plain 状态反向断言及未验范围见[文字布局记录](verification/text-layout-runtime.md)与[计划](plan/text-layout.md)。

## Cache 生命周期与有界正文分项

正式 Cache 桥直接使用 `idb@8.0.4`，正文为最多 64 KiB 的二进制块，metadata 与正文分开；snapshot pin 保留被替换/清空后仍在读取的完整 body，visible 与 staging/retired allocated 分别计费。Codex 内置浏览器通过真实 Worker/IndexedDB/Web Locks 门，覆盖死亡 owner、CAS/generation、事务 abort、读者 snapshot、六类 chunk 损坏与中途关闭。reader-close 原事务失败后独立按 owner/handle/directory/reader 清理，保留原错误，避免 Java 已释放的 reader 永久 pin 正文。具体矩阵与正式复验入口见[Cache 记录](verification/http-cache-runtime.md)。

共享 `CacheScenarios.java` 分别在官方 Maven 未适配 OkHttp 5.5.0 与真实 TeaVM 0.16 产品 Cache/BrowserCall/二进制 JSO 中执行，经受控 workerd origin 对照冷/热命中、304、no-cache/no-store、POST invalidation、Cookie Vary 和 evictAll 后打开 snapshot。请求/网络/命中/成功写入及正文摘要一致；原 JVM 断言实际 CodeSource，避免误用 seed 同名适配 JAR。CacheSink 的存储写失败只丢弃缓存副本，不吞网络读取异常。

独立的[共享 Java HTTP 故障门](verification/cache-http-failures.md)已在官方原 JVM 与 Codex 内置 Chromium 156 的实际 TeaVM 各通过四场景、50 项检查：精确读取 8192 B 后截断或取消、Cache 关闭后同目录重开、半成品不可见、旧完整条目保留及网络恢复。另观察到本地 HTTP/1 中继两次真实 RST 和四条原点响应关闭，正式 runner 退出 0；不推广为生产 HTTP/2、HTTP/3 或真实 Access 取消。

已有新 Cache 材料的 Arknights/CuuTruyen 在线图片分项见[Source 复验](verification/graphics-source-runtime.md#新-cache-材料复验)，仍未实测其冷/热 Cache 命中。固定 `b4f72f7` 的新 AOT 随后通过[原 xkcd 元数据 fresh Cache 复验](verification/source-network-cache.md)：cold HTTP 200 并提交 7187 B，warm 实际 store entry / 正文读取 / EOF / close，零上游请求；两次页列表摘要相同。原图片 cacheless 仍各自请求网络，无 304 结论。独立 origin 的原 Source 又通过 12 项实际 manager/Worker 重建门：dispose 终止旧 Worker，新 manager/Worker 在同四维 namespace 命中并读完 7187 B、EOF / reader-close，零网络、同 PageList 摘要，最终两 Worker 终止。这只验同一浏览器文档内的重建；浏览器进程、正式版本/身份切换、生产 Access、更广 Source / 取消仍待验收。随后双端模拟器也通过[原 xkcd Native Cache](verification/source-cache-native.md)：cold 完整提交 7187 B，warm 与正式 Native 容器重建后读取相同正文至 EOF、零网络，逐会话与最终 dispose 确认；不是 App 进程重启或其它 Source 结论。

真实 manager/加载器/产品 Worker 与受控 TS ABI 在内置 Chromium 156 通过[namespace 与组合存储 11 组](verification/runtime-storage-namespace.md)：实际构建替换和 manager 重建后 IDB 数据保留、四维隔离，以及同一真实派生键下 Cache/files 各 128 MiB allocated、完整分块读回与清理。没有修改 usage 伪造边界；不代表 Java/官方 Source、生产 Access、Native 或进程/物理磁盘资源门。

## 有界普通文件分项

`5148c60` 已将普通文件改为 typed idb inode/chunk、64 KiB 二进制 JSO、稀疏文件、配额与 Web Locks owner。数据、路径、长度及账本同事务，提交后才更新 cursor/ACK；rename/unlink 保留打开 inode，失败关闭可显式重试。真实浏览器机制、原 JVM 和实际 TeaVM 的共享 File/RandomAccessFile/Okio 场景分别通过；首次实际 TeaVM 门发现的 EOF/unsigned 差异由项目自有 JCL 适配修复，没有修改 vendor 或扩展 JAR。

固定预算、原始失败与最终输入身份见[文件证据](verification/file-storage-runtime.md)和[设计](design/runtime-file-storage.md)。普通 files namespace 的逻辑/allocated 预算已经实施；与独立 Cache 的既定分区及实际组合压力已通过上述受控 ABI 门；正式 Source、Native、产品切换和设备资源测量仍待验，见[存储计划](plan/runtime-storage.md)。

## 阅读连续性分项

2026-11-03，阅读路由已接 Source 原序/反序、漫画作用域章节键与上一章/下一章控制；不按编号排序或丢弃重复 URL。每次切章等旧 Reader 的 scheduler、图片 pin 与 provider 清理 ACK 后才挂载新叶；下一章 pages 迟到和新 provider 在下一帧挂载前退出均被关闭。`chapter_sequence_test.dart` 与 `chapter_reader_route_test.dart` 覆盖空/零/小数编号、重复章的快照键、跨漫画/Source 隔离及延迟清理/退出竞争；相关 26 项组件回归和 Flutter analyze 通过。完整 `pnpm flutter:check` 通过三个包的静态分析及 15/23/50 项测试，完整格式检查通过。此时尚无背景下一章准备、Drift 落盘、真实 Source 章节连续阅读或真机证据，不据此标记 P0/P1 通过。

2026-11-04，正式 Drift 产品接线与数据库静态资源已完成，完整格式检查、通用检查、TeaVM 回归及最终格式化后的三个 Flutter 包分析/测试通过。Codex 内置浏览器实际阅读原版 Arknights，完成连续切章、回看不降低最远进度、关标签页重开后恢复章节/当前页/最远页/章节顺序，以及重新阅读回首页。固定输入、命令和边界见[Web 产品进度记录](verification/reader-progress-web.md)；此处不是浏览器进程重启、Native 应用或生产 Access 动态请求门。

2026-11-04，固定新 host 的 Arknights DREAM 51 页、CuuTruyen Chương 142 的 23 页已在正式 Flutter Web 逐页显示并保存，末页显式完成，同路由下一章开头也通过，见[完整章记录](verification/full-chapter-web.md)。手动单双页被控件高度变化覆盖的缺口已先以正式 Widget 复现再修复；重连旧身份与迟到 API/图片清理污染新会话也已通过正式回归修复，见[重连记录](verification/runtime-reconnect.md)。该轮完整格式化、`pnpm flutter:check`（Reader 102 项）及 `pnpm check` 通过；固定 `be5c3ed` 的正式 Flutter Web release 已通过修复后末页实际复验：手动单页保持、51/51 保存及显式完成、返回详情继续阅读，详见同一完整章记录；没有重新逐页阅读 51 页。随后同一正式客户端以原 xkcd 通过 Web A→B→A：B 无 A 的继续阅读、返回 A 首次恢复第 2 页文字图，三个 Worker 的 namespace 依次 A/B/A，真实 304 后从原 Cache 读取 7187 B 至 EOF 并关闭。首轮记录器失败和新 origin 完整复验分别保留，详情见重连记录；版本更新、Native 身份与生产 Access 仍待验收。

## 新图形宿主与生产 Access 分项

2026-11-03 至 04，固定 `15a3900` 后六包本地 AOT 通过；Codex 内置浏览器在新材料下通过 Arknights 首中末直图，以及 CuuTruyen 23 个真实 DRM 页中的首中末 Bitmap/Canvas 重排。Little Tyrant 与 Philia Scans 初始化成功，但元数据请求均被各自站点 403 拒绝，图片未测。MangaDex 原包 61 个 Source 初始化成功，英文 Source 的列表链因 HTTP 超时失败，图片未测。xkcd 元数据及直图成功，但原 TextInterceptor 文字图片遇到 Android Stub，完整图片门失败。具体输入身份、必要数量和限制见[Source 记录](verification/graphics-source-runtime.md)。这些测试使用隔离 D1 和测试签名，仍不是生产 Source 或 Native 证据。

2026-11-04，用户在 Codex 内置浏览器完成真实 Cloudflare Access 登录，实际回跳 `https://karuyomi.wybxc.cc/api/bootstrap`；页面返回配置的本人邮箱、非空 subject、expiresAt 与 `stage=p0`。这一项证明当时生产正向登录及 bootstrap，未导出登录 Cookie/JWT。当时线上响应为旧部署 `protocolVersion=1`，不能代替当前 v4 / protocolVersion 2 的正向验收；Source 动态请求、会话过期/恢复与 Native 登录另验。历史匿名拦截及未登录状态的记录保留其当时范围。

## 历史部署与匿名边界

2026-11-03 已成功部署 `https://karuyomi.wybxc.cc`，Cloudflare Worker version 为 `0332ef7a-3d49-47c1-ac41-edbed49bd7fe`。云端 D1 的两次迁移均通过，e350 产物已 remote 注册。匿名检查得到 `/` 200、`/runtime/host.js` 200，`/runtime/host.html` 307 规范化到公开 `/runtime/host`；Safari 已实际渲染 Flutter 书架与三个导航页签。

Access 本人策略覆盖 `/api` 和 `/api/*`。匿名 `/api`、`/api/bootstrap` 与私有 `/api/extensions/artifacts/<hash>` 均返回 302 到 `wybxc.cloudflareaccess.com` 登录，保持 private/no-store。当时只验证了公开入口与匿名拦截。后续生产正向 bootstrap 已单独验收；私有产物交付属于已移除的历史架构，会话失效与恢复仍未验收。

## 自动化 TypeScript 迁移

16 个自有 Python 脚本及测试已全部迁为严格 TypeScript；CI 内嵌 Python 已移除，Python/venv/Ruff 不再是自有自动化依赖。Java oracle/编译器适配和平台构建配置保留原语言。依赖方向见 [TOOLING](TOOLING.md)：工具不反向导入 CLI，通用层不依赖领域，产品不导入工具；API 原有类型循环已提取到 `env.ts`，Native 资源由顶层组装。

固定 Node 24.15.0 下已通过全库 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 与 `pnpm build`。dependency-cruiser 覆盖 117 个模块、442 条依赖，无循环、越层或未解析导入；平台提供的 `cloudflare:workers` 按其环境解析。真实上游计划 CLI 发现 1,448 包，只生成忽略目录中的计划，未因此启动初次全量。CI 环境的流水线测试还实际验证了 SIGINT/SIGTERM 进程树停止后才释放 checkpoint 锁。

迁移提交 `8ad2362` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41606164124) 已全部通过。首次固定 checkout 真实代表构建中，Arknights Comics 原版 Gradle 编译通过，但分阶段宿主 javac 漏掉 HTTP v2 的 `HttpBodySource`，AOT 尚未进入 TeaVM。现已补齐 bootstrap 编译输入，新增真实 javac 依赖回归，并用实际 Maven classpath 编译正式桥四个类通过。该失败属于宿主编译输入，不是 Source 或原始 JAR；不能用上述检查通过替代完整 AOT 验收。

修复提交 `1bfc97f` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41610334065) 已全部通过。固定该提交的独立 clone 与三个上游 pin 后，Arknights Comics、MangaDraft 均完成原版 Gradle → TeaVM AOT → gzip 完整性检查，并在 Codex 内置浏览器 Chromium 156 通过正式 `verify-build.ts --serve`：实际下载/解压、Worker `hostInit/hostLoad`、IndexedDB 与清单 Source ID 一致，未发生 Source 网络请求。两包对应报告为 `browser_verified` / `runtimeReady=true`，在线兼容仍为 `not_tested`；其他未实测构建继续保持 `compiled_unverified`。

最终固定提交 `022d828` 的两包均重新构建，并对新清单与新字节重新通过同一内置浏览器 gate；不复用 `1bfc97f` 的验收报告。[该提交 CI](https://github.com/Wybxc/karuyomi/actions/runs/41614236181) 全部通过。

| `022d828` 代表构建     | 原始 JavaScript | 唯一 gzip | Source ID             |
| ---------------------- | --------------: | --------: | --------------------- |
| Arknights Comics 1.6.2 |     1,839,808 B | 592,989 B | `5973713386239249589` |
| MangaDraft 1.6.2       |     3,814,317 B | 800,371 B | `6866320578550428692` |

完整冻结计划发现 1,448 包；两包代表快照保留完整 catalog，尚未 finalize baseline。确认两包最新快照后，已从固定 `022d828` 独立 clone 启动本地剩余 1,446 包的单并发全量，首个新包已 built，supervisor 与实际 builder 均确认运行。它逐包保存交付结果，全部尝试结束后才产生完整候选；不自动部署或提前提交 checkpoint。计划、checkpoint、产物和原始报告均留在忽略目录，不能据此声称全量发布、在线阅读或真机验收已完成。

## CI 凭据权限

[Actions 权限验证](https://github.com/Wybxc/karuyomi/actions/runs/41605483397) 已成功使用仓库 secrets：更新预先建立的隔离 Worker `karuyomi-ci-permission-check`、上传一份唯一 Static Asset、创建 D1 并写入/读取标记，以及创建唯一随机子域名路由。最后删除临时路由和 D1，并将无公开地址的隔离 Worker 恢复为空白配置；生产应用和数据库未修改。

早期探测误用创建/删除 Worker，超出了正常部署所需的 Editor 权限。Cloudflare 当前 Editor 只能编辑已有 Worker，因此检查改为现有隔离 Worker；不要求给 CI 增加 Admin。该记录证明部署所需权限，不证明当前扩展快照已部署或生产 Access 登录通过。定时增量工作流在本地 baseline 完成前继续停用。

## 静态分发分项

首发 v6 的[六材料完整候选](verification/aot-current-pilot.md#六材料完整候选)已作为 0.1.0 部署。线上 index/state 与候选一致，`bootstrap.complete=true`；37 条匿名路径与四包完整性验证见[首发记录](verification/first-web-release.md)。扩展增量 CI 继续停用，直到有与工作流运行时匹配的生产基线。

历史 v4 三包生产快照及匿名交付见[v4 记录](verification/v4-production.md)。以下 `022d828` 两包部署和政策也保留其历史状态。

固定 `022d828` 的两包代表快照已部署到 `https://karuyomi.wybxc.cc`，Worker version 为 `1d434d1b-7e30-4668-b458-350e486f3b3d`，快照 revision 为 `22378bbcb89d40f5a0397c5098310072`。生产 D1 `0002` 迁移已成功；公开 index/state 字节与本地候选一致，两个 gzip 的 MIME、无 HTTP Content-Encoding、immutable 缓存与编码/原文双 SHA 均通过实际匿名下载验证。前一 `1bfc97f` 的两个清单和 gzip 地址均已实际返回 404，确认当前快照只保留最新版本。六份共享材料的长度/摘要通过，未知扩展和 Native 内置资源路径返回 404，匿名 `/api/bootstrap` 仍跳转到原 Access 团队。bootstrap 尚不完整，不能启用初次全量 CI；当时只有匿名拦截证据，后续生产登录分项见上文。

注册 CLI 已改为只校验当前 index/manifest 与材料元数据，不读取 bundle 或重复计算摘要；原 `--artifacts` 参数已移除。锁定 Wrangler 的标准 pnpm 补丁修复 D1 `--file --json` 夹带上传进度的问题，仍保留严格 JSON 解析和 SQL 失败拒绝。本地真实文件写入/查询/错误 SQL、30 项政策回归与 13 项真实 workerd 门均通过；修复后的正式远端同步也通过：当时两包只继承 MangaDraft 原有 `www.mangadraft.com` 策略，Arknights 保持未授权。线上快照确认后，本地 checkpoint 已保存，首次全量标记仍为 false。

最新静态交付代码已覆盖：严格 TS/Dart 当前索引、gzip 编码/原文字节各一次传输摘要、有界解压与取消；资源组装只复制当前索引可达文件，拒绝混合 index/state、损坏 gzip 与显式缺失快照。流水线离线回归包含源码/依赖/host 指纹、同失败不重试、扫描失败保留成功、运行时不匹配排除、删除退役、首次本地初始化、checkpoint 锁、真实进程树信号取消，以及远端确认后才提交状态。

真实本地 workerd + D1 + Static Assets 门验证了公开索引/清单/gzip 不进入入口 Worker、gzip MIME 且无 HTTP Content-Encoding、匿名静态下载、缺失扩展 404、应用 shell 与控制页规范化、移除的 API 返回 404、RS256/AUD/host 拒绝、元数据事务回滚，以及部署后只继承既有包的明确域名政策。新包仍未授权，退役包政策删除。此次夹具是受控小脚本，尚未代替当前真实 TeaVM AOT 初始化或生产 Access 验收。正式入口见 [API 回归说明](../apps/api/test/README.md)。

## P0-A 真实构建与 Web 初始化

2026-11-03，TypeScript 迁移后的 6 份共享材料已通过实际 workerd 检查：摘要、长度、JavaScript/WASM MIME 和 public immutable 缓存头正确。逐包 AOT 输出唯一 gzip bundle；D1 仅注册网络授权元数据，静态材料按受信 host catalog 核对。原型不保兼容，旧桥副本与旧 raw 恢复路径已移除；旧固定宿主全量队列已停止，需以当前宿主身份重建。gzip 恢复回归覆盖编码/原文双摘要、长度上界、截断、尾随和拼接流。当时两包真实 AOT 与线上传输证据见上文；全量 baseline 和旧本地 bundle 缓存清理仍待验证，后续正式 Web 版本更新分项见[独立记录](verification/extension-version-web.md)。正式契约见[共享材料](RUNTIME-MATERIALS.md)与[发布说明](EXTENSIONS.md)。

同一 `1bfc97f` Arknights Comics 原版扩展已在 Codex 内置浏览器 Chromium 156 经产品 Worker、隔离 D1、真实 workerd 和 HTTP v2 完成在线元数据检查：热门 17 项，搜索首个标题返回同名 1 项，详情成功，章节 3 项，真实章节 pages 返回 51 页；latest 按 `supportsLatest=false` 明确跳过。网络使用显式 `arknights.global` 白名单及真实 RS256 测试身份，不是生产 Access。未请求图片字节，未修改 Source/JAR，也未据此判定图片、Cache/JVM 等价或完整阅读通过。

真实 Flutter + flutter_inappwebview 6.1.5 + iOS 26.4 Simulator 已在本地受信 HTTPS 通过内置运行时验证：控制页真实 307 从 `/runtime/host.html` 到 `/runtime/host`；document-start 内置 host 与 Blob Worker 完成 Arknights Comics 的 `hostInit` / `hostLoad`，返回 Source `5973713386239249589`，IndexedDB 可用，API 携带同源 HttpOnly cookie。服务器故意将远端 host.js、worker.js 和材料路径设为 503，这些路径请求数仍为 0。旧 cache/file 构建明确拒绝并提示升级扩展；同长度篡改 AOT 被 `integrity_error` 拦截，重建容器后正常恢复。实测同时修复 WK 返回 HTTP status `200.0` 的有限整数转换边界，并加入负例回归。正式 app 代码、资源校验及 iOS CocoaPods 集成入库。

这项验证覆盖真实 Flutter 原生控制容器和本地 cookie 恢复，不是 Cloudflare Access 正向会话、物理 iPhone、图片通道或 Source 在线语义验收。

历史导入校验了 release9 研究交付；当前正式 Java 与桥已内化为项目源码，真正上游通过 submodule 和补丁追踪，依赖、原 JAR、ZIP 和大产物不入库。原 MangaDraft JAR SHA-256 为 `81d456c80449fc205e50332ff281c0b8ee20e584f7e5670ccd3f79abb71dfa86`，基线和产品构建前后保持一致。

| 项目                | 证据                                                        | 能证明的范围                                                                                                                         |
| ------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 冻结宿主基线        | [历史构建摘要](verification/runtime-evidence.md#构建与输入) | 未修改 release9 宿主真实编译；没有生成可安装产品清单                                                                                 |
| 产品宿主            | [产品构建摘要](verification/runtime-evidence.md#构建与输入) | 新 `hostInvoke` ABI、完整 DTO、显式引用覆盖层真实编译；bundle SHA `209ad02ba02eae99147502799c08e1aac0c1c7bc29906aa3d60e99174b1b9f22` |
| Chromium 156 初始化 | 同上摘要的浏览器初始化分项                                  | 清单/hash 检查后实际执行 `hostInit` / `hostLoad`，返回 MangaDraft ID `6866320578550428692`；缺章节引用经 Java 失败回调返回结构化错误 |
| DTO JVM oracle      | `tools/teavm/HostDtoTest.java`                              | 六项操作使用的完整漫画/章节/页面字段、长列表不截断、分页参数、顺序、memo、Long 精度及显式引用验证                                    |

`popular/latest/search/details/chapters/pages` 已实现 Java 调用边界。新增 Chromium 156 + 产品 JS + 真实 workerd/D1/R2/v1 HTTP bridge + RS256 测试签名的在线探针中，热门/最新/搜索请求均为 HTTP 200 并返回 20 项完整 DTO；原 JAR 字节码已确认：`j.getSearchManga` 将非 URL 查询原样交给 `r.i`，后者只构造过滤/分页参数，未将文本关键词加入 catalog 请求；观察到的不筛选行为来自冻结 Source 自身，不是 Host ABI 漏参，不能将返回列表判定为搜索匹配。详情/章节访问真实 `/manga/dragon-ball-kakumei` 后被源站 302 到 `/bot-verification`，最终返回 Human Verification；Java 明确返回 `source_error: Unable to find project script`，这是源站挑战而非 ABI 加载错误。探针没有伪造章节或 pages 引用，pages 尚未实测。当前仍未判定六项在线 Source 等价。控制 `ready` 始终为 `sourceReady: false`；真实初始化成功的 `open` 才返回 session。Source ID 与清单不符、hash/MIME/预算错误或登录 HTML 不得进入可用会话。远程脚本、非默认 filters/preferences 和产品图片调用仍明确不支持。

```sh
git submodule update --init --recursive
pnpm teavm:prepare --android
pnpm teavm:check
pnpm teavm:build --descriptor PATH_TO_DESCRIPTOR --output PATH_TO_OUTPUT
pnpm --filter @karuyomi/runtime-host build
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

上述命令仅适用于 [f623a82 及此前源码](https://github.com/Wybxc/karuyomi/tree/f623a82)；本轮已删除独立 Source 探针，不作为当前复验命令。当时打开脚本输出的 localhost 页面运行正式 Source 集成回归。它使用真实 IndexedDB、产品 Worker 与 HTTP bridge、隔离 workerd/D1/Static Assets 和 RS256 测试签名；不修改产品鉴权入口。复验步骤见 [集成说明](../apps/api/test/source-metadata-probe.md)，实测状态见 [摘要](verification/runtime-evidence.md)。初始化通过不等于文件/HTTP Cache 重启、升级与取消语义已完成回归。

## P0-B 独立字节与错误探针

[字节机制摘要](verification/runtime-evidence.md) 记录 Chromium 156 上实际编译的 TeaVM JSO 探针：空字节、`00/ff`、全部 256 值、含 NUL/emoji 的 UTF-8、带偏移视图和 64 KiB 随机字节经 `Uint8Array → byte[] → Uint8Array` 显式复制后逐字节一致。它同时验证 64 KiB 限额、复制不别名、retained Java 引用清除、fiber 等待/IOException 恢复、模拟 supplier 取消后无遗留/迟到回调，以及主线程/Worker 双向转移后的发送方 ArrayBuffer 脱离。这里只保留复制与取消的关键门槛；桌面机制结果不外推为手机性能、零拷贝或总堆上限。

[Zstd 错误摘要](verification/runtime-evidence.md) 对照实际编译的原版和产品 `Bridge.zstd`。两者对真实 WASM 无效压缩流都返回 `Truncated Zstd frame`；显式注入 rejected host Promise 时，原版生成代码因局部变量名碰撞抛出 `TypeError` 并等待超时，产品实现改用 `failureReason` 后恢复 Java RuntimeException。历史原版对照保留在本地研究归档。

上面的精简文档记录历史机制证据；正式产品与发布回归需要独立测试，不能依赖临时工程存在。

产品代码现已加入 [HTTP v2](HTTP-BRIDGE.md)：严格帧、Worker 按需响应、JS operation/generation handle、Java Okio Source 与有界上传 Sink。新增协议 38 项及 JS transport 9 项测试；完整 TypeScript 套件 192 项通过。Java 完整 javac 与 `tools/teavm/HttpBodyTest.java` 的 1,051 项断言通过，包括 64 MiB 分块读取与 8 MiB 上传上限（`pnpm teavm:check` 同时运行 DTO 与 body oracle）。真实 TeaVM 0.16 编译 JS 在 Node 的模拟六函数 supplier 下，验证 131,079 字节 GET/POST（00/ff、64 KiB 分块）、空 POST、pending-read 取消、超时、超请求块与 EOF 长度错共七例，handle 最终归零；这仍不是实际 HTTP、浏览器或 Access 验收。

当前构建、注册清单、Java、Worker 和 API 只维护 HTTP v2，旧 v1 传输分支已删除。Java 重新经过真实 TeaVM 编译后的 18 例模拟 supplier 回归，覆盖 GET/POST、空正文、取消/超时、受控重试及错误分类；这些仍是模拟环境证据。

`pnpm test:http-bridge` 已通过真实 workerd 与受控 HTTP origin 的 24 项检查：夹具真正发送 gzip（3,164 字节）与 Brotli（657 字节），解码后均为 131,089 字节且 SHA-256 一致；覆盖 200/206/403、HEAD、重复 Cookie、手动重定向、流式 POST、早响应仍验证上传 END，以及消费取消、请求取消和超时关闭 origin。分项实际验证 204/205/304 无正文与 304 表示元数据、显式 Range 的精确 19 字节返回、Unicode/重复 urlencoded 字段及跨 64 KiB 的 multipart 文件。表单由标准 Request/FormData codec 生成和解析；origin 在消费者已读到正确前缀后真实截断，bridge 返回 `upstream_body_error` 而非成功 END。入口通过固定 Undici 直连用户 Worker socket，origin 经明确启用 signal flag 的辅助 Worker 和原生 external HTTP proxy；没有修改生产入口。四个主动取消场景均使用 30 秒请求期限、1 秒取消窗口，本次本地取消及 origin 关闭用时约 12–22 毫秒；持续发送时使用普通 body cancel / AbortSignal，首块后 idle 的场景明确使用 TCP reset，不能把本地 destroy 当成远端已取消。该门已纳入 `pnpm check`，合同见 [HTTP bridge](HTTP-BRIDGE.md)。提交 `7e57a74` 的[项目 CI](https://github.com/Wybxc/karuyomi/actions/runs/41760712045) 已全部通过，包括通用检查、Flutter、构建与本地 D1。它不涉及实际 Source、生产 Access 或 CacheInterceptor；原 Source/cache 同版对照和图片/移动内存链路仍需验收，P0-B 尚未通过。上面的部署版本属于旧版本历史记录，当前代码尚不能据此声称已部署或通过生产 Access 正向会话。

共享 CacheInterceptor 的截断/半途取消另有[实际 TeaVM 与原 JVM 对照](verification/cache-http-failures.md)，与上述模拟 supplier、独立 HTTP bridge 门分别计证据；生产网络取消仍未通过。

正式 `be5c3ed` Flutter Web 主入口已完成原版 Arknights 1.6.2 图片获取中退出与恢复的限定分项：真实未完成 HTTPS 响应转发 8192 B 后暂停，正式 Reader 返回触发取消，约 12 毫秒后上游 aborted/close，早于 Source 原 10 秒期限；Java 取消、章节关闭、首图及原取消页恢复可见与保存均确认。最终 Worker 终止、308/308 遥测检查点与正常服务关闭分别取得；旧轮的超时、400 和缺失检查点均保留，见[Source 图片取消证据](verification/source-cancellation-web.md)。这一门使用隔离 RS256、loopback HTTP/1 与真实 Source HTTPS，不是生产 Access、HTTP/2/3、Native、全部图片阶段或进程/GPU 峰值验收。

## Web 产品图片通道

2026-11-03，当时 host ABI `karuyomi-source-host-v2` 的原版 Arknights Comics 1.6.2 已完成实际 AOT，并在 Codex 内置浏览器 Chromium 156 通过正式 Worker 初始化门：IndexedDB 可用、清单 Source ID 一致。build 为 `ext-en.arknightscomics-4d57964aa8f40e8728f0fb701b2fa3de`，bundle SHA-256 为 `7f47a06dfb8002b9f0b70713d39588091ba909f4477eadb6288fb7382c9ee93f`。这不是已部署的 ABI v1 两包快照，也不能与仍运行的固定 v1 首次全量混装；它不代表后续 v3 控制协议已通过实际运行验收。

本地隔离 D1、签名测试 JWT 和真实 workerd 的 Source 门完成热门 17 项、标题搜索同名 1 项、详情、3 个章节及 DREAM 的 51 页列表；latest 依源声明跳过。网络政策显式限定 `arknights.global` 与元数据确认的 `webusstatic.yo-star.com`，未扩展生产政策。原 Page 对象由 Java 会话保存，图片经原 Source 的 `getImageUrl/getImage` 与 HTTP v2 进入产品图片 sink，没有读取原图 URL 绕过 Source。

| 实际章节页 | 已处理编码字节 | 浏览器解码尺寸 | 显示与释放                                     |
| ---------- | -------------- | -------------- | ---------------------------------------------- |
| 第 1 页    | 39,602 B，JPEG | 1200 × 1691    | decode、尺寸一致、重复释放及 Blob URL 撤销通过 |
| 第 26 页   | 719,916 B，PNG | 1200 × 1691    | 同上                                           |
| 第 51 页   | 718,931 B，PNG | 1200 × 1691    | 同上                                           |

实际 Flutter Web release 构建在同一边界经“浏览→扩展→Source→漫画详情→DREAM”进入 ReaderScreen，真实首图、单双页翻页、缩放/重置、连续阅读模式切换与放大层打开/关闭通过交互检查；模式切换保留逻辑页，连续下一页可前进至第 3 页。它是本地产品链路，不是 Cloudflare Access 正向会话、完整章逐页验收、下一章/进度持久化或手机性能。

正式回归还覆盖：保留原始/子类 Page、cacheless/progress 与本地 XOR 拦截器的 JVM 对照；双完成后才公开资源；单块 ACK；取消与迟到发布、解码预算 tombstone、Java 退出后解锁；资源公开后迟到 cancel/close 不撤销已返回 Blob；详情退出动画期间迟到 pages 不重开 Reader。真实 Flutter 退出还暴露了两端 mock 掩盖的应答漂移，现关闭会话统一为 `{closed:true}`，取消/释放为 `{released:true}`，公开 API→Worker 延迟确认与浏览器 Source 门均明确检查相应 ACK。历史测试方法见 [Source 门](../apps/api/test/source-metadata-probe.md)。

`pnpm check`、`pnpm flutter:check` 与产品 Web/API dry-run 构建通过；Java 图片 oracle 对 seed 和正式 HttpSource 两套签名均通过。该历史输入的 Web 终端有 encoded/pixel/resource 总预算、头部预检与实际 decode；随后内部 Bitmap/ImageDecoder 的二进制与合计账本进展见下节。不能据此声称图片解密/重排、动画/超长图、进程/GPU 合计峰值、Native 受管文件或 P0 已通过。

## 长图 codec 机制（历史，候选已删除）

2026-11-05，未采用的候选源码、专属构建与测试工具已在 `e11b014` 删除。以下结果只记录历史机制，不表示当前仍维护或打包这套实现；当前由 Flutter/UI 直接解码。历史源码与构建说明见固定版本的 [codec README](https://github.com/Wybxc/karuyomi/blob/a2251a6/runtime/image-codec/README.md)。

2026-11-04，官方 Emscripten 5.0.7 macOS arm64 SDK 的 libspng 0.7.3 对 1080×20000 / 1080×40000 合成 RGBA8 非交错 PNG，Node 四项与内置 Chromium 五项通过；libjpeg-turbo 3.2.1 对 720×30000 / 720×60000 合成 baseline JPEG，Node 九项和浏览器六项通过。Node PNG 完整流对照原始 RGBA，JPEG 原尺寸与 1/2、1/4 完整流对照独立解码基准；Web 只核首/中/末区域且实际可见，不声称全流或缩放验收。

64 KiB 单块 ACK 背压、首块后协作取消与截尾拒绝分测通过，JPEG progressive 在解码前拒绝；协作终态 C 账本归零。观察到非共享 WASM heap 为 16 MiB，JPEG 最大计量 payload 为 1,959,276 B，不等同 RSS/GPU；强制 terminate 只证明 100 ms 窗无后续消息，没有测得 heap 回收。服务均已 exit=0、端口释放。官方 SDK 准备器及无大型下载的归档/HTTP/进程清理回归已接工程检查。详情、历史工具链偏差和复验命令见[长图 codec 证据](verification/long-image-codec.md)及固定版本的 [SDK 操作](https://github.com/Wybxc/karuyomi/blob/a2251a6/runtime/image-codec/README.md)。这些是独立机制，Source、随机区域/LOD、Flutter/Native 与真实设备峰值待验，正式 16 Mi 像素准入尚未调整。

正式源码也已在同一 macOS arm64 官方 SDK 下完成独立构建与 Node 19 项回归：四幅合成 PNG/JPEG 长图的完整流及首/中/末摘要一致，heap 均为 16 MiB，最大计量 payload 为 3,645,862 B，close 后分配数与 payload 均归零。两次使用独立构建缓存，第二次注入无效 CFLAGS/LDFLAGS/EMCC_CFLAGS/CMAKE_TOOLCHAIN_FILE，生成的四个 JS/WASM 文件字节相同；仅证明同主机/同 SDK 重建。新轮 80 ms 暂停只测同线程 pull，JPEG 缩放只核尺寸和字节数；新产物的独立 Worker、浏览器、共享材料、Source 与终端均待接入。正式命令、输入身份及覆盖范围见[正式 codec 验收](verification/long-image-codec.md#正式源码构建与-node-验收)。无大型 SDK 下载的 53 项运行库/构建器/工具链回归、完整 macOS 格式与通用 `pnpm check` 已通过。

随后当前源码增加有界 PNG encoder 和独立 codec Worker：真实 Node 门扩为 24 项，新增条带编码由 Sharp 全像素对照。正式 catalog/client/VerifiedLoader/Blob 模块与 WASM 已在 Codex 内置 Chromium 156 通过 11 项：四幅长图加最大高熵条带共 590 个基础 tile 的 PNG 字节/几何匹配独立 Node 实例，同一 Worker 内两个独立 WASM 实例；250 ms pull 暂停、逐块 ACK、首片/扣住首 ACK/start post 后取消、PNG/JPEG 截尾失效及错误后恢复通过。最大 DATA 为 64 KiB，观测最大活动 Worker 为 1，全部终态之后 terminate 再释放模块，最终为零；25 ms 无迟到消息只证明该观察窗，不证明物理 heap 或进程/GPU 归零。详细身份、C 计量、原始报告 SHA 和复验命令见[正式 Worker 证据](verification/long-image-codec.md)。Web Static Assets / Native host 内置材料接线及去重已有构建回归，Native 执行、Source/Protobuf/Reader、tile 缓存/LOD 与真机峰值仍未验，产品 16 Mi 像素门保持原状态。

## 内部 graphics 二进制与预算

2026-11-03，Bitmap、两套 ImageDecoder 和字体输入已将整图正文改为不超过 64 KiB 的 JSO 字节块，小 JSON 只传控制与 handle。尺寸查询先用锁定的 image-dimensions 解析至多 1 MiB 头部，不为 bounds 完整解码。账本分别覆盖可见 payload、surface、decoder/Frame、字体、临时副本和不可中断任务的工作预留；Source 持有的 Bitmap/decoder/Frame 不因普通调用结束被扫描删除，取消与迟到结果保留相应所有权直到任务真正退出。

新增流式 Java oracle 与原 DTO/HTTP/两套图片 oracle、16 个正式图形 Java 类 javac、113 项 runtime-host 测试及严格类型检查通过。Codex 内置浏览器 Chromium 156 的真实 Canvas 门通过；TeaVM 0.16.0 实际 Java→JSO→Canvas oracle 通过 131,079 字节分块往返、同步/异步 Java 异常、fiber bounds、Bitmap pixels/raw/PNG、region sample 别名与 Java Frame lease，显式释放后图形账本归零。独立 harness 初次遗漏正式构建器的 Android 重复类裁剪曾报 Stub，修正 harness 后复跑通过，未改扩展业务代码或原始 JAR。

预算合同、范围和复验入口见 [图片资源内部图形桥](IMAGE-RESOURCES.md#source-内部图形桥)。这是图形桥和受控 codec 的分项证据，尚需新 host 输入的真实 AOT、处理/解密源、移动环境及实际进程/GPU 峰值。Cache 与普通 File 的二进制正文、事务和各自预算已分阶段通过机制门，合计 namespace 预算及产品环境仍待汇合；图形账本不代表整个 Worker 的硬上限。Bitmap 自然回收和活 owner 的独立证据见[生命周期记录](verification/bitmap-lifetime-runtime.md)。

## F3 iOS 模拟器 HTTPS 机制

[实测摘要](verification/runtime-evidence.md) 记录 iOS 26.4 Simulator / Xcode SDK 27.2 在本地受信 HTTPS 下的机制验证：256 KiB、4 MiB、16 MiB 二进制，Worker 处理生成的 PNG，以及 16 MiB 下载启动后立即取消。正文走 `Worker → transferable ArrayBuffer → Blob URL → WKWebView.startDownload → WKDownloadDelegate → 受管临时文件`，只用小型控制消息；独立原生摘要、PNG 尺寸、发送方脱离、文件/Blob 释放与最终空资源目录检查通过。

iOS 临时独立工程与原始本地输出已归档到被忽略的研究目录，仓库只保留摘要。该次实测使用专用模拟器及临时受信 localhost 证书，没有跳过系统 TLS 校验。当时 `flutter_inappwebview` 未直接暴露所需 `startDownload` 受管文件链路，尚无产品薄扩展；这份历史机制证据不是 Flutter 产品图片桥，也不是物理 iPhone、生产 HTTPS/Access、任意阶段取消、首图性能或进程/GPU 峰值验收。

## Native 受管文件产品机制

2026-11-03 已接入正式 NativePlatformRuntime、资源所有权表、iOS WKDownload 文件桥与 Android 固定六槽 ArrayBuffer sink。iOS 26.4 Simulator / Xcode SDK 27.2 在正常受信 localhost HTTPS 下，实际 Flutter Headless 握手、唯一 token 绑定、307 控制页规范化、受控 Blob 下载、1,175 字节摘要、Flutter 256×128 解码及取消/释放/目录清理通过。Swift XCTest 11 项、Flutter 45 项、SourceRuntime 23 项和 Native opt-in/图片 manager 的 TypeScript 15 项通过；analyze 无问题，正式产品 iOS 模拟器构建成功。Android 嵌入脚本在该历史阶段仅通过 Node MessagePort 回归；后续实际 WebView 六槽、SQLite 进程重启及双端 readiness 差异见[Native 依赖与运行记录](verification/native-dependencies.md)。

完整合同、工具来源、期限/tombstone/配额和复验入口见 [Native 图片文件](NATIVE-IMAGE-FILES.md)。这证明产品容器与文件交接机制，尚非原版 Source→Native Reader、物理 iPhone、生产 Access、后台恢复或合计峰值验收。绑定与下载回调未确认停止时不会声称成功清理或归还预算。

固定 `a15c030` 的独立工作树进一步完成 iOS 原 Source 文件门：真实 CatalogController/ChapterPageProvider 从 17 项目录进入 3 章/51 页，首、中、末页经原 Source、HTTP v2、WKDownload 和 Flutter 文件解码均为 1200×1691，字节与上游流摘要逐项一致。release 删除文件并撤销所有权；获取中章节关闭、持图容器重建、binding 目录删除和新 generation 重开通过。身份核对与范围见 [原版 Source 分项证据](NATIVE-IMAGE-FILES.md#原版-source-到-native-文件的分项验收)。它仍使用测试身份与模拟器，未证明 Native ReaderScreen 完整交互、生产 Access、真机或峰值。

固定 `d76e8a4` 的新工作树已通过 iOS/Android 正式受管图片机制及真实进程重启的 SQLite 恢复，保留 `5e9e526` 的 iOS interactive 就绪失败及修正依据。iOS 进一步以相同材料的原 xkcd AOT 经正式 CatalogController/ChapterReaderRoute/ReaderScreen 显示两页，实际 frame 后保存末页与完成状态；terminate/launch 后重取原 Source 并恢复。输入是受控 Native 入口与合成 Flutter Pointer，同源受信 localhost HTTPS、隔离 RS256/D1 测试身份。它不证明生产 Access、真机触控、Android Source 或完整主入口日用流程；详细身份与限制见[Native 记录](verification/native-dependencies.md)。

固定 `8eef7b4`（`d76e8a4` 加 `6c2e09c`）的 Android 模拟器进一步通过原 xkcd 正式 ReaderScreen 两页、Source 文字图、显式完成和两次 force-stop 后 SQLite 恢复，最终 route/provider/WebView 退出也通过。修复文件 sink 与 controller 重复销毁 channel 的所有权错误，保留旧失败；最终截图等待正式“本地进度已保存”，与早期 pre-flush 截图分别留证。测试 CA 仅配置在独立 ignored debug App 的 exact localhost，系统 CA 保留，错误 CA/未配置域名均拒绝；不是生产 Access 或真机证据。完整输入、报告与限制见[Native 记录](verification/native-dependencies.md#android-独立-debug-app-的-tlssource-与退出复验)。

## Cache v3 的新材料复验

固定 `31555e8` 的三源新 AOT 已在内置 Chromium 156 通过正式 Source 元数据与图片链：xkcd 两页含原 TextInterceptor 文字图，Arknights 51 页首中末、CuuTruyen 23 页 DRM 引用首中末均解码、释放并关闭会话。输入与完整 EOF 范围见[三源记录](verification/cache-v3-sources.md)；不以此宣称 Cache 命中或取消通过。

同一 Cache 桥及官方 39 组 Worker/suite 字节在 iOS/Android 模拟器均通过 IndexedDB/Web Locks/Worker 机制和最终 dispose，见[移动引擎记录](verification/cache-v3-native.md)。这不替代 Native Java/Source、生产 Access 或真机门。

2026-11-10，首发六材料的正式 [iOS](verification/source-cache-native.md#2026-11-10ios-正式-app-进程退出后复用章节正文) 与 [Android](verification/source-cache-native.md#2026-11-10android-正式-app-强制停止后复用章节正文) App 已通过原 xkcd 章节 HTML 跨进程复用：真实退出再启动，新 generation 显示两页、重取原图，未重请求章节 HTML。iOS 的 WebKit 持久缓存与首次 7,151 B 真实响应摘要相同；Android 清除本地 App 数据后，以同一 D1 账号再次打开同一章，恢复一次完整 HTML 请求。浏览器、生产和真机另验。

## Reader 帧调度修复后的复验

固定 `19b65f5`（`31555e8` 加 `5267181`）的正式 Flutter Web release 已在 Codex 内置 Chromium 156 经主入口完成原 xkcd 两章、显式读完与关标签页重开；首次恢复 3318 末页即显示原文字图，未翻页或诊断补帧。原黑屏失败不覆盖，详见[Web 修复后证据](verification/reader-frame-web.md)。同输入 Android / iOS 模拟器也通过正式 Reader 及真实进程重启，原文字图、已保存 / 已读完与最终清理均已核对，见[Native 修复后证据](verification/reader-frame-native.md)。iOS 早期黑截图仍作为视觉失败保留；终态截图等待实际路由过渡完成，并以 OS / Flutter 两种原图核对。以上不声明生产 Access、Source Cache、真机或浏览器进程恢复。

## 正式扩展更新与 Native 主入口准备

2026-11-04，固定 `be5c3ed` 的正式 Flutter Web 通过官方 Arknights 1.6.1 → 1.6.2 更新：旧版保存 DREAM 第 3 页，新版重新连接后首次继续阅读即显示同一原图和已保存页位；两版 PageList 均为 51 页且摘要一致，同 principal/namespace、不同 Worker/generation，章节会话与最终 Worker 清理确认。当前静态快照旧清单/正文返回 404；独立审查和完整 90/90 检查点见[版本记录](verification/extension-version-web.md)。新版四次 Cache entry 后仍以真实 200 重新写入正文，不能认定正文复用、304、零网络或本地旧 bundle 缓存清理。

同期正式 Native main 成品、62 份 Dart 和内置材料核对一致，正常 TLS、Secure/HttpOnly Cookie 与真实 RS256 Worker 的九项预验通过；当时 CUA 无法连接 Simulator，App 未安装/启动，UI 保持 `not_run` / `passed=false`。测试服务、模拟器和工具启动的 Xcode 已清理，见[Native 主入口记录](verification/native-main-entry.md)。

2026-11-10，固定 `426536d` 的正式 iOS 模拟器通过 [xkcd 1.6.1 同版本 AOT 构建替换](verification/extension-version-native.md)：同一 HTTPS/D1 切换静态目录并经 UI 明确确认后，运行时扩展代码缓存只留新构建，新进程首次书架续读即显示真实第 2 页。独立四阶段 API 快照显示只确认了账户安装项，无附带业务状态变化。Native 上游版本升级、Android 换版、真机、生产 Access 和换版后 Source HTTP Cache 正文复用另验。

## UI 图片职责与分片选型

2026-11-04 当前原型已将 Source 图片交付统一为不透明编码资源；MIME、尺寸、EXIF、完整解码与分片决策移至 UI，Flutter 从实际显示所用 ImageStream 学习尺寸。旧 host 编码页/分片控制已移除，历史证据保持原输入；独立分片库仅候选，退出默认构建与 Web/Native 打包。工程检查、所有权边界与限制见[本轮记录](verification/ui-image-boundary.md)。候选算法尚无相对 Flutter 直接解码或平台区域解码的同条件真机性能依据，下一步先建立 UI 直接解码基线；不能用有界缓冲、WASM heap 或正确性证明性能优越。

阅读外观与输入预设沿用正式设置确认链路，协议与真实 D1、受控数据/组件以及实际平台证据分别记录，见[本轮设置记录](verification/reader-appearance.md)。

完整显示/适宽/适高与原图二维位置、视口锚沿同一正式设置和进度链路实现，协议、真实 D1、受控客户端及平台门分别见[适配记录](verification/reader-fit.md)。

首发六材料 Android 模拟器的[真实阅读旋转与回前台](verification/reader-fit.md#2026-11-10android-横屏控件与原图位置)已复验：短窗口保留图片和独立控件滚动，旋转前后的原图锚及最远进度保持，主动翻页仍可确认。真机另验。

同步裁白已接入同一正式设置链路，真实 PNG 的 Flutter 解码与默认 Reader 路径、资源所有权及独立平台限制见[裁白记录](verification/reader-crop.md)。

## 尚未通过的门槛

- 更多代表源的生产读图、阅读中 Access 失效后的恢复，以及 Native 在生产 Access 下的登录、读写和续读。[首发 Web xkcd](verification/first-web-release.md#实际-web-验收)已通过真实 Access、收藏、读图和续读；[隔离 Native 可见登录及阅读恢复](verification/native-main-entry.md#native-可见-access-回跳)使用本地身份提供方。
- 更广 Source 的 Web/Native 冷热 Cache、真实 Source 截断 / 取消、其它平台及上游版本变化后的 HTTP Cache 正文复用、普通文件、Native 上游版本升级及带实际 Source 缓存负载的往返换身份；xkcd Web 与双端 Native 元数据 fresh Cache 及实际容器重建后的复用已单独通过，iOS 和 Android 已另验原 xkcd 章节 HTML 跨 App 进程复用，浏览器进程重启仍待验。Cache 跨目录 namespace 39 组及受控 ABI 组合存储/manager 切换不能替代这些剩余产品门。Web 正式原 Source 的身份 A→B→A、双端模拟器阅读中 A→B、304 后正文复用与上述扩展更新续读分别保留其实际范围。
- 正式 Native 主入口人工操作、后台恢复与更多原 Source 的 Native 验收；原处理源重复/取消及更多真实解密源覆盖。
- 3–5 个未修改原版源完整章/下一章、物理设备触控、超长图、移动首图与合计峰值。
- 自定义封面的 Web↔Native 读回、生产 Cookie/Access、并发和丢响应恢复、服务端重启、生产私有 bucket/部署与远端清理；独立 Web 与 iOS、Android 模拟器的顺序往返和新进程读回已通过。
- P1 完整书架/分类/设置和日用流程、P2 同步、P3 用户扩展/迁移、P4 覆盖与优化；已有本地进度分项不能替代完整 P1。

CI 已配置统一检查，远端运行结果需由对应提交确认。以上工程与探针证据不表示 P0 或后续阶段通过。
