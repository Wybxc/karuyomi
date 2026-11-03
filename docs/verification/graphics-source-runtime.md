# 有界图形宿主的真实 Source 分项

2026-11-03 至 04，固定主仓库 `15a3900f63f0023a491414e08cd040c0772f71ce`、扩展源码 `efa93f5a3537856fe830450bbe33f69d21d28167`。工具链/原 JAR 与 Source 业务源码未修改。新材料包含二进制有界 graphics 与 Worker lifetime Cache editor；不包含后续正在实现的 Cache 正文分块。

host 输入指纹 `5d83479c087a11e609b9b4234312e4647af9d612ea1d72c3113412a061b1a85d`，材料版本 `8c615d89210ff6a9d3d0d2846449da1489c82466c580f22134e3359a70a7728f`。控制身份为 host ABI v3 / protocolVersion 2，HTTP bridgeVersion 2。六包本地 AOT 与 gzip 完整性通过：

| 包           | buildId                                                   | JavaScript 字节 | gzip 字节 |
| ------------ | --------------------------------------------------------- | --------------: | --------: |
| arknights    | `ext-en.arknightscomics-207adfd84cc88f7e00d133a3b6ac8e72` |       1,888,333 |   604,821 |
| cuutruyen    | `ext-vi.cuutruyen-8a40b2fc094034095e3be8ba3b9eba15`       |       2,090,016 |   655,210 |
| littletyrant | `ext-pt.littletyrant-22aa6b9e1b28a9f3cb1ff4b34dcbb6e7`    |       4,282,476 |   880,508 |
| philiascans  | `ext-en.philiascans-7c656b9b517ec8edbe5df6ac6e6d85f7`     |       2,938,209 |   656,575 |
| mangadex     | `ext-all.mangadex-044c1d878e89853644e5a7bc2f3a7943`       |       3,876,531 |   821,995 |
| xkcd         | `ext-all.xkcd-a35d1fb61661593eacafc5ee4818f77a`           |       3,990,290 |   848,177 |

## 实际内置浏览器

Codex 内置浏览器 Chromium 156，正式 host、产品 Worker、隔离 D1、真实 workerd 与 RS256 **测试身份**。公开静态产物按当前材料加载；没有把测试身份称为生产 Access。所有请求使用显式站点白名单。

- Arknights Comics：热门 17 项，标题搜索 1 项，详情与 3 章成功，DREAM 返回 51 页。原 Source 首/中/末页 0/25/50 解码为 1200×1691，分别 39602/719916/718931 字节；释放幂等且 Blob URL 撤销。latest 按 Source 声明跳过。
- CuuTruyen：实际热门、第二页、标题搜索、latest、详情与 175 章成功；Spy x Family 的 Chương 142 返回 23 页，全部含非空 `drm_data`。首/中/末 0/11/22 经原 ImageInterceptor 的 Base64/XOR 映射、BitmapFactory、Canvas 条带重排与 JPEG95 返回，分别为 746910/493881/563725 字节，尺寸 2048×1152、1024×1606、2048×1223。原站 scrambled JPEG 经 `storage-bravo.cuutruyen.net` 正常取回；原 Source 拒绝非 v4 映射，三页成功确认实际走了处理分支。解码、释放和撤销通过。
- Little Tyrant：Worker 初始化与 Source ID 检查成功；`tiraninha.world/wp-admin/admin-ajax.php` 的热门、搜索、latest 均收到真实 403，未取得漫画/章节引用。特殊头/Cookie 与 XOR 图片链未测；不伪造引用或绕过拒绝。
- Philia Scans：Worker 初始化与 Source ID 检查成功；`philiascans.org/api/manga` 三项列表请求均为真实 403。未取得公开章，token、图片解密及重排未测，不绕过 `hasAccess` 或登录/付费检查。

- MangaDex：原包 61 个 Source 初始化并与清单匹配，明确选英文 `2499283573021220255`；热门、搜索、latest 均在约 10 秒后返回结构化 HTTP timeout，没有取得上游 HTTP 状态。未获得真实漫画/章节，后续详情、pages 与动态 MD@Home 图片未测；没有伪造引用、扩张域名政策或把超时写成 403。

- xkcd：原包五语言 Source 初始化成功，英文 `1538249443376436084` 的热门、详情、3318 章及两页列表成功；搜索按原实现返回空列表，latest 明确不支持。第 3319 章直图经原 Source 返回 106037 字节 PNG（607×716），释放和撤销通过；第二页由原 TextInterceptor 生成文字图片时遇到 `java.lang.RuntimeException: Stub!`。该固定身份的图片 gate 因此失败，不能把第一张成功视作完整章节通过；下文另记新文字材料的复验，不修改这份历史身份或 Source。

这只证明上述浏览器元数据、Source 图片分项和失败边界；尚无三至五源全部在线、完整连续阅读、Native、运行中取消、实际进程/GPU 峰值或新 Cache 正文的证据。编译检查报告继续保留 `compiled_unverified`，正式发布验证不会因本文自动提升。

## 复验

冻结 checkout 后安装锁定依赖、准备锁定运行时，从完整输入计划逐包构建，不复用其它 host 身份的产物。正式入口：

```sh
pnpm --filter @karuyomi/runtime-host build
SOURCE_PROBE_ALLOWED_HOSTS=cuutruyen.net,hetcuutruyen.net,storage-bravo.cuutruyen.net,storage-charlie.cuutruyen.net \
SOURCE_PROBE_IMAGES=1 \
SOURCE_PROBE_EVIDENCE=.local/cuutruyen-online.json \
node apps/api/test/source-metadata-probe.ts BUILD/manifest.json BUILD/artifacts
```

多 Source 包通过 `SOURCE_PROBE_SOURCE_ID` 指定清单内的准确 ID；本次 MangaDex 使用英文 ID。用内置浏览器点击 `Run real metadata operations`。探针只记录 header/Cookie 名称、图片 host 和处理 fragment 的计数，不保存 token、Cookie 值或 DRM key。原始报告、构建日志与本次扩展观测入口留在冻结工作树 ignored `.local/p0c/`，文档只保留可复验身份、必要结果与未通过门。

## 新 Cache 材料复验

2026-11-04，另固定主仓库 `b6b5f478f568708273ba7d384e587164309ff999` 与相同三个上游 pin，重新准备工具链、扫描完整计划并仅在本地构建以下两包。host 输入指纹 `e7b0c766c6f50761835c80a4b17bf8820dccaf9697dacd19b12e865e70eb899a`，材料版本 `9eb2f18fff6e404078a3b8ef9f83aac882ba8dad5066bc971d556d9c88115706`；不复用上文旧 Cache 材料的 AOT。

| 包        | buildId                                                   | JavaScript 字节 | gzip 字节 |
| --------- | --------------------------------------------------------- | --------------: | --------: |
| arknights | `ext-en.arknightscomics-f84adfbf3b83d33ef45bdc0284c76718` |       1,899,694 |   607,120 |
| cuutruyen | `ext-vi.cuutruyen-abe419ec0673cb4314f582d92f7e3585`       |       2,100,468 |   656,844 |

Codex 内置浏览器 Chromium 156 使用该固定 checkout 的正式 `source-metadata-probe.ts`，产品 Cache/Worker/HTTP v2、隔离 D1 与测试签名；两个 Source 均重新通过原元数据链和首中末图片。Arknights 仍为 17 项/3 章/51 页，三图字节与尺寸同上；CuuTruyen 仍从真实 Spy x Family 第 142 章取得 23 个 DRM 页，三图处理后的字节/尺寸同上，Blob 释放与撤销通过。正式 probe 的 header/Cookie 名称和 fragment 计数已接入，未保存凭据值。

这证明新 Cache 材料下的两源在线图片链。没有测量这些 Source 的冷/热 Cache 命中计数，不能代替共享 Java 的同版语义对照，也没有新增生产 Access、Native、连续阅读或峰值证据。独立产物/报告位于该 checkout 的忽略目录 `.local/p0c/`；发布状态不自动提升。

## 新文字材料与 xkcd

2026-11-04，固定主仓库 `926b93d78a7360d849813b2d03dd650cd5c34172`，三个上游 pin 与首轮相同。在独立 `text-source-validation` checkout 使用 Node 24.15.0、固定 JDK/Maven、精确锁定的新 npm 依赖重新扫描并仅构建 xkcd。源码闭包仍为 `aa3fa0e42967ce18a35fb3c21b811c3218a35a4a8607cb12bc82f27a54da7f89`。复用旧官方构建的 debug keystore 后，官方 Gradle 重产原 JAR 的 SHA-256 严格保持 `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d`（125470 字节），没有编辑 JAR 或业务源码。

- host 输入指纹：`272b2f84259d7f7e629385394d6bc1671ceb099e2f26ae420b6a4728e62128b7`。
- buildId：`ext-all.xkcd-e2b8a80d2c3d3a9de6cb78b76505c27e`；bundle SHA-256 `75f4356b5ef81156454e106975666d25a132870f9af52de56d4234977040ee6f`，4032407 字节，gzip 851982 字节。
- 材料版本：`6ce41048c205ea29dc6ba076faa2eb63398bd745f9ad864787c21391e9acee37`；graphics SHA-256 `6e7bcba18059cfd8fd85943ad08af6038433f99497931af29e14b92461af598d`。不复用旧文字 stub 材料的 AOT。

Codex 内置浏览器 Chrome 156 经正式 `source-metadata-probe.ts`、产品 host/Worker、隔离 D1、真实 workerd、RS256 测试身份和显式 `xkcd.com,imgs.xkcd.com` 政策执行。明确选中英文 Source `1538249443376436084`；原返回的首章仍为 `3319: Elevators`，没有伪造或替换章节引用。热门/详情、3318 章及两页列表成功，搜索按原实现返回空，latest 不支持。

原 Source 两页均通过：直图 106037 字节 PNG、607×716；第二页经原 TextInterceptor 实际生成 49246 字节 PNG、1000×286。`tachiyomi-lib-textinterceptor` 仅在原拦截器内处理，没有加入网络白名单或发生该主机的外部请求。两次释放均撤销 Blob URL，Page session 关闭且 image gate passed。该证据是 Source 图片解码/资源边界，不是生产 Access 或 Native 验收。

随后以相同 AOT/材料配合固定 `80841b` 的真实 Flutter Web 构建，在正式产品界面选择英文 Source → xkcd → 3319。直图正常显示；切换到 2/2 可清楚看到原 TextInterceptor 生成的标题和完整 alt 文字，阅读进度已保存；下一章进入 3318 正常。本地可见文字截图为 `/tmp/karuyomi-xkcd-text-page.jpg`。此 UI 检查补齐该章实际显示证据，不把 Blob 撤销等同于内部 graphics ledger 归零，也不代表生产 Access 或长期连续阅读已通过。

复验在同一固定树构建 runtime-host 后执行：

```sh
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_IMAGES=1 \
SOURCE_PROBE_EVIDENCE=.local/xkcd-online.json \
node apps/api/test/source-metadata-probe.ts BUILD/manifest.json BUILD/artifacts
```

原始 descriptor、provenance、构建日志和报告保留在该树忽略的 `.local/text-source/`，严格原 JAR 构建使用 `xkcd-original/`。先前 fresh debug keystore 的试构建仅签名 `META-INF/CERT.RSA` 不同，未作为严格对照使用。

该 `926b93d` 身份的内部图形生命周期仍有确定缺口：官方 TextInterceptor 没有 recycle 它创建的 Bitmap；owned Bitmap 无自动回收注册，bridge `teaGraphicsEnd` 只清 byte handles/scratch，surface Map 仍持有画布。因此上述 release/revoke 不能冒称内部 ledger 归零，重复文字页处理、取消和存活 Worker 的内存/64-surface 预算仍待验收。独立 Java/Canvas 场景显式 recycle 后归零的结果见[文字布局记录](text-layout-runtime.md)，不能替代这项实际 Source 门。后续 typed lease 的活 owner、编码pin及真实Java自然回收已通过[独立验证](bitmap-lifetime-runtime.md)，须再固定新材料重建原 Source 复验。

## 新生命周期材料的原 xkcd Source

2026-11-04，固定主仓库 `5148c60185b71624664c45c20162e9322c9ef904`，在独立 `bitmap-source-validation` checkout 按 frozen lockfile 安装依赖并重新构建 xkcd。该身份包含Bitmap回收及二进制文件桥，早于后续 `3a06d5f` Cache reader关闭修复，不能作为该修复的Source复验。三个上游 pin 与前两轮相同，Source 闭包仍为 `aa3fa0e42967ce18a35fb3c21b811c3218a35a4a8607cb12bc82f27a54da7f89`。沿用旧官方构建的 debug keystore，让官方 Gradle 重产原 JAR；SHA-256 严格保持 `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d`（125470 字节），未修改业务源码或 JAR。

- host 输入指纹：`9e76bfb067f192f4b2c13dac68f81f1844530c2b4ce78746b8db8219c6943562`。
- buildId：`ext-all.xkcd-b96033033497e10d554cf94850e5793f`；bundle SHA-256 `a7efb40c8231bcde976321e91b44f88a51e2d6fe0aaba65bc6c6bd0cc10ad800`，4035205 字节，gzip 852513 字节。
- 材料版本：`80c9e303184623dea1b56acdd1c02cac0db522b83fe01f5f68285d7145f395c7`；graphics SHA-256 `230ec744421cc1651194900af006eba06b1659aa9d61de559a54150556e8af75`。没有复用 `926b93d` 的 bundle 或材料。

Codex 内置浏览器 Chrome156 先用未经扩展的正式 `source-metadata-probe.ts`，经过产品 host/Worker、真实 workerd、隔离 D1 与 RS256 测试身份复验。原英文 Source 返回 `3319: Elevators`、3318 章和两页；直图仍为 PNG106037 字节/607×716，原 TextInterceptor 第二页仍为 PNG49246 字节/1000×286。释放、Blob URL 撤销和 Page session 关闭通过；搜索按原 Source 返回0，latest 不支持。网络仍仅允许 `xkcd.com,imgs.xkcd.com`。

另外在 ignored harness 中对同一正式 host/Worker 附加内部账本读取与诊断计数，不改原 Source、JAR、bundle 或已校验共享材料。通过真实 pages 返回的第2页 pageKey 重复 `acquireImage`、解码并 `releaseImage` 共80次，实际新增80个 Java Bitmap lease，没有注入 `recycle`。两次运行均成功跨过64次处理，surface 数处理中多次自然下降，观测峰值均为18。

空闲回收结果如实保留：首轮处理完成后仍有17个 surface/19448000字节 raster reservation；单纯读取账本15010ms没有观测到最终GC，因此该轮“空闲15秒归零”观察失败。第二轮完成后仍有16个 surface/18304000字节，空闲1532ms也未归零。随后仅测试Worker执行每批32768个普通JS对象的有界分配/丢弃，5批后观察到所有图形账本归零，单次413ms；没有调用显式GC API，但这是测试分配压力下的观察，不能称为无压力空闲保证或实际 Source 负载保证。

取消门使用原 TextInterceptor 的实际 `OffscreenCanvas.convertToBlob`，只在测试harness暂缓其真实结果交付。编码等待时账本保留1个 surface/1144000字节 raster，总 reservation68383936字节；发出产品 `cancelImage` 后，在结果放行前继续保留计费。放行后原请求返回 `cancelled`，没有图片发布，graphics handles 为0，总计费降至该未回收 surface 的1144000字节。同一generation随后重新获取文字页成功，Worker没有因本次取消而重建。取消及恢复留下的两个未显式回收 Bitmap 在空闲1532ms仍未回收，后经22批相同有界对象分配观察归零，单次2155ms。

上述字节为bridge内部reservation，并非进程或GPU实测峰值；所有GC延时仅为单次机制观察。取消覆盖受控的真实PNG编码等待阶段，不推广为所有HTTP/解码阶段、所有Source或任意引擎环境。生产Access、长期连续阅读、Native生命周期与真机性能仍须另验。

正式两页复验命令沿用上一节。此次descriptor、provenance、构建日志及原始报告保留在固定树 `.local/bitmap-source/`：`xkcd-online.json`、`xkcd-lifecycle-idle.json`、`xkcd-lifecycle-pressure.json`，诊断服务源为 `lifecycle-probe.ts`。该ignored入口基于同树正式Source服务；观测代码和原生PNG结果gate不进入产品分发。
